# Control de cambios · Supply ERP (contratistas de alimentacion del Estado)

Que se hizo desde F0, hallazgos, que se corrigio y que queda pendiente. Se actualiza y se entrega despues de cada avance.

## 2026-10-30 · Arranque y F0 (version 0.1.0)

### Hecho
- Plan Maestro (doc en el proyecto de Claude): vision, alcance, 10 modulos + transversal IA, modelo de datos, arquitectura, 7 fases (F0 2-nov-2026 a go-live 14-may-2027), gestion del proyecto, insumos, riesgos, glosario.
- Mockups (canvas): tablero de menus con costo por racion, TV de seguimiento de OC, explosion de materiales, portal del proveedor.
- Informe de contraparte (`docs/BENCHMARK_Y_NORMATIVA_2026-10-30.md`): Odoo, SAP B1, Dynamics 365, Coupa/Ariba, Computrition, CBORD, Galley; three-way match; normativa (Decreto 1154/2020 y RADIAN, Ley 2046 y Decreto 248/2021, Ley 80 art. 40 y Concepto CCE C-451/2025, SIPSA SOAP, Res. UApA 0003/2026).
- Repositorio `erp-contratistas` con la base heredada de A2 PAN ERP: auth, multiempresa con RLS, roles por modulo (17 roles de plantilla pensados desde compras y operacion), roles construibles, usuarios, adjuntos por registro, bitacora, consecutivos, parametros por empresa, PWA.
- Migraciones 001 a 004 y seed 001 (UT Diestra, UT Nutrifood, Demo).
- M1 Contratos: cabezote, adiciones y prorrogas, unidades de servicio, ejecucion mensual, vista resumen con agotamiento y fecha estimada en que se acaba la plata, anexos por categoria.
- Pantallas: login, tablero, contratos (lista y detalle), empresa y parametros (datos, sedes, parametros), usuarios y roles, mi cuenta.

### Decisiones de diseño que salieron del informe de contraparte
1. Tope de adiciones del 50 % medido en SMLMV del año de suscripcion (no en pesos). Tabla `smlmv` por año; cada adicion guarda el SMLMV vigente. Excepcion legal con soporte adjunto.
2. El reloj de 3 dias habiles para aceptar la factura electronica arranca con el evento "recibo del bien" (RADIAN), no con la radicacion administrativa. En F5 el evento de inicio queda parametrizable (recibo del bien vs recepcion de la factura) porque hay un proyecto de decreto que lo cambiaria.
3. La factura del proveedor se lee del XML UBL de la DIAN, no por OCR del PDF. OCR solo para remisiones en papel y soportes de pequeños productores.
4. Tolerancias del cotejo factura vs OC vs entrada parametrizables por item y por item+proveedor (exacto en unidades contadas; 2 a 3 % de peso solo en carnicos y fruver; precio 0 % contra lista vigente con excepcion aprobada).
5. Pequeños productores ACFC no van a usar el portal: canal alterno (foto/WhatsApp + documento soporte). Atributo PP/ACFC en el tercero con registro departamental y vigencia; exportable al formato F1.G5.ABS del supervisor.
6. SIPSA se consume por el servicio SOAP del DANE (no hay REST), como indicador de sobreprecio, no como precio de compra.

### Pendiente de Osvaldo
- NIT y documentacion de UT Diestra (USPEC) y UT Nutrifood (PAE Atlantico): contrato, anexo tecnico, anexo nutricional (minutas con gramajes, dietas terapeuticas), anexo de talento humano, formatos de la entidad.
- Crear el repositorio `erp-contratistas` en GitHub (cuenta outria), el proyecto Supabase y el proyecto Vercel; avisar para subir el codigo y correr las migraciones.
- Nombre definitivo, estudio de marca y colores (por ahora "Supply ERP", azul oscuro + ambar).
- SMLMV 2026: verificar la cifra cargada en la tabla `smlmv` con el area juridica.

### Pendiente tecnico (F1)
- M2: minuta ciclica con calendario, cupos por fecha/grupo/dieta, menus por sede, menus especiales, explosion con ciclos libres y calculo inverso, presupuesto opcional.
- Tablero de menus de la semana con costo por componente y por racion (necesita M2 + master de precios).
- Plantillas de importacion masiva (sedes, cupos, minuta, proveedores, precios).
- Lectura del buzon (script de Gmail como en Los Andes) para anexos y oficios de la entidad.

## 2026-10-31 / 2026-11-01 · Infraestructura en linea y M2 Planeacion (version 0.2.0)

### Hecho
- GitHub `outria/erp-contratistas`, Supabase (org "ERP Contratistas", proyecto `erp-contratistas`, region Americas) y Vercel (equipo ALCO-ANDES, `erp-contratistas.vercel.app`) creados y conectados; variables cargadas; Site URL y Redirect URL de auth configuradas; usuario outria@gmail.com invitado (superadmin por trigger).
- Migraciones 001-006 y seeds 001-002 aplicados en Supabase.
- Seed 001 con datos reales del contrato USPEC-CTO-199-2025 (Grupo 15): NIT 901.942.965-2, valor $42.132.296.516 (2 vigencias), plazo 31-jul-2026, 6 unidades de servicio con PPL estimada (COCUC Cucuta 3.985, Ocana 393, Aguachica 186, Pamplona 349, Arauca 312, Batallon Guasimales 26). Fechas de suscripcion e inicio provisionales (falta acta de inicio). Estaciones de policia no cargadas (salieron el 30-jun-2025).
- Migracion 005: el administrador SQL (sin sesion) puede crear contratos y pedir consecutivos (hallazgo al correr el seed en Supabase: se revirtio completo).
- Migracion 006 (M2): productos y rendimientos, tiempos de comida, grupos de poblacion, componentes, variantes de racion, minuta patron, ajustes de gramaje (solo M2 aprobar), preparaciones e ingredientes por grupo, ciclos de N menus con modo de reinicio y avance solo en dias de servicio, reglas de rotacion, calendario de servicio, excepciones de menu, catalogo de 20 dietas USPEC con reglas (factor, porcion fija, exclusion, sustitucion, tiempos adicionales), equivalencias de dieta por contrato (modo unificado), cupos por periodo, partes diarios, poblacion en dieta, explosion de materiales (linea = cupos - dietas; dietas con reglas del contrato > catalogo), resumen por producto, alertas (sin ciclo, sin cupos, sin receta) y calculo inverso (simula 35 dias y extrapola).
- Seed 002 generado desde el Excel oficial del Anexo 4: 117 productos, 148 preparaciones (116 del N-N009 + alternativas desglosadas de frutas, jugos, postres, panes y bebidas + salchicha y calado), 648 ingredientes con peso bruto H/M, 26 factores de coccion (N-N000), minuta patron resumida (N-N001/002), ciclos estandar ERON (N-N007) y EP (N-N008) con preparacion por defecto para cada descriptor generico, ciclo asignado por sede desde el 1-abr-2025, cupos por sede (COCUC repartido 90/10 H/M provisional).
- Pruebas locales (Postgres 16) y en produccion: dia 16 vuelve al menu 1; EP sin sopa; 250 PPL en dieta hiperproteica con +10 % acordado salen de la linea y se explotan aparte; ajuste de pechuga a 140 g aplica en todas las sedes; semana de 7 dias = 3.078 filas, 36.757 raciones, 43 productos; calculo inverso 48 t de pechuga -> 10-sep-2025 (4 s).

### Decisiones de diseño (reglas de Osvaldo del 31-oct-2026)
- Variantes de racion y grupos de poblacion por contrato: sexo en PPL, grupo etario en PAE; cualquier modalidad.
- Servido minimo = minuta; lo entregado puede ser mayor (presion de la poblacion) o el crudo menor (producto que rinde mas) via `gramajes_ajuste`, solo roles con Planeacion: aprobar; todo queda en bitacora.
- Dietas: la explosion resta la poblacion en dieta de la linea; reglas del contrato ganan al catalogo (p. ej. +10 % en vez de +20 %); `dieta_equivalencias` permite unificar varias dietas en una preparacion (pechuga para quienes no comen carne roja).
- Reglas de rotacion parametrizables por contrato (frutas y postres: 4 variedades/semana).
- El refrigerio USPEC es facturable aparte y no cambiable en menus especiales (`tiempos_comida.cambiable_especial`).

### Pendiente
- Pantallas de M2 (minutas y ciclos, cupos y dietas, explosion, ajustes de gramaje) en la app: siguiente paso.
- Asignar preparaciones concretas por dia del ciclo segun rotacion (hoy cada descriptor generico tiene una preparacion por defecto: Crema de verduras, Jugo de mora, Banano, Pan blanco, Bocadillo, Nectar de pera).
- Acta de inicio del contrato (fecha real del menu 1), parte real H/M de COCUC, poblacion en dieta real por sede y valor de racion por establecimiento.
- Estaciones de policia de Cucuta (MECUC, mas de una docena) como sedes EP con planta externa; origen de produccion configurable (planta propia, tercerizada, rancho de ERON).
- Anexos 22, 23, 24 y 26 no disponibles (Osvaldo no los tiene).
- Nutrifood (PAE Atlantico): grupos etarios y modalidades (RPS, industrializada, complemento AM/PM) cuando llegue la documentacion.

## 2026-11-01 · Roles de direccion e intercambios de menu por sede (version 0.3.0, parte 4A)

### Hecho
- Migracion 007 (`20261107000000_roles_directores_intercambios_menu.sql`).
- Director de compras recibe Planeacion: aprobar (plantilla y copias de cada empresa).
- Roles nuevos de plantilla, copiados a las empresas existentes:
  - Director de operaciones: Contratos V, Planeacion VA, WMS V, Distribucion VCA, Sede VCA, Calidad VCA, TH VC, Maestros V, Vehiculos VCA, Tableros V.
  - Director de planeacion: Contratos V, Planeacion VCA, Compras V, WMS V, Sede V, Calidad V, Maestros VCA, Tableros V.
- Proyeccion vs requerimiento:
  - Una proyeccion la corre quien tenga Planeacion o Compras: ver.
  - El requerimiento oficial exige Planeacion: crear, y se aprueba y envia a compras con Planeacion: aprobar. Al enviarlo sale aviso a Compras.
  - Opcion de simular incluyendo intercambios propuestos.
- Festivos de Colombia 2025-2026, dias habiles y ventanas de concertacion de menus:
  - Inicial = 15 dias habiles desde el inicio del contrato; parametro `dias_habiles_ajuste_menu` por empresa. Para USPEC-CTO-199-2025: 1 al 23 de abril de 2025.
  - Ademas, revisiones y oficios.
- Intercambios de menu:
  - Clases: concertado (indefinido), temporada (cosecha o escasez; exige fecha final), contingencia (paro, derrumbe; rige de inmediato aunque este propuesto) y especial (no aplica al refrigerio).
  - Alcance: una sede o todo el contrato. Cambio de preparacion (pollo broaster -> guisado), de componente o de ingrediente (lenteja -> arveja, con factor de cantidad), por dia del ciclo o todos los dias.
  - Estados: propuesto -> concertado -> aprobado por la entidad (o rechazado/anulado). Propone Planeacion o el administrador de sede; concerta quien tenga Planeacion o Sede: aprobar; aprueba entidad Planeacion: aprobar.
  - Fuera de ventana: queda marcado y no se concerta sin oficio o soporte.
- Notificaciones internas por modulo:
  - Una contingencia avisa con urgencia a Planeacion y a Calidad (aviso a entidad e interventoria pendiente) y deja registrar cuando se aviso a cada una.
  - Fuera de ventana avisa a Planeacion.
- El menu del dia y la explosion leen ciclo oficial -> intercambios vigentes (sede gana a contrato; contingencia > temporada > especial > concertado; dia especifico gana a todos los dias; el mas reciente gana) -> intercambio puntual del dia.
- Vista `v_intercambios` para la interventoria con las diferencias de cada sede frente a la minuta oficial.

### Pruebas (local, transaccion revertida)
- Semana 3-9 nov 2025, COCUC y Ocana.
- Lenteja -> arveja concertado para todo el contrato: 788 kg pasan de lenteja a arveja. Sin oficio no deja concertar porque esta fuera de ventana.
- Contingencia en Ocana el 5-nov, res sudada -> pierna de pollo:
  - Solo cambia Ocana: la pierna sube 53 kg y COCUC sigue con res.
  - Salen los tres avisos.
- Temporada pechuga -> pierna x1,25 en COCUC, propuesta:
  - La explosion oficial no la toma.
  - La simulacion con propuestos si: pechuga 1.839 -> 165 kg y pierna 641 -> 2.733 kg.
- Requerimiento convertido, aprobado y enviado; aviso en Compras. Semana completa de 6 sedes en 1,8 s.

### Pendiente
- 4B (con Fable): explosion por conjuntos (sin bucles, para meses y varias empresas), catalogo maestro por grupo, proyeccion consolidada multiempresa y calculo inverso consolidado.
- 4C: pantallas de M2, incluida la de intercambios (ya aparece en el menu como "pronto").
- Director administrativo: Osvaldo explicara sus funciones.
- Equipos de compras por CEDI y razon social (Barranquilla: Jessy Gonzalez, Ana Rivadeneira, Richard; Bogota: Wilson Castro).

## 2026-11-02 · Familias de contrato, familias de intercambio y explosion por conjuntos (version 0.4.0, parte 4B-1, modelo Fable 5.1)

### Hecho
- Migracion 008 (`20261108000000_familias_modalidad_intercambio_explosion_conjuntos.sql`), aplicada en Supabase.
- **Familias de contrato** (`plantillas_modalidad`): el esqueleto de cada modalidad (tiempos, componentes con su familia de intercambio, grupos de poblacion, variantes, reglas de rotacion, dias de atencion, avance del ciclo, uso de dietas). Seis plantillas: USPEC PPL (confirmada contra el Anexo 4 de Diestra), PAE (CAM, RPS, CPM, RI; grupos etarios 4-8, 9-13, 14-17; solo dias de clase; sin dietas), casinos de fuerzas, adulto mayor, ICBF primera infancia y bomberos (esqueletos por confirmar cuando llegue cada contrato). `aplicar_plantilla_modalidad(contrato)` crea lo que falte sin borrar nada; despues cada contrato se ajusta libremente.
- **Familias de intercambio por contrato** (`familias_intercambio`, `familia_opciones`, `componentes.familia_id`): cada componente de cada tiempo apunta a su familia (el proteico del desayuno no es el del almuerzo). Para Diestra quedaron 12 familias con 153 opciones (29 en la minuta oficial, el resto del catalogo del Anexo 4) y subfamilias: proteico desayuno = huevo, queso, salchicha; proteico almuerzo/cena = res, pollo, cerdo, pescado; panificado = pan, arepa, calado, galleta, envuelto; tuberculo = papa, yuca, platano, ahuyama, name.
- `sugerir_intercambios(sede, fecha, tiempo, componente)`: opciones de la familia ordenadas (vigentes primero, luego las que no rompen rotacion, las de minuta, la misma subfamilia), con veces usadas en la ventana de rotacion, ultima vez y bandera de rompe rotacion.
- **Opciones extraordinarias en caliente** (`agregar_opcion_familia`): preparacion existente, producto existente o producto nuevo (el chorizo concertado con la PPL); si lo hace el administrador de sede queda propuesta y avisa a planeacion; si lo hace planeacion queda vigente. La receta nueva arranca con el gramaje de la minuta patron del componente. El producto nuevo queda marcado `pendiente_revision` y avisa a Maestros. `decidir_opcion_familia`: permanente, solo extraordinaria o retirar. Un intercambio con una preparacion que no estaba en la familia la agrega solo.
- **Dietas estandarizadas** (`dieta_estandar`): la nutricionista fija que la gente en dieta recibe siempre tal preparacion por componente, por contrato o por una sola carcel, por dieta o para todas, por tiempo o para todos (huevo en desayuno, pechuga en almuerzo y cena). `dieta_equivalencias` ahora tambien por sede. Se arranca con todas las dietas del contrato y se estandariza despues del tamizaje.
- La poblacion en dieta siempre va por grupo (H/M o etario): si el contrato tiene un solo grupo se asigna solo; si tiene varios y no se indica, se rechaza (antes se ignoraba en la linea y se duplicaba en la explosion).
- **Explosion por conjuntos**: `calcular_explosion` ya no recorre fila por fila; arma sede x dia x menu x poblacion en tablas temporales y hace dos inserciones (linea y dietas). Mismo resultado que la version anterior (3.100 filas, 36.757 raciones en la semana de prueba) en 0,5 s; 90 dias x 6 sedes con dietas = 34.758 filas en 4,6 s local y dentro del limite en Supabase. Admite calcular por tramos (`p_desde`, `p_hasta`) para que la pantalla parta proyecciones de varios meses.
- `dia_ciclo` sin bucle dia a dia para PAE (cuenta los dias de clase con una sola consulta).

### Pruebas (local, transaccion revertida, y verificacion en produccion)
- Lenteja -> arveja en todo el contrato, contingencia en Ocana, 250 PPL en dieta hiperproteica con +10 %: mismos numeros que la version por bucles.
- Dieta estandarizada en COCUC: toda la poblacion en dieta sale con huevos revueltos en desayuno y pechuga asada en almuerzo y cena; la regla por tiempo gana a la general.
- Sugerencias para el proteico del almuerzo del 5-nov en COCUC (res sudada): 18 opciones; res dorada, al pimenton, asada, encebollada y sobrebarriga primero (misma subfamilia, no rompen rotacion); res sudada marcada como actual y repetida 3 veces en la ventana.
- Chorizo creado en caliente desde un intercambio de contingencia en Ocana: receta con 114 g de arranque, producto pendiente de revision, aviso a Maestros, y la explosion ya lo pide (393 raciones).
- Plantilla PAE aplicada a un contrato de prueba de Nutrifood: 4 tiempos, 18 componentes con familia, 3 grupos etarios, calendario propio, ciclo de 20.

### Pendiente
- 4B-2: catalogo maestro por grupo (producto maestro al que apuntan los productos de cada empresa, con mapeo sugerido para aprobar) y proyeccion consolidada multiempresa con calculo inverso consolidado.
- 4C: pantallas de M2, en especial la programacion multisemana (semanas -1, 0, +1, +2 y "agregar semana") con el intercambio desde la celda usando `sugerir_intercambios`.
- Confirmar las plantillas de PAE, casinos, adulto mayor, ICBF y bomberos contra los anexos reales cuando lleguen.

## 2026-11-02 · Catalogo maestro, proyeccion consolidada y primera auditoria (version 0.5.0, partes 4B-2 y correcciones)

### Hecho
- Migracion 009: catalogo maestro por grupo (`productos_maestros`, mapeo sugerido por parecido de nombre con pg_trgm, aprobar o rechazar; productos nuevos reciben sugerencia al crearse; dos productos de la misma empresa nunca se funden solos), proyeccion consolidada multiempresa (`crear_proyeccion_consolidada`, `calcular_proyeccion_consolidada`, `resumen_proyeccion_consolidada` por maestro con aporte por empresa y contrato) y calculo inverso consolidado (contenedor).
- Protocolo de auditoria (`docs/PROTOCOLO_AUDITORIA.md`) y reglas del frontend para un refresh visual facil.
- Primera auditoria independiente de M2 (migraciones 006 a 009): 2 criticos, 7 altos, 5 medios, 4 bajos. Migracion 010 corrige todos los criticos y altos y tres medios:
  - C1 aislamiento entre empresas: trigger de coherencia de empresa en 29 tablas (contrato, sede, receta, producto, ciclo... deben ser de la misma empresa de la fila) y funciones de lectura (menu del dia, poblacion, ventana, sustitucion, alertas) como SECURITY INVOKER para que respeten el RLS.
  - C2 atajo de administrador: `auth.uid() is null` reemplazado por `es_admin_sql()` (solo editor SQL o service_role; nunca anon ni authenticated por la API) en todas las funciones; ejecucion revocada a public y anon en todas las funciones y por defecto en las nuevas. Verificado en produccion: 0 atajos viejos, 0 funciones ejecutables por anon.
  - A1 un parte diario parcial ya no borra los demas grupos (el parte gana al cupo en su mismo grupo, variante y tiempo).
  - A2 cupos y partes por tiempo de comida (necesario para PAE: cada estudiante recibe un solo tiempo).
  - A3 dietas: nunca superan la poblacion del grupo (se prorratean); reglas con prioridad contrato > empresa > catalogo; una regla inactiva del contrato anula la del catalogo; las reglas de otra empresa ya no se aplican.
  - A4 intercambios: clase, alcance e inicio no se cambian por edicion; el administrador de sede solo propone y concerta para su sede; orden de estados obligatorio (propuesto, concertado, aprobado por la entidad).
  - A5 explosiones y consolidadas guardan los tramos calculados; quedan "parcial" hasta cubrir todo el periodo y el calculo inverso consolidado exige que esten completas.
  - A6 dias habiles y calendario propio excluyen festivos; festivos de Colombia generados por ley (Emiliani + Pascua) de 2024 a 2035.
  - A7 rendimiento: sin bitacora por fila en el detalle de la explosion, crudo efectivo en SQL integrable, raciones por tramo, RLS del detalle evaluado una sola vez, calculo por tramos de fechas y de sedes. Caso pesado del auditor (90 dias, 6 sedes, 4 dietas por sede, 149.364 filas): 11 s completo, 5 s por mes; la pantalla calcula por tramos de 15 dias.
  - M1 bloqueo al recalcular, M3 mapeo maestro solo del mismo grupo y unidad (lo sugerido no suma hasta aprobarse), M5 fechas por defecto en hora de Bogota.
- Regresion: la semana de prueba da exactamente lo mismo que antes de las correcciones (3.100 filas, 70.396 kg).

### Pendiente de la auditoria (medios y bajos)
- Reglas de dieta `tiempo_adicional` (hipoglucida y gestantes con 6 tiempos) y `metodo_prohibido`: falta definir con Osvaldo que se sirve en los tiempos adicionales.
- Bordes de intercambios: cambio de componente sin preparacion nueva; sustitucion de ingrediente por ciclo; intercambio especial de ingrediente sin tiempo que alcanza el refrigerio; intercambio de dia 1 que alcanza el ciclo alterno de festivos.
- Unificar `menu_excepciones` tipo intercambio con `intercambios_menu`; calculo inverso por contrato sin explosiones temporales.
- `raciones` cuenta personas-dia (renombrar o agregar tiempos servidos); borrar familias con anular; validar recetas contra la minuta patron.
- PAE con cientos de colegios: calculo asincrono (pg_cron o funcion con service_role) en vez de tramos desde la pantalla.
- Frontend (antes de la 4C): tokens con nombres semanticos (hoy `--cafe`, `--naranja` heredados de A2 PAN), quitar estilos en linea y colores fijos, `ESTADOS` de panaderia en `ui.js`, aplicar `color_primario`/`color_acento` de la empresa, componentes `Tabla` y `Campo`.

## 2026-11-03 · Etapa 4C: programacion multisemana, intercambio desde la celda, novedades PAE y empresas demo (version 0.6.0, Fable 5.1)

### Hecho
- **Limpieza del frontend** (pedida por la auditoria): tokens semanticos en `globals.css` (`--primario`, `--acento`, `--fondo`, `--superficie`...; los nombres de A2 PAN quedan como alias), sin CSS heredado de panaderia, estilos en linea reemplazados por utilidades, estados del dominio en `ui.js`, componentes nuevos `Tabla`, `Campo` y `Panel`, colores de marca de la empresa aplicados a los tokens al entrar, icono propio de Supply ERP (pestana, PWA y Apple) en vez del de A2 PAN.
- **Migracion 011**:
  - Novedades de servicio (`novedades_servicio`): "manana no hay clases" (sin clases, paro, acto civico, actividad, clima, orden publico, salud publica), por sede o todas, uno o varios dias. Tres salidas para la materia prima: **correr** (el menu pasa al siguiente dia de servicio, lo normal en PAE), **trasladar** (ese menu se sirve en la fecha escogida y lo demas no se mueve) o **perder** (el ciclo sigue). Guarda la foto de la materia prima del dia. Flujo: la propone sede o planeacion, la aprueba la direccion de operaciones (Sede o Planeacion: aprobar) y queda el registro del aviso a entidad e interventoria y de su aprobacion. Anularla devuelve calendario y menu.
  - `calendario_servicio.cuenta_ciclo`: dia sin servicio que si avanza el ciclo (menu perdido o trasladado).
  - RPC `programacion(contrato, desde, hasta, sedes, propuestos)`: la cuadricula completa (sedes, dias con festivos, menu por celda con origen e intercambio, novedades) en una llamada; maximo 10 semanas; un usuario amarrado a una sede solo ve la suya.
  - Dietas: confirmado por la nutricionista que no hay tiempos adicionales; la regla `tiempo_adicional` queda desactivada.
  - **Empresas de practica**: Demo USPEC (3 sedes: 2 ERON y una estacion), Demo PAE (4 colegios del Atlantico con cupos por tiempo y grupo etario, receso de octubre y vacaciones de diciembre) y Demo Casinos (2 casinos en Cartagena). Catalogo copiado de Diestra, plantilla de la modalidad aplicada, ciclo de menus armado desde las familias de intercambio, dietas de muestra en USPEC.
  - Hallazgo de rendimiento: el planificador de Postgres asumia 1.000 filas por cada funcion de tabla y disparaba el JIT (casi un segundo de compilacion por llamada). Con los tamanos reales declarados y el JIT apagado en las funciones pesadas: programacion de 4 semanas 0,3 s (antes 5,4 s), explosion de una semana 0,16 s, 90 dias 1,7 s (antes 4,6 s).
- Migracion 012: los componentes salen en el orden de la minuta.
- **Pantalla Programacion de menus** (`/programacion`): semanas relativas (-1, actual, +1, +2... y "agregar semana", se recuerda la seleccion), filtro de sede, cuadricula sede x dia con numero de menu y el proteico (o primer componente) de cada tiempo, texto azul para lo distinto al ciclo, puntos de color por clase de intercambio, dias sin servicio y festivos marcados. Clic en la celda abre el panel del dia: menu completo por tiempo y componente; **Cambiar** trae las opciones de la familia agrupadas por subfamilia con "en minuta", "repite" (rotacion) y ultima vez; "Otra opcion que no esta en la lista" crea la preparacion y el producto en caliente; clase, alcance (sede o contrato), vigencia (solo ese dia, cada vez que toque ese menu hasta una fecha, o indefinido), motivo y soporte. Desde el mismo panel se concerta, se registra la aprobacion de la entidad, se reporta el dia sin servicio y se aprueba o anula la novedad con sus avisos.
- **Pantalla Intercambios y novedades** (`/intercambios`): listas con estado, soportes y acciones (lo que se le muestra a la interventoria).
- Probado en produccion sobre las empresas de practica: contingencia en Demo USPEC (res al pimenton -> pierna de pollo solo en una sede, rige de inmediato, aviso interno) y novedad PAE en el Megacolegio (jueves sin clases, menu trasladado al martes siguiente; las otras sedes no se mueven).

### Pendiente
- Pantallas: explosion con botones 8/15/30/90 dias y rango, cupos y dietas, minutas y calendario, catalogo maestro y consolidada.
- Auditoria de la etapa 4C (funcional, seguridad, rendimiento, UI/UX).
- Para A2 PAN (anotado para ese proyecto): los usuarios piden ver la semana -1, la 0 y la +1 en la programacion semanal de produccion, porque los requerimientos de la semana 0 se producen hasta los primeros dias de la semana +1.
