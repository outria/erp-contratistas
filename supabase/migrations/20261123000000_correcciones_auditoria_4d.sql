-- Supply ERP · Migracion 023 · Correcciones de la auditoria de la etapa 4D (5-nov-2026)
-- C1 parte diario vs cupo sin variante; A1 vigencias solapadas (+ constraints de exclusion); A2 importador exige modalidad en PAE;
-- A3 explosion_resumen tras calcular; A4/M2 marcar_calendario; A5 importador por nombres distintos; M1 estado_ciclo;
-- M3 gramajes de la programacion por crudo_ingrediente; M4 grants explicitos; M5 mi_sede en minutas y calendario.
set client_min_messages = warning;
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------
-- C1. El parte del dia manda por grupo y tiempo, sin mirar la variante (la variante es de la sede, no de la poblacion)
-- ---------------------------------------------------------------------
create or replace function public.poblacion_dia(p_contrato_sede uuid, p_fecha date)
returns table(grupo_poblacion_id uuid, variante_id uuid, tiempo_comida_id uuid, total integer, en_dieta integer, linea integer)
language sql stable rows 4 as $$
  with p as (
    select pd.grupo_poblacion_id, max(pd.variante_id::text)::uuid as variante_id, pd.tiempo_comida_id, sum(pd.cantidad)::int as total
      from public.partes_diarios pd
     where pd.contrato_sede_id = p_contrato_sede and pd.fecha = p_fecha
     group by pd.grupo_poblacion_id, pd.tiempo_comida_id
  ), c as (
    select cu.grupo_poblacion_id, max(cu.variante_id::text)::uuid as variante_id, cu.tiempo_comida_id, sum(cu.cantidad)::int as total
      from public.cupos cu
     where cu.contrato_sede_id = p_contrato_sede and cu.fecha_desde <= p_fecha and (cu.fecha_hasta is null or cu.fecha_hasta >= p_fecha)
     group by cu.grupo_poblacion_id, cu.tiempo_comida_id
  ), base as (
    select * from p
    union all
    select * from c where not exists (select 1 from p where p.grupo_poblacion_id = c.grupo_poblacion_id
                                        and p.tiempo_comida_id is not distinct from c.tiempo_comida_id)
  ), d as (
    select dp.grupo_poblacion_id, sum(dp.cantidad)::int as en_dieta
      from public.dietas_poblacion dp
     where dp.contrato_sede_id = p_contrato_sede and dp.fecha_desde <= p_fecha and (dp.fecha_hasta is null or dp.fecha_hasta >= p_fecha)
     group by 1
  )
  select b.grupo_poblacion_id, b.variante_id, b.tiempo_comida_id, b.total,
         case when b.tiempo_comida_id is null then least(coalesce(d.en_dieta, 0), b.total) else 0 end,
         case when b.tiempo_comida_id is null then greatest(0, b.total - coalesce(d.en_dieta, 0)) else b.total end
    from base b left join d on d.grupo_poblacion_id = b.grupo_poblacion_id;
$$;

-- los partes se guardan sin variante (la toma la sede); los que ya existan se normalizan
update public.partes_diarios set variante_id = null where variante_id is not null;
create or replace function public.guardar_parte_diario(p_contrato_sede uuid, p_fecha date, p_items jsonb, p_fuente text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0;
begin
  if not public.puede_editar_poblacion(p_contrato_sede) then raise exception 'Sin permiso para registrar el parte de esta sede.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha del parte.'; end if;
  select empresa_id into v_emp from public.contrato_sedes where id = p_contrato_sede;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if (it->>'grupo_id') is null then raise exception 'Cada fila del parte necesita grupo.'; end if;
    delete from public.partes_diarios where contrato_sede_id = p_contrato_sede and fecha = p_fecha and grupo_poblacion_id = (it->>'grupo_id')::uuid
       and tiempo_comida_id is not distinct from nullif(it->>'tiempo_id', '')::uuid;
    if nullif(it->>'cantidad', '') is not null then
      insert into public.partes_diarios (empresa_id, contrato_sede_id, fecha, grupo_poblacion_id, variante_id, tiempo_comida_id, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, p_fecha, (it->>'grupo_id')::uuid, null, nullif(it->>'tiempo_id', '')::uuid, (it->>'cantidad')::int, coalesce(p_fuente, 'parte diario'), auth.uid());
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- A1. Vigencias: la nueva se cierra en la siguiente vigencia futura menos un dia; constraints de exclusion para que no vuelva a pasar
-- ---------------------------------------------------------------------
create or replace function public.guardar_cupos(p_contrato_sede uuid, p_desde date, p_items jsonb, p_fuente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_g uuid; v_t uuid; v_v uuid; v_c int; v_hasta date;
begin
  if not public.puede_editar_poblacion(p_contrato_sede) then raise exception 'Sin permiso para editar los cupos de esta sede.'; end if;
  if p_desde is null then raise exception 'Falta la fecha desde la que rigen los cupos.'; end if;
  select empresa_id into v_emp from public.contrato_sedes where id = p_contrato_sede;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_g := (it->>'grupo_id')::uuid; v_t := (it->>'tiempo_id')::uuid; v_v := (it->>'variante_id')::uuid; v_c := coalesce((it->>'cantidad')::int, 0);
    if v_g is null then raise exception 'Cada cupo necesita grupo de poblacion.'; end if;
    if v_c < 0 then raise exception 'La cantidad no puede ser negativa.'; end if;
    -- misma fecha: se corrige en sitio
    delete from public.cupos c where c.contrato_sede_id = p_contrato_sede and c.grupo_poblacion_id = v_g and c.tiempo_comida_id is not distinct from v_t and c.fecha_desde = p_desde;
    -- vigencias anteriores del mismo grupo y tiempo (y las "para todos los tiempos" cuando llega una por tiempo) se cierran el dia antes
    update public.cupos c set fecha_hasta = p_desde - 1
     where c.contrato_sede_id = p_contrato_sede and c.grupo_poblacion_id = v_g
       and (c.tiempo_comida_id is not distinct from v_t or (v_t is not null and c.tiempo_comida_id is null))
       and c.fecha_desde < p_desde and (c.fecha_hasta is null or c.fecha_hasta >= p_desde);
    -- si ya hay una vigencia futura, la nueva termina el dia antes de esa
    select min(c.fecha_desde) - 1 into v_hasta from public.cupos c
     where c.contrato_sede_id = p_contrato_sede and c.grupo_poblacion_id = v_g and c.tiempo_comida_id is not distinct from v_t and c.fecha_desde > p_desde;
    if v_c > 0 then
      insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, tiempo_comida_id, variante_id, fecha_desde, fecha_hasta, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, v_g, v_t, v_v, p_desde, v_hasta, v_c, coalesce(p_fuente, 'registro manual'), auth.uid());
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('filas', n, 'desde', p_desde);
end $$;

create or replace function public.guardar_dietas(p_contrato_sede uuid, p_desde date, p_items jsonb, p_fuente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_d uuid; v_g uuid; v_c int; v_hasta date;
begin
  if not public.puede_editar_poblacion(p_contrato_sede) then raise exception 'Sin permiso para editar las dietas de esta sede.'; end if;
  if p_desde is null then raise exception 'Falta la fecha desde la que rige la poblacion en dieta.'; end if;
  select empresa_id into v_emp from public.contrato_sedes where id = p_contrato_sede;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_d := (it->>'dieta_id')::uuid; v_g := (it->>'grupo_id')::uuid; v_c := coalesce((it->>'cantidad')::int, 0);
    if v_d is null or v_g is null then raise exception 'Cada fila de dieta necesita tipo de dieta y grupo de poblacion.'; end if;
    if v_c < 0 then raise exception 'La cantidad no puede ser negativa.'; end if;
    delete from public.dietas_poblacion d where d.contrato_sede_id = p_contrato_sede and d.tipo_dieta_id = v_d and d.grupo_poblacion_id = v_g and d.fecha_desde = p_desde;
    update public.dietas_poblacion d set fecha_hasta = p_desde - 1
     where d.contrato_sede_id = p_contrato_sede and d.tipo_dieta_id = v_d and d.grupo_poblacion_id = v_g
       and d.fecha_desde < p_desde and (d.fecha_hasta is null or d.fecha_hasta >= p_desde);
    select min(d.fecha_desde) - 1 into v_hasta from public.dietas_poblacion d
     where d.contrato_sede_id = p_contrato_sede and d.tipo_dieta_id = v_d and d.grupo_poblacion_id = v_g and d.fecha_desde > p_desde;
    if v_c > 0 then
      insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, fecha_hasta, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, v_d, v_g, p_desde, v_hasta, v_c, coalesce(p_fuente, 'registro manual'), auth.uid());
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('filas', n, 'desde', p_desde);
end $$;

create or replace function public.guardar_gramajes(p_contrato uuid, p_desde date, p_items jsonb, p_motivo text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_c uuid; v_g uuid; v_ps numeric; v_pb numeric; v_hasta date;
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
    select min(g.vigente_desde) - 1 into v_hasta from public.gramajes_ajuste g
     where g.contrato_id = p_contrato and g.contrato_sede_id is null and g.producto_id is null and g.preparacion_id is null
       and g.componente_id = v_c and g.grupo_poblacion_id is not distinct from v_g and g.vigente_desde > p_desde;
    if v_ps is not null or v_pb is not null then
      insert into public.gramajes_ajuste (empresa_id, contrato_id, grupo_poblacion_id, componente_id, porcion_servida, peso_bruto, motivo, vigente_desde, vigente_hasta, aprobado_por)
      values (v_emp, p_contrato, v_g, v_c, v_ps, v_pb, coalesce(p_motivo, 'gramaje por grupo'), p_desde, v_hasta, auth.uid());
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.asignar_ciclo(p_sedes uuid[], p_ciclo uuid, p_variante uuid, p_fecha_inicio_menu1 date, p_desde date, p_modo text default 'continuo', p_avanza_sin_servicio boolean default null)
returns int language plpgsql security definer set search_path = public as $$
declare c public.ciclos_menu; v_cs uuid; n int := 0; v_avanza boolean; v_hasta date;
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
    select min(vigente_desde) - 1 into v_hasta from public.sede_ciclo where contrato_sede_id = v_cs and vigente_desde > p_desde;
    insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, vigente_hasta, menu_confirmado, creado_por)
    values (c.empresa_id, v_cs, p_ciclo, coalesce(p_variante, c.variante_id, (select id from public.variantes_racion v where v.contrato_id = c.contrato_id and v.es_estandar)), p_fecha_inicio_menu1, p_modo, v_avanza, p_desde, v_hasta, true, auth.uid());
    n := n + 1;
  end loop;
  return n;
end $$;

-- blindaje: sin solapes de vigencia (la variante no entra: es de la sede)
alter table public.cupos drop constraint if exists cupos_sin_solape;
alter table public.cupos add constraint cupos_sin_solape exclude using gist
  (contrato_sede_id with =, grupo_poblacion_id with =, coalesce(tiempo_comida_id, '00000000-0000-0000-0000-000000000000'::uuid) with =, daterange(fecha_desde, fecha_hasta, '[]') with &&);
alter table public.dietas_poblacion drop constraint if exists dietas_sin_solape;
alter table public.dietas_poblacion add constraint dietas_sin_solape exclude using gist
  (contrato_sede_id with =, tipo_dieta_id with =, coalesce(grupo_poblacion_id, '00000000-0000-0000-0000-000000000000'::uuid) with =, daterange(fecha_desde, fecha_hasta, '[]') with &&);
alter table public.sede_ciclo drop constraint if exists sede_ciclo_sin_solape;
alter table public.sede_ciclo add constraint sede_ciclo_sin_solape exclude using gist (contrato_sede_id with =, daterange(vigente_desde, vigente_hasta, '[]') with &&);
alter table public.gramajes_ajuste drop constraint if exists gramajes_sin_solape;
alter table public.gramajes_ajuste add constraint gramajes_sin_solape exclude using gist
  (contrato_id with =, coalesce(contrato_sede_id, '00000000-0000-0000-0000-000000000000'::uuid) with =, coalesce(componente_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
   coalesce(preparacion_id, '00000000-0000-0000-0000-000000000000'::uuid) with =, coalesce(producto_id, '00000000-0000-0000-0000-000000000000'::uuid) with =,
   coalesce(grupo_poblacion_id, '00000000-0000-0000-0000-000000000000'::uuid) with =, daterange(vigente_desde, vigente_hasta, '[]') with &&);

-- ---------------------------------------------------------------------
-- A2 + A5. Importador: exige modalidad cuando el contrato reparte por tiempo; resuelve cada nombre una sola vez; acumula en temporal
-- ---------------------------------------------------------------------
create or replace function public.importar_poblacion(p_contrato uuid, p_tipo text, p_filas jsonb, p_desde date, p_fuente text default null, p_aplicar boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions set jit = off as $$
declare v_emp uuid; v_por_tiempo boolean; v_variantes int; ok int := 0; mal int := 0; r record; v_cs uuid; v_desde date;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'editar')) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_tipo not in ('cupos', 'dietas') then raise exception 'Tipo de importacion no valido: %', p_tipo; end if;
  if jsonb_array_length(coalesce(p_filas, '[]'::jsonb)) > 5000 then raise exception 'Maximo 5.000 filas por carga; parta el archivo.'; end if;
  -- el contrato reparte cupos por tiempo (PAE) si su modalidad es pae o ya tiene cupos por tiempo
  v_por_tiempo := (select modalidad = 'pae' from public.contratos where id = p_contrato)
               or exists (select 1 from public.cupos c join public.contrato_sedes cs on cs.id = c.contrato_sede_id where cs.contrato_id = p_contrato and c.tiempo_comida_id is not null);
  select count(*) into v_variantes from public.variantes_racion v where v.contrato_id = p_contrato;

  -- filas crudas
  create temp table if not exists tmp_imp (fila int, n int, sede text, grupo text, tiempo text, variante text, dieta text, cantidad int, desde date, err text,
                                           cs_id uuid, sede_res text, g_id uuid, t_id uuid, v_id uuid, d_id uuid) on commit drop;
  truncate tmp_imp;
  insert into tmp_imp (fila, n, sede, grupo, tiempo, variante, dieta, cantidad, desde, err)
  select (f->>'fila')::int, ord, trim(coalesce(f->>'sede', '')), nullif(trim(coalesce(f->>'grupo', '')), ''), nullif(trim(coalesce(f->>'tiempo', '')), ''),
         nullif(trim(coalesce(f->>'variante', '')), ''), nullif(trim(coalesce(f->>'dieta', '')), ''),
         nullif(regexp_replace(coalesce(f->>'cantidad', ''), '[^0-9]', '', 'g'), '')::int,
         case when nullif(f->>'desde', '') ~ '^\d{4}-\d{2}-\d{2}' then (f->>'desde')::date else p_desde end,
         case when nullif(f->>'desde', '') is not null and not (f->>'desde' ~ '^\d{4}-\d{2}-\d{2}') then 'fecha no valida' end
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) with ordinality x(f, ord);

  -- sedes del contrato normalizadas una vez; cada nombre distinto se resuelve una vez (exacto, luego parecido >= 0,45)
  create temp table if not exists tmp_imp_sedes (id uuid, nombre text, norm text) on commit drop;
  truncate tmp_imp_sedes;
  insert into tmp_imp_sedes select cs.id, s.nombre, lower(unaccent(s.nombre)) from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.contrato_id = p_contrato and cs.estado = 'activa';
  create temp table if not exists tmp_imp_nombres (sede text, norm text, cs_id uuid, sede_res text) on commit drop;
  truncate tmp_imp_nombres;
  insert into tmp_imp_nombres (sede, norm) select distinct sede, lower(unaccent(sede)) from tmp_imp where sede <> '';
  update tmp_imp_nombres n set cs_id = s.id, sede_res = s.nombre from tmp_imp_sedes s where s.norm = n.norm;
  update tmp_imp_nombres n set (cs_id, sede_res) = (select s.id, s.nombre from tmp_imp_sedes s where similarity(s.norm, n.norm) >= 0.45 order by similarity(s.norm, n.norm) desc limit 1)
   where n.cs_id is null;
  update tmp_imp i set cs_id = n.cs_id, sede_res = n.sede_res from tmp_imp_nombres n where n.sede = i.sede;
  update tmp_imp set err = concat_ws('; ', err, 'sede no encontrada en el contrato') where cs_id is null;

  -- grupo: codigo, nombre, prefijo del nombre, inicial (H/M) o parecido >= 0,4; si no viene y hay un solo grupo, ese
  update tmp_imp i set g_id = (select gp.id from public.grupos_poblacion gp where gp.contrato_id = p_contrato
                   and (lower(gp.codigo) = lower(i.grupo) or lower(unaccent(gp.nombre)) = lower(unaccent(i.grupo)) or lower(unaccent(gp.nombre)) like lower(unaccent(i.grupo)) || '%'
                        or (gp.tipo = 'sexo' and lower(left(i.grupo, 1)) = lower(gp.codigo)))
                  order by gp.orden limit 1)
   where i.grupo is not null;
  update tmp_imp i set g_id = (select gp.id from public.grupos_poblacion gp where gp.contrato_id = p_contrato and similarity(lower(unaccent(gp.nombre)), lower(unaccent(i.grupo))) >= 0.4
                               order by similarity(lower(unaccent(gp.nombre)), lower(unaccent(i.grupo))) desc limit 1)
   where i.grupo is not null and i.g_id is null;
  update tmp_imp i set g_id = (select gp.id from public.grupos_poblacion gp where gp.contrato_id = p_contrato order by gp.orden limit 1)
   where i.grupo is null and (select count(*) from public.grupos_poblacion gp where gp.contrato_id = p_contrato) = 1;
  update tmp_imp set err = concat_ws('; ', err, case when grupo is null then 'falta el grupo (sexo o grupo etario)' else 'grupo "' || grupo || '" no existe en el contrato' end) where g_id is null;

  if p_tipo = 'cupos' then
    update tmp_imp i set t_id = (select tc.id from public.tiempos_comida tc where tc.contrato_id = p_contrato
                       and (lower(tc.codigo) = lower(i.tiempo) or lower(unaccent(tc.nombre)) like lower(unaccent(i.tiempo)) || '%') order by tc.orden limit 1)
     where i.tiempo is not null;
    update tmp_imp set err = concat_ws('; ', err, 'tiempo/modalidad "' || tiempo || '" no existe') where tiempo is not null and t_id is null;
    if v_por_tiempo then
      update tmp_imp set err = concat_ws('; ', err, 'falta la modalidad (RPS, CAM, CPM, RI): en este contrato cada estudiante recibe un tiempo') where tiempo is null;
    end if;
    if v_variantes > 1 then
      update tmp_imp i set v_id = (select vr.id from public.variantes_racion vr where vr.contrato_id = p_contrato
                         and (lower(vr.codigo) = lower(i.variante) or lower(unaccent(vr.nombre)) like lower(unaccent(i.variante)) || '%' or (upper(i.variante) = 'ERON' and vr.es_estandar)) limit 1)
       where i.variante is not null;
      update tmp_imp i set v_id = coalesce((select sc.variante_id from public.sede_ciclo sc where sc.contrato_sede_id = i.cs_id order by sc.vigente_desde desc limit 1),
                                           (select vr.id from public.variantes_racion vr where vr.contrato_id = p_contrato and vr.es_estandar limit 1))
       where i.v_id is null and i.cs_id is not null;
    end if;
  else
    update tmp_imp i set d_id = (select td.id from public.tipos_dieta td where (td.empresa_id is null or td.empresa_id = v_emp)
                       and (lower(td.codigo) = lower(i.dieta) or lower(unaccent(td.nombre_oficial)) = lower(unaccent(i.dieta)) or lower(unaccent(replace(td.nombre_oficial, 'Dieta ', ''))) = lower(unaccent(i.dieta)))
                       order by (td.empresa_id is not null) desc limit 1)
     where i.dieta is not null;
    update tmp_imp i set d_id = (select td.id from public.tipos_dieta td where (td.empresa_id is null or td.empresa_id = v_emp) and similarity(lower(unaccent(td.nombre_oficial)), lower(unaccent(i.dieta))) >= 0.35
                                 order by similarity(lower(unaccent(td.nombre_oficial)), lower(unaccent(i.dieta))) desc limit 1)
     where i.dieta is not null and i.d_id is null;
    update tmp_imp set err = concat_ws('; ', err, 'dieta "' || coalesce(dieta, '') || '" no esta en el catalogo') where d_id is null;
  end if;
  update tmp_imp set err = concat_ws('; ', err, 'cantidad vacia o no numerica') where cantidad is null;
  select count(*) filter (where err is null), count(*) filter (where err is not null) into ok, mal from tmp_imp;

  if p_aplicar and mal = 0 and ok > 0 then
    -- misma llave en varias filas (dos sedes educativas del mismo colegio): se suman
    for r in select cs_id, desde from tmp_imp where err is null group by 1, 2 loop
      if p_tipo = 'cupos' then
        perform public.guardar_cupos(r.cs_id, r.desde,
          (select jsonb_agg(jsonb_build_object('grupo_id', x.g_id, 'tiempo_id', x.t_id, 'variante_id', x.v_id, 'cantidad', x.c))
             from (select g_id, t_id, max(v_id::text)::uuid v_id, sum(cantidad) c from tmp_imp where cs_id = r.cs_id and desde = r.desde and err is null group by 1, 2) x),
          coalesce(p_fuente, 'importacion Excel'));
      else
        perform public.guardar_dietas(r.cs_id, r.desde,
          (select jsonb_agg(jsonb_build_object('dieta_id', x.d_id, 'grupo_id', x.g_id, 'cantidad', x.c))
             from (select d_id, g_id, sum(cantidad) c from tmp_imp where cs_id = r.cs_id and desde = r.desde and err is null group by 1, 2) x),
          coalesce(p_fuente, 'importacion Excel'));
      end if;
    end loop;
    insert into public.importaciones (empresa_id, tipo, archivo, filas_leidas, filas_cargadas, errores, estado)
    values (v_emp, p_tipo, p_fuente, ok + mal, ok, '[]'::jsonb, 'procesada');
  end if;
  return jsonb_build_object('ok', ok, 'con_error', mal, 'aplicado', p_aplicar and mal = 0 and ok > 0,
    'sedes', (select count(distinct cs_id) from tmp_imp where err is null),
    'filas', (select coalesce(jsonb_agg(jsonb_build_object('fila', fila, 'sede', sede, 'sede_resuelta', sede_res, 'cantidad', cantidad, 'desde', desde, 'error', err) order by n), '[]') from tmp_imp));
end $$;

-- ---------------------------------------------------------------------
-- A3. Estadisticas al final del calculo y sin_receta sin correlacion
-- ---------------------------------------------------------------------
create or replace function public.explosion_avance(p_explosion uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.puede_ver_explosion(p_explosion) then jsonb_build_object('estado', e.estado, 'raciones', e.raciones,
           'dias_cubiertos', (select count(*) from generate_series(e.fecha_desde, e.fecha_hasta, interval '1 day') g where e.cubierto @> g::date)) end
    from public.explosiones e where e.id = p_explosion;
$$;
revoke all on function public.explosion_avance(uuid) from public, anon;

-- A3 (continuacion): estadisticas al terminar cada tramo
create or replace function public.calcular_explosion(p_explosion uuid, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_sedes uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(filas integer, raciones integer, productos integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path = public set jit = off as $function$
declare e public.explosiones; v_filas int := 0; v_rac int := 0; n int; v_hay_sust boolean; d1 date; d2 date; v_total boolean;
begin
  select * into e from public.explosiones where id = p_explosion for update;   -- M1: un calculo a la vez por explosion
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if e.tipo = 'requerimiento' then
    if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then
      raise exception 'Sin permiso para calcular requerimientos (Planeacion: crear).';
    end if;
    if e.estado in ('aprobada','enviada_compras') then raise exception 'El requerimiento ya esta aprobado; cree uno nuevo.'; end if;
  elsif not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'ver') or public.tiene_permiso(e.empresa_id, 'M3', 'ver')) then
    raise exception 'Sin permiso para proyectar (Planeacion o Compras: ver).';
  end if;
  v_hay_sust := exists (select 1 from public.intercambios_menu x where x.contrato_id = e.contrato_id and x.tipo_cambio = 'ingrediente'
                          and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde)
                          and public.intercambio_aplica(x.estado, x.clase, e.incluye_propuestos));
  d1 := greatest(coalesce(p_desde, e.fecha_desde), e.fecha_desde); d2 := least(coalesce(p_hasta, e.fecha_hasta), e.fecha_hasta);
  v_total := p_desde is null and p_hasta is null and p_sedes is null;
  if v_total then
    delete from public.explosion_detalle where explosion_id = p_explosion;
    delete from public.explosion_raciones where explosion_id = p_explosion;
  else
    delete from public.explosion_detalle where explosion_id = p_explosion and fecha between d1 and d2 and (p_sedes is null or contrato_sede_id = any (p_sedes));
    delete from public.explosion_raciones where explosion_id = p_explosion and fecha between d1 and d2 and (p_sedes is null or contrato_sede_id = any (p_sedes));
  end if;

  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;
  create temp table tmp_exp_dias as
  select cs.id as sede_id, g::date as fecha, dc.dia
    from public.contrato_sedes cs
    cross join generate_series(d1, d2, interval '1 day') g
    cross join lateral public.dia_ciclo(cs.id, g::date) dc
   where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes))
     and (p_sedes is null or cs.id = any (p_sedes));
  create temp table tmp_exp_menu as
  select d.sede_id, d.fecha, m.*
    from tmp_exp_dias d cross join lateral public.menu_del_dia(d.sede_id, d.fecha, e.incluye_propuestos) m
   where m.preparacion_id is not null;
  create index on tmp_exp_menu (sede_id, fecha);
  create temp table tmp_exp_pob as
  select d.sede_id, d.fecha, p.*
    from tmp_exp_dias d cross join lateral public.poblacion_dia(d.sede_id, d.fecha) p;
  create index on tmp_exp_pob (sede_id, fecha);
  analyze tmp_exp_menu; analyze tmp_exp_pob;

  -- ---- linea
  insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
  select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, m.preparacion_id,
         coalesce(si.producto_id, ing.producto_id), p.grupo_poblacion_id, null, p.linea,
         cr.crudo * coalesce(si.factor, 1), p.linea * cr.crudo * coalesce(si.factor, 1),
         nullif(concat_ws(' · ', cr.nota, case when si.producto_id is not null then 'intercambio de ingrediente' end), '')
    from tmp_exp_menu m
    join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id)
                      and (p.tiempo_comida_id is null or p.tiempo_comida_id = m.tiempo_comida_id) and p.linea > 0
    join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                   where pi.preparacion_id = m.preparacion_id and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                   order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
    cross join lateral public.crudo_ingrediente(e.contrato_id, m.sede_id, m.fecha, m.preparacion_id, ing.producto_id, p.grupo_poblacion_id, m.componente_id, ing.peso_bruto) cr
    left join lateral (select * from public.sustitucion_ingrediente(m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos) where v_hay_sust) si on true;
  get diagnostics n = row_count; v_filas := v_filas + n;

  -- ---- dietas: reglas con prioridad contrato > empresa > catalogo (una regla inactiva del contrato anula la del catalogo);
  --      la poblacion en dieta se prorratea si supera la del grupo
  if e.incluye_dietas then
    insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
    select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, vp.prep,
           coalesce(rs.sust, si.producto_id, ing.producto_id), p.grupo_poblacion_id, dd.tipo_dieta_id, dd.cant,
           x.crudo_final, dd.cant * x.crudo_final, x.nota
      from tmp_exp_menu m
      join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id)
                        and p.tiempo_comida_id is null and p.en_dieta > 0
      join lateral (select z.tipo_dieta_id,
                           case when sum(z.c) over () > p.en_dieta then floor(z.c * p.en_dieta::numeric / sum(z.c) over ())::int else z.c end as cant
                      from (select dp.tipo_dieta_id, sum(dp.cantidad)::int as c from public.dietas_poblacion dp
                             where dp.contrato_sede_id = m.sede_id and dp.grupo_poblacion_id = p.grupo_poblacion_id
                               and dp.fecha_desde <= m.fecha and (dp.fecha_hasta is null or dp.fecha_hasta >= m.fecha)
                             group by dp.tipo_dieta_id) z) dd on dd.cant > 0
      left join lateral (select q.* from public.dieta_equivalencias q where q.contrato_id = e.contrato_id and q.tipo_dieta_id = dd.tipo_dieta_id
                           and (q.contrato_sede_id = m.sede_id or q.contrato_sede_id is null) order by q.contrato_sede_id nulls last limit 1) eq on true
      cross join lateral (select coalesce(eq.equivale_a_id, dd.tipo_dieta_id) as dieta) de
      left join lateral (select ds.preparacion_id from public.dieta_estandar ds
                          where ds.contrato_id = e.contrato_id and (ds.contrato_sede_id = m.sede_id or ds.contrato_sede_id is null)
                            and (ds.tipo_dieta_id = dd.tipo_dieta_id or ds.tipo_dieta_id is null) and (ds.tiempo_comida_id = m.tiempo_comida_id or ds.tiempo_comida_id is null)
                            and ds.componente_codigo = m.componente_codigo and ds.vigente_desde <= m.fecha and (ds.vigente_hasta is null or ds.vigente_hasta >= m.fecha)
                          order by ds.contrato_sede_id nulls last, ds.tipo_dieta_id nulls last, ds.tiempo_comida_id nulls last, ds.vigente_desde desc limit 1) ds on true
      cross join lateral (select coalesce(ds.preparacion_id, case when m.componente_codigo = 'PROTEICO' then eq.preparacion_proteico_id end, m.preparacion_id) as prep) vp
      cross join lateral (
        select bool_or(r.activa and r.tipo_regla = 'excluir_componente') as excl,
               max(r.valor) filter (where r.activa and r.tipo_regla = 'factor_porcion') as factor,
               max(r.valor) filter (where r.activa and r.tipo_regla = 'porcion_fija') as fija
          from (select distinct on (rd.tipo_regla) rd.*
                  from public.reglas_dieta rd
                 where rd.tipo_dieta_id = de.dieta and rd.componente_codigo = m.componente_codigo
                   and rd.tipo_regla in ('excluir_componente','factor_porcion','porcion_fija')
                   and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and (rd.empresa_id is null or rd.empresa_id = e.empresa_id)))
                 order by rd.tipo_regla, (rd.contrato_id is null), (rd.empresa_id is null)) r) rg
      join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                     where pi.preparacion_id = vp.prep and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                     order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
      left join public.productos prod on prod.id = ing.producto_id
      left join lateral (
        select bool_or(r.activa and r.tipo_regla in ('excluir_producto','excluir_categoria')) as excl,
               max(r.producto_sustituto_id::text) filter (where r.activa and r.tipo_regla = 'sustituir_producto')::uuid as sust
          from (select distinct on (rd.tipo_regla) rd.*
                  from public.reglas_dieta rd
                 where rd.tipo_dieta_id = de.dieta
                   and ((rd.tipo_regla in ('excluir_producto','sustituir_producto') and rd.producto_id = ing.producto_id)
                     or (rd.tipo_regla = 'excluir_categoria' and rd.categoria_producto = prod.categoria))
                   and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and (rd.empresa_id is null or rd.empresa_id = e.empresa_id)))
                 order by rd.tipo_regla, (rd.contrato_id is null), (rd.empresa_id is null)) r) rs on true
      cross join lateral public.crudo_ingrediente(e.contrato_id, m.sede_id, m.fecha, vp.prep, ing.producto_id, p.grupo_poblacion_id, m.componente_id, ing.peso_bruto) cr
      left join lateral (select * from public.sustitucion_ingrediente(m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos) where v_hay_sust and rs.sust is null) si on true
      cross join lateral (
        select (case when ing.es_principal and rg.fija is not null then rg.fija / coalesce(prod.rendimiento, 1)
                     when ing.es_principal and coalesce(rg.factor, 1) <> 1 then cr.crudo * rg.factor
                     else cr.crudo end) * coalesce(si.factor, 1) as crudo_final,
               nullif(concat_ws(' · ',
                 case when ing.es_principal and rg.fija is not null then 'dieta: porcion fija ' || rg.fija
                      when ing.es_principal and coalesce(rg.factor, 1) <> 1 then 'dieta: factor ' || rg.factor
                      else cr.nota end,
                 case when rs.sust is not null then 'dieta: sustituido' end,
                 case when vp.prep <> m.preparacion_id then 'dieta: preparacion unificada' end,
                 case when si.producto_id is not null then 'intercambio de ingrediente' end), '') as nota) x
     where not coalesce(rg.excl, false) and not coalesce(rs.excl, false);
    get diagnostics n = row_count; v_filas := v_filas + n;
  end if;

  -- raciones del tramo (personas-dia con servicio) y cobertura
  insert into public.explosion_raciones (explosion_id, contrato_sede_id, fecha, raciones)
  -- cada fila de poblacion_dia es una poblacion distinta (grupo x variante x tiempo): se suman todas (antes tomaba el maximo por tiempo y subcontaba PAE)
  select p_explosion, p.sede_id, p.fecha, coalesce(sum(p.total), 0)
    from tmp_exp_pob p group by p.sede_id, p.fecha;
  select coalesce(sum(r.raciones), 0) into v_rac from public.explosion_raciones r where r.explosion_id = p_explosion;
  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;
  -- estadisticas frescas: el resumen y la pantalla consultan justo despues de insertar decenas de miles de filas
  analyze public.explosion_detalle; analyze public.explosion_raciones;

  update public.explosiones
     set cubierto = case when v_total then datemultirange(daterange(e.fecha_desde, e.fecha_hasta, '[]'))
                         when p_sedes is null then cubierto + datemultirange(daterange(d1, d2, '[]'))
                         else cubierto end,          -- un tramo por sedes no cambia la cobertura por fechas
         raciones = v_rac, calculada_en = now()
   where id = p_explosion;
  update public.explosiones
     set estado = case when cubierto @> daterange(fecha_desde, fecha_hasta, '[]') then 'calculada' else 'parcial' end
   where id = p_explosion and estado in ('borrador','parcial','calculada');
  return query select v_filas, v_rac, (select count(distinct producto_id)::int from public.explosion_detalle where explosion_id = p_explosion);
end $function$;

-- A3: sin_receta sin correlacion
create or replace function public.explosion_resumen(p_explosion uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare e public.explosiones; r jsonb;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if not public.puede_ver_explosion(p_explosion) then raise exception 'Sin permiso'; end if;
  select jsonb_build_object(
    'explosion', jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'tipo', e.tipo, 'estado', e.estado, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta,
                   'incluye_dietas', e.incluye_dietas, 'incluye_propuestos', e.incluye_propuestos, 'raciones', e.raciones, 'calculada_en', e.calculada_en,
                   'aprobada_en', e.aprobada_en, 'notas', e.notas, 'contrato_id', e.contrato_id,
                   'sedes', (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre) order by s.nombre), '[]')
                               from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
                              where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes))),
                   'dias_cubiertos', (select count(*) from generate_series(e.fecha_desde, e.fecha_hasta, interval '1 day') g where e.cubierto @> g::date),
                   'dias', e.fecha_hasta - e.fecha_desde + 1),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('producto_id', v.producto_id, 'codigo', v.codigo, 'nombre', v.nombre, 'categoria', v.categoria,
                    'unidad_base', v.unidad_base, 'unidad_compra', v.unidad_compra, 'factor_compra', v.factor_compra,
                    'cantidad_base', round(v.cantidad_base, 1), 'cantidad_compra', v.cantidad_compra, 'de_linea', round(coalesce(v.de_linea, 0), 1), 'de_dietas', round(coalesce(v.de_dietas, 0), 1),
                    'dias', v.dias, 'promedio_dia', v.promedio_dia, 'perecedero', p.perecedero, 'nivel_riesgo', p.nivel_riesgo) order by v.categoria, v.nombre), '[]')
                    from public.v_explosion_productos v join public.productos p on p.id = v.producto_id where v.explosion_id = p_explosion),
    'categorias', (select coalesce(jsonb_agg(jsonb_build_object('categoria', x.categoria, 'productos', x.n, 'kg', x.kg) order by x.kg desc), '[]')
                     from (select p.categoria, count(distinct d.producto_id) n,
                                  round(sum(case when p.unidad_base in ('g','ml') then d.cantidad_bruta / 1000 else d.cantidad_bruta end), 1) kg
                             from public.explosion_detalle d join public.productos p on p.id = d.producto_id where d.explosion_id = p_explosion group by p.categoria) x),
    'por_sede', (select coalesce(jsonb_agg(jsonb_build_object('sede_id', x.contrato_sede_id, 'sede', s.nombre, 'raciones', x.rac, 'dias', x.dias, 'promedio', round(x.rac::numeric / nullif(x.dias, 0))) order by x.rac desc), '[]')
                   from (select r.contrato_sede_id, sum(r.raciones) rac, count(*) filter (where r.raciones > 0) dias from public.explosion_raciones r where r.explosion_id = p_explosion group by 1) x
                   join public.contrato_sedes cs on cs.id = x.contrato_sede_id join public.sedes s on s.id = cs.sede_id),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('fecha', x.fecha, 'raciones', x.rac, 'sedes', x.n) order by x.fecha), '[]')
                  from (select r.fecha, sum(r.raciones) rac, count(*) filter (where r.raciones > 0) n from public.explosion_raciones r where r.explosion_id = p_explosion group by 1) x),
    'por_tiempo', (select coalesce(jsonb_agg(jsonb_build_object('tiempo', t.codigo, 'nombre', t.nombre, 'raciones', x.rac) order by t.orden), '[]')
                     from (select d.tiempo_comida_id, sum(d.raciones) rac from (select tiempo_comida_id, contrato_sede_id, fecha, grupo_poblacion_id, tipo_dieta_id, max(raciones) raciones
                                                                                   from public.explosion_detalle where explosion_id = p_explosion group by 1,2,3,4,5) d group by 1) x
                     join public.tiempos_comida t on t.id = x.tiempo_comida_id),
    'sin_receta', (select count(*) from (
                     select r.contrato_sede_id, r.fecha from public.explosion_raciones r where r.explosion_id = p_explosion and r.raciones > 0
                     except
                     select distinct d.contrato_sede_id, d.fecha from public.explosion_detalle d where d.explosion_id = p_explosion) z)
  ) into r;
  return r;
end $$;

-- A4 + M2. marcar_calendario: precedencia y regla del contrato
create or replace function public.marcar_calendario(p_contrato uuid, p_sedes uuid[], p_desde date, p_hasta date, p_atiende boolean, p_motivo text default null, p_cuenta_ciclo boolean default false, p_solo_habiles boolean default true)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid; n int := 0; v_t int := 0; v_cs uuid; v_lista uuid[]; v_dias text;
begin
  select empresa_id, dias_atencion into v_emp, v_dias from public.contratos where id = p_contrato;
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
       where (not p_solo_habiles or p_atiende or v_dias = 'todos' or public.es_dia_habil(g::date))   -- "no atiende" solo en dias que de otro modo atenderian (regla del contrato)
         and not exists (select 1 from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is not distinct from v_cs and x.fecha = g::date);   -- respeta las marcas de novedades
      get diagnostics n = row_count;
    end if;
    v_t := v_t + n;
  end loop;
  return v_t;
end $$;

-- M1. estado_ciclo exige casillas obligatorias completas y deja un solo vigente por variante
create or replace function public.estado_ciclo(p_ciclo uuid, p_estado text, p_oficio text default null, p_vigente_desde date default null)
returns void language plpgsql security definer set search_path = public as $$
declare c public.ciclos_menu;
begin
  select * into c from public.ciclos_menu where id = p_ciclo;
  if c.id is null then raise exception 'Ciclo no encontrado'; end if;
  if not public.puede_editar_planeacion(c.empresa_id) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_estado not in ('borrador', 'vigente', 'historico', 'anulado') then raise exception 'Estado no valido'; end if;
  if p_estado = 'vigente' then
    -- todas las casillas obligatorias (menus x componentes obligatorios, menos los excluidos por la variante del ciclo) deben tener receta o descriptor
    if exists (select 1 from generate_series(1, c.n_menus) d
                 cross join (select co.id, co.tiempo_comida_id, co.codigo from public.componentes co where co.contrato_id = c.contrato_id and co.obligatorio
                              and not (co.codigo = any (coalesce((select v.componentes_excluidos from public.variantes_racion v where v.id = c.variante_id), '{}')))) co
                 left join public.ciclo_menu_items i on i.ciclo_id = p_ciclo and i.dia = d and i.componente_id = co.id and (i.preparacion_id is not null or i.descriptor is not null)
                where i.id is null) then
      raise exception 'Hay casillas obligatorias sin receta; complete el ciclo antes de ponerlo vigente.';
    end if;
    -- el vigente anterior de la misma variante pasa a historico
    update public.ciclos_menu set estado = 'historico' where contrato_id = c.contrato_id and id <> p_ciclo and estado = 'vigente' and variante_id is not distinct from c.variante_id;
  end if;
  if p_estado = 'anulado' and exists (select 1 from public.sede_ciclo sc where sc.ciclo_id = p_ciclo and (sc.vigente_hasta is null or sc.vigente_hasta >= current_date)) then
    raise exception 'Hay sedes con este ciclo asignado; cambieles el ciclo primero.';
  end if;
  update public.ciclos_menu set estado = p_estado, oficio_aprobacion = coalesce(p_oficio, oficio_aprobacion), vigente_desde = coalesce(p_vigente_desde, vigente_desde),
         tipo = case when p_estado = 'vigente' and p_oficio is not null then 'aprobado' else tipo end
   where id = p_ciclo;
end $$;

-- M5. mi_sede en minutas y calendario
create or replace function public.minutas_contrato(p_contrato uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_hoy date := (now() at time zone 'America/Bogota')::date; r jsonb; v_mi_sede uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  if not (public.es_admin_sql() or public.es_superadmin()) then v_mi_sede := public.mi_sede(v_emp); end if;
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
                from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.contrato_id = p_contrato and cs.estado = 'activa' and (v_mi_sede is null or cs.sede_id = v_mi_sede)),
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

create or replace function public.calendario_contrato(p_contrato uuid, p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_dias text; v_mi_sede uuid;
begin
  select empresa_id, dias_atencion into v_emp, v_dias from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then raise exception 'Sin permiso'; end if;
  if p_hasta - p_desde > 400 then raise exception 'Maximo 400 dias por consulta.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin()) then v_mi_sede := public.mi_sede(v_emp); end if;
  return jsonb_build_object(
    'dias_atencion', v_dias,
    'dias', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date, 'festivo', f.nombre,
                 'regla', case when v_dias = 'todos' then true else extract(isodow from g) between 1 and 5 and f.fecha is null end,
                 'contrato', (select jsonb_build_object('atiende', x.atiende, 'motivo', x.motivo, 'cuenta_ciclo', x.cuenta_ciclo, 'novedad', x.novedad_id is not null) from public.calendario_servicio x where x.contrato_id = p_contrato and x.contrato_sede_id is null and x.fecha = g::date),
                 'sedes', (select coalesce(jsonb_agg(jsonb_build_object('sede_id', x.contrato_sede_id, 'atiende', x.atiende, 'motivo', x.motivo)), '[]') from public.calendario_servicio x join public.contrato_sedes cs on cs.id = x.contrato_sede_id where x.contrato_id = p_contrato and x.contrato_sede_id is not null and x.fecha = g::date and (v_mi_sede is null or cs.sede_id = v_mi_sede))
               ) order by g), '[]')
               from generate_series(p_desde, p_hasta, interval '1 day') g left join public.festivos f on f.fecha = g::date)
  );
end $$;

-- M3. La programacion muestra el mismo gramaje que aplica la explosion
create or replace function public.programacion(p_contrato uuid, p_desde date, p_hasta date, p_sedes uuid[] default null, p_incluye_propuestos boolean default false, p_agrupar boolean default true)
returns jsonb language plpgsql security definer set search_path = public set jit = off set client_min_messages = warning as $$
declare v_emp uuid; v_mi_sede uuid; v_res jsonb; v_n_sedes int; v_dias int; v_n_grupos int;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then
    raise exception 'Sin permiso';
  end if;
  v_dias := p_hasta - p_desde + 1;
  if v_dias > 70 then raise exception 'Maximo 10 semanas por consulta.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin()) then v_mi_sede := public.mi_sede(v_emp); end if;

  create temp table if not exists tmp_prg_sedes (id uuid, nombre text, subtipo text, ciudad text, cupos int) on commit drop;
  truncate tmp_prg_sedes;
  insert into tmp_prg_sedes
  select cs.id, s.nombre, s.subtipo, s.ciudad, cs.cupos_referencia
    from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
   where cs.contrato_id = p_contrato and cs.estado = 'activa'
     and (p_sedes is null or cs.id = any (p_sedes)) and (v_mi_sede is null or cs.sede_id = v_mi_sede);
  select count(*) into v_n_sedes from tmp_prg_sedes;
  if v_n_sedes * v_dias > 21000 then
    raise exception 'Demasiadas celdas (% sedes x % dias). Filtre sedes o muestre menos semanas.', v_n_sedes, v_dias;
  end if;

  create temp table if not exists tmp_prg_dias (sede_id uuid, fecha date, dia int, servicio boolean) on commit drop;
  truncate tmp_prg_dias;
  insert into tmp_prg_dias
  select s.id, g::date, dc.dia, public.es_dia_servicio(p_contrato, s.id, g::date)
    from tmp_prg_sedes s cross join generate_series(p_desde, p_hasta, interval '1 day') g
    left join lateral public.dia_ciclo(s.id, g::date) dc on true;
  create index if not exists tmp_prg_dias_idx on tmp_prg_dias (sede_id, fecha);

  -- El menu se calcula una sola vez por "llave de menu": sedes con el mismo ciclo, variante y secuencia de dias,
  -- y sin intercambios propios en el rango, comparten el resultado (147 colegios PAE -> un punado de llaves).
  create temp table if not exists tmp_prg_llave (sede_id uuid, llave text, rep uuid) on commit drop;
  truncate tmp_prg_llave;
  insert into tmp_prg_llave (sede_id, llave)
  select s.id,
         case when exists (select 1 from public.intercambios_menu x where x.contrato_sede_id = s.id
                             and (x.estado in ('concertado','aprobado_entidad') or (p_incluye_propuestos and x.estado = 'propuesto'))
                             and coalesce(x.vigente_desde, p_desde) <= p_hasta and coalesce(x.vigente_hasta, p_hasta) >= p_desde)
              then s.id::text
              else md5(coalesce((select string_agg(sc.ciclo_id || '/' || coalesce(sc.variante_id::text, '-') || '/' || sc.fecha_inicio_menu1 || '/' || sc.modo_reinicio || '/' || sc.vigente_desde || '/' || coalesce(sc.vigente_hasta::text, '-'), '|' order by sc.vigente_desde)
                                     from public.sede_ciclo sc where sc.contrato_sede_id = s.id and sc.vigente_desde <= p_hasta and coalesce(sc.vigente_hasta, p_hasta) >= p_desde), '')
                        || '#' || coalesce((select string_agg(d.fecha || ':' || coalesce(d.dia::text, '-'), '|' order by d.fecha) from tmp_prg_dias d where d.sede_id = s.id), ''))
         end
    from tmp_prg_sedes s;
  update tmp_prg_llave l set rep = r.rep
    from (select llave, (array_agg(sede_id order by sede_id))[1] as rep from tmp_prg_llave group by llave) r
   where r.llave = l.llave;

  create temp table if not exists tmp_prg_menu (sede_id uuid, fecha date, orden int, corden int, item jsonb) on commit drop;
  truncate tmp_prg_menu;
  insert into tmp_prg_menu
  select l.sede_id, d.fecha, m.tiempo_orden, c.orden,
         jsonb_build_object('tiempo', m.tiempo_codigo, 'componente_id', m.componente_id, 'componente', m.componente_codigo,
                            'preparacion_id', m.preparacion_id, 'preparacion', coalesce(m.preparacion_nombre, m.descriptor), 'origen', m.origen,
                            'intercambio_id', m.intercambio_id, 'clase', x.clase, 'estado', x.estado)
    from (select distinct rep from tmp_prg_llave) r
    join tmp_prg_dias d on d.sede_id = r.rep and d.dia is not null
    cross join lateral public.menu_del_dia(d.sede_id, d.fecha, p_incluye_propuestos) m
    left join public.componentes c on c.id = m.componente_id
    left join public.intercambios_menu x on x.id = m.intercambio_id
    join tmp_prg_llave l on l.rep = r.rep;
  create index if not exists tmp_prg_menu_idx on tmp_prg_menu (sede_id, fecha);
  analyze tmp_prg_menu; analyze tmp_prg_dias;

  -- cupos (cobertura / PPL / estudiantes) por sede y dia: total, en dieta y por tiempo de comida (PAE)
  create temp table if not exists tmp_prg_pob (sede_id uuid, fecha date, total int, dieta int, por_tiempo jsonb) on commit drop;
  truncate tmp_prg_pob;
  insert into tmp_prg_pob
  select x.sede_id, x.fecha, sum(x.total)::int, sum(x.dieta)::int,
         jsonb_object_agg(x.tcod, x.total) filter (where x.tcod is not null)
    from (select d.sede_id, d.fecha, t.codigo as tcod, sum(p.total) as total, sum(p.en_dieta) as dieta
            from tmp_prg_dias d cross join lateral public.poblacion_dia(d.sede_id, d.fecha) p
            left join public.tiempos_comida t on t.id = p.tiempo_comida_id
           where d.dia is not null group by 1, 2, 3) x
   group by 1, 2;
  create index if not exists tmp_prg_pob_idx on tmp_prg_pob (sede_id, fecha);

  -- gramajes por componente y preparacion: servido de la minuta y crudo del ingrediente principal, por grupo de poblacion
  create temp table if not exists tmp_prg_gram (componente_id uuid, preparacion_id uuid, gram jsonb) on commit drop;
  truncate tmp_prg_gram;
  insert into tmp_prg_gram
  select x.componente_id, x.preparacion_id,
         jsonb_build_object('producto', pr.nombre,
           'grupos', (select jsonb_object_agg(g.codigo, jsonb_build_object(
                        'servido', case when cr.crudo is not null then round(cr.crudo * coalesce(fc.factor, prod.rendimiento, 1)) end,
                        'crudo', case when cr.crudo is not null then round(cr.crudo) end,
                        'ajuste', cr.nota))
                        from public.grupos_poblacion g
                        left join lateral (select i2.peso_bruto from public.preparacion_ingredientes i2
                                            where i2.preparacion_id = x.preparacion_id and i2.producto_id = pi.producto_id and (i2.grupo_poblacion_id = g.id or i2.grupo_poblacion_id is null)
                                            order by (i2.grupo_poblacion_id is null) limit 1) base on true
                        -- mismo calculo que la explosion: ajustes por grupo, componente, preparacion o producto (gramajes_ajuste) sobre la receta
                        left join lateral public.crudo_ingrediente(p_contrato, null, p_desde, x.preparacion_id, pi.producto_id, g.id, x.componente_id, base.peso_bruto) cr on base.peso_bruto is not null
                        left join public.preparaciones pp on pp.id = x.preparacion_id
                        left join public.factores_coccion fc on fc.producto_id = pi.producto_id and fc.metodo = pp.metodo_coccion
                        left join public.productos prod on prod.id = pi.producto_id
                        where g.contrato_id = p_contrato))
    from (select distinct (item->>'componente_id')::uuid as componente_id, (item->>'preparacion_id')::uuid as preparacion_id from tmp_prg_menu where item->>'preparacion_id' is not null) x
    left join lateral (select pi.producto_id from public.preparacion_ingredientes pi where pi.preparacion_id = x.preparacion_id order by pi.es_principal desc, pi.orden limit 1) pi on true
    left join public.productos pr on pr.id = pi.producto_id;

  -- agrupacion: sedes con exactamente el mismo menu en todo el rango (y el mismo patron de servicio) van en una sola fila
  create temp table if not exists tmp_prg_grupo (sede_id uuid, firma text, rep uuid, n int) on commit drop;
  truncate tmp_prg_grupo;
  insert into tmp_prg_grupo (sede_id, firma)
  select s.id, md5(coalesce((select string_agg(k, ',' order by k) from (select distinct e.key as k from tmp_prg_pob p, jsonb_each_text(coalesce(p.por_tiempo, '{}'::jsonb)) e where p.sede_id = s.id and e.value::int > 0) z), '')
                 || '#' || coalesce((select string_agg(d.fecha || ':' || coalesce(d.dia::text, '-') || ':' || d.servicio, '|' order by d.fecha) from tmp_prg_dias d where d.sede_id = s.id), '')
                 || '#' || coalesce((select string_agg(m.fecha || ':' || (m.item->>'tiempo') || ':' || (m.item->>'componente') || ':' || coalesce(m.item->>'preparacion_id', '-') || ':' || coalesce(m.item->>'estado', ''), '|' order by m.fecha, m.orden, m.corden, m.item->>'componente')
                                       from tmp_prg_menu m where m.sede_id = s.id), ''))
    from tmp_prg_sedes s;
  if p_agrupar then
    update tmp_prg_grupo g set rep = r.rep, n = r.n
      from (select firma, (array_agg(sede_id order by (select nombre from tmp_prg_sedes where id = sede_id)))[1] as rep, count(*) as n from tmp_prg_grupo group by firma) r
     where r.firma = g.firma;
  else
    update tmp_prg_grupo set rep = sede_id, n = 1 where true;   -- Supabase exige WHERE en todo UPDATE
  end if;
  select count(distinct rep) into v_n_grupos from tmp_prg_grupo;
  if v_n_grupos * v_dias > 2100 then
    raise exception 'Demasiadas filas distintas (% menus distintos x % dias). Filtre sedes o muestre menos semanas.', v_n_grupos, v_dias;
  end if;

  with dias as (
    select g::date as fecha, f.nombre as festivo from generate_series(p_desde, p_hasta, interval '1 day') g left join public.festivos f on f.fecha = g::date),
  menu as (
    select m.sede_id, m.fecha, jsonb_agg(m.item || jsonb_build_object('gramaje', gr.gram) order by m.orden, m.corden, m.item->>'componente') as items
      from tmp_prg_menu m
      left join tmp_prg_gram gr on gr.componente_id = (m.item->>'componente_id')::uuid and gr.preparacion_id = (m.item->>'preparacion_id')::uuid
     group by 1, 2),
  cel as (
    select d.sede_id, d.fecha, d.servicio, d.dia, mn.items,
           (select jsonb_build_object('total', sum(p.total), 'dieta', sum(p.dieta), 'sedes', count(*),
                                      'por_tiempo', (select jsonb_object_agg(k, v) from (select k, sum(v::int) v from tmp_prg_pob p2, jsonb_each_text(coalesce(p2.por_tiempo, '{}'::jsonb)) e(k, v)
                                                                                          where p2.fecha = d.fecha and p2.sede_id in (select g2.sede_id from tmp_prg_grupo g2 where g2.rep = d.sede_id) group by k) z))
              from tmp_prg_pob p where p.fecha = d.fecha and p.sede_id in (select g2.sede_id from tmp_prg_grupo g2 where g2.rep = d.sede_id)) as cupos,
           (select jsonb_build_object('motivo', cs.motivo, 'novedad_id', cs.novedad_id, 'cuenta_ciclo', cs.cuenta_ciclo, 'reposicion', cs.atiende) from public.calendario_servicio cs
             where cs.contrato_id = p_contrato and cs.fecha = d.fecha and (cs.contrato_sede_id = d.sede_id or cs.contrato_sede_id is null)
             order by cs.contrato_sede_id nulls last limit 1) as calendario,
           (select jsonb_build_object('tipo', e.tipo, 'motivo', e.motivo, 'novedad_id', e.novedad_id, 'dia_forzado', e.dia_ciclo_forzado,
                                      'desde', (select n.fecha from public.novedades_servicio n where n.id = e.novedad_id))
              from public.menu_excepciones e
             where e.contrato_id = p_contrato and e.fecha = d.fecha and e.aprobado and e.tipo in ('festivo','especial','emergencia','dia_forzado')
               and (e.contrato_sede_id = d.sede_id or e.contrato_sede_id is null)
             order by e.contrato_sede_id nulls last, e.creado_en desc limit 1) as excepcion
      from tmp_prg_dias d left join menu mn on mn.sede_id = d.sede_id and mn.fecha = d.fecha
     where d.sede_id in (select rep from tmp_prg_grupo))
  select jsonb_build_object(
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'modalidad', c.modalidad, 'dias_atencion', c.dias_atencion,
                                           'se_corre', public.sede_ciclo_se_corre(c.id, null, p_desde)) from public.contratos c where c.id = p_contrato),
    'tiempos', (select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden, 'id', t.id) order by t.orden) from public.tiempos_comida t where t.contrato_id = p_contrato),
    'grupos_poblacion', (select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre) order by g.orden) from public.grupos_poblacion g where g.contrato_id = p_contrato),
    'componentes', (select jsonb_agg(jsonb_build_object('id', co.id, 'tiempo', t.codigo, 'codigo', co.codigo, 'nombre', co.nombre, 'orden', co.orden, 'familia_id', co.familia_id) order by t.orden, co.orden)
                      from public.componentes co join public.tiempos_comida t on t.id = co.tiempo_comida_id where co.contrato_id = p_contrato),
    'sedes', (select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'subtipo', subtipo, 'ciudad', ciudad, 'cupos', cupos) order by nombre) from tmp_prg_sedes),
    -- filas de la cuadricula: una por menu distinto; la mas numerosa es el "menu estandar"
    'filas', (select jsonb_agg(jsonb_build_object('rep', g.rep, 'n', g.n, 'sedes', g.ids, 'estandar', g.rn = 1 and g.n > 1) order by g.rn)
                from (select rep, n, array_agg(sede_id order by (select nombre from tmp_prg_sedes where id = sede_id)) as ids,
                             row_number() over (order by n desc, (select nombre from tmp_prg_sedes where id = rep)) as rn
                        from tmp_prg_grupo group by rep, n) g),
    'total_sedes', (select count(*) from public.contrato_sedes cs where cs.contrato_id = p_contrato and cs.estado = 'activa'),
    'dias', (select jsonb_agg(jsonb_build_object('fecha', fecha, 'festivo', festivo) order by fecha) from dias),
    'celdas', (select jsonb_agg(jsonb_build_object('sede_id', sede_id, 'fecha', fecha, 'servicio', servicio, 'cupos', cupos, 'sin_servicio', case when not servicio then calendario end,
                                                   'reposicion', case when servicio and (calendario->>'reposicion')::boolean then calendario end,
                                                   'excepcion', excepcion, 'dia', dia, 'items', coalesce(items, '[]'::jsonb))) from cel),
    'novedades', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'sede_id', n.contrato_sede_id, 'fecha', n.fecha, 'fecha_hasta', n.fecha_hasta, 'tipo', n.tipo, 'accion', n.accion,
                           'fecha_destino', n.fecha_destino, 'motivo', n.motivo, 'estado', n.estado, 'aviso_entidad_en', n.aviso_entidad_en, 'aviso_interventoria_en', n.aviso_interventoria_en,
                           'aprobada_entidad', n.aprobada_entidad, 'creado_por', n.creado_por, 'n_productos', jsonb_array_length(coalesce(n.materia_prima->'productos', '[]'::jsonb)),
                           'raciones', n.materia_prima->'raciones') order by n.fecha), '[]'::jsonb)
                    from public.novedades_servicio n
                   where n.contrato_id = p_contrato and n.estado in ('propuesta','aprobada') and n.fecha <= p_hasta and coalesce(n.fecha_hasta, n.fecha) >= p_desde
                     and (n.contrato_sede_id is null or n.contrato_sede_id in (select id from tmp_prg_sedes)))
  ) into v_res;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- M4. Grants explicitos a authenticated (no depender del privilegio por defecto)
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('simular_poblacion','poblacion_contrato','puede_editar_poblacion','guardar_cupos','guardar_dietas','importar_poblacion',
              'puede_ver_explosion','explosion_resumen','explosion_producto','explosiones_contrato','anular_explosion','explosion_avance','explosion_por_sede',
              'minutas_contrato','ciclo_detalle','puede_editar_planeacion','guardar_ciclo_item','crear_ciclo','estado_ciclo','asignar_ciclo','guardar_gramajes',
              'calendario_contrato','marcar_calendario','guardar_parte_diario','partes_dia','contratos_grupo','consolidadas_lista','consolidada_detalle','anular_consolidada','cobertura_volumen',
              'programacion','dia_ciclo','calcular_explosion','poblacion_dia','crudo_ingrediente') loop
    execute format('revoke all on function %s from public, anon', r.f);
    execute format('grant execute on function %s to authenticated', r.f);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function %s to service_role', r.f); end if;
  end loop;
end $$;
