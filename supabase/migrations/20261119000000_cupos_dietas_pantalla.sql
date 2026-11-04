-- Supply ERP · Migracion 019 · Pantalla de cupos y dietas: consulta, guardado por vigencias e importacion desde Excel
-- Reglas: cupos y dietas se guardan por vigencia (fecha_desde / fecha_hasta); un cambio cierra la vigencia anterior el dia
-- antes y abre la nueva. Si en una misma fecha se corrige, se reemplaza. Permiso: M2 editar (planeacion); M7 editar solo su sede.
set client_min_messages = warning;
create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Consulta: lo que rige en una fecha, por sede, con los catalogos del contrato
-- ---------------------------------------------------------------------
create or replace function public.poblacion_contrato(p_contrato uuid, p_fecha date default null)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_f date := coalesce(p_fecha, (now() at time zone 'America/Bogota')::date); v_mi_sede uuid; r jsonb;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then
    raise exception 'Sin permiso';
  end if;
  if not (public.es_admin_sql() or public.es_superadmin()) then v_mi_sede := public.mi_sede(v_emp); end if;
  select jsonb_build_object(
    'fecha', v_f,
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'modalidad', c.modalidad) from public.contratos c where c.id = p_contrato),
    'grupos', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nombre', g.nombre, 'tipo', g.tipo) order by g.orden), '[]') from public.grupos_poblacion g where g.contrato_id = p_contrato),
    'tiempos', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'codigo', t.codigo, 'nombre', t.nombre) order by t.orden), '[]') from public.tiempos_comida t where t.contrato_id = p_contrato),
    'variantes', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'codigo', v.codigo, 'nombre', v.nombre, 'es_estandar', v.es_estandar) order by v.es_estandar desc, v.codigo), '[]') from public.variantes_racion v where v.contrato_id = p_contrato),
    'dietas', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'codigo', d.codigo, 'nombre', d.nombre_oficial, 'categoria', d.categoria) order by d.categoria, d.nombre_oficial), '[]')
                 from public.tipos_dieta d where d.empresa_id is null or d.empresa_id = v_emp),
    'sedes', (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre, 'ciudad', s.ciudad, 'subtipo', s.subtipo, 'cupos_referencia', cs.cupos_referencia,
                 'variante_id', (select sc.variante_id from public.sede_ciclo sc where sc.contrato_sede_id = cs.id and sc.vigente_desde <= v_f and (sc.vigente_hasta is null or sc.vigente_hasta >= v_f) order by sc.vigente_desde desc limit 1),
                 'cupos', (select coalesce(jsonb_agg(jsonb_build_object('grupo_id', cu.grupo_poblacion_id, 'tiempo_id', cu.tiempo_comida_id, 'variante_id', cu.variante_id, 'cantidad', cu.cantidad, 'desde', cu.fecha_desde, 'fuente', cu.fuente)), '[]')
                             from public.cupos cu where cu.contrato_sede_id = cs.id and cu.fecha_desde <= v_f and (cu.fecha_hasta is null or cu.fecha_hasta >= v_f)),
                 'dietas', (select coalesce(jsonb_agg(jsonb_build_object('dieta_id', dp.tipo_dieta_id, 'grupo_id', dp.grupo_poblacion_id, 'cantidad', dp.cantidad, 'desde', dp.fecha_desde, 'fuente', dp.fuente)), '[]')
                              from public.dietas_poblacion dp where dp.contrato_sede_id = cs.id and dp.fecha_desde <= v_f and (dp.fecha_hasta is null or dp.fecha_hasta >= v_f)),
                 'proxima', (select min(cu.fecha_desde) from public.cupos cu where cu.contrato_sede_id = cs.id and cu.fecha_desde > v_f),
                 'parte_hoy', (select sum(pd.cantidad) from public.partes_diarios pd where pd.contrato_sede_id = cs.id and pd.fecha = v_f)
               ) order by s.nombre), '[]')
                from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
               where cs.contrato_id = p_contrato and cs.estado = 'activa' and (v_mi_sede is null or cs.sede_id = v_mi_sede)),
    'historial', (select coalesce(jsonb_agg(x order by (x->>'desde') desc), '[]') from (
                    select distinct jsonb_build_object('desde', cu.fecha_desde, 'fuente', cu.fuente) x
                      from public.cupos cu join public.contrato_sedes cs on cs.id = cu.contrato_sede_id where cs.contrato_id = p_contrato limit 24) z)
  ) into r;
  return r;
end $$;
revoke all on function public.poblacion_contrato(uuid, date) from public, anon;

-- ---------------------------------------------------------------------
-- 2. Guardar cupos de una sede desde una fecha (cierra la vigencia anterior)
--    p_items: [{grupo_id, tiempo_id, variante_id, cantidad}]
-- ---------------------------------------------------------------------
create or replace function public.puede_editar_poblacion(p_contrato_sede uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid; v_sede uuid;
begin
  select cs.empresa_id, cs.sede_id into v_emp, v_sede from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if v_emp is null then return false; end if;
  return public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'editar')
      or (public.tiene_permiso(v_emp, 'M7', 'editar') and public.mi_sede(v_emp) = v_sede);
end $$;
revoke all on function public.puede_editar_poblacion(uuid) from public, anon;

create or replace function public.guardar_cupos(p_contrato_sede uuid, p_desde date, p_items jsonb, p_fuente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_g uuid; v_t uuid; v_v uuid; v_c int;
begin
  if not public.puede_editar_poblacion(p_contrato_sede) then raise exception 'Sin permiso para editar los cupos de esta sede.'; end if;
  if p_desde is null then raise exception 'Falta la fecha desde la que rigen los cupos.'; end if;
  select empresa_id into v_emp from public.contrato_sedes where id = p_contrato_sede;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_g := (it->>'grupo_id')::uuid; v_t := (it->>'tiempo_id')::uuid; v_v := (it->>'variante_id')::uuid; v_c := coalesce((it->>'cantidad')::int, 0);
    if v_g is null then raise exception 'Cada cupo necesita grupo de poblacion.'; end if;
    if v_c < 0 then raise exception 'La cantidad no puede ser negativa.'; end if;
    -- la misma fecha se corrige en sitio; las vigencias anteriores se cierran el dia antes
    delete from public.cupos c where c.contrato_sede_id = p_contrato_sede and c.grupo_poblacion_id = v_g
       and c.tiempo_comida_id is not distinct from v_t and c.variante_id is not distinct from v_v and c.fecha_desde = p_desde;
    -- se cierra la vigencia anterior del mismo grupo y tiempo (la variante es de la sede, no de la poblacion)
    update public.cupos c set fecha_hasta = p_desde - 1
     where c.contrato_sede_id = p_contrato_sede and c.grupo_poblacion_id = v_g
       and c.tiempo_comida_id is not distinct from v_t
       and c.fecha_desde < p_desde and (c.fecha_hasta is null or c.fecha_hasta >= p_desde);
    if v_c > 0 then
      insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, tiempo_comida_id, variante_id, fecha_desde, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, v_g, v_t, v_v, p_desde, v_c, coalesce(p_fuente, 'registro manual'), auth.uid());
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('filas', n, 'desde', p_desde);
end $$;
revoke all on function public.guardar_cupos(uuid, date, jsonb, text) from public, anon;

-- p_items: [{dieta_id, grupo_id, cantidad}]
create or replace function public.guardar_dietas(p_contrato_sede uuid, p_desde date, p_items jsonb, p_fuente text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; it jsonb; n int := 0; v_d uuid; v_g uuid; v_c int;
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
    if v_c > 0 then
      insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, cantidad, fuente, creado_por)
      values (v_emp, p_contrato_sede, v_d, v_g, p_desde, v_c, coalesce(p_fuente, 'registro manual'), auth.uid());
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('filas', n, 'desde', p_desde);
end $$;
revoke all on function public.guardar_dietas(uuid, date, jsonb, text) from public, anon;

-- ---------------------------------------------------------------------
-- 3. Importar desde Excel (la plantilla de recoleccion). El navegador lee el archivo y manda las filas;
--    aqui se resuelven sede, grupo, tiempo y dieta por nombre o codigo, y se devuelve fila por fila que paso.
--    p_filas: [{fila, sede, grupo, tiempo, variante, dieta, cantidad, desde}]  (grupo/tiempo/dieta por codigo o nombre)
--    p_aplicar false = solo previsualizar.
-- ---------------------------------------------------------------------
create or replace function public.importar_poblacion(p_contrato uuid, p_tipo text, p_filas jsonb, p_desde date, p_fuente text default null, p_aplicar boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; f jsonb; v_cs uuid; v_g uuid; v_t uuid; v_v uuid; v_d uuid; v_c int; v_desde date; v_err text; v_sede_nombre text; v_sim numeric;
        res jsonb := '[]'::jsonb; ok int := 0; mal int := 0; agr jsonb := '{}'::jsonb; k text; cs_key text;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'editar')) then raise exception 'Sin permiso (Planeacion: editar).'; end if;
  if p_tipo not in ('cupos', 'dietas') then raise exception 'Tipo de importacion no valido: %', p_tipo; end if;

  for f in select * from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) loop
    v_err := null; v_cs := null; v_g := null; v_t := null; v_v := null; v_d := null; v_sede_nombre := null;
    v_c := nullif(regexp_replace(coalesce(f->>'cantidad', ''), '[^0-9]', '', 'g'), '')::int;
    begin v_desde := coalesce(nullif(f->>'desde', '')::date, p_desde); exception when others then v_desde := p_desde; v_err := 'fecha no valida'; end;
    -- sede: exacta sin acentos ni mayusculas, luego la mas parecida (trigramas) si supera 0,45
    select cs.id, s.nombre into v_cs, v_sede_nombre
      from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
     where cs.contrato_id = p_contrato and cs.estado = 'activa' and lower(unaccent(s.nombre)) = lower(unaccent(trim(coalesce(f->>'sede', '')))) limit 1;
    if v_cs is null and coalesce(f->>'sede', '') <> '' then
      select cs.id, s.nombre, similarity(lower(unaccent(s.nombre)), lower(unaccent(f->>'sede'))) into v_cs, v_sede_nombre, v_sim
        from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
       where cs.contrato_id = p_contrato and cs.estado = 'activa'
       order by similarity(lower(unaccent(s.nombre)), lower(unaccent(f->>'sede'))) desc limit 1;
      if v_sim is null or v_sim < 0.45 then v_cs := null; v_sede_nombre := null; end if;
    end if;
    if v_cs is null then v_err := coalesce(v_err || '; ', '') || 'sede no encontrada en el contrato'; end if;
    -- grupo por codigo o por nombre (o unico grupo del contrato si no viene)
    if coalesce(f->>'grupo', '') <> '' then
      select g.id into v_g from public.grupos_poblacion g where g.contrato_id = p_contrato
        and (lower(g.codigo) = lower(trim(f->>'grupo')) or lower(unaccent(g.nombre)) = lower(unaccent(trim(f->>'grupo')))
             or lower(unaccent(g.nombre)) like lower(unaccent(trim(f->>'grupo'))) || '%'
             or (g.tipo = 'sexo' and lower(left(trim(f->>'grupo'), 1)) = lower(g.codigo))) order by g.orden limit 1;
      if v_g is null then
        select g.id into v_g from public.grupos_poblacion g where g.contrato_id = p_contrato
         order by similarity(lower(unaccent(g.nombre)), lower(unaccent(f->>'grupo'))) desc limit 1;
        if v_g is not null and (select similarity(lower(unaccent(g.nombre)), lower(unaccent(f->>'grupo'))) from public.grupos_poblacion g where g.id = v_g) < 0.4 then v_g := null; end if;
      end if;
      if v_g is null then v_err := coalesce(v_err || '; ', '') || 'grupo "' || (f->>'grupo') || '" no existe en el contrato'; end if;
    else
      select g.id into v_g from public.grupos_poblacion g where g.contrato_id = p_contrato order by g.orden limit 1;
      if (select count(*) from public.grupos_poblacion g where g.contrato_id = p_contrato) > 1 then v_err := coalesce(v_err || '; ', '') || 'falta el grupo (sexo o grupo etario)'; end if;
    end if;
    if p_tipo = 'cupos' then
      if coalesce(f->>'tiempo', '') <> '' then
        select t.id into v_t from public.tiempos_comida t where t.contrato_id = p_contrato
          and (lower(t.codigo) = lower(trim(f->>'tiempo')) or lower(unaccent(t.nombre)) like lower(unaccent(trim(f->>'tiempo'))) || '%') order by t.orden limit 1;
        if v_t is null then v_err := coalesce(v_err || '; ', '') || 'tiempo/modalidad "' || (f->>'tiempo') || '" no existe'; end if;
      end if;
      if coalesce(f->>'variante', '') <> '' then
        select v.id into v_v from public.variantes_racion v where v.contrato_id = p_contrato
          and (lower(v.codigo) = lower(trim(f->>'variante')) or lower(unaccent(v.nombre)) like lower(unaccent(trim(f->>'variante'))) || '%'
               or (upper(trim(f->>'variante')) = 'ERON' and v.es_estandar)) limit 1;
      elsif v_cs is not null and (select count(*) from public.variantes_racion v where v.contrato_id = p_contrato) > 1 then
        -- solo cuando el contrato maneja variantes (ERON / EP) se guarda la de la sede
        select sc.variante_id into v_v from public.sede_ciclo sc where sc.contrato_sede_id = v_cs order by sc.vigente_desde desc limit 1;
        if v_v is null then select v.id into v_v from public.variantes_racion v where v.contrato_id = p_contrato and v.es_estandar limit 1; end if;
      end if;
    else
      select d.id into v_d from public.tipos_dieta d where (d.empresa_id is null or d.empresa_id = v_emp)
        and (lower(d.codigo) = lower(trim(coalesce(f->>'dieta', ''))) or lower(unaccent(d.nombre_oficial)) = lower(unaccent(trim(coalesce(f->>'dieta', ''))))
             or lower(unaccent(replace(d.nombre_oficial, 'Dieta ', ''))) = lower(unaccent(trim(coalesce(f->>'dieta', '')))))
        order by (d.empresa_id is not null) desc limit 1;
      if v_d is null and coalesce(f->>'dieta', '') <> '' then
        select d.id into v_d from public.tipos_dieta d where (d.empresa_id is null or d.empresa_id = v_emp)
         order by similarity(lower(unaccent(d.nombre_oficial)), lower(unaccent(f->>'dieta'))) desc limit 1;
        if v_d is not null and (select similarity(lower(unaccent(d.nombre_oficial)), lower(unaccent(f->>'dieta'))) from public.tipos_dieta d where d.id = v_d) < 0.35 then v_d := null; end if;
      end if;
      if v_d is null then v_err := coalesce(v_err || '; ', '') || 'dieta "' || coalesce(f->>'dieta', '') || '" no esta en el catalogo'; end if;
    end if;
    if v_c is null then v_err := coalesce(v_err || '; ', '') || 'cantidad vacia o no numerica'; end if;

    if v_err is null then
      ok := ok + 1;
      -- agrupar por sede + fecha para guardar en una sola llamada (la misma llave se suma: varias filas del mismo colegio y grupo)
      cs_key := v_cs::text || '|' || v_desde::text;
      k := coalesce(v_g::text, '') || '|' || coalesce(v_t::text, '') || '|' || coalesce(v_v::text, '') || '|' || coalesce(v_d::text, '');
      if not (agr ? cs_key) then agr := agr || jsonb_build_object(cs_key, '{}'::jsonb); end if;
      agr := jsonb_set(agr, array[cs_key, k], to_jsonb(coalesce((agr #>> array[cs_key, k])::int, 0) + v_c), true);
    else
      mal := mal + 1;
    end if;
    res := res || jsonb_build_object('fila', f->'fila', 'sede', f->>'sede', 'sede_resuelta', v_sede_nombre, 'cantidad', v_c, 'desde', v_desde, 'error', v_err);
  end loop;

  if p_aplicar and mal = 0 and ok > 0 then
    for cs_key in select * from jsonb_object_keys(agr) loop
      v_cs := split_part(cs_key, '|', 1)::uuid; v_desde := split_part(cs_key, '|', 2)::date;
      if p_tipo = 'cupos' then
        perform public.guardar_cupos(v_cs, v_desde,
          (select jsonb_agg(jsonb_build_object('grupo_id', nullif(split_part(e.key, '|', 1), ''), 'tiempo_id', nullif(split_part(e.key, '|', 2), ''), 'variante_id', nullif(split_part(e.key, '|', 3), ''), 'cantidad', e.value))
             from jsonb_each(agr->cs_key) e), coalesce(p_fuente, 'importacion Excel'));
      else
        perform public.guardar_dietas(v_cs, v_desde,
          (select jsonb_agg(jsonb_build_object('dieta_id', nullif(split_part(e.key, '|', 4), ''), 'grupo_id', nullif(split_part(e.key, '|', 1), ''), 'cantidad', e.value))
             from jsonb_each(agr->cs_key) e), coalesce(p_fuente, 'importacion Excel'));
      end if;
    end loop;
    insert into public.importaciones (empresa_id, tipo, archivo, filas_leidas, filas_cargadas, errores, estado)
    values (v_emp, p_tipo, p_fuente, ok + mal, ok, '[]'::jsonb, 'procesada');
  end if;
  return jsonb_build_object('ok', ok, 'con_error', mal, 'aplicado', p_aplicar and mal = 0 and ok > 0, 'sedes', (select count(*) from jsonb_object_keys(agr)), 'filas', res);
end $$;
revoke all on function public.importar_poblacion(uuid, text, jsonb, date, text, boolean) from public, anon;

