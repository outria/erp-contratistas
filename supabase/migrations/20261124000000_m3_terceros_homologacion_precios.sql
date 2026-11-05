-- =====================================================================
-- Supply ERP · Migracion 024 · M3 Compras, parte 1: terceros y proveedores, marcas, presentaciones,
-- homologacion (proveedor x producto x marca x presentacion), master de precios con vigencia, bloqueos y evaluacion.
-- Reglas de Osvaldo:
--  - Un proveedor puede tener varias marcas de un producto en distintas unidades de empaque; una marca la pueden
--    tener varios proveedores (procesados). La materia prima natural no siempre tiene marca.
--  - Proyectos productivos del INPEC: cada panaderia de cada establecimiento es una razon social aparte que factura
--    por su lado; por contrato tienen prioridad como primera opcion de compra para lo que ofrecen.
--  - Compras evalua y selecciona: precio y condiciones, cumplimiento, calidad, bloqueos comerciales (morosidad u otro).
--  - Entregas en el CEDI o directo en la unidad de servicio (perecederos en carceles grandes).
-- =====================================================================
set client_min_messages = warning;

-- digito de verificacion DIAN
create or replace function public.dv_nit(p_nit text) returns int language plpgsql immutable as $$
declare pesos int[] := array[3,7,13,17,19,23,29,37,41,43,47,53,59,67,71]; s int := 0; d text := regexp_replace(coalesce(p_nit, ''), '\D', '', 'g'); i int; r int;
begin
  if d = '' or length(d) > 15 then return null; end if;
  for i in 1..length(d) loop s := s + substr(d, length(d) - i + 1, 1)::int * pesos[i]; end loop;
  r := s % 11;
  return case when r in (0, 1) then r else 11 - r end;
end $$;

-- ---------------------------------------------------------------------
-- 1. Terceros (proveedores, entidades, otros) por empresa
-- ---------------------------------------------------------------------
create table if not exists public.terceros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tipo_persona text not null default 'juridica' check (tipo_persona in ('juridica', 'natural', 'ut_consorcio', 'entidad_publica')),
  tipo_documento text not null default 'NIT' check (tipo_documento in ('NIT', 'CC', 'CE', 'PAS', 'PEP', 'NIT_EXT')),
  numero text not null,
  dv smallint,
  razon_social text not null,
  nombre_comercial text,
  es_proveedor boolean not null default true,
  es_entidad boolean not null default false,       -- entidad contratante / interventoria
  es_otro boolean not null default false,
  tipo_proveedor text check (tipo_proveedor is null or tipo_proveedor in ('fabricante', 'distribuidor', 'importador', 'productor_primario', 'proyecto_productivo_inpec', 'transportador', 'servicios', 'otro')),
  -- proyecto productivo del INPEC: ligado a un establecimiento (contrato_sede); prioridad contractual para lo que ofrece
  proyecto_productivo boolean not null default false,
  contrato_sede_id uuid references public.contrato_sedes(id),
  categorias text[] not null default '{}',          -- categorias que surte: proteinas, fruver, abarrotes...
  estado text not null default 'activo' check (estado in ('activo', 'inactivo')),
  motivo_inactivo text,
  -- ubicacion y contacto
  direccion text, ciudad text, departamento text, pais text default 'CO',
  telefono text, celular text, correo text, correo_facturacion text, correos_oc text[], sitio_web text,
  -- tributario
  responsable_iva boolean, regimen text check (regimen is null or regimen in ('ordinario', 'simple', 'no_responsable_iva', 'especial')),
  gran_contribuyente boolean, autorretenedor boolean, agente_retencion_iva boolean, responsabilidades_rut text[], actividad_ciiu text,
  rep_legal_nombre text, rep_legal_tipo_doc text, rep_legal_numero text,
  banco text, tipo_cuenta text check (tipo_cuenta is null or tipo_cuenta in ('ahorros', 'corriente')), numero_cuenta text, titular_cuenta text,
  -- condiciones comerciales
  condicion_pago text check (condicion_pago is null or condicion_pago in ('contado', 'anticipo', 'credito')),
  plazo_dias int, cupo_credito numeric,
  lead_time_dias int,                                -- dias entre la OC y la entrega
  entrega_en text not null default 'cedi' check (entrega_en in ('cedi', 'sede', 'ambos')),
  minimo_pedido numeric,
  -- homologacion general del proveedor
  estado_homologacion text not null default 'en_proceso' check (estado_homologacion in ('en_proceso', 'homologado', 'condicionado', 'rechazado', 'suspendido')),
  homologado_por uuid, homologado_en timestamptz, homologacion_vence date,
  calificacion numeric,                              -- ultima calificacion (0 a 100) de la evaluacion
  notas text,
  siigo_id text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz not null default now(),
  unique (empresa_id, tipo_documento, numero)
);
create index if not exists terceros_empresa_idx on public.terceros (empresa_id, razon_social);
create index if not exists terceros_nombre_trgm on public.terceros using gin (razon_social extensions.gin_trgm_ops);

create table if not exists public.tercero_contactos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  funcion text not null default 'comercial' check (funcion in ('comercial', 'cartera', 'contabilidad', 'logistica', 'calidad', 'facturacion', 'gerencia', 'otro')),
  nombre text not null, cargo text, telefono text, correo text, notas text,
  creado_en timestamptz not null default now()
);
create table if not exists public.tercero_puntos_despacho (   -- de donde despacha el proveedor (para lead time y rutas)
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  nombre text not null, direccion text, ciudad text, horario text, contacto text, telefono text, notas text,
  activo boolean not null default true, creado_en timestamptz not null default now()
);

-- documentos exigidos al proveedor (catalogo) y los que tiene cada uno (el archivo va en adjuntos, entidad 'tercero_doc')
create table if not exists public.tipos_documento_tercero (
  codigo text primary key, nombre text not null, orden int not null default 0,
  obligatorio boolean not null default false, solo_alimentos boolean not null default false, vigencia_dias int, ayuda text
);
insert into public.tipos_documento_tercero (codigo, nombre, orden, obligatorio, solo_alimentos, vigencia_dias, ayuda) values
  ('rut', 'RUT (DIAN)', 1, true, false, 365, 'Actualizado'),
  ('camara', 'Certificado de Camara de Comercio', 2, true, false, 30, 'No aplica a personas naturales sin establecimiento ni a proyectos productivos del INPEC'),
  ('cedula_rl', 'Cedula del representante legal', 3, true, false, null, null),
  ('cert_bancaria', 'Certificacion bancaria', 4, true, false, 90, null),
  ('datos_personales', 'Autorizacion de tratamiento de datos (Ley 1581)', 5, true, false, null, null),
  ('concepto_sanitario', 'Concepto sanitario favorable (Secretaria de Salud / INVIMA)', 6, true, true, 365, 'Planta, bodega o punto de despacho'),
  ('registro_sanitario', 'Registro, permiso o notificacion sanitaria INVIMA', 7, false, true, null, 'Por producto procesado'),
  ('fichas_tecnicas', 'Fichas tecnicas de los productos', 8, false, true, null, null),
  ('certificado_bpm', 'Certificado BPM / HACCP', 9, false, true, 365, null),
  ('plan_saneamiento', 'Plan de saneamiento y control de plagas', 10, false, true, 365, null),
  ('carnet_manipulacion', 'Carnets de manipulacion de alimentos (personal)', 11, false, true, 365, null),
  ('certificado_transporte', 'Vehiculos: concepto sanitario de transporte de alimentos', 12, false, true, 365, null),
  ('referencias', 'Referencias comerciales', 13, false, false, null, null),
  ('estados_financieros', 'Estados financieros', 14, false, false, 365, null),
  ('resolucion_inpec', 'Resolucion o acta del proyecto productivo (INPEC)', 15, false, false, null, 'Solo proyectos productivos')
on conflict (codigo) do nothing;
create table if not exists public.tercero_documentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  codigo text not null references public.tipos_documento_tercero(codigo),
  fecha_documento date, vence date, numero text, notas text, adjunto_id uuid references public.adjuntos(id),
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  unique (tercero_id, codigo)
);

-- bloqueos comerciales: morosidad, calidad, legal, otro; con vigencia; bloquean OC mientras rigen
create table if not exists public.tercero_bloqueos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  tipo text not null check (tipo in ('morosidad', 'calidad', 'incumplimiento', 'legal', 'documentos', 'otro')),
  motivo text not null,
  desde date not null default (now() at time zone 'America/Bogota')::date,
  hasta date,
  bloquea_oc boolean not null default true,
  levantado_por uuid, levantado_en timestamptz, nota_levantamiento text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now()
);
create index if not exists tercero_bloqueos_idx on public.tercero_bloqueos (tercero_id, desde);

-- evaluacion periodica (manual por ahora; el scorecard transaccional llega con recepciones y facturas)
create table if not exists public.tercero_evaluaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  periodo text not null,                              -- '2026-10', '2026-T3'
  cumplimiento numeric check (cumplimiento between 0 and 100),   -- entregas a tiempo y completas
  calidad numeric check (calidad between 0 and 100),             -- rechazos, devoluciones, temperatura
  precio numeric check (precio between 0 and 100),               -- competitividad y estabilidad
  servicio numeric check (servicio between 0 and 100),           -- respuesta, documentos, facturacion
  puntaje numeric,                                               -- ponderado
  concepto text check (concepto is null or concepto in ('confiable', 'aceptable', 'condicionado', 'no_confiable')),
  notas text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  unique (tercero_id, periodo)
);

-- ---------------------------------------------------------------------
-- 2. Marcas, presentaciones y homologacion de productos por proveedor
-- ---------------------------------------------------------------------
create table if not exists public.marcas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nombre text not null,
  fabricante_id uuid references public.terceros(id),
  notas text,
  estado text not null default 'activa' check (estado in ('activa', 'inactiva')),
  creado_en timestamptz not null default now(),
  unique (empresa_id, nombre)
);

-- unidad de empaque de un producto: "bulto x 50 kg", "caja x 24 und x 200 ml", "kg a granel"
create table if not exists public.presentaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  producto_id uuid not null references public.productos(id),
  nombre text not null,                 -- Bulto 50 kg
  contenido numeric not null check (contenido > 0),   -- cantidad en unidad base del producto (g, ml, und) por presentacion
  unidad_empaque text not null default 'und',          -- bulto, caja, canasta, kg, l, und, bandeja, paca
  granel boolean not null default false,
  codigo_barras text,
  estado text not null default 'activa' check (estado in ('activa', 'inactiva')),
  creado_en timestamptz not null default now(),
  unique (empresa_id, producto_id, nombre)
);
create index if not exists presentaciones_producto_idx on public.presentaciones (producto_id);

-- lo que cada proveedor ofrece: producto + marca (opcional) + presentacion, con su homologacion
create table if not exists public.proveedor_productos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  producto_id uuid not null references public.productos(id),
  marca_id uuid references public.marcas(id),
  presentacion_id uuid references public.presentaciones(id),
  codigo_proveedor text,
  origen text check (origen is null or origen in ('nacional', 'importado')),
  lead_time_dias int,
  minimo_pedido numeric,
  entrega_en text check (entrega_en is null or entrega_en in ('cedi', 'sede', 'ambos')),
  estado text not null default 'propuesto' check (estado in ('propuesto', 'homologado', 'condicionado', 'rechazado', 'suspendido')),
  homologado_por uuid, homologado_en timestamptz, homologacion_vence date,
  ficha_tecnica_id uuid references public.adjuntos(id),
  registro_sanitario text,
  preferido boolean not null default false,       -- lo marca compras: primera opcion para este producto
  notas text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz not null default now(),
  unique nulls not distinct (tercero_id, producto_id, marca_id, presentacion_id)
);
create index if not exists proveedor_productos_prod_idx on public.proveedor_productos (empresa_id, producto_id, estado);

-- ---------------------------------------------------------------------
-- 3. Master de precios: por oferta de proveedor (proveedor_producto) con vigencia; precio por presentacion y por unidad base
-- ---------------------------------------------------------------------
create table if not exists public.precios (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  proveedor_producto_id uuid not null references public.proveedor_productos(id) on delete cascade,
  precio numeric not null check (precio >= 0),            -- por presentacion (o por unidad de compra si es granel)
  por_unidad_base numeric not null,                        -- precio / contenido (COP por g, ml o und); lo calcula el trigger
  iva_pct numeric not null default 0 check (iva_pct between 0 and 100),
  moneda text not null default 'COP',
  vigente_desde date not null default (now() at time zone 'America/Bogota')::date,
  vigente_hasta date,
  origen text not null default 'cotizacion' check (origen in ('cotizacion', 'oferta_portal', 'negociacion', 'lista', 'factura', 'importacion')),
  lugar_entrega text not null default 'cedi' check (lugar_entrega in ('cedi', 'sede', 'ambos')),
  condicion_pago text check (condicion_pago is null or condicion_pago in ('contado', 'anticipo', 'credito')),
  incluye_flete boolean not null default true,
  soporte text, notas text,
  aprobado_por uuid, aprobado_en timestamptz,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  constraint precios_vigencia check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);
create index if not exists precios_pp_idx on public.precios (proveedor_producto_id, vigente_desde desc);
alter table public.precios drop constraint if exists precios_sin_solape;
alter table public.precios add constraint precios_sin_solape exclude using gist (proveedor_producto_id with =, daterange(vigente_desde, vigente_hasta, '[]') with &&);

-- precio por unidad base = precio / contenido de la presentacion (granel sin presentacion: precio por unidad de compra / factor_compra)
create or replace function public.precios_antes() returns trigger language plpgsql as $$
declare v_cont numeric; v_factor numeric;
begin
  select pr.contenido into v_cont from public.proveedor_productos pp left join public.presentaciones pr on pr.id = pp.presentacion_id where pp.id = new.proveedor_producto_id;
  if v_cont is null then
    select p.factor_compra into v_factor from public.proveedor_productos pp join public.productos p on p.id = pp.producto_id where pp.id = new.proveedor_producto_id;
    v_cont := coalesce(v_factor, 1);
  end if;
  new.por_unidad_base := case when v_cont > 0 then new.precio / v_cont else new.precio end;
  return new;
end $$;
drop trigger if exists precios_antes on public.precios;
create trigger precios_antes before insert or update on public.precios for each row execute function public.precios_antes();

-- ---------------------------------------------------------------------
-- 4. Seguridad
-- ---------------------------------------------------------------------
create or replace function public.puede_compras(p_empresa uuid, p_accion public.accion_permiso default 'crear') returns boolean language sql stable security definer set search_path = public as $$
  select public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(p_empresa, 'M3', p_accion) or (p_accion = 'crear' and public.tiene_permiso(p_empresa, 'M13', 'crear'));
$$;
revoke all on function public.puede_compras(uuid, public.accion_permiso) from public, anon; grant execute on function public.puede_compras(uuid, public.accion_permiso) to authenticated;

do $p$
declare t text;
begin
  foreach t in array array['terceros', 'tercero_contactos', 'tercero_puntos_despacho', 'tercero_documentos', 'tercero_bloqueos', 'tercero_evaluaciones', 'marcas', 'presentaciones', 'proveedor_productos', 'precios'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_ver', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id))', t || '_ver', t);
    execute format('drop policy if exists %I on public.%I', t || '_escribir', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.puede_compras(empresa_id, ''crear'')) with check (public.puede_compras(empresa_id, ''crear''))', t || '_escribir', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop trigger if exists %I_bitacora on public.%I', t, t);
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
  end loop;
end $p$;
alter table public.tipos_documento_tercero enable row level security;
drop policy if exists tipos_doc_ver on public.tipos_documento_tercero;
create policy tipos_doc_ver on public.tipos_documento_tercero for select to authenticated using (true);
grant select on public.tipos_documento_tercero to authenticated;

-- coherencia de empresa en las tablas nuevas (trigger de la auditoria M2)
do $$
declare t text;
begin
  foreach t in array array['tercero_contactos', 'tercero_puntos_despacho', 'tercero_documentos', 'tercero_bloqueos', 'tercero_evaluaciones', 'proveedor_productos', 'precios'] loop
    begin
      execute format('drop trigger if exists %I_empresa_coherente on public.%I', t, t);
      execute format('create trigger %I_empresa_coherente before insert or update on public.%I for each row execute function public.validar_empresa_coherente()', t, t);
    exception when undefined_function then null;
    end;
  end loop;
end $$;

-- antes de guardar un tercero: limpia numero, calcula DV, valida proyecto productivo, historial
create or replace function public.terceros_antes() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.numero := regexp_replace(trim(new.numero), '[^0-9A-Za-z]', '', 'g');
  if new.numero = '' then raise exception 'Escriba el numero de documento.'; end if;
  if coalesce(trim(new.razon_social), '') = '' then raise exception 'Escriba la razon social o el nombre.'; end if;
  new.razon_social := upper(trim(new.razon_social));
  if new.tipo_documento = 'NIT' then new.dv := public.dv_nit(new.numero); end if;
  if new.proyecto_productivo then
    new.tipo_proveedor := 'proyecto_productivo_inpec';
    if new.contrato_sede_id is null then raise exception 'Un proyecto productivo del INPEC debe quedar ligado a su establecimiento (sede del contrato).'; end if;
    if not exists (select 1 from public.contrato_sedes cs where cs.id = new.contrato_sede_id and cs.empresa_id = new.empresa_id) then raise exception 'El establecimiento no es de esta empresa.'; end if;
  end if;
  if new.estado_homologacion = 'homologado' and (tg_op = 'INSERT' or old.estado_homologacion <> 'homologado') then new.homologado_por := auth.uid(); new.homologado_en := now(); end if;
  new.actualizado_por := auth.uid(); new.actualizado_en := now();
  return new;
end $$;
drop trigger if exists terceros_antes on public.terceros;
create trigger terceros_antes before insert or update on public.terceros for each row execute function public.terceros_antes();

create or replace function public.proveedor_productos_antes() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.terceros t where t.id = new.tercero_id and t.empresa_id = new.empresa_id and t.es_proveedor) then raise exception 'El tercero no es proveedor de esta empresa.'; end if;
  if not exists (select 1 from public.productos p where p.id = new.producto_id and p.empresa_id = new.empresa_id) then raise exception 'El producto no es de esta empresa.'; end if;
  if new.presentacion_id is not null and not exists (select 1 from public.presentaciones pr where pr.id = new.presentacion_id and pr.producto_id = new.producto_id) then raise exception 'La presentacion no corresponde al producto.'; end if;
  if new.estado = 'homologado' and (tg_op = 'INSERT' or old.estado <> 'homologado') then
    if not public.puede_compras(new.empresa_id, 'aprobar') then raise exception 'Homologar un producto de proveedor requiere Compras: aprobar.'; end if;
    new.homologado_por := auth.uid(); new.homologado_en := now();
  end if;
  new.actualizado_por := auth.uid(); new.actualizado_en := now();
  return new;
end $$;
drop trigger if exists proveedor_productos_antes on public.proveedor_productos;
create trigger proveedor_productos_antes before insert or update on public.proveedor_productos for each row execute function public.proveedor_productos_antes();

-- ---------------------------------------------------------------------
-- 5. Consultas para las pantallas
-- ---------------------------------------------------------------------
-- esta bloqueado hoy?
create or replace function public.tercero_bloqueado(p_tercero uuid, p_fecha date default null) returns boolean language sql stable as $$
  select exists (select 1 from public.tercero_bloqueos b where b.tercero_id = p_tercero and b.bloquea_oc and b.levantado_en is null
                  and b.desde <= coalesce(p_fecha, (now() at time zone 'America/Bogota')::date) and (b.hasta is null or b.hasta >= coalesce(p_fecha, (now() at time zone 'America/Bogota')::date)));
$$;

-- lista de proveedores con lo que compras necesita ver de un vistazo
create or replace function public.proveedores_lista(p_empresa uuid, p_filtro text default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if not (public.es_admin_sql() or public.es_superadmin() or public.es_miembro(p_empresa)) then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'razon_social', t.razon_social, 'nombre_comercial', t.nombre_comercial, 'numero', t.numero, 'dv', t.dv, 'tipo_documento', t.tipo_documento,
            'tipo_proveedor', t.tipo_proveedor, 'proyecto_productivo', t.proyecto_productivo, 'establecimiento', (select s.nombre from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.id = t.contrato_sede_id),
            'categorias', t.categorias, 'ciudad', t.ciudad, 'estado', t.estado, 'estado_homologacion', t.estado_homologacion, 'homologacion_vence', t.homologacion_vence, 'calificacion', t.calificacion,
            'entrega_en', t.entrega_en, 'condicion_pago', t.condicion_pago, 'plazo_dias', t.plazo_dias, 'lead_time_dias', t.lead_time_dias,
            'bloqueado', public.tercero_bloqueado(t.id, v_hoy),
            'bloqueo', (select b.tipo || ': ' || b.motivo from public.tercero_bloqueos b where b.tercero_id = t.id and b.bloquea_oc and b.levantado_en is null and b.desde <= v_hoy and (b.hasta is null or b.hasta >= v_hoy) order by b.desde desc limit 1),
            'productos', (select count(*) from public.proveedor_productos pp where pp.tercero_id = t.id and pp.estado in ('homologado', 'condicionado')),
            'productos_propuestos', (select count(*) from public.proveedor_productos pp where pp.tercero_id = t.id and pp.estado = 'propuesto'),
            'docs_vencidos', (select count(*) from public.tercero_documentos d where d.tercero_id = t.id and d.vence is not null and d.vence < v_hoy),
            'docs_faltantes', (select count(*) from public.tipos_documento_tercero td where td.obligatorio and not (td.codigo = 'camara' and (t.tipo_persona = 'natural' or t.proyecto_productivo))
                                 and not exists (select 1 from public.tercero_documentos d where d.tercero_id = t.id and d.codigo = td.codigo)),
            'precios_vigentes', (select count(*) from public.precios pr join public.proveedor_productos pp on pp.id = pr.proveedor_producto_id where pp.tercero_id = t.id and pr.vigente_desde <= v_hoy and (pr.vigente_hasta is null or pr.vigente_hasta >= v_hoy))
          ) order by t.proyecto_productivo desc, t.razon_social), '[]')
            from public.terceros t where t.empresa_id = p_empresa and t.es_proveedor
             and (p_filtro is null or t.razon_social ilike '%' || p_filtro || '%' or t.numero like p_filtro || '%' or coalesce(t.nombre_comercial, '') ilike '%' || p_filtro || '%'));
end $$;
revoke all on function public.proveedores_lista(uuid, text) from public, anon; grant execute on function public.proveedores_lista(uuid, text) to authenticated;

-- ficha completa de un proveedor
create or replace function public.proveedor_ficha(p_tercero uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t public.terceros; v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  select * into t from public.terceros where id = p_tercero;
  if t.id is null then raise exception 'Tercero no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.es_miembro(t.empresa_id)) then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'tercero', to_jsonb(t) || jsonb_build_object('establecimiento', (select s.nombre from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.id = t.contrato_sede_id), 'bloqueado', public.tercero_bloqueado(t.id, v_hoy)),
    'contactos', (select coalesce(jsonb_agg(to_jsonb(c) order by c.funcion, c.nombre), '[]') from public.tercero_contactos c where c.tercero_id = t.id),
    'despachos', (select coalesce(jsonb_agg(to_jsonb(d) order by d.nombre), '[]') from public.tercero_puntos_despacho d where d.tercero_id = t.id and d.activo),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', td.codigo, 'nombre', td.nombre, 'obligatorio', td.obligatorio and not (td.codigo = 'camara' and (t.tipo_persona = 'natural' or t.proyecto_productivo)), 'solo_alimentos', td.solo_alimentos, 'vigencia_dias', td.vigencia_dias, 'ayuda', td.ayuda,
                      'id', d.id, 'fecha_documento', d.fecha_documento, 'vence', d.vence, 'numero', d.numero, 'notas', d.notas, 'adjunto_id', d.adjunto_id,
                      'estado', case when d.id is null then 'falta' when d.vence is not null and d.vence < v_hoy then 'vencido' when d.vence is not null and d.vence < v_hoy + 30 then 'por_vencer' else 'ok' end) order by td.orden), '[]')
                    from public.tipos_documento_tercero td left join public.tercero_documentos d on d.codigo = td.codigo and d.tercero_id = t.id
                    where not (td.codigo = 'resolucion_inpec' and not t.proyecto_productivo)),
    'bloqueos', (select coalesce(jsonb_agg(to_jsonb(b) || jsonb_build_object('vigente', b.levantado_en is null and b.desde <= v_hoy and (b.hasta is null or b.hasta >= v_hoy)) order by b.desde desc), '[]') from public.tercero_bloqueos b where b.tercero_id = t.id),
    'evaluaciones', (select coalesce(jsonb_agg(to_jsonb(e) order by e.periodo desc), '[]') from public.tercero_evaluaciones e where e.tercero_id = t.id),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('id', pp.id, 'producto_id', pp.producto_id, 'producto', p.nombre, 'codigo', p.codigo, 'categoria', p.categoria, 'unidad_base', p.unidad_base, 'unidad_compra', p.unidad_compra, 'factor_compra', p.factor_compra,
                       'marca_id', pp.marca_id, 'marca', m.nombre, 'presentacion_id', pp.presentacion_id, 'presentacion', pr.nombre, 'contenido', pr.contenido, 'codigo_proveedor', pp.codigo_proveedor, 'origen', pp.origen,
                       'lead_time_dias', pp.lead_time_dias, 'minimo_pedido', pp.minimo_pedido, 'entrega_en', pp.entrega_en, 'estado', pp.estado, 'preferido', pp.preferido, 'registro_sanitario', pp.registro_sanitario, 'notas', pp.notas, 'homologacion_vence', pp.homologacion_vence,
                       'precio', (select jsonb_build_object('id', x.id, 'precio', x.precio, 'por_unidad_base', x.por_unidad_base, 'iva_pct', x.iva_pct, 'desde', x.vigente_desde, 'hasta', x.vigente_hasta, 'origen', x.origen, 'lugar_entrega', x.lugar_entrega)
                                    from public.precios x where x.proveedor_producto_id = pp.id and x.vigente_desde <= v_hoy and (x.vigente_hasta is null or x.vigente_hasta >= v_hoy) order by x.vigente_desde desc limit 1),
                       'precio_por_compra', (select round(x.por_unidad_base * coalesce(p.factor_compra, 1), 2) from public.precios x where x.proveedor_producto_id = pp.id and x.vigente_desde <= v_hoy and (x.vigente_hasta is null or x.vigente_hasta >= v_hoy) order by x.vigente_desde desc limit 1),
                       'historial', (select count(*) from public.precios x where x.proveedor_producto_id = pp.id)
                     ) order by p.categoria, p.nombre, m.nombre, pr.nombre), '[]')
                    from public.proveedor_productos pp join public.productos p on p.id = pp.producto_id
                    left join public.marcas m on m.id = pp.marca_id left join public.presentaciones pr on pr.id = pp.presentacion_id
                   where pp.tercero_id = t.id)
  );
end $$;
revoke all on function public.proveedor_ficha(uuid) from public, anon; grant execute on function public.proveedor_ficha(uuid) to authenticated;

-- master de precios por producto: todas las ofertas vigentes, la mejor, y el ultimo precio pagado (cuando haya facturas)
create or replace function public.master_precios(p_empresa uuid, p_categoria text default null, p_filtro text default null, p_fecha date default null)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_f date := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
begin
  if not (public.es_admin_sql() or public.es_superadmin() or public.es_miembro(p_empresa)) then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('producto_id', p.id, 'codigo', p.codigo, 'producto', p.nombre, 'categoria', p.categoria, 'unidad_base', p.unidad_base, 'unidad_compra', p.unidad_compra, 'factor_compra', p.factor_compra, 'perecedero', p.perecedero,
            'ofertas', (select coalesce(jsonb_agg(jsonb_build_object('pp_id', pp.id, 'tercero_id', t.id, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'proyecto_productivo', t.proyecto_productivo, 'bloqueado', public.tercero_bloqueado(t.id, v_f),
                            'marca', m.nombre, 'presentacion', pr.nombre, 'contenido', pr.contenido, 'estado', pp.estado, 'preferido', pp.preferido, 'entrega_en', coalesce(pp.entrega_en, t.entrega_en), 'lead_time', coalesce(pp.lead_time_dias, t.lead_time_dias),
                            'precio', x.precio, 'por_unidad_base', x.por_unidad_base, 'por_compra', round(x.por_unidad_base * coalesce(p.factor_compra, 1), 2), 'iva_pct', x.iva_pct, 'desde', x.vigente_desde, 'hasta', x.vigente_hasta, 'origen', x.origen, 'precio_id', x.id)
                            order by (pp.estado = 'homologado') desc, x.por_unidad_base nulls last), '[]')
                          from public.proveedor_productos pp join public.terceros t on t.id = pp.tercero_id
                          left join public.marcas m on m.id = pp.marca_id left join public.presentaciones pr on pr.id = pp.presentacion_id
                          left join lateral (select * from public.precios x where x.proveedor_producto_id = pp.id and x.vigente_desde <= v_f and (x.vigente_hasta is null or x.vigente_hasta >= v_f) order by x.vigente_desde desc limit 1) x on true
                         where pp.producto_id = p.id and pp.estado <> 'rechazado' and t.estado = 'activo'),
            'mejor', (select round(min(x.por_unidad_base) * coalesce(p.factor_compra, 1), 2) from public.proveedor_productos pp join public.terceros t on t.id = pp.tercero_id join public.precios x on x.proveedor_producto_id = pp.id
                       where pp.producto_id = p.id and pp.estado in ('homologado', 'condicionado') and t.estado = 'activo' and not public.tercero_bloqueado(t.id, v_f) and x.vigente_desde <= v_f and (x.vigente_hasta is null or x.vigente_hasta >= v_f)),
            'n_ofertas', (select count(*) from public.proveedor_productos pp where pp.producto_id = p.id and pp.estado <> 'rechazado')
          ) order by p.categoria, p.nombre), '[]')
            from public.productos p
           where p.empresa_id = p_empresa and p.estado = 'activo' and (p_categoria is null or p.categoria = p_categoria)
             and (p_filtro is null or p.nombre ilike '%' || p_filtro || '%' or p.codigo ilike '%' || p_filtro || '%'));
end $$;
revoke all on function public.master_precios(uuid, text, text, date) from public, anon; grant execute on function public.master_precios(uuid, text, text, date) to authenticated;

-- registrar un precio (cierra el anterior el dia antes; la nueva termina antes de la siguiente futura)
create or replace function public.registrar_precio(p_pp uuid, p_precio numeric, p_desde date, p_iva numeric default 0, p_origen text default 'cotizacion', p_lugar text default 'cedi', p_hasta date default null, p_soporte text default null, p_notas text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid; v_hasta date;
begin
  select empresa_id into v_emp from public.proveedor_productos where id = p_pp;
  if v_emp is null then raise exception 'Oferta de proveedor no encontrada'; end if;
  if not public.puede_compras(v_emp, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if p_desde is null then raise exception 'Falta la fecha desde la que rige el precio.'; end if;
  delete from public.precios where proveedor_producto_id = p_pp and vigente_desde = p_desde;
  update public.precios set vigente_hasta = p_desde - 1 where proveedor_producto_id = p_pp and vigente_desde < p_desde and (vigente_hasta is null or vigente_hasta >= p_desde);
  select min(vigente_desde) - 1 into v_hasta from public.precios where proveedor_producto_id = p_pp and vigente_desde > p_desde;
  insert into public.precios (empresa_id, proveedor_producto_id, precio, por_unidad_base, iva_pct, vigente_desde, vigente_hasta, origen, lugar_entrega, soporte, notas)
  values (v_emp, p_pp, p_precio, 0, coalesce(p_iva, 0), p_desde, coalesce(p_hasta, v_hasta), coalesce(p_origen, 'cotizacion'), coalesce(p_lugar, 'cedi'), p_soporte, p_notas) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.registrar_precio(uuid, numeric, date, numeric, text, text, date, text, text) from public, anon; grant execute on function public.registrar_precio(uuid, numeric, date, numeric, text, text, date, text, text) to authenticated;

-- alta rapida de oferta: proveedor + producto (+ marca por nombre, + presentacion por nombre y contenido) + precio opcional
create or replace function public.alta_oferta(p_tercero uuid, p_producto uuid, p_marca text default null, p_presentacion text default null, p_contenido numeric default null, p_unidad_empaque text default 'und',
                                              p_precio numeric default null, p_desde date default null, p_iva numeric default 0, p_estado text default 'propuesto', p_codigo_proveedor text default null, p_lead_time int default null, p_entrega_en text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_marca uuid; v_pres uuid; v_pp uuid;
begin
  select empresa_id into v_emp from public.terceros where id = p_tercero;
  if v_emp is null then raise exception 'Proveedor no encontrado'; end if;
  if not public.puede_compras(v_emp, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if nullif(trim(coalesce(p_marca, '')), '') is not null then
    insert into public.marcas (empresa_id, nombre) values (v_emp, trim(p_marca)) on conflict (empresa_id, nombre) do update set nombre = excluded.nombre returning id into v_marca;
  end if;
  if nullif(trim(coalesce(p_presentacion, '')), '') is not null then
    if coalesce(p_contenido, 0) <= 0 then raise exception 'La presentacion necesita el contenido en la unidad base del producto (g, ml o und).'; end if;
    insert into public.presentaciones (empresa_id, producto_id, nombre, contenido, unidad_empaque) values (v_emp, p_producto, trim(p_presentacion), p_contenido, coalesce(p_unidad_empaque, 'und'))
    on conflict (empresa_id, producto_id, nombre) do update set contenido = excluded.contenido returning id into v_pres;
  end if;
  insert into public.proveedor_productos (empresa_id, tercero_id, producto_id, marca_id, presentacion_id, codigo_proveedor, lead_time_dias, entrega_en, estado)
  values (v_emp, p_tercero, p_producto, v_marca, v_pres, p_codigo_proveedor, p_lead_time, p_entrega_en, coalesce(p_estado, 'propuesto'))
  on conflict (tercero_id, producto_id, marca_id, presentacion_id) do update set codigo_proveedor = coalesce(excluded.codigo_proveedor, public.proveedor_productos.codigo_proveedor), lead_time_dias = coalesce(excluded.lead_time_dias, public.proveedor_productos.lead_time_dias)
  returning id into v_pp;
  if p_precio is not null then perform public.registrar_precio(v_pp, p_precio, coalesce(p_desde, (now() at time zone 'America/Bogota')::date), p_iva, 'cotizacion', coalesce(p_entrega_en, 'cedi')); end if;
  return v_pp;
end $$;
revoke all on function public.alta_oferta(uuid, uuid, text, text, numeric, text, numeric, date, numeric, text, text, int, text) from public, anon; grant execute on function public.alta_oferta(uuid, uuid, text, text, numeric, text, numeric, date, numeric, text, text, int, text) to authenticated;

-- bloquear / levantar bloqueo
create or replace function public.bloquear_tercero(p_tercero uuid, p_tipo text, p_motivo text, p_hasta date default null, p_bloquea_oc boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid;
begin
  select empresa_id into v_emp from public.terceros where id = p_tercero;
  if not public.puede_compras(v_emp, 'aprobar') then raise exception 'Bloquear un proveedor requiere Compras: aprobar.'; end if;
  insert into public.tercero_bloqueos (empresa_id, tercero_id, tipo, motivo, hasta, bloquea_oc) values (v_emp, p_tercero, p_tipo, p_motivo, p_hasta, p_bloquea_oc) returning id into v_id;
  insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
  select v_emp, 'M3', 'alta', 'Proveedor bloqueado: ' || t.razon_social, p_tipo || ': ' || p_motivo, '/proveedores?id=' || t.id, 'tercero', t.id from public.terceros t where t.id = p_tercero;
  return v_id;
end $$;
create or replace function public.levantar_bloqueo(p_id uuid, p_nota text default null) returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.tercero_bloqueos where id = p_id;
  if not public.puede_compras(v_emp, 'aprobar') then raise exception 'Levantar un bloqueo requiere Compras: aprobar.'; end if;
  update public.tercero_bloqueos set levantado_por = auth.uid(), levantado_en = now(), nota_levantamiento = p_nota where id = p_id;
end $$;
revoke all on function public.bloquear_tercero(uuid, text, text, date, boolean), public.levantar_bloqueo(uuid, text) from public, anon;
grant execute on function public.bloquear_tercero(uuid, text, text, date, boolean), public.levantar_bloqueo(uuid, text) to authenticated;

-- evaluacion: ponderacion 35 cumplimiento, 30 calidad, 20 precio, 15 servicio; actualiza la calificacion del tercero
create or replace function public.evaluar_tercero(p_tercero uuid, p_periodo text, p_cumplimiento numeric, p_calidad numeric, p_precio numeric, p_servicio numeric, p_notas text default null)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_p numeric;
begin
  select empresa_id into v_emp from public.terceros where id = p_tercero;
  if not public.puede_compras(v_emp, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  v_p := round(coalesce(p_cumplimiento, 0) * 0.35 + coalesce(p_calidad, 0) * 0.30 + coalesce(p_precio, 0) * 0.20 + coalesce(p_servicio, 0) * 0.15, 1);
  insert into public.tercero_evaluaciones (empresa_id, tercero_id, periodo, cumplimiento, calidad, precio, servicio, puntaje, concepto, notas)
  values (v_emp, p_tercero, p_periodo, p_cumplimiento, p_calidad, p_precio, p_servicio, v_p,
          case when v_p >= 85 then 'confiable' when v_p >= 70 then 'aceptable' when v_p >= 50 then 'condicionado' else 'no_confiable' end, p_notas)
  on conflict (tercero_id, periodo) do update set cumplimiento = excluded.cumplimiento, calidad = excluded.calidad, precio = excluded.precio, servicio = excluded.servicio, puntaje = excluded.puntaje, concepto = excluded.concepto, notas = excluded.notas;
  update public.terceros set calificacion = v_p where id = p_tercero;
  return v_p;
end $$;
revoke all on function public.evaluar_tercero(uuid, text, numeric, numeric, numeric, numeric, text) from public, anon; grant execute on function public.evaluar_tercero(uuid, text, numeric, numeric, numeric, numeric, text) to authenticated;

-- catalogos cortos para formularios
create or replace function public.catalogos_compras(p_empresa uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'marcas', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nombre', m.nombre) order by m.nombre), '[]') from public.marcas m where m.empresa_id = p_empresa and m.estado = 'activa'),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'categoria', p.categoria, 'unidad_base', p.unidad_base, 'unidad_compra', p.unidad_compra, 'factor_compra', p.factor_compra,
                    'presentaciones', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'contenido', pr.contenido) order by pr.contenido), '[]') from public.presentaciones pr where pr.producto_id = p.id and pr.estado = 'activa')) order by p.categoria, p.nombre), '[]')
                    from public.productos p where p.empresa_id = p_empresa and p.estado = 'activo'),
    'establecimientos', (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre, 'contrato', c.numero) order by s.nombre), '[]') from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id join public.contratos c on c.id = cs.contrato_id where cs.empresa_id = p_empresa and cs.estado = 'activa'),
    'categorias', (select coalesce(jsonb_agg(distinct p.categoria), '[]') from public.productos p where p.empresa_id = p_empresa and p.estado = 'activo')
  ) where public.es_admin_sql() or public.es_superadmin() or public.es_miembro(p_empresa);
$$;
revoke all on function public.catalogos_compras(uuid) from public, anon; grant execute on function public.catalogos_compras(uuid) to authenticated;
