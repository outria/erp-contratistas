-- =====================================================================
-- Supply ERP · Migracion 011 · Parte 4C backend (03-nov-2026)
-- 1. Novedades de servicio (PAE: "manana no hay clases"): dia sin servicio con tres salidas para la materia prima ya comprada:
--    correr (el menu perdido pasa al siguiente dia de servicio y todo se corre), perder (el ciclo sigue y ese menu no se sirve)
--    o trasladar (ese menu se sirve en una fecha concreta, dentro de 2 o 3 dias o la semana siguiente, y lo demas no se mueve).
--    Flujo: la propone sede o planeacion, la aprueba la direccion de operaciones, se avisa a entidad e interventoria.
--    Guarda la foto de la materia prima del dia para saber que se corre.
-- 2. Programacion multisemana: una sola consulta devuelve la cuadricula sede x dia con menu, intercambios y novedades.
-- 3. Dietas con "tiempos adicionales": confirmado por la nutricionista que no existen; son reemplazos dentro de los tiempos.
--    Se desactiva la regla tiempo_adicional del catalogo.
-- 4. Empresas de practica: Demo USPEC, Demo PAE y Demo Casinos, con catalogo copiado de Diestra, sedes, cupos, ciclos y ejemplos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Novedades de servicio
-- ---------------------------------------------------------------------
alter table public.calendario_servicio add column cuenta_ciclo boolean not null default false;   -- no se sirve pero el ciclo avanza (menu perdido)
alter table public.calendario_servicio add column novedad_id uuid;
alter table public.menu_excepciones add column novedad_id uuid;

create table public.novedades_servicio (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_id        uuid not null references public.contratos(id),
  contrato_sede_id   uuid references public.contrato_sedes(id),      -- null = todas las sedes del contrato (paro departamental)
  fecha              date not null,
  fecha_hasta        date,                                            -- varios dias seguidos (null = solo fecha)
  tipo               text not null check (tipo in ('sin_clases','paro','acto_civico','actividad','clima','orden_publico','salud_publica','otro')),
  accion             text not null default 'correr' check (accion in ('correr','perder','trasladar')),
  fecha_destino      date,                                            -- trasladar: donde se sirve el menu perdido
  motivo             text not null,
  soporte            text,
  materia_prima      jsonb,                                           -- foto de lo que se necesitaba ese dia (productos y cantidades)
  estado             text not null default 'propuesta' check (estado in ('propuesta','aprobada','rechazada','anulada')),
  aviso_entidad_en   timestamptz,
  aviso_interventoria_en timestamptz,
  aprobada_entidad   boolean not null default false,
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now(),
  aprobado_por       uuid references auth.users(id),
  aprobado_en        timestamptz,
  actualizado_por    uuid references auth.users(id),
  actualizado_en     timestamptz not null default now(),
  check (fecha_hasta is null or fecha_hasta >= fecha),
  check (accion <> 'trasladar' or fecha_destino is not null)
);
create index novedades_servicio_idx on public.novedades_servicio (contrato_id, fecha);
alter table public.calendario_servicio add constraint calendario_servicio_novedad_fk foreign key (novedad_id) references public.novedades_servicio(id) on delete cascade;
alter table public.menu_excepciones add constraint menu_excepciones_novedad_fk foreign key (novedad_id) references public.novedades_servicio(id) on delete cascade;

alter table public.novedades_servicio enable row level security;
create policy novedades_servicio_ver on public.novedades_servicio for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))));
create policy novedades_servicio_crear on public.novedades_servicio for insert to authenticated
  with check (public.es_superadmin() or (estado = 'propuesta' and (public.tiene_permiso(empresa_id, 'M2', 'crear')
    or (public.tiene_permiso(empresa_id, 'M7', 'crear') and contrato_sede_id is not null
        and (public.mi_sede(empresa_id) is null or exists (select 1 from public.contrato_sedes cs where cs.id = contrato_sede_id and cs.sede_id = public.mi_sede(empresa_id)))))));
create policy novedades_servicio_editar on public.novedades_servicio for update to authenticated
  using (public.es_superadmin() or (estado = 'propuesta' and (public.tiene_permiso(empresa_id, 'M2', 'editar') or creado_por = auth.uid())))
  with check (public.es_superadmin() or estado = 'propuesta');
grant select, insert, update on public.novedades_servicio to authenticated;
create trigger novedades_servicio_actualizacion before update on public.novedades_servicio for each row execute function public.marcar_actualizacion();
create trigger novedades_servicio_bitacora after insert or update or delete on public.novedades_servicio for each row execute function public.registrar_bitacora();
create trigger novedades_servicio_empresa_coherente before insert or update on public.novedades_servicio for each row execute function public.validar_empresa_coherente();

-- materia prima que pedia un dia en una sede (o todo el contrato): la foto que se guarda en la novedad
create or replace function public.materia_prima_dia(p_contrato uuid, p_fecha date, p_contrato_sede uuid default null, p_fecha_hasta date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid; v_res jsonb;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver')) then
    raise exception 'Sin permiso';
  end if;
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
  return v_res;
end $$;

-- al proponer una novedad se guarda la foto de la materia prima del dia (si el contrato ya tiene explosion posible)
create or replace function public.foto_materia_prima_novedad() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.materia_prima is null then
    begin
      new.materia_prima := public.materia_prima_dia(new.contrato_id, new.fecha, new.contrato_sede_id, new.fecha_hasta);
    exception when others then new.materia_prima := jsonb_build_object('error', sqlerrm); end;
  end if;
  return new;
end $$;
create trigger novedades_servicio_foto before insert on public.novedades_servicio for each row execute function public.foto_materia_prima_novedad();

-- aviso interno al proponer (operaciones y planeacion deben reaccionar rapido)
create or replace function public.avisar_novedad() returns trigger language plpgsql security definer set search_path = public as $$
declare v_sede text;
begin
  select s.nombre into v_sede from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.id = new.contrato_sede_id;
  v_sede := coalesce(v_sede, 'todas las sedes');
  insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
  values (new.empresa_id, 'M7', case when new.fecha <= (now() at time zone 'America/Bogota')::date + 1 then 'urgente' else 'alta' end,
          'Sin servicio ' || to_char(new.fecha, 'DD/MM') || case when new.fecha_hasta is not null then ' al ' || to_char(new.fecha_hasta, 'DD/MM') else '' end || ' · ' || v_sede,
          new.motivo || '. Accion propuesta: ' || case new.accion when 'correr' then 'correr el menu' when 'perder' then 'el menu se pierde' else 'trasladar el menu al ' || to_char(new.fecha_destino, 'DD/MM') end
          || '. Requiere aprobacion de la direccion de operaciones y aviso a entidad e interventoria.',
          '/programacion?novedad=' || new.id, 'novedad_servicio', new.id);
  insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
  values (new.empresa_id, 'M2', 'alta', 'Novedad de servicio propuesta · ' || v_sede, new.motivo, '/programacion?novedad=' || new.id, 'novedad_servicio', new.id);
  return new;
end $$;
create trigger novedades_servicio_avisar after insert on public.novedades_servicio for each row execute function public.avisar_novedad();

-- aprobar aplica la novedad al calendario (y el traslado al menu); anular la deshace
create or replace function public.decidir_novedad_servicio(p_id uuid, p_decision text, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare n public.novedades_servicio; s record; d date; v_dia int; v_ciclo uuid;
begin
  select * into n from public.novedades_servicio where id = p_id for update;
  if n.id is null then raise exception 'Novedad no encontrada'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(n.empresa_id, 'M7', 'aprobar') or public.tiene_permiso(n.empresa_id, 'M2', 'aprobar')
          or (p_decision = 'anular' and n.creado_por = auth.uid() and n.estado = 'propuesta')) then
    raise exception 'Sin permiso (Operacion en sede o Planeacion: aprobar).';
  end if;
  if p_decision = 'aprobar' then
    if n.estado <> 'propuesta' then raise exception 'La novedad esta %.', n.estado; end if;
    for s in select cs.id from public.contrato_sedes cs where cs.contrato_id = n.contrato_id and cs.estado = 'activa' and (n.contrato_sede_id is null or cs.id = n.contrato_sede_id) loop
      -- traslado: el dia de ciclo que tocaba en la fecha perdida se fuerza en la fecha destino (antes de marcar el dia sin servicio)
      if n.accion = 'trasladar' then
        select dc.dia, dc.ciclo_id into v_dia, v_ciclo from public.dia_ciclo(s.id, n.fecha) dc;
        if v_dia is not null then
          insert into public.menu_excepciones (empresa_id, contrato_id, contrato_sede_id, fecha, tipo, dia_ciclo_forzado, motivo, soporte, aprobado, novedad_id)
          values (n.empresa_id, n.contrato_id, s.id, n.fecha_destino, 'dia_forzado', v_dia, 'Traslado del menu del ' || to_char(n.fecha, 'DD/MM') || ': ' || n.motivo, n.soporte, true, n.id);
        end if;
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
    delete from public.calendario_servicio where novedad_id = p_id;
    delete from public.menu_excepciones where novedad_id = p_id;
    update public.novedades_servicio set estado = 'anulada' where id = p_id;
  else raise exception 'Decision no valida (aprobar, rechazar, anular)'; end if;
end $$;

create or replace function public.registrar_aviso_novedad(p_id uuid, p_a text) returns void language plpgsql security definer set search_path = public as $$
declare n public.novedades_servicio;
begin
  select * into n from public.novedades_servicio where id = p_id;
  if n.id is null then raise exception 'Novedad no encontrada'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(n.empresa_id, 'M8', 'crear') or public.tiene_permiso(n.empresa_id, 'M7', 'aprobar') or public.tiene_permiso(n.empresa_id, 'M2', 'editar')) then
    raise exception 'Sin permiso para registrar avisos.';
  end if;
  if p_a = 'entidad' then update public.novedades_servicio set aviso_entidad_en = now() where id = p_id;
  elsif p_a = 'interventoria' then update public.novedades_servicio set aviso_interventoria_en = now() where id = p_id;
  elsif p_a = 'aprobada_entidad' then update public.novedades_servicio set aprobada_entidad = true where id = p_id;
  else raise exception 'Indique entidad, interventoria o aprobada_entidad'; end if;
end $$;

-- dia_ciclo: un dia sin servicio con cuenta_ciclo = true si avanza el ciclo (menu perdido o trasladado)
create or replace function public.dia_ciclo(p_contrato_sede uuid, p_fecha date)
returns table (ciclo_id uuid, dia int, variante_id uuid) language plpgsql stable set search_path = public as $$
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
     where coalesce(x.atiende or x.cuenta_ciclo, case when v_dias = 'todos' then true else public.es_dia_habil(g::date) end);
  end if;
  return query select sc.ciclo_id, (v_pos % v_n) + 1, sc.variante_id;
end $$;

-- ---------------------------------------------------------------------
-- 2. Programacion multisemana (una llamada por rango)
-- ---------------------------------------------------------------------
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
                            'intercambio_id', m.intercambio_id, 'clase', x.clase, 'estado', x.estado)
    from tmp_prg_sedes s cross join generate_series(p_desde, p_hasta, interval '1 day') g
    cross join lateral public.menu_del_dia(s.id, g::date, p_incluye_propuestos) m
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
           (select jsonb_agg(m.item order by (m.item->>'orden')::int, m.item->>'componente') from tmp_prg_menu m where m.sede_id = s.id and m.fecha = d.fecha) as items
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

revoke execute on function public.materia_prima_dia(uuid, date, uuid, date), public.decidir_novedad_servicio(uuid, text, text), public.registrar_aviso_novedad(uuid, text),
  public.programacion(uuid, date, date, uuid[], boolean) from public, anon;
grant execute on function public.materia_prima_dia(uuid, date, uuid, date), public.decidir_novedad_servicio(uuid, text, text), public.registrar_aviso_novedad(uuid, text),
  public.programacion(uuid, date, date, uuid[], boolean) to authenticated;

-- El planificador asume 1.000 filas por cada funcion de tabla y dispara el JIT (casi un segundo de compilacion por llamada).
-- Se le dicen los tamanos reales y se apaga el JIT en las funciones pesadas.
alter function public.dia_ciclo(uuid, date) rows 1;
alter function public.menu_del_dia(uuid, date, boolean) rows 30;
alter function public.poblacion_dia(uuid, date) rows 4;
alter function public.crudo_ingrediente(uuid, uuid, date, uuid, uuid, uuid, uuid, numeric) rows 1;
alter function public.sustitucion_ingrediente(uuid, date, int, uuid, uuid, uuid, boolean) rows 1;
alter function public.calcular_explosion(uuid, date, date, uuid[]) set jit = off;
alter function public.sugerir_intercambios(uuid, date, uuid, uuid) set jit = off;
alter function public.alertas_explosion(uuid) set jit = off;
alter function public.resumen_proyeccion_consolidada(uuid) set jit = off;

-- ---------------------------------------------------------------------
-- 3. Dietas: no hay tiempos adicionales (nutricionista, 03-nov-2026); son reemplazos dentro de los tiempos
-- ---------------------------------------------------------------------
update public.reglas_dieta set activa = false, nota = coalesce(nota, '') || ' · Desactivada 03-nov-2026: no son tiempos extra sino reemplazos dentro de los tiempos' where tipo_regla = 'tiempo_adicional';
update public.tipos_dieta set tiempos_adicionales = 0 where tiempos_adicionales > 0;

-- ---------------------------------------------------------------------
-- 4. Empresas de practica
-- ---------------------------------------------------------------------
-- copia productos, factores y recetas (con el crudo del grupo H o el generico) de una empresa a otra
create or replace function public.copiar_catalogo(p_origen uuid, p_destino uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare n_p int; n_r int; n_i int; v_h uuid;
begin
  if not (public.es_admin_sql() or public.es_superadmin()) then raise exception 'Solo el administrador de la plataforma copia catalogos.'; end if;
  insert into public.productos (empresa_id, codigo, nombre, categoria, unidad_base, unidad_compra, factor_compra, codigo_tcac, nivel_riesgo, prohibido, restringido, rendimiento, merma_pct, perecedero, dias_vida_util)
  select p_destino, codigo, nombre, categoria, unidad_base, unidad_compra, factor_compra, codigo_tcac, nivel_riesgo, prohibido, restringido, rendimiento, merma_pct, perecedero, dias_vida_util
    from public.productos o where o.empresa_id = p_origen and o.estado = 'activo'
  on conflict (empresa_id, codigo) do nothing;
  get diagnostics n_p = row_count;
  insert into public.factores_coccion (empresa_id, producto_id, metodo, factor, fuente)
  select p_destino, d.id, f.metodo, f.factor, f.fuente
    from public.factores_coccion f join public.productos o on o.id = f.producto_id join public.productos d on d.empresa_id = p_destino and d.codigo = o.codigo
   where f.empresa_id = p_origen
  on conflict do nothing;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, metodo_coccion, procedimiento, restringida, rendimiento_porciones)
  select p_destino, null, codigo, nombre, componente_codigo, metodo_coccion, procedimiento, restringida, rendimiento_porciones
    from public.preparaciones o where o.empresa_id = p_origen and o.estado = 'activa'
  on conflict do nothing;
  get diagnostics n_r = row_count;
  select g.id into v_h from public.grupos_poblacion g join public.contratos c on c.id = g.contrato_id where c.empresa_id = p_origen and g.codigo = 'H' limit 1;
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, opcional, orden)
  select distinct on (dp.id, dprod.id) p_destino, dp.id, dprod.id, null, i.peso_bruto, i.es_principal, i.opcional, i.orden
    from public.preparacion_ingredientes i
    join public.preparaciones op on op.id = i.preparacion_id and op.empresa_id = p_origen
    join public.preparaciones dp on dp.empresa_id = p_destino and dp.codigo = op.codigo and dp.contrato_id is null
    join public.productos oprod on oprod.id = i.producto_id
    join public.productos dprod on dprod.empresa_id = p_destino and dprod.codigo = oprod.codigo
   where i.grupo_poblacion_id is null or i.grupo_poblacion_id = v_h
   order by dp.id, dprod.id, (i.grupo_poblacion_id is null)
  on conflict do nothing;
  get diagnostics n_i = row_count;
  return jsonb_build_object('productos', n_p, 'recetas', n_r, 'ingredientes', n_i);
end $$;

-- arma una empresa de practica completa para una modalidad
create or replace function public.crear_empresa_demo(p_modalidad text, p_origen_catalogo uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_ct uuid; v_ent uuid; v_origen uuid; v_nit text; v_nombre text; v_corto text; v_ciudad text; v_entidad text; v_tipo_ent text;
        v_ini date := date_trunc('month', (now() at time zone 'America/Bogota')::date)::date - interval '2 months';
        v_n int; t record; co record; s record; v_ciclo uuid; v_dia int; v_prep uuid; v_k int; v_sede uuid; v_cs uuid; g record; v_est uuid; v_cupo int;
        v_fam uuid; v_opts uuid[]; v_i int; v_tc uuid;
begin
  if not (public.es_admin_sql() or public.es_superadmin()) then raise exception 'Solo el administrador de la plataforma crea empresas de practica.'; end if;
  v_origen := coalesce(p_origen_catalogo, (select id from public.empresas where nit = '901942965'));
  if p_modalidad = 'uspec_ppl' then v_nit := '900000001'; v_nombre := 'Demo USPEC (practica)'; v_corto := 'Demo USPEC'; v_ciudad := 'Bogota'; v_entidad := 'USPEC (practica)'; v_tipo_ent := 'uspec';
  elsif p_modalidad = 'pae' then v_nit := '900000002'; v_nombre := 'Demo PAE (practica)'; v_corto := 'Demo PAE'; v_ciudad := 'Barranquilla'; v_entidad := 'Gobernacion (practica)'; v_tipo_ent := 'gobernacion';
  elsif p_modalidad = 'fuerzas_casino' then v_nit := '900000003'; v_nombre := 'Demo Casinos (practica)'; v_corto := 'Demo Casinos'; v_ciudad := 'Cartagena'; v_entidad := 'Fuerzas Militares (practica)'; v_tipo_ent := 'fuerzas';
  else raise exception 'Modalidad de practica no soportada: %', p_modalidad; end if;

  select id into v_emp from public.empresas where nit = v_nit;
  if v_emp is null then
    v_emp := public.alta_empresa(v_nombre, v_nit, '1', v_ciudad, v_corto, 'otro', null, 'CEDI de practica', '{}'::jsonb);
  else
    update public.empresas set razon_social = v_nombre, nombre_corto = v_corto where id = v_emp;
  end if;
  perform public.copiar_catalogo(v_origen, v_emp);

  select id into v_ent from public.entidades_contratantes where empresa_id = v_emp limit 1;
  if v_ent is null then insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad) values (v_emp, v_entidad, v_tipo_ent, v_ciudad) returning id into v_ent; end if;
  select id into v_ct from public.contratos where empresa_id = v_emp limit 1;
  if v_ct is null then
    v_ct := public.crear_contrato(jsonb_build_object('empresa_id', v_emp, 'numero', 'DEMO-' || upper(p_modalidad) || '-2026', 'entidad_id', v_ent, 'modalidad', p_modalidad,
      'objeto', 'Contrato de practica para capacitacion: ' || v_nombre, 'valor_inicial', 5000000000, 'incluye_iva', true,
      'fecha_suscripcion', v_ini - 15, 'fecha_inicio', v_ini, 'fecha_fin_inicial', v_ini + interval '12 months', 'estado', 'vigente',
      'notas', 'Datos de practica. Lo que se registre aqui no cuenta en la operacion real.'));
  end if;
  perform public.aplicar_plantilla_modalidad(v_ct);
  perform public.crear_ventana_inicial(v_ct);

  -- sedes y cupos
  if not exists (select 1 from public.contrato_sedes where contrato_id = v_ct) then
    for s in select * from (values
        ('uspec_ppl', 'EPMSC Practica Norte', 'eron', 'Bogota', 1200, 'ESTANDAR'), ('uspec_ppl', 'EPMSC Practica Sur', 'eron', 'Bogota', 480, 'ESTANDAR'), ('uspec_ppl', 'Estacion de Policia Practica', 'estacion', 'Bogota', 60, 'EP'),
        ('pae', 'IE Tecnica de Practica', 'colegio', 'Soledad', 900, 'ESTANDAR'), ('pae', 'IE Rural de Practica', 'colegio', 'Baranoa', 350, 'ESTANDAR'), ('pae', 'IE Normal de Practica', 'colegio', 'Sabanalarga', 650, 'ESTANDAR'), ('pae', 'Megacolegio de Practica', 'colegio', 'Barranquilla', 1500, 'ESTANDAR'),
        ('fuerzas_casino', 'Casino de Cadetes Practica', 'casino', 'Cartagena', 420, 'ESTANDAR'), ('fuerzas_casino', 'Casino de Oficiales Practica', 'casino', 'Cartagena', 150, 'ESTANDAR')
      ) x(mod, nombre, subtipo, ciudad, cupos, variante) where x.mod = p_modalidad loop
      insert into public.sedes (empresa_id, nombre, tipo, subtipo, ciudad) values (v_emp, s.nombre, 'unidad_servicio', s.subtipo, s.ciudad) returning id into v_sede;
      insert into public.contrato_sedes (empresa_id, contrato_id, sede_id, cupos_referencia, fecha_inicio) values (v_emp, v_ct, v_sede, s.cupos, v_ini) returning id into v_cs;
      -- cupos por grupo (y por tiempo en PAE: cada estudiante recibe un solo tiempo)
      if p_modalidad = 'pae' then
        for t in select id, codigo from public.tiempos_comida where contrato_id = v_ct loop
          for g in select id, codigo, orden from public.grupos_poblacion where contrato_id = v_ct loop
            v_cupo := round(s.cupos * case t.codigo when 'RPS' then 0.5 when 'CAM' then 0.25 when 'CPM' then 0.15 else 0.10 end * case g.orden when 1 then 0.4 when 2 then 0.4 else 0.2 end);
            if v_cupo > 0 then
              insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, tiempo_comida_id, fecha_desde, cantidad, fuente) values (v_emp, v_cs, g.id, t.id, v_ini, v_cupo, 'focalizacion de practica');
            end if;
          end loop;
        end loop;
      else
        for g in select id, codigo, orden from public.grupos_poblacion where contrato_id = v_ct loop
          v_cupo := case when p_modalidad = 'uspec_ppl' then round(s.cupos * case g.codigo when 'H' then 0.92 else 0.08 end) else s.cupos end;
          insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, variante_id, fecha_desde, cantidad, fuente)
          values (v_emp, v_cs, g.id, (select id from public.variantes_racion where contrato_id = v_ct and codigo = s.variante), v_ini, v_cupo, 'parte de practica');
        end loop;
      end if;
    end loop;
  end if;

  -- familias: opciones desde el catalogo copiado (+ equivalencias para familias que el Anexo 4 no trae)
  perform public.sembrar_familias_contrato(v_ct);
  insert into public.familia_opciones (empresa_id, familia_id, preparacion_id, subfamilia, origen)
  select v_emp, f.id, p.id, trim(split_part(coalesce((select pr.nombre from public.preparacion_ingredientes pi join public.productos pr on pr.id = pi.producto_id where pi.preparacion_id = p.id and pi.es_principal limit 1), p.nombre), ',', 1)), 'plantilla'
    from public.familias_intercambio f
    join public.preparaciones p on p.empresa_id = v_emp and p.contrato_id is null and p.estado = 'activa'
     and ((f.codigo = 'LACTEO' and (p.componente_codigo = 'BEBIDA_DES' or p.codigo in ('BEBIDA_KUMIS','BEBIDA_YOGURT','BEBIDA_LECHE_DE_VACA','BEBIDA_BEBIDA_CON_LECHE_Y_AVENA')))
       or (f.codigo = 'LEGUMINOSA' and p.componente_codigo = 'SOPA' and (p.nombre ilike '%lenteja%' or p.nombre ilike '%frijol%' or p.nombre ilike '%fríjol%' or p.nombre ilike '%guandul%' or p.nombre ilike '%garbanzo%'))
       or (f.codigo = 'ACOMPANANTE' and p.componente_codigo = 'SOPA'))
   where f.contrato_id = v_ct
  on conflict do nothing;

  -- ciclo de menus: por cada dia, tiempo y componente una opcion de la familia (rotando para no repetir)
  if not exists (select 1 from public.ciclos_menu where contrato_id = v_ct) then
    select coalesce(n_menus_ciclo, 15) into v_n from public.contratos where id = v_ct;
    insert into public.ciclos_menu (empresa_id, contrato_id, codigo, nombre, n_menus) values (v_emp, v_ct, 'CICLO_DEMO', 'Ciclo de practica (' || v_n || ' menus)', v_n) returning id into v_ciclo;
    for co in select c.id, c.codigo, c.familia_id, c.tiempo_comida_id, tc.codigo as tcod, row_number() over (order by tc.orden, c.orden) as k
                from public.componentes c join public.tiempos_comida tc on tc.id = c.tiempo_comida_id where c.contrato_id = v_ct loop
      select array_agg(o.preparacion_id order by p.nombre) into v_opts
        from public.familia_opciones o join public.preparaciones p on p.id = o.preparacion_id
       where o.familia_id = co.familia_id and o.estado = 'vigente'
         and (co.codigo <> 'CEREAL' or co.tcod in ('DES','REF','CAM','CPM','RI','RAM','RPM') or p.componente_codigo = 'CEREAL');
      if v_opts is null then continue; end if;
      for v_dia in 1..v_n loop
        -- salto distinto por componente para que las combinaciones no se repitan igual cada dia
        v_i := ((v_dia - 1) * (1 + (co.k % 3)) + co.k) % array_length(v_opts, 1) + 1;
        insert into public.ciclo_menu_items (empresa_id, ciclo_id, dia, tiempo_comida_id, componente_id, preparacion_id)
        values (v_emp, v_ciclo, v_dia, co.tiempo_comida_id, co.id, v_opts[v_i]) on conflict do nothing;
      end loop;
    end loop;
    update public.familia_opciones o set en_minuta = true, origen = 'minuta'
      where o.empresa_id = v_emp and exists (select 1 from public.ciclo_menu_items i where i.ciclo_id = v_ciclo and i.preparacion_id = o.preparacion_id);
    for s in select cs.id, (select codigo from public.variantes_racion where contrato_id = v_ct and codigo = (select case when se.subtipo = 'estacion' then 'EP' else 'ESTANDAR' end)) as var, se.subtipo
               from public.contrato_sedes cs join public.sedes se on se.id = cs.sede_id where cs.contrato_id = v_ct loop
      insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, menu_confirmado)
      values (v_emp, s.id, v_ciclo, (select id from public.variantes_racion where contrato_id = v_ct and codigo = coalesce(s.var, 'ESTANDAR')), v_ini, 'continuo',
              (select coalesce((pl.esquema->>'avanza_sin_servicio')::boolean, true) from public.plantillas_modalidad pl where pl.codigo = p_modalidad), v_ini, true);
    end loop;
  end if;

  -- muestras para la pantalla: dietas en USPEC, vacaciones y una novedad en PAE
  if p_modalidad = 'uspec_ppl' and not exists (select 1 from public.dietas_poblacion dp join public.contrato_sedes cs on cs.id = dp.contrato_sede_id where cs.contrato_id = v_ct) then
    insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, cantidad, fuente)
    select v_emp, cs.id, td.id, (select id from public.grupos_poblacion where contrato_id = v_ct and codigo = 'H'), v_ini, case td.codigo when 'HIPERCAL_HIPERPROT' then 40 when 'BLANDA' then 15 else 10 end, 'BD de dietas de practica'
      from public.contrato_sedes cs cross join (select id, codigo from public.tipos_dieta where empresa_id is null and codigo in ('HIPERCAL_HIPERPROT','BLANDA','HIPOSODICA')) td
     where cs.contrato_id = v_ct and cs.cupos_referencia > 100;
  end if;
  if p_modalidad = 'pae' and not exists (select 1 from public.calendario_servicio where contrato_id = v_ct) then
    -- receso escolar de una semana en octubre y vacaciones de fin de ano
    insert into public.calendario_servicio (empresa_id, contrato_id, fecha, atiende, motivo)
    select v_emp, v_ct, gs.d::date, false, 'Receso escolar' from generate_series(make_date(extract(year from v_ini)::int, 10, 6), make_date(extract(year from v_ini)::int, 10, 10), interval '1 day') gs(d)
     where gs.d::date >= v_ini
    union all
    select v_emp, v_ct, gs.d::date, false, 'Vacaciones de fin de ano' from generate_series(make_date(extract(year from v_ini)::int, 12, 1), make_date(extract(year from v_ini)::int, 12, 31), interval '1 day') gs(d)
     where extract(isodow from gs.d) between 1 and 5;
  end if;
  return jsonb_build_object('empresa_id', v_emp, 'contrato_id', v_ct, 'nombre', v_nombre);
end $$;

revoke execute on function public.copiar_catalogo(uuid, uuid), public.crear_empresa_demo(text, uuid) from public, anon;
grant execute on function public.copiar_catalogo(uuid, uuid), public.crear_empresa_demo(text, uuid) to authenticated;

select public.crear_empresa_demo('uspec_ppl');
select public.crear_empresa_demo('pae');
select public.crear_empresa_demo('fuerzas_casino');
