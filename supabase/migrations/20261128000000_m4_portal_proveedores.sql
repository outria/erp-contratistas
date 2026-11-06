-- =====================================================================
-- Supply ERP · Migracion 028 · M4 Portal de proveedores (e-procurement), parte 1
--   · Usuarios proveedor: cuenta ligada a un tercero (NIT) por empresa; rol 'proveedor' (solo M4). es_miembro deja de
--     incluir a los proveedores (asi las policies "miembro de la empresa" no les abren nada); es_proveedor_de y mi_tercero
--     son la llave del portal.
--   · Solicitudes de cotizacion (RFQ, consecutivo SO): lineas por producto, invitados, cierre; el proveedor cotiza cada
--     linea con una o varias VARIANTES (marca, presentacion, precio, pago, plazo, pronto pago, lead time, minimo, ficha);
--     comparativo normalizado por unidad de compra y costo efectivo; adjudicacion (parcial por linea) que alimenta el
--     master de precios (origen oferta_portal) y genera las OC en borrador.
--   · Precios propuestos por el proveedor sobre sus ofertas vigentes (tabla aparte: no chocan con la vigencia del master);
--     Compras acepta (entra al master) o rechaza.
--   · Confirmacion de OC desde el portal; documentos del proveedor subidos por el mismo (storage con ruta propia).
-- Reglas de la casa: SECURITY DEFINER + control de permisos, es_admin_sql(), WHERE en todo update, grants explicitos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Identidad del proveedor
-- ---------------------------------------------------------------------
create table if not exists public.usuarios_proveedor (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,     -- null mientras la cuenta no exista en Supabase Auth
  correo text not null,
  nombre text, cargo text,
  activo boolean not null default true,
  invitado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  unique (empresa_id, correo)
);
create index if not exists usuarios_proveedor_usuario_idx on public.usuarios_proveedor (usuario_id, empresa_id);

-- miembro "interno": membresia activa con un rol que no es de proveedor
create or replace function public.es_miembro(p_empresa uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membresias m join public.roles r on r.id = m.rol_id
                  where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo and not r.es_proveedor);
$$;
create or replace function public.es_proveedor_de(p_empresa uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membresias m join public.roles r on r.id = m.rol_id
                  where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo and r.es_proveedor);
$$;
-- el tercero del proveedor autenticado en esa empresa (null si no es proveedor)
create or replace function public.mi_tercero(p_empresa uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select up.tercero_id from public.usuarios_proveedor up
   where up.usuario_id = auth.uid() and up.empresa_id = p_empresa and up.activo and public.es_proveedor_de(p_empresa)
   limit 1;
$$;
revoke all on function public.es_proveedor_de(uuid), public.mi_tercero(uuid) from public, anon;
grant execute on function public.es_proveedor_de(uuid), public.mi_tercero(uuid) to authenticated;

-- el proveedor ve la fila de la empresa (para entrar) y su propio tercero
drop policy if exists empresas_ver_proveedor on public.empresas;
create policy empresas_ver_proveedor on public.empresas for select to authenticated using (public.es_proveedor_de(id));
drop policy if exists terceros_ver_propio on public.terceros;
create policy terceros_ver_propio on public.terceros for select to authenticated using (id = public.mi_tercero(empresa_id));
drop policy if exists tercero_documentos_propio on public.tercero_documentos;
create policy tercero_documentos_propio on public.tercero_documentos for select to authenticated using (tercero_id = public.mi_tercero(empresa_id));
drop policy if exists tipos_documento_tercero_prov on public.tipos_documento_tercero;
create policy tipos_documento_tercero_prov on public.tipos_documento_tercero for select to authenticated using (true);

alter table public.usuarios_proveedor enable row level security;
drop policy if exists usuarios_proveedor_ver on public.usuarios_proveedor;
create policy usuarios_proveedor_ver on public.usuarios_proveedor for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id) or usuario_id = auth.uid());
grant select on public.usuarios_proveedor to authenticated;

-- Compras invita al usuario del proveedor: si la cuenta ya existe en Auth queda activa de una; si no, queda pendiente
-- hasta que el administrador la invite en Supabase (Authentication > Invite user) y vuelva a correr la invitacion.
create or replace function public.invitar_usuario_proveedor(p_tercero uuid, p_correo text, p_nombre text default null, p_cargo text default null)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare t public.terceros; v_user uuid; v_rol uuid; v_id uuid;
begin
  select * into t from public.terceros where id = p_tercero;
  if t.id is null then raise exception 'Proveedor no encontrado'; end if;
  if not public.puede_compras(t.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_correo));
  insert into public.usuarios_proveedor (empresa_id, tercero_id, usuario_id, correo, nombre, cargo)
  values (t.empresa_id, t.id, v_user, lower(trim(p_correo)), p_nombre, p_cargo)
  on conflict (empresa_id, correo) do update set tercero_id = excluded.tercero_id, usuario_id = coalesce(excluded.usuario_id, public.usuarios_proveedor.usuario_id), nombre = coalesce(excluded.nombre, public.usuarios_proveedor.nombre), cargo = coalesce(excluded.cargo, public.usuarios_proveedor.cargo), activo = true
  returning id into v_id;
  if v_user is not null then
    select id into v_rol from public.roles where empresa_id = t.empresa_id and codigo = 'proveedor' and estado = 'activo';
    if v_rol is null then raise exception 'La empresa no tiene el rol proveedor'; end if;
    if exists (select 1 from public.membresias m join public.roles r on r.id = m.rol_id where m.usuario_id = v_user and m.empresa_id = t.empresa_id and not r.es_proveedor) then
      raise exception 'Ese correo es de un usuario interno de la empresa; un proveedor necesita una cuenta aparte.';
    end if;
    insert into public.membresias (usuario_id, empresa_id, rol_id, creado_por) values (v_user, t.empresa_id, v_rol, auth.uid())
    on conflict (usuario_id, empresa_id) do update set rol_id = excluded.rol_id, activo = true;
    update public.perfiles set tipo = 'proveedor', nombre = coalesce(nombre, p_nombre) where id = v_user and tipo <> 'proveedor';
  end if;
  return jsonb_build_object('id', v_id, 'activo', v_user is not null, 'mensaje', case when v_user is null then 'La cuenta no existe todavia en Supabase Auth: invitela (Authentication > Invite user) y vuelva a dar clic en Invitar.' else 'Usuario del portal activo.' end);
end $$;
create or replace function public.desactivar_usuario_proveedor(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare u public.usuarios_proveedor;
begin
  select * into u from public.usuarios_proveedor where id = p_id;
  if u.id is null then raise exception 'No encontrado'; end if;
  if not public.puede_compras(u.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  update public.usuarios_proveedor set activo = false where id = p_id;
  if u.usuario_id is not null then update public.membresias set activo = false where usuario_id = u.usuario_id and empresa_id = u.empresa_id; end if;
end $$;

-- storage: el proveedor sube y ve solo bajo <empresa>/proveedor/<su tercero>/...
drop policy if exists adjuntos_storage_prov_ver on storage.objects;
create policy adjuntos_storage_prov_ver on storage.objects for select to authenticated
  using (bucket_id = 'adjuntos' and (storage.foldername(name))[2] = 'proveedor' and (storage.foldername(name))[3] = public.mi_tercero(((storage.foldername(name))[1])::uuid)::text);
drop policy if exists adjuntos_storage_prov_subir on storage.objects;
create policy adjuntos_storage_prov_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'adjuntos' and (storage.foldername(name))[2] = 'proveedor' and (storage.foldername(name))[3] = public.mi_tercero(((storage.foldername(name))[1])::uuid)::text);
drop policy if exists adjuntos_ver_proveedor on public.adjuntos;
create policy adjuntos_ver_proveedor on public.adjuntos for select to authenticated using (entidad = 'proveedor' and entidad_id = public.mi_tercero(empresa_id));

-- el proveedor registra un documento suyo (el archivo ya subio al storage): queda con fecha y vencimiento, Compras lo valida
create or replace function public.portal_documento(p_empresa uuid, p_codigo text, p_nombre text, p_ruta text, p_tipo_mime text default null, p_tamano bigint default null, p_fecha date default null, p_vence date default null, p_numero text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_t uuid := public.mi_tercero(p_empresa); v_adj uuid;
begin
  if v_t is null then raise exception 'Solo para usuarios del portal de proveedores.'; end if;
  insert into public.adjuntos (empresa_id, entidad, entidad_id, categoria, nombre, ruta, tipo_mime, tamano, vigente_desde, vigente_hasta, subido_nombre)
  values (p_empresa, 'proveedor', v_t, p_codigo, p_nombre, p_ruta, p_tipo_mime, p_tamano, p_fecha, p_vence, (select nombre from public.usuarios_proveedor where usuario_id = auth.uid() and empresa_id = p_empresa limit 1))
  returning id into v_adj;
  insert into public.tercero_documentos (empresa_id, tercero_id, codigo, fecha_documento, vence, numero, adjunto_id, notas)
  values (p_empresa, v_t, p_codigo, p_fecha, p_vence, p_numero, v_adj, 'Subido por el proveedor desde el portal')
  on conflict (tercero_id, codigo) do update set fecha_documento = excluded.fecha_documento, vence = excluded.vence, numero = coalesce(excluded.numero, public.tercero_documentos.numero), adjunto_id = excluded.adjunto_id, notas = excluded.notas;
  return v_adj;
end $$;

-- ---------------------------------------------------------------------
-- 2. Solicitudes de cotizacion
-- ---------------------------------------------------------------------
create table if not exists public.solicitudes_cotizacion (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  codigo text not null,
  titulo text not null,
  explosion_id uuid references public.explosiones(id),
  contrato_id uuid references public.contratos(id),
  lugar_entrega text not null default 'cedi' check (lugar_entrega in ('cedi', 'sede', 'ambos')),
  entrega_desde date, entrega_hasta date,
  cierre timestamptz not null,
  condiciones text,                     -- lo que el proveedor debe saber (pago estandar, documentos, visita)
  permite_variantes boolean not null default true,
  estado text not null default 'borrador' check (estado in ('borrador', 'publicada', 'cerrada', 'adjudicada', 'anulada')),
  publicada_en timestamptz, cerrada_en timestamptz,
  notas text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (empresa_id, codigo)
);
create table if not exists public.solicitud_lineas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  solicitud_id uuid not null references public.solicitudes_cotizacion(id) on delete cascade,
  producto_id uuid not null references public.productos(id),
  cantidad numeric not null check (cantidad > 0),       -- en unidad de compra del producto
  contrato_sede_id uuid references public.contrato_sedes(id),
  especificacion text,                                  -- calidad, marca de referencia, empaque deseado
  orden int not null default 1,
  unique (solicitud_id, producto_id, contrato_sede_id)
);
create table if not exists public.solicitud_invitados (
  solicitud_id uuid not null references public.solicitudes_cotizacion(id) on delete cascade,
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id),
  notificado_en timestamptz, visto_en timestamptz,
  primary key (solicitud_id, tercero_id)
);
create table if not exists public.ofertas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  solicitud_id uuid not null references public.solicitudes_cotizacion(id) on delete cascade,
  tercero_id uuid not null references public.terceros(id),
  estado text not null default 'borrador' check (estado in ('borrador', 'enviada', 'retirada', 'adjudicada', 'parcial', 'no_adjudicada')),
  validez_hasta date,
  condiciones text,                     -- observaciones generales del proveedor
  enviada_en timestamptz, enviada_por uuid,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  unique (solicitud_id, tercero_id)
);
create table if not exists public.oferta_lineas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  oferta_id uuid not null references public.ofertas(id) on delete cascade,
  linea_id uuid not null references public.solicitud_lineas(id) on delete cascade,
  variante int not null default 1,
  marca text, presentacion text, contenido numeric check (contenido is null or contenido > 0), unidad_empaque text,   -- contenido en unidad base por presentacion; null = granel por unidad de compra
  precio numeric not null check (precio >= 0),              -- por presentacion (o por unidad de compra si granel), sin IVA
  iva_pct numeric not null default 0,
  condicion_pago text check (condicion_pago is null or condicion_pago in ('contado', 'anticipo', 'credito')),
  plazo_dias int,
  descuento_pronto_pago_pct numeric, descuento_pronto_pago_dias int,
  lead_time_dias int, minimo_pedido numeric,
  lugar_entrega text check (lugar_entrega is null or lugar_entrega in ('cedi', 'sede', 'ambos')),
  incluye_flete boolean not null default true,
  origen text check (origen is null or origen in ('nacional', 'importado')),
  registro_sanitario text,
  ficha_tecnica_id uuid references public.adjuntos(id),
  nota text,
  por_unidad_compra numeric,                                 -- lo calcula el trigger: precio normalizado a la unidad de compra del producto
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  unique (oferta_id, linea_id, variante)
);
create table if not exists public.adjudicaciones (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  solicitud_id uuid not null references public.solicitudes_cotizacion(id) on delete cascade,
  linea_id uuid not null references public.solicitud_lineas(id),
  oferta_linea_id uuid not null references public.oferta_lineas(id),
  cantidad numeric not null check (cantidad > 0),            -- en unidad de compra
  motivo text,
  oc_id uuid references public.ordenes_compra(id),
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now()
);
create index if not exists solicitudes_empresa_idx on public.solicitudes_cotizacion (empresa_id, cierre desc);
create index if not exists ofertas_solicitud_idx on public.ofertas (solicitud_id);
create index if not exists oferta_lineas_oferta_idx on public.oferta_lineas (oferta_id, linea_id);

-- precios propuestos por el proveedor sobre una oferta homologada (no tocan el master hasta que Compras acepte)
create table if not exists public.precios_propuestos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  proveedor_producto_id uuid not null references public.proveedor_productos(id) on delete cascade,
  precio numeric not null check (precio >= 0), iva_pct numeric not null default 0,
  vigente_desde date not null, vigente_hasta date,
  condicion_pago text check (condicion_pago is null or condicion_pago in ('contado', 'anticipo', 'credito')), plazo_dias int,
  descuento_pronto_pago_pct numeric, descuento_pronto_pago_dias int, minimo_pedido numeric, lugar_entrega text default 'cedi',
  nota text,
  estado text not null default 'propuesto' check (estado in ('propuesto', 'aceptado', 'rechazado')),
  resuelto_por uuid, resuelto_en timestamptz, nota_resolucion text, precio_id uuid references public.precios(id),
  propuesto_por uuid default auth.uid(), creado_en timestamptz not null default now()
);
create index if not exists precios_propuestos_idx on public.precios_propuestos (empresa_id, estado, creado_en desc);

-- normalizacion de la variante: precio por unidad de compra del producto
create or replace function public.oferta_lineas_antes() returns trigger language plpgsql security definer set search_path = public as $$
declare v_factor numeric; v_oferta public.ofertas;
begin
  select * into v_oferta from public.ofertas where id = new.oferta_id;
  if v_oferta.estado not in ('borrador', 'enviada') then raise exception 'La oferta ya no se puede modificar (%).', v_oferta.estado; end if;
  if not exists (select 1 from public.solicitud_lineas l where l.id = new.linea_id and l.solicitud_id = v_oferta.solicitud_id) then raise exception 'La linea no es de esta solicitud'; end if;
  select p.factor_compra into v_factor from public.solicitud_lineas l join public.productos p on p.id = l.producto_id where l.id = new.linea_id;
  new.empresa_id := v_oferta.empresa_id;
  new.por_unidad_compra := case when new.contenido is null or new.contenido <= 0 then new.precio else round(new.precio / new.contenido * coalesce(v_factor, 1), 2) end;
  new.actualizado_en := now();
  return new;
end $$;
drop trigger if exists oferta_lineas_antes on public.oferta_lineas;
create trigger oferta_lineas_antes before insert or update on public.oferta_lineas for each row execute function public.oferta_lineas_antes();

-- seguridad: RLS; internos ven todo lo de su empresa; el proveedor ve sus invitaciones publicadas, sus ofertas y sus propuestas
do $p$
declare t text;
begin
  foreach t in array array['solicitudes_cotizacion', 'solicitud_lineas', 'solicitud_invitados', 'ofertas', 'oferta_lineas', 'adjudicaciones', 'precios_propuestos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_ver', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id))', t || '_ver', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $p$;
drop policy if exists solicitudes_prov on public.solicitudes_cotizacion;
create policy solicitudes_prov on public.solicitudes_cotizacion for select to authenticated using (estado in ('publicada', 'cerrada', 'adjudicada') and exists (select 1 from public.solicitud_invitados i where i.solicitud_id = public.solicitudes_cotizacion.id and i.tercero_id = public.mi_tercero(public.solicitudes_cotizacion.empresa_id)));
drop policy if exists solicitud_lineas_prov on public.solicitud_lineas;
create policy solicitud_lineas_prov on public.solicitud_lineas for select to authenticated using (exists (select 1 from public.solicitud_invitados i join public.solicitudes_cotizacion s on s.id = i.solicitud_id where i.solicitud_id = public.solicitud_lineas.solicitud_id and s.estado <> 'borrador' and i.tercero_id = public.mi_tercero(public.solicitud_lineas.empresa_id)));
drop policy if exists ofertas_prov on public.ofertas;
create policy ofertas_prov on public.ofertas for select to authenticated using (tercero_id = public.mi_tercero(empresa_id));
drop policy if exists oferta_lineas_prov on public.oferta_lineas;
create policy oferta_lineas_prov on public.oferta_lineas for select to authenticated using (exists (select 1 from public.ofertas o where o.id = public.oferta_lineas.oferta_id and o.tercero_id = public.mi_tercero(public.oferta_lineas.empresa_id)));
drop policy if exists precios_propuestos_prov on public.precios_propuestos;
create policy precios_propuestos_prov on public.precios_propuestos for select to authenticated using (exists (select 1 from public.proveedor_productos pp where pp.id = public.precios_propuestos.proveedor_producto_id and pp.tercero_id = public.mi_tercero(public.precios_propuestos.empresa_id)));
drop policy if exists proveedor_productos_prov on public.proveedor_productos;
create policy proveedor_productos_prov on public.proveedor_productos for select to authenticated using (tercero_id = public.mi_tercero(empresa_id));
drop policy if exists precios_prov on public.precios;
create policy precios_prov on public.precios for select to authenticated using (exists (select 1 from public.proveedor_productos pp where pp.id = public.precios.proveedor_producto_id and pp.tercero_id = public.mi_tercero(public.precios.empresa_id)));
drop policy if exists ordenes_compra_prov on public.ordenes_compra;
create policy ordenes_compra_prov on public.ordenes_compra for select to authenticated using (estado not in ('borrador', 'anulada') and tercero_id = public.mi_tercero(empresa_id));
drop policy if exists oc_items_prov on public.oc_items;
create policy oc_items_prov on public.oc_items for select to authenticated using (exists (select 1 from public.ordenes_compra o where o.id = public.oc_items.oc_id and o.estado not in ('borrador', 'anulada') and o.tercero_id = public.mi_tercero(public.oc_items.empresa_id)));
drop policy if exists productos_prov on public.productos;
create policy productos_prov on public.productos for select to authenticated using (public.es_proveedor_de(empresa_id));
drop policy if exists marcas_prov on public.marcas;
create policy marcas_prov on public.marcas for select to authenticated using (public.es_proveedor_de(empresa_id));
drop policy if exists presentaciones_prov on public.presentaciones;
create policy presentaciones_prov on public.presentaciones for select to authenticated using (public.es_proveedor_de(empresa_id));

-- ---------------------------------------------------------------------
-- 3. Lado Compras: crear, invitar, publicar, cerrar, comparar, adjudicar
-- ---------------------------------------------------------------------
-- p: {empresa_id, id?, titulo, explosion_id?, contrato_id?, lugar_entrega, entrega_desde, entrega_hasta, cierre, condiciones, notas,
--     lineas: [{producto_id, cantidad, contrato_sede_id?, especificacion?}], invitados: [tercero_id], solo_sin_precio?: bool}
create or replace function public.guardar_solicitud(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_id uuid := nullif(p->>'id', '')::uuid; s public.solicitudes_cotizacion; l jsonb; v_exp uuid := nullif(p->>'explosion_id', '')::uuid; i int := 0;
begin
  if v_id is not null then select * into s from public.solicitudes_cotizacion where id = v_id; v_emp := s.empresa_id; if s.estado <> 'borrador' then raise exception 'Solo se edita una solicitud en borrador.'; end if; end if;
  if not public.puede_compras(v_emp, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if (p->>'cierre') is null then raise exception 'Falta la fecha y hora de cierre.'; end if;
  if v_id is null then
    insert into public.solicitudes_cotizacion (empresa_id, codigo, titulo, explosion_id, contrato_id, lugar_entrega, entrega_desde, entrega_hasta, cierre, condiciones, notas)
    values (v_emp, public.siguiente_consecutivo(v_emp, 'SO'), p->>'titulo', v_exp, coalesce(nullif(p->>'contrato_id', '')::uuid, (select contrato_id from public.explosiones where id = v_exp)), coalesce(p->>'lugar_entrega', 'cedi'),
            nullif(p->>'entrega_desde', '')::date, nullif(p->>'entrega_hasta', '')::date, (p->>'cierre')::timestamptz, p->>'condiciones', p->>'notas') returning id into v_id;
  else
    update public.solicitudes_cotizacion set titulo = p->>'titulo', lugar_entrega = coalesce(p->>'lugar_entrega', lugar_entrega), entrega_desde = nullif(p->>'entrega_desde', '')::date, entrega_hasta = nullif(p->>'entrega_hasta', '')::date,
           cierre = (p->>'cierre')::timestamptz, condiciones = p->>'condiciones', notas = p->>'notas', actualizado_en = now() where id = v_id;
    delete from public.solicitud_lineas where solicitud_id = v_id;
    delete from public.solicitud_invitados where solicitud_id = v_id;
  end if;
  -- lineas: las enviadas, o todas las del requerimiento (opcionalmente solo las que no tienen proveedor elegible)
  if jsonb_typeof(p->'lineas') = 'array' and jsonb_array_length(p->'lineas') > 0 then
    for l in select x from jsonb_array_elements(p->'lineas') x loop
      i := i + 1;
      insert into public.solicitud_lineas (empresa_id, solicitud_id, producto_id, cantidad, contrato_sede_id, especificacion, orden)
      values (v_emp, v_id, (l->>'producto_id')::uuid, (l->>'cantidad')::numeric, nullif(l->>'contrato_sede_id', '')::uuid, l->>'especificacion', i)
      on conflict (solicitud_id, producto_id, contrato_sede_id) do update set cantidad = excluded.cantidad, especificacion = excluded.especificacion;
    end loop;
  elsif v_exp is not null then
    insert into public.solicitud_lineas (empresa_id, solicitud_id, producto_id, cantidad, orden)
    select v_emp, v_id, x.producto_id, round(x.base / nullif(pr.factor_compra, 0), 2), row_number() over (order by pr.categoria, pr.nombre)
      from (select d.producto_id, sum(d.cantidad_bruta) base from public.explosion_detalle d where d.explosion_id = v_exp group by 1) x
      join public.productos pr on pr.id = x.producto_id
     where coalesce((p->>'solo_sin_precio')::boolean, false) = false
        or not exists (select 1 from public.precio_base_producto(x.producto_id, (now() at time zone 'America/Bogota')::date));
  end if;
  -- invitados: los enviados, o los homologados activos sin bloqueo de las categorias de las lineas
  if jsonb_typeof(p->'invitados') = 'array' and jsonb_array_length(p->'invitados') > 0 then
    insert into public.solicitud_invitados (solicitud_id, tercero_id, empresa_id) select v_id, (x#>>'{}')::uuid, v_emp from jsonb_array_elements(p->'invitados') x on conflict do nothing;
  else
    insert into public.solicitud_invitados (solicitud_id, tercero_id, empresa_id)
    select distinct v_id, t.id, v_emp from public.terceros t
     where t.empresa_id = v_emp and t.es_proveedor and t.estado = 'activo' and t.estado_homologacion in ('homologado', 'condicionado', 'en_proceso') and not public.tercero_bloqueado(t.id)
       and t.categorias && (select coalesce(array_agg(distinct pr.categoria), '{}') from public.solicitud_lineas l join public.productos pr on pr.id = l.producto_id where l.solicitud_id = v_id)
    on conflict do nothing;
  end if;
  return v_id;
end $$;

create or replace function public.estado_solicitud(p_id uuid, p_accion text, p_nota text default null) returns void language plpgsql security definer set search_path = public as $$
declare s public.solicitudes_cotizacion;
begin
  select * into s from public.solicitudes_cotizacion where id = p_id;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  if not public.puede_compras(s.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if p_accion = 'publicar' then
    if s.estado <> 'borrador' then raise exception 'Solo se publica un borrador.'; end if;
    if not exists (select 1 from public.solicitud_lineas where solicitud_id = p_id) then raise exception 'La solicitud no tiene lineas.'; end if;
    if not exists (select 1 from public.solicitud_invitados where solicitud_id = p_id) then raise exception 'No hay proveedores invitados.'; end if;
    if s.cierre <= now() then raise exception 'El cierre debe ser una fecha futura.'; end if;
    update public.solicitudes_cotizacion set estado = 'publicada', publicada_en = now(), actualizado_en = now() where id = p_id;
    update public.solicitud_invitados set notificado_en = now() where solicitud_id = p_id;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (s.empresa_id, 'M3', 'normal', 'Solicitud ' || s.codigo || ' publicada', s.titulo || ' · cierra ' || to_char(s.cierre at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI'), '/cotizaciones?id=' || s.id, 'solicitud', s.id);
  elsif p_accion = 'cerrar' then
    if s.estado <> 'publicada' then raise exception 'Solo se cierra una solicitud publicada.'; end if;
    update public.solicitudes_cotizacion set estado = 'cerrada', cerrada_en = now(), actualizado_en = now() where id = p_id;
    update public.ofertas set estado = 'retirada', actualizado_en = now() where solicitud_id = p_id and estado = 'borrador';   -- lo no enviado no cuenta
  elsif p_accion = 'reabrir' then
    if s.estado <> 'cerrada' then raise exception 'Solo se reabre una cerrada.'; end if;
    if s.cierre <= now() then raise exception 'Primero mueva la fecha de cierre al futuro.'; end if;
    update public.solicitudes_cotizacion set estado = 'publicada', cerrada_en = null, actualizado_en = now() where id = p_id;
  elsif p_accion = 'anular' then
    if s.estado in ('adjudicada', 'anulada') then raise exception 'La solicitud ya esta %.', s.estado; end if;
    update public.solicitudes_cotizacion set estado = 'anulada', notas = concat_ws(E'\n', notas, 'Anulada: ' || coalesce(p_nota, 'sin motivo')), actualizado_en = now() where id = p_id;
  else raise exception 'Accion no valida'; end if;
end $$;

-- comparativo: por linea, todas las variantes enviadas, normalizadas; costo efectivo = precio por unidad de compra
-- menos el descuento por pronto pago si la empresa lo aprovecha (config compras.aprovecha_pronto_pago, por defecto si)
create or replace function public.comparar_ofertas(p_solicitud uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare s public.solicitudes_cotizacion; v_pp boolean; v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud;
  if s.id is null or not public.puede_compras(s.empresa_id, 'ver') then raise exception 'Sin permiso'; end if;
  select coalesce((valor#>>'{}')::boolean, true) into v_pp from public.config_empresa where empresa_id = s.empresa_id and clave = 'compras.aprovecha_pronto_pago';
  v_pp := coalesce(v_pp, true);
  return jsonb_build_object(
    'solicitud', to_jsonb(s) || jsonb_build_object('requerimiento', (select codigo from public.explosiones e where e.id = s.explosion_id), 'contrato', (select numero from public.contratos c where c.id = s.contrato_id), 'abierta', s.estado = 'publicada' and s.cierre > now()),
    'invitados', (select coalesce(jsonb_agg(jsonb_build_object('tercero_id', t.id, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'inpec', t.proyecto_productivo, 'homologacion', t.estado_homologacion, 'calificacion', t.calificacion, 'bloqueado', public.tercero_bloqueado(t.id),
                      'notificado_en', i.notificado_en, 'visto_en', i.visto_en, 'oferta_estado', o.estado, 'oferta_id', o.id, 'enviada_en', o.enviada_en, 'validez_hasta', o.validez_hasta, 'condiciones', o.condiciones,
                      'lineas_cotizadas', (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id),
                      'usuarios', (select count(*) from public.usuarios_proveedor up where up.tercero_id = t.id and up.activo and up.usuario_id is not null)) order by t.razon_social), '[]')
                    from public.solicitud_invitados i join public.terceros t on t.id = i.tercero_id left join public.ofertas o on o.solicitud_id = i.solicitud_id and o.tercero_id = t.id where i.solicitud_id = p_solicitud),
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'producto_id', l.producto_id, 'producto', pr.nombre, 'codigo', pr.codigo, 'categoria', pr.categoria, 'unidad_compra', pr.unidad_compra, 'unidad_base', pr.unidad_base, 'factor_compra', pr.factor_compra,
                  'cantidad', l.cantidad, 'especificacion', l.especificacion, 'sede', (select se.nombre from public.contrato_sedes cs join public.sedes se on se.id = cs.sede_id where cs.id = l.contrato_sede_id), 'contrato_sede_id', l.contrato_sede_id,
                  'precio_master', (select round(pb.por_unidad_base * coalesce(pr.factor_compra, 1), 2) from public.precio_base_producto(l.producto_id, v_hoy) pb),
                  'variantes', (select coalesce(jsonb_agg(v order by (v->>'costo_efectivo')::numeric), '[]') from (
                     select jsonb_build_object('id', ol.id, 'oferta_id', o.id, 'tercero_id', t.id, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'inpec', t.proyecto_productivo, 'calificacion', t.calificacion, 'homologacion', t.estado_homologacion, 'bloqueado', public.tercero_bloqueado(t.id),
                              'variante', ol.variante, 'marca', ol.marca, 'presentacion', ol.presentacion, 'contenido', ol.contenido, 'unidad_empaque', ol.unidad_empaque, 'precio', ol.precio, 'iva_pct', ol.iva_pct, 'por_unidad_compra', ol.por_unidad_compra,
                              'condicion_pago', ol.condicion_pago, 'plazo_dias', ol.plazo_dias, 'pp_pct', ol.descuento_pronto_pago_pct, 'pp_dias', ol.descuento_pronto_pago_dias, 'lead_time', ol.lead_time_dias, 'minimo', ol.minimo_pedido, 'lugar_entrega', ol.lugar_entrega, 'flete', ol.incluye_flete, 'origen', ol.origen,
                              'ficha_tecnica_id', ol.ficha_tecnica_id, 'registro_sanitario', ol.registro_sanitario, 'nota', ol.nota,
                              'costo_efectivo', case when v_pp and coalesce(ol.descuento_pronto_pago_pct, 0) > 0 then round(ol.por_unidad_compra * (1 - ol.descuento_pronto_pago_pct / 100), 2) else ol.por_unidad_compra end,
                              'total_linea', round(l.cantidad * case when v_pp and coalesce(ol.descuento_pronto_pago_pct, 0) > 0 then ol.por_unidad_compra * (1 - ol.descuento_pronto_pago_pct / 100) else ol.por_unidad_compra end, 0),
                              'adjudicada', (select coalesce(sum(a.cantidad), 0) from public.adjudicaciones a where a.oferta_linea_id = ol.id)) v
                       from public.oferta_lineas ol join public.ofertas o on o.id = ol.oferta_id join public.terceros t on t.id = o.tercero_id
                      where ol.linea_id = l.id and o.estado in ('enviada', 'adjudicada', 'parcial', 'no_adjudicada')) q),
                  'adjudicado', (select coalesce(sum(a.cantidad), 0) from public.adjudicaciones a where a.linea_id = l.id)
                ) order by l.orden), '[]') from public.solicitud_lineas l join public.productos pr on pr.id = l.producto_id where l.solicitud_id = p_solicitud),
    'aprovecha_pronto_pago', v_pp,
    'ocs', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'total', o.total)), '[]') from public.adjudicaciones a join public.ordenes_compra o on o.id = a.oc_id where a.solicitud_id = p_solicitud)
  );
end $$;

-- adjudicar: p_items [{linea_id, oferta_linea_id, cantidad, motivo}] -> adjudicaciones, master de precios (oferta_portal), OC en borrador por proveedor y lugar
create or replace function public.adjudicar_solicitud(p_solicitud uuid, p_items jsonb, p_fecha_entrega date default null, p_cerrar boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.solicitudes_cotizacion; it jsonb; v record; v_pp uuid; v_precio uuid; g record; v_oc uuid; v_ids uuid[] := '{}'; v_cedi uuid; v_sede uuid; v_desde date := (now() at time zone 'America/Bogota')::date;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  if not public.puede_compras(s.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
  if s.estado not in ('publicada', 'cerrada') then raise exception 'La solicitud esta %.', s.estado; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'No hay lineas adjudicadas.'; end if;
  select id into v_cedi from public.sedes where empresa_id = s.empresa_id and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1;
  drop table if exists tmp_adj; create temp table tmp_adj (adj_id uuid, linea_id uuid, oferta_linea_id uuid, tercero_id uuid, producto_id uuid, pp_id uuid, cantidad numeric, lugar text, contrato_sede_id uuid, precio numeric, iva numeric, contenido numeric, unidad text, descripcion text, motivo text) on commit drop;
  for it in select x from jsonb_array_elements(p_items) x loop
    select ol.*, o.tercero_id, l.producto_id, l.contrato_sede_id lsede, pr.nombre producto, pr.unidad_compra, pr.factor_compra into v
      from public.oferta_lineas ol join public.ofertas o on o.id = ol.oferta_id join public.solicitud_lineas l on l.id = ol.linea_id join public.productos pr on pr.id = l.producto_id
     where ol.id = (it->>'oferta_linea_id')::uuid and o.solicitud_id = p_solicitud and o.estado in ('enviada', 'adjudicada', 'parcial');
    if v.id is null then raise exception 'Variante de oferta no valida para esta solicitud'; end if;
    if public.tercero_bloqueado(v.tercero_id) then raise exception 'El proveedor tiene un bloqueo vigente; no se le puede adjudicar.'; end if;
    -- la variante entra al catalogo del proveedor (producto x marca x presentacion) y al master de precios como oferta_portal
    v_pp := public.alta_oferta(v.tercero_id, v.producto_id, v.marca, v.presentacion, v.contenido, v.unidad_empaque, null, null, 0, 'homologado', null, v.lead_time_dias, v.lugar_entrega);
    update public.proveedor_productos set ficha_tecnica_id = coalesce(v.ficha_tecnica_id, ficha_tecnica_id), registro_sanitario = coalesce(v.registro_sanitario, registro_sanitario), origen = coalesce(v.origen, origen), minimo_pedido = coalesce(v.minimo_pedido, minimo_pedido) where id = v_pp;
    v_precio := public.registrar_precio(v_pp, v.precio, v_desde, v.iva_pct, 'oferta_portal', coalesce(v.lugar_entrega, s.lugar_entrega, 'cedi'), null, s.codigo, 'Adjudicacion ' || s.codigo || ' variante ' || v.variante);
    update public.precios set condicion_pago = v.condicion_pago, plazo_dias = v.plazo_dias, descuento_pronto_pago_pct = v.descuento_pronto_pago_pct, descuento_pronto_pago_dias = v.descuento_pronto_pago_dias, minimo_pedido = v.minimo_pedido, incluye_flete = v.incluye_flete, oferta_linea_id = v.id, aprobado_por = auth.uid(), aprobado_en = now() where id = v_precio;
    insert into public.adjudicaciones (empresa_id, solicitud_id, linea_id, oferta_linea_id, cantidad, motivo) values (s.empresa_id, p_solicitud, v.linea_id, v.id, (it->>'cantidad')::numeric, it->>'motivo') returning id into v_pp;
    insert into tmp_adj values (v_pp, v.linea_id, v.id, v.tercero_id, v.producto_id, (select pp.id from public.proveedor_productos pp where pp.tercero_id = v.tercero_id and pp.producto_id = v.producto_id and coalesce((select m.nombre from public.marcas m where m.id = pp.marca_id), '') = coalesce(v.marca, '') and coalesce((select pr.nombre from public.presentaciones pr where pr.id = pp.presentacion_id), '') = coalesce(v.presentacion, '') limit 1),
      (it->>'cantidad')::numeric, case when coalesce(v.lugar_entrega, s.lugar_entrega) = 'sede' and v.lsede is not null then 'sede' else 'cedi' end, case when coalesce(v.lugar_entrega, s.lugar_entrega) = 'sede' then v.lsede end,
      v.precio, v.iva_pct, coalesce(v.contenido, v.factor_compra, 1), coalesce(v.unidad_empaque, v.unidad_compra), concat_ws(' · ', v.producto, v.marca, v.presentacion), coalesce(it->>'motivo', 'adjudicacion ' || s.codigo));
  end loop;
  -- OC en borrador por proveedor + lugar + establecimiento
  for g in select tercero_id, lugar, contrato_sede_id from tmp_adj group by 1, 2, 3 loop
    if g.lugar = 'sede' then select cs.sede_id into v_sede from public.contrato_sedes cs where cs.id = g.contrato_sede_id; else v_sede := v_cedi; end if;
    insert into public.ordenes_compra (empresa_id, codigo, tercero_id, explosion_id, contrato_id, lugar_entrega, sede_entrega_id, contrato_sede_id, fecha_entrega, condicion_pago, plazo_dias, notas)
    select s.empresa_id, public.siguiente_consecutivo(s.empresa_id, 'OC'), t.id, s.explosion_id, s.contrato_id, g.lugar, v_sede, g.contrato_sede_id, coalesce(p_fecha_entrega, s.entrega_desde),
           coalesce((select ol.condicion_pago from tmp_adj a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where a.tercero_id = g.tercero_id limit 1), t.condicion_pago),
           coalesce((select ol.plazo_dias from tmp_adj a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where a.tercero_id = g.tercero_id limit 1), t.plazo_dias), 'Adjudicacion de la solicitud ' || s.codigo
      from public.terceros t where t.id = g.tercero_id returning id into v_oc;
    v_ids := v_ids || v_oc;
    insert into public.oc_items (empresa_id, oc_id, producto_id, proveedor_producto_id, descripcion, unidad_pedido, contenido_base, cantidad, cantidad_base, precio, iva_pct, requerida_base, motivo)
    select s.empresa_id, v_oc, a.producto_id, a.pp_id, a.descripcion, a.unidad, a.contenido, ceil(a.cantidad * coalesce(pr.factor_compra, 1) / a.contenido), 0, a.precio, a.iva, a.cantidad * coalesce(pr.factor_compra, 1), a.motivo
      from tmp_adj a join public.productos pr on pr.id = a.producto_id where a.tercero_id = g.tercero_id and a.lugar = g.lugar and coalesce(a.contrato_sede_id, '00000000-0000-0000-0000-000000000000') = coalesce(g.contrato_sede_id, '00000000-0000-0000-0000-000000000000');
    update public.adjudicaciones ad set oc_id = v_oc from tmp_adj a where ad.id = a.adj_id and a.tercero_id = g.tercero_id and a.lugar = g.lugar and coalesce(a.contrato_sede_id, '00000000-0000-0000-0000-000000000000') = coalesce(g.contrato_sede_id, '00000000-0000-0000-0000-000000000000');
  end loop;
  -- estados de las ofertas
  update public.ofertas o set estado = case when exists (select 1 from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id)
                                             then case when (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id) = (select count(distinct ol.linea_id) from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id) then 'adjudicada' else 'parcial' end
                                             else case when p_cerrar then 'no_adjudicada' else o.estado end end, actualizado_en = now()
   where o.solicitud_id = p_solicitud and o.estado in ('enviada', 'adjudicada', 'parcial', 'no_adjudicada');
  if p_cerrar then update public.solicitudes_cotizacion set estado = 'adjudicada', cerrada_en = coalesce(cerrada_en, now()), actualizado_en = now() where id = p_solicitud; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'total', o.total) order by o.codigo), '[]') from public.ordenes_compra o where o.id = any(v_ids));
end $$;

create or replace function public.solicitudes_lista(p_empresa uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
begin
  if not public.puede_compras(p_empresa, 'ver') then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'codigo', s.codigo, 'titulo', s.titulo, 'estado', s.estado, 'cierre', s.cierre, 'abierta', s.estado = 'publicada' and s.cierre > now(), 'requerimiento', e.codigo, 'contrato', c.numero, 'lugar_entrega', s.lugar_entrega,
            'lineas', (select count(*) from public.solicitud_lineas l where l.solicitud_id = s.id), 'invitados', (select count(*) from public.solicitud_invitados i where i.solicitud_id = s.id),
            'ofertas', (select count(*) from public.ofertas o where o.solicitud_id = s.id and o.estado <> 'borrador' and o.estado <> 'retirada'), 'adjudicadas', (select count(distinct linea_id) from public.adjudicaciones a where a.solicitud_id = s.id)) order by s.creado_en desc), '[]')
            from public.solicitudes_cotizacion s left join public.explosiones e on e.id = s.explosion_id left join public.contratos c on c.id = s.contrato_id where s.empresa_id = p_empresa);
end $$;

-- precios propuestos por proveedores: resolver
create or replace function public.resolver_precio_propuesto(p_id uuid, p_acepta boolean, p_nota text default null) returns void language plpgsql security definer set search_path = public as $$
declare pp public.precios_propuestos; v_precio uuid;
begin
  select * into pp from public.precios_propuestos where id = p_id;
  if pp.id is null then raise exception 'No encontrado'; end if;
  if not public.puede_compras(pp.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
  if pp.estado <> 'propuesto' then raise exception 'Ya fue resuelto (%).', pp.estado; end if;
  if p_acepta then
    v_precio := public.registrar_precio(pp.proveedor_producto_id, pp.precio, greatest(pp.vigente_desde, (now() at time zone 'America/Bogota')::date), pp.iva_pct, 'oferta_portal', coalesce(pp.lugar_entrega, 'cedi'), pp.vigente_hasta, null, coalesce(pp.nota, 'Propuesto por el proveedor en el portal'));
    update public.precios set condicion_pago = pp.condicion_pago, plazo_dias = pp.plazo_dias, descuento_pronto_pago_pct = pp.descuento_pronto_pago_pct, descuento_pronto_pago_dias = pp.descuento_pronto_pago_dias, minimo_pedido = pp.minimo_pedido, aprobado_por = auth.uid(), aprobado_en = now() where id = v_precio;
  end if;
  update public.precios_propuestos set estado = case when p_acepta then 'aceptado' else 'rechazado' end, resuelto_por = auth.uid(), resuelto_en = now(), nota_resolucion = p_nota, precio_id = v_precio where id = p_id;
end $$;

create or replace function public.precios_propuestos_lista(p_empresa uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.puede_compras(p_empresa, 'ver') then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'estado', x.estado, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'tercero_id', t.id, 'producto', pr.nombre, 'marca', m.nombre, 'presentacion', ps.nombre, 'contenido', ps.contenido, 'unidad_compra', pr.unidad_compra,
            'precio', x.precio, 'por_compra', round(x.precio / coalesce(ps.contenido, pr.factor_compra, 1) * coalesce(pr.factor_compra, 1), 2), 'iva_pct', x.iva_pct, 'desde', x.vigente_desde, 'hasta', x.vigente_hasta, 'condicion_pago', x.condicion_pago, 'plazo_dias', x.plazo_dias, 'pp_pct', x.descuento_pronto_pago_pct, 'pp_dias', x.descuento_pronto_pago_dias, 'minimo', x.minimo_pedido, 'nota', x.nota, 'creado_en', x.creado_en,
            'vigente', (select v.precio from public.precios v where v.proveedor_producto_id = x.proveedor_producto_id and v.vigente_desde <= (now() at time zone 'America/Bogota')::date and (v.vigente_hasta is null or v.vigente_hasta >= (now() at time zone 'America/Bogota')::date) order by v.vigente_desde desc limit 1),
            'mejor_master', (select round(pb.por_unidad_base * coalesce(pr.factor_compra, 1), 2) from public.precio_base_producto(pr.id, (now() at time zone 'America/Bogota')::date) pb)) order by (x.estado = 'propuesto') desc, x.creado_en desc), '[]')
            from public.precios_propuestos x join public.proveedor_productos pp on pp.id = x.proveedor_producto_id join public.terceros t on t.id = pp.tercero_id join public.productos pr on pr.id = pp.producto_id
            left join public.marcas m on m.id = pp.marca_id left join public.presentaciones ps on ps.id = pp.presentacion_id where x.empresa_id = p_empresa);
end $$;

-- ---------------------------------------------------------------------
-- 4. Lado proveedor (portal): todo pasa por mi_tercero(empresa)
-- ---------------------------------------------------------------------
create or replace function public.portal_resumen(p_empresa uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_t uuid := public.mi_tercero(p_empresa); v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if v_t is null then raise exception 'Solo para usuarios del portal de proveedores.'; end if;
  return jsonb_build_object(
    'empresa', (select jsonb_build_object('id', e.id, 'nombre', coalesce(e.nombre_corto, e.razon_social), 'razon_social', e.razon_social, 'nit', e.nit) from public.empresas e where e.id = p_empresa),
    'tercero', (select jsonb_build_object('id', t.id, 'razon_social', t.razon_social, 'nombre_comercial', t.nombre_comercial, 'tipo_documento', t.tipo_documento, 'numero', t.numero, 'dv', t.dv, 'estado_homologacion', t.estado_homologacion, 'homologacion_vence', t.homologacion_vence, 'calificacion', t.calificacion,
                   'categorias', t.categorias, 'entrega_en', t.entrega_en, 'condicion_pago', t.condicion_pago, 'plazo_dias', t.plazo_dias, 'lead_time_dias', t.lead_time_dias, 'correo', t.correo, 'telefono', coalesce(t.celular, t.telefono), 'ciudad', t.ciudad, 'proyecto_productivo', t.proyecto_productivo,
                   'bloqueado', public.tercero_bloqueado(t.id), 'bloqueo', (select b.tipo || ': ' || b.motivo from public.tercero_bloqueos b where b.tercero_id = t.id and b.levantado_en is null and b.desde <= v_hoy and (b.hasta is null or b.hasta >= v_hoy) order by b.desde desc limit 1)) from public.terceros t where t.id = v_t),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', td.codigo, 'nombre', td.nombre, 'obligatorio', td.obligatorio, 'ayuda', td.ayuda, 'vigencia_dias', td.vigencia_dias, 'fecha', d.fecha_documento, 'vence', d.vence, 'numero', d.numero, 'adjunto_id', d.adjunto_id,
                      'estado', case when d.id is null then 'falta' when d.vence is not null and d.vence < v_hoy then 'vencido' when d.vence is not null and d.vence < v_hoy + 30 then 'por_vencer' else 'ok' end,
                      'ruta', (select a.ruta from public.adjuntos a where a.id = d.adjunto_id)) order by td.orden), '[]')
                     from public.tipos_documento_tercero td left join public.tercero_documentos d on d.tercero_id = v_t and d.codigo = td.codigo
                    where not td.solo_alimentos or exists (select 1 from public.terceros t where t.id = v_t and t.categorias && '{proteinas,fruver,lacteos,abarrotes,panaderia,bebidas}'::text[])),
    'solicitudes', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'codigo', s.codigo, 'titulo', s.titulo, 'estado', s.estado, 'cierre', s.cierre, 'abierta', s.estado = 'publicada' and s.cierre > now(), 'lugar_entrega', s.lugar_entrega, 'entrega_desde', s.entrega_desde, 'entrega_hasta', s.entrega_hasta,
                      'lineas', (select count(*) from public.solicitud_lineas l where l.solicitud_id = s.id), 'oferta_estado', o.estado, 'oferta_id', o.id, 'cotizadas', (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id),
                      'adjudicadas', (select count(*) from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id)) order by (s.estado = 'publicada' and s.cierre > now()) desc, s.cierre desc), '[]')
                      from public.solicitud_invitados i join public.solicitudes_cotizacion s on s.id = i.solicitud_id left join public.ofertas o on o.solicitud_id = s.id and o.tercero_id = v_t
                     where i.tercero_id = v_t and s.estado in ('publicada', 'cerrada', 'adjudicada')),
    'ofertas_catalogo', (select coalesce(jsonb_agg(jsonb_build_object('pp_id', pp.id, 'producto_id', pr.id, 'producto', pr.nombre, 'categoria', pr.categoria, 'unidad_compra', pr.unidad_compra, 'unidad_base', pr.unidad_base, 'factor_compra', pr.factor_compra, 'marca', m.nombre, 'presentacion', ps.nombre, 'contenido', ps.contenido, 'estado', pp.estado, 'preferido', pp.preferido,
                           'precio', x.precio, 'por_compra', case when x.por_unidad_base is null then null else round(x.por_unidad_base * coalesce(pr.factor_compra, 1), 2) end, 'iva_pct', x.iva_pct, 'desde', x.vigente_desde, 'hasta', x.vigente_hasta, 'condicion_pago', x.condicion_pago, 'plazo_dias', x.plazo_dias,
                           'propuesta', (select jsonb_build_object('id', q.id, 'precio', q.precio, 'desde', q.vigente_desde, 'estado', q.estado, 'nota_resolucion', q.nota_resolucion) from public.precios_propuestos q where q.proveedor_producto_id = pp.id order by q.creado_en desc limit 1),
                           'ficha_tecnica_id', pp.ficha_tecnica_id) order by pr.categoria, pr.nombre, m.nombre), '[]')
                           from public.proveedor_productos pp join public.productos pr on pr.id = pp.producto_id left join public.marcas m on m.id = pp.marca_id left join public.presentaciones ps on ps.id = pp.presentacion_id
                           left join lateral (select * from public.precios x where x.proveedor_producto_id = pp.id and x.vigente_desde <= v_hoy and (x.vigente_hasta is null or x.vigente_hasta >= v_hoy) order by x.vigente_desde desc limit 1) x on true
                          where pp.tercero_id = v_t and pp.estado <> 'rechazado'),
    'ordenes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'fecha_emision', o.fecha_emision, 'fecha_entrega', o.fecha_entrega, 'fecha_entrega_confirmada', o.fecha_entrega_confirmada, 'lugar_entrega', o.lugar_entrega, 'sede', se.nombre, 'ciudad', se.ciudad, 'direccion', se.direccion, 'total', o.total, 'condicion_pago', o.condicion_pago, 'plazo_dias', o.plazo_dias, 'notas', o.notas, 'observaciones_proveedor', o.observaciones_proveedor,
                   'items', (select count(*) from public.oc_items i where i.oc_id = o.id)) order by o.fecha_emision desc, o.codigo desc), '[]')
                   from public.ordenes_compra o left join public.sedes se on se.id = o.sede_entrega_id where o.tercero_id = v_t and o.estado not in ('borrador', 'anulada')),
    'evaluaciones', (select coalesce(jsonb_agg(jsonb_build_object('periodo', ev.periodo, 'cumplimiento', ev.cumplimiento, 'calidad', ev.calidad, 'precio', ev.precio, 'servicio', ev.servicio, 'total', ev.puntaje, 'concepto', ev.concepto) order by ev.periodo desc), '[]') from public.tercero_evaluaciones ev where ev.tercero_id = v_t),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'categoria', p.categoria, 'unidad_compra', p.unidad_compra, 'unidad_base', p.unidad_base, 'factor_compra', p.factor_compra) order by p.categoria, p.nombre), '[]') from public.productos p where p.empresa_id = p_empresa and p.estado = 'activo')
  );
end $$;

-- detalle de una solicitud para cotizar: lineas con mi oferta (variantes)
create or replace function public.portal_solicitud(p_solicitud uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.solicitudes_cotizacion; v_t uuid; o public.ofertas;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  v_t := public.mi_tercero(s.empresa_id);
  if v_t is null or not exists (select 1 from public.solicitud_invitados i where i.solicitud_id = s.id and i.tercero_id = v_t) or s.estado = 'borrador' then raise exception 'Sin acceso a esta solicitud'; end if;
  select * into o from public.ofertas where solicitud_id = s.id and tercero_id = v_t;
  return jsonb_build_object(
    'solicitud', jsonb_build_object('id', s.id, 'codigo', s.codigo, 'titulo', s.titulo, 'estado', s.estado, 'cierre', s.cierre, 'abierta', s.estado = 'publicada' and s.cierre > now(), 'lugar_entrega', s.lugar_entrega, 'entrega_desde', s.entrega_desde, 'entrega_hasta', s.entrega_hasta, 'condiciones', s.condiciones, 'permite_variantes', s.permite_variantes,
                   'empresa', (select coalesce(e.nombre_corto, e.razon_social) from public.empresas e where e.id = s.empresa_id)),
    'oferta', case when o.id is null then null else jsonb_build_object('id', o.id, 'estado', o.estado, 'validez_hasta', o.validez_hasta, 'condiciones', o.condiciones, 'enviada_en', o.enviada_en) end,
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'producto_id', pr.id, 'producto', pr.nombre, 'categoria', pr.categoria, 'unidad_compra', pr.unidad_compra, 'unidad_base', pr.unidad_base, 'factor_compra', pr.factor_compra, 'cantidad', l.cantidad, 'especificacion', l.especificacion,
                  'sede', (select se.nombre || coalesce(' · ' || se.ciudad, '') from public.contrato_sedes cs join public.sedes se on se.id = cs.sede_id where cs.id = l.contrato_sede_id),
                  'mis_variantes', (select coalesce(jsonb_agg(to_jsonb(ol) order by ol.variante), '[]') from public.oferta_lineas ol where ol.oferta_id = o.id and ol.linea_id = l.id),
                  'adjudicado_a_mi', (select coalesce(sum(a.cantidad), 0) from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id and a.linea_id = l.id),
                  'mis_presentaciones', (select coalesce(jsonb_agg(distinct jsonb_build_object('marca', m.nombre, 'presentacion', ps.nombre, 'contenido', ps.contenido, 'unidad_empaque', ps.unidad_empaque)), '[]') from public.proveedor_productos pp left join public.marcas m on m.id = pp.marca_id left join public.presentaciones ps on ps.id = pp.presentacion_id where pp.tercero_id = v_t and pp.producto_id = pr.id)
                ) order by l.orden), '[]') from public.solicitud_lineas l join public.productos pr on pr.id = l.producto_id where l.solicitud_id = s.id)
  );
end $$;

-- el proveedor marca que vio la solicitud
create or replace function public.portal_vista(p_solicitud uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_t uuid;
begin
  select empresa_id into v_emp from public.solicitudes_cotizacion where id = p_solicitud; v_t := public.mi_tercero(v_emp);
  if v_t is null then return; end if;
  update public.solicitud_invitados set visto_en = coalesce(visto_en, now()) where solicitud_id = p_solicitud and tercero_id = v_t;
end $$;

-- guardar una variante de mi oferta (crea la oferta en borrador si no existe)
-- p: {linea_id, id?, variante?, marca, presentacion, contenido, unidad_empaque, precio, iva_pct, condicion_pago, plazo_dias, descuento_pronto_pago_pct, descuento_pronto_pago_dias, lead_time_dias, minimo_pedido, lugar_entrega, incluye_flete, origen, registro_sanitario, ficha_tecnica_id, nota, borrar?}
create or replace function public.portal_guardar_variante(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare l public.solicitud_lineas; s public.solicitudes_cotizacion; v_t uuid; v_of uuid; v_id uuid := nullif(p->>'id', '')::uuid; v_var int;
begin
  select * into l from public.solicitud_lineas where id = (p->>'linea_id')::uuid;
  if l.id is null then raise exception 'Linea no encontrada'; end if;
  select * into s from public.solicitudes_cotizacion where id = l.solicitud_id;
  v_t := public.mi_tercero(s.empresa_id);
  if v_t is null or not exists (select 1 from public.solicitud_invitados i where i.solicitud_id = s.id and i.tercero_id = v_t) then raise exception 'Sin acceso a esta solicitud'; end if;
  if not (s.estado = 'publicada' and s.cierre > now()) then raise exception 'La solicitud ya cerro.'; end if;
  insert into public.ofertas (empresa_id, solicitud_id, tercero_id) values (s.empresa_id, s.id, v_t) on conflict (solicitud_id, tercero_id) do update set actualizado_en = now() returning id into v_of;
  if (select estado from public.ofertas where id = v_of) = 'retirada' then update public.ofertas set estado = 'borrador', actualizado_en = now() where id = v_of; end if;
  if coalesce(p->>'borrar', 'false') = 'true' then delete from public.oferta_lineas where id = v_id and oferta_id = v_of; return v_id; end if;
  if (p->>'precio') is null then raise exception 'Falta el precio.'; end if;
  if v_id is null then
    if not s.permite_variantes and exists (select 1 from public.oferta_lineas where oferta_id = v_of and linea_id = l.id) then raise exception 'Esta solicitud admite una sola cotizacion por linea.'; end if;
    select coalesce(max(variante), 0) + 1 into v_var from public.oferta_lineas where oferta_id = v_of and linea_id = l.id;
    insert into public.oferta_lineas (empresa_id, oferta_id, linea_id, variante, marca, presentacion, contenido, unidad_empaque, precio, iva_pct, condicion_pago, plazo_dias, descuento_pronto_pago_pct, descuento_pronto_pago_dias, lead_time_dias, minimo_pedido, lugar_entrega, incluye_flete, origen, registro_sanitario, ficha_tecnica_id, nota)
    values (s.empresa_id, v_of, l.id, v_var, nullif(trim(coalesce(p->>'marca', '')), ''), nullif(trim(coalesce(p->>'presentacion', '')), ''), (p->>'contenido')::numeric, p->>'unidad_empaque', (p->>'precio')::numeric, coalesce((p->>'iva_pct')::numeric, 0), nullif(p->>'condicion_pago', ''), (p->>'plazo_dias')::int,
            (p->>'descuento_pronto_pago_pct')::numeric, (p->>'descuento_pronto_pago_dias')::int, (p->>'lead_time_dias')::int, (p->>'minimo_pedido')::numeric, nullif(p->>'lugar_entrega', ''), coalesce((p->>'incluye_flete')::boolean, true), nullif(p->>'origen', ''), p->>'registro_sanitario', nullif(p->>'ficha_tecnica_id', '')::uuid, p->>'nota')
    returning id into v_id;
  else
    update public.oferta_lineas set marca = nullif(trim(coalesce(p->>'marca', '')), ''), presentacion = nullif(trim(coalesce(p->>'presentacion', '')), ''), contenido = (p->>'contenido')::numeric, unidad_empaque = p->>'unidad_empaque', precio = (p->>'precio')::numeric, iva_pct = coalesce((p->>'iva_pct')::numeric, 0),
           condicion_pago = nullif(p->>'condicion_pago', ''), plazo_dias = (p->>'plazo_dias')::int, descuento_pronto_pago_pct = (p->>'descuento_pronto_pago_pct')::numeric, descuento_pronto_pago_dias = (p->>'descuento_pronto_pago_dias')::int, lead_time_dias = (p->>'lead_time_dias')::int, minimo_pedido = (p->>'minimo_pedido')::numeric,
           lugar_entrega = nullif(p->>'lugar_entrega', ''), incluye_flete = coalesce((p->>'incluye_flete')::boolean, true), origen = nullif(p->>'origen', ''), registro_sanitario = p->>'registro_sanitario', ficha_tecnica_id = nullif(p->>'ficha_tecnica_id', '')::uuid, nota = p->>'nota'
     where id = v_id and oferta_id = v_of;
  end if;
  -- una oferta ya enviada que se edita vuelve a quedar enviada (la ultima version es la que vale); se anota
  update public.ofertas set actualizado_en = now() where id = v_of;
  return v_id;
end $$;

create or replace function public.portal_estado_oferta(p_solicitud uuid, p_accion text, p_validez date default null, p_condiciones text default null) returns void language plpgsql security definer set search_path = public as $$
declare s public.solicitudes_cotizacion; v_t uuid; o public.ofertas;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud; v_t := public.mi_tercero(s.empresa_id);
  if v_t is null then raise exception 'Sin acceso'; end if;
  select * into o from public.ofertas where solicitud_id = s.id and tercero_id = v_t;
  if o.id is null then raise exception 'No hay oferta que enviar: cotice al menos una linea.'; end if;
  if p_accion = 'enviar' then
    if not (s.estado = 'publicada' and s.cierre > now()) then raise exception 'La solicitud ya cerro.'; end if;
    if not exists (select 1 from public.oferta_lineas where oferta_id = o.id) then raise exception 'Cotice al menos una linea antes de enviar.'; end if;
    update public.ofertas set estado = 'enviada', enviada_en = now(), enviada_por = auth.uid(), validez_hasta = coalesce(p_validez, validez_hasta), condiciones = coalesce(p_condiciones, condiciones), actualizado_en = now() where id = o.id;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (s.empresa_id, 'M3', 'normal', 'Oferta recibida en ' || s.codigo, (select coalesce(t.nombre_comercial, t.razon_social) from public.terceros t where t.id = v_t) || ' cotizo ' || (select count(distinct linea_id) from public.oferta_lineas where oferta_id = o.id) || ' lineas', '/cotizaciones?id=' || s.id, 'solicitud', s.id);
  elsif p_accion = 'retirar' then
    if o.estado not in ('borrador', 'enviada') then raise exception 'La oferta ya fue evaluada.'; end if;
    update public.ofertas set estado = 'retirada', actualizado_en = now() where id = o.id;
  else raise exception 'Accion no valida'; end if;
end $$;

-- el proveedor propone un precio nuevo (o condiciones) sobre una de sus ofertas de catalogo
create or replace function public.portal_proponer_precio(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare pp public.proveedor_productos; v_t uuid; v_id uuid;
begin
  select * into pp from public.proveedor_productos where id = (p->>'pp_id')::uuid;
  if pp.id is null then raise exception 'Oferta no encontrada'; end if;
  v_t := public.mi_tercero(pp.empresa_id);
  if v_t is null or pp.tercero_id <> v_t then raise exception 'Sin acceso'; end if;
  if pp.estado = 'rechazado' then raise exception 'Esta oferta fue rechazada por compras.'; end if;
  update public.precios_propuestos set estado = 'rechazado', nota_resolucion = 'Reemplazada por una propuesta nueva', resuelto_en = now() where proveedor_producto_id = pp.id and estado = 'propuesto';
  insert into public.precios_propuestos (empresa_id, proveedor_producto_id, precio, iva_pct, vigente_desde, vigente_hasta, condicion_pago, plazo_dias, descuento_pronto_pago_pct, descuento_pronto_pago_dias, minimo_pedido, lugar_entrega, nota)
  values (pp.empresa_id, pp.id, (p->>'precio')::numeric, coalesce((p->>'iva_pct')::numeric, 0), coalesce(nullif(p->>'vigente_desde', '')::date, (now() at time zone 'America/Bogota')::date), nullif(p->>'vigente_hasta', '')::date, nullif(p->>'condicion_pago', ''), (p->>'plazo_dias')::int,
          (p->>'descuento_pronto_pago_pct')::numeric, (p->>'descuento_pronto_pago_dias')::int, (p->>'minimo_pedido')::numeric, coalesce(nullif(p->>'lugar_entrega', ''), 'cedi'), p->>'nota') returning id into v_id;
  insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
  values (pp.empresa_id, 'M3', 'baja', 'Precio propuesto por ' || (select coalesce(t.nombre_comercial, t.razon_social) from public.terceros t where t.id = v_t), (select nombre from public.productos where id = pp.producto_id) || ': $ ' || to_char((p->>'precio')::numeric, 'FM999G999G999G990'), '/precios?propuestos=1', 'precio_propuesto', v_id);
  return v_id;
end $$;

-- el proveedor propone un producto nuevo de su catalogo (queda 'propuesto' hasta que compras homologue)
create or replace function public.portal_ofrecer_producto(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare v_t uuid := public.mi_tercero((p->>'empresa_id')::uuid); v_emp uuid := (p->>'empresa_id')::uuid; v_marca uuid; v_pres uuid; v_pp uuid;
begin
  if v_t is null then raise exception 'Sin acceso'; end if;
  if nullif(trim(coalesce(p->>'marca', '')), '') is not null then insert into public.marcas (empresa_id, nombre) values (v_emp, trim(p->>'marca')) on conflict (empresa_id, nombre) do update set nombre = excluded.nombre returning id into v_marca; end if;
  if nullif(trim(coalesce(p->>'presentacion', '')), '') is not null then
    if coalesce((p->>'contenido')::numeric, 0) <= 0 then raise exception 'La presentacion necesita el contenido (g, ml o und por empaque).'; end if;
    insert into public.presentaciones (empresa_id, producto_id, nombre, contenido, unidad_empaque) values (v_emp, (p->>'producto_id')::uuid, trim(p->>'presentacion'), (p->>'contenido')::numeric, coalesce(p->>'unidad_empaque', 'und'))
    on conflict (empresa_id, producto_id, nombre) do update set contenido = excluded.contenido returning id into v_pres;
  end if;
  insert into public.proveedor_productos (empresa_id, tercero_id, producto_id, marca_id, presentacion_id, codigo_proveedor, lead_time_dias, entrega_en, origen, registro_sanitario, ficha_tecnica_id, estado, notas)
  values (v_emp, v_t, (p->>'producto_id')::uuid, v_marca, v_pres, p->>'codigo_proveedor', (p->>'lead_time_dias')::int, nullif(p->>'entrega_en', ''), nullif(p->>'origen', ''), p->>'registro_sanitario', nullif(p->>'ficha_tecnica_id', '')::uuid, 'propuesto', 'Propuesto por el proveedor en el portal')
  on conflict (tercero_id, producto_id, marca_id, presentacion_id) do update set ficha_tecnica_id = coalesce(excluded.ficha_tecnica_id, public.proveedor_productos.ficha_tecnica_id), registro_sanitario = coalesce(excluded.registro_sanitario, public.proveedor_productos.registro_sanitario)
  returning id into v_pp;
  if (p->>'precio') is not null then perform public.portal_proponer_precio(jsonb_build_object('pp_id', v_pp, 'precio', p->>'precio', 'iva_pct', p->>'iva_pct', 'condicion_pago', p->>'condicion_pago', 'plazo_dias', p->>'plazo_dias', 'lugar_entrega', p->>'entrega_en', 'nota', 'Producto nuevo ofrecido desde el portal')); end if;
  return v_pp;
end $$;

-- el proveedor confirma (o pide cambio de) una OC enviada
create or replace function public.portal_confirmar_oc(p_oc uuid, p_fecha date default null, p_nota text default null, p_acepta boolean default true) returns void language plpgsql security definer set search_path = public as $$
declare o public.ordenes_compra; v_t uuid;
begin
  select * into o from public.ordenes_compra where id = p_oc; v_t := public.mi_tercero(o.empresa_id);
  if v_t is null or o.tercero_id <> v_t then raise exception 'Sin acceso a esta OC'; end if;
  if o.estado <> 'enviada' then raise exception 'La OC esta %; solo se confirma una OC enviada.', o.estado; end if;
  if p_acepta then
    update public.ordenes_compra set estado = 'confirmada', confirmada_en = now(), fecha_entrega_confirmada = coalesce(p_fecha, o.fecha_entrega), observaciones_proveedor = p_nota, actualizado_en = now() where id = p_oc;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (o.empresa_id, 'M3', 'normal', 'OC ' || o.codigo || ' confirmada por el proveedor', 'Entrega el ' || to_char(coalesce(p_fecha, o.fecha_entrega), 'DD/MM/YYYY') || coalesce(' · ' || p_nota, ''), '/ordenes-compra?id=' || o.id, 'orden_compra', o.id);
  else
    update public.ordenes_compra set observaciones_proveedor = concat_ws(E'\n', 'PIDE CAMBIO' || coalesce(' (entrega ' || to_char(p_fecha, 'DD/MM/YYYY') || ')', '') || ': ' || coalesce(p_nota, 'sin detalle')), actualizado_en = now() where id = p_oc;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (o.empresa_id, 'M3', 'alta', 'OC ' || o.codigo || ': el proveedor pide un cambio', coalesce(p_nota, 'sin detalle'), '/ordenes-compra?id=' || o.id, 'orden_compra', o.id);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------
do $g$
declare f text;
begin
  foreach f in array array['invitar_usuario_proveedor(uuid, text, text, text)', 'desactivar_usuario_proveedor(uuid)', 'portal_documento(uuid, text, text, text, text, bigint, date, date, text)',
    'guardar_solicitud(jsonb)', 'estado_solicitud(uuid, text, text)', 'comparar_ofertas(uuid)', 'adjudicar_solicitud(uuid, jsonb, date, boolean)', 'solicitudes_lista(uuid)', 'resolver_precio_propuesto(uuid, boolean, text)', 'precios_propuestos_lista(uuid)',
    'portal_resumen(uuid)', 'portal_solicitud(uuid)', 'portal_vista(uuid)', 'portal_guardar_variante(jsonb)', 'portal_estado_oferta(uuid, text, date, text)', 'portal_proponer_precio(jsonb)', 'portal_ofrecer_producto(jsonb)', 'portal_confirmar_oc(uuid, date, text, boolean)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function public.%s to service_role', f); end if;
  end loop;
end $g$;
