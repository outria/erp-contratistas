-- =====================================================================
-- Supply ERP · Migracion 029 · Correcciones de la auditoria M3 + M4 parte 1 (6-nov-2026)
-- Informe: docs/auditorias/AUDITORIA_2026-11-06_etapa_M3_M4.md
--   C1  presentaciones con contenido fijo (alta_oferta, portal, trigger)
--   A1  el proveedor ya no lee tablas completas (notas internas, motivos): todo por RPC
--   A2  validacion de empresa en todas las referencias de M3/M4; portal_resumen filtrado por empresa
--   A3  documentos del proveedor quedan pendientes de validar; ruta y vencimiento controlados; adjuntos no editables por el proveedor
--   A4  adjudicacion: OC por condicion de pago, unidad de pedido correcta, tope de cantidad, solo con la solicitud cerrada
--   A5  sugerencia de compra descuenta lo ya comprado
--   A6  sugerencia de compra liviana para PAE grandes (filtro por categoria, reparto por sede compacto)
--   M1  invitacion solo con correo confirmado; no toca internos ni superadmins
--   M2  policies con initplan (una evaluacion por consulta, no por fila)
--   M3  comparativo sellado hasta el cierre
--   M4  adjudicar sobre oferta suspendida o rechazada: error; propuesta: se homologa
--   M5  solicitud con entrega en sede: lineas por establecimiento
--   M6  bitacora en tablas de OC y portal; foto de cada envio de oferta
--   M7  costo_ciclo con las raciones de las sedes que usan el ciclo
--   M8  sin cambios a ofertas ya evaluadas; marca de oferta editada despues de enviada
--   Bajos B1, B4, B6, B7, B10
-- =====================================================================

-- ---------------------------------------------------------------------
-- Apoyos: empresas del usuario como conjunto (para policies con initplan, M2)
-- ---------------------------------------------------------------------
create or replace function public.mis_empresas_internas() returns setof uuid language sql stable security definer set search_path = public as $$
  select m.empresa_id from public.membresias m join public.roles r on r.id = m.rol_id where m.usuario_id = auth.uid() and m.activo and not r.es_proveedor;
$$;
create or replace function public.mis_empresas_compras() returns setof uuid language sql stable security definer set search_path = public as $$
  select distinct m.empresa_id from public.membresias m join public.permisos p on p.rol_id = m.rol_id
   where m.usuario_id = auth.uid() and m.activo and p.accion = 'crear' and p.modulo in ('M3', 'M13');
$$;
create or replace function public.mis_empresas_proveedor() returns setof uuid language sql stable security definer set search_path = public as $$
  select m.empresa_id from public.membresias m join public.roles r on r.id = m.rol_id where m.usuario_id = auth.uid() and m.activo and r.es_proveedor;
$$;
create or replace function public.mis_terceros() returns setof uuid language sql stable security definer set search_path = public as $$
  select up.tercero_id from public.usuarios_proveedor up
   where up.usuario_id = auth.uid() and up.activo and up.empresa_id in (select public.mis_empresas_proveedor());
$$;
revoke all on function public.mis_empresas_internas(), public.mis_empresas_compras(), public.mis_empresas_proveedor(), public.mis_terceros() from public, anon;
grant execute on function public.mis_empresas_internas(), public.mis_empresas_compras(), public.mis_empresas_proveedor(), public.mis_terceros() to authenticated;

-- ---------------------------------------------------------------------
-- C1 · el contenido de una presentacion con ofertas no se cambia
-- ---------------------------------------------------------------------
create or replace function public.presentaciones_contenido_fijo() returns trigger language plpgsql as $$
begin
  if new.contenido is distinct from old.contenido and exists (select 1 from public.proveedor_productos pp where pp.presentacion_id = old.id) then
    raise exception 'La presentacion "%" ya tiene ofertas; su contenido no se cambia. Cree otra presentacion.', old.nombre;
  end if;
  return new;
end $$;
drop trigger if exists presentaciones_contenido_fijo on public.presentaciones;
create trigger presentaciones_contenido_fijo before update of contenido on public.presentaciones for each row execute function public.presentaciones_contenido_fijo();

-- columnas nuevas que usan las funciones de abajo
alter table public.ofertas add column if not exists envios jsonb not null default '[]'::jsonb;

-- C1 · alta_oferta: una presentacion existente nunca cambia de contenido
create or replace function public.alta_oferta(p_tercero uuid, p_producto uuid, p_marca text default null, p_presentacion text default null, p_contenido numeric default null, p_unidad_empaque text default 'und',
                                              p_precio numeric default null, p_desde date default null, p_iva numeric default 0, p_estado text default 'propuesto', p_codigo_proveedor text default null, p_lead_time int default null, p_entrega_en text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_marca uuid; v_pres uuid; v_pp uuid; v_cont numeric;
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
    on conflict (empresa_id, producto_id, nombre) do update set nombre = excluded.nombre returning id, contenido into v_pres, v_cont;
    if v_cont is distinct from p_contenido then
      raise exception 'Ya existe la presentacion "%" con contenido % (no %). Use otro nombre, por ejemplo "% (%)".', trim(p_presentacion), v_cont, p_contenido, trim(p_presentacion), p_contenido;
    end if;
  end if;
  insert into public.proveedor_productos (empresa_id, tercero_id, producto_id, marca_id, presentacion_id, codigo_proveedor, lead_time_dias, entrega_en, estado)
  values (v_emp, p_tercero, p_producto, v_marca, v_pres, p_codigo_proveedor, p_lead_time, p_entrega_en, coalesce(p_estado, 'propuesto'))
  on conflict (tercero_id, producto_id, marca_id, presentacion_id) do update set codigo_proveedor = coalesce(excluded.codigo_proveedor, public.proveedor_productos.codigo_proveedor), lead_time_dias = coalesce(excluded.lead_time_dias, public.proveedor_productos.lead_time_dias)
  returning id into v_pp;
  if p_precio is not null then perform public.registrar_precio(v_pp, p_precio, coalesce(p_desde, (now() at time zone 'America/Bogota')::date), p_iva, 'cotizacion', coalesce(p_entrega_en, 'cedi')); end if;
  return v_pp;
end $$;

-- A5 / A6 · sugerir_compra: descuenta lo ya comprado, filtro por categoria, reparto por sede compacto
drop function if exists public.sugerir_compra(uuid, date);
create or replace function public.sugerir_compra(p_explosion uuid, p_fecha date default null, p_categoria text default null)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare e public.explosiones; v_f date; v_cedi uuid;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null or not public.puede_compras(e.empresa_id, 'ver') then raise exception 'Sin permiso'; end if;
  v_f := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
  select id into v_cedi from public.sedes where empresa_id = e.empresa_id and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1;
  return jsonb_build_object(
    'explosion', jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'estado', e.estado, 'tipo', e.tipo, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta, 'raciones', e.raciones, 'contrato_id', e.contrato_id),
    'cedi_id', v_cedi, 'categoria', p_categoria,
    'categorias', (select coalesce(jsonb_agg(distinct pz.categoria), '[]') from public.explosion_detalle d join public.productos pz on pz.id = d.producto_id where d.explosion_id = p_explosion),
    'ordenes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'total', o.total, 'items', (select count(*) from public.oc_items i where i.oc_id = o.id)) order by o.codigo), '[]')
                  from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id where o.explosion_id = e.id and o.estado <> 'anulada'),
    'productos', (
      with req0 as (
        select d.producto_id, d.contrato_sede_id, sum(d.cantidad_bruta) base
          from public.explosion_detalle d join public.productos pz on pz.id = d.producto_id
         where d.explosion_id = p_explosion and (p_categoria is null or pz.categoria = p_categoria) group by 1, 2),
      ya_sede as (  -- lo ya comprado con entrega directa, por establecimiento
        select i.producto_id, o.contrato_sede_id, sum(i.cantidad_base) base from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id
         where o.explosion_id = p_explosion and o.estado <> 'anulada' and o.lugar_entrega = 'sede' group by 1, 2),
      ya_cedi as (  -- lo ya comprado para el CEDI
        select i.producto_id, sum(i.cantidad_base) base from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id
         where o.explosion_id = p_explosion and o.estado <> 'anulada' and o.lugar_entrega = 'cedi' group by 1),
      tot as (select producto_id, sum(base) base from req0 group by 1),
      req as (  -- lo pendiente por establecimiento (A5: no volver a comprar lo que ya esta en OC)
        select r.producto_id, r.contrato_sede_id, greatest(r.base - coalesce(ys.base, 0), 0) base
          from req0 r left join ya_sede ys on ys.producto_id = r.producto_id and ys.contrato_sede_id = r.contrato_sede_id),
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
          from req r join elegibles o on o.producto_id = r.producto_id and o.proyecto_productivo and o.inpec_sede = r.contrato_sede_id and r.base > 0
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
              -- resto: mejor opcion; si entrega solo en sede, una asignacion con el reparto compacto por establecimiento en 'sedes'
              select jsonb_build_object('tercero_id', mo.tercero_id, 'proveedor', mo.proveedor, 'pp_id', mo.pp_id, 'precio_id', mo.precio_id, 'marca', mo.marca, 'presentacion', mo.presentacion, 'unidad_pedido', mo.unidad_pedido, 'contenido', mo.contenido,
                       'precio', mo.precio, 'por_compra', round(mo.por_unidad_base * coalesce(p.factor_compra, 1), 2), 'iva_pct', mo.iva_pct, 'condicion_pago', mo.condicion_pago, 'plazo_dias', case when mo.condicion_pago = 'contado' then null else mo.plazo_dias end, 'lead_time', mo.lead_time,
                       'cantidad_base', g.base, 'cantidad', ceil(g.base / mo.contenido), 'lugar_entrega', case when mo.entrega_en = 'sede' then 'sede' else 'cedi' end, 'contrato_sede_id', null, 'sede', null,
                       'motivo', case when mo.preferido then 'preferido' when (select count(*) from elegibles z where z.producto_id = p.id) = 1 then 'unica opcion' else 'mejor precio' end, 'inpec', mo.proyecto_productivo,
                       'sedes', g.sedes) a
                from (select * from mejor union all select * from mejor2 m2 where not exists (select 1 from mejor m where m.producto_id = m2.producto_id)) mo
                join lateral (
                  select case when mo.entrega_en = 'sede' then sum(r.base) else greatest(sum(r.base) - coalesce((select c.base from ya_cedi c where c.producto_id = p.id), 0), 0) end base,
                         case when mo.entrega_en = 'sede' then jsonb_agg(jsonb_build_array(r.contrato_sede_id, s.nombre, r.base) order by s.nombre) filter (where r.base > 0) end sedes
                    from resto r join public.contrato_sedes cs on cs.id = r.contrato_sede_id join public.sedes s on s.id = cs.sede_id where r.producto_id = p.id) g on g.base > 0
               where mo.producto_id = p.id
            ) z(a)),
          'alternativas', (select coalesce(jsonb_agg(jsonb_build_object('tercero_id', o.tercero_id, 'proveedor', o.proveedor, 'pp_id', o.pp_id, 'precio_id', o.precio_id, 'marca', o.marca, 'presentacion', o.presentacion, 'unidad_pedido', o.unidad_pedido, 'contenido', o.contenido,
                               'precio', o.precio, 'por_compra', case when o.por_unidad_base is null then null else round(o.por_unidad_base * coalesce(p.factor_compra, 1), 2) end, 'iva_pct', o.iva_pct, 'estado', o.estado, 'bloqueado', o.bloqueado, 'preferido', o.preferido, 'inpec', o.proyecto_productivo,
                               'entrega_en', o.entrega_en, 'lead_time', o.lead_time, 'condicion_pago', o.condicion_pago, 'plazo_dias', o.plazo_dias, 'sin_precio', o.precio is null)
                               order by o.bloqueado, o.precio is null, o.por_unidad_base), '[]') from ofertas o where o.producto_id = p.id),
          'n_sedes', (select count(*) from req0 r where r.producto_id = p.id),
          'primera_sede', (select jsonb_build_object('contrato_sede_id', r.contrato_sede_id, 'sede', s.nombre) from req0 r join public.contrato_sedes cs on cs.id = r.contrato_sede_id join public.sedes s on s.id = cs.sede_id where r.producto_id = p.id order by s.nombre limit 1)
        ) order by (select count(*) from elegibles o where o.producto_id = p.id) = 0 desc, p.categoria, p.nombre), '[]')
        from tot t join public.productos p on p.id = t.producto_id left join ya y on y.producto_id = t.producto_id)
  );
end $$;
revoke all on function public.sugerir_compra(uuid, date, text) from public, anon; grant execute on function public.sugerir_compra(uuid, date, text) to authenticated;

-- B4 · generar_oc: contado sin plazo
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
    select e.empresa_id, public.siguiente_consecutivo(e.empresa_id, 'OC'), t.id, e.id, e.contrato_id, g.lugar, v_sede, g.contrato_sede_id::uuid, p_fecha_entrega, t.condicion_pago, case when t.condicion_pago = 'contado' then null else t.plazo_dias end, p_notas
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

-- M7 · costo_ciclo: raciones solo de las sedes con el ciclo vigente
create or replace function public.costo_ciclo(p_ciclo uuid, p_grupo uuid default null, p_fecha date default null, p_top int default 12)
returns jsonb language plpgsql volatile security definer set search_path = public set jit = off as $$
declare c public.ciclos_menu; v_f date; v_grupo uuid; v_dias_mes numeric; r jsonb; v_sedes int;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M3', 'ver') or public.tiene_permiso(c.empresa_id, 'M2', 'ver')) then raise exception 'Sin permiso'; end if;
  v_f := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
  set local client_min_messages = warning;
  -- M7: las raciones son las de las sedes que tienen este ciclo vigente (si ninguna, el contrato completo)
  select count(distinct sc.contrato_sede_id) into v_sedes from public.sede_ciclo sc
   where sc.ciclo_id = p_ciclo and sc.vigente_desde <= v_f and (sc.vigente_hasta is null or sc.vigente_hasta >= v_f);
  -- grupo de referencia: el pedido, si no el de mas cupos vigentes, si no el primero
  v_grupo := coalesce(p_grupo,
    (select cu.grupo_poblacion_id from public.cupos cu join public.contrato_sedes cs on cs.id = cu.contrato_sede_id
      where cs.contrato_id = c.contrato_id and cu.fecha_desde <= v_f and (cu.fecha_hasta is null or cu.fecha_hasta >= v_f) group by 1 order by sum(cu.cantidad) desc limit 1),
    (select g.id from public.grupos_poblacion g where g.contrato_id = c.contrato_id order by g.orden limit 1));
  select case when k.dias_atencion = 'todos' then 30 else 20 end into v_dias_mes from public.contratos k where k.id = c.contrato_id;

  -- 1. ingredientes de cada casilla con su crudo (gramajes vigentes del contrato) y su precio
  drop table if exists tmp_cc;
  create temp table tmp_cc on commit drop as
  select i.id item_id, i.dia, i.tiempo_comida_id, i.componente_id, i.preparacion_id, p.nombre preparacion, i.descriptor,
         pi.producto_id, pr.nombre producto, pr.categoria, pr.unidad_base, pi.es_principal,
         (ci.crudo) crudo, px.por_unidad_base, px.proveedor, px.simulado,
         case when px.por_unidad_base is null then null else round(ci.crudo * px.por_unidad_base, 2) end costo
    from public.ciclo_menu_items i
    left join public.preparaciones p on p.id = i.preparacion_id
    left join public.preparacion_ingredientes pi on pi.preparacion_id = i.preparacion_id and (pi.grupo_poblacion_id = v_grupo or pi.grupo_poblacion_id is null) and not pi.opcional
    left join public.productos pr on pr.id = pi.producto_id
    left join lateral public.crudo_ingrediente(c.contrato_id, null, v_f, i.preparacion_id, pi.producto_id, v_grupo, i.componente_id, pi.peso_bruto) ci on pi.id is not null
    left join lateral public.precio_base_producto(pi.producto_id, v_f) px on pi.id is not null
   where i.ciclo_id = p_ciclo
     -- si la receta trae fila especifica del grupo para un producto, no usar ademas la generica
     and (pi.id is null or pi.grupo_poblacion_id is not null or not exists (select 1 from public.preparacion_ingredientes z where z.preparacion_id = pi.preparacion_id and z.producto_id = pi.producto_id and z.grupo_poblacion_id = v_grupo));

  -- 2. costo por casilla
  drop table if exists tmp_cel;
  create temp table tmp_cel on commit drop as
  select item_id, dia, tiempo_comida_id, componente_id, preparacion_id, max(preparacion) preparacion, max(descriptor) descriptor,
         sum(costo) costo, count(producto_id) n_ing, count(producto_id) filter (where por_unidad_base is null) sin_precio, bool_or(simulado) simulado
    from tmp_cc group by 1, 2, 3, 4, 5;

  -- 3. raciones por dia por tiempo (poblacion vigente del contrato, todas las sedes y variantes; cupo sin tiempo = todos los tiempos)
  drop table if exists tmp_rac;
  create temp table tmp_rac on commit drop as
  select t.id tiempo_comida_id, sum(cu.cantidad) raciones
    from public.tiempos_comida t
    join public.contrato_sedes cs on cs.contrato_id = t.contrato_id and cs.estado = 'activa'
    join public.cupos cu on cu.contrato_sede_id = cs.id and (cu.tiempo_comida_id = t.id or cu.tiempo_comida_id is null)
   where t.contrato_id = c.contrato_id and cu.fecha_desde <= v_f and (cu.fecha_hasta is null or cu.fecha_hasta >= v_f)
     and (v_sedes = 0 or exists (select 1 from public.sede_ciclo sc where sc.contrato_sede_id = cs.id and sc.ciclo_id = p_ciclo and sc.vigente_desde <= v_f and (sc.vigente_hasta is null or sc.vigente_hasta >= v_f)))
   group by 1;

  -- 4. alternativas mas baratas por casilla (misma familia del componente; si no hay familia, mismo componente_codigo).
  --    El costo de cada alternativa se calcula una sola vez por (preparacion, componente).
  drop table if exists tmp_cand;
  create temp table tmp_cand on commit drop as
  select ce.item_id, ce.componente_id, ce.preparacion_id, ce.costo costo_actual, p2.id alt_id, p2.nombre alt_nombre
    from tmp_cel ce
    join public.componentes co on co.id = ce.componente_id
    join public.preparaciones p2 on p2.empresa_id = c.empresa_id and p2.estado = 'activa' and (p2.contrato_id is null or p2.contrato_id = c.contrato_id) and p2.id <> ce.preparacion_id
   where ce.costo is not null and ce.sin_precio = 0
     and ((co.familia_id is not null and exists (select 1 from public.familia_opciones fo where fo.familia_id = co.familia_id and fo.preparacion_id = p2.id and fo.estado = 'vigente'))
       or (co.familia_id is null and p2.componente_codigo is not null and p2.componente_codigo = co.codigo));
  drop table if exists tmp_pc;
  create temp table tmp_pc on commit drop as
  select d.alt_id, d.componente_id,
         sum(round(ci.crudo * px.por_unidad_base, 2)) costo_alt,
         count(*) filter (where px.por_unidad_base is null) alt_sin_precio
    from (select distinct alt_id, componente_id from tmp_cand) d
    join public.preparacion_ingredientes pi on pi.preparacion_id = d.alt_id and not pi.opcional and (pi.grupo_poblacion_id = v_grupo or pi.grupo_poblacion_id is null)
    left join lateral public.crudo_ingrediente(c.contrato_id, null, v_f, d.alt_id, pi.producto_id, v_grupo, d.componente_id, pi.peso_bruto) ci on true
    left join lateral public.precio_base_producto(pi.producto_id, v_f) px on true
   where (pi.grupo_poblacion_id is not null or not exists (select 1 from public.preparacion_ingredientes z where z.preparacion_id = pi.preparacion_id and z.producto_id = pi.producto_id and z.grupo_poblacion_id = v_grupo))
   group by 1, 2;
  drop table if exists tmp_alt;
  create temp table tmp_alt on commit drop as
  select distinct on (cd.item_id) cd.item_id, ce.dia, ce.tiempo_comida_id, cd.componente_id, cd.preparacion_id, cd.costo_actual, cd.alt_id, cd.alt_nombre, pc.costo_alt
    from tmp_cand cd join tmp_cel ce on ce.item_id = cd.item_id join tmp_pc pc on pc.alt_id = cd.alt_id and pc.componente_id = cd.componente_id
   where pc.costo_alt is not null and pc.alt_sin_precio = 0 and pc.costo_alt < cd.costo_actual
   order by cd.item_id, pc.costo_alt;

  select jsonb_build_object(
    'ciclo', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'n_menus', c.n_menus, 'estado', c.estado, 'contrato_id', c.contrato_id),
    'grupo', (select jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nombre', g.nombre) from public.grupos_poblacion g where g.id = v_grupo),
    'fecha', v_f, 'dias_mes', v_dias_mes, 'sedes_con_ciclo', v_sedes,
    'raciones_dia', (select coalesce(jsonb_object_agg(tiempo_comida_id, raciones), '{}') from tmp_rac),
    'celdas', (select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'dia', dia, 'tiempo_id', tiempo_comida_id, 'componente_id', componente_id, 'preparacion_id', preparacion_id, 'preparacion', coalesce(preparacion, descriptor),
                  'costo', costo, 'n_ing', n_ing, 'sin_precio', sin_precio, 'simulado', simulado,
                  'ingredientes', (select jsonb_agg(jsonb_build_object('producto', producto, 'crudo', crudo, 'unidad', unidad_base, 'precio_base', por_unidad_base, 'costo', costo, 'proveedor', proveedor, 'principal', es_principal, 'simulado', simulado) order by es_principal desc, costo desc nulls last) from tmp_cc x where x.item_id = tmp_cel.item_id and x.producto_id is not null)
                ) order by dia, tiempo_comida_id, componente_id), '[]') from tmp_cel),
    'menus', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'costo', costo, 'sin_precio', sin_precio, 'por_tiempo', por_tiempo) order by dia), '[]')
                from (select dia, sum(costo) costo, sum(sin_precio) sin_precio, (select jsonb_object_agg(tiempo_comida_id, s) from (select tiempo_comida_id, sum(costo) s from tmp_cel z where z.dia = y.dia group by 1) w) por_tiempo from tmp_cel y group by dia) m),
    'resumen', jsonb_build_object(
      'costo_racion_dia_prom', (select round(avg(s), 2) from (select dia, sum(costo) s from tmp_cel group by dia) m),
      'menu_mas_caro', (select jsonb_build_object('dia', dia, 'costo', s) from (select dia, sum(costo) s from tmp_cel group by dia) m order by s desc nulls last limit 1),
      'menu_mas_barato', (select jsonb_build_object('dia', dia, 'costo', s) from (select dia, sum(costo) s from tmp_cel group by dia) m order by s nulls last limit 1),
      'por_tiempo', (select coalesce(jsonb_agg(jsonb_build_object('tiempo_id', t.id, 'tiempo', t.nombre, 'promedio', x.prom, 'raciones_dia', (select raciones from tmp_rac r where r.tiempo_comida_id = t.id),
                        'mas_caro', (select jsonb_build_object('dia', dia, 'costo', s) from (select dia, sum(costo) s from tmp_cel z where z.tiempo_comida_id = t.id group by dia) m order by s desc nulls last limit 1),
                        'mas_barato', (select jsonb_build_object('dia', dia, 'costo', s) from (select dia, sum(costo) s from tmp_cel z where z.tiempo_comida_id = t.id group by dia) m order by s nulls last limit 1),
                        'componente_mas_caro', (select jsonb_build_object('componente', co.nombre, 'promedio', round(avg(z.costo), 2)) from tmp_cel z join public.componentes co on co.id = z.componente_id where z.tiempo_comida_id = t.id group by co.id, co.nombre order by 1 desc limit 1)
                      ) order by t.orden), '[]')
                       from public.tiempos_comida t join lateral (select round(avg(s), 2) prom from (select dia, sum(costo) s from tmp_cel z where z.tiempo_comida_id = t.id group by dia) m) x on true
                      where t.contrato_id = c.contrato_id and exists (select 1 from tmp_cel z where z.tiempo_comida_id = t.id)),
      'componentes', (select coalesce(jsonb_agg(jsonb_build_object('componente_id', q.id, 'componente', q.nombre, 'tiempo_id', q.tiempo_comida_id, 'promedio', q.prom) order by q.prom desc nulls last), '[]')
                        from (select co.id, co.nombre, co.tiempo_comida_id, round(avg(z.costo), 2) prom from tmp_cel z join public.componentes co on co.id = z.componente_id group by co.id, co.nombre, co.tiempo_comida_id) q),
      'sin_precio', (select coalesce(jsonb_agg(jsonb_build_object('producto', producto, 'categoria', categoria, 'casillas', n) order by n desc), '[]') from (select producto, categoria, count(*) n from tmp_cc where producto_id is not null and por_unidad_base is null group by 1, 2) s),
      'casillas', (select count(*) from tmp_cel), 'casillas_sin_receta', (select count(*) from tmp_cel where preparacion_id is null), 'casillas_sin_precio', (select count(*) from tmp_cel where sin_precio > 0),
      'con_simulados', (select bool_or(simulado) from tmp_cel)
    ),
    'sugerencias', (select coalesce(jsonb_agg(s order by (s->>'ahorro_mes')::numeric desc nulls last), '[]') from (
                     select jsonb_build_object('item_id', a.item_id, 'dia', a.dia, 'tiempo_id', a.tiempo_comida_id, 'tiempo', t.nombre, 'componente', co.nombre, 'actual', p1.nombre, 'actual_costo', a.costo_actual,
                              'alternativa', a.alt_nombre, 'alternativa_id', a.alt_id, 'alternativa_costo', a.costo_alt, 'ahorro_racion', round(a.costo_actual - a.costo_alt, 2),
                              'raciones_dia', r.raciones, 'ahorro_ciclo', round((a.costo_actual - a.costo_alt) * coalesce(r.raciones, 0), 0),
                              'ahorro_mes', round((a.costo_actual - a.costo_alt) * coalesce(r.raciones, 0) * v_dias_mes / c.n_menus, 0)) s
                       from tmp_alt a join public.tiempos_comida t on t.id = a.tiempo_comida_id join public.componentes co on co.id = a.componente_id join public.preparaciones p1 on p1.id = a.preparacion_id
                       left join tmp_rac r on r.tiempo_comida_id = a.tiempo_comida_id
                      order by (a.costo_actual - a.costo_alt) * coalesce(r.raciones, 1) desc limit greatest(p_top, 1)) q),
    'ahorro_total_mes', (select coalesce(round(sum((a.costo_actual - a.costo_alt) * coalesce(r.raciones, 0) * v_dias_mes / c.n_menus), 0), 0) from tmp_alt a left join tmp_rac r on r.tiempo_comida_id = a.tiempo_comida_id)
  ) into r;
  return r;
end $$;

-- M1 · invitar_usuario_proveedor: correo confirmado, sin tocar internos ni superadmins
create or replace function public.invitar_usuario_proveedor(p_tercero uuid, p_correo text, p_nombre text default null, p_cargo text default null)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare t public.terceros; v_user uuid; v_rol uuid; v_id uuid;
begin
  select * into t from public.terceros where id = p_tercero;
  if t.id is null then raise exception 'Proveedor no encontrado'; end if;
  if not public.puede_compras(t.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  -- M1: solo cuentas con el correo confirmado; nunca un superadmin
  select u.id into v_user from auth.users u where lower(u.email) = lower(trim(p_correo)) and u.email_confirmed_at is not null;
  if v_user is not null and exists (select 1 from public.perfiles pf where pf.id = v_user and pf.es_superadmin) then raise exception 'Ese correo es de un administrador de la plataforma.'; end if;
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
    -- el tipo global solo cambia si no es usuario interno en ninguna empresa
    update public.perfiles set tipo = 'proveedor', nombre = coalesce(nombre, p_nombre)
     where id = v_user and tipo <> 'proveedor'
       and not exists (select 1 from public.membresias m join public.roles r on r.id = m.rol_id where m.usuario_id = v_user and not r.es_proveedor);
  end if;
  return jsonb_build_object('id', v_id, 'activo', v_user is not null, 'mensaje', case when v_user is null then 'La cuenta no existe o no ha confirmado el correo en Supabase Auth: creela o invitela (Authentication > Users) y, cuando este confirmada, vuelva a dar clic en Invitar.' else 'Usuario del portal activo.' end);
end $$;

-- M5 / B6 · guardar_solicitud: lineas por establecimiento, aviso de cero lineas, invitados validos
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
    -- M5: con entrega en el establecimiento, una linea por producto y establecimiento
    insert into public.solicitud_lineas (empresa_id, solicitud_id, producto_id, cantidad, contrato_sede_id, orden)
    select v_emp, v_id, x.producto_id, round(x.base / nullif(pr.factor_compra, 0), 2), x.contrato_sede_id, row_number() over (order by pr.categoria, pr.nombre, x.contrato_sede_id)
      from (select d.producto_id, case when coalesce(p->>'lugar_entrega', 'cedi') in ('sede', 'ambos') then d.contrato_sede_id end contrato_sede_id, sum(d.cantidad_bruta) base
              from public.explosion_detalle d where d.explosion_id = v_exp group by 1, 2) x
      join public.productos pr on pr.id = x.producto_id
     where coalesce((p->>'solo_sin_precio')::boolean, false) = false
        or not exists (select 1 from public.precio_base_producto(x.producto_id, (now() at time zone 'America/Bogota')::date));
  end if;
  if not exists (select 1 from public.solicitud_lineas where solicitud_id = v_id) then
    raise exception 'La solicitud quedo sin lineas%.', case when coalesce((p->>'solo_sin_precio')::boolean, false) then ': todos los productos del requerimiento ya tienen precio homologado (quite el filtro "solo sin precio" o compre directo desde Ordenes de compra)' else '' end;
  end if;
  -- invitados: los enviados, o los homologados activos sin bloqueo de las categorias de las lineas
  if jsonb_typeof(p->'invitados') = 'array' and jsonb_array_length(p->'invitados') > 0 then
    insert into public.solicitud_invitados (solicitud_id, tercero_id, empresa_id)
    select v_id, t.id, v_emp from jsonb_array_elements(p->'invitados') x join public.terceros t on t.id = (x#>>'{}')::uuid and t.empresa_id = v_emp and t.es_proveedor and t.estado = 'activo' on conflict do nothing;
  else
    insert into public.solicitud_invitados (solicitud_id, tercero_id, empresa_id)
    select distinct v_id, t.id, v_emp from public.terceros t
     where t.empresa_id = v_emp and t.es_proveedor and t.estado = 'activo' and t.estado_homologacion in ('homologado', 'condicionado') and not public.tercero_bloqueado(t.id)
       and t.categorias && (select coalesce(array_agg(distinct pr.categoria), '{}') from public.solicitud_lineas l join public.productos pr on pr.id = l.producto_id where l.solicitud_id = v_id)
    on conflict do nothing;
  end if;
  return v_id;
end $$;

-- M3 / M8 · comparar_ofertas: sellada hasta el cierre; marca ofertas editadas despues de enviadas
create or replace function public.comparar_ofertas(p_solicitud uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare s public.solicitudes_cotizacion; v_pp boolean; v_hoy date := (now() at time zone 'America/Bogota')::date; v_sellada boolean;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud;
  if s.id is null or not public.puede_compras(s.empresa_id, 'ver') then raise exception 'Sin permiso'; end if;
  select coalesce((valor#>>'{}')::boolean, true) into v_pp from public.config_empresa where empresa_id = s.empresa_id and clave = 'compras.aprovecha_pronto_pago';
  v_pp := coalesce(v_pp, true);
  -- M3: oferta sellada; nadie ve precios antes del cierre
  v_sellada := s.estado = 'publicada' and s.cierre > now();
  return jsonb_build_object(
    'solicitud', to_jsonb(s) || jsonb_build_object('requerimiento', (select codigo from public.explosiones e where e.id = s.explosion_id), 'contrato', (select numero from public.contratos c where c.id = s.contrato_id), 'abierta', s.estado = 'publicada' and s.cierre > now(), 'sellada', v_sellada),
    'invitados', (select coalesce(jsonb_agg(jsonb_build_object('tercero_id', t.id, 'proveedor', coalesce(t.nombre_comercial, t.razon_social), 'inpec', t.proyecto_productivo, 'homologacion', t.estado_homologacion, 'calificacion', t.calificacion, 'bloqueado', public.tercero_bloqueado(t.id),
                      'notificado_en', i.notificado_en, 'visto_en', i.visto_en, 'oferta_estado', o.estado, 'oferta_id', o.id, 'enviada_en', o.enviada_en, 'validez_hasta', o.validez_hasta, 'condiciones', o.condiciones,
                      'lineas_cotizadas', (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id), 'editada_despues', o.enviada_en is not null and o.actualizado_en > o.enviada_en + interval '2 seconds', 'envios', jsonb_array_length(coalesce(o.envios, '[]')),
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
                      where ol.linea_id = l.id and o.estado in ('enviada', 'adjudicada', 'parcial', 'no_adjudicada') and not v_sellada) q),
                  'adjudicado', (select coalesce(sum(a.cantidad), 0) from public.adjudicaciones a where a.linea_id = l.id)
                ) order by l.orden), '[]') from public.solicitud_lineas l join public.productos pr on pr.id = l.producto_id where l.solicitud_id = p_solicitud),
    'aprovecha_pronto_pago', v_pp,
    'ocs', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'total', o.total)), '[]') from public.adjudicaciones a join public.ordenes_compra o on o.id = a.oc_id where a.solicitud_id = p_solicitud)
  );
end $$;

-- A2 / A3 · portal_resumen: filtrado por empresa y con el documento pendiente de validar
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
                      'ruta', (select a.ruta from public.adjuntos a where a.id = d.adjunto_id),
                      'pendiente', (select jsonb_build_object('id', dp.id, 'fecha', dp.fecha_documento, 'vence', dp.vence, 'estado', dp.estado, 'nota', dp.nota_resolucion, 'subido_en', dp.creado_en) from public.documentos_propuestos dp where dp.tercero_id = v_t and dp.codigo = td.codigo order by dp.creado_en desc limit 1)) order by td.orden), '[]')
                     from public.tipos_documento_tercero td left join public.tercero_documentos d on d.tercero_id = v_t and d.codigo = td.codigo
                    where not td.solo_alimentos or exists (select 1 from public.terceros t where t.id = v_t and t.categorias && '{proteinas,fruver,lacteos,abarrotes,panaderia,bebidas}'::text[])),
    'solicitudes', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'codigo', s.codigo, 'titulo', s.titulo, 'estado', s.estado, 'cierre', s.cierre, 'abierta', s.estado = 'publicada' and s.cierre > now(), 'lugar_entrega', s.lugar_entrega, 'entrega_desde', s.entrega_desde, 'entrega_hasta', s.entrega_hasta,
                      'lineas', (select count(*) from public.solicitud_lineas l where l.solicitud_id = s.id), 'oferta_estado', o.estado, 'oferta_id', o.id, 'cotizadas', (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id),
                      'adjudicadas', (select count(*) from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id)) order by (s.estado = 'publicada' and s.cierre > now()) desc, s.cierre desc), '[]')
                      from public.solicitud_invitados i join public.solicitudes_cotizacion s on s.id = i.solicitud_id left join public.ofertas o on o.solicitud_id = s.id and o.tercero_id = v_t
                     where i.tercero_id = v_t and s.empresa_id = p_empresa and s.estado in ('publicada', 'cerrada', 'adjudicada')),
    'ofertas_catalogo', (select coalesce(jsonb_agg(jsonb_build_object('pp_id', pp.id, 'producto_id', pr.id, 'producto', pr.nombre, 'categoria', pr.categoria, 'unidad_compra', pr.unidad_compra, 'unidad_base', pr.unidad_base, 'factor_compra', pr.factor_compra, 'marca', m.nombre, 'presentacion', ps.nombre, 'contenido', ps.contenido, 'estado', pp.estado, 'preferido', pp.preferido,
                           'precio', x.precio, 'por_compra', case when x.por_unidad_base is null then null else round(x.por_unidad_base * coalesce(pr.factor_compra, 1), 2) end, 'iva_pct', x.iva_pct, 'desde', x.vigente_desde, 'hasta', x.vigente_hasta, 'condicion_pago', x.condicion_pago, 'plazo_dias', x.plazo_dias,
                           'propuesta', (select jsonb_build_object('id', q.id, 'precio', q.precio, 'desde', q.vigente_desde, 'estado', q.estado, 'nota_resolucion', q.nota_resolucion) from public.precios_propuestos q where q.proveedor_producto_id = pp.id order by q.creado_en desc limit 1),
                           'ficha_tecnica_id', pp.ficha_tecnica_id) order by pr.categoria, pr.nombre, m.nombre), '[]')
                           from public.proveedor_productos pp join public.productos pr on pr.id = pp.producto_id left join public.marcas m on m.id = pp.marca_id left join public.presentaciones ps on ps.id = pp.presentacion_id
                           left join lateral (select * from public.precios x where x.proveedor_producto_id = pp.id and x.vigente_desde <= v_hoy and (x.vigente_hasta is null or x.vigente_hasta >= v_hoy) order by x.vigente_desde desc limit 1) x on true
                          where pp.tercero_id = v_t and pp.estado <> 'rechazado'),
    'ordenes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'estado', o.estado, 'fecha_emision', o.fecha_emision, 'fecha_entrega', o.fecha_entrega, 'fecha_entrega_confirmada', o.fecha_entrega_confirmada, 'lugar_entrega', o.lugar_entrega, 'sede', se.nombre, 'ciudad', se.ciudad, 'direccion', se.direccion, 'total', o.total, 'condicion_pago', o.condicion_pago, 'plazo_dias', o.plazo_dias, 'notas', o.notas, 'observaciones_proveedor', o.observaciones_proveedor,
                   'items', (select count(*) from public.oc_items i where i.oc_id = o.id)) order by o.fecha_emision desc, o.codigo desc), '[]')
                   from public.ordenes_compra o left join public.sedes se on se.id = o.sede_entrega_id where o.tercero_id = v_t and o.empresa_id = p_empresa and o.estado not in ('borrador', 'anulada')),
    'evaluaciones', (select coalesce(jsonb_agg(jsonb_build_object('periodo', ev.periodo, 'cumplimiento', ev.cumplimiento, 'calidad', ev.calidad, 'precio', ev.precio, 'servicio', ev.servicio, 'total', ev.puntaje, 'concepto', ev.concepto) order by ev.periodo desc), '[]') from public.tercero_evaluaciones ev where ev.tercero_id = v_t and ev.empresa_id = p_empresa),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'categoria', p.categoria, 'unidad_compra', p.unidad_compra, 'unidad_base', p.unidad_base, 'factor_compra', p.factor_compra) order by p.categoria, p.nombre), '[]') from public.productos p where p.empresa_id = p_empresa and p.estado = 'activo')
  );
end $$;

-- A3 / M8 · portal_guardar_variante: ficha propia, presentacion obligatoria con contenido, sin cambios despues de evaluada
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
  if (select estado from public.ofertas where id = v_of) not in ('borrador', 'enviada') then raise exception 'La oferta ya fue evaluada; no se puede cambiar.'; end if;
  if coalesce(p->>'borrar', 'false') = 'true' then delete from public.oferta_lineas where id = v_id and oferta_id = v_of; update public.ofertas set actualizado_en = now() where id = v_of; return v_id; end if;
  -- A3: la ficha tecnica tiene que ser un adjunto del mismo proveedor
  if nullif(p->>'ficha_tecnica_id', '') is not null and not exists (select 1 from public.adjuntos a where a.id = (p->>'ficha_tecnica_id')::uuid and a.empresa_id = s.empresa_id and a.entidad = 'proveedor' and a.entidad_id = v_t) then
    raise exception 'La ficha tecnica debe ser un documento subido por su empresa en el portal.';
  end if;
  if (p->>'contenido') is not null and nullif(trim(coalesce(p->>'presentacion', '')), '') is null then raise exception 'Indique el nombre de la presentacion (ej.: Bulto 50 kg) cuando da el contenido.'; end if;
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

-- B7 · portal_proponer_precio: enlace correcto
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
  values (pp.empresa_id, 'M3', 'baja', 'Precio propuesto por ' || (select coalesce(t.nombre_comercial, t.razon_social) from public.terceros t where t.id = v_t), (select nombre from public.productos where id = pp.producto_id) || ': $ ' || to_char((p->>'precio')::numeric, 'FM999G999G999G990'), '/cotizaciones?t=propuestos', 'precio_propuesto', v_id);
  return v_id;
end $$;

-- M6 · portal_estado_oferta: guarda una foto de las variantes en cada envio
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
    update public.ofertas set estado = 'enviada', enviada_en = now(), enviada_por = auth.uid(), envios = coalesce(envios, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('fecha', now(), 'por', auth.uid(), 'variantes', (select jsonb_agg(to_jsonb(ol) - 'empresa_id' order by ol.linea_id, ol.variante) from public.oferta_lineas ol where ol.oferta_id = o.id))), validez_hasta = coalesce(p_validez, validez_hasta), condiciones = coalesce(p_condiciones, condiciones), actualizado_en = now() where id = o.id;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (s.empresa_id, 'M3', 'normal', 'Oferta recibida en ' || s.codigo, (select coalesce(t.nombre_comercial, t.razon_social) from public.terceros t where t.id = v_t) || ' cotizo ' || (select count(distinct linea_id) from public.oferta_lineas where oferta_id = o.id) || ' lineas', '/cotizaciones?id=' || s.id, 'solicitud', s.id);
  elsif p_accion = 'retirar' then
    if o.estado not in ('borrador', 'enviada') then raise exception 'La oferta ya fue evaluada.'; end if;
    update public.ofertas set estado = 'retirada', actualizado_en = now() where id = o.id;
  else raise exception 'Accion no valida'; end if;
end $$;


-- ---------------------------------------------------------------------
-- A2 · ninguna referencia de otra empresa en tablas de M3 / M4
-- ---------------------------------------------------------------------
create or replace function public.validar_empresa_m3m4() returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); v_emp uuid := (j->>'empresa_id')::uuid; x record; v_e uuid;
begin
  for x in select * from (values ('tercero_id', 'terceros'), ('explosion_id', 'explosiones'), ('contrato_id', 'contratos'), ('contrato_sede_id', 'contrato_sedes'),
      ('sede_entrega_id', 'sedes'), ('producto_id', 'productos'), ('proveedor_producto_id', 'proveedor_productos'), ('solicitud_id', 'solicitudes_cotizacion'),
      ('oferta_id', 'ofertas'), ('linea_id', 'solicitud_lineas'), ('oferta_linea_id', 'oferta_lineas'), ('oc_id', 'ordenes_compra'),
      ('ficha_tecnica_id', 'adjuntos'), ('adjunto_id', 'adjuntos'), ('marca_id', 'marcas'), ('presentacion_id', 'presentaciones')) v(c, t) loop
    if j ? x.c and j->>x.c is not null then
      execute format('select empresa_id from public.%I where id = $1', x.t) into v_e using (j->>x.c)::uuid;
      if v_e is distinct from v_emp then raise exception 'Referencia de otra empresa en %.%.', tg_table_name, x.c; end if;
    end if;
  end loop;
  return new;
end $$;
do $t$ declare t text; begin
  foreach t in array array['ordenes_compra', 'oc_items', 'solicitudes_cotizacion', 'solicitud_lineas', 'solicitud_invitados', 'ofertas', 'oferta_lineas', 'adjudicaciones',
                           'precios_propuestos', 'usuarios_proveedor', 'presentaciones', 'tercero_documentos', 'terceros', 'proveedor_productos', 'precios'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_empresa_m3m4', t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.validar_empresa_m3m4()', t || '_empresa_m3m4', t);
  end loop;
end $t$;

-- ---------------------------------------------------------------------
-- A1 · el proveedor ya no lee filas completas de tablas internas; el portal trabaja por RPC
-- ---------------------------------------------------------------------
drop policy if exists ordenes_compra_prov on public.ordenes_compra;
drop policy if exists oc_items_prov on public.oc_items;
drop policy if exists terceros_ver_propio on public.terceros;
drop policy if exists proveedor_productos_prov on public.proveedor_productos;
drop policy if exists precios_prov on public.precios;
drop policy if exists solicitudes_prov on public.solicitudes_cotizacion;
drop policy if exists solicitud_lineas_prov on public.solicitud_lineas;
drop policy if exists tercero_documentos_propio on public.tercero_documentos;

create or replace function public.portal_oc_items(p_oc uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o public.ordenes_compra;
begin
  select * into o from public.ordenes_compra where id = p_oc;
  if o.id is null or public.mi_tercero(o.empresa_id) is distinct from o.tercero_id or o.estado in ('borrador', 'anulada') then raise exception 'Sin acceso a esta OC'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('descripcion', i.descripcion, 'unidad_pedido', i.unidad_pedido, 'cantidad', i.cantidad, 'precio', i.precio,
            'iva_pct', i.iva_pct, 'total', i.total, 'cantidad_recibida', i.cantidad_recibida) order by i.descripcion), '[]') from public.oc_items i where i.oc_id = p_oc);
end $$;

-- ---------------------------------------------------------------------
-- M2 · policies con initplan: una sola evaluacion por consulta
-- ---------------------------------------------------------------------
do $p$ declare t text; begin
  foreach t in array array['terceros', 'tercero_contactos', 'tercero_puntos_despacho', 'tercero_documentos', 'tercero_bloqueos', 'tercero_evaluaciones', 'marcas', 'presentaciones', 'proveedor_productos', 'precios',
                           'ordenes_compra', 'oc_items', 'solicitudes_cotizacion', 'solicitud_lineas', 'solicitud_invitados', 'ofertas', 'oferta_lineas', 'adjudicaciones', 'precios_propuestos'] loop
    execute format('drop policy if exists %I on public.%I', t || '_ver', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_internas()))', t || '_ver', t);
  end loop;
  foreach t in array array['terceros', 'tercero_contactos', 'tercero_puntos_despacho', 'tercero_documentos', 'tercero_bloqueos', 'tercero_evaluaciones', 'marcas', 'presentaciones', 'proveedor_productos', 'precios'] loop
    execute format('drop policy if exists %I on public.%I', t || '_escribir', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_compras())) with check ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_compras()))', t || '_escribir', t);
  end loop;
end $p$;
-- lo que el proveedor si lee directo (lo que el mismo escribio y el catalogo)
drop policy if exists ofertas_prov on public.ofertas;
create policy ofertas_prov on public.ofertas for select to authenticated using (tercero_id in (select public.mis_terceros()));
drop policy if exists oferta_lineas_prov on public.oferta_lineas;
create policy oferta_lineas_prov on public.oferta_lineas for select to authenticated using (oferta_id in (select o.id from public.ofertas o where o.tercero_id in (select public.mis_terceros())));
drop policy if exists precios_propuestos_prov on public.precios_propuestos;
create policy precios_propuestos_prov on public.precios_propuestos for select to authenticated using (proveedor_producto_id in (select pp.id from public.proveedor_productos pp where pp.tercero_id in (select public.mis_terceros())));
drop policy if exists productos_prov on public.productos;
create policy productos_prov on public.productos for select to authenticated using (empresa_id in (select public.mis_empresas_proveedor()));
drop policy if exists marcas_prov on public.marcas;
create policy marcas_prov on public.marcas for select to authenticated using (empresa_id in (select public.mis_empresas_proveedor()));
drop policy if exists presentaciones_prov on public.presentaciones;
create policy presentaciones_prov on public.presentaciones for select to authenticated using (empresa_id in (select public.mis_empresas_proveedor()));
drop policy if exists empresas_ver_proveedor on public.empresas;
create policy empresas_ver_proveedor on public.empresas for select to authenticated using (id in (select public.mis_empresas_proveedor()));
drop policy if exists adjuntos_ver_proveedor on public.adjuntos;
create policy adjuntos_ver_proveedor on public.adjuntos for select to authenticated using (entidad = 'proveedor' and entidad_id in (select public.mis_terceros()));
drop policy if exists usuarios_proveedor_ver on public.usuarios_proveedor;
create policy usuarios_proveedor_ver on public.usuarios_proveedor for select to authenticated using ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_internas()) or usuario_id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- A3 · documentos del proveedor: quedan pendientes; Compras valida. Adjuntos: el proveedor no los edita ni borra
-- ---------------------------------------------------------------------
drop policy if exists adjuntos_editar on public.adjuntos;
create policy adjuntos_editar on public.adjuntos for update to authenticated
  using ((select public.es_superadmin()) or (subido_por = (select auth.uid()) and empresa_id in (select public.mis_empresas_internas())) or public.tiene_permiso(empresa_id, 'M0', 'editar'))
  with check ((select public.es_superadmin()) or (subido_por = (select auth.uid()) and empresa_id in (select public.mis_empresas_internas())) or public.tiene_permiso(empresa_id, 'M0', 'editar'));
drop policy if exists adjuntos_borrar on public.adjuntos;
create policy adjuntos_borrar on public.adjuntos for delete to authenticated
  using ((select public.es_superadmin()) or (subido_por = (select auth.uid()) and empresa_id in (select public.mis_empresas_internas())) or public.tiene_permiso(empresa_id, 'M0', 'editar'));

create table if not exists public.documentos_propuestos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tercero_id uuid not null references public.terceros(id) on delete cascade,
  codigo text not null references public.tipos_documento_tercero(codigo),
  adjunto_id uuid not null references public.adjuntos(id),
  fecha_documento date, vence date, numero text,
  estado text not null default 'propuesto' check (estado in ('propuesto', 'aceptado', 'rechazado')),
  resuelto_por uuid, resuelto_en timestamptz, nota_resolucion text,
  subido_por uuid default auth.uid(), creado_en timestamptz not null default now()
);
create index if not exists documentos_propuestos_idx on public.documentos_propuestos (tercero_id, codigo, creado_en desc);
alter table public.documentos_propuestos enable row level security;
drop policy if exists documentos_propuestos_ver on public.documentos_propuestos;
create policy documentos_propuestos_ver on public.documentos_propuestos for select to authenticated using ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_internas()) or tercero_id in (select public.mis_terceros()));
grant select on public.documentos_propuestos to authenticated;
drop trigger if exists documentos_propuestos_empresa_m3m4 on public.documentos_propuestos;
create trigger documentos_propuestos_empresa_m3m4 before insert or update on public.documentos_propuestos for each row execute function public.validar_empresa_m3m4();

create or replace function public.portal_documento(p_empresa uuid, p_codigo text, p_nombre text, p_ruta text, p_tipo_mime text default null, p_tamano bigint default null, p_fecha date default null, p_vence date default null, p_numero text default null)
returns uuid language plpgsql security definer set search_path = public, storage as $$
declare v_t uuid := public.mi_tercero(p_empresa); v_adj uuid; v_vig int; v_vence date; v_id uuid; v_hoy date := (now() at time zone 'America/Bogota')::date; v_tipo text;
begin
  if v_t is null then raise exception 'Solo para usuarios del portal de proveedores.'; end if;
  if p_ruta is null or p_ruta not like p_empresa::text || '/proveedor/' || v_t::text || '/%' or p_ruta like '%..%' then raise exception 'Ruta de archivo no valida.'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'adjuntos' and o.name = p_ruta) then raise exception 'El archivo no se encuentra; vuelva a subirlo.'; end if;
  select nombre, vigencia_dias into v_tipo, v_vig from public.tipos_documento_tercero where codigo = p_codigo;
  if v_tipo is null then raise exception 'Tipo de documento no valido.'; end if;
  if p_fecha is not null and p_fecha > v_hoy then raise exception 'La fecha del documento no puede ser futura.'; end if;
  -- con vigencia fija el vencimiento lo calcula el sistema; si no, lo que diga el proveedor (Compras lo revisa)
  v_vence := case when v_vig is not null then coalesce(p_fecha, v_hoy) + v_vig else p_vence end;
  insert into public.adjuntos (empresa_id, entidad, entidad_id, categoria, nombre, ruta, tipo_mime, tamano, vigente_desde, vigente_hasta, subido_nombre)
  values (p_empresa, 'proveedor', v_t, p_codigo, p_nombre, p_ruta, p_tipo_mime, p_tamano, p_fecha, v_vence, (select nombre from public.usuarios_proveedor where usuario_id = auth.uid() and empresa_id = p_empresa limit 1))
  returning id into v_adj;
  update public.documentos_propuestos set estado = 'rechazado', nota_resolucion = 'Reemplazado por una version nueva', resuelto_en = now()
   where tercero_id = v_t and codigo = p_codigo and estado = 'propuesto';
  insert into public.documentos_propuestos (empresa_id, tercero_id, codigo, adjunto_id, fecha_documento, vence, numero)
  values (p_empresa, v_t, p_codigo, v_adj, p_fecha, v_vence, p_numero) returning id into v_id;
  insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
  values (p_empresa, 'M3', 'baja', 'Documento por validar: ' || v_tipo, (select coalesce(t.nombre_comercial, t.razon_social) from public.terceros t where t.id = v_t) || coalesce(' · vence ' || to_char(v_vence, 'DD/MM/YYYY'), ''), '/proveedores?id=' || v_t, 'documento_propuesto', v_id);
  return v_id;
end $$;

create or replace function public.resolver_documento_propuesto(p_id uuid, p_acepta boolean, p_nota text default null, p_vence date default null) returns void language plpgsql security definer set search_path = public as $$
declare d public.documentos_propuestos;
begin
  select * into d from public.documentos_propuestos where id = p_id;
  if d.id is null then raise exception 'No encontrado'; end if;
  if not public.puede_compras(d.empresa_id, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if d.estado <> 'propuesto' then raise exception 'Ya fue resuelto (%).', d.estado; end if;
  if p_acepta then
    insert into public.tercero_documentos (empresa_id, tercero_id, codigo, fecha_documento, vence, numero, adjunto_id, notas)
    values (d.empresa_id, d.tercero_id, d.codigo, d.fecha_documento, coalesce(p_vence, d.vence), d.numero, d.adjunto_id, 'Validado desde el portal' || coalesce(': ' || p_nota, ''))
    on conflict (tercero_id, codigo) do update set fecha_documento = excluded.fecha_documento, vence = excluded.vence, numero = coalesce(excluded.numero, public.tercero_documentos.numero), adjunto_id = excluded.adjunto_id, notas = excluded.notas;
  end if;
  update public.documentos_propuestos set estado = case when p_acepta then 'aceptado' else 'rechazado' end, resuelto_por = auth.uid(), resuelto_en = now(), nota_resolucion = p_nota,
         vence = coalesce(p_vence, vence) where id = p_id;
end $$;

create or replace function public.documentos_propuestos_lista(p_tercero uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.terceros where id = p_tercero;
  if v_emp is null or not public.puede_compras(v_emp, 'ver') then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'codigo', d.codigo, 'tipo', td.nombre, 'fecha', d.fecha_documento, 'vence', d.vence, 'numero', d.numero, 'estado', d.estado, 'nota', d.nota_resolucion,
            'creado_en', d.creado_en, 'archivo', a.nombre, 'ruta', a.ruta, 'subido_por', a.subido_nombre, 'vigencia_dias', td.vigencia_dias) order by (d.estado = 'propuesto') desc, d.creado_en desc), '[]')
            from public.documentos_propuestos d join public.tipos_documento_tercero td on td.codigo = d.codigo join public.adjuntos a on a.id = d.adjunto_id where d.tercero_id = p_tercero);
end $$;

-- A3 · el proveedor ofrece productos sin reescribir el catalogo comun ni ofertas ya homologadas
create or replace function public.portal_ofrecer_producto(p jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_t uuid := public.mi_tercero((p->>'empresa_id')::uuid); v_marca uuid; v_pres uuid; v_cont numeric; v_pp uuid; v_estado text; v_prod uuid := (p->>'producto_id')::uuid;
begin
  if v_t is null then raise exception 'Sin acceso'; end if;
  if not exists (select 1 from public.productos where id = v_prod and empresa_id = v_emp and estado = 'activo') then raise exception 'Producto no valido.'; end if;
  if nullif(p->>'ficha_tecnica_id', '') is not null and not exists (select 1 from public.adjuntos a where a.id = (p->>'ficha_tecnica_id')::uuid and a.empresa_id = v_emp and a.entidad = 'proveedor' and a.entidad_id = v_t) then
    raise exception 'La ficha tecnica debe ser un documento subido por su empresa en el portal.';
  end if;
  if nullif(trim(coalesce(p->>'marca', '')), '') is not null then
    insert into public.marcas (empresa_id, nombre) values (v_emp, trim(p->>'marca')) on conflict (empresa_id, nombre) do update set nombre = excluded.nombre returning id into v_marca;
  end if;
  if nullif(trim(coalesce(p->>'presentacion', '')), '') is not null then
    if coalesce((p->>'contenido')::numeric, 0) <= 0 then raise exception 'La presentacion necesita el contenido (g, ml o und por empaque).'; end if;
    select id, contenido into v_pres, v_cont from public.presentaciones where empresa_id = v_emp and producto_id = v_prod and nombre = trim(p->>'presentacion');
    if v_pres is not null and v_cont <> (p->>'contenido')::numeric then
      raise exception 'Ya existe la presentacion "%" con contenido %. Use ese contenido o un nombre distinto.', trim(p->>'presentacion'), v_cont;
    end if;
    if v_pres is null then
      insert into public.presentaciones (empresa_id, producto_id, nombre, contenido, unidad_empaque) values (v_emp, v_prod, trim(p->>'presentacion'), (p->>'contenido')::numeric, coalesce(nullif(p->>'unidad_empaque', ''), 'und')) returning id into v_pres;
    end if;
  end if;
  select id, estado into v_pp, v_estado from public.proveedor_productos
   where tercero_id = v_t and producto_id = v_prod and marca_id is not distinct from v_marca and presentacion_id is not distinct from v_pres;
  if v_pp is not null and v_estado <> 'propuesto' then
    raise exception 'Ya tiene esta oferta registrada (%). Para cambiar el precio use Proponer precio; la ficha o el registro nuevos subalos en Documentos.', v_estado;
  end if;
  if v_pp is null then
    insert into public.proveedor_productos (empresa_id, tercero_id, producto_id, marca_id, presentacion_id, codigo_proveedor, lead_time_dias, entrega_en, origen, registro_sanitario, ficha_tecnica_id, estado, notas)
    values (v_emp, v_t, v_prod, v_marca, v_pres, p->>'codigo_proveedor', (p->>'lead_time_dias')::int, nullif(p->>'entrega_en', ''), nullif(p->>'origen', ''), p->>'registro_sanitario', nullif(p->>'ficha_tecnica_id', '')::uuid, 'propuesto', 'Propuesto por el proveedor en el portal')
    returning id into v_pp;
  else
    update public.proveedor_productos set codigo_proveedor = coalesce(p->>'codigo_proveedor', codigo_proveedor), lead_time_dias = coalesce((p->>'lead_time_dias')::int, lead_time_dias), entrega_en = coalesce(nullif(p->>'entrega_en', ''), entrega_en),
           origen = coalesce(nullif(p->>'origen', ''), origen), registro_sanitario = coalesce(p->>'registro_sanitario', registro_sanitario), ficha_tecnica_id = coalesce(nullif(p->>'ficha_tecnica_id', '')::uuid, ficha_tecnica_id)
     where id = v_pp and estado = 'propuesto';
  end if;
  if (p->>'precio') is not null then perform public.portal_proponer_precio(jsonb_build_object('pp_id', v_pp, 'precio', p->>'precio', 'iva_pct', p->>'iva_pct', 'condicion_pago', p->>'condicion_pago', 'plazo_dias', p->>'plazo_dias', 'lugar_entrega', p->>'entrega_en', 'nota', 'Producto nuevo ofrecido desde el portal')); end if;
  return v_pp;
end $$;

-- ---------------------------------------------------------------------
-- A4 / M4 · adjudicacion
-- ---------------------------------------------------------------------
create or replace function public.adjudicar_solicitud(p_solicitud uuid, p_items jsonb, p_fecha_entrega date default null, p_cerrar boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.solicitudes_cotizacion; it jsonb; v record; v_pp uuid; v_precio uuid; v_adj uuid; v_estado_pp text; g record; v_oc uuid; v_ids uuid[] := '{}'; v_cedi uuid; v_sede uuid;
        v_hoy date := (now() at time zone 'America/Bogota')::date; v_lugar text; v_exceso text;
begin
  select * into s from public.solicitudes_cotizacion where id = p_solicitud;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  if not public.puede_compras(s.empresa_id, 'aprobar') then raise exception 'Sin permiso (Compras: aprobar).'; end if;
  if s.estado not in ('publicada', 'cerrada') then raise exception 'La solicitud esta %.', s.estado; end if;
  if s.estado = 'publicada' and s.cierre > now() then raise exception 'La solicitud sigue abierta hasta el %; cierrela antes de adjudicar.', to_char(s.cierre at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'No hay lineas adjudicadas.'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x where coalesce((x->>'cantidad')::numeric, 0) <= 0) then raise exception 'Las cantidades adjudicadas deben ser mayores que cero.'; end if;
  -- tope: lo adjudicado (antes + ahora) no pasa de lo pedido + 10 %
  select string_agg(pr.nombre || ' (pedido ' || l.cantidad || ', adjudicado ' || q.total || ')', '; ') into v_exceso
    from (select l2.id, coalesce((select sum(a.cantidad) from public.adjudicaciones a where a.linea_id = l2.id), 0)
                        + coalesce((select sum((x->>'cantidad')::numeric) from jsonb_array_elements(p_items) x where (x->>'linea_id')::uuid = l2.id), 0) total
            from public.solicitud_lineas l2 where l2.solicitud_id = p_solicitud) q
    join public.solicitud_lineas l on l.id = q.id join public.productos pr on pr.id = l.producto_id
   where q.total > l.cantidad * 1.10;
  if v_exceso is not null then raise exception 'La cantidad adjudicada supera lo pedido en mas de 10 %%: %', v_exceso; end if;
  set local client_min_messages = warning;
  select id into v_cedi from public.sedes where empresa_id = s.empresa_id and tipo in ('cedi', 'bodega') and estado = 'activa' order by (tipo = 'cedi') desc, creado_en limit 1;
  drop table if exists tmp_adj;
  create temp table tmp_adj (adj_id uuid, tercero_id uuid, producto_id uuid, pp_id uuid, cantidad_compra numeric, factor numeric, lugar text, contrato_sede_id uuid, precio numeric, iva numeric,
                             contenido numeric, unidad text, descripcion text, motivo text, condicion_pago text, plazo_dias int) on commit drop;
  -- la de mayor cantidad se procesa al final: si dos variantes caen en la misma oferta de catalogo, su precio es el que queda en el master
  for it in select x from jsonb_array_elements(p_items) x order by (x->>'cantidad')::numeric loop
    select ol.*, o.tercero_id, o.validez_hasta, l.producto_id, l.contrato_sede_id lsede, pr.nombre producto, pr.unidad_compra, pr.factor_compra into v
      from public.oferta_lineas ol join public.ofertas o on o.id = ol.oferta_id join public.solicitud_lineas l on l.id = ol.linea_id join public.productos pr on pr.id = l.producto_id
     where ol.id = (it->>'oferta_linea_id')::uuid and ol.linea_id = (it->>'linea_id')::uuid and o.solicitud_id = p_solicitud and o.estado in ('enviada', 'adjudicada', 'parcial');
    if v.id is null then raise exception 'Variante de oferta no valida para esta linea de la solicitud.'; end if;
    if v.validez_hasta is not null and v.validez_hasta < v_hoy then raise exception 'La oferta de % vencio el %.', (select razon_social from public.terceros where id = v.tercero_id), to_char(v.validez_hasta, 'DD/MM/YYYY'); end if;
    if public.tercero_bloqueado(v.tercero_id) then raise exception 'El proveedor % tiene un bloqueo vigente; no se le puede adjudicar.', (select razon_social from public.terceros where id = v.tercero_id); end if;
    v_pp := public.alta_oferta(v.tercero_id, v.producto_id, v.marca, v.presentacion, v.contenido, v.unidad_empaque, null, null, 0, 'homologado', null, v.lead_time_dias, v.lugar_entrega);
    select estado into v_estado_pp from public.proveedor_productos where id = v_pp;
    if v_estado_pp in ('suspendido', 'rechazado') then
      raise exception 'La oferta de catalogo de % para % (%) esta %; levantela en la ficha del proveedor o adjudique otra opcion.', (select razon_social from public.terceros where id = v.tercero_id), v.producto, concat_ws(' · ', v.marca, v.presentacion), v_estado_pp;
    end if;
    update public.proveedor_productos set estado = 'homologado' where id = v_pp and estado = 'propuesto';
    update public.proveedor_productos set ficha_tecnica_id = coalesce(v.ficha_tecnica_id, ficha_tecnica_id), registro_sanitario = coalesce(v.registro_sanitario, registro_sanitario), origen = coalesce(v.origen, origen), minimo_pedido = coalesce(v.minimo_pedido, minimo_pedido) where id = v_pp;
    v_precio := public.registrar_precio(v_pp, v.precio, v_hoy, v.iva_pct, 'oferta_portal', coalesce(v.lugar_entrega, s.lugar_entrega, 'cedi'), null, s.codigo, 'Adjudicacion ' || s.codigo || ' opcion ' || v.variante);
    update public.precios set condicion_pago = v.condicion_pago, plazo_dias = case when v.condicion_pago = 'contado' then null else v.plazo_dias end, descuento_pronto_pago_pct = v.descuento_pronto_pago_pct, descuento_pronto_pago_dias = v.descuento_pronto_pago_dias,
           minimo_pedido = v.minimo_pedido, incluye_flete = v.incluye_flete, oferta_linea_id = v.id, aprobado_por = auth.uid(), aprobado_en = now() where id = v_precio;
    insert into public.adjudicaciones (empresa_id, solicitud_id, linea_id, oferta_linea_id, cantidad, motivo) values (s.empresa_id, p_solicitud, v.linea_id, v.id, (it->>'cantidad')::numeric, it->>'motivo') returning id into v_adj;
    v_lugar := case when v.lsede is not null and coalesce(v.lugar_entrega, s.lugar_entrega) <> 'cedi' then 'sede' else 'cedi' end;
    insert into tmp_adj values (v_adj, v.tercero_id, v.producto_id, v_pp, (it->>'cantidad')::numeric, coalesce(v.factor_compra, 1), v_lugar, case when v_lugar = 'sede' then v.lsede end,
      v.precio, v.iva_pct, coalesce(v.contenido, v.factor_compra, 1),
      case when v.contenido is null then v.unidad_compra else coalesce(nullif(trim(v.presentacion), ''), nullif(trim(v.unidad_empaque), ''), 'empaque') end,
      concat_ws(' · ', v.producto, v.marca, v.presentacion), coalesce(it->>'motivo', 'adjudicacion ' || s.codigo), v.condicion_pago, case when v.condicion_pago = 'contado' then null else v.plazo_dias end);
  end loop;
  -- una OC por proveedor + lugar + establecimiento + condicion de pago
  for g in select tercero_id, lugar, contrato_sede_id, condicion_pago, plazo_dias from tmp_adj group by 1, 2, 3, 4, 5 loop
    if g.lugar = 'sede' then select cs.sede_id into v_sede from public.contrato_sedes cs where cs.id = g.contrato_sede_id; else v_sede := v_cedi; end if;
    insert into public.ordenes_compra (empresa_id, codigo, tercero_id, explosion_id, contrato_id, lugar_entrega, sede_entrega_id, contrato_sede_id, fecha_entrega, condicion_pago, plazo_dias, notas)
    select s.empresa_id, public.siguiente_consecutivo(s.empresa_id, 'OC'), t.id, s.explosion_id, s.contrato_id, g.lugar, v_sede, g.contrato_sede_id, coalesce(p_fecha_entrega, s.entrega_desde),
           coalesce(g.condicion_pago, t.condicion_pago), case when coalesce(g.condicion_pago, t.condicion_pago) = 'contado' then null else coalesce(g.plazo_dias, t.plazo_dias) end, 'Adjudicacion de la solicitud ' || s.codigo
      from public.terceros t where t.id = g.tercero_id returning id into v_oc;
    v_ids := v_ids || v_oc;
    insert into public.oc_items (empresa_id, oc_id, producto_id, proveedor_producto_id, descripcion, unidad_pedido, contenido_base, cantidad, cantidad_base, precio, iva_pct, requerida_base, motivo)
    select s.empresa_id, v_oc, a.producto_id, a.pp_id, a.descripcion, a.unidad, a.contenido, ceil(a.cantidad_compra * a.factor / a.contenido), 0, a.precio, a.iva, a.cantidad_compra * a.factor, a.motivo
      from tmp_adj a where a.tercero_id = g.tercero_id and a.lugar = g.lugar and a.contrato_sede_id is not distinct from g.contrato_sede_id and a.condicion_pago is not distinct from g.condicion_pago and a.plazo_dias is not distinct from g.plazo_dias;
    update public.adjudicaciones ad set oc_id = v_oc from tmp_adj a
     where ad.id = a.adj_id and a.tercero_id = g.tercero_id and a.lugar = g.lugar and a.contrato_sede_id is not distinct from g.contrato_sede_id and a.condicion_pago is not distinct from g.condicion_pago and a.plazo_dias is not distinct from g.plazo_dias;
  end loop;
  update public.ofertas set estado = 'retirada', actualizado_en = now() where solicitud_id = p_solicitud and estado = 'borrador';
  update public.ofertas o set estado = case when exists (select 1 from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id)
                                             then case when (select count(distinct ol.linea_id) from public.oferta_lineas ol where ol.oferta_id = o.id) = (select count(distinct ol.linea_id) from public.adjudicaciones a join public.oferta_lineas ol on ol.id = a.oferta_linea_id where ol.oferta_id = o.id) then 'adjudicada' else 'parcial' end
                                             else case when p_cerrar then 'no_adjudicada' else o.estado end end, actualizado_en = now()
   where o.solicitud_id = p_solicitud and o.estado in ('enviada', 'adjudicada', 'parcial', 'no_adjudicada');
  update public.solicitudes_cotizacion set estado = case when p_cerrar then 'adjudicada' else 'cerrada' end, cerrada_en = coalesce(cerrada_en, now()), actualizado_en = now() where id = p_solicitud;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'total', o.total) order by o.codigo), '[]') from public.ordenes_compra o where o.id = any(v_ids));
end $$;

-- ---------------------------------------------------------------------
-- M6 · bitacora en las tablas de OC y del portal
-- ---------------------------------------------------------------------
do $b$ declare t text; begin
  foreach t in array array['solicitudes_cotizacion', 'solicitud_lineas', 'solicitud_invitados', 'ofertas', 'oferta_lineas', 'adjudicaciones', 'precios_propuestos', 'usuarios_proveedor', 'documentos_propuestos', 'ordenes_compra', 'oc_items'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_bitacora', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t || '_bitacora', t);
  end loop;
end $b$;

-- ---------------------------------------------------------------------
-- B1 y grants
-- ---------------------------------------------------------------------
do $g$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('precio_base_producto', 'tercero_bloqueado', 've_sede', 'es_empresa_demo', 'dv_nit',
              'alta_oferta', 'sugerir_compra', 'generar_oc', 'costo_ciclo', 'invitar_usuario_proveedor', 'guardar_solicitud', 'comparar_ofertas', 'portal_resumen', 'portal_guardar_variante',
              'portal_proponer_precio', 'portal_estado_oferta', 'portal_oc_items', 'portal_documento', 'resolver_documento_propuesto', 'documentos_propuestos_lista', 'portal_ofrecer_producto', 'adjudicar_solicitud') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function %s to service_role', f); end if;
  end loop;
end $g$;
