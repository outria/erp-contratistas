-- =====================================================================
-- Supply ERP · Migracion 006 · M2 Planeacion: productos, minutas, ciclos, dietas, cupos y explosion
-- Diseñada para cualquier modalidad (USPEC/PPL, PAE, ICBF, fuerzas, casinos, adulto mayor...):
--   * Grupos de poblacion por contrato (sexo en PPL, grupo etario en PAE, otros).
--   * Variantes de racion (ERON, estacion de policia sin sopa, remision, gestante, festivo...).
--   * Minuta patron = servido MINIMO contractual por componente y grupo, con crudo de referencia.
--   * Ajustes de gramaje (mas o menos crudo/servido) solo por roles con M2 aprobar; quedan en bitacora.
--   * Rendimiento crudo->servido parametrizable por producto (arroz premium 3,6 vs estandar 2,3).
--   * Preparaciones (recetas) con ingredientes y peso bruto por grupo de poblacion.
--   * Ciclos de N menus (15, 18, 20, 21...) con modo de reinicio y avance solo en dias de servicio.
--   * Dietas: catalogo oficial (20 USPEC) + reglas cuantificables + modo unificado por contrato.
--   * Cupos por periodo y parte diario por sede, grupo y variante; poblacion en dieta por periodo.
--   * Explosion de materiales por rango de fechas: linea = cupos - dietas; dietas segun reglas.
--   * Calculo inverso: hasta que fecha rinde una cantidad de un producto.
-- Reglas dictadas por Osvaldo el 31-oct-2026 (ver CONTROL_DE_CAMBIOS).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Productos (materia prima) y rendimientos  [M13 maestros, minimo para M2]
-- ---------------------------------------------------------------------
create table public.productos (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  codigo             text not null,
  nombre             text not null,
  categoria          text not null default 'abarrotes'
                     check (categoria in ('proteinas','fruver','lacteos','abarrotes','panaderia','bebidas','aseo','desechables','otros')),
  unidad_base        text not null default 'g' check (unidad_base in ('g','ml','und')),
  unidad_compra      text not null default 'kg',          -- kg, l, und, bulto, caja...
  factor_compra      numeric(14,4) not null default 1000,  -- cuantas unidades base trae una unidad de compra (kg = 1000 g)
  codigo_tcac        text,
  nivel_riesgo       text check (nivel_riesgo in ('alto','medio','bajo')),
  prohibido          boolean not null default false,       -- lista roja del contrato (N-N010)
  restringido        boolean not null default false,
  rendimiento        numeric(8,4),                          -- servido / crudo por defecto (ej. arroz 2,3). null = usa minuta
  merma_pct          numeric(6,3),                          -- merma de porcionado en %, si aplica
  perecedero         boolean not null default false,
  dias_vida_util     int,
  estado             text not null default 'activo' check (estado in ('activo','inactivo')),
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now(),
  actualizado_por    uuid references auth.users(id),
  actualizado_en     timestamptz not null default now(),
  unique (empresa_id, codigo)
);
create index productos_empresa_nombre_idx on public.productos (empresa_id, nombre);

-- rendimiento por producto y metodo de coccion (N-N000); gana a productos.rendimiento cuando existe
create table public.factores_coccion (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  producto_id   uuid not null references public.productos(id),
  metodo        text not null,                              -- cocido, asado, horneado, frito, revuelto, porcion, entera, pulpa
  factor        numeric(8,4) not null check (factor > 0),   -- servido = crudo * factor
  fuente        text,
  unique (producto_id, metodo)
);

-- ---------------------------------------------------------------------
-- 2. Estructura del contrato: tiempos, grupos de poblacion, componentes, variantes
-- ---------------------------------------------------------------------
create table public.tiempos_comida (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  codigo          text not null,            -- DES, ALM, CEN, REF, RG1...
  nombre          text not null,
  orden           int not null default 1,
  hora_inicio     time,
  hora_fin        time,
  facturable      boolean not null default true,     -- el refrigerio USPEC se factura aparte
  cambiable_especial boolean not null default true,  -- el refrigerio USPEC no se puede cambiar en menus especiales
  unique (contrato_id, codigo)
);

create table public.grupos_poblacion (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  codigo          text not null,            -- H, M | PRE, P1_3, P4_5, S6_9, M10_11
  nombre          text not null,
  tipo            text not null default 'sexo' check (tipo in ('sexo','etario','otro')),
  orden           int not null default 1,
  unique (contrato_id, codigo)
);

create table public.componentes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  tiempo_comida_id uuid not null references public.tiempos_comida(id),
  codigo          text not null,            -- FRUTA, PROTEICO, CEREAL, BEBIDA, SOPA, TUBERCULO, VERDURA, JUGO, POSTRE...
  nombre          text not null,
  orden           int not null default 1,
  obligatorio     boolean not null default true,
  unique (contrato_id, tiempo_comida_id, codigo)
);

-- variantes de racion: ESTANDAR (ERON), EP (estacion de policia, sin sopa), REMISION, GESTANTE_T1.., FESTIVO, INDUSTRIALIZADA, RPS...
create table public.variantes_racion (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  codigo          text not null,
  nombre          text not null,
  base_id         uuid references public.variantes_racion(id),  -- de cual hereda lo que no redefine
  es_estandar     boolean not null default false,
  componentes_excluidos text[] not null default '{}',             -- codigos de componente que no lleva (EP: SOPA)
  descripcion     text,
  unique (contrato_id, codigo)
);

-- ---------------------------------------------------------------------
-- 3. Minuta patron (servido minimo contractual) y ajustes de gramaje
-- ---------------------------------------------------------------------
create table public.minuta_patron (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_id        uuid not null references public.contratos(id),
  variante_id        uuid references public.variantes_racion(id),   -- null = aplica a la estandar
  grupo_poblacion_id uuid references public.grupos_poblacion(id),   -- null = todos los grupos
  componente_id      uuid not null references public.componentes(id),
  producto_id        uuid references public.productos(id),          -- alimento concreto (res, pechuga...) o null = el componente en general
  metodo_coccion     text,
  porcion_servida    numeric(10,2) not null,   -- gramaje minimo obligatorio (g o ml)
  unidad             text not null default 'g' check (unidad in ('g','ml','und')),
  peso_bruto_ref     numeric(10,2),            -- crudo de referencia del anexo
  medida_casera      text,
  fuente             text,                     -- 'Anexo 4 N-N001 fila 52'
  unique nulls not distinct (contrato_id, variante_id, grupo_poblacion_id, componente_id, producto_id, metodo_coccion)
);

-- Ajuste de lo que realmente se entrega (mas o menos que la minuta). Solo M2 aprobar (roles altos).
create table public.gramajes_ajuste (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_id        uuid not null references public.contratos(id),
  contrato_sede_id   uuid references public.contrato_sedes(id),     -- null = todas las sedes del contrato
  grupo_poblacion_id uuid references public.grupos_poblacion(id),
  componente_id      uuid references public.componentes(id),
  producto_id        uuid references public.productos(id),
  preparacion_id     uuid,                                            -- se enlaza abajo (fk diferida tras crear preparaciones)
  porcion_servida    numeric(10,2),             -- servido que se entrega (puede ser > minuta por presion de la poblacion)
  peso_bruto         numeric(10,2),             -- crudo que se usa (puede ser < referencia por mejor rendimiento)
  factor_crudo       numeric(8,4),              -- alternativa: multiplicar el crudo de la receta por este factor
  motivo             text not null,
  vigente_desde      date not null default current_date,
  vigente_hasta      date,
  aprobado_por       uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now()
);
create index gramajes_ajuste_idx on public.gramajes_ajuste (contrato_id, vigente_desde);

-- ---------------------------------------------------------------------
-- 4. Preparaciones (recetas) e ingredientes
-- ---------------------------------------------------------------------
create table public.preparaciones (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid references public.contratos(id),         -- null = receta de la empresa reutilizable en cualquier contrato
  codigo          text not null,
  nombre          text not null,
  componente_codigo text,                                        -- PROTEICO, SOPA, JUGO... (para sugerir en el ciclo)
  metodo_coccion  text,
  procedimiento   text,
  restringida     boolean not null default false,
  rendimiento_porciones int,                                     -- si la receta se formula por tanda
  estado          text not null default 'activa' check (estado in ('activa','inactiva')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique nulls not distinct (empresa_id, contrato_id, codigo)
);
alter table public.gramajes_ajuste add constraint gramajes_ajuste_preparacion_fk foreign key (preparacion_id) references public.preparaciones(id);

create table public.preparacion_ingredientes (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  preparacion_id     uuid not null references public.preparaciones(id) on delete cascade,
  producto_id        uuid not null references public.productos(id),
  grupo_poblacion_id uuid references public.grupos_poblacion(id),   -- null = todos (una fila por grupo cuando el crudo difiere, H/M)
  peso_bruto         numeric(10,3) not null check (peso_bruto >= 0),  -- crudo por racion, en unidad base del producto
  es_principal       boolean not null default false,                 -- el ingrediente que define el componente (la proteina del proteico)
  opcional           boolean not null default false,
  orden              int not null default 1,
  unique nulls not distinct (preparacion_id, producto_id, grupo_poblacion_id)
);

-- ---------------------------------------------------------------------
-- 5. Ciclos de menu, reglas de rotacion, asignacion a sedes y excepciones
-- ---------------------------------------------------------------------
create table public.ciclos_menu (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  codigo          text not null,
  nombre          text not null,
  n_menus         int not null check (n_menus between 1 and 90),
  variante_id     uuid references public.variantes_racion(id),   -- ciclo propio de una variante (EP) o null = estandar
  tipo            text not null default 'estandar' check (tipo in ('estandar','propuesto','aprobado','especial')),
  vigente_desde   date,
  vigente_hasta   date,                                            -- la Armada cambia el ciclo completo cada 3 meses
  oficio_aprobacion text,
  estado          text not null default 'borrador' check (estado in ('borrador','vigente','historico','anulado')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (contrato_id, codigo)
);

create table public.ciclo_menu_items (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  ciclo_id        uuid not null references public.ciclos_menu(id) on delete cascade,
  dia             int not null check (dia >= 1),
  tiempo_comida_id uuid not null references public.tiempos_comida(id),
  componente_id   uuid not null references public.componentes(id),
  preparacion_id  uuid references public.preparaciones(id),       -- null mientras el descriptor sea generico ("SOPA O CREMA")
  descriptor      text,
  unique (ciclo_id, dia, tiempo_comida_id, componente_id)
);
create index ciclo_menu_items_idx on public.ciclo_menu_items (ciclo_id, dia);

-- reglas de variedad por componente (frutas 4 distintas/semana, postres 4 sin repetir 4 dias...) parametrizables por contrato
create table public.reglas_rotacion (
  id                      uuid primary key default gen_random_uuid(),
  empresa_id              uuid not null references public.empresas(id),
  contrato_id             uuid not null references public.contratos(id),
  componente_codigo       text not null,
  min_variedades_semana   int,
  max_dias_consecutivos   int,
  ventana_no_repetir_dias int,
  nota                    text,
  unique (contrato_id, componente_codigo)
);

-- como corre el ciclo en cada sede: desde que fecha arranca el menu 1, como reinicia y si avanza en dias sin servicio
create table public.sede_ciclo (
  id                    uuid primary key default gen_random_uuid(),
  empresa_id            uuid not null references public.empresas(id),
  contrato_sede_id      uuid not null references public.contrato_sedes(id),
  ciclo_id              uuid not null references public.ciclos_menu(id),
  variante_id           uuid references public.variantes_racion(id),   -- variante que recibe esta sede (EP, ESTANDAR)
  fecha_inicio_menu1    date not null,
  modo_reinicio         text not null default 'continuo' check (modo_reinicio in ('continuo','mensual','semanal')),
  avanza_sin_servicio   boolean not null default true,  -- USPEC si (7 dias); PAE no (solo dias de clase)
  vigente_desde         date not null,
  vigente_hasta         date,
  menu_confirmado       boolean not null default false,
  creado_por            uuid references auth.users(id) default auth.uid(),
  creado_en             timestamptz not null default now()
);
create index sede_ciclo_idx on public.sede_ciclo (contrato_sede_id, vigente_desde);

-- dias sin servicio o con servicio excepcional (PAE: paro, acto civico, vacaciones; festivos sin atencion)
create table public.calendario_servicio (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas(id),
  contrato_id       uuid not null references public.contratos(id),
  contrato_sede_id  uuid references public.contrato_sedes(id),  -- null = todo el contrato
  fecha             date not null,
  atiende           boolean not null,
  motivo            text,
  creado_por        uuid references auth.users(id) default auth.uid(),
  creado_en         timestamptz not null default now()
);
create index calendario_servicio_idx on public.calendario_servicio (contrato_id, fecha);

-- excepciones de menu: festivo (ciclo especial), menu especial concertado, emergencia, intercambio puntual
create table public.menu_excepciones (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas(id),
  contrato_id       uuid not null references public.contratos(id),
  contrato_sede_id  uuid references public.contrato_sedes(id),   -- null = todas las sedes
  fecha             date not null,
  tipo              text not null check (tipo in ('festivo','especial','emergencia','intercambio','dia_forzado')),
  dia_ciclo_forzado int,                                           -- dia_forzado: usar este dia del ciclo
  ciclo_alterno_id  uuid references public.ciclos_menu(id),       -- festivo/especial: ciclo especial completo (dia 1)
  tiempo_comida_id  uuid references public.tiempos_comida(id),    -- intercambio puntual: que tiempo
  componente_id     uuid references public.componentes(id),
  preparacion_id    uuid references public.preparaciones(id),     -- preparacion que reemplaza
  motivo            text,
  soporte           text,                                          -- correo u oficio
  aprobado          boolean not null default false,
  creado_por        uuid references auth.users(id) default auth.uid(),
  creado_en         timestamptz not null default now()
);
create index menu_excepciones_idx on public.menu_excepciones (contrato_id, fecha);

-- ---------------------------------------------------------------------
-- 6. Dietas: catalogo, reglas, equivalencias y poblacion en dieta
-- ---------------------------------------------------------------------
create table public.tipos_dieta (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid references public.empresas(id),      -- null = catalogo de la plataforma (USPEC 2025)
  codigo          text not null,
  nombre_oficial  text not null,
  categoria       text not null check (categoria in ('consistencia','macronutrientes','micronutrientes','especial','fisiologica','otra')),
  tiempos_adicionales int not null default 0,                -- hipoglucida y gestantes: 6 tiempos
  descripcion     text,
  unique nulls not distinct (empresa_id, codigo)
);

-- reglas cuantificables que derivan la dieta del menu de linea
create table public.reglas_dieta (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid references public.empresas(id),    -- null = regla del catalogo
  contrato_id        uuid references public.contratos(id),   -- regla acordada para un contrato (gana sobre el catalogo)
  tipo_dieta_id      uuid not null references public.tipos_dieta(id),
  tipo_regla         text not null check (tipo_regla in ('factor_porcion','porcion_fija','excluir_componente','excluir_producto','excluir_categoria','sustituir_producto','metodo_prohibido','tiempo_adicional')),
  componente_codigo  text,            -- PROTEICO, SOPA, POSTRE...
  producto_id        uuid references public.productos(id),
  categoria_producto text,
  valor              numeric(10,3),   -- factor (1,40), porcion fija (50), tiempos (3)
  producto_sustituto_id uuid references public.productos(id),
  metodo             text,
  nota               text,
  activa             boolean not null default true
);
create index reglas_dieta_idx on public.reglas_dieta (tipo_dieta_id, contrato_id);

-- Modo de manejo por contrato: unificar varias dietas en una sola receta/materia prima por componente
create table public.dieta_equivalencias (
  id                   uuid primary key default gen_random_uuid(),
  empresa_id           uuid not null references public.empresas(id),
  contrato_id          uuid not null references public.contratos(id),
  tipo_dieta_id        uuid not null references public.tipos_dieta(id),   -- la dieta reportada
  equivale_a_id        uuid references public.tipos_dieta(id),            -- se explota como esta otra (null = como linea)
  preparacion_proteico_id uuid references public.preparaciones(id),       -- p. ej. pechuga para todas las que no comen carne roja
  nota                 text,
  unique (contrato_id, tipo_dieta_id)
);

-- poblacion en dieta por sede y periodo (el detalle por PPL llega con M7/M11)
create table public.dietas_poblacion (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_sede_id   uuid not null references public.contrato_sedes(id),
  tipo_dieta_id      uuid not null references public.tipos_dieta(id),
  grupo_poblacion_id uuid references public.grupos_poblacion(id),
  fecha_desde        date not null,
  fecha_hasta        date,
  cantidad           int not null check (cantidad >= 0),
  fuente             text,                 -- BD mensual de dietas, reporte de sanidad
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now()
);
create index dietas_poblacion_idx on public.dietas_poblacion (contrato_sede_id, fecha_desde);

-- ---------------------------------------------------------------------
-- 7. Cupos por periodo y parte diario
-- ---------------------------------------------------------------------
create table public.cupos (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_sede_id   uuid not null references public.contrato_sedes(id),
  grupo_poblacion_id uuid not null references public.grupos_poblacion(id),
  variante_id        uuid references public.variantes_racion(id),    -- null = estandar de la sede
  tiempo_comida_id   uuid references public.tiempos_comida(id),      -- null = todos los tiempos
  fecha_desde        date not null,
  fecha_hasta        date,
  cantidad           int not null check (cantidad >= 0),
  fuente             text,                  -- contrato, oficio, parte INPEC, SIMAT
  documento          text,
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now()
);
create index cupos_idx on public.cupos (contrato_sede_id, fecha_desde);

-- parte diario real (foto del tablero, parte de guardia, asistencia escolar): gana sobre cupos para esa fecha
create table public.partes_diarios (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  contrato_sede_id   uuid not null references public.contrato_sedes(id),
  fecha              date not null,
  grupo_poblacion_id uuid not null references public.grupos_poblacion(id),
  variante_id        uuid references public.variantes_racion(id),
  tiempo_comida_id   uuid references public.tiempos_comida(id),
  cantidad           int not null check (cantidad >= 0),
  fuente             text,
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now(),
  unique nulls not distinct (contrato_sede_id, fecha, grupo_poblacion_id, variante_id, tiempo_comida_id)
);

-- ---------------------------------------------------------------------
-- 8. Funciones de calendario: dia de servicio y menu del dia
-- ---------------------------------------------------------------------
create or replace function public.es_dia_servicio(p_contrato uuid, p_contrato_sede uuid, p_fecha date)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_dias text; v_exc boolean;
begin
  -- excepcion explicita (sede primero, luego contrato)
  select atiende into v_exc from public.calendario_servicio
   where contrato_id = p_contrato and fecha = p_fecha and (contrato_sede_id = p_contrato_sede or contrato_sede_id is null)
   order by contrato_sede_id nulls last limit 1;
  if found then return v_exc; end if;
  select dias_atencion into v_dias from public.contratos where id = p_contrato;
  if v_dias = 'todos' then return true; end if;
  if v_dias = 'habiles' then return extract(isodow from p_fecha) between 1 and 5; end if;
  return true; -- calendario_propio: se gobierna solo con calendario_servicio
end $$;

-- Dia del ciclo que corresponde a una fecha en una sede (null si no hay servicio o no hay ciclo asignado)
create or replace function public.dia_ciclo(p_contrato_sede uuid, p_fecha date)
returns table (ciclo_id uuid, dia int, variante_id uuid) language plpgsql stable security definer set search_path = public as $$
declare sc record; v_contrato uuid; v_n int; v_pos int; d date; v_ancla date; v_exc record;
begin
  select cs.contrato_id into v_contrato from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if not public.es_dia_servicio(v_contrato, p_contrato_sede, p_fecha) then return; end if;

  -- excepciones de dia completo
  select * into v_exc from public.menu_excepciones e
   where e.contrato_id = v_contrato and e.fecha = p_fecha and (e.contrato_sede_id = p_contrato_sede or e.contrato_sede_id is null)
     and e.tipo in ('festivo','especial','emergencia','dia_forzado') and e.aprobado
   order by e.contrato_sede_id nulls last limit 1;

  select * into sc from public.sede_ciclo s
   where s.contrato_sede_id = p_contrato_sede and s.vigente_desde <= p_fecha and (s.vigente_hasta is null or s.vigente_hasta >= p_fecha)
   order by s.vigente_desde desc limit 1;
  if sc.id is null then return; end if;

  if v_exc.id is not null and v_exc.ciclo_alterno_id is not null then
    return query select v_exc.ciclo_alterno_id, 1, sc.variante_id; return;
  end if;
  if v_exc.id is not null and v_exc.dia_ciclo_forzado is not null then
    return query select sc.ciclo_id, v_exc.dia_ciclo_forzado, sc.variante_id; return;
  end if;

  select n_menus into v_n from public.ciclos_menu where id = sc.ciclo_id;
  -- ancla: desde donde se cuenta el menu 1
  v_ancla := sc.fecha_inicio_menu1;
  if sc.modo_reinicio = 'mensual' then v_ancla := greatest(sc.fecha_inicio_menu1, date_trunc('month', p_fecha)::date); end if;
  if sc.modo_reinicio = 'semanal' then v_ancla := greatest(sc.fecha_inicio_menu1, date_trunc('week', p_fecha)::date); end if;
  if p_fecha < v_ancla then return; end if;

  if sc.avanza_sin_servicio then
    v_pos := (p_fecha - v_ancla);
  else
    -- solo cuentan los dias con servicio (PAE)
    v_pos := 0; d := v_ancla;
    while d < p_fecha loop
      if public.es_dia_servicio(v_contrato, p_contrato_sede, d) then v_pos := v_pos + 1; end if;
      d := d + 1;
    end loop;
  end if;
  return query select sc.ciclo_id, (v_pos % v_n) + 1, sc.variante_id;
end $$;

-- Menu del dia: cada componente de cada tiempo con su preparacion (aplica intercambios puntuales)
create or replace function public.menu_del_dia(p_contrato_sede uuid, p_fecha date)
returns table (ciclo_id uuid, dia int, variante_id uuid, tiempo_comida_id uuid, tiempo_codigo text, tiempo_orden int,
               componente_id uuid, componente_codigo text, preparacion_id uuid, preparacion_nombre text, descriptor text, origen text)
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
       )
  select b.ciclo_id, b.dia, b.variante_id, b.tiempo_comida_id, b.codigo, b.orden, b.componente_id, b.ccod,
         coalesce(x.preparacion_id, b.preparacion_id) as preparacion_id,
         p.nombre, b.descriptor,
         case when x.id is not null then 'intercambio' else 'ciclo' end as origen
    from base b
    left join public.menu_excepciones x on x.contrato_id = (select contrato_id from cs) and x.fecha = p_fecha and x.aprobado
         and x.tipo = 'intercambio' and (x.contrato_sede_id = p_contrato_sede or x.contrato_sede_id is null)
         and x.tiempo_comida_id = b.tiempo_comida_id and x.componente_id = b.componente_id
    left join public.preparaciones p on p.id = coalesce(x.preparacion_id, b.preparacion_id)
   order by b.orden, b.ccod;
$$;

-- Poblacion de una sede en una fecha: parte diario si existe, si no el cupo vigente. Resta la poblacion en dieta -> linea
create or replace function public.poblacion_dia(p_contrato_sede uuid, p_fecha date)
returns table (grupo_poblacion_id uuid, variante_id uuid, total int, en_dieta int, linea int) language sql stable security definer set search_path = public as $$
  with p as (
    select pd.grupo_poblacion_id, pd.variante_id, sum(pd.cantidad)::int as total
      from public.partes_diarios pd
     where pd.contrato_sede_id = p_contrato_sede and pd.fecha = p_fecha and pd.tiempo_comida_id is null
     group by pd.grupo_poblacion_id, pd.variante_id
  ), c as (
    select cu.grupo_poblacion_id, cu.variante_id, sum(cu.cantidad)::int as total
      from public.cupos cu
     where cu.contrato_sede_id = p_contrato_sede and cu.tiempo_comida_id is null
       and cu.fecha_desde <= p_fecha and (cu.fecha_hasta is null or cu.fecha_hasta >= p_fecha)
     group by cu.grupo_poblacion_id, cu.variante_id
  ), base as (
    select * from p union all select * from c where not exists (select 1 from p)
  ), d as (
    select dp.grupo_poblacion_id, sum(dp.cantidad)::int as en_dieta
      from public.dietas_poblacion dp
     where dp.contrato_sede_id = p_contrato_sede and dp.fecha_desde <= p_fecha and (dp.fecha_hasta is null or dp.fecha_hasta >= p_fecha)
     group by dp.grupo_poblacion_id
  )
  select b.grupo_poblacion_id, b.variante_id, b.total,
         coalesce(d.en_dieta, 0) as en_dieta,
         greatest(0, b.total - coalesce(d.en_dieta, 0)) as linea
    from base b left join d on d.grupo_poblacion_id = b.grupo_poblacion_id;
$$;

-- ---------------------------------------------------------------------
-- 9. Explosion de materiales
-- ---------------------------------------------------------------------
create table public.explosiones (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  contrato_id     uuid not null references public.contratos(id),
  codigo          text not null,
  nombre          text,
  fecha_desde     date not null,
  fecha_hasta     date not null,
  sedes           uuid[],                                   -- null = todas las sedes activas del contrato
  incluye_dietas  boolean not null default true,
  modo_presupuesto text not null default 'ninguno' check (modo_presupuesto in ('ninguno','ultimo_precio','media_3','moda_3')),
  estado          text not null default 'borrador' check (estado in ('borrador','calculada','aprobada','enviada_compras','anulada')),
  raciones        int,
  calculada_en    timestamptz,
  notas           text,
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  check (fecha_hasta >= fecha_desde),
  unique (empresa_id, codigo)
);

create table public.explosion_detalle (
  id                 bigint generated always as identity primary key,
  empresa_id         uuid not null references public.empresas(id),
  explosion_id       uuid not null references public.explosiones(id) on delete cascade,
  contrato_sede_id   uuid not null references public.contrato_sedes(id),
  fecha              date not null,
  dia_ciclo          int,
  tiempo_comida_id   uuid not null references public.tiempos_comida(id),
  componente_id      uuid not null references public.componentes(id),
  preparacion_id     uuid references public.preparaciones(id),
  producto_id        uuid not null references public.productos(id),
  grupo_poblacion_id uuid references public.grupos_poblacion(id),
  tipo_dieta_id      uuid references public.tipos_dieta(id),      -- null = linea
  raciones           int not null,
  crudo_por_racion   numeric(12,4) not null,                       -- ya con ajustes y reglas de dieta
  cantidad_bruta     numeric(16,3) not null,                       -- raciones * crudo_por_racion (unidad base del producto)
  ajuste_aplicado    text                                          -- 'ajuste gramaje' | 'dieta: factor 1.4' | ...
);
create index explosion_detalle_idx on public.explosion_detalle (explosion_id, producto_id);
create index explosion_detalle_fecha_idx on public.explosion_detalle (explosion_id, fecha, contrato_sede_id);

-- crudo efectivo de un ingrediente para un grupo, con ajustes de gramaje vigentes (sede > contrato) y rendimiento por producto
create or replace function public.crudo_ingrediente(
  p_contrato uuid, p_contrato_sede uuid, p_fecha date, p_preparacion uuid, p_producto uuid, p_grupo uuid, p_componente uuid,
  p_peso_bruto numeric
) returns table (crudo numeric, nota text) language plpgsql stable security definer set search_path = public as $$
declare a record; v numeric := p_peso_bruto; n text := null;
begin
  select * into a from public.gramajes_ajuste g
   where g.contrato_id = p_contrato
     and (g.contrato_sede_id = p_contrato_sede or g.contrato_sede_id is null)
     and (g.grupo_poblacion_id = p_grupo or g.grupo_poblacion_id is null)
     and (g.producto_id = p_producto or (g.producto_id is null and g.preparacion_id = p_preparacion) or (g.producto_id is null and g.preparacion_id is null and g.componente_id = p_componente))
     and g.vigente_desde <= p_fecha and (g.vigente_hasta is null or g.vigente_hasta >= p_fecha)
   order by g.contrato_sede_id nulls last, g.producto_id nulls last, g.grupo_poblacion_id nulls last, g.vigente_desde desc
   limit 1;
  if a.id is not null then
    if a.peso_bruto is not null then v := a.peso_bruto; n := 'ajuste crudo';
    elsif a.factor_crudo is not null then v := p_peso_bruto * a.factor_crudo; n := 'ajuste factor ' || a.factor_crudo;
    elsif a.porcion_servida is not null then
      -- servido ajustado -> crudo con el rendimiento del producto (factor de coccion o rendimiento general)
      v := a.porcion_servida / coalesce(
             (select f.factor from public.factores_coccion f join public.preparaciones pp on pp.id = p_preparacion where f.producto_id = p_producto and f.metodo = pp.metodo_coccion limit 1),
             (select rendimiento from public.productos where id = p_producto), 1);
      n := 'ajuste servido ' || a.porcion_servida;
    end if;
  end if;
  return query select v, n;
end $$;

-- Calcula (o recalcula) la explosion: borra el detalle y lo vuelve a generar
create or replace function public.calcular_explosion(p_explosion uuid)
returns table (filas int, raciones int, productos int) language plpgsql security definer set search_path = public as $$
declare e public.explosiones; s record; d date; m record; pob record; ing record; cr record; dd record; r record;
        v_emp uuid; v_rac int := 0; v_filas int := 0; v_crudo numeric; v_nota text; v_rac_dieta int; v_eq record; v_prep uuid; v_excl boolean; v_factor numeric; v_fija numeric; v_sust uuid;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then
    raise exception 'Sin permiso para calcular explosiones (Planeacion: crear).';
  end if;
  v_emp := e.empresa_id;
  delete from public.explosion_detalle where explosion_id = p_explosion;

  for s in select cs.* from public.contrato_sedes cs
            where cs.contrato_id = e.contrato_id and cs.estado = 'activa'
              and (e.sedes is null or cs.id = any (e.sedes)) loop
    d := e.fecha_desde;
    while d <= e.fecha_hasta loop
      for m in select * from public.menu_del_dia(s.id, d) loop
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
              insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
              values (v_emp, p_explosion, s.id, d, m.dia, m.tiempo_comida_id, m.componente_id, m.preparacion_id, ing.producto_id, pob.grupo_poblacion_id, null, pob.linea, cr.crudo, pob.linea * cr.crudo, cr.nota);
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

-- Resumen por producto (lo que compras necesita), con stock por ahora en 0 (llega con M5)
create or replace view public.v_explosion_productos with (security_invoker = on) as
select d.explosion_id, d.empresa_id, d.producto_id, p.codigo, p.nombre, p.categoria, p.unidad_base, p.unidad_compra, p.factor_compra,
       sum(d.cantidad_bruta) as cantidad_base,
       round(sum(d.cantidad_bruta) / nullif(p.factor_compra, 0), 3) as cantidad_compra,
       sum(d.cantidad_bruta) filter (where d.tipo_dieta_id is null) as de_linea,
       sum(d.cantidad_bruta) filter (where d.tipo_dieta_id is not null) as de_dietas,
       count(distinct d.fecha) as dias,
       round(sum(d.cantidad_bruta) / nullif(count(distinct d.fecha), 0), 3) as promedio_dia
  from public.explosion_detalle d join public.productos p on p.id = d.producto_id
 group by d.explosion_id, d.empresa_id, d.producto_id, p.codigo, p.nombre, p.categoria, p.unidad_base, p.unidad_compra, p.factor_compra;
grant select on public.v_explosion_productos to authenticated;

-- Alertas de la explosion: menus sin receta (descriptor generico), sedes sin ciclo, sedes sin cupos
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
      for m in select * from public.menu_del_dia(s.id, d) where preparacion_id is null loop
        tipo := 'sin_receta'; detalle := m.tiempo_codigo || ' · ' || m.componente_codigo || ' · ' || coalesce(m.descriptor, '(vacio)') || ' (dia ' || m.dia || ')'; fecha := d; sede := s.nombre; return next;
      end loop;
      d := d + 1;
    end loop;
  end loop;
end $$;

-- Calculo inverso: con p_cantidad (unidad base) de un producto, hasta que fecha alcanza.
-- Simula dia a dia hasta p_dias_simulados (por defecto un ciclo largo de 35 dias) y, si no se agota, extrapola con el promedio diario.
create or replace function public.calculo_inverso(p_contrato uuid, p_producto uuid, p_cantidad numeric, p_desde date, p_sedes uuid[] default null, p_dias_simulados int default 35, p_max_dias int default 730)
returns table (fecha_hasta date, dias int, consumo_diario_promedio numeric, consumo_total numeric, extrapolado boolean) language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_emp uuid; acum numeric := 0; n int := 0; dia_cons numeric; prom numeric; extra int := 0;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  insert into public.explosiones (empresa_id, contrato_id, codigo, nombre, fecha_desde, fecha_hasta, sedes, estado)
  values (v_emp, p_contrato, 'TMP-' || substr(gen_random_uuid()::text, 1, 8), 'calculo inverso temporal', p_desde, p_desde + p_dias_simulados - 1, p_sedes, 'borrador') returning id into v_id;
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

-- ---------------------------------------------------------------------
-- 10. Catalogo de dietas USPEC 2025 (plataforma) con reglas base del Manual de Dietas
-- ---------------------------------------------------------------------
insert into public.tipos_dieta (empresa_id, codigo, nombre_oficial, categoria, tiempos_adicionales, descripcion) values
  (null, 'LIQ_CLARA',      'Dieta Liquida Clara',                 'consistencia', 0, 'Transicion 24-48 h; 5-7 tomas; sin fibra, condimentos ni lacteos'),
  (null, 'LIQ_COMPLETA',   'Dieta Liquida Completa',              'consistencia', 0, 'Todo liquido, nutricionalmente adecuada'),
  (null, 'BLANDA',         'Dieta Blanda',                        'consistencia', 0, 'Sin fritos, tostadas, calados, verdura cruda; carne mechada o molida'),
  (null, 'SEMIBLANDA',     'Dieta Semi Blanda',                   'consistencia', 0, 'Pures, souffles, sopas licuadas'),
  (null, 'HIPOCALORICA',   'Dieta Hipocalorica',                  'macronutrientes', 0, 'Restringe hasta 20 % del VCT; sin azucar, panela ni miel'),
  (null, 'HIPOGRASA',      'Dieta Hipograsa',                     'macronutrientes', 0, 'Grasa 20 % VCT; sin fritos ni grasas saturadas'),
  (null, 'HIPERCALORICA',  'Dieta Hipercalorica',                 'macronutrientes', 0, '+20 % VCT'),
  (null, 'HIPERCAL_HIPERPROT', 'Dieta Hipercalorica e Hiperproteica', 'macronutrientes', 0, '+20 % VCT; proteina hasta 15 %'),
  (null, 'HIPOGLUCIDA',    'Dieta Hipoglucida',                   'macronutrientes', 2, 'Fraccionada en 6 tiempos; sin azucar, panela, miel, postres'),
  (null, 'HIPOSODICA',     'Dieta Hiposodica',                    'micronutrientes', 0, 'Sodio 400 / 1.000 / 1.500 mg; sin enlatados, embutidos, pan con sal'),
  (null, 'ALTA_HIERRO',    'Dieta Alta en Hierro',                'micronutrientes', 0, '+40 % porcion de alimentos ricos en hierro hem'),
  (null, 'ASTRINGENTE',    'Dieta Astringente',                   'micronutrientes', 0, 'Leche sin lactosa, sin verdura cruda, sin fritos ni leguminosas'),
  (null, 'ALTA_FIBRA',     'Dieta Alta en Fibra',                 'micronutrientes', 0, 'Mas agua; sin pan blanco ni tuberculo; verduras crudas'),
  (null, 'RENAL',          'Dieta Renal',                         'especial', 0, 'Carnes y pescado 50 g cocido; desayuno proteico 3 veces/semana de 30 g'),
  (null, 'HIPOPURINICA',   'Dieta Hipopurinica',                  'especial', 0, 'Lacteos descremados, menos grasa saturada'),
  (null, 'SIN_IRRITANTES', 'Dieta sin Irritantes Gastricos',      'especial', 0, 'Sin ajo, pimienta, pimenton, embutidos, salsas, frutas acidas, fritos'),
  (null, 'SIN_LACTOSA',    'Dieta Libre de Lactosa',              'especial', 0, 'Yogur, kumis, leche deslactosada o vegetal'),
  (null, 'REFLUJO',        'Reflujo Esofagico',                   'especial', 0, 'Sin chocolate, grasa, ajo, cebolla, citricos, cafe, tomate'),
  (null, 'VEGETARIANA',    'Dieta Vegetariana',                   'especial', 0, 'Ovolacto, lacto, ovo o vegana'),
  (null, 'GESTANTE',       'Gestantes y lactantes',               'fisiologica', 2, '6 tiempos; +150/+350 kcal por trimestre'),
  (null, 'OTRA',           'Otra',                                'otra', 0, 'Definida por el medico tratante');

-- reglas base (catalogo) que se pueden sobreescribir por contrato
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, valor, nota)
select id, 'factor_porcion', 'PROTEICO', 1.40, 'Manual de dietas: +40 % en alimentos ricos en hierro hem' from public.tipos_dieta where empresa_id is null and codigo = 'ALTA_HIERRO';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, valor, nota)
select id, 'factor_porcion', 'PROTEICO', 1.20, 'Hiperproteica: +20 % de proteina (ajustable por acuerdo con la entidad)' from public.tipos_dieta where empresa_id is null and codigo = 'HIPERCAL_HIPERPROT';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, valor, nota)
select id, 'porcion_fija', 'PROTEICO', 50, 'Renal: carnes y pescado 50 g cocido en almuerzo y cena' from public.tipos_dieta where empresa_id is null and codigo = 'RENAL';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, nota)
select id, 'excluir_componente', 'POSTRE', 'Hipoglucida: sin postres ni azucar' from public.tipos_dieta where empresa_id is null and codigo = 'HIPOGLUCIDA';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, nota)
select id, 'excluir_componente', 'POSTRE', 'Hipocalorica: sin postre' from public.tipos_dieta where empresa_id is null and codigo = 'HIPOCALORICA';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, valor, nota)
select id, 'tiempo_adicional', null, 2, 'Hipoglucida: 6 tiempos de comida' from public.tipos_dieta where empresa_id is null and codigo = 'HIPOGLUCIDA';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, componente_codigo, valor, nota)
select id, 'tiempo_adicional', null, 2, 'Gestantes: 3 refrigerios adicionales segun trimestre' from public.tipos_dieta where empresa_id is null and codigo = 'GESTANTE';
insert into public.reglas_dieta (tipo_dieta_id, tipo_regla, categoria_producto, nota)
select id, 'excluir_categoria', 'proteinas', 'Vegetariana: sin carnes (ajustar segun variante)' from public.tipos_dieta where empresa_id is null and codigo = 'VEGETARIANA';

-- ---------------------------------------------------------------------
-- 11. Permisos: M2 planeacion (y M13 para productos). Ajustes de gramaje: solo M2 aprobar.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['tiempos_comida','grupos_poblacion','componentes','variantes_racion','minuta_patron','preparaciones','preparacion_ingredientes',
                           'ciclos_menu','ciclo_menu_items','reglas_rotacion','sede_ciclo','calendario_servicio','menu_excepciones',
                           'dieta_equivalencias','dietas_poblacion','cupos','partes_diarios','explosiones','explosion_detalle'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I_ver on public.%I for select to authenticated using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, ''M2'', ''ver'') or public.tiene_permiso(empresa_id, ''M3'', ''ver'') or public.tiene_permiso(empresa_id, ''M7'', ''ver''))))', t, t);
    execute format('create policy %I_crear on public.%I for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M2'', ''crear''))', t, t);
    execute format('create policy %I_editar on public.%I for update to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M2'', ''editar'')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M2'', ''editar''))', t, t);
    execute format('create policy %I_borrar on public.%I for delete to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M2'', ''anular''))', t, t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
  end loop;
end $$;
-- partes diarios y cupos tambien los carga la sede (M7 crear)
create policy partes_diarios_crear_m7 on public.partes_diarios for insert to authenticated with check (public.tiene_permiso(empresa_id, 'M7', 'crear'));
create policy partes_diarios_editar_m7 on public.partes_diarios for update to authenticated using (public.tiene_permiso(empresa_id, 'M7', 'editar')) with check (public.tiene_permiso(empresa_id, 'M7', 'editar'));

-- ajustes de gramaje: ver con M2, escribir solo con M2 aprobar (director administrativo, planeacion, compras, gerencia)
alter table public.gramajes_ajuste enable row level security;
create policy gramajes_ajuste_ver on public.gramajes_ajuste for select to authenticated using (public.es_superadmin() or (public.es_miembro(empresa_id) and public.tiene_permiso(empresa_id, 'M2', 'ver')));
create policy gramajes_ajuste_crear on public.gramajes_ajuste for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar'));
create policy gramajes_ajuste_editar on public.gramajes_ajuste for update to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar'));
grant select, insert, update on public.gramajes_ajuste to authenticated;
create trigger gramajes_ajuste_bitacora after insert or update or delete on public.gramajes_ajuste for each row execute function public.registrar_bitacora();

-- productos y factores: M13 (maestros) o M2
do $$
declare t text;
begin
  foreach t in array array['productos','factores_coccion'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I_ver on public.%I for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id))', t, t);
    execute format('create policy %I_crear on public.%I for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M13'', ''crear'') or public.tiene_permiso(empresa_id, ''M2'', ''crear''))', t, t);
    execute format('create policy %I_editar on public.%I for update to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M13'', ''editar'') or public.tiene_permiso(empresa_id, ''M2'', ''editar'')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M13'', ''editar'') or public.tiene_permiso(empresa_id, ''M2'', ''editar''))', t, t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
  end loop;
end $$;
create trigger productos_actualizacion before update on public.productos for each row execute function public.marcar_actualizacion();
create trigger preparaciones_actualizacion before update on public.preparaciones for each row execute function public.marcar_actualizacion();
create trigger ciclos_menu_actualizacion before update on public.ciclos_menu for each row execute function public.marcar_actualizacion();
create trigger explosiones_actualizacion before update on public.explosiones for each row execute function public.marcar_actualizacion();

-- catalogo de dietas: lectura para todos; la plataforma (empresa null) solo superadmin; las de empresa con M2
alter table public.tipos_dieta enable row level security;
alter table public.reglas_dieta enable row level security;
create policy tipos_dieta_ver on public.tipos_dieta for select to authenticated using (empresa_id is null or public.es_superadmin() or public.es_miembro(empresa_id));
create policy tipos_dieta_admin on public.tipos_dieta for all to authenticated
  using (public.es_superadmin() or (empresa_id is not null and public.tiene_permiso(empresa_id, 'M2', 'editar')))
  with check (public.es_superadmin() or (empresa_id is not null and public.tiene_permiso(empresa_id, 'M2', 'editar')));
create policy reglas_dieta_ver on public.reglas_dieta for select to authenticated using (empresa_id is null or public.es_superadmin() or public.es_miembro(empresa_id));
create policy reglas_dieta_admin on public.reglas_dieta for all to authenticated
  using (public.es_superadmin() or (empresa_id is not null and public.tiene_permiso(empresa_id, 'M2', 'editar')))
  with check (public.es_superadmin() or (empresa_id is not null and public.tiene_permiso(empresa_id, 'M2', 'editar')));
grant select, insert, update, delete on public.tipos_dieta, public.reglas_dieta to authenticated;

-- crear explosion con consecutivo
create or replace function public.crear_explosion(p_contrato uuid, p_desde date, p_hasta date, p_sedes uuid[] default null, p_incluye_dietas boolean default true, p_modo_presupuesto text default 'ninguno', p_nombre text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'crear')) then
    raise exception 'Sin permiso para crear explosiones (Planeacion: crear).';
  end if;
  insert into public.explosiones (empresa_id, contrato_id, codigo, nombre, fecha_desde, fecha_hasta, sedes, incluye_dietas, modo_presupuesto)
  values (v_emp, p_contrato, public.siguiente_consecutivo(v_emp, 'EXP'), p_nombre, p_desde, p_hasta, p_sedes, p_incluye_dietas, p_modo_presupuesto)
  returning id into v_id;
  return v_id;
end $$;

revoke execute on function public.es_dia_servicio(uuid, uuid, date), public.dia_ciclo(uuid, date), public.menu_del_dia(uuid, date), public.poblacion_dia(uuid, date),
  public.crudo_ingrediente(uuid, uuid, date, uuid, uuid, uuid, uuid, numeric), public.calcular_explosion(uuid), public.alertas_explosion(uuid),
  public.calculo_inverso(uuid, uuid, numeric, date, uuid[], int, int), public.crear_explosion(uuid, date, date, uuid[], boolean, text, text) from public, anon;
grant execute on function public.es_dia_servicio(uuid, uuid, date), public.dia_ciclo(uuid, date), public.menu_del_dia(uuid, date), public.poblacion_dia(uuid, date),
  public.crudo_ingrediente(uuid, uuid, date, uuid, uuid, uuid, uuid, numeric), public.calcular_explosion(uuid), public.alertas_explosion(uuid),
  public.calculo_inverso(uuid, uuid, numeric, date, uuid[], int, int), public.crear_explosion(uuid, date, date, uuid[], boolean, text, text) to authenticated;
