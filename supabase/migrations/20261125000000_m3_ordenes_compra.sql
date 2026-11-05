-- =====================================================================
-- Supply ERP · Migracion 025 · M3 parte 2: ordenes de compra
--   · OC con lugar de entrega (CEDI o directo en la sede / establecimiento), consecutivo OC, estados y items.
--   · Sugerencia de compra desde un requerimiento aprobado: por producto, la mejor opcion disponible
--     (homologada, sin bloqueo, precio vigente) con prioridad contractual del proyecto productivo del INPEC
--     en su propio establecimiento y entrega directa cuando el proveedor entrega en sede.
--   · Generacion de OC en borrador agrupando por proveedor + lugar de entrega; aprobar / enviar / anular / cerrar.
--   · Columnas en precios para las condiciones alternativas que llegaran del portal (M4): plazo, pronto pago, minimo, estado.
-- Reglas de la casa: SECURITY DEFINER + tiene_permiso, es_admin_sql(), WHERE en todo update, grants explicitos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. precios: condiciones alternativas (las usa el portal M4; hoy todo queda 'aceptado')
-- ---------------------------------------------------------------------
alter table public.precios add column if not exists plazo_dias int;
alter table public.precios add column if not exists descuento_pronto_pago_pct numeric check (descuento_pronto_pago_pct is null or descuento_pronto_pago_pct between 0 and 100);
alter table public.precios add column if not exists descuento_pronto_pago_dias int;
alter table public.precios add column if not exists minimo_pedido numeric;
alter table public.precios add column if not exists estado text not null default 'aceptado' check (estado in ('propuesto', 'aceptado', 'rechazado'));
alter table public.precios add column if not exists oferta_linea_id uuid;   -- M4: de que variante de oferta salio

-- ---------------------------------------------------------------------
-- 1. Ordenes de compra
-- ---------------------------------------------------------------------
create table if not exists public.ordenes_compra (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  codigo text not null,
  tercero_id uuid not null references public.terceros(id),
  explosion_id uuid references public.explosiones(id),          -- requerimiento de origen (null = OC manual)
  contrato_id uuid references public.contratos(id),
  lugar_entrega text not null default 'cedi' check (lugar_entrega in ('cedi', 'sede')),
  sede_entrega_id uuid references public.sedes(id),              -- CEDI / bodega, o la unidad de servicio
  contrato_sede_id uuid references public.contrato_sedes(id),    -- cuando se entrega directo en el establecimiento
  fecha_emision date not null default (now() at time zone 'America/Bogota')::date,
  fecha_entrega date,
  condicion_pago text check (condicion_pago is null or condicion_pago in ('contado', 'anticipo', 'credito')),
  plazo_dias int,
  moneda text not null default 'COP',
  subtotal numeric not null default 0,
  iva numeric not null default 0,
  total numeric not null default 0,
  estado text not null default 'borrador' check (estado in ('borrador', 'aprobada', 'enviada', 'confirmada', 'recibida_parcial', 'cerrada', 'anulada')),
  motivo_anulacion text,
  notas text,                       -- para el proveedor (va en la OC)
  notas_internas text,
  aprobada_por uuid, aprobada_en timestamptz,
  enviada_por uuid, enviada_en timestamptz,
  confirmada_en timestamptz, fecha_entrega_confirmada date, observaciones_proveedor text,
  cerrada_en timestamptz,
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz not null default now(),
  unique (empresa_id, codigo)
);
create index if not exists oc_empresa_idx on public.ordenes_compra (empresa_id, fecha_emision desc);
create index if not exists oc_tercero_idx on public.ordenes_compra (tercero_id, estado);
create index if not exists oc_explosion_idx on public.ordenes_compra (explosion_id);

create table if not exists public.oc_items (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  oc_id uuid not null references public.ordenes_compra(id) on delete cascade,
  producto_id uuid not null references public.productos(id),
  proveedor_producto_id uuid references public.proveedor_productos(id),
  descripcion text not null,            -- producto · marca · presentacion (foto al momento de la OC)
  unidad_pedido text not null,          -- bulto 50 kg, caja, kg...
  contenido_base numeric not null default 1,   -- unidades base por unidad de pedido (g, ml, und)
  cantidad numeric not null check (cantidad > 0),
  cantidad_base numeric not null,              -- cantidad * contenido_base (lo que cubre del requerimiento)
  precio numeric not null default 0 check (precio >= 0),   -- por unidad de pedido, sin IVA
  iva_pct numeric not null default 0,
  subtotal numeric not null default 0,
  iva numeric not null default 0,
  total numeric not null default 0,
  cantidad_recibida numeric not null default 0,
  requerida_base numeric,               -- lo que pedia el requerimiento para este proveedor (en unidad base)
  motivo text,                          -- por que este proveedor: INPEC prioritario, preferido, mejor precio, unica opcion, manual
  notas text,
  creado_en timestamptz not null default now()
);
create index if not exists oc_items_oc_idx on public.oc_items (oc_id);
create index if not exists oc_items_producto_idx on public.oc_items (empresa_id, producto_id);

-- totales de la linea y de la cabecera
create or replace function public.oc_items_antes() returns trigger language plpgsql as $$
begin
  new.cantidad_base := new.cantidad * coalesce(new.contenido_base, 1);
  new.subtotal := round(new.cantidad * new.precio, 2);
  new.iva := round(new.subtotal * coalesce(new.iva_pct, 0) / 100, 2);
  new.total := new.subtotal + new.iva;
  return new;
end $$;
drop trigger if exists oc_items_antes on public.oc_items;
create trigger oc_items_antes before insert or update on public.oc_items for each row execute function public.oc_items_antes();

create or replace function public.oc_totales() returns trigger language plpgsql security definer set search_path = public as $$
declare v_oc uuid := coalesce(new.oc_id, old.oc_id);
begin
  update public.ordenes_compra o set subtotal = t.s, iva = t.i, total = t.s + t.i, actualizado_en = now()
    from (select coalesce(sum(subtotal), 0) s, coalesce(sum(iva), 0) i from public.oc_items where oc_id = v_oc) t
   where o.id = v_oc;
  return null;
end $$;
drop trigger if exists oc_totales on public.oc_items;
create trigger oc_totales after insert or update or delete on public.oc_items for each row execute function public.oc_totales();

do $p$
declare t text;
begin
  foreach t in array array['ordenes_compra', 'oc_items'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_ver', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id))', t || '_ver', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $p$;

-- ---------------------------------------------------------------------
-- 2. Sugerencia de compra desde un requerimiento
--    Por producto: cantidad total del requerimiento (unidad base y de compra), por establecimiento, y la asignacion
--    propuesta: (a) el proyecto productivo del INPEC cubre lo de SU establecimiento si lo ofrece homologado con precio;
--    (b) el resto va a la mejor opcion: preferido primero, luego menor precio por unidad base, entre homologados o
--    condicionados, sin bloqueo, con precio vigente. Si el proveedor entrega solo en sede, se propone entrega directa
--    por establecimiento; si entrega en CEDI (o ambos), una sola entrega al CEDI.
-- ---------------------------------------------------------------------
create or replace function public.sugerir_compra(p_explosion uuid, p_fecha date default null)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare e public.explosiones; v_f date; v_cedi uuid;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null or not public.puede_compras(e.empresa_id, 'ver') then raise exception 'Sin permiso'; end if;
  v_f := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
  select id into v_cedi from public.sedes where empresa_id = e.empresa_id and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1;
  return jsonb_build_object(
    'explosion', jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'estado', e.estado, 'tipo', e.tipo, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta, 'raciones', e.raciones, 'contrato_id', e.contrato_id),
    'cedi_id', v_cedi,
    'ordenes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'total', o.total, 'items', (select count(*) from public.oc_items i where i.oc_id = o.id)) order by o.codigo), '[]')
                  from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id where o.explosion_id = e.id and o.estado <> 'anulada'),
    'productos', (
      with req as (
        select d.producto_id, d.contrato_sede_id, sum(d.cantidad_bruta) base
          from public.explosion_detalle d where d.explosion_id = p_explosion group by 1, 2),
      tot as (select producto_id, sum(base) base from req group by 1),
      ya as (  -- lo que ya esta en OC no anuladas de este requerimiento
        select i.producto_id, sum(i.cantidad_base) base from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id
         where o.explosion_id = p_explosion and o.estado <> 'anulada' group by 1),
      ofertas as (
        select pp.id pp_id, pp.producto_id, t.id tercero_id, coalesce(t.nombre_comercial, t.razon_social) proveedor, t.proyecto_productivo, t.contrato_sede_id inpec_sede,
               pp.preferido, pp.estado, m.nombre marca, pr.nombre presentacion, coalesce(pr.contenido, p.factor_compra, 1) contenido, coalesce(pr.unidad_empaque, p.unidad_compra) unidad_pedido,
               coalesce(pp.entrega_en, t.entrega_en) entrega_en, coalesce(pp.lead_time_dias, t.lead_time_dias) lead_time, t.condicion_pago, t.plazo_dias,
               x.id precio_id, x.precio, x.por_unidad_base, x.iva_pct, x.lugar_entrega precio_lugar,
               public.tercero_bloqueado(t.id, v_f) bloqueado
          from public.proveedor_productos pp
          join public.terceros t on t.id = pp.tercero_id
          join public.productos p on p.id = pp.producto_id
          left join public.marcas m on m.id = pp.marca_id
          left join public.presentaciones pr on pr.id = pp.presentacion_id
          left join lateral (select * from public.precios x where x.proveedor_producto_id = pp.id and x.estado = 'aceptado' and x.vigente_desde <= v_f and (x.vigente_hasta is null or x.vigente_hasta >= v_f) order by x.vigente_desde desc limit 1) x on true
         where pp.empresa_id = e.empresa_id and pp.producto_id in (select producto_id from tot) and pp.estado in ('homologado', 'condicionado') and t.estado = 'activo'),
      elegibles as (select * from ofertas where not bloqueado and precio is not null),
      -- (a) INPEC: cubre lo de su propio establecimiento (si ese establecimiento esta en el requerimiento)
      inpec as (
        select distinct on (r.producto_id, r.contrato_sede_id) r.producto_id, r.contrato_sede_id, r.base, o.pp_id, o.tercero_id, o.proveedor, o.preferido, o.marca, o.presentacion, o.contenido, o.unidad_pedido, o.lead_time, o.condicion_pago, o.plazo_dias, o.precio_id, o.precio, o.por_unidad_base, o.iva_pct
          from req r join elegibles o on o.producto_id = r.producto_id and o.proyecto_productivo and o.inpec_sede = r.contrato_sede_id
         order by r.producto_id, r.contrato_sede_id, o.preferido desc, o.por_unidad_base),
      resto as (  -- lo que no cubre INPEC, por establecimiento
        select r.producto_id, r.contrato_sede_id, r.base from req r
         where not exists (select 1 from inpec i where i.producto_id = r.producto_id and i.contrato_sede_id = r.contrato_sede_id)),
      mejor as (  -- la mejor opcion general por producto
        select distinct on (producto_id) * from elegibles where not proyecto_productivo or inpec_sede is null
         order by producto_id, preferido desc, por_unidad_base, lead_time nulls last),
      mejor2 as (  -- si solo quedan INPEC de otros establecimientos, igual sirven
        select distinct on (producto_id) * from elegibles order by producto_id, preferido desc, por_unidad_base)
      select coalesce(jsonb_agg(jsonb_build_object(
          'producto_id', p.id, 'codigo', p.codigo, 'producto', p.nombre, 'categoria', p.categoria, 'perecedero', p.perecedero,
          'unidad_base', p.unidad_base, 'unidad_compra', p.unidad_compra, 'factor_compra', p.factor_compra,
          'requerido_base', t.base, 'requerido_compra', round(t.base / nullif(p.factor_compra, 0), 2),
          'ya_en_oc_base', coalesce(y.base, 0), 'ya_en_oc_compra', round(coalesce(y.base, 0) / nullif(p.factor_compra, 0), 2),
          'n_ofertas', (select count(*) from ofertas o where o.producto_id = p.id),
          'n_elegibles', (select count(*) from elegibles o where o.producto_id = p.id),
          'asignaciones', (
            select coalesce(jsonb_agg(a order by (a->>'motivo') = 'INPEC prioritario' desc, a->>'proveedor'), '[]') from (
              -- INPEC por establecimiento (entrega directa en su establecimiento)
              select jsonb_build_object('tercero_id', i.tercero_id, 'proveedor', i.proveedor, 'pp_id', i.pp_id, 'precio_id', i.precio_id, 'marca', i.marca, 'presentacion', i.presentacion, 'unidad_pedido', i.unidad_pedido, 'contenido', i.contenido,
                       'precio', i.precio, 'por_compra', round(i.por_unidad_base * coalesce(p.factor_compra, 1), 2), 'iva_pct', i.iva_pct, 'condicion_pago', i.condicion_pago, 'plazo_dias', i.plazo_dias, 'lead_time', i.lead_time,
                       'cantidad_base', i.base, 'cantidad', ceil(i.base / i.contenido), 'lugar_entrega', 'sede', 'contrato_sede_id', i.contrato_sede_id, 'sede', s.nombre, 'motivo', 'INPEC prioritario', 'inpec', true) a
                from inpec i join public.contrato_sedes cs on cs.id = i.contrato_sede_id join public.sedes s on s.id = cs.sede_id where i.producto_id = p.id
              union all
              -- resto: mejor opcion; si entrega solo en sede, una asignacion por establecimiento, si no, una al CEDI
              select case when mo.entrega_en = 'sede' then
                       jsonb_build_object('tercero_id', mo.tercero_id, 'proveedor', mo.proveedor, 'pp_id', mo.pp_id, 'precio_id', mo.precio_id, 'marca', mo.marca, 'presentacion', mo.presentacion, 'unidad_pedido', mo.unidad_pedido, 'contenido', mo.contenido,
                         'precio', mo.precio, 'por_compra', round(mo.por_unidad_base * coalesce(p.factor_compra, 1), 2), 'iva_pct', mo.iva_pct, 'condicion_pago', mo.condicion_pago, 'plazo_dias', mo.plazo_dias, 'lead_time', mo.lead_time,
                         'cantidad_base', g.base, 'cantidad', ceil(g.base / mo.contenido), 'lugar_entrega', 'sede', 'contrato_sede_id', g.contrato_sede_id, 'sede', g.sede,
                         'motivo', case when mo.preferido then 'preferido' when (select count(*) from elegibles z where z.producto_id = p.id) = 1 then 'unica opcion' else 'mejor precio' end, 'inpec', mo.proyecto_productivo)
                     else
                       jsonb_build_object('tercero_id', mo.tercero_id, 'proveedor', mo.proveedor, 'pp_id', mo.pp_id, 'precio_id', mo.precio_id, 'marca', mo.marca, 'presentacion', mo.presentacion, 'unidad_pedido', mo.unidad_pedido, 'contenido', mo.contenido,
                         'precio', mo.precio, 'por_compra', round(mo.por_unidad_base * coalesce(p.factor_compra, 1), 2), 'iva_pct', mo.iva_pct, 'condicion_pago', mo.condicion_pago, 'plazo_dias', mo.plazo_dias, 'lead_time', mo.lead_time,
                         'cantidad_base', g.base, 'cantidad', ceil(g.base / mo.contenido), 'lugar_entrega', 'cedi', 'contrato_sede_id', null, 'sede', null,
                         'motivo', case when mo.preferido then 'preferido' when (select count(*) from elegibles z where z.producto_id = p.id) = 1 then 'unica opcion' else 'mejor precio' end, 'inpec', mo.proyecto_productivo)
                     end a
                from (select * from mejor union all select * from mejor2 m2 where not exists (select 1 from mejor m where m.producto_id = m2.producto_id)) mo
                join lateral (
                  select case when mo.entrega_en = 'sede' then r.contrato_sede_id end contrato_sede_id, case when mo.entrega_en = 'sede' then s.nombre end sede, sum(r.base) base
                    from resto r join public.contrato_sedes cs on cs.id = r.contrato_sede_id join public.sedes s on s.id = cs.sede_id where r.producto_id = p.id group by 1, 2) g on g.base > 0
               where mo.producto_id = p.id
            ) z(a)),
          'alternativas', (select coalesce(jsonb_agg(jsonb_build_object('tercero_id', o.tercero_id, 'proveedor', o.proveedor, 'pp_id', o.pp_id, 'precio_id', o.precio_id, 'marca', o.marca, 'presentacion', o.presentacion, 'unidad_pedido', o.unidad_pedido, 'contenido', o.contenido,
                               'precio', o.precio, 'por_compra', case when o.por_unidad_base is null then null else round(o.por_unidad_base * coalesce(p.factor_compra, 1), 2) end, 'iva_pct', o.iva_pct, 'estado', o.estado, 'bloqueado', o.bloqueado, 'preferido', o.preferido, 'inpec', o.proyecto_productivo,
                               'entrega_en', o.entrega_en, 'lead_time', o.lead_time, 'condicion_pago', o.condicion_pago, 'plazo_dias', o.plazo_dias, 'sin_precio', o.precio is null)
                               order by o.bloqueado, o.precio is null, o.por_unidad_base), '[]') from ofertas o where o.producto_id = p.id),
          'por_sede', (select coalesce(jsonb_agg(jsonb_build_object('contrato_sede_id', r.contrato_sede_id, 'sede', s.nombre, 'base', r.base, 'compra', round(r.base / nullif(p.factor_compra, 0), 2)) order by s.nombre), '[]')
                         from req r join public.contrato_sedes cs on cs.id = r.contrato_sede_id join public.sedes s on s.id = cs.sede_id where r.producto_id = p.id)
        ) order by (select count(*) from elegibles o where o.producto_id = p.id) = 0 desc, p.categoria, p.nombre), '[]')
        from tot t join public.productos p on p.id = t.producto_id left join ya y on y.producto_id = t.producto_id)
  );
end $$;
revoke all on function public.sugerir_compra(uuid, date) from public, anon; grant execute on function public.sugerir_compra(uuid, date) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Generar OC en borrador desde asignaciones revisadas por compras
--    p_asignaciones: [{producto_id, tercero_id, pp_id, cantidad, precio, iva_pct, lugar_entrega, contrato_sede_id, motivo, cantidad_base}]
--    Agrupa por proveedor + lugar + establecimiento. Devuelve las OC creadas.
-- ---------------------------------------------------------------------
create or replace function public.generar_oc(p_explosion uuid, p_asignaciones jsonb, p_fecha_entrega date default null, p_notas text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.explosiones; g record; a jsonb; v_oc uuid; v_cedi uuid; v_ids uuid[] := '{}'; v_pp record; v_sede uuid;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Requerimiento no encontrado'; end if;
  if not public.puede_compras(e.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if e.estado not in ('aprobada', 'enviada_compras') then raise exception 'Solo se compra sobre un requerimiento aprobado (estado actual: %).', e.estado; end if;
  if jsonb_typeof(p_asignaciones) <> 'array' or jsonb_array_length(p_asignaciones) = 0 then raise exception 'No hay lineas para comprar.'; end if;
  select id into v_cedi from public.sedes where empresa_id = e.empresa_id and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1;

  for g in select x->>'tercero_id' tercero_id, coalesce(x->>'lugar_entrega', 'cedi') lugar, nullif(x->>'contrato_sede_id', '') contrato_sede_id
             from jsonb_array_elements(p_asignaciones) x group by 1, 2, 3 loop
    if public.tercero_bloqueado(g.tercero_id::uuid) then
      raise exception 'El proveedor % tiene un bloqueo vigente que impide emitir OC.', (select razon_social from public.terceros where id = g.tercero_id::uuid);
    end if;
    if g.lugar = 'sede' then
      select cs.sede_id into v_sede from public.contrato_sedes cs where cs.id = g.contrato_sede_id::uuid;
    else v_sede := v_cedi; end if;
    insert into public.ordenes_compra (empresa_id, codigo, tercero_id, explosion_id, contrato_id, lugar_entrega, sede_entrega_id, contrato_sede_id, fecha_entrega, condicion_pago, plazo_dias, notas)
    select e.empresa_id, public.siguiente_consecutivo(e.empresa_id, 'OC'), t.id, e.id, e.contrato_id, g.lugar, v_sede, g.contrato_sede_id::uuid, p_fecha_entrega, t.condicion_pago, t.plazo_dias, p_notas
      from public.terceros t where t.id = g.tercero_id::uuid returning id into v_oc;
    v_ids := v_ids || v_oc;
    for a in select x from jsonb_array_elements(p_asignaciones) x
              where x->>'tercero_id' = g.tercero_id and coalesce(x->>'lugar_entrega', 'cedi') = g.lugar and coalesce(nullif(x->>'contrato_sede_id', ''), '') = coalesce(g.contrato_sede_id, '') loop
      select pp.id, p.nombre producto, m.nombre marca, pr.nombre presentacion, coalesce(pr.contenido, p.factor_compra, 1) contenido, coalesce(pr.unidad_empaque, p.unidad_compra) unidad
        into v_pp from public.proveedor_productos pp join public.productos p on p.id = pp.producto_id left join public.marcas m on m.id = pp.marca_id left join public.presentaciones pr on pr.id = pp.presentacion_id
       where pp.id = (a->>'pp_id')::uuid;
      if v_pp.id is null then
        select null::uuid id, p.nombre producto, null::text marca, null::text presentacion, coalesce(p.factor_compra, 1) contenido, p.unidad_compra unidad into v_pp from public.productos p where p.id = (a->>'producto_id')::uuid;
      end if;
      insert into public.oc_items (empresa_id, oc_id, producto_id, proveedor_producto_id, descripcion, unidad_pedido, contenido_base, cantidad, cantidad_base, precio, iva_pct, requerida_base, motivo)
      values (e.empresa_id, v_oc, (a->>'producto_id')::uuid, v_pp.id, concat_ws(' · ', v_pp.producto, v_pp.marca, v_pp.presentacion), v_pp.unidad, v_pp.contenido,
              (a->>'cantidad')::numeric, 0, coalesce((a->>'precio')::numeric, 0), coalesce((a->>'iva_pct')::numeric, 0), (a->>'cantidad_base')::numeric, coalesce(a->>'motivo', 'manual'));
    end loop;
  end loop;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'total', o.total) order by o.codigo), '[]') from public.ordenes_compra o where o.id = any(v_ids));
end $$;
revoke all on function public.generar_oc(uuid, jsonb, date, text) from public, anon; grant execute on function public.generar_oc(uuid, jsonb, date, text) to authenticated;

-- OC manual (sin requerimiento) o edicion de cabecera de un borrador
create or replace function public.guardar_oc(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_id uuid := nullif(p->>'id', '')::uuid; o public.ordenes_compra; v_sede uuid; v_lugar text := coalesce(p->>'lugar_entrega', 'cedi');
begin
  if v_id is not null then
    select * into o from public.ordenes_compra where id = v_id; v_emp := o.empresa_id;
    if o.estado <> 'borrador' then raise exception 'Solo se edita una OC en borrador.'; end if;
  end if;
  if not public.puede_compras(v_emp, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if v_lugar = 'sede' then select cs.sede_id into v_sede from public.contrato_sedes cs where cs.id = (p->>'contrato_sede_id')::uuid;
  else select id into v_sede from public.sedes where empresa_id = v_emp and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1; end if;
  if v_id is null then
    if public.tercero_bloqueado((p->>'tercero_id')::uuid) then raise exception 'El proveedor tiene un bloqueo vigente que impide emitir OC.'; end if;
    insert into public.ordenes_compra (empresa_id, codigo, tercero_id, contrato_id, lugar_entrega, sede_entrega_id, contrato_sede_id, fecha_entrega, condicion_pago, plazo_dias, notas, notas_internas)
    select v_emp, public.siguiente_consecutivo(v_emp, 'OC'), (p->>'tercero_id')::uuid, nullif(p->>'contrato_id', '')::uuid, v_lugar, v_sede, nullif(p->>'contrato_sede_id', '')::uuid, nullif(p->>'fecha_entrega', '')::date,
           coalesce(nullif(p->>'condicion_pago', ''), t.condicion_pago), coalesce((p->>'plazo_dias')::int, t.plazo_dias), p->>'notas', p->>'notas_internas'
      from public.terceros t where t.id = (p->>'tercero_id')::uuid returning id into v_id;
  else
    update public.ordenes_compra set contrato_id = nullif(p->>'contrato_id', '')::uuid, lugar_entrega = v_lugar, sede_entrega_id = v_sede, contrato_sede_id = nullif(p->>'contrato_sede_id', '')::uuid,
           fecha_entrega = nullif(p->>'fecha_entrega', '')::date, condicion_pago = nullif(p->>'condicion_pago', ''), plazo_dias = (p->>'plazo_dias')::int, notas = p->>'notas', notas_internas = p->>'notas_internas',
           actualizado_por = auth.uid(), actualizado_en = now()
     where id = v_id;
  end if;
  return v_id;
end $$;
revoke all on function public.guardar_oc(jsonb) from public, anon; grant execute on function public.guardar_oc(jsonb) to authenticated;

-- linea de OC en borrador: crear / editar / borrar
create or replace function public.guardar_oc_item(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare o public.ordenes_compra; v_id uuid := nullif(p->>'id', '')::uuid; v_pp record;
begin
  select * into o from public.ordenes_compra where id = (p->>'oc_id')::uuid;
  if o.id is null then raise exception 'OC no encontrada'; end if;
  if not public.puede_compras(o.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if o.estado <> 'borrador' then raise exception 'Solo se editan lineas de una OC en borrador.'; end if;
  if coalesce(p->>'borrar', 'false') = 'true' then delete from public.oc_items where id = v_id and oc_id = o.id; return v_id; end if;
  select pp.id, pp.producto_id, p2.nombre producto, m.nombre marca, pr.nombre presentacion, coalesce(pr.contenido, p2.factor_compra, 1) contenido, coalesce(pr.unidad_empaque, p2.unidad_compra) unidad
    into v_pp from public.proveedor_productos pp join public.productos p2 on p2.id = pp.producto_id left join public.marcas m on m.id = pp.marca_id left join public.presentaciones pr on pr.id = pp.presentacion_id
   where pp.id = nullif(p->>'pp_id', '')::uuid;
  if v_pp.id is null then
    select null::uuid id, p2.id producto_id, p2.nombre producto, null::text marca, null::text presentacion, coalesce(p2.factor_compra, 1) contenido, p2.unidad_compra unidad into v_pp from public.productos p2 where p2.id = (p->>'producto_id')::uuid;
    if v_pp.producto_id is null then raise exception 'Producto no encontrado'; end if;
  end if;
  if v_id is null then
    insert into public.oc_items (empresa_id, oc_id, producto_id, proveedor_producto_id, descripcion, unidad_pedido, contenido_base, cantidad, cantidad_base, precio, iva_pct, motivo, notas)
    values (o.empresa_id, o.id, v_pp.producto_id, v_pp.id, concat_ws(' · ', v_pp.producto, v_pp.marca, v_pp.presentacion), v_pp.unidad, v_pp.contenido, (p->>'cantidad')::numeric, 0, coalesce((p->>'precio')::numeric, 0), coalesce((p->>'iva_pct')::numeric, 0), 'manual', p->>'notas')
    returning id into v_id;
  else
    update public.oc_items set cantidad = (p->>'cantidad')::numeric, precio = coalesce((p->>'precio')::numeric, 0), iva_pct = coalesce((p->>'iva_pct')::numeric, 0), notas = p->>'notas' where id = v_id and oc_id = o.id;
  end if;
  return v_id;
end $$;
revoke all on function public.guardar_oc_item(jsonb) from public, anon; grant execute on function public.guardar_oc_item(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Estados: aprobar (M3 aprobar), enviar (notifica; el portal M4 la vera), confirmar (proveedor o compras por el), cerrar, anular
-- ---------------------------------------------------------------------
create or replace function public.estado_oc(p_id uuid, p_accion text, p_nota text default null, p_fecha date default null)
returns void language plpgsql security definer set search_path = public as $$
declare o public.ordenes_compra; v_prov text;
begin
  select * into o from public.ordenes_compra where id = p_id;
  if o.id is null then raise exception 'OC no encontrada'; end if;
  select coalesce(nombre_comercial, razon_social) into v_prov from public.terceros where id = o.tercero_id;
  if p_accion = 'aprobar' then
    if not public.puede_compras(o.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
    if o.estado <> 'borrador' then raise exception 'Solo se aprueba una OC en borrador.'; end if;
    if not exists (select 1 from public.oc_items where oc_id = o.id) then raise exception 'La OC no tiene lineas.'; end if;
    if public.tercero_bloqueado(o.tercero_id) then raise exception 'El proveedor % tiene un bloqueo vigente.', v_prov; end if;
    update public.ordenes_compra set estado = 'aprobada', aprobada_por = auth.uid(), aprobada_en = now(), actualizado_en = now() where id = p_id;
  elsif p_accion = 'enviar' then
    if not public.puede_compras(o.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
    if o.estado <> 'aprobada' then raise exception 'Primero apruebe la OC.'; end if;
    update public.ordenes_compra set estado = 'enviada', enviada_por = auth.uid(), enviada_en = now(), actualizado_en = now() where id = p_id;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (o.empresa_id, 'M3', 'normal', 'OC ' || o.codigo || ' enviada a ' || v_prov, 'Total $ ' || to_char(o.total, 'FM999G999G999G990') || case when o.fecha_entrega is not null then ' · entrega ' || to_char(o.fecha_entrega, 'DD/MM/YYYY') else '' end, '/ordenes-compra?id=' || o.id, 'orden_compra', o.id);
    -- bodega / sede se enteran de lo que va a llegar (M5)
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (o.empresa_id, 'M5', 'normal', 'Entrega programada: OC ' || o.codigo || ' de ' || v_prov, case when o.lugar_entrega = 'sede' then 'Directo en el establecimiento' else 'Llega al CEDI' end || case when o.fecha_entrega is not null then ' el ' || to_char(o.fecha_entrega, 'DD/MM/YYYY') else '' end, '/ordenes-compra?id=' || o.id, 'orden_compra', o.id);
  elsif p_accion = 'confirmar' then
    if not public.puede_compras(o.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
    if o.estado <> 'enviada' then raise exception 'Solo se confirma una OC enviada.'; end if;
    update public.ordenes_compra set estado = 'confirmada', confirmada_en = now(), fecha_entrega_confirmada = coalesce(p_fecha, o.fecha_entrega), observaciones_proveedor = p_nota, actualizado_en = now() where id = p_id;
  elsif p_accion = 'cerrar' then
    if not public.puede_compras(o.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
    if o.estado not in ('enviada', 'confirmada', 'recibida_parcial') then raise exception 'Solo se cierra una OC enviada o en recepcion.'; end if;
    update public.ordenes_compra set estado = 'cerrada', cerrada_en = now(), notas_internas = concat_ws(E'\n', notas_internas, p_nota), actualizado_en = now() where id = p_id;
  elsif p_accion = 'anular' then
    if not public.puede_compras(o.empresa_id, 'aprobar') and not (o.estado = 'borrador' and public.puede_compras(o.empresa_id, 'crear')) then raise exception 'Sin permiso (Compras: aprobar).'; end if;
    if o.estado in ('cerrada', 'anulada') then raise exception 'La OC ya esta %.', o.estado; end if;
    if exists (select 1 from public.oc_items where oc_id = o.id and cantidad_recibida > 0) then raise exception 'Tiene recepciones registradas; cierrela en vez de anularla.'; end if;
    update public.ordenes_compra set estado = 'anulada', motivo_anulacion = coalesce(p_nota, 'sin motivo'), actualizado_por = auth.uid(), actualizado_en = now() where id = p_id;
  else raise exception 'Accion no valida'; end if;
end $$;
revoke all on function public.estado_oc(uuid, text, text, date) from public, anon; grant execute on function public.estado_oc(uuid, text, text, date) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Consultas de pantalla
-- ---------------------------------------------------------------------
create or replace function public.ocs_lista(p_empresa uuid, p_estado text default null, p_desde date default null, p_hasta date default null, p_tercero uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
begin
  if not public.puede_compras(p_empresa, 'ver') then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'tercero_id', t.id, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'inpec', t.proyecto_productivo,
            'explosion_id', o.explosion_id, 'requerimiento', e.codigo, 'contrato', c.numero, 'lugar_entrega', o.lugar_entrega, 'sede', s.nombre, 'fecha_emision', o.fecha_emision, 'fecha_entrega', o.fecha_entrega,
            'condicion_pago', o.condicion_pago, 'plazo_dias', o.plazo_dias, 'subtotal', o.subtotal, 'iva', o.iva, 'total', o.total,
            'items', (select count(*) from public.oc_items i where i.oc_id = o.id), 'recibido_pct', (select round(100 * sum(i.cantidad_recibida) / nullif(sum(i.cantidad), 0)) from public.oc_items i where i.oc_id = o.id)
          ) order by o.fecha_emision desc, o.codigo desc), '[]')
            from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id
            left join public.explosiones e on e.id = o.explosion_id left join public.contratos c on c.id = o.contrato_id left join public.sedes s on s.id = o.sede_entrega_id
           where o.empresa_id = p_empresa and (p_estado is null or o.estado = p_estado) and (p_desde is null or o.fecha_emision >= p_desde) and (p_hasta is null or o.fecha_emision <= p_hasta) and (p_tercero is null or o.tercero_id = p_tercero));
end $$;
revoke all on function public.ocs_lista(uuid, text, date, date, uuid) from public, anon; grant execute on function public.ocs_lista(uuid, text, date, date, uuid) to authenticated;

create or replace function public.oc_detalle(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare o public.ordenes_compra;
begin
  select * into o from public.ordenes_compra where id = p_id;
  if o.id is null or not public.puede_compras(o.empresa_id, 'ver') then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'oc', to_jsonb(o) || jsonb_build_object('aprobada_por_nombre', (select nombre from public.perfiles where id = o.aprobada_por), 'creado_por_nombre', (select nombre from public.perfiles where id = o.creado_por)),
    'proveedor', (select jsonb_build_object('id', t.id, 'razon_social', t.razon_social, 'nombre_comercial', t.nombre_comercial, 'tipo_documento', t.tipo_documento, 'numero', t.numero, 'dv', t.dv, 'direccion', t.direccion, 'ciudad', t.ciudad,
                    'telefono', coalesce(t.celular, t.telefono), 'correo', t.correo, 'correos_oc', t.correos_oc, 'proyecto_productivo', t.proyecto_productivo, 'bloqueado', public.tercero_bloqueado(t.id), 'condicion_pago', t.condicion_pago, 'plazo_dias', t.plazo_dias, 'lead_time_dias', t.lead_time_dias)
                    from public.terceros t where t.id = o.tercero_id),
    'empresa', (select jsonb_build_object('nombre', coalesce(e.nombre_corto, e.razon_social), 'razon_social', e.razon_social, 'nit', e.nit, 'ciudad', e.ciudad, 'direccion', e.direccion) from public.empresas e where e.id = o.empresa_id),
    'entrega', (select jsonb_build_object('sede', s.nombre, 'tipo', s.tipo, 'ciudad', s.ciudad, 'direccion', s.direccion, 'responsable', s.responsable, 'telefono', s.telefono) from public.sedes s where s.id = o.sede_entrega_id),
    'requerimiento', (select jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta) from public.explosiones e where e.id = o.explosion_id),
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'entidad', en.nombre) from public.contratos c left join public.entidades_contratantes en on en.id = c.entidad_id where c.id = o.contrato_id),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'producto_id', i.producto_id, 'pp_id', i.proveedor_producto_id, 'codigo', p.codigo, 'descripcion', i.descripcion, 'categoria', p.categoria, 'unidad_pedido', i.unidad_pedido, 'contenido_base', i.contenido_base,
                 'unidad_base', p.unidad_base, 'unidad_compra', p.unidad_compra, 'factor_compra', p.factor_compra, 'cantidad', i.cantidad, 'cantidad_base', i.cantidad_base, 'cantidad_compra', round(i.cantidad_base / nullif(p.factor_compra, 0), 2),
                 'precio', i.precio, 'iva_pct', i.iva_pct, 'subtotal', i.subtotal, 'iva', i.iva, 'total', i.total, 'cantidad_recibida', i.cantidad_recibida, 'requerida_base', i.requerida_base, 'motivo', i.motivo, 'notas', i.notas) order by p.categoria, i.descripcion), '[]')
                from public.oc_items i join public.productos p on p.id = i.producto_id where i.oc_id = o.id)
  );
end $$;
revoke all on function public.oc_detalle(uuid) from public, anon; grant execute on function public.oc_detalle(uuid) to authenticated;

-- requerimientos aprobados o enviados a compras, con lo ya comprado (para la bandeja de compras)
create or replace function public.requerimientos_compras(p_empresa uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
begin
  if not public.puede_compras(p_empresa, 'ver') then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'estado', e.estado, 'contrato', c.numero, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta, 'raciones', e.raciones,
            'productos', (select count(distinct producto_id) from public.explosion_detalle d where d.explosion_id = e.id),
            'ocs', (select count(*) from public.ordenes_compra o where o.explosion_id = e.id and o.estado <> 'anulada'),
            'total_oc', (select coalesce(sum(o.total), 0) from public.ordenes_compra o where o.explosion_id = e.id and o.estado <> 'anulada'),
            'productos_con_oc', (select count(distinct i.producto_id) from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id where o.explosion_id = e.id and o.estado <> 'anulada')
          ) order by e.fecha_desde desc), '[]')
            from public.explosiones e join public.contratos c on c.id = e.contrato_id
           where e.empresa_id = p_empresa and e.tipo = 'requerimiento' and e.estado in ('aprobada', 'enviada_compras'));
end $$;
revoke all on function public.requerimientos_compras(uuid) from public, anon; grant execute on function public.requerimientos_compras(uuid) to authenticated;

-- grants de respaldo (service_role solo si existe)
do $g$
declare f text;
begin
  foreach f in array array['sugerir_compra(uuid, date)', 'generar_oc(uuid, jsonb, date, text)', 'guardar_oc(jsonb)', 'guardar_oc_item(jsonb)', 'estado_oc(uuid, text, text, date)', 'ocs_lista(uuid, text, date, date, uuid)', 'oc_detalle(uuid)', 'requerimientos_compras(uuid)'] loop
    execute format('grant execute on function public.%s to authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function public.%s to service_role', f); end if;
  end loop;
end $g$;
