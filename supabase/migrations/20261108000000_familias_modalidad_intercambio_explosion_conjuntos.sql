-- =====================================================================
-- Supply ERP · Migracion 008 · Parte 4B-1 (02-nov-2026, reglas de Osvaldo)
-- 1. Familias de contrato (plantillas por modalidad): el esqueleto de tiempos, componentes, grupos, variantes,
--    rotacion y familias de intercambio que trae cada modalidad (USPEC, PAE, casinos de fuerzas, adulto mayor, ICBF, bomberos).
--    Se aplica a un contrato y de ahi en adelante se ajusta: "no camisas de fuerza".
-- 2. Familias de intercambio por contrato: que opciones son intercambiables dentro de cada componente
--    (desayuno proteico: huevo, queso, salchicha; almuerzo tuberculo: papa, yuca, platano, ahuyama, name...).
--    Con opciones extraordinarias que se agregan en caliente (contingencia: chorizo concertado con la PPL) y
--    quedan propuestas hasta que planeacion las apruebe como permanentes.
-- 3. Dietas estandarizadas por la nutricionista: "a la gente de dieta siempre huevo en desayuno y pechuga en
--    almuerzo y cena", por contrato o por una sola carcel, por dieta o para todas.
-- 4. Explosion por conjuntos (sin bucles fila a fila): aguanta meses y varias sedes dentro del tiempo limite.
-- 5. dia_ciclo sin bucle dia a dia para PAE (solo cuentan los dias de clase).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Plantillas por modalidad (familias de contrato)
-- ---------------------------------------------------------------------
create table public.plantillas_modalidad (
  codigo        text primary key,
  modalidad     text not null,                 -- valor de contratos.modalidad al que aplica
  nombre        text not null,
  descripcion   text,
  esquema       jsonb not null,                -- tiempos, componentes, grupos, variantes, rotacion, familias, parametros
  fuente        text,
  confirmada    boolean not null default false, -- true cuando se valido contra el anexo real de un contrato
  version       int not null default 1,
  actualizado_en timestamptz not null default now()
);
alter table public.plantillas_modalidad enable row level security;
create policy plantillas_modalidad_ver on public.plantillas_modalidad for select to authenticated using (true);
create policy plantillas_modalidad_admin on public.plantillas_modalidad for all to authenticated using (public.es_superadmin()) with check (public.es_superadmin());
grant select, insert, update, delete on public.plantillas_modalidad to authenticated;

insert into public.plantillas_modalidad (codigo, modalidad, nombre, descripcion, fuente, confirmada, esquema) values
('uspec_ppl', 'uspec_ppl', 'USPEC · PPL en ERON y estaciones', 'Cuatro tiempos (desayuno, almuerzo, cena y refrigerio nocturno), 7 dias, ciclo de 15 menus que avanza todos los dias, poblacion por sexo, dietas terapeuticas del Manual de Dietas, variante EP sin sopa. El refrigerio se factura aparte y no cambia en menus especiales.',
 'Contrato USPEC-CTO-199-2025 Grupo 15 · Anexo 4', true,
 $j${"dias_atencion":"todos","avanza_sin_servicio":true,"n_menus_ciclo":15,"usa_dietas":true,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"H","nombre":"Hombres","tipo":"sexo","orden":1},{"codigo":"M","nombre":"Mujeres","tipo":"sexo","orden":2}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"ERON","es_estandar":true,"componentes_excluidos":[]},{"codigo":"EP","nombre":"Estacion de policia / CTD","es_estandar":false,"componentes_excluidos":["SOPA"]}],
   "tiempos":[
     {"codigo":"DES","nombre":"Desayuno","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"FRUTA","nombre":"Fruta entera","orden":1,"familia":"FRUTA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO_DES"},
       {"codigo":"CEREAL","nombre":"Derivado de cereal","orden":3,"familia":"PANIFICADO"},{"codigo":"BEBIDA","nombre":"Bebida caliente o fria","orden":4,"familia":"BEBIDA_DES"}]},
     {"codigo":"ALM","nombre":"Almuerzo","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"SOPA","nombre":"Sopa","orden":1,"familia":"SOPA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal (arroz)","orden":3,"familia":"CEREAL"},
       {"codigo":"VERDURA","nombre":"Hortalizas y verduras","orden":4,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo, raiz o platano","orden":5,"familia":"TUBERCULO"},
       {"codigo":"JUGO","nombre":"Bebida de fruta","orden":6,"familia":"JUGO"},{"codigo":"POSTRE","nombre":"Postre","orden":7,"familia":"POSTRE"}]},
     {"codigo":"CEN","nombre":"Cena","orden":3,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"SOPA","nombre":"Sopa","orden":1,"familia":"SOPA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal (arroz)","orden":3,"familia":"CEREAL"},
       {"codigo":"VERDURA","nombre":"Hortalizas y verduras","orden":4,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo, raiz o platano","orden":5,"familia":"TUBERCULO"},{"codigo":"JUGO","nombre":"Bebida de fruta","orden":6,"familia":"JUGO"}]},
     {"codigo":"REF","nombre":"Refrigerio nocturno","orden":4,"facturable":true,"cambiable_especial":false,"componentes":[
       {"codigo":"BEBIDA","nombre":"Bebida","orden":1,"familia":"BEBIDA_REF"},{"codigo":"CEREAL","nombre":"Panificado","orden":2,"familia":"PANIFICADO"}]}],
   "rotacion":[{"componente":"FRUTA","min_variedades_semana":4,"max_dias_consecutivos":2,"ventana_no_repetir_dias":3},{"componente":"POSTRE","min_variedades_semana":4,"max_dias_consecutivos":1,"ventana_no_repetir_dias":4},
     {"componente":"JUGO","min_variedades_semana":2,"max_dias_consecutivos":1,"ventana_no_repetir_dias":3},{"componente":"BEBIDA","min_variedades_semana":4},{"componente":"CEREAL","min_variedades_semana":4},
     {"componente":"PROTEICO","ventana_no_repetir_dias":4},{"componente":"SOPA","ventana_no_repetir_dias":4},{"componente":"VERDURA","ventana_no_repetir_dias":4},{"componente":"TUBERCULO","ventana_no_repetir_dias":4}],
   "familias":[{"codigo":"PROTEICO_DES","nombre":"Proteico de desayuno","subfamilias":["Huevo","Queso","Salchicha"]},{"codigo":"PROTEICO","nombre":"Proteico de almuerzo y cena","subfamilias":["Res","Pollo","Cerdo","Pescado"]},
     {"codigo":"PANIFICADO","nombre":"Derivado de cereal / panificado","subfamilias":["Pan","Arepa","Calado o tostada","Galleta","Envuelto"]},{"codigo":"TUBERCULO","nombre":"Tuberculo, raiz o platano","subfamilias":["Papa","Yuca","Platano","Ahuyama","Name"]},
     {"codigo":"CEREAL","nombre":"Cereal (arroz y pasta)","subfamilias":["Arroz","Pasta"]},{"codigo":"SOPA","nombre":"Sopa o crema"},{"codigo":"VERDURA","nombre":"Hortalizas y verduras"},{"codigo":"FRUTA","nombre":"Fruta entera"},
     {"codigo":"JUGO","nombre":"Bebida de fruta"},{"codigo":"POSTRE","nombre":"Postre"},{"codigo":"BEBIDA_DES","nombre":"Bebida de desayuno"},{"codigo":"BEBIDA_REF","nombre":"Bebida de refrigerio"}]}$j$),
('pae', 'pae', 'PAE · alimentacion escolar', 'Cada estudiante recibe un solo tiempo segun su modalidad: racion preparada en sitio (almuerzo), complemento AM o PM (jornada manana o tarde), racion industrializada. Solo dias de clase (calendario propio), ciclo de 20 menus que avanza solo en dias de servicio, grupos etarios, sin dietas terapeuticas (acuerdos con rectores via intercambios por sede).',
 'Lineamientos PAE (MinEducacion / UApA); por confirmar contra el anexo de UT Nutrifood', false,
 $j${"dias_atencion":"calendario_propio","avanza_sin_servicio":false,"n_menus_ciclo":20,"usa_dietas":false,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"G4_8","nombre":"4 a 8 anos 11 meses","tipo":"etario","orden":1},{"codigo":"G9_13","nombre":"9 a 13 anos 11 meses","tipo":"etario","orden":2},{"codigo":"G14_17","nombre":"14 a 17 anos 11 meses","tipo":"etario","orden":3}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"Estandar","es_estandar":true,"componentes_excluidos":[]}],
   "tiempos":[
     {"codigo":"CAM","nombre":"Complemento AM (jornada manana)","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"LACTEO","nombre":"Bebida con leche o derivado lacteo","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Cereal o panificado","orden":2,"familia":"PANIFICADO"},{"codigo":"PROTEICO","nombre":"Alimento proteico (cuando aplica)","orden":3,"familia":"PROTEICO_DES"},{"codigo":"FRUTA","nombre":"Fruta","orden":4,"familia":"FRUTA"}]},
     {"codigo":"RPS","nombre":"Racion preparada en sitio (almuerzo)","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"PROTEICO","nombre":"Alimento proteico","orden":1,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal","orden":2,"familia":"CEREAL"},{"codigo":"TUBERCULO","nombre":"Tuberculo, raiz o platano","orden":3,"familia":"TUBERCULO"},
       {"codigo":"VERDURA","nombre":"Hortalizas y verduras","orden":4,"familia":"VERDURA"},{"codigo":"LEGUMINOSA","nombre":"Leguminosa (cuando aplica)","orden":5,"familia":"LEGUMINOSA"},{"codigo":"BEBIDA","nombre":"Jugo de fruta o bebida con leche","orden":6,"familia":"JUGO"},{"codigo":"FRUTA","nombre":"Fruta (cuando aplica)","orden":7,"familia":"FRUTA"}]},
     {"codigo":"CPM","nombre":"Complemento PM (jornada tarde)","orden":3,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"LACTEO","nombre":"Bebida con leche o derivado lacteo","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Cereal o panificado","orden":2,"familia":"PANIFICADO"},{"codigo":"PROTEICO","nombre":"Alimento proteico (cuando aplica)","orden":3,"familia":"PROTEICO_DES"},{"codigo":"FRUTA","nombre":"Fruta","orden":4,"familia":"FRUTA"}]},
     {"codigo":"RI","nombre":"Racion industrializada","orden":4,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"LACTEO","nombre":"Bebida lactea UHT","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Panificado o cereal empacado","orden":2,"familia":"PANIFICADO"},{"codigo":"FRUTA","nombre":"Fruta","orden":3,"familia":"FRUTA"}]}],
   "rotacion":[{"componente":"FRUTA","min_variedades_semana":3},{"componente":"PROTEICO","ventana_no_repetir_dias":3},{"componente":"TUBERCULO","ventana_no_repetir_dias":3}],
   "familias":[{"codigo":"PROTEICO_DES","nombre":"Proteico de complemento","subfamilias":["Huevo","Queso","Embutido"]},{"codigo":"PROTEICO","nombre":"Proteico de almuerzo","subfamilias":["Res","Pollo","Cerdo","Pescado","Huevo"]},
     {"codigo":"PANIFICADO","nombre":"Cereal o panificado","subfamilias":["Pan","Arepa","Galleta","Envuelto"]},{"codigo":"TUBERCULO","nombre":"Tuberculo, raiz o platano","subfamilias":["Papa","Yuca","Platano","Name","Ahuyama"]},
     {"codigo":"CEREAL","nombre":"Cereal","subfamilias":["Arroz","Pasta"]},{"codigo":"VERDURA","nombre":"Hortalizas y verduras"},{"codigo":"LEGUMINOSA","nombre":"Leguminosa","subfamilias":["Lenteja","Frijol","Arveja","Garbanzo"]},
     {"codigo":"FRUTA","nombre":"Fruta"},{"codigo":"JUGO","nombre":"Jugo o bebida"},{"codigo":"LACTEO","nombre":"Lacteo","subfamilias":["Leche","Yogur","Kumis","Avena en leche"]}]}$j$),
('fuerzas_casino', 'fuerzas_casino', 'Casinos de fuerzas (Armada, Policia, Ejercito)', 'Tres tiempos principales (y refrigerio si el contrato lo pide), 7 dias, ciclo de 21 menus, poblacion unica, calidad y gramajes superiores a USPEC. Dietas solo por prescripcion medica.',
 'Esqueleto por confirmar con el contrato (casino de cadetes Armada / MEBAR)', false,
 $j${"dias_atencion":"todos","avanza_sin_servicio":true,"n_menus_ciclo":21,"usa_dietas":true,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"UNICO","nombre":"Poblacion unica","tipo":"otro","orden":1}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"Estandar","es_estandar":true,"componentes_excluidos":[]}],
   "tiempos":[
     {"codigo":"DES","nombre":"Desayuno","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"FRUTA","nombre":"Fruta o jugo","orden":1,"familia":"FRUTA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO_DES"},{"codigo":"CEREAL","nombre":"Panificado o arepa","orden":3,"familia":"PANIFICADO"},{"codigo":"ACOMPANANTE","nombre":"Acompanante (caldo, calentado, tamal)","orden":4,"familia":"ACOMPANANTE"},{"codigo":"BEBIDA","nombre":"Bebida caliente","orden":5,"familia":"BEBIDA_DES"}]},
     {"codigo":"ALM","nombre":"Almuerzo","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"SOPA","nombre":"Sopa o crema","orden":1,"familia":"SOPA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Arroz o pasta","orden":3,"familia":"CEREAL"},{"codigo":"VERDURA","nombre":"Ensalada","orden":4,"familia":"VERDURA"},
       {"codigo":"TUBERCULO","nombre":"Tuberculo o platano","orden":5,"familia":"TUBERCULO"},{"codigo":"JUGO","nombre":"Jugo","orden":6,"familia":"JUGO"},{"codigo":"POSTRE","nombre":"Postre","orden":7,"familia":"POSTRE"}]},
     {"codigo":"CEN","nombre":"Cena","orden":3,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"PROTEICO","nombre":"Proteico","orden":1,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Arroz o pasta","orden":2,"familia":"CEREAL"},{"codigo":"VERDURA","nombre":"Ensalada","orden":3,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo o platano","orden":4,"familia":"TUBERCULO"},{"codigo":"BEBIDA","nombre":"Bebida","orden":5,"familia":"BEBIDA_DES"}]}],
   "rotacion":[{"componente":"PROTEICO","ventana_no_repetir_dias":3},{"componente":"SOPA","ventana_no_repetir_dias":4},{"componente":"POSTRE","min_variedades_semana":5}],
   "familias":[{"codigo":"PROTEICO_DES","nombre":"Proteico de desayuno","subfamilias":["Huevo","Queso","Embutido","Carne"]},{"codigo":"PROTEICO","nombre":"Proteico","subfamilias":["Res","Pollo","Cerdo","Pescado","Mariscos"]},{"codigo":"PANIFICADO","nombre":"Panificado"},{"codigo":"ACOMPANANTE","nombre":"Acompanante de desayuno"},
     {"codigo":"TUBERCULO","nombre":"Tuberculo o platano","subfamilias":["Papa","Yuca","Platano"]},{"codigo":"CEREAL","nombre":"Arroz o pasta"},{"codigo":"SOPA","nombre":"Sopa o crema"},{"codigo":"VERDURA","nombre":"Ensalada"},{"codigo":"FRUTA","nombre":"Fruta o jugo"},{"codigo":"JUGO","nombre":"Jugo"},{"codigo":"POSTRE","nombre":"Postre"},{"codigo":"BEBIDA_DES","nombre":"Bebida"}]}$j$),
('adulto_mayor', 'adulto_mayor', 'Adulto mayor (centros vida y comedores)', 'Almuerzo en sitio y complemento, dias habiles, ciclo de 20 menus, poblacion unica con consistencia adaptada (blanda) frecuente.',
 'Esqueleto por confirmar', false,
 $j${"dias_atencion":"habiles","avanza_sin_servicio":false,"n_menus_ciclo":20,"usa_dietas":true,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"UNICO","nombre":"Adulto mayor","tipo":"otro","orden":1}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"Estandar","es_estandar":true,"componentes_excluidos":[]},{"codigo":"BLANDA","nombre":"Consistencia blanda","es_estandar":false,"componentes_excluidos":[]}],
   "tiempos":[
     {"codigo":"ALM","nombre":"Almuerzo","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"SOPA","nombre":"Sopa o crema","orden":1,"familia":"SOPA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal","orden":3,"familia":"CEREAL"},{"codigo":"VERDURA","nombre":"Verdura","orden":4,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo","orden":5,"familia":"TUBERCULO"},{"codigo":"JUGO","nombre":"Jugo","orden":6,"familia":"JUGO"},{"codigo":"FRUTA","nombre":"Fruta","orden":7,"familia":"FRUTA"}]},
     {"codigo":"CPM","nombre":"Complemento (refrigerio)","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[
       {"codigo":"LACTEO","nombre":"Lacteo","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Panificado","orden":2,"familia":"PANIFICADO"},{"codigo":"FRUTA","nombre":"Fruta","orden":3,"familia":"FRUTA"}]}],
   "rotacion":[{"componente":"PROTEICO","ventana_no_repetir_dias":3}],
   "familias":[{"codigo":"PROTEICO","nombre":"Proteico","subfamilias":["Res","Pollo","Cerdo","Pescado","Huevo"]},{"codigo":"PANIFICADO","nombre":"Panificado"},{"codigo":"TUBERCULO","nombre":"Tuberculo","subfamilias":["Papa","Yuca","Platano","Ahuyama"]},{"codigo":"CEREAL","nombre":"Cereal"},{"codigo":"SOPA","nombre":"Sopa o crema"},{"codigo":"VERDURA","nombre":"Verdura"},{"codigo":"FRUTA","nombre":"Fruta"},{"codigo":"JUGO","nombre":"Jugo"},{"codigo":"LACTEO","nombre":"Lacteo"}]}$j$),
('icbf_primera_infancia', 'icbf_primera_infancia', 'ICBF · primera infancia (CDI y hogares)', 'Varios tiempos en el dia (desayuno, refrigerio AM, almuerzo, refrigerio PM) para ninos de 6 meses a 5 anos por grupo de edad, dias habiles, minuta por grupo etario y consistencia.',
 'Esqueleto por confirmar con la minuta patron ICBF', false,
 $j${"dias_atencion":"habiles","avanza_sin_servicio":false,"n_menus_ciclo":20,"usa_dietas":false,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"E6_11M","nombre":"6 a 11 meses","tipo":"etario","orden":1},{"codigo":"E1_2","nombre":"1 a 2 anos","tipo":"etario","orden":2},{"codigo":"E3_5","nombre":"3 a 5 anos","tipo":"etario","orden":3}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"Estandar","es_estandar":true,"componentes_excluidos":[]}],
   "tiempos":[
     {"codigo":"DES","nombre":"Desayuno","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"LACTEO","nombre":"Lacteo","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Cereal","orden":2,"familia":"PANIFICADO"},{"codigo":"PROTEICO","nombre":"Proteico","orden":3,"familia":"PROTEICO_DES"},{"codigo":"FRUTA","nombre":"Fruta","orden":4,"familia":"FRUTA"}]},
     {"codigo":"RAM","nombre":"Refrigerio AM","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"FRUTA","nombre":"Fruta","orden":1,"familia":"FRUTA"}]},
     {"codigo":"ALM","nombre":"Almuerzo","orden":3,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"PROTEICO","nombre":"Proteico","orden":1,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal","orden":2,"familia":"CEREAL"},{"codigo":"TUBERCULO","nombre":"Tuberculo","orden":3,"familia":"TUBERCULO"},{"codigo":"VERDURA","nombre":"Verdura","orden":4,"familia":"VERDURA"},{"codigo":"JUGO","nombre":"Jugo","orden":5,"familia":"JUGO"}]},
     {"codigo":"RPM","nombre":"Refrigerio PM","orden":4,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"LACTEO","nombre":"Lacteo","orden":1,"familia":"LACTEO"},{"codigo":"CEREAL","nombre":"Cereal","orden":2,"familia":"PANIFICADO"}]}],
   "rotacion":[{"componente":"FRUTA","min_variedades_semana":4}],
   "familias":[{"codigo":"PROTEICO_DES","nombre":"Proteico de desayuno","subfamilias":["Huevo","Queso"]},{"codigo":"PROTEICO","nombre":"Proteico","subfamilias":["Res","Pollo","Cerdo","Pescado","Higado"]},{"codigo":"PANIFICADO","nombre":"Cereal"},{"codigo":"TUBERCULO","nombre":"Tuberculo"},{"codigo":"CEREAL","nombre":"Cereal"},{"codigo":"VERDURA","nombre":"Verdura"},{"codigo":"FRUTA","nombre":"Fruta"},{"codigo":"JUGO","nombre":"Jugo"},{"codigo":"LACTEO","nombre":"Lacteo"}]}$j$),
('bomberos', 'bomberos', 'Bomberos y cuerpos de socorro', 'Tres tiempos, 7 dias, ciclo de 21 menus, poblacion unica.', 'Esqueleto por confirmar', false,
 $j${"dias_atencion":"todos","avanza_sin_servicio":true,"n_menus_ciclo":21,"usa_dietas":false,"modo_reinicio":"continuo",
   "grupos":[{"codigo":"UNICO","nombre":"Poblacion unica","tipo":"otro","orden":1}],
   "variantes":[{"codigo":"ESTANDAR","nombre":"Estandar","es_estandar":true,"componentes_excluidos":[]}],
   "tiempos":[
     {"codigo":"DES","nombre":"Desayuno","orden":1,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"FRUTA","nombre":"Fruta","orden":1,"familia":"FRUTA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO_DES"},{"codigo":"CEREAL","nombre":"Panificado","orden":3,"familia":"PANIFICADO"},{"codigo":"BEBIDA","nombre":"Bebida","orden":4,"familia":"BEBIDA_DES"}]},
     {"codigo":"ALM","nombre":"Almuerzo","orden":2,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"SOPA","nombre":"Sopa","orden":1,"familia":"SOPA"},{"codigo":"PROTEICO","nombre":"Proteico","orden":2,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal","orden":3,"familia":"CEREAL"},{"codigo":"VERDURA","nombre":"Verdura","orden":4,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo","orden":5,"familia":"TUBERCULO"},{"codigo":"JUGO","nombre":"Jugo","orden":6,"familia":"JUGO"}]},
     {"codigo":"CEN","nombre":"Cena","orden":3,"facturable":true,"cambiable_especial":true,"componentes":[{"codigo":"PROTEICO","nombre":"Proteico","orden":1,"familia":"PROTEICO"},{"codigo":"CEREAL","nombre":"Cereal","orden":2,"familia":"CEREAL"},{"codigo":"VERDURA","nombre":"Verdura","orden":3,"familia":"VERDURA"},{"codigo":"TUBERCULO","nombre":"Tuberculo","orden":4,"familia":"TUBERCULO"},{"codigo":"BEBIDA","nombre":"Bebida","orden":5,"familia":"BEBIDA_DES"}]}],
   "rotacion":[{"componente":"PROTEICO","ventana_no_repetir_dias":3}],
   "familias":[{"codigo":"PROTEICO_DES","nombre":"Proteico de desayuno"},{"codigo":"PROTEICO","nombre":"Proteico"},{"codigo":"PANIFICADO","nombre":"Panificado"},{"codigo":"TUBERCULO","nombre":"Tuberculo"},{"codigo":"CEREAL","nombre":"Cereal"},{"codigo":"SOPA","nombre":"Sopa"},{"codigo":"VERDURA","nombre":"Verdura"},{"codigo":"FRUTA","nombre":"Fruta"},{"codigo":"JUGO","nombre":"Jugo"},{"codigo":"BEBIDA_DES","nombre":"Bebida"}]}$j$);

-- ---------------------------------------------------------------------
-- 2. Familias de intercambio por contrato y sus opciones
-- ---------------------------------------------------------------------
create table public.familias_intercambio (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id),
  contrato_id      uuid not null references public.contratos(id),
  codigo           text not null,                 -- PROTEICO_DES, PROTEICO, PANIFICADO, TUBERCULO...
  nombre           text not null,
  subfamilias      text[] not null default '{}',  -- Res, Pollo, Cerdo, Pescado (orientan la sugerencia)
  nota             text,
  creado_por       uuid references auth.users(id) default auth.uid(),
  creado_en        timestamptz not null default now(),
  unique (contrato_id, codigo)
);
-- que familia usa cada componente de cada tiempo (el proteico del desayuno no es el del almuerzo)
alter table public.componentes add column familia_id uuid references public.familias_intercambio(id);

create table public.familia_opciones (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id),
  familia_id       uuid not null references public.familias_intercambio(id) on delete cascade,
  preparacion_id   uuid not null references public.preparaciones(id),
  subfamilia       text,                          -- Res, Pollo... (del ingrediente principal)
  en_minuta        boolean not null default false, -- aparece en el ciclo oficial
  es_extraordinaria boolean not null default false, -- agregada en caliente (contingencia); no es de la minuta
  estado           text not null default 'vigente' check (estado in ('vigente','propuesta','retirada')),
  origen           text not null default 'minuta' check (origen in ('minuta','catalogo','manual','contingencia','plantilla')),
  nota             text,
  creado_por       uuid references auth.users(id) default auth.uid(),
  creado_en        timestamptz not null default now(),
  aprobado_por     uuid references auth.users(id),
  aprobado_en      timestamptz,
  unique (familia_id, preparacion_id)
);
create index familia_opciones_idx on public.familia_opciones (familia_id, estado);

alter table public.productos add column pendiente_revision boolean not null default false;   -- creado en caliente desde un intercambio
alter table public.intercambios_menu add column opcion_familia_id uuid references public.familia_opciones(id);

-- Aplica el esqueleto de la modalidad a un contrato (solo crea lo que no exista; nunca borra)
create or replace function public.aplicar_plantilla_modalidad(p_contrato uuid, p_codigo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.contratos; pl public.plantillas_modalidad; t jsonb; co jsonb; g jsonb; v jsonb; r jsonb; f jsonb;
        v_t uuid; v_f uuid; n_t int := 0; n_c int := 0; n_g int := 0; n_v int := 0; n_r int := 0; n_f int := 0;
begin
  select * into c from public.contratos where id = p_contrato;
  if c.id is null then raise exception 'Contrato no encontrado'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'crear')) then
    raise exception 'Sin permiso (Planeacion: crear).';
  end if;
  select * into pl from public.plantillas_modalidad where codigo = coalesce(p_codigo, c.modalidad);
  if pl.codigo is null then raise exception 'No hay plantilla para la modalidad %', coalesce(p_codigo, c.modalidad); end if;

  for g in select * from jsonb_array_elements(pl.esquema->'grupos') loop
    insert into public.grupos_poblacion (empresa_id, contrato_id, codigo, nombre, tipo, orden)
    values (c.empresa_id, c.id, g->>'codigo', g->>'nombre', coalesce(g->>'tipo', 'otro'), coalesce((g->>'orden')::int, 1))
    on conflict (contrato_id, codigo) do nothing;
    if found then n_g := n_g + 1; end if;
  end loop;
  for v in select * from jsonb_array_elements(pl.esquema->'variantes') loop
    insert into public.variantes_racion (empresa_id, contrato_id, codigo, nombre, es_estandar, componentes_excluidos)
    values (c.empresa_id, c.id, v->>'codigo', v->>'nombre', coalesce((v->>'es_estandar')::boolean, false),
            coalesce((select array_agg(x) from jsonb_array_elements_text(v->'componentes_excluidos') x), '{}'))
    on conflict (contrato_id, codigo) do nothing;
    if found then n_v := n_v + 1; end if;
  end loop;
  for f in select * from jsonb_array_elements(pl.esquema->'familias') loop
    insert into public.familias_intercambio (empresa_id, contrato_id, codigo, nombre, subfamilias)
    values (c.empresa_id, c.id, f->>'codigo', f->>'nombre', coalesce((select array_agg(x) from jsonb_array_elements_text(f->'subfamilias') x), '{}'))
    on conflict (contrato_id, codigo) do nothing;
    if found then n_f := n_f + 1; end if;
  end loop;
  for t in select * from jsonb_array_elements(pl.esquema->'tiempos') loop
    insert into public.tiempos_comida (empresa_id, contrato_id, codigo, nombre, orden, facturable, cambiable_especial)
    values (c.empresa_id, c.id, t->>'codigo', t->>'nombre', coalesce((t->>'orden')::int, 1), coalesce((t->>'facturable')::boolean, true), coalesce((t->>'cambiable_especial')::boolean, true))
    on conflict (contrato_id, codigo) do nothing;
    if found then n_t := n_t + 1; end if;
    select id into v_t from public.tiempos_comida where contrato_id = c.id and codigo = t->>'codigo';
    for co in select * from jsonb_array_elements(t->'componentes') loop
      select id into v_f from public.familias_intercambio where contrato_id = c.id and codigo = co->>'familia';
      insert into public.componentes (empresa_id, contrato_id, tiempo_comida_id, codigo, nombre, orden, familia_id)
      values (c.empresa_id, c.id, v_t, co->>'codigo', co->>'nombre', coalesce((co->>'orden')::int, 1), v_f)
      on conflict (contrato_id, tiempo_comida_id, codigo) do update set familia_id = coalesce(public.componentes.familia_id, excluded.familia_id);
      if found then n_c := n_c + 1; end if;
    end loop;
  end loop;
  for r in select * from jsonb_array_elements(pl.esquema->'rotacion') loop
    insert into public.reglas_rotacion (empresa_id, contrato_id, componente_codigo, min_variedades_semana, max_dias_consecutivos, ventana_no_repetir_dias, nota)
    values (c.empresa_id, c.id, r->>'componente', (r->>'min_variedades_semana')::int, (r->>'max_dias_consecutivos')::int, (r->>'ventana_no_repetir_dias')::int, 'Plantilla ' || pl.codigo)
    on conflict (contrato_id, componente_codigo) do nothing;
    if found then n_r := n_r + 1; end if;
  end loop;
  update public.contratos set dias_atencion = coalesce(pl.esquema->>'dias_atencion', dias_atencion),
                              tiempos_comida = coalesce(jsonb_array_length(pl.esquema->'tiempos'), tiempos_comida),
                              n_menus_ciclo = coalesce(n_menus_ciclo, (pl.esquema->>'n_menus_ciclo')::int)
   where id = c.id;
  return jsonb_build_object('plantilla', pl.codigo, 'tiempos', n_t, 'componentes', n_c, 'grupos', n_g, 'variantes', n_v, 'rotacion', n_r, 'familias', n_f);
end $$;

-- Siembra las opciones de cada familia desde lo que ya existe en el contrato: ciclo oficial (en_minuta) y catalogo de preparaciones
create or replace function public.sembrar_familias_contrato(p_contrato uuid)
returns int language plpgsql security definer set search_path = public as $$
declare c public.contratos; n int := 0; co record; v_f uuid; v_cod text;
begin
  select * into c from public.contratos where id = p_contrato;
  if c.id is null then raise exception 'Contrato no encontrado'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'crear')) then
    raise exception 'Sin permiso (Planeacion: crear).';
  end if;
  -- 1. cada componente sin familia recibe la familia que mas usan sus preparaciones en el ciclo (PROTEICO_DES, PANIFICADO...)
  for co in select c2.*, t.codigo as tcod from public.componentes c2 join public.tiempos_comida t on t.id = c2.tiempo_comida_id where c2.contrato_id = c.id and c2.familia_id is null loop
    select p.componente_codigo into v_cod
      from public.ciclo_menu_items i join public.preparaciones p on p.id = i.preparacion_id
     where i.componente_id = co.id and p.componente_codigo is not null
     group by p.componente_codigo order by count(*) desc limit 1;
    v_cod := coalesce(v_cod, co.codigo);
    insert into public.familias_intercambio (empresa_id, contrato_id, codigo, nombre)
    values (c.empresa_id, c.id, v_cod, initcap(replace(v_cod, '_', ' ')))
    on conflict (contrato_id, codigo) do nothing;
    select id into v_f from public.familias_intercambio where contrato_id = c.id and codigo = v_cod;
    update public.componentes set familia_id = v_f where id = co.id;
  end loop;
  -- 2. opciones: preparaciones del catalogo con ese componente_codigo (de la empresa o del contrato), marcando las que estan en el ciclo
  with ins as (
    insert into public.familia_opciones (empresa_id, familia_id, preparacion_id, subfamilia, en_minuta, origen)
    select c.empresa_id, f.id, p.id,
           (select trim(split_part(pr.nombre, ',', 1)) from public.preparacion_ingredientes pi join public.productos pr on pr.id = pi.producto_id
             where pi.preparacion_id = p.id and pi.es_principal order by pi.orden limit 1),
           exists (select 1 from public.ciclo_menu_items i join public.ciclos_menu cm on cm.id = i.ciclo_id where cm.contrato_id = c.id and i.preparacion_id = p.id),
           case when exists (select 1 from public.ciclo_menu_items i join public.ciclos_menu cm on cm.id = i.ciclo_id where cm.contrato_id = c.id and i.preparacion_id = p.id) then 'minuta' else 'catalogo' end
      from public.familias_intercambio f
      join public.preparaciones p on p.empresa_id = c.empresa_id and (p.contrato_id = c.id or p.contrato_id is null) and p.estado = 'activa' and p.componente_codigo = f.codigo
     where f.contrato_id = c.id
    on conflict (familia_id, preparacion_id) do update set en_minuta = excluded.en_minuta or public.familia_opciones.en_minuta
    returning 1)
  select count(*) into n from ins;
  return n;
end $$;

-- Sugerencias de intercambio para una celda de la programacion (sede, fecha, tiempo, componente)
create or replace function public.sugerir_intercambios(p_contrato_sede uuid, p_fecha date, p_tiempo_comida uuid, p_componente uuid)
returns table (opcion_id uuid, preparacion_id uuid, preparacion_nombre text, subfamilia text, misma_subfamilia boolean, en_minuta boolean,
               es_extraordinaria boolean, estado text, veces_en_ventana int, ultima_vez date, rompe_rotacion boolean, es_actual boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid; v_contrato uuid; v_f uuid; v_actual uuid; v_sub text; v_ccod text; v_ventana int; v_maxc int;
begin
  select cs.empresa_id, cs.contrato_id into v_emp, v_contrato from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if v_contrato is null then raise exception 'Sede no encontrada'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M7', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver')) then
    raise exception 'Sin permiso';
  end if;
  select c.familia_id, c.codigo into v_f, v_ccod from public.componentes c where c.id = p_componente;
  if v_f is null then return; end if;
  select m.preparacion_id into v_actual from public.menu_del_dia(p_contrato_sede, p_fecha) m where m.tiempo_comida_id = p_tiempo_comida and m.componente_id = p_componente limit 1;
  select o.subfamilia into v_sub from public.familia_opciones o where o.familia_id = v_f and o.preparacion_id = v_actual;
  select coalesce(r.ventana_no_repetir_dias, 3), r.max_dias_consecutivos into v_ventana, v_maxc from public.reglas_rotacion r where r.contrato_id = v_contrato and r.componente_codigo = v_ccod;
  v_ventana := coalesce(v_ventana, 3);
  return query
  with uso as (
    select m.preparacion_id as pid, g::date as f
      from generate_series(p_fecha - greatest(v_ventana, 14), p_fecha + v_ventana, interval '1 day') g
      cross join lateral public.menu_del_dia(p_contrato_sede, g::date) m
     where m.componente_id = p_componente and g::date <> p_fecha
  )
  select o.id, o.preparacion_id, p.nombre, o.subfamilia, (o.subfamilia is not distinct from v_sub) and v_sub is not null, o.en_minuta, o.es_extraordinaria, o.estado,
         (select count(*)::int from uso u where u.pid = o.preparacion_id and u.f between p_fecha - v_ventana and p_fecha + v_ventana),
         (select max(u.f) from uso u where u.pid = o.preparacion_id and u.f < p_fecha),
         exists (select 1 from uso u where u.pid = o.preparacion_id and u.f between p_fecha - v_ventana and p_fecha + v_ventana),
         o.preparacion_id = v_actual
    from public.familia_opciones o join public.preparaciones p on p.id = o.preparacion_id
   where o.familia_id = v_f and o.estado in ('vigente','propuesta')
   order by o.preparacion_id = v_actual desc,
            (o.estado = 'vigente' and not o.es_extraordinaria) desc,
            exists (select 1 from uso u where u.pid = o.preparacion_id and u.f between p_fecha - v_ventana and p_fecha + v_ventana),
            o.en_minuta desc, (o.subfamilia is not distinct from v_sub) desc, p.nombre;
end $$;

-- Agregar una opcion a la familia en caliente: una preparacion existente, o una nueva a partir de un producto (existente o nuevo).
-- Planeacion (M2 crear) la deja vigente; el administrador de sede (M7 crear) la deja propuesta y avisa a planeacion.
create or replace function public.agregar_opcion_familia(p_familia uuid, p_preparacion uuid default null, p_producto uuid default null,
                                                         p_nombre text default null, p_producto_nuevo text default null, p_nota text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare f public.familias_intercambio; v_prep uuid; v_prod uuid; v_estado text; v_extra boolean; v_id uuid; v_peso numeric; v_cat text; v_sede text; v_pnombre text;
begin
  select * into f from public.familias_intercambio where id = p_familia;
  if f.id is null then raise exception 'Familia no encontrada'; end if;
  if auth.uid() is null or public.es_superadmin() or public.tiene_permiso(f.empresa_id, 'M2', 'crear') then v_estado := 'vigente'; v_extra := false;
  elsif public.tiene_permiso(f.empresa_id, 'M7', 'crear') then v_estado := 'propuesta'; v_extra := true;
  else raise exception 'Sin permiso para agregar opciones (Planeacion o Sede: crear).'; end if;

  v_prep := p_preparacion;
  if v_prep is null then
    -- producto nuevo (chorizo que no estaba en el catalogo)
    v_prod := p_producto;
    if v_prod is null and coalesce(trim(p_producto_nuevo), '') <> '' then
      v_cat := case when f.codigo like 'PROTEICO%' then 'proteinas' when f.codigo in ('TUBERCULO','VERDURA','FRUTA','JUGO','LEGUMINOSA') then 'fruver'
                    when f.codigo in ('PANIFICADO') then 'panaderia' when f.codigo like 'BEBIDA%' or f.codigo = 'JUGO' then 'bebidas' when f.codigo = 'LACTEO' then 'lacteos' else 'abarrotes' end;
      insert into public.productos (empresa_id, codigo, nombre, categoria, pendiente_revision)
      values (f.empresa_id, upper(regexp_replace(translate(trim(p_producto_nuevo), 'áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN'), '[^A-Za-z0-9]+', '_', 'g')) || '_' || substr(gen_random_uuid()::text, 1, 4), trim(p_producto_nuevo), v_cat, true)
      returning id into v_prod;
      insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
      values (f.empresa_id, 'M13', 'alta', 'Producto creado en caliente: ' || trim(p_producto_nuevo), 'Creado desde un intercambio de la familia ' || f.nombre || '. Complete la ficha (unidad, categoria, rendimiento, riesgo).', '/maestros?producto=' || v_prod, 'producto', v_prod);
    end if;
    if v_prod is null then raise exception 'Indique la preparacion, el producto o el nombre del producto nuevo.'; end if;
    select nombre into v_pnombre from public.productos where id = v_prod;
    -- gramaje de arranque: la minuta patron del componente de esa familia (crudo de referencia o servido)
    select coalesce(mp.peso_bruto_ref, mp.porcion_servida) into v_peso
      from public.minuta_patron mp join public.componentes c on c.id = mp.componente_id
     where c.familia_id = f.id order by mp.producto_id nulls first, coalesce(mp.peso_bruto_ref, mp.porcion_servida) desc limit 1;
    insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento)
    values (f.empresa_id, f.contrato_id,
            upper(regexp_replace(translate(coalesce(trim(p_nombre), v_pnombre), 'áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN'), '[^A-Za-z0-9]+', '_', 'g')) || '_' || substr(gen_random_uuid()::text, 1, 4),
            coalesce(trim(p_nombre), v_pnombre), f.codigo, 'Receta creada desde un intercambio' || case when v_peso is null then ' (sin gramaje: revisar)' else '' end)
    returning id into v_prep;
    insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, peso_bruto, es_principal)
    values (f.empresa_id, v_prep, v_prod, coalesce(v_peso, 0), true);
  end if;

  insert into public.familia_opciones (empresa_id, familia_id, preparacion_id, subfamilia, en_minuta, es_extraordinaria, estado, origen, nota, aprobado_por, aprobado_en)
  values (f.empresa_id, f.id, v_prep,
          (select trim(split_part(pr.nombre, ',', 1)) from public.preparacion_ingredientes pi join public.productos pr on pr.id = pi.producto_id where pi.preparacion_id = v_prep and pi.es_principal order by pi.orden limit 1),
          false, v_extra, v_estado, case when v_extra then 'contingencia' else 'manual' end, p_nota,
          case when v_estado = 'vigente' then auth.uid() end, case when v_estado = 'vigente' then now() end)
  on conflict (familia_id, preparacion_id) do update set estado = case when public.familia_opciones.estado = 'retirada' then excluded.estado else public.familia_opciones.estado end, nota = coalesce(excluded.nota, public.familia_opciones.nota)
  returning id into v_id;

  if v_estado = 'propuesta' then
    insert into public.notificaciones (empresa_id, modulo, prioridad, titulo, cuerpo, enlace, entidad, entidad_id)
    values (f.empresa_id, 'M2', 'alta', 'Opcion extraordinaria propuesta · ' || f.nombre,
            (select nombre from public.preparaciones where id = v_prep) || coalesce(': ' || p_nota, '') || '. Apruebela como permanente o retirela.',
            '/intercambios?familia=' || f.id, 'familia_opcion', v_id);
  end if;
  return v_id;
end $$;

-- Planeacion decide: permanente (entra a la familia), solo extraordinaria vigente, o retirada
create or replace function public.decidir_opcion_familia(p_opcion uuid, p_decision text)
returns void language plpgsql security definer set search_path = public as $$
declare o public.familia_opciones;
begin
  select * into o from public.familia_opciones where id = p_opcion;
  if o.id is null then raise exception 'Opcion no encontrada'; end if;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(o.empresa_id, 'M2', 'aprobar')) then raise exception 'Sin permiso (Planeacion: aprobar).'; end if;
  if p_decision = 'permanente' then update public.familia_opciones set estado = 'vigente', es_extraordinaria = false, aprobado_por = auth.uid(), aprobado_en = now() where id = p_opcion;
  elsif p_decision = 'extraordinaria' then update public.familia_opciones set estado = 'vigente', es_extraordinaria = true, aprobado_por = auth.uid(), aprobado_en = now() where id = p_opcion;
  elsif p_decision = 'retirar' then update public.familia_opciones set estado = 'retirada' where id = p_opcion;
  else raise exception 'Decision no valida (permanente, extraordinaria, retirar)'; end if;
end $$;

-- Un intercambio con una preparacion que no esta en la familia del componente la agrega como opcion (propuesta o vigente segun quien lo haga)
create or replace function public.enlazar_opcion_intercambio() returns trigger language plpgsql security definer set search_path = public as $$
declare v_f uuid; v_o uuid;
begin
  if new.tipo_cambio = 'preparacion' and new.preparacion_nueva_id is not null and new.opcion_familia_id is null then
    select familia_id into v_f from public.componentes where id = new.componente_id;
    if v_f is not null then
      select id into v_o from public.familia_opciones where familia_id = v_f and preparacion_id = new.preparacion_nueva_id;
      if v_o is null then
        v_o := public.agregar_opcion_familia(v_f, new.preparacion_nueva_id, null, null, null, 'Agregada desde intercambio: ' || new.motivo);
      end if;
      new.opcion_familia_id := v_o;
    end if;
  end if;
  return new;
end $$;
create trigger intercambios_menu_enlazar_opcion before insert on public.intercambios_menu for each row execute function public.enlazar_opcion_intercambio();

-- RLS
alter table public.familias_intercambio enable row level security;
alter table public.familia_opciones enable row level security;
create policy familias_intercambio_ver on public.familias_intercambio for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))));
create policy familias_intercambio_editar on public.familias_intercambio for all to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'editar')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'crear'));
create policy familia_opciones_ver on public.familia_opciones for select to authenticated
  using (public.es_superadmin() or (public.es_miembro(empresa_id) and (public.tiene_permiso(empresa_id, 'M2', 'ver') or public.tiene_permiso(empresa_id, 'M7', 'ver') or public.tiene_permiso(empresa_id, 'M3', 'ver'))));
create policy familia_opciones_editar on public.familia_opciones for all to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'editar')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'crear'));
grant select, insert, update, delete on public.familias_intercambio, public.familia_opciones to authenticated;
create trigger familias_intercambio_bitacora after insert or update or delete on public.familias_intercambio for each row execute function public.registrar_bitacora();
create trigger familia_opciones_bitacora after insert or update or delete on public.familia_opciones for each row execute function public.registrar_bitacora();

create or replace view public.v_familias_intercambio with (security_invoker = on) as
select f.id as familia_id, f.empresa_id, f.contrato_id, f.codigo, f.nombre as familia, f.subfamilias,
       o.id as opcion_id, p.nombre as preparacion, o.subfamilia, o.en_minuta, o.es_extraordinaria, o.estado, o.origen, o.nota,
       (select string_agg(t.codigo || '/' || c.codigo, ', ' order by t.orden, c.orden) from public.componentes c join public.tiempos_comida t on t.id = c.tiempo_comida_id where c.familia_id = f.id) as usada_en
  from public.familias_intercambio f
  left join public.familia_opciones o on o.familia_id = f.id
  left join public.preparaciones p on p.id = o.preparacion_id;
grant select on public.v_familias_intercambio to authenticated;

-- ---------------------------------------------------------------------
-- 3. Dietas estandarizadas por la nutricionista (por contrato o por una sede; por dieta o para todas)
-- ---------------------------------------------------------------------
alter table public.dieta_equivalencias add column contrato_sede_id uuid references public.contrato_sedes(id);
alter table public.dieta_equivalencias drop constraint dieta_equivalencias_contrato_id_tipo_dieta_id_key;
alter table public.dieta_equivalencias add constraint dieta_equivalencias_unq unique nulls not distinct (contrato_id, contrato_sede_id, tipo_dieta_id);

create table public.dieta_estandar (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas(id),
  contrato_id       uuid not null references public.contratos(id),
  contrato_sede_id  uuid references public.contrato_sedes(id),      -- null = todo el contrato
  tipo_dieta_id     uuid references public.tipos_dieta(id),         -- null = todas las dietas
  tiempo_comida_id  uuid references public.tiempos_comida(id),      -- null = todos los tiempos
  componente_codigo text not null,                                   -- PROTEICO, SOPA...
  preparacion_id    uuid not null references public.preparaciones(id),
  motivo            text,                                            -- tamizaje / concertacion de la nutricionista
  soporte           text,
  vigente_desde     date not null default current_date,
  vigente_hasta     date,
  creado_por        uuid references auth.users(id) default auth.uid(),
  creado_en         timestamptz not null default now()
);
create index dieta_estandar_idx on public.dieta_estandar (contrato_id, componente_codigo, vigente_desde);
alter table public.dieta_estandar enable row level security;
create policy dieta_estandar_ver on public.dieta_estandar for select to authenticated using (public.es_superadmin() or (public.es_miembro(empresa_id) and public.tiene_permiso(empresa_id, 'M2', 'ver')));
create policy dieta_estandar_admin on public.dieta_estandar for all to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M2', 'aprobar'));
grant select, insert, update, delete on public.dieta_estandar to authenticated;
create trigger dieta_estandar_bitacora after insert or update or delete on public.dieta_estandar for each row execute function public.registrar_bitacora();

-- La poblacion en dieta siempre va por grupo (H/M, grupo etario): si el contrato tiene un solo grupo se asigna solo;
-- si tiene varios y no se indica, se rechaza (antes una dieta sin grupo se ignoraba en la linea y se duplicaba en la explosion).
create or replace function public.completar_grupo_dieta() returns trigger language plpgsql security definer set search_path = public as $$
declare v_ct uuid; v_n int; v_g uuid;
begin
  if new.grupo_poblacion_id is null then
    select contrato_id into v_ct from public.contrato_sedes where id = new.contrato_sede_id;
    select count(*), min(id::text)::uuid into v_n, v_g from public.grupos_poblacion where contrato_id = v_ct;
    if v_n = 1 then new.grupo_poblacion_id := v_g;
    elsif v_n > 1 then raise exception 'Indique el grupo de poblacion de la dieta (el contrato tiene % grupos).', v_n;
    end if;
  end if;
  return new;
end $$;
create trigger dietas_poblacion_grupo before insert or update on public.dietas_poblacion for each row execute function public.completar_grupo_dieta();

-- ---------------------------------------------------------------------
-- 4. dia_ciclo sin bucle (PAE: cuenta los dias de servicio con una sola consulta)
-- ---------------------------------------------------------------------
create or replace function public.dia_ciclo(p_contrato_sede uuid, p_fecha date)
returns table (ciclo_id uuid, dia int, variante_id uuid) language plpgsql stable security definer set search_path = public as $$
declare sc record; v_contrato uuid; v_dias text; v_n int; v_pos int; v_ancla date; v_exc record;
begin
  select cs.contrato_id into v_contrato from public.contrato_sedes cs where cs.id = p_contrato_sede;
  if not public.es_dia_servicio(v_contrato, p_contrato_sede, p_fecha) then return; end if;
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
     where coalesce(x.atiende, case when v_dias = 'habiles' then extract(isodow from g) between 1 and 5 else true end);
  end if;
  return query select sc.ciclo_id, (v_pos % v_n) + 1, sc.variante_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Explosion por conjuntos
-- ---------------------------------------------------------------------
-- p_desde/p_hasta: calcular solo un tramo (la pantalla parte las proyecciones largas por meses para no pasar el tiempo limite)
drop function if exists public.calcular_explosion(uuid);
create function public.calcular_explosion(p_explosion uuid, p_desde date default null, p_hasta date default null)
returns table (filas int, raciones int, productos int) language plpgsql security definer set search_path = public as $$
declare e public.explosiones; v_filas int := 0; v_rac int := 0; n int; v_hay_sust boolean; d1 date; d2 date;
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
  v_hay_sust := exists (select 1 from public.intercambios_menu x where x.contrato_id = e.contrato_id and x.tipo_cambio = 'ingrediente'
                          and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde)
                          and public.intercambio_aplica(x.estado, x.clase, e.incluye_propuestos));
  d1 := greatest(coalesce(p_desde, e.fecha_desde), e.fecha_desde); d2 := least(coalesce(p_hasta, e.fecha_hasta), e.fecha_hasta);
  if p_desde is null and p_hasta is null then delete from public.explosion_detalle where explosion_id = p_explosion;
  else delete from public.explosion_detalle where explosion_id = p_explosion and fecha between d1 and d2; end if;

  -- sede x dia con su dia de ciclo, menu y poblacion (una sola pasada)
  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;
  create temp table tmp_exp_dias as
  select cs.id as sede_id, g::date as fecha, dc.dia
    from public.contrato_sedes cs
    cross join generate_series(d1, d2, interval '1 day') g
    left join lateral public.dia_ciclo(cs.id, g::date) dc on true
   where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes));
  create temp table tmp_exp_menu as
  select d.sede_id, d.fecha, m.*
    from tmp_exp_dias d cross join lateral public.menu_del_dia(d.sede_id, d.fecha, e.incluye_propuestos) m
   where d.dia is not null and m.preparacion_id is not null;
  create index on tmp_exp_menu (sede_id, fecha);
  create temp table tmp_exp_pob as
  select d.sede_id, d.fecha, p.*
    from tmp_exp_dias d cross join lateral public.poblacion_dia(d.sede_id, d.fecha) p
   where d.dia is not null;
  create index on tmp_exp_pob (sede_id, fecha);

  -- ---- linea
  insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
  select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, m.preparacion_id,
         coalesce(si.producto_id, ing.producto_id), p.grupo_poblacion_id, null, p.linea,
         cr.crudo * coalesce(si.factor, 1), p.linea * cr.crudo * coalesce(si.factor, 1),
         nullif(concat_ws(' · ', cr.nota, case when si.producto_id is not null then 'intercambio de ingrediente' end), '')
    from tmp_exp_menu m
    join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id) and p.linea > 0
    join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                   where pi.preparacion_id = m.preparacion_id and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                   order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
    cross join lateral public.crudo_ingrediente(e.contrato_id, m.sede_id, m.fecha, m.preparacion_id, ing.producto_id, p.grupo_poblacion_id, m.componente_id, ing.peso_bruto) cr
    left join lateral (select * from public.sustitucion_ingrediente(m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos) where v_hay_sust) si on true;
  get diagnostics n = row_count; v_filas := v_filas + n;

  -- ---- dietas (por tipo): equivalencia (sede > contrato), preparacion estandarizada, reglas del contrato > catalogo
  if e.incluye_dietas then
    insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
    select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, vp.prep,
           coalesce(rs.sust, si.producto_id, ing.producto_id), p.grupo_poblacion_id, dd.tipo_dieta_id, dd.cant,
           x.crudo_final, dd.cant * x.crudo_final, x.nota
      from tmp_exp_menu m
      join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id) and p.en_dieta > 0
      join lateral (select dp.tipo_dieta_id, sum(dp.cantidad)::int as cant from public.dietas_poblacion dp
                     where dp.contrato_sede_id = m.sede_id and (dp.grupo_poblacion_id = p.grupo_poblacion_id or dp.grupo_poblacion_id is null)
                       and dp.fecha_desde <= m.fecha and (dp.fecha_hasta is null or dp.fecha_hasta >= m.fecha)
                     group by dp.tipo_dieta_id) dd on dd.cant > 0
      left join lateral (select q.* from public.dieta_equivalencias q where q.contrato_id = e.contrato_id and q.tipo_dieta_id = dd.tipo_dieta_id
                           and (q.contrato_sede_id = m.sede_id or q.contrato_sede_id is null) order by q.contrato_sede_id nulls last limit 1) eq on true
      cross join lateral (select coalesce(eq.equivale_a_id, dd.tipo_dieta_id) as dieta) de
      left join lateral (select ds.preparacion_id from public.dieta_estandar ds
                          where ds.contrato_id = e.contrato_id and (ds.contrato_sede_id = m.sede_id or ds.contrato_sede_id is null)
                            and (ds.tipo_dieta_id = dd.tipo_dieta_id or ds.tipo_dieta_id is null) and (ds.tiempo_comida_id = m.tiempo_comida_id or ds.tiempo_comida_id is null)
                            and ds.componente_codigo = m.componente_codigo and ds.vigente_desde <= m.fecha and (ds.vigente_hasta is null or ds.vigente_hasta >= m.fecha)
                          order by ds.contrato_sede_id nulls last, ds.tipo_dieta_id nulls last, ds.tiempo_comida_id nulls last, ds.vigente_desde desc limit 1) ds on true
      cross join lateral (select coalesce(ds.preparacion_id, case when m.componente_codigo = 'PROTEICO' then eq.preparacion_proteico_id end, m.preparacion_id) as prep) vp
      cross join lateral (select bool_or(rd.tipo_regla = 'excluir_componente') as excl,
                                 (array_agg(rd.valor order by rd.contrato_id nulls last) filter (where rd.tipo_regla = 'factor_porcion'))[1] as factor,
                                 (array_agg(rd.valor order by rd.contrato_id nulls last) filter (where rd.tipo_regla = 'porcion_fija'))[1] as fija
                            from public.reglas_dieta rd
                           where rd.activa and rd.tipo_dieta_id = de.dieta and rd.componente_codigo = m.componente_codigo
                             and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and rd.empresa_id is null))) rg
      join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                     where pi.preparacion_id = vp.prep and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                     order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
      left join public.productos prod on prod.id = ing.producto_id
      left join lateral (select rd.producto_sustituto_id as sust from public.reglas_dieta rd
                          where rd.activa and rd.tipo_dieta_id = de.dieta and rd.tipo_regla = 'sustituir_producto' and rd.producto_id = ing.producto_id
                            and (rd.contrato_id = e.contrato_id or rd.contrato_id is null) order by rd.contrato_id nulls last limit 1) rs on true
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
     where not coalesce(rg.excl, false)
       and not exists (select 1 from public.reglas_dieta rd where rd.activa and rd.tipo_dieta_id = de.dieta and rd.tipo_regla = 'excluir_producto' and rd.producto_id = ing.producto_id and (rd.contrato_id = e.contrato_id or rd.contrato_id is null))
       and not exists (select 1 from public.reglas_dieta rd where rd.activa and rd.tipo_dieta_id = de.dieta and rd.tipo_regla = 'excluir_categoria' and rd.categoria_producto = prod.categoria and (rd.contrato_id = e.contrato_id or rd.contrato_id is null));
    get diagnostics n = row_count; v_filas := v_filas + n;
  end if;

  -- raciones de todo el periodo de la explosion (dias con ciclo), aunque se haya calculado solo un tramo
  select coalesce(sum(p.total), 0) into v_rac
    from public.contrato_sedes cs
    cross join generate_series(e.fecha_desde, e.fecha_hasta, interval '1 day') g
    cross join lateral public.poblacion_dia(cs.id, g::date) p
   where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes))
     and exists (select 1 from public.dia_ciclo(cs.id, g::date));

  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;
  update public.explosiones set estado = 'calculada', raciones = v_rac, calculada_en = now() where id = p_explosion;
  return query select v_filas, v_rac, (select count(distinct producto_id)::int from public.explosion_detalle where explosion_id = p_explosion);
end $$;

-- ---------------------------------------------------------------------
-- 6. Permisos de ejecucion y siembra para los contratos existentes
-- ---------------------------------------------------------------------
revoke execute on function public.aplicar_plantilla_modalidad(uuid, text), public.sembrar_familias_contrato(uuid), public.sugerir_intercambios(uuid, date, uuid, uuid),
  public.agregar_opcion_familia(uuid, uuid, uuid, text, text, text), public.decidir_opcion_familia(uuid, text) from public, anon;
grant execute on function public.calcular_explosion(uuid, date, date) to authenticated;
revoke execute on function public.calcular_explosion(uuid, date, date) from public, anon;
grant execute on function public.aplicar_plantilla_modalidad(uuid, text), public.sembrar_familias_contrato(uuid), public.sugerir_intercambios(uuid, date, uuid, uuid),
  public.agregar_opcion_familia(uuid, uuid, uuid, text, text, text), public.decidir_opcion_familia(uuid, text) to authenticated;

-- Diestra ya tiene tiempos y componentes del Anexo 4: solo se le siembran las familias y sus opciones (subfamilias desde la plantilla)
do $$ declare c record; begin
  for c in select * from public.contratos loop
    perform public.sembrar_familias_contrato(c.id);
    update public.familias_intercambio f set subfamilias = coalesce((select array_agg(x) from jsonb_array_elements_text(j->'subfamilias') x), '{}'),
                                              nombre = coalesce(j->>'nombre', f.nombre)
      from public.plantillas_modalidad pl, jsonb_array_elements(pl.esquema->'familias') j
     where pl.codigo = c.modalidad and f.contrato_id = c.id and f.codigo = j->>'codigo' and f.subfamilias = '{}';
  end loop;
end $$;
