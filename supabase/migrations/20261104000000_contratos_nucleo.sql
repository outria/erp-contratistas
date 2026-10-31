-- =====================================================================
-- Supply ERP · Migracion 004 · M1 Contratos y anexos (nucleo)
-- Entidades contratantes, contratos (cabezote), modificaciones (adiciones, prorrogas,
-- suspensiones, otrosies), unidades de servicio del contrato, ejecucion mensual
-- (para agotamiento presupuestal mientras llega M9) y la vista resumen.
-- Regla del 50 % (Ley 80 art. 40, Concepto CCE C-451 de 2025): el tope se mide en SMLMV
-- del año de suscripcion, no en pesos. Se guarda el SMLMV y se calcula en salarios.
-- =====================================================================

-- SMLMV por año (tabla de la plataforma; la actualiza el superadmin cada enero)
create table public.smlmv (
  anio    int primary key,
  valor   numeric(14,2) not null,
  fuente  text
);
insert into public.smlmv (anio, valor, fuente) values
  (2024, 1300000, 'Decreto 2292 de 2023'),
  (2025, 1423500, 'Decreto 1572 de 2024'),
  (2026, 1750905, 'Decreto 1480 de 2025 (verificar cifra con el area juridica)');
alter table public.smlmv enable row level security;
create policy smlmv_ver on public.smlmv for select to authenticated using (true);
create policy smlmv_admin on public.smlmv for all to authenticated using (public.es_superadmin()) with check (public.es_superadmin());
grant select, insert, update on public.smlmv to authenticated;

-- ---------------------------------------------------------------------
-- 1. Entidades contratantes (USPEC, gobernaciones, alcaldias, ICBF, fuerzas...) por empresa
-- ---------------------------------------------------------------------
create table public.entidades_contratantes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  nombre          text not null,
  nit             text,
  tipo            text not null default 'otra'
                  check (tipo in ('nacional', 'gobernacion', 'alcaldia', 'icbf', 'uspec', 'fuerzas', 'otra')),
  ciudad          text,
  contacto        text,
  correo          text,
  telefono        text,
  estado          text not null default 'activa' check (estado in ('activa', 'anulada')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (empresa_id, nombre)
);

-- ---------------------------------------------------------------------
-- 2. Contratos (cabezote)
-- ---------------------------------------------------------------------
create table public.contratos (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas(id),
  codigo              text not null,                 -- consecutivo interno CT-000001
  numero              text not null,                 -- numero del contrato en la entidad (ej. 202501642)
  entidad_id          uuid not null references public.entidades_contratantes(id),
  modalidad           text not null
                      check (modalidad in ('uspec_ppl', 'pae', 'icbf_primera_infancia', 'fuerzas_casino', 'adulto_mayor', 'bomberos', 'otro')),
  objeto              text not null,
  obligaciones        text,                          -- resumen; el detalle va en adjuntos
  proceso_secop       text,                          -- numero o enlace del proceso en SECOP II
  interventoria       text,                          -- firma o equipo que audita
  supervisor_entidad  text,
  valor_inicial       numeric(16,2) not null check (valor_inicial > 0),
  incluye_iva         boolean not null default false,
  fecha_suscripcion   date not null,
  fecha_inicio        date not null,
  fecha_fin_inicial   date not null,
  smlmv_suscripcion   numeric(14,2) not null,        -- se toma de la tabla smlmv por el año de suscripcion
  dias_atencion       text not null default 'habiles'
                      check (dias_atencion in ('habiles', 'todos', 'calendario_propio')),
  tiempos_comida      int not null default 1 check (tiempos_comida between 1 and 6),
  n_menus_ciclo       int,                           -- 15, 18, 20, 21 (se detalla en M2)
  ciclo_reparto       text default 'semanal',        -- semanal, quincenal, 2+3, 3+4 (por defecto para las sedes)
  dias_subsanacion    int default 3,                 -- plazo contractual para subsanar hallazgos
  poliza_cumplimiento text,
  estado              text not null default 'borrador'
                      check (estado in ('borrador', 'vigente', 'suspendido', 'liquidacion', 'terminado', 'anulado')),
  notas               text,
  creado_por          uuid references auth.users(id) default auth.uid(),
  creado_en           timestamptz not null default now(),
  actualizado_por     uuid references auth.users(id),
  actualizado_en      timestamptz not null default now(),
  unique (empresa_id, codigo),
  unique (empresa_id, entidad_id, numero),
  check (fecha_fin_inicial >= fecha_inicio)
);
create index contratos_empresa_estado_idx on public.contratos (empresa_id, estado);

-- SMLMV automatico por año de suscripcion si no lo mandan
create or replace function public.contrato_smlmv() returns trigger language plpgsql as $$
begin
  if new.smlmv_suscripcion is null or new.smlmv_suscripcion = 0 then
    select valor into new.smlmv_suscripcion from public.smlmv where anio = extract(year from new.fecha_suscripcion)::int;
    if new.smlmv_suscripcion is null then
      raise exception 'No hay SMLMV cargado para el año %. Pida al superadministrador cargarlo.', extract(year from new.fecha_suscripcion)::int;
    end if;
  end if;
  return new;
end $$;
alter table public.contratos alter column smlmv_suscripcion drop not null;
create trigger contratos_smlmv before insert or update of fecha_suscripcion on public.contratos for each row execute function public.contrato_smlmv();

-- ---------------------------------------------------------------------
-- 3. Modificaciones: adiciones en valor, prorrogas en tiempo, suspensiones, otrosies
-- ---------------------------------------------------------------------
create table public.contrato_modificaciones (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id) on delete restrict,
  tipo            text not null check (tipo in ('adicion', 'prorroga', 'adicion_prorroga', 'suspension', 'reinicio', 'otrosi', 'cesion', 'terminacion_anticipada')),
  numero          text,                              -- numero del otrosi / adicion en la entidad
  fecha           date not null,
  valor_adicion   numeric(16,2) not null default 0 check (valor_adicion >= 0),
  nueva_fecha_fin date,
  dias_suspension int,
  smlmv_vigente   numeric(14,2),                     -- SMLMV al momento de la adicion (para el tope)
  motivo          text,
  excepcion_legal boolean not null default false,    -- la entidad justifica superar el tope (p. ej. norma especial)
  estado          text not null default 'vigente' check (estado in ('borrador', 'vigente', 'anulada')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now()
);
create index contrato_modificaciones_idx on public.contrato_modificaciones (contrato_id, fecha);

-- Regla del 50 %: suma de adiciones en SMLMV no puede pasar la mitad del valor inicial en SMLMV
create or replace function public.validar_tope_adicion() returns trigger language plpgsql security definer set search_path = public as $$
declare c public.contratos; v_tope numeric; v_acum numeric; v_pct numeric; v_smlmv numeric;
begin
  if new.estado <> 'vigente' or new.valor_adicion = 0 then return new; end if;
  select * into c from public.contratos where id = new.contrato_id;
  if new.smlmv_vigente is null then
    select valor into v_smlmv from public.smlmv where anio = extract(year from new.fecha)::int;
    new.smlmv_vigente := coalesce(v_smlmv, c.smlmv_suscripcion);
  end if;
  select coalesce((select valor from public.config_empresa where empresa_id = c.empresa_id and clave = 'tope_adiciones_pct')::numeric, 50) into v_pct;
  v_tope := (c.valor_inicial / c.smlmv_suscripcion) * (v_pct / 100.0);
  select coalesce(sum(m.valor_adicion / coalesce(m.smlmv_vigente, c.smlmv_suscripcion)), 0) into v_acum
    from public.contrato_modificaciones m
   where m.contrato_id = c.id and m.estado = 'vigente' and m.id <> new.id;
  v_acum := v_acum + new.valor_adicion / new.smlmv_vigente;
  if v_acum > v_tope and not new.excepcion_legal then
    raise exception 'La adicion supera el tope del % %% del valor inicial medido en SMLMV (acumulado % salarios, tope % salarios). Si la entidad lo justifica, marque "excepcion legal" y adjunte el soporte.',
      v_pct, round(v_acum, 2), round(v_tope, 2);
  end if;
  return new;
end $$;
create trigger contrato_modificaciones_tope before insert or update on public.contrato_modificaciones
  for each row execute function public.validar_tope_adicion();

-- ---------------------------------------------------------------------
-- 4. Unidades de servicio del contrato (ERON, colegios, CDI...) y sus cupos de referencia
--    La sede fisica vive en public.sedes (tipo unidad_servicio); aqui se amarra al contrato
--    con lo propio del contrato: codigo en la entidad, ciclo de reparto, dia de arranque de la
--    semana de consumo, firmantes del cuadro de raciones.
-- ---------------------------------------------------------------------
create table public.contrato_sedes (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_id        uuid not null references public.contratos(id) on delete restrict,
  sede_id            uuid not null references public.sedes(id),
  codigo_entidad     text,                          -- codigo DANE del colegio, codigo ERON, etc.
  cupos_referencia   int not null default 0,        -- cupos al inicio (el detalle por fecha/grupo va en M2)
  ciclo_reparto      text,                          -- hereda del contrato si es null
  dia_inicio_semana  int check (dia_inicio_semana between 1 and 7),
  firmante_1         text,                          -- jefe de guardia / rector
  firmante_2         text,                          -- director ERON / lider padres
  menu_confirmado    boolean not null default false, -- USPEC: menu adaptado confirmado en los primeros 15 dias
  fecha_inicio       date,
  fecha_fin          date,
  estado             text not null default 'activa' check (estado in ('activa', 'suspendida', 'retirada')),
  notas              text,
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now(),
  actualizado_por    uuid references auth.users(id),
  actualizado_en     timestamptz not null default now(),
  unique (contrato_id, sede_id)
);

-- ---------------------------------------------------------------------
-- 5. Ejecucion mensual (facturado a la entidad) para el agotamiento presupuestal.
--    Mientras no exista M9, contabilidad lo carga a mano por mes; cuando llegue M9 se alimenta solo.
-- ---------------------------------------------------------------------
create table public.contrato_ejecucion (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id) on delete restrict,
  periodo         date not null,                     -- primer dia del mes
  raciones        int,
  valor_facturado numeric(16,2) not null default 0,
  valor_pagado    numeric(16,2) not null default 0,
  fecha_radicacion date,
  fecha_pago      date,
  origen          text not null default 'manual' check (origen in ('manual', 'facturacion')),
  notas           text,
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (contrato_id, periodo)
);

-- ---------------------------------------------------------------------
-- 6. Vista resumen: valor total, fecha fin vigente, ejecutado, % agotamiento y fecha proyectada
-- ---------------------------------------------------------------------
create or replace view public.v_contratos_resumen with (security_invoker = on) as
with mods as (
  select contrato_id,
         sum(valor_adicion) filter (where estado = 'vigente') as adiciones,
         max(nueva_fecha_fin) filter (where estado = 'vigente') as fin_prorrogado,
         sum(coalesce(dias_suspension, 0)) filter (where estado = 'vigente') as dias_suspendidos,
         count(*) filter (where estado = 'vigente') as n_modificaciones
    from public.contrato_modificaciones group by contrato_id),
ejec as (
  select contrato_id, sum(valor_facturado) as facturado, sum(valor_pagado) as pagado, sum(raciones) as raciones,
         min(periodo) as primer_mes, max(periodo) as ultimo_mes, count(*) as meses
    from public.contrato_ejecucion group by contrato_id),
sedes as (select contrato_id, count(*) filter (where estado = 'activa') as n_sedes, sum(cupos_referencia) filter (where estado = 'activa') as cupos
    from public.contrato_sedes group by contrato_id)
select c.*,
       e.nombre as entidad_nombre, e.tipo as entidad_tipo,
       coalesce(m.adiciones, 0) as adiciones,
       c.valor_inicial + coalesce(m.adiciones, 0) as valor_total,
       coalesce(m.fin_prorrogado, c.fecha_fin_inicial) as fecha_fin_vigente,
       coalesce(m.n_modificaciones, 0) as n_modificaciones,
       round(coalesce(m.adiciones, 0) / c.smlmv_suscripcion / (c.valor_inicial / c.smlmv_suscripcion) * 100, 2) as adiciones_pct_smlmv,
       coalesce(x.facturado, 0) as facturado,
       coalesce(x.pagado, 0) as pagado,
       coalesce(x.raciones, 0) as raciones_facturadas,
       case when c.valor_inicial + coalesce(m.adiciones, 0) > 0
            then round(coalesce(x.facturado, 0) / (c.valor_inicial + coalesce(m.adiciones, 0)) * 100, 2) end as agotamiento_pct,
       (c.valor_inicial + coalesce(m.adiciones, 0)) - coalesce(x.facturado, 0) as saldo,
       -- ritmo mensual promedio y fecha estimada de agotamiento
       case when coalesce(x.meses, 0) > 0 and x.facturado > 0
            then round(x.facturado / x.meses, 2) end as ritmo_mensual,
       case when coalesce(x.meses, 0) > 0 and x.facturado > 0
            then (coalesce(x.ultimo_mes, current_date) + interval '1 month' * ceil(((c.valor_inicial + coalesce(m.adiciones, 0)) - x.facturado) / (x.facturado / x.meses)))::date end as fecha_agotamiento_estimada,
       coalesce(s.n_sedes, 0) as n_sedes,
       coalesce(s.cupos, 0) as cupos_referencia,
       greatest(0, coalesce(m.fin_prorrogado, c.fecha_fin_inicial) - current_date) as dias_restantes
  from public.contratos c
  join public.entidades_contratantes e on e.id = c.entidad_id
  left join mods m on m.contrato_id = c.id
  left join ejec x on x.contrato_id = c.id
  left join sedes s on s.contrato_id = c.id;
grant select on public.v_contratos_resumen to authenticated;

-- ---------------------------------------------------------------------
-- 7. Crear contrato con consecutivo (RPC)
-- ---------------------------------------------------------------------
create or replace function public.crear_contrato(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_id uuid; v_cod text;
begin
  if not (public.es_superadmin() or public.tiene_permiso(v_emp, 'M1', 'crear')) then
    raise exception 'Sin permiso para crear contratos (Contratos: crear).';
  end if;
  v_cod := public.siguiente_consecutivo(v_emp, 'CT');
  insert into public.contratos (empresa_id, codigo, numero, entidad_id, modalidad, objeto, obligaciones, proceso_secop, interventoria,
    supervisor_entidad, valor_inicial, incluye_iva, fecha_suscripcion, fecha_inicio, fecha_fin_inicial, dias_atencion, tiempos_comida,
    n_menus_ciclo, ciclo_reparto, dias_subsanacion, poliza_cumplimiento, estado, notas)
  values (v_emp, v_cod, p->>'numero', (p->>'entidad_id')::uuid, p->>'modalidad', p->>'objeto', p->>'obligaciones', p->>'proceso_secop', p->>'interventoria',
    p->>'supervisor_entidad', (p->>'valor_inicial')::numeric, coalesce((p->>'incluye_iva')::boolean, false), (p->>'fecha_suscripcion')::date,
    (p->>'fecha_inicio')::date, (p->>'fecha_fin_inicial')::date, coalesce(p->>'dias_atencion', 'habiles'), coalesce((p->>'tiempos_comida')::int, 1),
    (p->>'n_menus_ciclo')::int, coalesce(p->>'ciclo_reparto', 'semanal'), coalesce((p->>'dias_subsanacion')::int, 3), p->>'poliza_cumplimiento',
    coalesce(p->>'estado', 'borrador'), p->>'notas')
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.crear_contrato(jsonb) from public, anon;
grant execute on function public.crear_contrato(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 8. Triggers de auditoria y RLS (M1)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['entidades_contratantes','contratos','contrato_modificaciones','contrato_sedes','contrato_ejecucion'] loop
    execute format('create trigger %I_actualizacion before update on public.%I for each row execute function public.marcar_actualizacion()', t, t);
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I_ver on public.%I for select to authenticated using (public.es_superadmin() or (public.es_miembro(empresa_id) and public.tiene_permiso(empresa_id, ''M1'', ''ver'')))', t, t);
    execute format('create policy %I_crear on public.%I for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M1'', ''crear''))', t, t);
    execute format('create policy %I_editar on public.%I for update to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M1'', ''editar'')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M1'', ''editar''))', t, t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
  end loop;
end $$;
-- la ejecucion mensual tambien la carga contabilidad (M9 crear) aunque no tenga M1 crear
create policy contrato_ejecucion_crear_m9 on public.contrato_ejecucion for insert to authenticated
  with check (public.tiene_permiso(empresa_id, 'M9', 'crear'));
create policy contrato_ejecucion_editar_m9 on public.contrato_ejecucion for update to authenticated
  using (public.tiene_permiso(empresa_id, 'M9', 'editar')) with check (public.tiene_permiso(empresa_id, 'M9', 'editar'));
