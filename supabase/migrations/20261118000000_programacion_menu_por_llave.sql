-- Supply ERP · Migracion 018 · Programacion: el menu se calcula una vez por llave (ciclo + variante + dias) y se comparte entre sedes sin intercambios propios
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
                        'servido', (select mp.porcion_servida || ' ' || mp.unidad from public.minuta_patron mp
                                     where mp.componente_id = x.componente_id and (mp.grupo_poblacion_id = g.id or mp.grupo_poblacion_id is null)
                                       and (mp.producto_id = pi.producto_id or mp.producto_id is null)
                                     order by (mp.producto_id is null), (mp.grupo_poblacion_id is null) limit 1),
                        'crudo', (select round(i2.peso_bruto) from public.preparacion_ingredientes i2
                                   where i2.preparacion_id = x.preparacion_id and i2.producto_id = pi.producto_id and (i2.grupo_poblacion_id = g.id or i2.grupo_poblacion_id is null)
                                   order by (i2.grupo_poblacion_id is null) limit 1)))
                        from public.grupos_poblacion g where g.contrato_id = p_contrato))
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

-- dia_ciclo: el conteo de dias de servicio desde el ancla se hace con un join a festivos en vez de llamar es_dia_habil dia por dia
-- (en PAE con 34 colegios x 4 semanas eran 88.000 llamadas; ahora un solo barrido por celda)
create or replace function public.dia_ciclo(p_contrato_sede uuid, p_fecha date)
returns table(ciclo_id uuid, dia integer, variante_id uuid)
language plpgsql stable rows 1 set search_path = public as $$
declare sc record; v_contrato uuid; v_dias text; v_n int; v_pos int; v_ancla date; v_exc record;
begin
  select cs.contrato_id into v_contrato from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if v_contrato is null or not public.es_dia_servicio(v_contrato, p_contrato_sede, p_fecha) then return; end if;
  select * into v_exc from public.menu_excepciones e
   where e.contrato_id = v_contrato and e.fecha = p_fecha and (e.contrato_sede_id = p_contrato_sede or e.contrato_sede_id is null)
     and e.tipo in ('festivo','especial','emergencia','dia_forzado') and e.aprobado
   order by e.contrato_sede_id nulls last, e.creado_en desc limit 1;
  select * into sc from public.sede_ciclo s
   where s.contrato_sede_id = p_contrato_sede and s.vigente_desde <= p_fecha and (s.vigente_hasta is null or s.vigente_hasta >= p_fecha)
   order by s.vigente_desde desc limit 1;
  if sc.id is null then return; end if;
  if v_exc.id is not null and v_exc.ciclo_alterno_id is not null then return query select v_exc.ciclo_alterno_id, 1, sc.variante_id; return; end if;
  if v_exc.id is not null and v_exc.dia_ciclo_forzado is not null then return query select sc.ciclo_id, v_exc.dia_ciclo_forzado, sc.variante_id; return; end if;
  select n_menus into v_n from public.ciclos_menu where id = sc.ciclo_id;
  v_ancla := sc.fecha_inicio_menu1;
  if sc.modo_reinicio = 'mensual' then v_ancla := greatest(sc.fecha_inicio_menu1, date_trunc('month', p_fecha)::date); end if;
  if sc.modo_reinicio = 'semanal' then v_ancla := greatest(sc.fecha_inicio_menu1, date_trunc('week', p_fecha)::date); end if;
  if p_fecha < v_ancla then return; end if;
  if sc.avanza_sin_servicio then
    v_pos := (p_fecha - v_ancla);
  else
    select dias_atencion into v_dias from public.contratos where id = v_contrato;
    select count(*) into v_pos
      from generate_series(v_ancla, p_fecha - 1, interval '1 day') g
      left join lateral (select cs.atiende, cs.cuenta_ciclo from public.calendario_servicio cs where cs.contrato_id = v_contrato and cs.fecha = g::date
                            and (cs.contrato_sede_id = p_contrato_sede or cs.contrato_sede_id is null) order by cs.contrato_sede_id nulls last limit 1) x on true
      left join public.festivos f on f.fecha = g::date
     where coalesce(x.atiende or x.cuenta_ciclo, v_dias = 'todos' or (extract(isodow from g) between 1 and 5 and f.fecha is null));
  end if;
  return query select sc.ciclo_id, (v_pos % v_n) + 1, sc.variante_id;
end $$;
