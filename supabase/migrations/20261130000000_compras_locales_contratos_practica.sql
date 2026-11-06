-- Supply ERP · Migracion 030 · Compras publicas locales (Ley 2046 de 2020) por contrato
-- y contratos reales en modo practica.
--
-- 1. empresas.es_practica: marca explicita de empresa de practica (lo de "demo" en el nombre queda como respaldo).
-- 2. Parametros de compras locales en cada contrato:
--      meta_compras_locales_pct (30 por ley) + meta_compras_locales_extra_pct (lo que se ofrecio de mas en la oferta)
--      base_compras_locales: 'rubro_alimentos' (facturado x % del rubro de alimentos de la estructura de la racion,
--      ej. USPEC Anexo 25: G15 73,72 %, promedio nacional 72,83 %) o 'facturado_total' (PAE Atlantico: "30 % del valor
--      total facturado mensualmente", obligacion 48 de los contratos 202602581 y 202602582).
--      zona_compras_locales: departamentos donde cuenta la compra (PAE Atlantico: costa + Cundinamarca y Santanderes).
--      valor_racion_ref: valor de la racion de referencia (UT Alfa: $50.407).
-- 3. Terceros: proveedor Ley 2046 (pequeno productor, ACFC u organizacion), certificado y municipio del productor.
-- 4. compras_locales_soportes: compras locales cargadas a mano o importadas del consolidado (factura, OC, NIT, valor),
--    con los campos del formato oficial "Seguimiento compras publicas locales de alimentos vigencia 2026".
-- 5. compras_locales_tablero(): por contrato y mes (en curso y anteriores): facturado (o estimado), base, meta,
--    requerido, comprado local, cumplimiento y faltante.
-- 6. crear_contrato_practica(): arma una UT de practica con su entidad y contrato con datos reales.
-- 7. Siembra: los contratos reales de Fombisol y Alimentar Capital en modo practica.
set client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Empresa de practica
-- ---------------------------------------------------------------------
alter table public.empresas add column if not exists es_practica boolean not null default false;
update public.empresas set es_practica = true where nit in ('900000001', '900000002', '900000003') and es_practica = false;

create or replace function public.es_empresa_demo(p_empresa uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.empresas e where e.id = p_empresa
                    and (e.es_practica or e.nit ~ '^90000000\d$' or e.razon_social ilike '%demo%' or e.razon_social ilike '%practica%'));
$$;

-- ---------------------------------------------------------------------
-- 2. Parametros de compras locales por contrato
-- ---------------------------------------------------------------------
alter table public.contratos
  add column if not exists meta_compras_locales_pct numeric(5,2) not null default 30 check (meta_compras_locales_pct between 0 and 100),
  add column if not exists meta_compras_locales_extra_pct numeric(5,2) not null default 0 check (meta_compras_locales_extra_pct between 0 and 100),
  add column if not exists base_compras_locales text not null default 'rubro_alimentos' check (base_compras_locales in ('rubro_alimentos', 'facturado_total')),
  add column if not exists rubro_alimentos_pct numeric(5,2) check (rubro_alimentos_pct is null or rubro_alimentos_pct between 0 and 100),
  add column if not exists zona_compras_locales text[] not null default '{}',
  add column if not exists valor_racion_ref numeric(14,2) check (valor_racion_ref is null or valor_racion_ref > 0),
  add column if not exists fuente_parametros_cl text;           -- de donde sale cada dato (anexo, clausula, "por confirmar")

-- ---------------------------------------------------------------------
-- 3. Proveedor Ley 2046
-- ---------------------------------------------------------------------
alter table public.terceros
  add column if not exists ley2046 boolean not null default false,
  add column if not exists tipo_productor_local text check (tipo_productor_local is null or tipo_productor_local in ('pequeno_productor', 'acfc', 'organizacion_productores', 'otro')),
  add column if not exists ley2046_certificado_vence date,
  add column if not exists municipio_productor text;

create or replace function public.guardar_ley2046_tercero(p_tercero uuid, p_ley2046 boolean, p_tipo text default null,
                                                         p_vence date default null, p_municipio text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.terceros where id = p_tercero;
  if v_emp is null then raise exception 'Tercero no encontrado.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M3', 'crear')) then
    raise exception 'Sin permiso (Compras: crear).';
  end if;
  if p_ley2046 and p_tipo is null then raise exception 'Indique el tipo de productor local (pequeno productor, ACFC u organizacion).'; end if;
  update public.terceros
     set ley2046 = coalesce(p_ley2046, false),
         tipo_productor_local = case when p_ley2046 then p_tipo end,
         ley2046_certificado_vence = case when p_ley2046 then p_vence end,
         municipio_productor = coalesce(nullif(trim(p_municipio), ''), municipio_productor),
         actualizado_por = auth.uid(), actualizado_en = now()
   where id = p_tercero;
end $$;

create or replace function public.guardar_parametros_cl(p_contrato uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M1', 'crear')) then
    raise exception 'Sin permiso (Contratos: crear).';
  end if;
  update public.contratos c
     set meta_compras_locales_pct       = coalesce((p->>'meta_compras_locales_pct')::numeric, c.meta_compras_locales_pct),
         meta_compras_locales_extra_pct = coalesce((p->>'meta_compras_locales_extra_pct')::numeric, c.meta_compras_locales_extra_pct),
         base_compras_locales           = coalesce(p->>'base_compras_locales', c.base_compras_locales),
         rubro_alimentos_pct            = case when p ? 'rubro_alimentos_pct' then (p->>'rubro_alimentos_pct')::numeric else c.rubro_alimentos_pct end,
         zona_compras_locales           = case when p ? 'zona_compras_locales' then array(select jsonb_array_elements_text(p->'zona_compras_locales')) else c.zona_compras_locales end,
         valor_racion_ref               = case when p ? 'valor_racion_ref' then (p->>'valor_racion_ref')::numeric else c.valor_racion_ref end,
         fuente_parametros_cl           = coalesce(p->>'fuente_parametros_cl', c.fuente_parametros_cl),
         actualizado_por = auth.uid(), actualizado_en = now()
   where c.id = p_contrato;
end $$;

-- ---------------------------------------------------------------------
-- 4. Soportes de compras locales (carga manual o importada)
-- ---------------------------------------------------------------------
create table if not exists public.compras_locales_soportes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  contrato_id uuid not null references public.contratos(id),
  periodo date not null check (periodo = date_trunc('month', periodo)::date),   -- primer dia del mes
  tercero_id uuid references public.terceros(id),
  oc_id uuid references public.ordenes_compra(id),          -- si viene de una OC de la plataforma, la OC no se suma dos veces
  proveedor_nit text,
  proveedor_nombre text not null,
  tipo_proveedor text,
  factura text,                                               -- No. factura / recibo / soporte
  fecha_compra date,
  oc_codigo text,
  tipo_producto text,                                         -- Fresco, Procesado
  alimento text,
  especie_variedad text,
  cantidad numeric,
  unidad text,
  valor numeric(16,2) not null check (valor >= 0),
  ley2046 boolean not null default false,
  lugar_productor text,                                       -- municipio / departamento del productor
  origen text not null default 'manual' check (origen in ('manual', 'importado', 'oc')),
  notas text,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz not null default now()
);
create index if not exists cls_contrato_periodo_idx on public.compras_locales_soportes (contrato_id, periodo);
create index if not exists cls_empresa_idx on public.compras_locales_soportes (empresa_id);
create index if not exists cls_oc_idx on public.compras_locales_soportes (oc_id) where oc_id is not null;

-- el contrato y la OC deben ser de la misma empresa
create or replace function public.cls_validar() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.contratos where id = new.contrato_id and empresa_id = new.empresa_id) then
    raise exception 'El contrato no pertenece a la empresa.';
  end if;
  if new.tercero_id is not null and not exists (select 1 from public.terceros where id = new.tercero_id and empresa_id = new.empresa_id) then
    raise exception 'El proveedor no pertenece a la empresa.';
  end if;
  if new.oc_id is not null and not exists (select 1 from public.ordenes_compra where id = new.oc_id and empresa_id = new.empresa_id) then
    raise exception 'La OC no pertenece a la empresa.';
  end if;
  new.actualizado_en := now();
  return new;
end $$;
drop trigger if exists cls_validar on public.compras_locales_soportes;
create trigger cls_validar before insert or update on public.compras_locales_soportes for each row execute function public.cls_validar();
drop trigger if exists cls_bitacora on public.compras_locales_soportes;
create trigger cls_bitacora after insert or update or delete on public.compras_locales_soportes for each row execute function public.registrar_bitacora();

alter table public.compras_locales_soportes enable row level security;
drop policy if exists cls_ver on public.compras_locales_soportes;
create policy cls_ver on public.compras_locales_soportes for select to authenticated
  using (public.es_superadmin() or empresa_id in (select public.mis_empresas_internas()));
drop policy if exists cls_crear on public.compras_locales_soportes;
create policy cls_crear on public.compras_locales_soportes for insert to authenticated
  with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M3', 'crear'));
drop policy if exists cls_editar on public.compras_locales_soportes;
create policy cls_editar on public.compras_locales_soportes for update to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M3', 'crear'))
  with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M3', 'crear'));
drop policy if exists cls_borrar on public.compras_locales_soportes;
create policy cls_borrar on public.compras_locales_soportes for delete to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M3', 'crear'));
revoke all on public.compras_locales_soportes from public, anon;
grant select, insert, update, delete on public.compras_locales_soportes to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then grant all on public.compras_locales_soportes to service_role; end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Tablero de compras locales: por contrato y mes
--    requerido = (meta + extra) % x base;  base = facturado x rubro % (o facturado total, segun el contrato)
--    facturado: contrato_ejecucion del mes; si no esta cargado, promedio de los ultimos 3 meses facturados (estimado)
--    comprado local: OC (no borrador ni anulada) a proveedores Ley 2046 + soportes Ley 2046 del mes
-- ---------------------------------------------------------------------
create or replace function public.compras_locales_tablero(p_empresa uuid default null, p_meses int default 3, p_hasta date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_hasta date := date_trunc('month', coalesce(p_hasta, (now() at time zone 'America/Bogota')::date))::date;
        v_meses int := least(greatest(coalesce(p_meses, 3), 1), 12);
        v_out jsonb;
begin
  if p_empresa is not null and not (public.es_admin_sql() or public.es_superadmin() or p_empresa in (select public.mis_empresas_internas())) then
    raise exception 'Sin acceso a esa empresa.';
  end if;
  with ct as (
    select c.*, e.nombre_corto as empresa_nombre, e.es_practica
      from public.contratos c join public.empresas e on e.id = c.empresa_id
     where c.estado in ('vigente', 'suspendido', 'liquidacion')
       and (p_empresa is null or c.empresa_id = p_empresa)
       and (public.es_admin_sql() or public.es_superadmin() or c.empresa_id in (select public.mis_empresas_internas()))
  ), meses as (
    select (v_hasta - make_interval(months => g))::date as periodo from generate_series(0, v_meses - 1) g
  ), base as (
    select ct.id as contrato_id, ct.numero, ct.codigo, ct.empresa_id, ct.empresa_nombre, ct.es_practica, ct.modalidad,
           ct.meta_compras_locales_pct + ct.meta_compras_locales_extra_pct as meta_pct, ct.meta_compras_locales_extra_pct as extra_pct,
           ct.base_compras_locales, ct.rubro_alimentos_pct, m.periodo,
           ej.valor_facturado as facturado_real,
           (select round(avg(x.valor_facturado), 2) from (select e2.valor_facturado from public.contrato_ejecucion e2
                                                 where e2.contrato_id = ct.id and e2.periodo < m.periodo and e2.valor_facturado > 0
                                                 order by e2.periodo desc limit 3) x) as facturado_prom
      from ct cross join meses m
      left join public.contrato_ejecucion ej on ej.contrato_id = ct.id and ej.periodo = m.periodo
     where m.periodo >= date_trunc('month', ct.fecha_inicio)::date
  ), compras as (
    select b.contrato_id, b.periodo,
           coalesce((select sum(o.total) from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id
                      where o.contrato_id = b.contrato_id and t.ley2046 and o.estado not in ('borrador', 'anulada')
                        and date_trunc('month', o.fecha_emision)::date = b.periodo
                        and not exists (select 1 from public.compras_locales_soportes s where s.oc_id = o.id)), 0)
         + coalesce((select sum(s.valor) from public.compras_locales_soportes s
                      where s.contrato_id = b.contrato_id and s.periodo = b.periodo and s.ley2046), 0) as local,
           coalesce((select sum(o.total) from public.ordenes_compra o
                      where o.contrato_id = b.contrato_id and o.estado not in ('borrador', 'anulada')
                        and date_trunc('month', o.fecha_emision)::date = b.periodo
                        and not exists (select 1 from public.compras_locales_soportes s where s.oc_id = o.id)), 0)
         + coalesce((select sum(s.valor) from public.compras_locales_soportes s
                      where s.contrato_id = b.contrato_id and s.periodo = b.periodo), 0) as total
      from base b
  ), calc as (
    select b.*, c.local, c.total,
           coalesce(b.facturado_real, b.facturado_prom) as facturado,
           b.facturado_real is null and b.facturado_prom is not null as facturado_estimado,
           case when b.base_compras_locales = 'facturado_total' then coalesce(b.facturado_real, b.facturado_prom)
                when b.rubro_alimentos_pct is not null then round(coalesce(b.facturado_real, b.facturado_prom) * b.rubro_alimentos_pct / 100, 2) end as base_valor
      from base b join compras c on c.contrato_id = b.contrato_id and c.periodo = b.periodo
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'contrato_id', contrato_id, 'numero', numero, 'codigo', codigo, 'empresa_id', empresa_id, 'empresa', empresa_nombre,
           'practica', es_practica, 'modalidad', modalidad, 'periodo', periodo,
           'facturado', facturado, 'facturado_estimado', facturado_estimado,
           'base_tipo', base_compras_locales, 'rubro_pct', rubro_alimentos_pct, 'base', base_valor,
           'meta_pct', meta_pct, 'extra_pct', extra_pct,
           'requerido', round(base_valor * meta_pct / 100, 2),
           'comprado_local', local, 'comprado_total', total,
           'pct_local_de_compras', case when total > 0 then round(local / total * 100, 1) end,
           'cumplimiento_pct', case when base_valor > 0 then round(local / (base_valor * meta_pct / 100) * 100, 1) end,
           'pct_sobre_base', case when base_valor > 0 then round(local / base_valor * 100, 2) end,
           'faltante', case when base_valor is not null then greatest(round(base_valor * meta_pct / 100 - local, 2), 0) end,
           'alerta', case when base_compras_locales = 'rubro_alimentos' and rubro_alimentos_pct is null then 'Falta el % del rubro de alimentos del contrato'
                          when facturado is null then 'Falta el facturado del mes (Contratos > Ejecucion)' end
         ) order by empresa_nombre, numero, periodo desc), '[]'::jsonb)
    into v_out from calc;
  return v_out;
end $$;

revoke all on function public.compras_locales_tablero(uuid, int, date), public.guardar_ley2046_tercero(uuid, boolean, text, date, text),
                       public.guardar_parametros_cl(uuid, jsonb), public.es_empresa_demo(uuid) from public, anon;
grant execute on function public.compras_locales_tablero(uuid, int, date), public.guardar_ley2046_tercero(uuid, boolean, text, date, text),
                          public.guardar_parametros_cl(uuid, jsonb), public.es_empresa_demo(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Contrato real en modo practica: crea (o reutiliza) la UT de practica, la entidad y el contrato
-- ---------------------------------------------------------------------
create or replace function public.crear_contrato_practica(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_ent uuid; v_ct uuid; v_g uuid;
begin
  if not (public.es_admin_sql() or public.es_superadmin()) then raise exception 'Solo el administrador de la plataforma crea contratos de practica.'; end if;
  if coalesce(p->>'nit_practica', '') !~ '^9000001\d\d$' then raise exception 'El NIT de practica debe ser 9000001NN.'; end if;
  select id into v_emp from public.empresas where nit = p->>'nit_practica';
  if v_emp is null then
    v_emp := public.alta_empresa(p->>'ut' || ' (practica)', p->>'nit_practica', public.dv_nit(p->>'nit_practica')::text, coalesce(p->>'ciudad', 'Barranquilla'),
                                 p->>'ut' || ' (practica)', 'union_temporal', null, 'CEDI de practica', '{}'::jsonb);
  end if;
  update public.empresas set es_practica = true where id = v_emp and es_practica = false;
  select id into v_g from public.grupos where nombre = 'Grupo de practica';
  if v_g is not null then update public.empresas set grupo_id = v_g where id = v_emp and grupo_id is null; end if;

  select id into v_ent from public.entidades_contratantes where empresa_id = v_emp and nombre = p->>'entidad';
  if v_ent is null then
    insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad) values (v_emp, p->>'entidad', coalesce(p->>'tipo_entidad', 'otra'), p->>'ciudad')
    returning id into v_ent;
  end if;
  select id into v_ct from public.contratos where empresa_id = v_emp and entidad_id = v_ent and numero = p->>'numero';
  if v_ct is null then
    v_ct := public.crear_contrato(jsonb_build_object('empresa_id', v_emp, 'numero', p->>'numero', 'entidad_id', v_ent, 'modalidad', p->>'modalidad',
      'objeto', p->>'objeto', 'proceso_secop', p->>'proceso', 'valor_inicial', coalesce((p->>'valor')::numeric, 1), 'incluye_iva', false,
      'fecha_suscripcion', coalesce(p->>'suscripcion', '2026-01-15'), 'fecha_inicio', coalesce(p->>'inicio', '2026-02-01'),
      'fecha_fin_inicial', coalesce(p->>'fin', '2026-12-31'), 'dias_atencion', coalesce(p->>'dias_atencion', 'habiles'),
      'tiempos_comida', coalesce((p->>'tiempos')::int, 1), 'estado', coalesce(p->>'estado', 'vigente'),
      'notas', 'PRACTICA con datos reales. ' || coalesce(p->>'notas', '')));
  end if;
  perform public.guardar_parametros_cl(v_ct, jsonb_strip_nulls(jsonb_build_object(
    'meta_compras_locales_pct', coalesce((p->>'meta')::numeric, 30), 'meta_compras_locales_extra_pct', coalesce((p->>'extra')::numeric, 0),
    'base_compras_locales', coalesce(p->>'base', 'rubro_alimentos'), 'rubro_alimentos_pct', (p->>'rubro')::numeric,
    'zona_compras_locales', p->'zona', 'valor_racion_ref', (p->>'racion')::numeric, 'fuente_parametros_cl', p->>'fuente')));
  return v_ct;
end $$;
revoke all on function public.crear_contrato_practica(jsonb) from public, anon;
grant execute on function public.crear_contrato_practica(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Siembra: contratos reales en modo practica (valor 1 = valor por confirmar)
-- ---------------------------------------------------------------------
do $$
declare z_costa text[] := array['Atlantico', 'Magdalena', 'Bolivar', 'Cesar', 'La Guajira', 'Sucre', 'Cordoba', 'San Andres y Providencia', 'Cundinamarca', 'Santander', 'Norte de Santander'];
        r jsonb;
begin
  for r in select * from jsonb_array_elements(jsonb_build_array(
    jsonb_build_object('nit_practica', '900000101', 'ut', 'UT Capital USPEC 2025', 'ciudad', 'Bogota', 'entidad', 'USPEC', 'tipo_entidad', 'uspec',
      'numero', 'CAPITAL-USPEC-2025 (por confirmar)', 'modalidad', 'uspec_ppl', 'tiempos', 4, 'dias_atencion', 'todos',
      'objeto', 'Suministro de alimentacion a PPL, establecimientos de Bogota y Cundinamarca-Boyaca (racion de 4 tiempos; valor por tipo de establecimiento: grandes mas baratas, remotas y estaciones con transporte mas caras)',
      'rubro', 72.83, 'fuente', 'Rubro: Anexo 25 promedio nacional 72,83 % (Osvaldo dijo ~72 %); confirmar el % del grupo de Capital. Numero, valor y fechas por confirmar con Wilson.'),
    jsonb_build_object('nit_practica', '900000102', 'ut', 'UT Alfa', 'ciudad', 'Bogota', 'entidad', 'Secretaria Distrital de Seguridad, Convivencia y Justicia', 'tipo_entidad', 'alcaldia',
      'numero', 'SCJ-1921-2026', 'modalidad', 'otro', 'tiempos', 4, 'dias_atencion', 'todos', 'valor', 42186012028, 'racion', 50407,
      'suscripcion', '2026-09-15', 'inicio', '2026-10-01', 'fin', '2027-07-27',
      'objeto', 'Racion diaria unipersonal (desayuno, almuerzo, cena y refrigerio) preparada en planta y transportada a EP, URI y CDT de Bogota; 299 dias o hasta agotar',
      'fuente', 'Contrato SCJ-1921-2026 (Drive). Fechas aproximadas: confirmar acta de inicio. Rubro de alimentos por confirmar (obligaciones 27 y 28: Ley 2046, pago contra entrega).'),
    jsonb_build_object('nit_practica', '900000103', 'ut', 'UT Nutrifood', 'entidad', 'Gobernacion del Atlantico', 'tipo_entidad', 'gobernacion',
      'numero', '202604177', 'modalidad', 'pae', 'base', 'facturado_total', 'zona', to_jsonb(z_costa),
      'objeto', 'PAE Atlantico Grupo 1 2026 (reemplaza a UT Atlantic)',
      'fuente', 'Se asume la misma clausula de UT Atlantic (30 % del facturado mensual, zona costa + Cundinamarca y Santanderes); confirmar en el clausulado. Valor y fechas por confirmar.'),
    jsonb_build_object('nit_practica', '900000104', 'ut', 'UT Atlantic', 'entidad', 'Gobernacion del Atlantico', 'tipo_entidad', 'gobernacion',
      'numero', '202602581', 'proceso', 'LP-0004-2026', 'modalidad', 'pae', 'base', 'facturado_total', 'zona', to_jsonb(z_costa), 'estado', 'liquidacion',
      'fin', '2026-09-15', 'objeto', 'PAE Atlantico Zona 1 (agotado el 15-sep-2026, en cierre)',
      'fuente', 'Obligacion 48: 30 % del valor total facturado mensualmente; zona geografica (correo de la Gobernacion, 6-oct-2026).'),
    jsonb_build_object('nit_practica', '900000104', 'ut', 'UT Atlantic', 'entidad', 'Gobernacion del Atlantico', 'tipo_entidad', 'gobernacion',
      'numero', '202602582', 'proceso', 'LP-0004-2026', 'modalidad', 'pae', 'base', 'facturado_total', 'zona', to_jsonb(z_costa), 'estado', 'liquidacion',
      'fin', '2026-09-08', 'objeto', 'PAE Atlantico Zona 2 (agotado el 8-sep-2026, en cierre)',
      'fuente', 'Obligacion 48: 30 % del valor total facturado mensualmente; zona geografica (correo de la Gobernacion, 6-oct-2026).'),
    jsonb_build_object('nit_practica', '900000105', 'ut', 'UT Alianza Integral', 'ciudad', 'Soledad', 'entidad', 'Alcaldia de Soledad', 'tipo_entidad', 'alcaldia',
      'numero', 'PAE-SOLEDAD-2026 (por confirmar)', 'modalidad', 'pae', 'objeto', 'PAE Soledad 2026',
      'fuente', 'Contrato PAE2026.pdf en Drive; numero, valor, % y base por confirmar.'),
    jsonb_build_object('nit_practica', '900000106', 'ut', 'UT Malambo', 'ciudad', 'Malambo', 'entidad', 'Alcaldia de Malambo', 'tipo_entidad', 'alcaldia',
      'numero', 'PAE-MALAMBO-2026 (por confirmar)', 'modalidad', 'pae', 'objeto', 'PAE Malambo 2026',
      'fuente', 'CONTRATO.pdf en Drive; numero, valor, % y base por confirmar.'),
    jsonb_build_object('nit_practica', '900000107', 'ut', 'UT Cenit', 'ciudad', 'Cienaga', 'entidad', 'Municipio de Cienaga (Magdalena)', 'tipo_entidad', 'alcaldia',
      'numero', '003-C23-1600-2026', 'proceso', 'LP 002-2026', 'modalidad', 'pae', 'valor', 9261946604, 'suscripcion', '2026-07-03', 'inicio', '2026-07-15', 'fin', '2026-12-15',
      'objeto', 'Complemento alimentario PAE Cienaga: 64 dias escolares JM/JT y almuerzo; internados 84 dias calendario o hasta agotar',
      'fuente', 'Pagina 1 del contrato y Resolucion RES-DIR-EST-0959-2026 (correo de Carlos Yepes, 14-oct-2026). Fechas de inicio aproximadas; % y base por confirmar.'),
    jsonb_build_object('nit_practica', '900000108', 'ut', 'UT Bienestar Corporativo', 'ciudad', 'Covenas', 'entidad', 'Armada Nacional ARC Covenas', 'tipo_entidad', 'fuerzas',
      'numero', 'ARC-COVENAS-2026 (por confirmar)', 'modalidad', 'fuerzas_casino', 'tiempos', 4, 'dias_atencion', 'todos', 'objeto', 'Alimentacion Armada ARC Covenas',
      'fuente', 'CONTRATO ARC.pdf en Drive; datos por confirmar.'),
    jsonb_build_object('nit_practica', '900000109', 'ut', 'UT Brigadistas', 'entidad', 'Entidad SA-005-2026 (por confirmar)', 'tipo_entidad', 'otra',
      'numero', 'SA-005-2026', 'modalidad', 'bomberos', 'objeto', 'Alimentacion de brigadistas / bomberos',
      'fuente', 'Clausulado y oferta economica en Drive; datos por confirmar.'),
    jsonb_build_object('nit_practica', '900000110', 'ut', 'UT CDR', 'entidad', 'Entidad LP-006-2026 (por confirmar)', 'tipo_entidad', 'otra',
      'numero', 'LP-006-2026', 'modalidad', 'uspec_ppl', 'tiempos', 4, 'dias_atencion', 'todos', 'objeto', 'Alimentacion carceles Barranquilla',
      'fuente', 'Clausulado y oferta economica carceles en Drive; datos por confirmar.'),
    jsonb_build_object('nit_practica', '900000111', 'ut', 'UT Altis', 'entidad', 'Entidad URIs / carceles (por confirmar)', 'tipo_entidad', 'otra',
      'numero', 'ALTIS-2026 (por confirmar)', 'modalidad', 'uspec_ppl', 'tiempos', 4, 'dias_atencion', 'todos', 'objeto', 'Alimentacion URIs y carceles Barranquilla',
      'fuente', 'Contrato no ubicado (ni Drive ni correo). Pedir a Yesid.'),
    jsonb_build_object('nit_practica', '900000112', 'ut', 'UT Proposito Superior', 'entidad', 'Entidad SA-008-2026 (por confirmar)', 'tipo_entidad', 'otra',
      'numero', 'SA-008-2026', 'modalidad', 'otro', 'objeto', 'Por confirmar',
      'fuente', 'Clausulado en Drive; datos por confirmar.')
  )) loop
    perform public.crear_contrato_practica(r);
  end loop;

  -- UT Diestra (real): parametros conocidos del Anexo 25
  update public.contratos
     set rubro_alimentos_pct = 73.72, base_compras_locales = 'rubro_alimentos',
         fuente_parametros_cl = 'Anexo 25 USPEC 2022, grupo 15: alimentos 73,72 %. Meta 30 %; confirmar si la oferta sumo puntos adicionales.'
   where numero = 'USPEC-CTO-199-2025' and rubro_alimentos_pct is null;
end $$;
