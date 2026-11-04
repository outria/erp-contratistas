-- =====================================================================
-- Supply ERP · Migracion 013 · Correcciones de la auditoria de la etapa 4C (03-nov-2026)
-- A1 aprobacion de novedades por sede y sin autoaprobacion; A2 usuario amarrado a sede solo ve la suya;
-- A3 rendimiento y tamano de programacion; A4 "correr" solo donde el ciclo se corre; A5 bordes de "trasladar";
-- M1 novedades solapadas; M3 foto de materia prima despues del RLS y sin ruido de bitacora; M5 la cuadricula dice
-- que paso con el menu; B5 bordes de estado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- M3. Bitacora silenciable para calculos temporales
-- ---------------------------------------------------------------------
create or replace function public.registrar_bitacora()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id text; v_fila jsonb;
begin
  if current_setting('supply.sin_bitacora', true) = 'si' then return coalesce(new, old); end if;
  v_fila := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_emp := (v_fila->>'empresa_id')::uuid;
  v_id  := coalesce(v_fila->>'id', v_fila->>'clave');
  if tg_table_name = 'permisos' then
    select empresa_id into v_emp from public.roles where id = (v_fila->>'rol_id')::uuid;
    v_id := (v_fila->>'rol_id') || ':' || (v_fila->>'modulo') || ':' || (v_fila->>'accion');
  end if;
  insert into public.bitacora (empresa_id, usuario_id, tabla, registro_id, accion, antes, despues)
  values (v_emp, auth.uid(), tg_table_name, v_id, tg_op,
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

-- materia prima del dia: respeta la sede del usuario y no deja rastro en bitacora
create or replace function public.materia_prima_dia(p_contrato uuid, p_fecha date, p_contrato_sede uuid default null, p_fecha_hasta date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid; v_res jsonb; v_mi uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then
    raise exception 'Sin permiso';
  end if;
  v_mi := case when public.es_admin_sql() or public.es_superadmin() then null else public.mi_sede(v_emp) end;
  if v_mi is not null and (p_contrato_sede is null or not exists (select 1 from public.contrato_sedes cs where cs.id = p_contrato_sede and cs.sede_id = v_mi)) then
    raise exception 'Su usuario solo puede consultar su sede.';
  end if;
  perform set_config('supply.sin_bitacora', 'si', true);
  insert into public.explosiones (empresa_id, contrato_id, codigo, nombre, fecha_desde, fecha_hasta, sedes, estado, tipo)
  values (v_emp, p_contrato, 'TMP-' || substr(gen_random_uuid()::text, 1, 8), 'materia prima del dia', p_fecha, coalesce(p_fecha_hasta, p_fecha),
          case when p_contrato_sede is null then null else array[p_contrato_sede] end, 'borrador', 'proyeccion') returning id into v_id;
  perform public.calcular_explosion(v_id);
  select jsonb_build_object(
           'raciones', (select raciones from public.explosiones where id = v_id),
           'productos', coalesce(jsonb_agg(jsonb_build_object('producto_id', producto_id, 'codigo', codigo, 'nombre', nombre, 'categoria', categoria,
                                   'cantidad_base', round(cantidad_base, 1), 'unidad_base', unidad_base, 'cantidad_compra', cantidad_compra, 'unidad_compra', unidad_compra) order by cantidad_base desc), '[]'))
    into v_res from public.v_explosion_productos where explosion_id = v_id;
  delete from public.explosiones where id = v_id;
  perform set_config('supply.sin_bitacora', '', true);
  return v_res;
end $$;

-- la foto se toma DESPUES de que la fila paso el RLS (trigger after), no antes
drop trigger if exists novedades_servicio_foto on public.novedades_servicio;
create or replace function public.foto_materia_prima_novedad() returns trigger language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if new.materia_prima is null then
    begin v := public.materia_prima_dia(new.contrato_id, new.fecha, new.contrato_sede_id, new.fecha_hasta);
    exception when others then v := jsonb_build_object('error', sqlerrm); end;
    update public.novedades_servicio set materia_prima = v where id = new.id;
  end if;
  return null;
end $$;
create trigger novedades_servicio_foto after insert on public.novedades_servicio for each row execute function public.foto_materia_prima_novedad();

-- ---------------------------------------------------------------------
-- A4 + A5 + M1. Validaciones al proponer: correr solo si el ciclo se corre; trasladar un solo dia; sin solapes
-- ---------------------------------------------------------------------
create or replace function public.sede_ciclo_se_corre(p_contrato uuid, p_contrato_sede uuid, p_fecha date) returns boolean language sql stable set search_path = public as $$
  -- true si al menos una sede afectada tiene un ciclo que solo avanza en dias de servicio (PAE); false si todas avanzan todos los dias (USPEC, casinos)
  select coalesce(bool_or(not sc.avanza_sin_servicio), false)
    from public.contrato_sedes cs
    join lateral (select s.avanza_sin_servicio from public.sede_ciclo s where s.contrato_sede_id = cs.id and s.vigente_desde <= p_fecha and (s.vigente_hasta is null or s.vigente_hasta >= p_fecha) order by s.vigente_desde desc limit 1) sc on true
   where cs.contrato_id = p_contrato and cs.estado = 'activa' and (p_contrato_sede is null or cs.id = p_contrato_sede);
$$;

create or replace function public.validar_novedad() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.accion = 'correr' and not public.sede_ciclo_se_corre(new.contrato_id, new.contrato_sede_id, new.fecha) then
    raise exception 'En este contrato el ciclo avanza todos los dias: el menu no se puede correr. Escoja trasladar o perder.';
  end if;
  if new.accion = 'trasladar' then
    if new.fecha_hasta is not null and new.fecha_hasta <> new.fecha then raise exception 'Trasladar aplica a un solo dia: registre una novedad por cada dia que se traslada.'; end if;
    if new.fecha_destino <= new.fecha then raise exception 'La fecha destino debe ser posterior al dia sin servicio.'; end if;
  end if;
  if tg_op = 'INSERT' and exists (
      select 1 from public.novedades_servicio n
       where n.contrato_id = new.contrato_id and n.estado in ('propuesta','aprobada')
         and (n.contrato_sede_id is null or new.contrato_sede_id is null or n.contrato_sede_id = new.contrato_sede_id)
         and n.fecha <= coalesce(new.fecha_hasta, new.fecha) and coalesce(n.fecha_hasta, n.fecha) >= new.fecha) then
    raise exception 'Ya hay una novedad propuesta o aprobada que cubre ese dia en esa sede.';
  end if;
  return new;
end $$;
drop trigger if exists novedades_servicio_validar on public.novedades_servicio;
create trigger novedades_servicio_validar before insert or update on public.novedades_servicio for each row execute function public.validar_novedad();

-- un solo registro de calendario por contrato/sede/fecha
create unique index if not exists calendario_servicio_unico on public.calendario_servicio (contrato_id, coalesce(contrato_sede_id, '00000000-0000-0000-0000-000000000000'::uuid), fecha);

-- ---------------------------------------------------------------------
-- A1 + A5 + B5. Decidir la novedad: quien, con que alcance, y que pasa con el traslado
-- ---------------------------------------------------------------------
create or replace function public.decidir_novedad_servicio(p_id uuid, p_decision text, p_nota text default null, p_desplazar boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n public.novedades_servicio; s record; d date; v_dia int; v_dia_dest int; v_admin boolean; v_mi uuid; v_ok boolean; v_avisos text[] := '{}';
begin
  select * into n from public.novedades_servicio where id = p_id for update;
  if n.id is null then raise exception 'Novedad no encontrada'; end if;
  v_admin := public.es_admin_sql() or public.es_superadmin();
  v_mi := public.mi_sede(n.empresa_id);
  -- direccion de operaciones / planeacion (M2 aprobar) decide todo; el aprobador de sede (M7 aprobar) solo su sede y nunca lo que propuso el mismo
  v_ok := v_admin or public.tiene_permiso(n.empresa_id, 'M2', 'aprobar')
       or (public.tiene_permiso(n.empresa_id, 'M7', 'aprobar') and n.contrato_sede_id is not null
           and (v_mi is null or exists (select 1 from public.contrato_sedes cs where cs.id = n.contrato_sede_id and cs.sede_id = v_mi))
           and n.creado_por is distinct from auth.uid())
       or (p_decision = 'anular' and n.creado_por = auth.uid() and n.estado = 'propuesta');
  if not v_ok then raise exception 'Sin permiso: la novedad la aprueba la direccion de operaciones (o el aprobador de la sede, si no la propuso el mismo).'; end if;

  if p_decision = 'aprobar' then
    if n.estado <> 'propuesta' then raise exception 'La novedad esta %.', n.estado; end if;
    if exists (select 1 from public.calendario_servicio c where c.contrato_id = n.contrato_id and c.fecha between n.fecha and coalesce(n.fecha_hasta, n.fecha)
                 and (c.contrato_sede_id is not distinct from n.contrato_sede_id)) then
      raise exception 'Ese dia ya tiene una marca en el calendario de servicio para ese alcance.';
    end if;
    for s in select cs.id from public.contrato_sedes cs where cs.contrato_id = n.contrato_id and cs.estado = 'activa' and (n.contrato_sede_id is null or cs.id = n.contrato_sede_id) loop
      if n.accion = 'trasladar' then
        select dc.dia into v_dia from public.dia_ciclo(s.id, n.fecha) dc;
        if v_dia is null then continue; end if;
        -- destino sin servicio (sabado, festivo, vacaciones): se habilita una jornada de reposicion
        if not public.es_dia_servicio(n.contrato_id, s.id, n.fecha_destino) then
          insert into public.calendario_servicio (empresa_id, contrato_id, contrato_sede_id, fecha, atiende, cuenta_ciclo, motivo, novedad_id)
          values (n.empresa_id, n.contrato_id, s.id, n.fecha_destino, true, false, 'Jornada de reposicion del menu del ' || to_char(n.fecha, 'DD/MM'), n.id)
          on conflict do nothing;
          v_avisos := array_append(v_avisos, 'Se habilito el ' || to_char(n.fecha_destino, 'DD/MM') || ' como jornada de reposicion.');
        else
          -- destino con menu propio: ese menu se desplaza (se pierde) y hay que decirlo explicitamente
          select dc.dia into v_dia_dest from public.dia_ciclo(s.id, n.fecha_destino) dc;
          if v_dia_dest is not null and not p_desplazar then
            raise exception 'El % ya tiene el menu %: si traslada, ese menu no se sirve. Confirme el desplazamiento.', to_char(n.fecha_destino, 'DD/MM'), v_dia_dest;
          end if;
          if v_dia_dest is not null then v_avisos := array_append(v_avisos, 'El menu ' || v_dia_dest || ' del ' || to_char(n.fecha_destino, 'DD/MM') || ' queda desplazado.'); end if;
        end if;
        insert into public.menu_excepciones (empresa_id, contrato_id, contrato_sede_id, fecha, tipo, dia_ciclo_forzado, motivo, soporte, aprobado, novedad_id)
        values (n.empresa_id, n.contrato_id, s.id, n.fecha_destino, 'dia_forzado', v_dia, 'Traslado del menu ' || v_dia || ' del ' || to_char(n.fecha, 'DD/MM') || ': ' || n.motivo, n.soporte, true, n.id);
      end if;
    end loop;
    d := n.fecha;
    while d <= coalesce(n.fecha_hasta, n.fecha) loop
      insert into public.calendario_servicio (empresa_id, contrato_id, contrato_sede_id, fecha, atiende, cuenta_ciclo, motivo, novedad_id)
      values (n.empresa_id, n.contrato_id, n.contrato_sede_id, d, false, n.accion <> 'correr', n.motivo, n.id);
      d := d + 1;
    end loop;
    update public.novedades_servicio set estado = 'aprobada', aprobado_por = auth.uid(), aprobado_en = now(),
           motivo = case when coalesce(trim(p_nota), '') <> '' then motivo || ' | ' || trim(p_nota) else motivo end where id = p_id;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (n.empresa_id, 'M8', 'urgente', 'Avisar a entidad e interventoria: sin servicio ' || to_char(n.fecha, 'DD/MM'),
            n.motivo || '. Registre el aviso cuando lo envie.', '/programacion?novedad=' || n.id, 'novedad_servicio', n.id);
  elsif p_decision = 'rechazar' then
    if n.estado <> 'propuesta' then raise exception 'La novedad esta %.', n.estado; end if;
    update public.novedades_servicio set estado = 'rechazada', motivo = case when coalesce(trim(p_nota), '') <> '' then motivo || ' | ' || trim(p_nota) else motivo end where id = p_id;
  elsif p_decision = 'anular' then
    if n.estado not in ('propuesta','aprobada') then raise exception 'La novedad esta %.', n.estado; end if;
    delete from public.calendario_servicio where novedad_id = p_id;
    delete from public.menu_excepciones where novedad_id = p_id;
    update public.novedades_servicio set estado = 'anulada' where id = p_id;
  else raise exception 'Decision no valida (aprobar, rechazar, anular)'; end if;
  return jsonb_build_object('estado', (select estado from public.novedades_servicio where id = p_id), 'avisos', to_jsonb(v_avisos));
end $$;
drop function if exists public.decidir_novedad_servicio(uuid, text, text);

create or replace function public.registrar_aviso_novedad(p_id uuid, p_a text) returns void language plpgsql security definer set search_path = public as $$
declare n public.novedades_servicio; v_mi uuid;
begin
  select * into n from public.novedades_servicio where id = p_id;
  if n.id is null then raise exception 'Novedad no encontrada'; end if;
  if n.estado <> 'aprobada' then raise exception 'Los avisos se registran sobre una novedad aprobada.'; end if;
  v_mi := public.mi_sede(n.empresa_id);
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(n.empresa_id, 'M8', 'crear') or public.tiene_permiso(n.empresa_id, 'M2', 'editar')
          or (public.tiene_permiso(n.empresa_id, 'M7', 'aprobar') and n.contrato_sede_id is not null
              and (v_mi is null or exists (select 1 from public.contrato_sedes cs where cs.id = n.contrato_sede_id and cs.sede_id = v_mi)))) then
    raise exception 'Sin permiso para registrar avisos.';
  end if;
  if p_a = 'entidad' then update public.novedades_servicio set aviso_entidad_en = now() where id = p_id;
  elsif p_a = 'interventoria' then update public.novedades_servicio set aviso_interventoria_en = now() where id = p_id;
  elsif p_a = 'aprobada_entidad' then update public.novedades_servicio set aprobada_entidad = true where id = p_id;
  else raise exception 'Indique entidad, interventoria o aprobada_entidad'; end if;
end $$;

-- ---------------------------------------------------------------------
-- A2. Amarre a sede en las lecturas: la membresia con sede define lo que se ve
-- ---------------------------------------------------------------------
create or replace function public.ve_sede(p_empresa uuid, p_contrato_sede uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.es_superadmin() or public.mi_sede(p_empresa) is null or p_contrato_sede is null
      or exists (select 1 from public.contrato_sedes cs where cs.id = p_contrato_sede and cs.sede_id = public.mi_sede(p_empresa));
$$;
grant execute on function public.ve_sede(uuid, uuid) to authenticated;
drop policy if exists novedades_servicio_ver on public.novedades_servicio;
create policy novedades_servicio_ver on public.novedades_servicio for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))
         and public.ve_sede(empresa_id, contrato_sede_id)));
drop policy if exists intercambios_menu_ver on public.intercambios_menu;
create policy intercambios_menu_ver on public.intercambios_menu for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))
         and public.ve_sede(empresa_id, contrato_sede_id)));

-- ---------------------------------------------------------------------
-- A2 + A3 + A4 + M5. Programacion: amarre a sede, indice en la temporal, tope de celdas, payload compacto,
--                     que paso con el menu en cada celda, y si el ciclo se corre
-- ---------------------------------------------------------------------
create or replace function public.programacion(p_contrato uuid, p_desde date, p_hasta date, p_sedes uuid[] default null, p_incluye_propuestos boolean default false)
returns jsonb language plpgsql security definer set search_path = public set jit = off set client_min_messages = warning as $$
declare v_emp uuid; v_mi_sede uuid; v_res jsonb; v_n_sedes int; v_dias int;
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
  if v_n_sedes * v_dias > 2100 then
    raise exception 'Demasiadas celdas (% sedes x % dias). Filtre sedes o muestre menos semanas.', v_n_sedes, v_dias;
  end if;

  create temp table if not exists tmp_prg_dias (sede_id uuid, fecha date, dia int, servicio boolean) on commit drop;
  truncate tmp_prg_dias;
  insert into tmp_prg_dias
  select s.id, g::date, dc.dia, public.es_dia_servicio(p_contrato, s.id, g::date)
    from tmp_prg_sedes s cross join generate_series(p_desde, p_hasta, interval '1 day') g
    left join lateral public.dia_ciclo(s.id, g::date) dc on true;
  create index if not exists tmp_prg_dias_idx on tmp_prg_dias (sede_id, fecha);

  create temp table if not exists tmp_prg_menu (sede_id uuid, fecha date, orden int, corden int, item jsonb) on commit drop;
  truncate tmp_prg_menu;
  insert into tmp_prg_menu
  select d.sede_id, d.fecha, m.tiempo_orden, c.orden,
         jsonb_build_object('tiempo', m.tiempo_codigo, 'componente_id', m.componente_id, 'componente', m.componente_codigo,
                            'preparacion_id', m.preparacion_id, 'preparacion', coalesce(m.preparacion_nombre, m.descriptor), 'origen', m.origen,
                            'intercambio_id', m.intercambio_id, 'clase', x.clase, 'estado', x.estado)
    from tmp_prg_dias d
    cross join lateral public.menu_del_dia(d.sede_id, d.fecha, p_incluye_propuestos) m
    left join public.componentes c on c.id = m.componente_id
    left join public.intercambios_menu x on x.id = m.intercambio_id
   where d.dia is not null;
  create index if not exists tmp_prg_menu_idx on tmp_prg_menu (sede_id, fecha);
  analyze tmp_prg_menu; analyze tmp_prg_dias;

  with dias as (
    select g::date as fecha, f.nombre as festivo from generate_series(p_desde, p_hasta, interval '1 day') g left join public.festivos f on f.fecha = g::date),
  menu as (
    select sede_id, fecha, jsonb_agg(item order by orden, corden, item->>'componente') as items from tmp_prg_menu group by 1, 2),
  cel as (
    select d.sede_id, d.fecha, d.servicio, d.dia, mn.items,
           (select jsonb_build_object('motivo', cs.motivo, 'novedad_id', cs.novedad_id, 'cuenta_ciclo', cs.cuenta_ciclo, 'reposicion', cs.atiende) from public.calendario_servicio cs
             where cs.contrato_id = p_contrato and cs.fecha = d.fecha and (cs.contrato_sede_id = d.sede_id or cs.contrato_sede_id is null)
             order by cs.contrato_sede_id nulls last limit 1) as calendario,
           (select jsonb_build_object('tipo', e.tipo, 'motivo', e.motivo, 'novedad_id', e.novedad_id, 'dia_forzado', e.dia_ciclo_forzado,
                                      'desde', (select n.fecha from public.novedades_servicio n where n.id = e.novedad_id))
              from public.menu_excepciones e
             where e.contrato_id = p_contrato and e.fecha = d.fecha and e.aprobado and e.tipo in ('festivo','especial','emergencia','dia_forzado')
               and (e.contrato_sede_id = d.sede_id or e.contrato_sede_id is null)
             order by e.contrato_sede_id nulls last, e.creado_en desc limit 1) as excepcion
      from tmp_prg_dias d left join menu mn on mn.sede_id = d.sede_id and mn.fecha = d.fecha)
  select jsonb_build_object(
    'contrato', (select jsonb_build_object('id', c.id, 'numero', c.numero, 'modalidad', c.modalidad, 'dias_atencion', c.dias_atencion,
                                           'se_corre', public.sede_ciclo_se_corre(c.id, null, p_desde)) from public.contratos c where c.id = p_contrato),
    'tiempos', (select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'orden', t.orden, 'id', t.id) order by t.orden) from public.tiempos_comida t where t.contrato_id = p_contrato),
    'componentes', (select jsonb_agg(jsonb_build_object('id', co.id, 'tiempo', t.codigo, 'codigo', co.codigo, 'nombre', co.nombre, 'orden', co.orden, 'familia_id', co.familia_id) order by t.orden, co.orden)
                      from public.componentes co join public.tiempos_comida t on t.id = co.tiempo_comida_id where co.contrato_id = p_contrato),
    'sedes', (select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'subtipo', subtipo, 'ciudad', ciudad, 'cupos', cupos) order by nombre) from tmp_prg_sedes),
    'total_sedes', (select count(*) from public.contrato_sedes cs where cs.contrato_id = p_contrato and cs.estado = 'activa'),
    'dias', (select jsonb_agg(jsonb_build_object('fecha', fecha, 'festivo', festivo) order by fecha) from dias),
    'celdas', (select jsonb_agg(jsonb_build_object('sede_id', sede_id, 'fecha', fecha, 'servicio', servicio, 'sin_servicio', case when not servicio then calendario end,
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

revoke execute on function public.decidir_novedad_servicio(uuid, text, text, boolean), public.sede_ciclo_se_corre(uuid, uuid, date) from public, anon;
grant execute on function public.decidir_novedad_servicio(uuid, text, text, boolean), public.sede_ciclo_se_corre(uuid, uuid, date) to authenticated;
