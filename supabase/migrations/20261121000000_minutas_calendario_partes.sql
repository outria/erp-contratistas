-- Supply ERP · Migracion 021 · Minutas y calendario: ciclos de menu editables, asignacion por sede, gramajes por grupo
-- (etario o sexo), calendario de servicio por rangos, partes diarios y requerimiento por establecimiento.
set client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 0. Gramajes proporcionales: un ajuste a nivel de componente o preparacion (porcion servida del grupo etario, por ejemplo)
--    escala TODA la receta en la misma proporcion que el ingrediente principal, en vez de aplicar la porcion a cada ingrediente.
--    Un ajuste a nivel de producto sigue aplicando solo a ese producto.
-- ---------------------------------------------------------------------
create or replace function public.crudo_ingrediente(p_contrato uuid, p_contrato_sede uuid, p_fecha date, p_preparacion uuid, p_producto uuid, p_grupo uuid, p_componente uuid, p_peso_bruto numeric)
returns table(crudo numeric, nota text) language sql stable rows 1 as $$
  with a as (
    select g.* from public.gramajes_ajuste g
     where g.contrato_id = p_contrato
       and (g.contrato_sede_id = p_contrato_sede or g.contrato_sede_id is null)
       and (g.grupo_poblacion_id = p_grupo or g.grupo_poblacion_id is null)
       and (g.producto_id = p_producto or (g.producto_id is null and g.preparacion_id = p_preparacion) or (g.producto_id is null and g.preparacion_id is null and g.componente_id = p_componente))
       and g.vigente_desde <= p_fecha and (g.vigente_hasta is null or g.vigente_hasta >= p_fecha)
     order by g.contrato_sede_id nulls last, g.producto_id nulls last, g.preparacion_id nulls last, g.grupo_poblacion_id nulls last, g.vigente_desde desc
     limit 1),
  -- ingrediente principal de la receta para el grupo (o el generico) y su factor de coccion
  pr as (
    select pi.producto_id, pi.peso_bruto,
           coalesce((select f.factor from public.factores_coccion f join public.preparaciones pp on pp.id = p_preparacion where f.producto_id = pi.producto_id and f.metodo = pp.metodo_coccion limit 1),
                    (select x.rendimiento from public.productos x where x.id = pi.producto_id), 1) as factor
      from public.preparacion_ingredientes pi
     where pi.preparacion_id = p_preparacion and pi.es_principal and (pi.grupo_poblacion_id = p_grupo or pi.grupo_poblacion_id is null)
     order by pi.grupo_poblacion_id nulls last limit 1),
  f as (
    select coalesce((select f.factor from public.factores_coccion f join public.preparaciones pp on pp.id = p_preparacion where f.producto_id = p_producto and f.metodo = pp.metodo_coccion limit 1),
                    (select x.rendimiento from public.productos x where x.id = p_producto), 1) as factor)
  select case
           when a.id is null then p_peso_bruto
           -- ajuste directo sobre este producto
           when a.producto_id is not null and a.peso_bruto is not null then a.peso_bruto
           when a.producto_id is not null and a.factor_crudo is not null then p_peso_bruto * a.factor_crudo
           when a.producto_id is not null and a.porcion_servida is not null then a.porcion_servida / nullif(f.factor, 0)
           -- ajuste de la preparacion o del componente: proporcional al principal
           when a.factor_crudo is not null then p_peso_bruto * a.factor_crudo
           when pr.producto_id = p_producto and a.peso_bruto is not null then a.peso_bruto
           when pr.producto_id = p_producto and a.porcion_servida is not null then a.porcion_servida / nullif(pr.factor, 0)
           when pr.producto_id is not null and pr.peso_bruto > 0 and a.peso_bruto is not null then p_peso_bruto * (a.peso_bruto / pr.peso_bruto)
           when pr.producto_id is not null and pr.peso_bruto > 0 and a.porcion_servida is not null then p_peso_bruto * ((a.porcion_servida / nullif(pr.factor, 0)) / pr.peso_bruto)
           else p_peso_bruto end,
         case when a.id is null then null
              when a.peso_bruto is not null then 'ajuste crudo'
              when a.factor_crudo is not null then 'ajuste factor ' || a.factor_crudo
              when a.porcion_servida is not null then 'servido ' || a.porcion_servida || case when a.grupo_poblacion_id is not null then ' (grupo)' else '' end end
    from (select 1) uno left join a on true left join pr on true cross join f;
$$;

-- ---------------------------------------------------------------------
-- 1. Lectura general para la pantalla
-- ---------------------------------------------------------------------
create or replace function public.minutas_contrato(p_contrato uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_hoy date := (now() at time zone 'America/Bogota')::date; r jsonb;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  select jsonb_build_object(
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'modalidad', c.modalidad, 'dias_atencion', c.dias_atencion, 'n_menus_ciclo', c.n_menus_ciclo, 'fecha_inicio', c.fecha_inicio, 'fecha_fin', c.fecha_fin_inicial) from public.contratos c where c.id = p_contrato),
    'grupos', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nombre', g.nombre, 'tipo', g.tipo) order by g.orden), '[]') from public.grupos_poblacion g where g.contrato_id = p_contrato),
    'tiempos', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden) order by t.orden), '[]') from public.tiempos_comida t where t.contrato_id = p_contrato),
    'componentes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'tiempo_id', c.tiempo_comida_id, 'orden', c.orden, 'obligatorio', c.obligatorio, 'familia_id', c.familia_id) order by t.orden, c.orden), '[]')
                      from public.componentes c join public.tiempos_comida t on t.id = c.tiempo_comida_id where c.contrato_id = p_contrato),
    'variantes', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'codigo', v.codigo, 'nombre', v.nombre, 'es_estandar', v.es_estandar, 'excluidos', v.componentes_excluidos) order by v.es_estandar desc, v.codigo), '[]') from public.variantes_racion v where v.contrato_id = p_contrato),
    'ciclos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'n_menus', c.n_menus, 'tipo', c.tipo, 'estado', c.estado, 'vigente_desde', c.vigente_desde, 'vigente_hasta', c.vigente_hasta, 'oficio', c.oficio_aprobacion,
                   'items', (select count(*) from public.ciclo_menu_items i where i.ciclo_id = c.id), 'sin_receta', (select count(*) from public.ciclo_menu_items i where i.ciclo_id = c.id and i.preparacion_id is null),
                   'sedes', (select count(distinct sc.contrato_sede_id) from public.sede_ciclo sc where sc.ciclo_id = c.id and sc.vigente_desde <= v_hoy and (sc.vigente_hasta is null or sc.vigente_hasta >= v_hoy))) order by c.estado = 'vigente' desc, c.codigo), '[]')
                 from public.ciclos_menu c where c.contrato_id = p_contrato and c.estado <> 'anulado'),
    'sedes', (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre, 'ciudad', s.ciudad, 'subtipo', s.subtipo,
                 'asignacion', (select jsonb_build_object('id', sc.id, 'ciclo_id', sc.ciclo_id, 'variante_id', sc.variante_id, 'fecha_inicio_menu1', sc.fecha_inicio_menu1, 'modo_reinicio', sc.modo_reinicio, 'avanza_sin_servicio', sc.avanza_sin_servicio, 'vigente_desde', sc.vigente_desde, 'menu_confirmado', sc.menu_confirmado)
                                  from public.sede_ciclo sc where sc.contrato_sede_id = cs.id and sc.vigente_desde <= v_hoy and (sc.vigente_hasta is null or sc.vigente_hasta >= v_hoy) order by sc.vigente_desde desc limit 1),
                 'dia_hoy', (select dc.dia from public.dia_ciclo(cs.id, v_hoy) dc),
                 'excepciones', (select count(*) from public.calendario_servicio x where x.contrato_sede_id = cs.id and x.fecha >= v_hoy)
               ) order by s.nombre), '[]')
                from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.contrato_id = p_contrato and cs.estado = 'activa'),
    -- gramajes vigentes a nivel de contrato: por componente y grupo (porcion servida) mas el peso del principal de referencia
    'gramajes', (select coalesce(jsonb_agg(jsonb_build_object('componente_id', g.componente_id, 'grupo_id', g.grupo_poblacion_id, 'porcion_servida', g.porcion_servida, 'peso_bruto', g.peso_bruto, 'factor', g.factor_crudo, 'desde', g.vigente_desde, 'motivo', g.motivo)), '[]')
                   from public.gramajes_ajuste g where g.contrato_id = p_contrato and g.contrato_sede_id is null and g.producto_id is null and g.preparacion_id is null and g.componente_id is not null
                    and g.vigente_desde <= v_hoy and (g.vigente_hasta is null or g.vigente_hasta >= v_hoy)),
    'referencia', (select coalesce(jsonb_agg(jsonb_build_object('componente_id', x.componente_id, 'servido', round(x.servido), 'crudo', round(x.crudo), 'principal', x.nombre)), '[]')
                     from (select distinct on (c.id) c.id as componente_id, pi.peso_bruto as crudo,
                                  pi.peso_bruto * coalesce((select f.factor from public.factores_coccion f where f.producto_id = pi.producto_id and f.metodo = p.metodo_coccion limit 1), pr.rendimiento, 1) as servido, pr.nombre
                             from public.componentes c
                             join public.ciclo_menu_items i on i.componente_id = c.id
                             join public.preparaciones p on p.id = i.preparacion_id
                             join public.preparacion_ingredientes pi on pi.preparacion_id = p.id and pi.es_principal and pi.grupo_poblacion_id is null
                             join public.productos pr on pr.id = pi.producto_id
                            where c.contrato_id = p_contrato order by c.id, i.dia) x),
    'festivos', (select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]') from public.festivos f where f.fecha between v_hoy - 60 and v_hoy + 400)
  ) into r;
  return r;
end $$;
revoke all on function public.minutas_contrato(uuid) from public, anon;

-- detalle de un ciclo: items por dia x tiempo x componente y las opciones de cada componente (familia)
create or replace function public.ciclo_detalle(p_ciclo uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare c public.ciclos_menu;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver') or public.tiene_permiso(c.empresa_id, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'ciclo', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'n_menus', c.n_menus, 'tipo', c.tipo, 'estado', c.estado, 'contrato_id', c.contrato_id, 'variante_id', c.variante_id),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('dia', i.dia, 'tiempo_id', i.tiempo_comida_id, 'componente_id', i.componente_id, 'preparacion_id', i.preparacion_id, 'preparacion', p.nombre, 'descriptor', i.descriptor,
                 'principal', (select pr.nombre from public.preparacion_ingredientes pi join public.productos pr on pr.id = pi.producto_id where pi.preparacion_id = p.id and pi.es_principal limit 1))), '[]')
                from public.ciclo_menu_items i left join public.preparaciones p on p.id = i.preparacion_id where i.ciclo_id = p_ciclo),
    -- opciones por componente: las de la familia del componente (en minuta primero) y, si no hay familia, las preparaciones del mismo componente
    'opciones', (select coalesce(jsonb_object_agg(x.componente_id, x.ops), '{}')
                   from (select co.id as componente_id,
                                (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'en_minuta', o.en_minuta) order by o.en_minuta desc nulls last, p.nombre), '[]')
                                   from public.preparaciones p
                                   left join public.familia_opciones o on o.preparacion_id = p.id and o.familia_id = co.familia_id and o.estado = 'vigente'
                                  where p.empresa_id = c.empresa_id and p.estado = 'activa' and (p.contrato_id is null or p.contrato_id = c.contrato_id)
                                    and ((co.familia_id is not null and o.id is not null) or (co.familia_id is null and p.componente_codigo = co.codigo))) as ops
                           from public.componentes co where co.contrato_id = c.contrato_id) x)
  );
end $$;
revoke all on function public.ciclo_detalle(uuid) from public, anon;

-- ---------------------------------------------------------------------
-- 2. Edicion de ciclos
-- ---------------------------------------------------------------------
create or replace function public.puede_editar_planeacion(p_empresa uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(p_empresa, 'M2', 'editar');
$$;
revoke all on function public.puede_editar_planeacion(uuid) from public, anon;

create or replace function public.guardar_ciclo_item(p_ciclo uuid, p_dia int, p_tiempo uuid, p_componente uuid, p_preparacion uuid, p_descriptor text default null)
returns void language plpgsql security definer set search_path = public as $$
declare c public.ciclos_menu;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not public.puede_editar_planeacion(c.empresa_id) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if c.estado in ('historico', 'anulado') then raise exception 'Este ciclo ya no se edita (%). Cree uno nuevo copiandolo.', c.estado; end if;
  if p_dia < 1 or p_dia > c.n_menus then raise exception 'El dia % no existe en un ciclo de % menus.', p_dia, c.n_menus; end if;
  if p_preparacion is null and p_descriptor is null then
    delete from public.ciclo_menu_items where ciclo_id = p_ciclo and dia = p_dia and tiempo_comida_id = p_tiempo and componente_id = p_componente;
  else
    insert into public.ciclo_menu_items (empresa_id, ciclo_id, dia, tiempo_comida_id, componente_id, preparacion_id, descriptor)
    values (c.empresa_id, p_ciclo, p_dia, p_tiempo, p_componente, p_preparacion, p_descriptor)
    on conflict (ciclo_id, dia, tiempo_comida_id, componente_id) do update set preparacion_id = excluded.preparacion_id, descriptor = excluded.descriptor;
  end if;
end $$;
revoke all on function public.guardar_ciclo_item(uuid, int, uuid, uuid, uuid, text) from public, anon;

-- crear un ciclo (vacio o copiando otro) y cambiar su estado
create or replace function public.crear_ciclo(p_contrato uuid, p_codigo text, p_nombre text, p_n_menus int, p_copiar_de uuid default null, p_tipo text default 'estandar', p_variante uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not public.puede_editar_planeacion(v_emp) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if coalesce(trim(p_codigo), '') = '' then raise exception 'El ciclo necesita un codigo.'; end if;
  insert into public.ciclos_menu (empresa_id, contrato_id, codigo, nombre, n_menus, tipo, estado, variante_id)
  values (v_emp, p_contrato, upper(trim(p_codigo)), p_nombre, p_n_menus, coalesce(p_tipo, 'estandar'), 'borrador', p_variante) returning id into v_id;
  if p_copiar_de is not null then
    insert into public.ciclo_menu_items (empresa_id, ciclo_id, dia, tiempo_comida_id, componente_id, preparacion_id, descriptor)
    select v_emp, v_id, i.dia, i.tiempo_comida_id, i.componente_id, i.preparacion_id, i.descriptor
      from public.ciclo_menu_items i join public.ciclos_menu o on o.id = i.ciclo_id
     where i.ciclo_id = p_copiar_de and o.contrato_id = p_contrato and i.dia <= p_n_menus;
  end if;
  return v_id;
end $$;
revoke all on function public.crear_ciclo(uuid, text, text, int, uuid, text, uuid) from public, anon;

create or replace function public.estado_ciclo(p_ciclo uuid, p_estado text, p_oficio text default null, p_vigente_desde date default null)
returns void language plpgsql security definer set search_path = public as $$
declare c public.ciclos_menu;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not public.puede_editar_planeacion(c.empresa_id) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_estado not in ('borrador', 'vigente', 'historico', 'anulado') then raise exception 'Estado no valido'; end if;
  if p_estado = 'vigente' and exists (select 1 from public.ciclo_menu_items i where i.ciclo_id = p_ciclo and i.preparacion_id is null and i.descriptor is null) then
    raise exception 'Hay casillas sin receta; complete el ciclo antes de ponerlo vigente.';
  end if;
  if p_estado = 'anulado' and exists (select 1 from public.sede_ciclo sc where sc.ciclo_id = p_ciclo and (sc.vigente_hasta is null or sc.vigente_hasta >= current_date)) then
    raise exception 'Hay sedes con este ciclo asignado; cambieles el ciclo primero.';
  end if;
  update public.ciclos_menu set estado = p_estado, oficio_aprobacion = coalesce(p_oficio, oficio_aprobacion), vigente_desde = coalesce(p_vigente_desde, vigente_desde),
         tipo = case when p_estado = 'vigente' and p_oficio is not null then 'aprobado' else tipo end
   where id = p_ciclo;
end $$;
revoke all on function public.estado_ciclo(uuid, text, text, date) from public, anon;

-- asignar ciclo a una o varias sedes desde una fecha (cierra la asignacion anterior el dia antes)
create or replace function public.asignar_ciclo(p_sedes uuid[], p_ciclo uuid, p_variante uuid, p_fecha_inicio_menu1 date, p_desde date, p_modo text default 'continuo', p_avanza_sin_servicio boolean default null)
returns int language plpgsql security definer set search_path = public as $$
declare c public.ciclos_menu; v_cs uuid; n int := 0; v_avanza boolean;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not public.puede_editar_planeacion(c.empresa_id) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if c.estado = 'anulado' then raise exception 'El ciclo esta anulado.'; end if;
  if p_desde is null or p_fecha_inicio_menu1 is null then raise exception 'Falta la fecha desde la que rige o la fecha del menu 1.'; end if;
  if p_modo not in ('continuo', 'mensual', 'semanal') then raise exception 'Modo de reinicio no valido'; end if;
  v_avanza := coalesce(p_avanza_sin_servicio, (select coalesce((pl.esquema->>'avanza_sin_servicio')::boolean, true) from public.plantillas_modalidad pl join public.contratos ct on ct.modalidad = pl.codigo where ct.id = c.contrato_id), true);
  foreach v_cs in array p_sedes loop
    if not exists (select 1 from public.contrato_sedes cs where cs.id = v_cs and cs.contrato_id = c.contrato_id) then raise exception 'La sede no pertenece al contrato del ciclo.'; end if;
    delete from public.sede_ciclo where contrato_sede_id = v_cs and vigente_desde = p_desde;
    update public.sede_ciclo set vigente_hasta = p_desde - 1 where contrato_sede_id = v_cs and vigente_desde < p_desde and (vigente_hasta is null or vigente_hasta >= p_desde);
    insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, menu_confirmado, creado_por)
    values (c.empresa_id, v_cs, p_ciclo, coalesce(p_variante, c.variante_id, (select id from public.variantes_racion v where v.contrato_id = c.contrato_id and v.es_estandar)), p_fecha_inicio_menu1, p_modo, v_avanza, p_desde, true, auth.uid());
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.asignar_ciclo(uuid[], uuid, uuid, date, date, text, boolean) from public, anon;

-- ---------------------------------------------------------------------
-- 3. Gramajes por componente y grupo (porcion servida que fija el lineamiento o la nutricionista)
--    p_items: [{componente_id, grupo_id (null = todos), porcion_servida, peso_bruto}]
-- ---------------------------------------------------------------------
create or replace function public.guardar_gramajes(p_contrato uuid, p_desde date, p_items jsonb, p_motivo text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_c uuid; v_g uuid; v_ps numeric; v_pb numeric;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not public.puede_editar_planeacion(v_emp) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_desde is null then raise exception 'Falta la fecha desde la que rigen los gramajes.'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_c := (it->>'componente_id')::uuid; v_g := (it->>'grupo_id')::uuid; v_ps := nullif(it->>'porcion_servida', '')::numeric; v_pb := nullif(it->>'peso_bruto', '')::numeric;
    if v_c is null then raise exception 'Cada gramaje necesita componente.'; end if;
    delete from public.gramajes_ajuste g where g.contrato_id = p_contrato and g.contrato_sede_id is null and g.producto_id is null and g.preparacion_id is null
       and g.componente_id = v_c and g.grupo_poblacion_id is not distinct from v_g and g.vigente_desde = p_desde;
    update public.gramajes_ajuste g set vigente_hasta = p_desde - 1
     where g.contrato_id = p_contrato and g.contrato_sede_id is null and g.producto_id is null and g.preparacion_id is null
       and g.componente_id = v_c and g.grupo_poblacion_id is not distinct from v_g and g.vigente_desde < p_desde and (g.vigente_hasta is null or g.vigente_hasta >= p_desde);
    if v_ps is not null or v_pb is not null then
      insert into public.gramajes_ajuste (empresa_id, contrato_id, grupo_poblacion_id, componente_id, porcion_servida, peso_bruto, motivo, vigente_desde, aprobado_por)
      values (v_emp, p_contrato, v_g, v_c, v_ps, v_pb, coalesce(p_motivo, 'gramaje por grupo'), p_desde, auth.uid());
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.guardar_gramajes(uuid, date, jsonb, text) from public, anon;

-- ---------------------------------------------------------------------
-- 4. Calendario de servicio por rangos (dias de clase, receso, vacaciones, paro, jornada de reposicion)
-- ---------------------------------------------------------------------
create or replace function public.calendario_contrato(p_contrato uuid, p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_dias text;
begin
  select empresa_id, dias_atencion into v_emp, v_dias from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  if p_hasta - p_desde > 400 then raise exception 'Maximo 400 dias por consulta.'; end if;
  return jsonb_build_object(
    'dias_atencion', v_dias,
    'dias', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date, 'festivo', f.nombre,
                 'regla', case when v_dias = 'todos' then true else extract(isodow from g) between 1 and 5 and f.fecha is null end,
                 'contrato', (select jsonb_build_object('atiende', x.atiende, 'motivo', x.motivo, 'cuenta_ciclo', x.cuenta_ciclo, 'novedad', x.novedad_id is not null) from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is null and x.fecha = g::date),
                 'sedes', (select coalesce(jsonb_agg(jsonb_build_object('sede_id', x.contrato_sede_id, 'atiende', x.atiende, 'motivo', x.motivo)), '[]') from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is not null and x.fecha = g::date)
               ) order by g), '[]')
               from generate_series(p_desde, p_hasta, interval '1 day') g left join public.festivos f on f.fecha = g::date)
  );
end $$;
revoke all on function public.calendario_contrato(uuid, date, date) from public, anon;

-- marcar un rango: p_atiende null = volver a la regla (borra las marcas del rango)
create or replace function public.marcar_calendario(p_contrato uuid, p_sedes uuid[], p_desde date, p_hasta date, p_atiende boolean, p_motivo text default null, p_cuenta_ciclo boolean default false, p_solo_habiles boolean default true)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; n int := 0; v_cs uuid; v_lista uuid[];
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not public.puede_editar_planeacion(v_emp) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_hasta < p_desde then raise exception 'El rango esta al reves.'; end if;
  if p_hasta - p_desde > 120 then raise exception 'Maximo 120 dias por marca; haga varias.'; end if;
  v_lista := coalesce(p_sedes, array[null::uuid]);
  foreach v_cs in array v_lista loop
    delete from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is not distinct from v_cs and x.fecha between p_desde and p_hasta and x.novedad_id is null;
    get diagnostics n = row_count;
    if p_atiende is not null then
      insert into public.calendario_servicio (empresa_id, contrato_id, contrato_sede_id, fecha, atiende, motivo, cuenta_ciclo, creado_por)
      select v_emp, p_contrato, v_cs, g::date, p_atiende, p_motivo, p_cuenta_ciclo, auth.uid()
        from generate_series(p_desde, p_hasta, interval '1 day') g
       where not p_solo_habiles or p_atiende or public.es_dia_habil(g::date)   -- "no atiende" solo se marca en dias que de otro modo atenderian
         and not exists (select 1 from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is not distinct from v_cs and x.fecha = g::date);
      get diagnostics n = row_count;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.marcar_calendario(uuid, uuid[], date, date, boolean, text, boolean, boolean) from public, anon;

-- ---------------------------------------------------------------------
-- 5. Partes diarios (parte de guardia, asistencia del dia): lo que realmente se atendio o se va a atender ese dia
--    p_items: [{grupo_id, variante_id, tiempo_id, cantidad}]
-- ---------------------------------------------------------------------
create or replace function public.guardar_parte_diario(p_contrato_sede uuid, p_fecha date, p_items jsonb, p_fuente text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0;
begin
  if not public.puede_editar_poblacion(p_contrato_sede) then raise exception 'Sin permiso para registrar el parte de esta sede.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha del parte.'; end if;
  select empresa_id into v_emp from public.contrato_sedes where id = p_contrato_sede;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if (it->>'grupo_id') is null then raise exception 'Cada fila del parte necesita grupo.'; end if;
    if nullif(it->>'cantidad', '') is null then
      delete from public.partes_diarios where contrato_sede_id = p_contrato_sede and fecha = p_fecha and grupo_poblacion_id = (it->>'grupo_id')::uuid
         and variante_id is not distinct from (it->>'variante_id')::uuid and tiempo_comida_id is not distinct from (it->>'tiempo_id')::uuid;
    else
      insert into public.partes_diarios (empresa_id, contrato_sede_id, fecha, grupo_poblacion_id, variante_id, tiempo_comida_id, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, p_fecha, (it->>'grupo_id')::uuid, (it->>'variante_id')::uuid, (it->>'tiempo_id')::uuid, (it->>'cantidad')::int, coalesce(p_fuente, 'parte diario'), auth.uid())
      on conflict (contrato_sede_id, fecha, grupo_poblacion_id, variante_id, tiempo_comida_id) do update set cantidad = excluded.cantidad, fuente = excluded.fuente, creado_por = excluded.creado_por, creado_en = now();
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.guardar_parte_diario(uuid, date, jsonb, text) from public, anon;

-- partes de un dia para todas las sedes del contrato, con el cupo vigente al lado
create or replace function public.partes_dia(p_contrato uuid, p_fecha date)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_mi_sede uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  if not (public.es_admin_sql() or public.es_superadmin()) then v_mi_sede := public.mi_sede(v_emp); end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre, 'servicio', public.es_dia_servicio(p_contrato, cs.id, p_fecha),
            'cupos', (select coalesce(jsonb_agg(jsonb_build_object('grupo_id', c.grupo_poblacion_id, 'tiempo_id', c.tiempo_comida_id, 'variante_id', c.variante_id, 'cantidad', c.cantidad)), '[]')
                        from (select grupo_poblacion_id, tiempo_comida_id, variante_id, sum(cantidad) cantidad from public.cupos c where c.contrato_sede_id = cs.id and c.fecha_desde <= p_fecha and (c.fecha_hasta is null or c.fecha_hasta >= p_fecha) group by 1,2,3) c),
            'parte', (select coalesce(jsonb_agg(jsonb_build_object('grupo_id', p.grupo_poblacion_id, 'tiempo_id', p.tiempo_comida_id, 'variante_id', p.variante_id, 'cantidad', p.cantidad, 'fuente', p.fuente)), '[]')
                        from public.partes_diarios p where p.contrato_sede_id = cs.id and p.fecha = p_fecha),
            'variante_id', (select sc.variante_id from public.sede_ciclo sc where sc.contrato_sede_id = cs.id and sc.vigente_desde <= p_fecha and (sc.vigente_hasta is null or sc.vigente_hasta >= p_fecha) order by sc.vigente_desde desc limit 1)
          ) order by s.nombre), '[]')
            from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
           where cs.contrato_id = p_contrato and cs.estado = 'activa' and (v_mi_sede is null or cs.sede_id = v_mi_sede));
end $$;
revoke all on function public.partes_dia(uuid, date) from public, anon;

-- ---------------------------------------------------------------------
-- 6. Requerimiento por establecimiento: lo que hay que despachar a cada sede, con el tramo de ciclo y menus que cubre
-- ---------------------------------------------------------------------
create or replace function public.explosion_por_sede(p_explosion uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
begin
  if not public.puede_ver_explosion(p_explosion) then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('sede_id', x.contrato_sede_id, 'sede', s.nombre, 'ciudad', s.ciudad, 'raciones', x.rac, 'desde', x.d1, 'hasta', x.d2, 'dias', x.dias,
             'menus', x.menus, 'menu_desde', x.m1, 'menu_hasta', x.m2,
             'productos', (select coalesce(jsonb_agg(jsonb_build_object('producto_id', y.producto_id, 'codigo', p.codigo, 'nombre', p.nombre, 'categoria', p.categoria, 'unidad_compra', p.unidad_compra,
                             'cantidad_compra', round(y.c / nullif(p.factor_compra, 0), 2), 'perecedero', p.perecedero) order by p.categoria, p.nombre), '[]')
                             from (select d.producto_id, sum(d.cantidad_bruta) c from public.explosion_detalle d where d.explosion_id = p_explosion and d.contrato_sede_id = x.contrato_sede_id group by 1) y
                             join public.productos p on p.id = y.producto_id)
           ) order by s.nombre), '[]')
            from (select d.contrato_sede_id, min(d.fecha) d1, max(d.fecha) d2, count(distinct d.fecha) dias, count(distinct d.dia_ciclo) menus,
                         (array_agg(d.dia_ciclo order by d.fecha))[1] m1, (array_agg(d.dia_ciclo order by d.fecha desc))[1] m2,
                         (select sum(r.raciones) from public.explosion_raciones r where r.explosion_id = p_explosion and r.contrato_sede_id = d.contrato_sede_id) rac
                    from public.explosion_detalle d where d.explosion_id = p_explosion group by 1) x
            join public.contrato_sedes cs on cs.id = x.contrato_sede_id join public.sedes s on s.id = cs.sede_id);
end $$;
revoke all on function public.explosion_por_sede(uuid) from public, anon;
