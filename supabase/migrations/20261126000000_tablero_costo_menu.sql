-- =====================================================================
-- Supply ERP · Migracion 026 · M3 parte 3: tablero de costo por tiempo de comida y componente
--   · costo_ciclo: para un ciclo de menus (y un grupo de poblacion de referencia), el costo por racion de cada casilla
--     (menu x tiempo x componente) = suma de ingredientes crudos (con gramajes vigentes) x mejor precio vigente por unidad base
--     del master de precios. Devuelve ademas el resumen lateral (menu mas y menos costoso, tiempo mas y menos costoso,
--     por tiempo cual menu es el mas caro y el mas barato, componente que mas pesa, productos sin precio) y las
--     sugerencias de intercambio: alternativas de la misma familia que bajan el costo, con el ahorro por racion,
--     por vuelta de ciclo y por mes segun la poblacion vigente del contrato.
--   · simular_precios_demo: solo en empresas de practica, carga precios plausibles por categoria (marcados SIMULADO)
--     para los productos sin precio, para poder ver el tablero mientras llegan las listas reales.
-- =====================================================================

-- precio vigente por unidad base de un producto (mejor opcion: homologada o condicionada, sin bloqueo, aceptada)
create or replace function public.precio_base_producto(p_producto uuid, p_fecha date)
returns table (por_unidad_base numeric, proveedor text, pp_id uuid, simulado boolean) language sql stable rows 1 as $$
  select x.por_unidad_base, coalesce(t.nombre_comercial, t.razon_social), pp.id, coalesce(x.notas, '') ilike '%SIMULADO%'
    from public.proveedor_productos pp
    join public.terceros t on t.id = pp.tercero_id
    join public.precios x on x.proveedor_producto_id = pp.id
   where pp.producto_id = p_producto and pp.estado in ('homologado', 'condicionado') and t.estado = 'activo'
     and x.estado = 'aceptado' and x.vigente_desde <= p_fecha and (x.vigente_hasta is null or x.vigente_hasta >= p_fecha)
     and not public.tercero_bloqueado(t.id, p_fecha)
   order by x.por_unidad_base, pp.preferido desc
   limit 1;
$$;

create or replace function public.costo_ciclo(p_ciclo uuid, p_grupo uuid default null, p_fecha date default null, p_top int default 12)
returns jsonb language plpgsql volatile security definer set search_path = public set jit = off as $$
declare c public.ciclos_menu; v_f date; v_grupo uuid; v_dias_mes numeric; r jsonb;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M3', 'ver') or public.tiene_permiso(c.empresa_id, 'M2', 'ver')) then raise exception 'Sin permiso'; end if;
  v_f := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date);
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
    'fecha', v_f, 'dias_mes', v_dias_mes,
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
revoke all on function public.costo_ciclo(uuid, uuid, date, int) from public, anon; grant execute on function public.costo_ciclo(uuid, uuid, date, int) to authenticated;

-- ---------------------------------------------------------------------
-- Precios simulados para empresas de practica (nit 90000000X o "demo" en la razon social)
-- ---------------------------------------------------------------------
create or replace function public.es_empresa_demo(p_empresa uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.empresas e where e.id = p_empresa and (e.nit ~ '^90000000\d$' or e.razon_social ilike '%demo%' or e.razon_social ilike '%practica%'));
$$;

create or replace function public.simular_precios_demo(p_empresa uuid, p_semilla int default 7)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_t uuid; v_n int := 0; p record; v_precio numeric; v_pp uuid; v_h numeric;
begin
  if not public.puede_compras(p_empresa, 'crear') then raise exception 'Sin permiso (Compras: crear).'; end if;
  if not public.es_empresa_demo(p_empresa) then raise exception 'Los precios simulados solo se cargan en empresas de practica.'; end if;
  select id into v_t from public.terceros where empresa_id = p_empresa and numero = '900000099';
  if v_t is null then
    insert into public.terceros (empresa_id, numero, dv, razon_social, nombre_comercial, tipo_proveedor, categorias, estado_homologacion, entrega_en, condicion_pago, plazo_dias, lead_time_dias, ciudad, notas)
    values (p_empresa, '900000099', public.dv_nit('900000099'), 'Proveedor Simulado de Practica SAS', 'SIMULADO (practica)', 'distribuidor', '{proteinas,fruver,lacteos,abarrotes,panaderia,bebidas,otros}', 'homologado', 'ambos', 'credito', 30, 2, 'Practica',
            'Precios SIMULADOS por categoria para ver el tablero de costos. Reemplazar por listas reales.')
    returning id into v_t;
  end if;
  for p in select pr.* from public.productos pr where pr.empresa_id = p_empresa and pr.estado = 'activo'
             and not exists (select 1 from public.precio_base_producto(pr.id, (now() at time zone 'America/Bogota')::date)) loop
    v_h := (abs(hashtext(p.codigo || p_semilla::text)) % 1000) / 1000.0;   -- 0 a 1 estable por producto
    -- COP por kg / l / unidad segun categoria (rangos del mercado colombiano 2026, redondeados)
    v_precio := case p.categoria
      when 'proteinas' then 12000 + v_h * 14000
      when 'fruver' then 2200 + v_h * 4800
      when 'lacteos' then 4500 + v_h * 6500
      when 'panaderia' then 5000 + v_h * 6000
      when 'bebidas' then 2500 + v_h * 4500
      when 'abarrotes' then 2800 + v_h * 9200
      when 'aseo' then 6000 + v_h * 10000
      when 'desechables' then 8000 + v_h * 12000
      else 3000 + v_h * 7000 end;
    if p.unidad_base = 'und' then v_precio := 400 + v_h * 1600; end if;   -- huevo, arepa, pan, bocadillo: por unidad
    v_precio := round(v_precio / 50) * 50;
    -- oferta a granel por unidad de compra del producto (kg, l, und)
    insert into public.proveedor_productos (empresa_id, tercero_id, producto_id, estado, homologado_en, notas)
    values (p_empresa, v_t, p.id, 'homologado', now(), 'SIMULADO') on conflict do nothing returning id into v_pp;
    if v_pp is null then select id into v_pp from public.proveedor_productos where tercero_id = v_t and producto_id = p.id and marca_id is null and presentacion_id is null; end if;
    -- precio por unidad de compra: si la unidad base es g o ml, el factor de compra dice cuantas trae (kg = 1000); por und el factor suele ser 1
    insert into public.precios (empresa_id, proveedor_producto_id, precio, por_unidad_base, iva_pct, vigente_desde, origen, lugar_entrega, notas)
    values (p_empresa, v_pp, case when p.unidad_base = 'und' then v_precio * coalesce(p.factor_compra, 1) else v_precio * coalesce(p.factor_compra, 1000) / 1000 end, 0, 0, (now() at time zone 'America/Bogota')::date - 1, 'importacion', 'cedi', 'SIMULADO por categoria');
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('proveedor_id', v_t, 'precios_creados', v_n);
end $$;
revoke all on function public.simular_precios_demo(uuid, int) from public, anon; grant execute on function public.simular_precios_demo(uuid, int) to authenticated;

do $g$
declare f text;
begin
  foreach f in array array['precio_base_producto(uuid, date)', 'costo_ciclo(uuid, uuid, date, int)', 'es_empresa_demo(uuid)', 'simular_precios_demo(uuid, int)'] loop
    execute format('grant execute on function public.%s to authenticated', f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function public.%s to service_role', f); end if;
  end loop;
end $g$;
