-- =====================================================================
-- Supply ERP · Migracion 010 · Correcciones de la auditoria de M2 (02-nov-2026)
-- Criticos: C1 lectura/escritura cruzada entre empresas; C2 atajo auth.uid() is null explotable por anon.
-- Altos: A1 parte parcial borra grupos; A2 cupos por tiempo de comida (PAE); A3 dietas (exceso, reglas de otra empresa,
--        prioridad contrato > empresa > catalogo, anular reglas del catalogo); A4 intercambios (ventana, clase, sede del
--        usuario, orden de estados); A5 consolidada calculada a medias; A6 festivos en dias de servicio y festivos
--        generados por ley; A7 rendimiento de la explosion.
-- Medios: M1 bloqueo al recalcular; M3 mapeo maestro de otro grupo/unidad y sugeridos sumados; M5 fechas en hora de Bogota.
-- =====================================================================

-- ---------------------------------------------------------------------
-- C2. Quien es "administrador SQL": solo una sesion que NO entra por la API (editor SQL, migraciones) o el service_role.
--     En PostgREST la sesion siempre es "authenticator", asi que anon y authenticated nunca pasan por el atajo.
-- ---------------------------------------------------------------------
create or replace function public.es_admin_sql() returns boolean language sql stable as $$
  select session_user::text <> 'authenticator'
      or coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '') = 'service_role';
$$;

-- ---------------------------------------------------------------------
-- A6. Festivos de Colombia generados por ley (Ley 51 de 1983 "Emiliani" + Semana Santa por la fecha de Pascua)
-- ---------------------------------------------------------------------
create or replace function public.pascua(p_anio int) returns date language plpgsql immutable as $$
declare a int; b int; c int; d int; e int; f int; g int; h int; i int; k int; l int; m int; mes int; dia int;
begin
  a := p_anio % 19; b := p_anio / 100; c := p_anio % 100; d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
  h := (19 * a + b - d - g + 15) % 30; i := c / 4; k := c % 4; l := (32 + 2 * e + 2 * i - h - k) % 7; m := (a + 11 * h + 22 * l) / 451;
  mes := (h + l - 7 * m + 114) / 31; dia := ((h + l - 7 * m + 114) % 31) + 1;
  return make_date(p_anio, mes, dia);
end $$;

create or replace function public.lunes_siguiente(p date) returns date language sql immutable as $$
  select p + ((8 - extract(isodow from p)::int) % 7);
$$;

create or replace function public.generar_festivos_colombia(p_anio int) returns int language plpgsql as $$
declare pa date := public.pascua(p_anio); n int;
begin
  insert into public.festivos (fecha, nombre)
  select x.f, x.n from (values
    (make_date(p_anio, 1, 1), 'Año nuevo'),
    (public.lunes_siguiente(make_date(p_anio, 1, 6)), 'Reyes magos'),
    (public.lunes_siguiente(make_date(p_anio, 3, 19)), 'San Jose'),
    (pa - 3, 'Jueves santo'),
    (pa - 2, 'Viernes santo'),
    (make_date(p_anio, 5, 1), 'Dia del trabajo'),
    (public.lunes_siguiente(pa + 39), 'Ascension'),
    (public.lunes_siguiente(pa + 60), 'Corpus Christi'),
    (public.lunes_siguiente(pa + 68), 'Sagrado Corazon'),
    (public.lunes_siguiente(make_date(p_anio, 6, 29)), 'San Pedro y San Pablo'),
    (make_date(p_anio, 7, 20), 'Independencia'),
    (make_date(p_anio, 8, 7), 'Batalla de Boyaca'),
    (public.lunes_siguiente(make_date(p_anio, 8, 15)), 'Asuncion'),
    (public.lunes_siguiente(make_date(p_anio, 10, 12)), 'Dia de la raza'),
    (public.lunes_siguiente(make_date(p_anio, 11, 1)), 'Todos los santos'),
    (public.lunes_siguiente(make_date(p_anio, 11, 11)), 'Independencia de Cartagena'),
    (make_date(p_anio, 12, 8), 'Inmaculada Concepcion'),
    (make_date(p_anio, 12, 25), 'Navidad')) x(f, n)
  on conflict (fecha) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
select public.generar_festivos_colombia(a) from generate_series(2024, 2035) a;

-- dia de servicio: habiles y calendario propio excluyen fines de semana y festivos; calendario_servicio manda sobre todo
create or replace function public.es_dia_servicio(p_contrato uuid, p_contrato_sede uuid, p_fecha date)
returns boolean language plpgsql stable set search_path = public as $$
declare v_dias text; v_exc boolean;
begin
  select atiende into v_exc from public.calendario_servicio
   where contrato_id = p_contrato and fecha = p_fecha and (contrato_sede_id = p_contrato_sede or contrato_sede_id is null)
   order by contrato_sede_id nulls last limit 1;
  if found then return v_exc; end if;
  select dias_atencion into v_dias from public.contratos where id = p_contrato;
  if v_dias = 'todos' then return true; end if;
  return public.es_dia_habil(p_fecha);   -- habiles y calendario_propio (PAE: dias de clase se marcan en calendario_servicio)
end $$;

create or replace function public.dia_ciclo(p_contrato_sede uuid, p_fecha date)
returns table (ciclo_id uuid, dia int, variante_id uuid) language plpgsql stable set search_path = public as $$
declare sc record; v_contrato uuid; v_dias text; v_n int; v_pos int; v_ancla date; v_exc record;
begin
  select cs.contrato_id into v_contrato from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if v_contrato is null or not public.es_dia_servicio(v_contrato, p_contrato_sede, p_fecha) then return; end if;
  select * into v_exc from public.menu_excepciones e
   where e.contrato_id = v_contrato and e.fecha = p_fecha and (e.contrato_sede_id = p_contrato_sede or e.contrato_sede_id is null)
     and e.tipo in ('festivo','especial','emergencia','dia_forzado') and e.aprobado
   order by e.contrato_sede_id nulls last limit 1;
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
      left join lateral (select cs.atiende from public.calendario_servicio cs where cs.contrato_id = v_contrato and cs.fecha = g::date
                            and (cs.contrato_sede_id = p_contrato_sede or cs.contrato_sede_id is null) order by cs.contrato_sede_id nulls last limit 1) x on true
     where coalesce(x.atiende, case when v_dias = 'todos' then true else public.es_dia_habil(g::date) end);
  end if;
  return query select sc.ciclo_id, (v_pos % v_n) + 1, sc.variante_id;
end $$;

-- ---------------------------------------------------------------------
-- C1 (a). Las funciones de lectura pasan a SECURITY INVOKER: llamadas por un usuario respetan el RLS de su empresa;
--         llamadas desde una funcion definer (explosion, sugerencias) leen todo lo que esa funcion ya autorizo.
-- ---------------------------------------------------------------------
alter function public.menu_del_dia(uuid, date, boolean) security invoker;
alter function public.en_ventana_ajuste(uuid, date) security invoker;
alter function public.sustitucion_ingrediente(uuid, date, int, uuid, uuid, uuid, boolean) security invoker;
alter function public.alertas_explosion(uuid) security invoker;

-- A1 + A2. Poblacion por grupo, variante y tiempo de comida: el parte gana al cupo en su mismo grupo/variante/tiempo
-- (no borra los demas grupos). tiempo null = todos los tiempos. La dieta se resta de la fila "todos los tiempos" y nunca
-- supera la poblacion.
drop function if exists public.poblacion_dia(uuid, date);
create function public.poblacion_dia(p_contrato_sede uuid, p_fecha date)
returns table (grupo_poblacion_id uuid, variante_id uuid, tiempo_comida_id uuid, total int, en_dieta int, linea int)
language sql stable as $$
  with p as (
    select pd.grupo_poblacion_id, pd.variante_id, pd.tiempo_comida_id, sum(pd.cantidad)::int as total
      from public.partes_diarios pd
     where pd.contrato_sede_id = p_contrato_sede and pd.fecha = p_fecha
     group by 1, 2, 3
  ), c as (
    select cu.grupo_poblacion_id, cu.variante_id, cu.tiempo_comida_id, sum(cu.cantidad)::int as total
      from public.cupos cu
     where cu.contrato_sede_id = p_contrato_sede and cu.fecha_desde <= p_fecha and (cu.fecha_hasta is null or cu.fecha_hasta >= p_fecha)
     group by 1, 2, 3
  ), base as (
    select * from p
    union all
    select * from c where not exists (select 1 from p where p.grupo_poblacion_id = c.grupo_poblacion_id
                                        and p.variante_id is not distinct from c.variante_id and p.tiempo_comida_id is not distinct from c.tiempo_comida_id)
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

-- A7. crudo efectivo en SQL puro (se integra en la consulta de la explosion en vez de llamarse 100.000 veces)
drop function if exists public.crudo_ingrediente(uuid, uuid, date, uuid, uuid, uuid, uuid, numeric);
create function public.crudo_ingrediente(
  p_contrato uuid, p_contrato_sede uuid, p_fecha date, p_preparacion uuid, p_producto uuid, p_grupo uuid, p_componente uuid, p_peso_bruto numeric
) returns table (crudo numeric, nota text) language sql stable as $$
  select coalesce(
           case when a.id is null then null
                when a.peso_bruto is not null then a.peso_bruto
                when a.factor_crudo is not null then p_peso_bruto * a.factor_crudo
                when a.porcion_servida is not null then a.porcion_servida / coalesce(
                     (select f.factor from public.factores_coccion f join public.preparaciones pp on pp.id = p_preparacion where f.producto_id = p_producto and f.metodo = pp.metodo_coccion limit 1),
                     (select pr.rendimiento from public.productos pr where pr.id = p_producto), 1)
           end, p_peso_bruto),
         case when a.id is null then null
              when a.peso_bruto is not null then 'ajuste crudo'
              when a.factor_crudo is not null then 'ajuste factor ' || a.factor_crudo
              when a.porcion_servida is not null then 'ajuste servido ' || a.porcion_servida end
    from (select 1) uno
    left join lateral (
      select g.* from public.gramajes_ajuste g
       where g.contrato_id = p_contrato
         and (g.contrato_sede_id = p_contrato_sede or g.contrato_sede_id is null)
         and (g.grupo_poblacion_id = p_grupo or g.grupo_poblacion_id is null)
         and (g.producto_id = p_producto or (g.producto_id is null and g.preparacion_id = p_preparacion) or (g.producto_id is null and g.preparacion_id is null and g.componente_id = p_componente))
         and g.vigente_desde <= p_fecha and (g.vigente_hasta is null or g.vigente_hasta >= p_fecha)
       order by g.contrato_sede_id nulls last, g.producto_id nulls last, g.grupo_poblacion_id nulls last, g.vigente_desde desc
       limit 1) a on true;
$$;

-- ---------------------------------------------------------------------
-- C1 (b). Coherencia de empresa: toda referencia (contrato, sede, receta, producto, ciclo...) debe ser de la misma empresa de la fila.
-- ---------------------------------------------------------------------
create or replace function public.validar_empresa_coherente() returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); v_emp uuid := (j->>'empresa_id')::uuid; col text; tbl text; v uuid; v_e uuid; v_nullable boolean;
begin
  for col, tbl, v_nullable in select * from (values
      ('contrato_id','contratos',false), ('contrato_sede_id','contrato_sedes',false), ('sede_id','sedes',false),
      ('preparacion_id','preparaciones',false), ('preparacion_nueva_id','preparaciones',false), ('preparacion_proteico_id','preparaciones',false),
      ('producto_id','productos',false), ('producto_origen_id','productos',false), ('producto_destino_id','productos',false), ('producto_sustituto_id','productos',false),
      ('ciclo_id','ciclos_menu',false), ('ciclo_alterno_id','ciclos_menu',false),
      ('componente_id','componentes',false), ('componente_nuevo_id','componentes',false), ('tiempo_comida_id','tiempos_comida',false),
      ('grupo_poblacion_id','grupos_poblacion',false), ('variante_id','variantes_racion',false), ('familia_id','familias_intercambio',false),
      ('tipo_dieta_id','tipos_dieta',true), ('equivale_a_id','tipos_dieta',true)) x(c, t, n) loop
    if j ? col and j->>col is not null then
      v := (j->>col)::uuid;
      execute format('select empresa_id from public.%I where id = $1', tbl) into v_e using v;
      if v_e is null and v_nullable then continue; end if;   -- catalogo de la plataforma (dietas)
      if v_emp is null or v_e is distinct from v_emp then
        raise exception 'Referencia de otra empresa en %.% (%).', tg_table_name, col, v;
      end if;
    end if;
  end loop;
  return new;
end $$;

-- reglas de dieta de un contrato heredan la empresa del contrato
create or replace function public.completar_empresa_regla() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.contrato_id is not null then
    new.empresa_id := coalesce(new.empresa_id, (select empresa_id from public.contratos where id = new.contrato_id));
  end if;
  if new.empresa_id is null and not (public.es_superadmin() or public.es_admin_sql()) then
    raise exception 'Solo el administrador de la plataforma crea reglas del catalogo general.';
  end if;
  return new;
end $$;
create trigger reglas_dieta_empresa before insert or update on public.reglas_dieta for each row execute function public.completar_empresa_regla();

do $$ declare t text; begin
  foreach t in array array['tiempos_comida','grupos_poblacion','componentes','variantes_racion','minuta_patron','gramajes_ajuste','preparaciones',
                           'preparacion_ingredientes','ciclos_menu','ciclo_menu_items','reglas_rotacion','sede_ciclo','calendario_servicio','menu_excepciones',
                           'dieta_equivalencias','dietas_poblacion','cupos','partes_diarios','explosiones','intercambios_menu','ventanas_ajuste_menu',
                           'familias_intercambio','familia_opciones','dieta_estandar','contrato_sedes','contrato_modificaciones','contrato_ejecucion','factores_coccion'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I_empresa_coherente on public.%I', t, t);
      execute format('create trigger %I_empresa_coherente before insert or update on public.%I for each row execute function public.validar_empresa_coherente()', t, t);
    end if;
  end loop;
end $$;
create trigger reglas_dieta_empresa_coherente before insert or update on public.reglas_dieta for each row execute function public.validar_empresa_coherente();

-- ---------------------------------------------------------------------
-- A4. Intercambios: clase, alcance y ventana no se cambian por edicion; el administrador de sede solo propone para su sede;
--     los estados siguen su orden.
-- ---------------------------------------------------------------------
create or replace function public.mi_sede(p_empresa uuid) returns uuid language sql stable security definer set search_path = public as $$
  select m.sede_id from public.membresias m where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo limit 1;
$$;
grant execute on function public.mi_sede(uuid) to authenticated;

create or replace function public.proteger_intercambio() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.es_admin_sql() or public.es_superadmin() then return new; end if;
  if new.empresa_id <> old.empresa_id or new.contrato_id <> old.contrato_id or new.contrato_sede_id is distinct from old.contrato_sede_id
     or new.clase <> old.clase or new.vigente_desde <> old.vigente_desde then
    raise exception 'La clase, el alcance y el inicio del intercambio no se cambian: anule y cree uno nuevo.';
  end if;
  new.fuera_de_ventana := old.fuera_de_ventana;
  new.creado_por := old.creado_por; new.creado_en := old.creado_en;
  if new.estado <> old.estado and current_setting('supply.cambio_estado', true) is distinct from 'si' then
    raise exception 'El estado se cambia con cambiar_estado_intercambio.';
  end if;
  return new;
end $$;
create trigger intercambios_menu_proteger before update on public.intercambios_menu for each row execute function public.proteger_intercambio();

drop policy if exists intercambios_menu_crear on public.intercambios_menu;
create policy intercambios_menu_crear on public.intercambios_menu for insert to authenticated
  with check (public.es_superadmin()
    or (public.tiene_permiso(empresa_id, 'M2', 'crear') and estado = 'propuesto')
    or (public.tiene_permiso(empresa_id, 'M7', 'crear') and estado = 'propuesto' and contrato_sede_id is not null
        and (public.mi_sede(empresa_id) is null or exists (select 1 from public.contrato_sedes cs where cs.id = contrato_sede_id and cs.sede_id = public.mi_sede(empresa_id)))));

create or replace function public.cambiar_estado_intercambio(p_id uuid, p_estado text, p_soporte text default null, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare x public.intercambios_menu; v_ok boolean; v_admin boolean := public.es_admin_sql() or public.es_superadmin();
begin
  select * into x from public.intercambios_menu where id = p_id for update;
  if x.id is null then raise exception 'Intercambio no encontrado'; end if;
  -- orden de estados
  if not ((x.estado = 'propuesto' and p_estado in ('concertado','rechazado','anulado'))
       or (x.estado = 'concertado' and p_estado in ('aprobado_entidad','rechazado','anulado'))
       or (x.estado = 'aprobado_entidad' and p_estado = 'anulado')) then
    raise exception 'No se puede pasar de "%" a "%".', x.estado, p_estado;
  end if;
  v_ok := v_admin
       or (p_estado = 'concertado' and (public.tiene_permiso(x.empresa_id, 'M2', 'aprobar')
            or (public.tiene_permiso(x.empresa_id, 'M7', 'aprobar') and x.contrato_sede_id is not null
                and (public.mi_sede(x.empresa_id) is null or exists (select 1 from public.contrato_sedes cs where cs.id = x.contrato_sede_id and cs.sede_id = public.mi_sede(x.empresa_id))))))
       or (p_estado in ('aprobado_entidad','rechazado') and public.tiene_permiso(x.empresa_id, 'M2', 'aprobar'))
       or (p_estado = 'anulado' and (public.tiene_permiso(x.empresa_id, 'M2', 'aprobar') or (x.creado_por = auth.uid() and x.estado = 'propuesto')));
  if not v_ok then raise exception 'Sin permiso para pasar el intercambio a "%".', p_estado; end if;
  perform set_config('supply.cambio_estado', 'si', true);
  update public.intercambios_menu
     set estado = p_estado,
         soporte = coalesce(nullif(trim(p_soporte), ''), soporte),
         motivo = case when p_nota is not null and trim(p_nota) <> '' then motivo || ' | ' || trim(p_nota) else motivo end,
         concertado_por = case when p_estado = 'concertado' then auth.uid() else concertado_por end,
         concertado_en  = case when p_estado = 'concertado' then now() else concertado_en end,
         aprobado_por   = case when p_estado = 'aprobado_entidad' then auth.uid() else aprobado_por end,
         aprobado_en    = case when p_estado = 'aprobado_entidad' then now() else aprobado_en end
   where id = p_id;
  perform set_config('supply.cambio_estado', '', true);
end $$;

-- los avisos de intercambio ya se pueden registrar en un update (el trigger de proteccion los permite)
create or replace function public.registrar_aviso_intercambio(p_id uuid, p_a text) returns void language plpgsql security definer set search_path = public as $$
declare x public.intercambios_menu;
begin
  select * into x from public.intercambios_menu where id = p_id;
  if x.id is null then raise exception 'Intercambio no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(x.empresa_id, 'M8', 'crear') or public.tiene_permiso(x.empresa_id, 'M2', 'editar')) then
    raise exception 'Sin permiso para registrar avisos.';
  end if;
  if p_a = 'entidad' then update public.intercambios_menu set aviso_entidad_en = now() where id = p_id;
  elsif p_a = 'interventoria' then update public.intercambios_menu set aviso_interventoria_en = now() where id = p_id;
  else raise exception 'Indique entidad o interventoria'; end if;
end $$;

-- M5. Fechas por defecto en hora de Bogota
alter table public.gramajes_ajuste alter column vigente_desde set default ((now() at time zone 'America/Bogota')::date);
alter table public.dieta_estandar alter column vigente_desde set default ((now() at time zone 'America/Bogota')::date);

-- ---------------------------------------------------------------------
-- A5 + A7. Explosion: cobertura por tramos, raciones por tramo, bloqueo, sin bitacora por fila, RLS evaluado una vez.
-- ---------------------------------------------------------------------
alter table public.explosiones drop constraint explosiones_estado_check;
alter table public.explosiones add constraint explosiones_estado_check check (estado in ('borrador','parcial','calculada','aprobada','enviada_compras','anulada'));
alter table public.explosiones add column cubierto datemultirange not null default '{}';

create table public.explosion_raciones (
  explosion_id     uuid not null references public.explosiones(id) on delete cascade,
  contrato_sede_id uuid not null,
  fecha            date not null,
  raciones         int not null,      -- personas-dia con servicio (todos los tiempos)
  primary key (explosion_id, contrato_sede_id, fecha)
);
alter table public.explosion_raciones enable row level security;
create policy explosion_raciones_ver on public.explosion_raciones for select to authenticated
  using (exists (select 1 from public.explosiones e where e.id = explosion_id));
grant select on public.explosion_raciones to authenticated;

drop trigger if exists explosion_detalle_bitacora on public.explosion_detalle;

-- empresas donde el usuario puede ver planeacion/compras/sede (para RLS que se evalua una sola vez por consulta)
create or replace function public.mis_empresas_planeacion() returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct m.empresa_id), '{}')
    from public.membresias m join public.permisos p on p.rol_id = m.rol_id
   where m.usuario_id = auth.uid() and m.activo and p.accion = 'ver' and p.modulo in ('M2','M3','M7');
$$;
grant execute on function public.mis_empresas_planeacion() to authenticated;
drop policy if exists explosion_detalle_ver on public.explosion_detalle;
create policy explosion_detalle_ver on public.explosion_detalle for select to authenticated
  using ((select public.es_superadmin()) or empresa_id = any ((select public.mis_empresas_planeacion())::uuid[]));
drop policy if exists explosiones_ver on public.explosiones;
create policy explosiones_ver on public.explosiones for select to authenticated
  using ((select public.es_superadmin()) or empresa_id = any ((select public.mis_empresas_planeacion())::uuid[]));

drop function if exists public.calcular_explosion(uuid, date, date);
create function public.calcular_explosion(p_explosion uuid, p_desde date default null, p_hasta date default null, p_sedes uuid[] default null)
returns table (filas int, raciones int, productos int) language plpgsql security definer set search_path = public as $$
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
  select p_explosion, p.sede_id, p.fecha, coalesce(sum(p.total) filter (where p.tiempo_comida_id is null), 0) + coalesce(max(p.total) filter (where p.tiempo_comida_id is not null), 0)
    from tmp_exp_pob p group by p.sede_id, p.fecha;
  select coalesce(sum(r.raciones), 0) into v_rac from public.explosion_raciones r where r.explosion_id = p_explosion;
  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;

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
end $$;
revoke execute on function public.calcular_explosion(uuid, date, date, uuid[]) from public, anon;
grant execute on function public.calcular_explosion(uuid, date, date, uuid[]) to authenticated;

-- consolidada: queda calculada solo si todas sus explosiones cubren todo el periodo
create or replace function public.calcular_proyeccion_consolidada(p_id uuid, p_desde date default null, p_hasta date default null)
returns table (contratos int, filas int) language plpgsql security definer set search_path = public as $$
declare x record; r record; v_c int := 0; v_f int := 0;
begin
  if not public.puede_ver_consolidada(p_id) then raise exception 'Sin permiso'; end if;
  for x in select id from public.explosiones where proyeccion_consolidada_id = p_id loop
    select * into r from public.calcular_explosion(x.id, p_desde, p_hasta);
    v_c := v_c + 1; v_f := v_f + coalesce(r.filas, 0);
  end loop;
  update public.proyecciones_consolidadas
     set estado = case when not exists (select 1 from public.explosiones ex where ex.proyeccion_consolidada_id = p_id and ex.estado <> 'calculada') then 'calculada' else 'borrador' end,
         calculada_en = now()
   where id = p_id;
  return query select v_c, v_f;
end $$;

-- cerrar una consolidada que la pantalla calculo por tramos
create or replace function public.cerrar_proyeccion_consolidada(p_id uuid) returns text language plpgsql security definer set search_path = public as $$
declare v_est text;
begin
  if not public.puede_ver_consolidada(p_id) then raise exception 'Sin permiso'; end if;
  update public.proyecciones_consolidadas
     set estado = case when not exists (select 1 from public.explosiones ex where ex.proyeccion_consolidada_id = p_id and ex.estado <> 'calculada') then 'calculada' else 'borrador' end,
         calculada_en = now()
   where id = p_id returning estado into v_est;
  return v_est;
end $$;
revoke execute on function public.cerrar_proyeccion_consolidada(uuid) from public, anon;
grant execute on function public.cerrar_proyeccion_consolidada(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- M3. Mapeo maestro: mismo grupo y misma unidad; la consolidada solo suma por maestro lo aprobado
-- ---------------------------------------------------------------------
create or replace function public.decidir_mapeo_maestro(p_producto uuid, p_decision text, p_maestro uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare pr public.productos; v_grupo uuid; v_id uuid; pm public.productos_maestros;
begin
  select * into pr from public.productos where id = p_producto;
  if pr.id is null then raise exception 'Producto no encontrado'; end if;
  select grupo_id into v_grupo from public.empresas where id = pr.empresa_id;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso_grupo(v_grupo, 'M13', 'aprobar')) then raise exception 'Sin permiso (Maestros: aprobar).'; end if;
  if p_decision = 'aprobar' then
    select * into pm from public.productos_maestros where id = coalesce(p_maestro, pr.maestro_id);
    if pm.id is null or pm.grupo_id <> v_grupo then raise exception 'El maestro no es del grupo de la empresa.'; end if;
    if pm.unidad_base <> pr.unidad_base then raise exception 'El maestro esta en % y el producto en %: no se pueden sumar.', pm.unidad_base, pr.unidad_base; end if;
    update public.productos set maestro_id = pm.id, maestro_estado = 'aprobado' where id = p_producto;
  elsif p_decision = 'rechazar' then
    insert into public.productos_maestros (grupo_id, codigo, nombre, nombre_norm, categoria, unidad_base, unidad_compra, factor_compra, subfamilia)
    values (v_grupo, upper(regexp_replace(public.normalizar_nombre_producto(pr.nombre), '\s+', '_', 'g')) || '_' || substr(gen_random_uuid()::text, 1, 4),
            pr.nombre, public.normalizar_nombre_producto(pr.nombre), pr.categoria, pr.unidad_base, pr.unidad_compra, pr.factor_compra, trim(split_part(pr.nombre, ',', 1)))
    returning id into v_id;
    update public.productos set maestro_id = v_id, maestro_estado = 'aprobado', maestro_similitud = null where id = p_producto;
  else raise exception 'Decision no valida (aprobar, rechazar)'; end if;
end $$;

create or replace function public.resumen_proyeccion_consolidada(p_id uuid)
returns table (maestro_id uuid, maestro_codigo text, maestro_nombre text, categoria text, unidad_base text, unidad_compra text,
               cantidad_base numeric, cantidad_compra numeric, promedio_dia_base numeric, sin_maestro boolean, mapeo_pendiente boolean, por_empresa jsonb)
language sql stable security definer set search_path = public as $$
  with pc as (select * from public.proyecciones_consolidadas where id = p_id and public.puede_ver_consolidada(p_id)),
  porprod as (
    select d.producto_id, ex.empresa_id, ex.contrato_id, sum(d.cantidad_bruta) as cant
      from pc join public.explosiones ex on ex.proyeccion_consolidada_id = pc.id
      join public.explosion_detalle d on d.explosion_id = ex.id
     group by 1, 2, 3),
  emp as (
    -- un mapeo sugerido todavia no suma con el maestro: va por su producto y se marca pendiente
    select case when pr.maestro_estado = 'aprobado' then pr.maestro_id else pr.id end as clave,
           case when pr.maestro_estado = 'aprobado' then pr.maestro_id end as maestro_id,
           bool_or(pr.maestro_estado = 'sugerido') as pend, x.empresa_id, x.contrato_id, sum(x.cant) as cant
      from porprod x join public.productos pr on pr.id = x.producto_id
     group by 1, 2, 4, 5)
  select emp.maestro_id,
         coalesce(pm.codigo, pr.codigo), coalesce(pm.nombre, pr.nombre), coalesce(pm.categoria, pr.categoria),
         coalesce(pm.unidad_base, pr.unidad_base), coalesce(pm.unidad_compra, pr.unidad_compra),
         round(sum(emp.cant), 3),
         round(sum(emp.cant) / nullif(coalesce(pm.factor_compra, pr.factor_compra), 0), 3),
         round(sum(emp.cant) / greatest((select fecha_hasta - fecha_desde + 1 from pc), 1), 3),
         emp.maestro_id is null,
         bool_or(emp.pend),
         jsonb_agg(jsonb_build_object('empresa', e.nombre_corto, 'contrato', ct.numero, 'cantidad', round(emp.cant, 3)) order by emp.cant desc)
    from emp
    join public.empresas e on e.id = emp.empresa_id
    join public.contratos ct on ct.id = emp.contrato_id
    left join public.productos_maestros pm on pm.id = emp.maestro_id
    left join public.productos pr on pr.id = emp.clave and emp.maestro_id is null
   group by emp.clave, emp.maestro_id, pm.id, pr.id
   order by sum(emp.cant) desc;
$$;

-- calculo inverso por contrato: con permiso y como proyeccion (antes no revisaba permisos)
create or replace function public.calculo_inverso(p_contrato uuid, p_producto uuid, p_cantidad numeric, p_desde date, p_sedes uuid[] default null, p_dias_simulados int default 35, p_max_dias int default 730)
returns table (fecha_hasta date, dias int, consumo_diario_promedio numeric, consumo_total numeric, extrapolado boolean) language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_emp uuid; acum numeric := 0; n int := 0; dia_cons numeric; prom numeric; extra int := 0;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver')) then
    raise exception 'Sin permiso (Planeacion o Compras: ver).';
  end if;
  p_dias_simulados := least(greatest(p_dias_simulados, 7), 60);
  insert into public.explosiones (empresa_id, contrato_id, codigo, nombre, fecha_desde, fecha_hasta, sedes, estado, tipo)
  values (v_emp, p_contrato, 'TMP-' || substr(gen_random_uuid()::text, 1, 8), 'calculo inverso temporal', p_desde, p_desde + p_dias_simulados - 1, p_sedes, 'borrador', 'proyeccion') returning id into v_id;
  perform public.calcular_explosion(v_id);
  for dia_cons in select coalesce(sum(d.cantidad_bruta), 0)
                    from generate_series(p_desde, p_desde + p_dias_simulados - 1, interval '1 day') g
                    left join public.explosion_detalle d on d.explosion_id = v_id and d.producto_id = p_producto and d.fecha = g::date
                   group by g order by g loop
    if acum + dia_cons > p_cantidad then exit; end if;
    acum := acum + dia_cons; n := n + 1;
  end loop;
  select coalesce(sum(cantidad_bruta), 0) / greatest(p_dias_simulados, 1) into prom from public.explosion_detalle where explosion_id = v_id and producto_id = p_producto;
  delete from public.explosiones where id = v_id;
  if n >= p_dias_simulados and prom > 0 then
    extra := least(p_max_dias - n, floor((p_cantidad - acum) / prom)::int);
    acum := acum + extra * prom; n := n + extra;
  end if;
  return query select (p_desde + n - 1)::date, n, case when n > 0 then round(acum / n, 3) end, round(acum, 3), extra > 0;
end $$;

-- alertas sin bucle dia a dia
create or replace function public.alertas_explosion(p_explosion uuid)
returns table (tipo text, detalle text, fecha date, sede text) language sql stable as $$
  with e as (select * from public.explosiones where id = p_explosion),
  s as (select cs.id, se.nombre from e join public.contrato_sedes cs on cs.contrato_id = e.contrato_id join public.sedes se on se.id = cs.sede_id
         where cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes)))
  select 'sin_ciclo', 'La sede no tiene ciclo de menu asignado', null::date, s.nombre from s, e
   where not exists (select 1 from public.sede_ciclo x where x.contrato_sede_id = s.id and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde))
  union all
  select 'sin_cupos', 'La sede no tiene cupos cargados en el periodo', null, s.nombre from s, e
   where not exists (select 1 from public.cupos c where c.contrato_sede_id = s.id and c.fecha_desde <= e.fecha_hasta and (c.fecha_hasta is null or c.fecha_hasta >= e.fecha_desde))
  union all
  select 'sin_receta', m.tiempo_codigo || ' · ' || m.componente_codigo || ' · ' || coalesce(m.descriptor, '(vacio)') || ' (dia ' || m.dia || ')', g::date, s.nombre
    from s cross join e cross join generate_series(e.fecha_desde, e.fecha_hasta, interval '1 day') g
    cross join lateral public.menu_del_dia(s.id, g::date, e.incluye_propuestos) m
   where m.preparacion_id is null;
$$;

-- ---------------------------------------------------------------------
-- C2 (b). Reemplaza el atajo en todas las funciones existentes y cierra la ejecucion publica/anon.
-- ---------------------------------------------------------------------
do $$ declare f record; v_def text; begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosrc like '%auth.uid() is null%' loop
    v_def := pg_get_functiondef(f.oid);
    v_def := replace(v_def, 'auth.uid() is null', 'public.es_admin_sql()');
    execute v_def;
  end loop;
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public', f.sig);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke execute on function %s from anon', f.sig); end if;
    execute format('grant execute on function %s to authenticated', f.sig);
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function %s to service_role', f.sig); end if;
  end loop;
end $$;
alter default privileges in schema public revoke execute on functions from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then execute 'alter default privileges in schema public revoke execute on functions from anon'; end if;
end $$;
