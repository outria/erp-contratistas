-- Supply ERP · Migracion 012 · La programacion devuelve los componentes en el orden de la minuta (no alfabetico)
create or replace function public.programacion(p_contrato uuid, p_desde date, p_hasta date, p_sedes uuid[] default null, p_incluye_propuestos boolean default false)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare v_emp uuid; v_mi_sede uuid; v_res jsonb;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then
    raise exception 'Sin permiso';
  end if;
  if p_hasta - p_desde > 70 then raise exception 'Maximo 10 semanas por consulta.'; end if;
  -- un usuario amarrado a una sede (administrador de rancho) solo ve la suya
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver')) then v_mi_sede := public.mi_sede(v_emp); end if;

  create temp table if not exists tmp_prg_sedes (id uuid, nombre text, subtipo text, ciudad text, cupos int) on commit drop;
  truncate tmp_prg_sedes;
  insert into tmp_prg_sedes
  select cs.id, s.nombre, s.subtipo, s.ciudad, cs.cupos_referencia
    from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
   where cs.contrato_id = p_contrato and cs.estado = 'activa'
     and (p_sedes is null or cs.id = any (p_sedes)) and (v_mi_sede is null or cs.sede_id = v_mi_sede);
  -- menu plano de todas las celdas en una sola pasada (igual que la explosion), luego se agrupa
  create temp table if not exists tmp_prg_menu (sede_id uuid, fecha date, item jsonb) on commit drop;
  truncate tmp_prg_menu;
  insert into tmp_prg_menu
  select s.id, g::date,
         jsonb_build_object('tiempo', m.tiempo_codigo, 'orden', m.tiempo_orden, 'componente_id', m.componente_id, 'componente', m.componente_codigo,
                            'preparacion_id', m.preparacion_id, 'preparacion', coalesce(m.preparacion_nombre, m.descriptor), 'origen', m.origen,
                            'intercambio_id', m.intercambio_id, 'clase', x.clase, 'estado', x.estado, 'corden', c.orden, 'componente_nombre', c.nombre)
    from tmp_prg_sedes s cross join generate_series(p_desde, p_hasta, interval '1 day') g
    cross join lateral public.menu_del_dia(s.id, g::date, p_incluye_propuestos) m
    left join public.componentes c on c.id = m.componente_id
    left join public.intercambios_menu x on x.id = m.intercambio_id;

  with dias as (
    select g::date as fecha, f.nombre as festivo from generate_series(p_desde, p_hasta, interval '1 day') g left join public.festivos f on f.fecha = g::date),
  cel as (
    select s.id as sede_id, d.fecha,
           public.es_dia_servicio(p_contrato, s.id, d.fecha) as servicio,
           (select jsonb_build_object('motivo', cs.motivo, 'novedad_id', cs.novedad_id, 'cuenta_ciclo', cs.cuenta_ciclo) from public.calendario_servicio cs
             where cs.contrato_id = p_contrato and cs.fecha = d.fecha and not cs.atiende and (cs.contrato_sede_id = s.id or cs.contrato_sede_id is null)
             order by cs.contrato_sede_id nulls last limit 1) as sin_servicio,
           dc.dia,
           (select jsonb_agg(m.item order by (m.item->>'orden')::int, (m.item->>'corden')::int, m.item->>'componente') from tmp_prg_menu m where m.sede_id = s.id and m.fecha = d.fecha) as items
      from tmp_prg_sedes s cross join dias d
      left join lateral public.dia_ciclo(s.id, d.fecha) dc on true)
  select jsonb_build_object(
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'modalidad', c.modalidad, 'dias_atencion', c.dias_atencion) from public.contratos c where c.id = p_contrato),
    'tiempos', (select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden, 'id', t.id) order by t.orden) from public.tiempos_comida t where t.contrato_id = p_contrato),
    'componentes', (select jsonb_agg(jsonb_build_object('id', co.id, 'tiempo', t.codigo, 'codigo', co.codigo, 'nombre', co.nombre, 'orden', co.orden, 'familia_id', co.familia_id) order by t.orden, co.orden)
                      from public.componentes co join public.tiempos_comida t on t.id = co.tiempo_comida_id where co.contrato_id = p_contrato),
    'sedes', (select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'subtipo', subtipo, 'ciudad', ciudad, 'cupos', cupos) order by nombre) from tmp_prg_sedes),
    'dias', (select jsonb_agg(jsonb_build_object('fecha', fecha, 'festivo', festivo) order by fecha) from dias),
    'celdas', (select jsonb_agg(jsonb_build_object('sede_id', sede_id, 'fecha', fecha, 'servicio', servicio, 'sin_servicio', sin_servicio, 'dia', dia, 'items', coalesce(items, '[]'::jsonb))) from cel),
    'novedades', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'sede_id', n.contrato_sede_id, 'fecha', n.fecha, 'fecha_hasta', n.fecha_hasta, 'tipo', n.tipo, 'accion', n.accion,
                           'fecha_destino', n.fecha_destino, 'motivo', n.motivo, 'estado', n.estado, 'aviso_entidad_en', n.aviso_entidad_en, 'aviso_interventoria_en', n.aviso_interventoria_en,
                           'aprobada_entidad', n.aprobada_entidad, 'materia_prima', n.materia_prima) order by n.fecha), '[]'::jsonb)
                    from public.novedades_servicio n
                   where n.contrato_id = p_contrato and n.estado in ('propuesta','aprobada') and n.fecha <= p_hasta and coalesce(n.fecha_hasta, n.fecha) >= p_desde
                     and (n.contrato_sede_id is null or n.contrato_sede_id in (select id from tmp_prg_sedes)))
  ) into v_res;
  return v_res;
end $$;
