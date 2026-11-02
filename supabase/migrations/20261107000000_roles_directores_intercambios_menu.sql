-- =====================================================================
-- Supply ERP · Migracion 007 · Roles de direccion e intercambios de menu por sede (01-nov-2026, con OK de Osvaldo)
-- 1. Director de compras con Planeacion: aprobar (ajustes de gramaje, requerimientos, intercambios).
--    Roles nuevos: Director de operaciones y Director de planeacion.
-- 2. Proyeccion (simulacion) vs requerimiento oficial a compras.
-- 3. Festivos de Colombia y dias habiles (ventanas de concertacion de menus).
-- 4. Intercambios de menu: concertado (indefinido), temporada/cosecha o escasez, contingencia (paro, derrumbe...)
--    y especial; por sede o para todo el contrato; cambian preparacion, componente o ingrediente; con estados
--    propuesto -> concertado -> aprobado por la entidad; ventanas de concertacion; aviso interno en contingencias.
-- 5. Menu del dia y explosion leen: ciclo oficial -> intercambios vigentes -> intercambio puntual del dia.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Roles de direccion
-- ---------------------------------------------------------------------
insert into public.roles (empresa_id, codigo, nombre, descripcion, es_proveedor, sistema) values
  (null, 'dir_operaciones', 'Director de operaciones', 'Operacion de las unidades de servicio: menus concertados, intercambios, entregas, calidad, personal y flota', false, true),
  (null, 'dir_planeacion',  'Director de planeacion',  'Minutas, ciclos, cupos, dietas, ajustes de gramaje, proyecciones y requerimientos a compras', false, true)
on conflict do nothing;

create temporary table tmp_matriz7 (rol text, modulo text, letras text);
insert into tmp_matriz7 (rol, modulo, letras) values
  ('dir_operaciones','M1','V'),('dir_operaciones','M2','VA'),('dir_operaciones','M5','V'),('dir_operaciones','M6','VCA'),
  ('dir_operaciones','M7','VCA'),('dir_operaciones','M8','VCA'),('dir_operaciones','M11','VC'),('dir_operaciones','M13','V'),
  ('dir_operaciones','M14','VCA'),('dir_operaciones','M15','V'),
  ('dir_planeacion','M1','V'),('dir_planeacion','M2','VCA'),('dir_planeacion','M3','V'),('dir_planeacion','M5','V'),
  ('dir_planeacion','M7','V'),('dir_planeacion','M8','V'),('dir_planeacion','M13','VCA'),('dir_planeacion','M15','V'),
  ('dir_compras','M2','VCA');

insert into public.permisos (rol_id, modulo, accion)
select r.id, m.modulo, a.accion
  from tmp_matriz7 m
  join public.roles r on r.codigo = m.rol and r.sistema   -- plantilla global y las copias de cada empresa
  cross join lateral (
    select 'ver'::public.accion_permiso as accion where m.letras like '%V%'
    union all select 'crear'   where m.letras like '%C%'
    union all select 'editar'  where m.letras like '%C%'
    union all select 'aprobar' where m.letras like '%A%'
    union all select 'anular'  where m.letras like '%A%'
  ) a
on conflict do nothing;
drop table tmp_matriz7;

-- las empresas que ya existen reciben su copia de los roles nuevos
do $$ declare e record; begin
  for e in select id from public.empresas loop perform public.clonar_roles_plantilla(e.id); end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Festivos y dias habiles
-- ---------------------------------------------------------------------
create table public.festivos (
  fecha   date primary key,
  nombre  text not null,
  pais    text not null default 'CO'
);
insert into public.festivos (fecha, nombre) values
  ('2025-01-01','Año nuevo'),('2025-01-06','Reyes magos'),('2025-03-24','San Jose'),('2025-04-17','Jueves santo'),('2025-04-18','Viernes santo'),
  ('2025-05-01','Dia del trabajo'),('2025-06-02','Ascension'),('2025-06-23','Corpus Christi'),('2025-06-30','Sagrado Corazon / San Pedro y San Pablo'),
  ('2025-07-20','Independencia'),('2025-08-07','Batalla de Boyaca'),('2025-08-18','Asuncion'),('2025-10-13','Dia de la raza'),('2025-11-03','Todos los santos'),
  ('2025-11-17','Independencia de Cartagena'),('2025-12-08','Inmaculada Concepcion'),('2025-12-25','Navidad'),
  ('2026-01-01','Año nuevo'),('2026-01-12','Reyes magos'),('2026-03-23','San Jose'),('2026-04-02','Jueves santo'),('2026-04-03','Viernes santo'),
  ('2026-05-01','Dia del trabajo'),('2026-05-18','Ascension'),('2026-06-08','Corpus Christi'),('2026-06-15','Sagrado Corazon'),('2026-06-29','San Pedro y San Pablo'),
  ('2026-07-20','Independencia'),('2026-08-07','Batalla de Boyaca'),('2026-08-17','Asuncion'),('2026-10-12','Dia de la raza'),('2026-11-02','Todos los santos'),
  ('2026-11-16','Independencia de Cartagena'),('2026-12-08','Inmaculada Concepcion'),('2026-12-25','Navidad');
alter table public.festivos enable row level security;
create policy festivos_ver on public.festivos for select to authenticated using (true);
create policy festivos_admin on public.festivos for all to authenticated using (public.es_superadmin()) with check (public.es_superadmin());
grant select, insert, update, delete on public.festivos to authenticated;

create or replace function public.es_dia_habil(p_fecha date) returns boolean language sql stable as $$
  select extract(isodow from p_fecha) between 1 and 5 and not exists (select 1 from public.festivos f where f.fecha = p_fecha);
$$;

-- fecha que resulta de contar n dias habiles despues de p_desde (p_desde cuenta como dia 1 si es habil)
create or replace function public.sumar_dias_habiles(p_desde date, p_n int) returns date language plpgsql stable as $$
declare d date := p_desde; c int := 0;
begin
  if p_n <= 0 then return p_desde; end if;
  loop
    if public.es_dia_habil(d) then c := c + 1; end if;
    exit when c >= p_n;
    d := d + 1;
  end loop;
  return d;
end $$;
grant execute on function public.es_dia_habil(date), public.sumar_dias_habiles(date, int) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Ventanas de concertacion de menus
-- ---------------------------------------------------------------------
create table public.ventanas_ajuste_menu (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  contrato_id   uuid not null references public.contratos(id),
  tipo          text not null check (tipo in ('inicial','revision','oficio')),
  fecha_desde   date not null,
  fecha_hasta   date not null,
  soporte       text,
  nota          text,
  creado_por    uuid references auth.users(id) default auth.uid(),
  creado_en     timestamptz not null default now(),
  check (fecha_hasta >= fecha_desde)
);
create index ventanas_ajuste_menu_idx on public.ventanas_ajuste_menu (contrato_id, fecha_desde);

-- dias habiles de la ventana inicial por empresa (USPEC: 15)
insert into public.config_empresa (empresa_id, clave, valor, descripcion)
select id, 'dias_habiles_ajuste_menu', '15'::jsonb, 'Dias habiles desde el inicio del contrato para concertar cambios de menu' from public.empresas
on conflict do nothing;

create or replace function public.crear_ventana_inicial(p_contrato uuid, p_dias int default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare c public.contratos; v_dias int; v_id uuid;
begin
  select * into c from public.contratos where id = p_contrato;
  if c.id is null then raise exception 'Contrato no encontrado'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'editar')) then
    raise exception 'Sin permiso (Planeacion: editar).';
  end if;
  v_dias := coalesce(p_dias, (select (valor #>> '{}')::int from public.config_empresa where empresa_id = c.empresa_id and clave = 'dias_habiles_ajuste_menu'), 15);
  delete from public.ventanas_ajuste_menu where contrato_id = c.id and tipo = 'inicial';
  insert into public.ventanas_ajuste_menu (empresa_id, contrato_id, tipo, fecha_desde, fecha_hasta, nota)
  values (c.empresa_id, c.id, 'inicial', c.fecha_inicio, public.sumar_dias_habiles(c.fecha_inicio, v_dias), v_dias || ' dias habiles desde el inicio del contrato')
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.en_ventana_ajuste(p_contrato uuid, p_fecha date) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ventanas_ajuste_menu v where v.contrato_id = p_contrato and p_fecha between v.fecha_desde and v.fecha_hasta);
$$;

-- ventana inicial para los contratos que ya existen
select public.crear_ventana_inicial(id) from public.contratos;


-- ---------------------------------------------------------------------
-- 4. Notificaciones internas (carrera de relevos). Las ven quienes tienen ver en el modulo indicado.
-- ---------------------------------------------------------------------
create table public.notificaciones (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  modulo        text not null references public.modulos(codigo),
  prioridad     text not null default 'normal' check (prioridad in ('baja','normal','alta','urgente')),
  titulo        text not null,
  cuerpo        text,
  enlace        text,
  entidad       text,
  entidad_id    uuid,
  leida_por     uuid[] not null default '{}',
  creado_por    uuid references auth.users(id) default auth.uid(),
  creado_en     timestamptz not null default now()
);
create index notificaciones_empresa_idx on public.notificaciones (empresa_id, creado_en desc);
alter table public.notificaciones enable row level security;
create policy notificaciones_ver on public.notificaciones for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and public.tiene_permiso(empresa_id, modulo, 'ver')));
grant select on public.notificaciones to authenticated;

create or replace function public.marcar_notificacion_leida(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare n public.notificaciones;
begin
  select * into n from public.notificaciones where id = p_id;
  if n.id is null or not (public.es_superadmin() or (public.es_miembro(n.empresa_id) and public.tiene_permiso(n.empresa_id, n.modulo, 'ver'))) then
    raise exception 'Notificacion no encontrada';
  end if;
  update public.notificaciones set leida_por = array_append(leida_por, auth.uid()) where id = p_id and not (auth.uid() = any (leida_por));
end $$;
grant execute on function public.marcar_notificacion_leida(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Intercambios de menu
-- ---------------------------------------------------------------------
create table public.intercambios_menu (
  id                    uuid primary key default gen_random_uuid(),
  empresa_id            uuid not null references public.empresas(id),
  contrato_id           uuid not null references public.contratos(id),
  contrato_sede_id      uuid references public.contrato_sedes(id),          -- null = todas las sedes del contrato
  ciclo_id              uuid references public.ciclos_menu(id),             -- null = el ciclo vigente de cada sede
  clase                 text not null check (clase in ('concertado','temporada','contingencia','especial')),
  tipo_cambio           text not null check (tipo_cambio in ('preparacion','componente','ingrediente')),
  dia                   int check (dia is null or dia >= 1),                -- dia del ciclo; null = todos los dias
  tiempo_comida_id      uuid references public.tiempos_comida(id),          -- null = todos los tiempos (solo para ingrediente)
  componente_id         uuid references public.componentes(id),             -- componente que cambia
  preparacion_nueva_id  uuid references public.preparaciones(id),
  componente_nuevo_id   uuid references public.componentes(id),
  producto_origen_id    uuid references public.productos(id),               -- ingrediente: el que sale (arveja)
  producto_destino_id   uuid references public.productos(id),               -- ingrediente: el que entra (lenteja)
  factor_cantidad       numeric(8,4) not null default 1 check (factor_cantidad > 0),
  vigente_desde         date not null,
  vigente_hasta         date,                                                -- null = indefinido (concertado)
  estado                text not null default 'propuesto'
                        check (estado in ('propuesto','concertado','aprobado_entidad','rechazado','anulado')),
  fuera_de_ventana      boolean not null default false,
  motivo                text not null,
  soporte               text,                                                -- oficio / correo / acta
  aviso_entidad_en      timestamptz,                                         -- contingencia: cuando se aviso a la entidad
  aviso_interventoria_en timestamptz,
  creado_por            uuid references auth.users(id) default auth.uid(),
  creado_en             timestamptz not null default now(),
  concertado_por        uuid references auth.users(id),
  concertado_en         timestamptz,
  aprobado_por          uuid references auth.users(id),
  aprobado_en           timestamptz,
  actualizado_por       uuid references auth.users(id),
  actualizado_en        timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);
create index intercambios_menu_idx on public.intercambios_menu (contrato_id, vigente_desde);
create index intercambios_menu_sede_idx on public.intercambios_menu (contrato_sede_id);

-- cuando un intercambio cuenta para el menu y la explosion
create or replace function public.intercambio_aplica(p_estado text, p_clase text, p_incluye_propuestos boolean default false)
returns boolean language sql immutable as $$
  select p_estado in ('concertado','aprobado_entidad')
      or (p_clase = 'contingencia' and p_estado = 'propuesto')      -- la contingencia rige de inmediato; se formaliza despues
      or (p_incluye_propuestos and p_estado = 'propuesto');         -- simulaciones "que pasaria si"
$$;

-- validaciones y marcas al crear o cambiar un intercambio
create or replace function public.validar_intercambio() returns trigger language plpgsql security definer set search_path = public as $$
declare v_t uuid; v_tn uuid; v_sede text;
begin
  if new.tipo_cambio = 'preparacion' and (new.componente_id is null or new.preparacion_nueva_id is null) then
    raise exception 'Cambio de preparacion: indique el componente y la preparacion nueva.';
  end if;
  if new.tipo_cambio = 'componente' and (new.componente_id is null or new.componente_nuevo_id is null) then
    raise exception 'Cambio de componente: indique el componente que sale y el que entra.';
  end if;
  if new.tipo_cambio = 'componente' then
    select tiempo_comida_id into v_t from public.componentes where id = new.componente_id;
    select tiempo_comida_id into v_tn from public.componentes where id = new.componente_nuevo_id;
    if v_t is distinct from v_tn then raise exception 'El componente nuevo debe ser del mismo tiempo de comida.'; end if;
  end if;
  if new.tipo_cambio = 'ingrediente' and (new.producto_origen_id is null or new.producto_destino_id is null) then
    raise exception 'Cambio de ingrediente: indique el producto que sale y el que entra.';
  end if;
  if new.componente_id is not null and new.tiempo_comida_id is null then
    select tiempo_comida_id into new.tiempo_comida_id from public.componentes where id = new.componente_id;
  end if;
  -- el refrigerio (tiempo no cambiable) no admite intercambios especiales
  if new.clase = 'especial' and exists (select 1 from public.tiempos_comida t where t.id = new.tiempo_comida_id and not t.cambiable_especial) then
    raise exception 'Este tiempo de comida no se puede cambiar en menus especiales (obligacion contractual).';
  end if;
  if new.clase in ('temporada','contingencia') and new.vigente_hasta is null then
    raise exception 'Los intercambios por temporada o contingencia deben tener fecha final.';
  end if;
  if tg_op = 'INSERT' then
    new.fuera_de_ventana := (new.clase = 'concertado' and not public.en_ventana_ajuste(new.contrato_id, (now() at time zone 'America/Bogota')::date));
  end if;
  -- fuera de ventana: para concertarlo o aprobarlo se exige el oficio o correo que lo autoriza
  if new.fuera_de_ventana and new.estado in ('concertado','aprobado_entidad') and coalesce(trim(new.soporte), '') = '' then
    raise exception 'El intercambio esta fuera de la ventana de concertacion: adjunte o escriba el oficio que lo autoriza.';
  end if;
  return new;
end $$;
create trigger intercambios_menu_validar before insert or update on public.intercambios_menu for each row execute function public.validar_intercambio();
create trigger intercambios_menu_actualizacion before update on public.intercambios_menu for each row execute function public.marcar_actualizacion();
create trigger intercambios_menu_bitacora after insert or update or delete on public.intercambios_menu for each row execute function public.registrar_bitacora();

-- aviso interno al registrar una contingencia o un intercambio fuera de ventana
create or replace function public.avisar_intercambio() returns trigger language plpgsql security definer set search_path = public as $$
declare v_sede text;
begin
  select coalesce(s.nombre, 'todas las sedes') into v_sede from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.id = new.contrato_sede_id;
  v_sede := coalesce(v_sede, 'todas las sedes');
  if new.clase = 'contingencia' then
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (new.empresa_id, 'M2', 'urgente', 'Intercambio por contingencia · ' || v_sede,
            new.motivo || ' (del ' || to_char(new.vigente_desde, 'DD/MM/YYYY') || ' al ' || to_char(new.vigente_hasta, 'DD/MM/YYYY') || '). Recuerde avisar a la entidad y a la interventoria segun el protocolo de calidad.',
            '/intercambios?id=' || new.id, 'intercambio_menu', new.id);
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (new.empresa_id, 'M8', 'urgente', 'Aviso a entidad e interventoria pendiente · ' || v_sede,
            'Intercambio por contingencia: ' || new.motivo, '/intercambios?id=' || new.id, 'intercambio_menu', new.id);
  elsif new.fuera_de_ventana then
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (new.empresa_id, 'M2', 'alta', 'Intercambio fuera de ventana · ' || v_sede,
            new.motivo || '. Requiere oficio que lo autorice para concertarlo.', '/intercambios?id=' || new.id, 'intercambio_menu', new.id);
  end if;
  return new;
end $$;
create trigger intercambios_menu_avisar after insert on public.intercambios_menu for each row execute function public.avisar_intercambio();

-- cambiar estado: concertar (director de operaciones o de planeacion, compras con aprobar), aprobar entidad (Planeacion: aprobar)
create or replace function public.cambiar_estado_intercambio(p_id uuid, p_estado text, p_soporte text default null, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare x public.intercambios_menu; v_ok boolean;
begin
  select * into x from public.intercambios_menu where id = p_id;
  if x.id is null then raise exception 'Intercambio no encontrado'; end if;
  v_ok := auth.uid() is null or public.es_superadmin()
       or (p_estado = 'concertado' and (public.tiene_permiso(x.empresa_id, 'M2', 'aprobar') or public.tiene_permiso(x.empresa_id, 'M7', 'aprobar')))
       or (p_estado in ('aprobado_entidad','rechazado') and public.tiene_permiso(x.empresa_id, 'M2', 'aprobar'))
       or (p_estado = 'anulado' and (public.tiene_permiso(x.empresa_id, 'M2', 'aprobar') or (x.creado_por = auth.uid() and x.estado = 'propuesto')));
  if not v_ok then raise exception 'Sin permiso para pasar el intercambio a "%".', p_estado; end if;
  if x.estado in ('rechazado','anulado') then raise exception 'El intercambio ya esta %.', x.estado; end if;
  update public.intercambios_menu
     set estado = p_estado,
         soporte = coalesce(nullif(trim(p_soporte), ''), soporte),
         motivo = case when p_nota is not null and trim(p_nota) <> '' then motivo || ' | ' || trim(p_nota) else motivo end,
         concertado_por = case when p_estado = 'concertado' then auth.uid() else concertado_por end,
         concertado_en  = case when p_estado = 'concertado' then now() else concertado_en end,
         aprobado_por   = case when p_estado = 'aprobado_entidad' then auth.uid() else aprobado_por end,
         aprobado_en    = case when p_estado = 'aprobado_entidad' then now() else aprobado_en end
   where id = p_id;
end $$;

-- registrar los avisos de contingencia hechos a la entidad / interventoria
create or replace function public.registrar_aviso_intercambio(p_id uuid, p_a text) returns void language plpgsql security definer set search_path = public as $$
declare x public.intercambios_menu;
begin
  select * into x from public.intercambios_menu where id = p_id;
  if x.id is null then raise exception 'Intercambio no encontrado'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(x.empresa_id, 'M8', 'crear') or public.tiene_permiso(x.empresa_id, 'M2', 'editar')) then
    raise exception 'Sin permiso para registrar avisos.';
  end if;
  if p_a = 'entidad' then update public.intercambios_menu set aviso_entidad_en = now() where id = p_id;
  elsif p_a = 'interventoria' then update public.intercambios_menu set aviso_interventoria_en = now() where id = p_id;
  else raise exception 'Indique entidad o interventoria'; end if;
end $$;

alter table public.intercambios_menu enable row level security;
alter table public.ventanas_ajuste_menu enable row level security;
create policy intercambios_menu_ver on public.intercambios_menu for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))));
-- proponen: planeacion/compras (M2 crear) y el administrador de sede (M7 crear), siempre como "propuesto"
create policy intercambios_menu_crear on public.intercambios_menu for insert to authenticated
  with check (public.es_superadmin() or ((public.tiene_permiso(empresa_id, 'M2', 'crear') or public.tiene_permiso(empresa_id, 'M7', 'crear')) and estado = 'propuesto'));
-- se edita mientras esta propuesto; los cambios de estado van por cambiar_estado_intercambio
create policy intercambios_menu_editar on public.intercambios_menu for update to authenticated
  using (public.es_superadmin() or (estado = 'propuesto' and (public.tiene_permiso(empresa_id, 'M2', 'editar') or creado_por = auth.uid())))
  with check (public.es_superadmin() or estado = 'propuesto');
grant select, insert, update on public.intercambios_menu to authenticated;
create policy ventanas_ajuste_menu_ver on public.ventanas_ajuste_menu for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id));
create policy ventanas_ajuste_menu_admin on public.ventanas_ajuste_menu for all to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar'))
  with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar'));
grant select, insert, update, delete on public.ventanas_ajuste_menu to authenticated;
create trigger ventanas_ajuste_menu_bitacora after insert or update or delete on public.ventanas_ajuste_menu for each row execute function public.registrar_bitacora();

-- vista para la interventoria: diferencias de cada sede frente a la minuta oficial
create or replace view public.v_intercambios with (security_invoker = on) as
select x.*, coalesce(s.nombre, 'Todas las sedes') as sede_nombre, t.nombre as tiempo_nombre, co.nombre as componente_nombre,
       pn.nombre as preparacion_nueva, cn.nombre as componente_nuevo, po.nombre as producto_origen, pd.nombre as producto_destino,
       ci.nombre as ciclo_nombre,
       public.intercambio_aplica(x.estado, x.clase, false) as aplica_hoy,
       case when x.vigente_hasta is not null and x.vigente_hasta < (now() at time zone 'America/Bogota')::date then true else false end as vencido
  from public.intercambios_menu x
  left join public.contrato_sedes cs on cs.id = x.contrato_sede_id
  left join public.sedes s on s.id = cs.sede_id
  left join public.tiempos_comida t on t.id = x.tiempo_comida_id
  left join public.componentes co on co.id = x.componente_id
  left join public.preparaciones pn on pn.id = x.preparacion_nueva_id
  left join public.componentes cn on cn.id = x.componente_nuevo_id
  left join public.productos po on po.id = x.producto_origen_id
  left join public.productos pd on pd.id = x.producto_destino_id
  left join public.ciclos_menu ci on ci.id = x.ciclo_id;
grant select on public.v_intercambios to authenticated;

-- sustitucion de ingrediente vigente para un uso concreto (sede, fecha, dia, tiempo, componente)
create or replace function public.sustitucion_ingrediente(p_contrato_sede uuid, p_fecha date, p_dia int, p_tiempo uuid, p_componente uuid, p_producto uuid, p_incluye_propuestos boolean default false)
returns table (producto_id uuid, factor numeric, intercambio_id uuid) language sql stable security definer set search_path = public as $$
  select x.producto_destino_id, x.factor_cantidad, x.id
    from public.intercambios_menu x join public.contrato_sedes cs on cs.id = p_contrato_sede and cs.contrato_id = x.contrato_id
   where x.tipo_cambio = 'ingrediente' and x.producto_origen_id = p_producto
     and (x.contrato_sede_id = p_contrato_sede or x.contrato_sede_id is null)
     and (x.dia is null or x.dia = p_dia)
     and (x.tiempo_comida_id is null or x.tiempo_comida_id = p_tiempo)
     and (x.componente_id is null or x.componente_id = p_componente)
     and x.vigente_desde <= p_fecha and (x.vigente_hasta is null or x.vigente_hasta >= p_fecha)
     and public.intercambio_aplica(x.estado, x.clase, p_incluye_propuestos)
   order by (x.contrato_sede_id is null), case x.clase when 'contingencia' then 1 when 'temporada' then 2 when 'especial' then 3 else 4 end,
            (x.dia is null), x.vigente_desde desc, x.creado_en desc
   limit 1;
$$;

-- ---------------------------------------------------------------------
-- 6. Menu del dia con intercambios
-- ---------------------------------------------------------------------
drop function if exists public.menu_del_dia(uuid, date);
create function public.menu_del_dia(p_contrato_sede uuid, p_fecha date, p_incluye_propuestos boolean default false)
returns table (ciclo_id uuid, dia int, variante_id uuid, tiempo_comida_id uuid, tiempo_codigo text, tiempo_orden int,
               componente_id uuid, componente_codigo text, preparacion_id uuid, preparacion_nombre text, descriptor text, origen text, intercambio_id uuid)
language sql stable security definer set search_path = public as $$
  with dc as (select * from public.dia_ciclo(p_contrato_sede, p_fecha)),
       cs as (select contrato_id from public.contrato_sedes where id = p_contrato_sede),
       v as (select coalesce(vr.componentes_excluidos, '{}') as excl from dc left join public.variantes_racion vr on vr.id = dc.variante_id),
       base as (
         select dc.ciclo_id, dc.dia, dc.variante_id, i.tiempo_comida_id, t.codigo, t.orden, i.componente_id, c.codigo as ccod, i.preparacion_id, i.descriptor
           from dc join public.ciclo_menu_items i on i.ciclo_id = dc.ciclo_id and i.dia = dc.dia
           join public.tiempos_comida t on t.id = i.tiempo_comida_id
           join public.componentes c on c.id = i.componente_id
          where not (c.codigo = any (coalesce((select excl from v limit 1), '{}'::text[])))
       ),
       ic as (
         select distinct on (b.tiempo_comida_id, b.componente_id) b.tiempo_comida_id as t_id, b.componente_id as c_id, x.id, x.tipo_cambio, x.preparacion_nueva_id, x.componente_nuevo_id
           from base b join public.intercambios_menu x
             on x.contrato_id = (select contrato_id from cs)
            and (x.contrato_sede_id = p_contrato_sede or x.contrato_sede_id is null)
            and (x.ciclo_id is null or x.ciclo_id = b.ciclo_id)
            and (x.dia is null or x.dia = b.dia)
            and x.componente_id = b.componente_id
            and x.tipo_cambio in ('preparacion','componente')
            and x.vigente_desde <= p_fecha and (x.vigente_hasta is null or x.vigente_hasta >= p_fecha)
            and public.intercambio_aplica(x.estado, x.clase, p_incluye_propuestos)
          order by b.tiempo_comida_id, b.componente_id, (x.contrato_sede_id is null),
                   case x.clase when 'contingencia' then 1 when 'temporada' then 2 when 'especial' then 3 else 4 end,
                   (x.dia is null), x.vigente_desde desc, x.creado_en desc
       )
  select b.ciclo_id, b.dia, b.variante_id, b.tiempo_comida_id, b.codigo, b.orden,
         case when ic.tipo_cambio = 'componente' then ic.componente_nuevo_id else b.componente_id end,
         case when ic.tipo_cambio = 'componente' then cn.codigo else b.ccod end,
         coalesce(px.preparacion_id, ic.preparacion_nueva_id, b.preparacion_id) as preparacion_id,
         p.nombre, b.descriptor,
         case when px.id is not null then 'intercambio_dia' when ic.id is not null then 'intercambio' else 'ciclo' end as origen,
         ic.id
    from base b
    left join ic on ic.t_id = b.tiempo_comida_id and ic.c_id = b.componente_id
    left join public.componentes cn on cn.id = ic.componente_nuevo_id
    left join public.menu_excepciones px on px.contrato_id = (select contrato_id from cs) and px.fecha = p_fecha and px.aprobado
         and px.tipo = 'intercambio' and (px.contrato_sede_id = p_contrato_sede or px.contrato_sede_id is null)
         and px.tiempo_comida_id = b.tiempo_comida_id and px.componente_id = b.componente_id
    left join public.preparaciones p on p.id = coalesce(px.preparacion_id, ic.preparacion_nueva_id, b.preparacion_id)
   order by b.orden, b.ccod;
$$;
revoke execute on function public.menu_del_dia(uuid, date, boolean) from public, anon;
grant execute on function public.menu_del_dia(uuid, date, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Proyeccion vs requerimiento
-- ---------------------------------------------------------------------
alter table public.explosiones add column tipo text not null default 'proyeccion' check (tipo in ('proyeccion','requerimiento'));
alter table public.explosiones add column incluye_propuestos boolean not null default false;
alter table public.explosiones add column aprobada_por uuid references auth.users(id);
alter table public.explosiones add column aprobada_en timestamptz;

drop function if exists public.crear_explosion(uuid, date, date, uuid[], boolean, text, text);
create function public.crear_explosion(p_contrato uuid, p_desde date, p_hasta date, p_sedes uuid[] default null, p_incluye_dietas boolean default true,
                                       p_modo_presupuesto text default 'ninguno', p_nombre text default null, p_tipo text default 'proyeccion', p_incluye_propuestos boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if p_tipo = 'requerimiento' then
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'crear')) then
      raise exception 'Sin permiso para crear requerimientos (Planeacion: crear).';
    end if;
  else
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver')) then
      raise exception 'Sin permiso para proyectar (Planeacion o Compras: ver).';
    end if;
  end if;
  insert into public.explosiones (empresa_id, contrato_id, codigo, nombre, fecha_desde, fecha_hasta, sedes, incluye_dietas, modo_presupuesto, tipo, incluye_propuestos)
  values (v_emp, p_contrato, public.siguiente_consecutivo(v_emp, 'EXP'), p_nombre, p_desde, p_hasta, p_sedes, p_incluye_dietas, p_modo_presupuesto, p_tipo, p_incluye_propuestos)
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.crear_explosion(uuid, date, date, uuid[], boolean, text, text, text, boolean) from public, anon;
grant execute on function public.crear_explosion(uuid, date, date, uuid[], boolean, text, text, text, boolean) to authenticated;

-- convertir una proyeccion calculada en requerimiento, y aprobarlo / enviarlo a compras
create or replace function public.estado_requerimiento(p_explosion uuid, p_accion text) returns void language plpgsql security definer set search_path = public as $$
declare e public.explosiones;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if p_accion = 'convertir' then
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then raise exception 'Sin permiso (Planeacion: crear).'; end if;
    if e.estado <> 'calculada' then raise exception 'Solo una proyeccion calculada se convierte en requerimiento.'; end if;
    update public.explosiones set tipo = 'requerimiento' where id = p_explosion;
  elsif p_accion = 'aprobar' then
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'aprobar')) then raise exception 'Sin permiso (Planeacion: aprobar).'; end if;
    if e.tipo <> 'requerimiento' or e.estado <> 'calculada' then raise exception 'Solo se aprueba un requerimiento calculado.'; end if;
    update public.explosiones set estado = 'aprobada', aprobada_por = auth.uid(), aprobada_en = now() where id = p_explosion;
  elsif p_accion = 'enviar' then
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'aprobar')) then raise exception 'Sin permiso (Planeacion: aprobar).'; end if;
    if e.estado <> 'aprobada' then raise exception 'Primero apruebe el requerimiento.'; end if;
    update public.explosiones set estado = 'enviada_compras' where id = p_explosion;
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (e.empresa_id, 'M3', 'alta', 'Requerimiento ' || e.codigo || ' enviado a compras',
            'Del ' || to_char(e.fecha_desde, 'DD/MM/YYYY') || ' al ' || to_char(e.fecha_hasta, 'DD/MM/YYYY'), '/explosion?id=' || e.id, 'explosion', e.id);
  else raise exception 'Accion no valida'; end if;
end $$;
grant execute on function public.estado_requerimiento(uuid, text) to authenticated;

revoke execute on function public.crear_ventana_inicial(uuid, int), public.en_ventana_ajuste(uuid, date), public.cambiar_estado_intercambio(uuid, text, text, text),
  public.registrar_aviso_intercambio(uuid, text), public.sustitucion_ingrediente(uuid, date, int, uuid, uuid, uuid, boolean), public.estado_requerimiento(uuid, text) from public, anon;
grant execute on function public.crear_ventana_inicial(uuid, int), public.en_ventana_ajuste(uuid, date), public.cambiar_estado_intercambio(uuid, text, text, text),
  public.registrar_aviso_intercambio(uuid, text), public.sustitucion_ingrediente(uuid, date, int, uuid, uuid, uuid, boolean), public.estado_requerimiento(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 8. Explosion: proyeccion con ver (Planeacion o Compras), requerimiento con crear; aplica intercambios de menu e ingrediente
-- ---------------------------------------------------------------------
create or replace function public.calcular_explosion(p_explosion uuid)
returns table (filas int, raciones int, productos int) language plpgsql security definer set search_path = public as $$
declare e public.explosiones; s record; d date; m record; pob record; ing record; cr record; dd record; r record;
        v_emp uuid; v_rac int := 0; v_filas int := 0; v_crudo numeric; v_nota text; v_rac_dieta int; v_eq record; v_prep uuid; v_excl boolean; v_factor numeric; v_fija numeric; v_sust uuid; v_hay_sust boolean; si record; v_prod uuid;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if e.tipo = 'requerimiento' then
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then
      raise exception 'Sin permiso para calcular requerimientos (Planeacion: crear).';
    end if;
    if e.estado in ('aprobada','enviada_compras') then raise exception 'El requerimiento ya esta aprobado; cree uno nuevo.'; end if;
  elsif not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'ver') or public.tiene_permiso(e.empresa_id, 'M3', 'ver')) then
    raise exception 'Sin permiso para proyectar (Planeacion o Compras: ver).';
  end if;
  -- hay cambios de ingrediente vigentes en el periodo? (evita consultar uno por uno si no hay)
  v_hay_sust := exists (select 1 from public.intercambios_menu x where x.contrato_id = e.contrato_id and x.tipo_cambio = 'ingrediente'
                          and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde)
                          and public.intercambio_aplica(x.estado, x.clase, e.incluye_propuestos));
  v_emp := e.empresa_id;
  delete from public.explosion_detalle where explosion_id = p_explosion;

  for s in select cs.* from public.contrato_sedes cs
            where cs.contrato_id = e.contrato_id and cs.estado = 'activa'
              and (e.sedes is null or cs.id = any (e.sedes)) loop
    d := e.fecha_desde;
    while d <= e.fecha_hasta loop
      for m in select * from public.menu_del_dia(s.id, d, e.incluye_propuestos) loop
        if m.preparacion_id is null then d := d; continue; end if;  -- descriptor generico sin receta: no explota (queda en alerta)
        for pob in select * from public.poblacion_dia(s.id, d) loop
          if pob.variante_id is distinct from m.variante_id and pob.variante_id is not null then continue; end if;
          -- ---- linea
          if pob.linea > 0 then
            for ing in select pi.* from public.preparacion_ingredientes pi
                        where pi.preparacion_id = m.preparacion_id and (pi.grupo_poblacion_id = pob.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                        order by pi.grupo_poblacion_id nulls last loop
              -- si hay fila especifica del grupo, no usar la generica del mismo producto
              if ing.grupo_poblacion_id is null and exists (select 1 from public.preparacion_ingredientes x where x.preparacion_id = ing.preparacion_id and x.producto_id = ing.producto_id and x.grupo_poblacion_id = pob.grupo_poblacion_id) then continue; end if;
              select * into cr from public.crudo_ingrediente(e.contrato_id, s.id, d, m.preparacion_id, ing.producto_id, pob.grupo_poblacion_id, m.componente_id, ing.peso_bruto);
              v_prod := ing.producto_id; v_crudo := cr.crudo; v_nota := cr.nota;
              if v_hay_sust then
                select * into si from public.sustitucion_ingrediente(s.id, d, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos);
                if si.producto_id is not null then
                  v_prod := si.producto_id; v_crudo := v_crudo * si.factor; v_nota := concat_ws(' · ', v_nota, 'intercambio de ingrediente');
                end if;
              end if;
              insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
              values (v_emp, p_explosion, s.id, d, m.dia, m.tiempo_comida_id, m.componente_id, m.preparacion_id, v_prod, pob.grupo_poblacion_id, null, pob.linea, v_crudo, pob.linea * v_crudo, v_nota);
              v_filas := v_filas + 1;
            end loop;
          end if;
          -- ---- dietas (por tipo), si la explosion las incluye
          if e.incluye_dietas and pob.en_dieta > 0 then
            for dd in select dp.tipo_dieta_id, sum(dp.cantidad)::int as cant from public.dietas_poblacion dp
                       where dp.contrato_sede_id = s.id and (dp.grupo_poblacion_id = pob.grupo_poblacion_id or dp.grupo_poblacion_id is null)
                         and dp.fecha_desde <= d and (dp.fecha_hasta is null or dp.fecha_hasta >= d)
                       group by dp.tipo_dieta_id loop
              v_rac_dieta := dd.cant;
              -- equivalencia del contrato: explotar como otra dieta, o con una preparacion unificada para el proteico
              select * into v_eq from public.dieta_equivalencias q where q.contrato_id = e.contrato_id and q.tipo_dieta_id = dd.tipo_dieta_id;
              v_prep := m.preparacion_id;
              if v_eq.id is not null and v_eq.preparacion_proteico_id is not null and m.componente_codigo = 'PROTEICO' then v_prep := v_eq.preparacion_proteico_id; end if;
              -- reglas aplicables: del contrato primero, luego del catalogo; sobre la dieta equivalente si la hay
              v_excl := false; v_factor := 1; v_fija := null;
              for r in select * from public.reglas_dieta rd
                        where rd.activa and rd.tipo_dieta_id = coalesce(v_eq.equivale_a_id, dd.tipo_dieta_id)
                          and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and rd.empresa_id is null))
                          and (rd.componente_codigo is null or rd.componente_codigo = m.componente_codigo)
                        order by rd.contrato_id nulls last loop
                if r.tipo_regla = 'excluir_componente' and r.componente_codigo = m.componente_codigo then v_excl := true; end if;
                if r.tipo_regla = 'factor_porcion' and r.componente_codigo = m.componente_codigo and v_factor = 1 then v_factor := r.valor; end if;
                if r.tipo_regla = 'porcion_fija' and r.componente_codigo = m.componente_codigo and v_fija is null then v_fija := r.valor; end if;
              end loop;
              if v_excl then continue; end if;
              for ing in select pi.* from public.preparacion_ingredientes pi
                          where pi.preparacion_id = v_prep and (pi.grupo_poblacion_id = pob.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                          order by pi.grupo_poblacion_id nulls last loop
                if ing.grupo_poblacion_id is null and exists (select 1 from public.preparacion_ingredientes x where x.preparacion_id = ing.preparacion_id and x.producto_id = ing.producto_id and x.grupo_poblacion_id = pob.grupo_poblacion_id) then continue; end if;
                -- exclusion o sustitucion de producto
                if exists (select 1 from public.reglas_dieta rd where rd.activa and rd.tipo_dieta_id = coalesce(v_eq.equivale_a_id, dd.tipo_dieta_id) and rd.tipo_regla = 'excluir_producto' and rd.producto_id = ing.producto_id and (rd.contrato_id = e.contrato_id or rd.contrato_id is null)) then continue; end if;
                if exists (select 1 from public.reglas_dieta rd join public.productos pr on pr.id = ing.producto_id where rd.activa and rd.tipo_dieta_id = coalesce(v_eq.equivale_a_id, dd.tipo_dieta_id) and rd.tipo_regla = 'excluir_categoria' and rd.categoria_producto = pr.categoria and (rd.contrato_id = e.contrato_id or rd.contrato_id is null)) then continue; end if;
                select rd.producto_sustituto_id into v_sust from public.reglas_dieta rd where rd.activa and rd.tipo_dieta_id = coalesce(v_eq.equivale_a_id, dd.tipo_dieta_id) and rd.tipo_regla = 'sustituir_producto' and rd.producto_id = ing.producto_id and (rd.contrato_id = e.contrato_id or rd.contrato_id is null) order by rd.contrato_id nulls last limit 1;
                select * into cr from public.crudo_ingrediente(e.contrato_id, s.id, d, v_prep, ing.producto_id, pob.grupo_poblacion_id, m.componente_id, ing.peso_bruto);
                v_crudo := cr.crudo; v_nota := cr.nota;
                if ing.es_principal and v_fija is not null then
                  v_crudo := v_fija / coalesce((select rendimiento from public.productos where id = ing.producto_id), 1); v_nota := 'dieta: porcion fija ' || v_fija;
                elsif ing.es_principal and v_factor <> 1 then
                  v_crudo := v_crudo * v_factor; v_nota := 'dieta: factor ' || v_factor;
                end if;
                if v_hay_sust and v_sust is null then
                  select * into si from public.sustitucion_ingrediente(s.id, d, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos);
                  if si.producto_id is not null then
                    v_sust := si.producto_id; v_crudo := v_crudo * si.factor; v_nota := concat_ws(' · ', v_nota, 'intercambio de ingrediente');
                  end if;
                end if;
                insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
                values (v_emp, p_explosion, s.id, d, m.dia, m.tiempo_comida_id, m.componente_id, v_prep, coalesce(v_sust, ing.producto_id), pob.grupo_poblacion_id, dd.tipo_dieta_id, v_rac_dieta, v_crudo, v_rac_dieta * v_crudo,
                        concat_ws(' · ', v_nota, case when v_sust is not null then 'dieta: sustituido' end, case when v_prep <> m.preparacion_id then 'dieta: preparacion unificada' end));
                v_filas := v_filas + 1;
              end loop;
            end loop;
          end if;
        end loop;
      end loop;
      -- raciones del dia (todos los tiempos facturables) para el resumen
      select coalesce(sum(p.total), 0) into v_rac_dieta from public.poblacion_dia(s.id, d) p;
      if exists (select 1 from public.dia_ciclo(s.id, d)) then v_rac := v_rac + v_rac_dieta; end if;
      d := d + 1;
    end loop;
  end loop;

  update public.explosiones set estado = 'calculada', raciones = v_rac, calculada_en = now() where id = p_explosion;
  return query select v_filas, v_rac, (select count(distinct producto_id)::int from public.explosion_detalle where explosion_id = p_explosion);
end $$;

create or replace function public.alertas_explosion(p_explosion uuid)
returns table (tipo text, detalle text, fecha date, sede text) language plpgsql stable security definer set search_path = public as $$
declare e public.explosiones; s record; d date; m record;
begin
  select * into e from public.explosiones where id = p_explosion;
  for s in select cs.id, se.nombre from public.contrato_sedes cs join public.sedes se on se.id = cs.sede_id
            where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes)) loop
    if not exists (select 1 from public.sede_ciclo x where x.contrato_sede_id = s.id and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde)) then
      tipo := 'sin_ciclo'; detalle := 'La sede no tiene ciclo de menu asignado'; fecha := null; sede := s.nombre; return next;
    end if;
    if not exists (select 1 from public.cupos c where c.contrato_sede_id = s.id and c.fecha_desde <= e.fecha_hasta and (c.fecha_hasta is null or c.fecha_hasta >= e.fecha_desde)) then
      tipo := 'sin_cupos'; detalle := 'La sede no tiene cupos cargados en el periodo'; fecha := null; sede := s.nombre; return next;
    end if;
    d := e.fecha_desde;
    while d <= e.fecha_hasta loop
      for m in select * from public.menu_del_dia(s.id, d, e.incluye_propuestos) where preparacion_id is null loop
        tipo := 'sin_receta'; detalle := m.tiempo_codigo || ' · ' || m.componente_codigo || ' · ' || coalesce(m.descriptor, '(vacio)') || ' (dia ' || m.dia || ')'; fecha := d; sede := s.nombre; return next;
      end loop;
      d := d + 1;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 9. Cada director concerta en su frente; quien tiene la vista de compras puede proyectar
-- ---------------------------------------------------------------------
comment on table public.intercambios_menu is 'Intercambios de menu: concertado (indefinido), temporada (cosecha/escasez), contingencia (paro, derrumbe; aviso a entidad e interventoria) y especial. Por sede o todo el contrato.';
