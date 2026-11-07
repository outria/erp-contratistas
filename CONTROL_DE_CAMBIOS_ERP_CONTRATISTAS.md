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

### Auditoria de la etapa 4C (03-nov-2026) y correcciones (migracion 013, version 0.6.1)
Veredicto del auditor: el nucleo funcional hace lo que dice (correr, perder y anular, excepcion de sede sobre la del contrato, sin fugas entre empresas), pero 5 hallazgos altos y 7 medios habia que corregir antes de seguir. Corregido:
- A1 Aprobacion de novedades: el aprobador de sede (Sede: aprobar) solo decide sobre su sede y nunca sobre lo que propuso el mismo; una novedad de todas las sedes solo la aprueba Planeacion: aprobar (direccion de operaciones o planeacion). Igual para registrar avisos.
- A2 Usuario amarrado a una sede: la programacion, las novedades y los intercambios solo le muestran su sede, tenga el permiso que tenga.
- A3 Rendimiento de la programacion: indices en las temporales, menu agrupado en una pasada, sin la foto de materia prima en la cuadricula (se carga al abrir el detalle), tope de 2.100 celdas (30 sedes x 10 semanas en 1,3 s; antes 10 s) y, con mas de 20 sedes, maximo 2 semanas salvo que se filtre una sede.
- A4 "Correr" solo existe donde el ciclo se corre (PAE y similares); en USPEC y casinos la base lo rechaza y la pantalla no lo ofrece: se traslada o se pierde.
- A5 Trasladar: a un dia sin servicio (sabado, festivo) habilita una jornada de reposicion; a un dia con menu exige confirmar que ese menu se desplaza y lo dice; solo un dia por novedad.
- M1 Sin novedades solapadas ni dos marcas de calendario para la misma sede y fecha. M2 "Solo este dia" se amarra a la fecha y no al dia del ciclo (sobrevive a que el ciclo se corra). M3 La foto de materia prima se toma despues del RLS, respeta la sede y no deja ruido en bitacora. M4 La pantalla no ofrece "todas las sedes" a quien no puede, y los errores de permiso salen en palabras de la operacion. M5 Las celdas dicen que paso con el menu: "menu trasladado al 10/11", "menu perdido", "trasladado del 5/11", "jornada de reposicion". M7 El contrato vigente abre primero. B5 bordes de estado.
- UI/UX: verbos "Proponer intercambio / Proponer novedad / Aprobado por la entidad", botones bloqueados mientras corre la accion, leyenda completa (novedad, sin servicio, festivo, hoy), columna de sedes fija al desplazar, radios accesibles con teclado y foco al abrir el panel, contraste del ambar como texto, texto sobre el primario segun el color de la empresa, confirmacion al anular desde la lista.
Queda en el pendiente (bajos): numeracion unica de semanas en el selector, abrir una novedad fuera de las semanas cargadas, `copiar_catalogo` solo agrega (no actualiza) y las sombras con el color de la marca vieja.

### 2026-11-03 (noche) · Programacion: menu estandar agrupado, cupos y gramajes (migraciones 014 y 015, version 0.6.2)
Pedido de Osvaldo al ver la pantalla: con un PAE de 147 colegios no se puede ver una fila por colegio, y faltaban los cupos (PPL, estudiantes) y los gramajes.
- **Filas agrupadas**: las sedes que llevan exactamente el mismo menu en el rango (y el mismo patron de servicio) salen en una sola fila. La mas numerosa es el "Menu estandar · N sedes" (desplegable con los nombres); solo se desglosan las sedes que se apartan por un intercambio, una novedad o una variante (en Diestra: 5 ERON en una fila y el Batallon aparte por ser EP sin sopa). Se puede apagar con "agrupar sedes con el mismo menu". El tope de la consulta ahora se mide en filas visibles (2.100 celdas) y no en sedes.
- **Cupos por celda**: cada celda muestra la cobertura del dia (PPL, estudiantes o cupos segun la modalidad), sumada sobre las sedes de la fila, con la poblacion en dieta y, en PAE, el desglose por tiempo (RPS, CAM, CPM, RI). En el panel del dia salen en grande. Sale de `poblacion_dia`, asi que respeta partes diarios y cupos por tiempo.
- **Gramajes por componente**: debajo de cada preparacion, el servido de la minuta patron y el crudo del ingrediente principal por racion, por grupo de poblacion (H/M en USPEC, grupos etarios en PAE); si todos los grupos son iguales se muestra una vez.
- En una fila agrupada, el panel pide a que sede se le registra el cambio o la novedad (o todo el contrato).
- Hallazgo propio: los cupos por tiempo tomaban un solo grupo etario; corregido en la 015 (RPS 1.700, CAM 851...).

### 2026-11-03 (noche) · Correcciones sobre la revision de Osvaldo (migracion 016, version 0.6.3)
- **Error "UPDATE requires a WHERE clause"** al apagar "agrupar sedes": la rama sin agrupacion actualizaba una tabla temporal sin `where`; Supabase lo bloquea para el rol autenticado. Corregido (`where true`). Regla para funciones nuevas: todo `update`/`delete`, incluso sobre temporales, lleva `where`.
- **Celda completa cuando la sede tiene una sola modalidad**: en la practica cada colegio atiende casi siempre una modalidad (RPS o RI). Si en el dia solo hay un tiempo con cupos, la celda muestra todos los componentes de ese tiempo (proteico, cereal, tuberculo, verdura, leguminosa, bebida, fruta); si la sede combina varias modalidades (RPS + CAM + CPM), queda el modo compacto de un componente principal por tiempo y el detalle en el panel del dia. En el panel, los tiempos sin cupos salen plegados.
- **Agrupacion por tiempos servidos**: la firma que junta sedes en una fila incluye ahora que tiempos tienen cupos ese dia; dos colegios con el mismo ciclo pero una con RPS y otra con RI ya no se mezclan.
- Demo PAE ajustada a la realidad: IE Tecnica y Megacolegio solo RPS, IE Rural solo RI, IE Normal RPS + CAM + CPM.
- Plantilla Excel entregada a Osvaldo para recoger la cobertura: USPEC (PPL por establecimiento, hombres y mujeres, poblacion por dieta terapeutica y sexo) y PAE (estudiantes por colegio, modalidad y grupo etario), mas casinos y otros por sede y tiempo. El modelo ya los recibe (`cupos_contrato` por grupo y tiempo, `dietas_poblacion` por grupo y dieta, `partes_diarios`); falta la pantalla de Cupos, dietas y novedades para cargarlos sin SQL y el importador desde Excel.

Pendiente que se agrega: pantalla de Cupos y dietas con importador Excel (prioridad alta, es lo que destraba la explosion real); grupos etarios por contrato parametrizables desde Minutas y calendario.

## 2026-11-04 · Poblacion simulada, pantalla de Cupos y dietas e importador Excel (migraciones 017 a 019, version 0.7.0)
Osvaldo no tiene a la mano la focalizacion PAE, los partes de guardia ni la BD de dietas, y pidio no vararse: simular con sus reglas y seguir.

### Hecho
- **Grupos etarios PAE** (mig 017): la plantilla pasa a cinco grupos (preescolar 3 a 5, 6 a 8, 9 a 13, 14 a 17, 18 o mas), parametrizables por contrato; los contratos PAE existentes se migran (4 a 8 pasa a 6 a 8). Los nombres se ajustan cuando llegue el lineamiento del contrato.
- **Simulador de poblacion** `simular_poblacion(semilla)` (mig 017), reproducible: Demo PAE crece a 34 colegios del Atlantico, cada uno con una modalidad (RPS o RI, pocos combinan con CAM/CPM) y participacion por grupo etario entre 15 % y 25 %; Demo USPEC pasa a 12 establecimientos sin mujeres (como los grupos 6 y 7); dietas para Demo USPEC y Diestra entre 0 % y 40 % de la PPL (moda cerca del 15 %), 84 a 92 % hipercalorica e hiperproteica, 3 a 7 % hiposodica, el resto contadas, gestantes solo donde hay mujeres (COCUC). Todo con fuente `SIMULADA ...` para reemplazarlo. Excel entregado: `Poblacion_SIMULADA_Supply_ERP_2026-11-04.xlsx`.
- Vistas planas `v_poblacion_vigente` y `v_dietas_vigentes` (security invoker) para revisar y exportar.
- **Programacion mas rapida** (mig 018): el menu se calcula una vez por "llave" (ciclo + variante + secuencia de dias) y se comparte entre las sedes sin intercambios propios; `dia_ciclo` cuenta los dias de servicio con un join a festivos en vez de llamar `es_dia_habil` dia por dia (88.000 llamadas en 34 colegios x 4 semanas). 34 colegios x 4 semanas: 2,0 s a 1,1 s; estimado 147 colegios: ~3,5 s. El rotulo de una fila agrupada muestra ahora las modalidades que sirve y la cobertura (Menu estandar · RPS · 13.341 estudiantes).
- **Pantalla Cupos y dietas** (`/cupos`, mig 019, menu M2/M3/M7):
  - Tabla por sede (y por modalidad en PAE) con cada grupo, total, desde cuando rige, fuente (chip "simulada"), vigencia futura y parte del dia; totales por grupo. Fecha "lo que rige el" para ver cualquier dia.
  - Panel de edicion por sede con fecha "rige desde" y fuente: `guardar_cupos` cierra la vigencia anterior el dia antes y abre la nueva; un cero quita el cupo; la variante es de la sede, no de la poblacion.
  - Pestana Dietas: por sede, poblacion, en dieta, %, columnas por dieta usada; panel por dieta y sexo con alerta si hay mas en dieta que poblacion; `guardar_dietas` con la misma regla de vigencias.
  - **Importar Excel**: lee la plantilla de recoleccion (hojas USPEC cupos con hombres y mujeres, USPEC dietas, PAE focalizacion, casinos) o cualquier Excel con columnas parecidas (sede/establecimiento/institucion, sexo o grupo etario, modalidad, dieta, cantidad, fecha). `importar_poblacion` resuelve sede por nombre exacto sin acentos o por parecido (trigramas, umbral 0,45), grupo por codigo o nombre, tiempo y dieta por codigo o nombre; previsualiza fila por fila con la sede resuelta y el error, y solo carga cuando todo cuadra (agrupando por sede y fecha, sumando filas repetidas). Deja rastro en `importaciones`.
  - Descargar Excel con lo vigente en el formato de la plantilla.
  - Permisos: M2 editar edita todo; M7 editar solo su sede (`puede_editar_poblacion`); importar solo M2.
- Plantilla de recoleccion entregada: `Plantilla_cobertura_cupos_dietas_Supply_ERP.xlsx`.

### Pendiente
- Partes diarios (parte de guardia dia a dia) desde la pantalla: hoy solo por SQL o importacion; la tabla ya existe y `poblacion_dia` la prioriza sobre los cupos.
- Grupos etarios y gramajes por grupo desde Minutas y calendario.
- Catalogo maestro y proyeccion consolidada en pantalla.

### 2026-11-04 (tarde) · Pantalla de Explosion de materiales (migracion 020, version 0.7.1)
- `/explosion` (menu M2/M3): lista de proyecciones y requerimientos del contrato (codigo, periodo, sedes, raciones, productos, estado, quien la creo) y **Nueva proyeccion** con presets de 8, 15, 30 y 90 dias o rango, todas las sedes o una seleccion, con o sin dietas, con o sin intercambios propuestos.
- **Calculo por tramos desde el navegador**: el tamano del tramo sale de un presupuesto de 160 sede-dias por llamada (USPEC con 4 tiempos y dietas pesa unas 3 veces mas por sede-dia que PAE); si una llamada se pasa del limite de 8 s de Supabase, el tramo se parte a la mitad y se reintenta. Barra de avance; una proyeccion a medias queda "parcial" y se completa con Recalcular. Probado en produccion: Demo USPEC 12 establecimientos x 30 dias = 327.120 raciones, 112 productos.
- Detalle: KPIs (raciones, productos, periodo, dias con servicio, sede-dias sin receta), raciones por tiempo de comida, pestanas **Productos** (a comprar en unidad de compra, promedio por dia, linea y dietas por separado, dias; filtro por categoria y busqueda), **Por sede**, **Por dia** (barras) y **Alertas** (sedes sin ciclo, sin cupos, dias sin receta). Detalle por producto: en que preparaciones (crudo por racion, raciones, ajustes de dieta o intercambio), por sede y por dia. Descargar Excel (productos, raciones por sede y por dia).
- Flujo de requerimiento desde la misma pantalla: convertir en requerimiento (M2 crear), aprobar y enviar a compras (M2 aprobar, deja aviso en M3), anular (queda para trazabilidad, `anular_explosion`).
- Funciones nuevas: `explosion_resumen`, `explosion_producto`, `explosiones_contrato`, `anular_explosion`, `puede_ver_explosion`; indice `explosion_detalle (explosion_id, producto_id)`.
- **Hallazgo propio corregido**: las raciones del tramo en PAE tomaban el maximo por tiempo y no la suma de las poblaciones (grupo x tiempo); una explosion de 34 colegios marcaba 6.332 raciones-dia en vez de 28.525. Los kilos no estaban afectados (salen fila a fila), solo el contador de raciones.
- Pendiente: presupuesto en pesos (llega con el master de precios, M3); comparar dos proyecciones; explosion desde la programacion con un clic.

### 2026-11-04 (noche) · Minutas y calendario, partes diarios y requerimiento por establecimiento (migracion 021, version 0.8.0)
Pantalla `/minutas` (menu M2/M3/M7) con cinco pestanas:
- **Ciclos de menu**: lista de versiones de la minuta (menus, casillas, cuantas sin receta, sedes que lo usan, estado, oficio); editor dia x tiempo x componente donde cada casilla se cambia con un selector de recetas de la familia del componente (★ las que ya estan en la minuta del contrato); nuevo ciclo vacio o copiando otro; poner vigente (exige todas las casillas con receta) y pasar a historico. Funciones `ciclo_detalle`, `guardar_ciclo_item`, `crear_ciclo`, `estado_ciclo`.
- **Ciclo por sede**: que ciclo, variante y modo de reinicio lleva cada sede, fecha del menu 1, desde cuando rige, el menu que toca hoy y las marcas futuras de calendario; asignacion a una o varias sedes a la vez (`asignar_ciclo`, cierra la asignacion anterior el dia antes).
- **Gramajes por grupo**: matriz componente x grupo (etario en PAE, hombres y mujeres en USPEC) con la porcion servida; la columna "receta" muestra lo que da hoy la receta de referencia. Se guarda como ajuste de contrato por componente y grupo con vigencia (`guardar_gramajes`).
  - **Cambio de fondo en `crudo_ingrediente`**: un ajuste a nivel de componente o preparacion escala TODA la receta en proporcion al ingrediente principal (antes aplicaba la porcion servida a cada ingrediente, con lo que la sal o el aceite tomaban el gramaje de la proteina). Un ajuste a nivel de producto sigue aplicando solo a ese producto.
- **Calendario**: meses en cuadricula con el estado de cada dia (servicio por regla, sin servicio, marcado sin servicio, jornada extra, solo algunas sedes, festivo, hoy); clic en primer y ultimo dia de un rango para marcar receso, vacaciones, paro o jornada de reposicion, para todo el contrato o algunas sedes, con opcion de que el ciclo siga corriendo; "volver a la regla" quita marcas (`calendario_contrato`, `marcar_calendario`; respeta las marcas que vienen de novedades aprobadas).
- **Partes diarios**: por dia, una fila por sede con una casilla por grupo (y por modalidad en PAE), el cupo vigente como referencia, boton "= cupo", diferencia parte vs cupo en rojo cuando se pasa; M7 solo su sede (`partes_dia`, `guardar_parte_diario`). El parte manda sobre el cupo en programacion y explosion (ya era asi en `poblacion_dia`).
- **Explosion · Por establecimiento (despacho)**: por sede, periodo, del menu X al menu Y, raciones, productos y perecederos, lista completa en panel y Excel con resumen, detalle y una hoja por sede. Es el insumo del picking de bodega y de las entregas directas en sede (`explosion_por_sede`).

Apuntes de Osvaldo para los modulos que siguen (se guardan aqui para no perderlos):
- De una proyeccion aprobada salen dos procesos en paralelo: (1) requerimiento a compras, donde M3 evalua y selecciona proveedores (comparativa de precios y condiciones, cumplimiento, calidad, bloqueos comerciales por morosidad u otra situacion); (2) requerimiento por establecimiento para que bodega haga el picking / prealistamiento y despache, con el detalle de que ciclo a que ciclo, de que menu a que menu y de que fecha a que fecha.
- La mayoria de proveedores entregan en el CEDI, pero algunos entregan directo en la unidad de servicio, sobre todo en USPEC (carceles grandes) con perecederos (fruver) y a veces otras categorias. El modelo de OC debe permitir lugar de entrega por sede.
- **Proyectos productivos del INPEC** (en la practica, las panaderias de cada establecimiento): por contrato hay que darles prioridad como primera opcion de compra; terminan siendo proveedores y es una obligacion contractual. En M3: marcar al proveedor como "proyecto productivo INPEC" ligado a un establecimiento, con prioridad en la seleccion para los productos que ofrece (pan y eventualmente hortalizas).

Pendiente: importar ciclo desde Excel (la minuta aprobada por la entidad); gramajes por sede (ajuste local) desde la pantalla; partes diarios por importacion; auditoria independiente de la etapa 4D (cupos, explosion, minutas) segun el protocolo.

## 2026-11-05 · Negociacion por volumen (migracion 022, version 0.8.1) y apuntes para Compras
Pedido de Osvaldo: una calculadora para negociar volumen (precio por cantidad, importaciones por contenedor) que junte varios contratos, o todos, o los que lleguen a una misma bodega, y diga que programas cubre y hasta que fecha.
- Pantalla `/negociacion` en el grupo Compras (M3 ver o M2 ver). Reusa la proyeccion consolidada (mig 009): se eligen contratos de una o varias empresas del grupo (agrupados por empresa, con sedes y cupos a la vista), periodo de 15 a 180 dias o rango, con o sin dietas. El calculo corre contrato por contrato y por tramos desde el navegador (misma rutina de la explosion, ahora compartida en `lib/tramos.js`) y al final cierra la consolidada.
- Detalle: periodo, contratos y sedes, raciones, productos del catalogo maestro; estado por contrato con enlace a su explosion; tabla de consumo del periodo por producto maestro con el total, el promedio diario y el aporte de cada contrato; filtro por categoria y busqueda; Excel con una columna por contrato.
- **Calculadora de cobertura** (`cobertura_volumen`): producto, cantidad en unidad de compra, toneladas o contenedores x kg, y los programas a cubrir (todos o un subconjunto). Reparte la cantidad dia a dia como la consume cada programa y devuelve hasta que fecha alcanza, dias de cobertura, consumo diario del conjunto, lo que queda, el reparto por contrato (promedio diario, participacion y cuanto le toca) y el consumo por mes. Si la cantidad supera el periodo proyectado, extrapola con el promedio diario y lo dice. Probado en produccion: un contenedor de 24 t de pechuga cubre los tres programas demo hasta el 5 de diciembre (774 kg/dia; USPEC 76,6 %, PAE 18,7 %, casinos 4,7 %).
- Las tres empresas de practica quedaron en un "Grupo de practica" con catalogo maestro aprobado (los productos son copias del mismo catalogo, casan exactos), asi la consolidada entre demos funciona igual que entre UT Diestra y UT Nutrifood.
- Correcciones de paso: `puede_ver_consolidada` y `crear_proyeccion_consolidada` usan `es_admin_sql()` (regla del protocolo) y validan grupo, periodo al reves y maximo un ano.
- Pendiente ligado: cuando exista Logistica (bodegas), agrupar los contratos por la bodega a la que llega el producto; precio y presupuesto cuando exista el master de precios.

Apuntes nuevos para Compras y el tablero:
- **Tablero de costo por tiempo de comida**: por programa, cuanto cuesta cada tiempo de comida (desayuno, almuerzo, cena, refrigerio; RPS, CAM, CPM, RI) y cada componente, con el mockup "RP" que se entrego como referencia. Depende del master de precios (M3): costo = crudo por racion x precio vigente. Queda para cuando entren los precios; el diseno visual se afina al final.
- Compras (M3) debe traer: evaluacion y seleccion de proveedores (comparativa de precios y condiciones, cumplimiento, calidad, bloqueos comerciales por morosidad u otra causa), lugar de entrega por sede en la OC (entregas directas de perecederos en carceles grandes), y proveedor "proyecto productivo INPEC" ligado a establecimiento con prioridad contractual.

### 2026-11-05 · Auditoria independiente de la etapa 4D y correcciones (migracion 023, version 0.8.2)
Informe completo en `docs/auditorias/AUDITORIA_2026-11-05_etapa_4D.md` (1 critico, 5 altos, 9 medios, 11 bajos; seguridad entre empresas cerrada: 23 de 23 funciones rechazan al usuario ajeno; `dia_ciclo` set-based identico al anterior en 9.774 celdas).
- **C1 (critico) corregido**: el parte diario sumaba al cupo cuando el cupo no tenia variante (caso real de Diestra: COCUC pasaba de 3.587 a 6.587 PPL y las dietas se descontaban dos veces). Ahora `poblacion_dia` deja que el parte mande por grupo y tiempo sin mirar la variante, y los partes se guardan sin variante (la variante es de la sede). Probado: parte de 3.000 reemplaza a 3.587.
- **A1**: vigencias solapadas. `guardar_cupos`, `guardar_dietas`, `guardar_gramajes` y `asignar_ciclo` cierran la nueva vigencia el dia antes de la siguiente futura; constraints de exclusion (`btree_gist`, `daterange`) en cupos, dietas, gramajes y sede_ciclo para que no vuelva a pasar. Al llegar un cupo por tiempo se cierra el "para todos los tiempos" del mismo grupo.
- **A2**: el importador exige la modalidad (RPS, CAM, CPM, RI) cuando el contrato reparte cupos por tiempo (PAE o contratos que ya la usan); la pantalla ofrece "modalidad para las filas que no la traen" para hojas que son de una sola modalidad.
- **A3 / M7**: `calcular_explosion` hace `analyze` al terminar; `sin_receta` sin correlacion (`except`); la pantalla pide el resumen pesado solo al terminar el calculo (`explosion_avance` ligero queda disponible).
- **A4 / M2**: `marcar_calendario` con parentesis correctos (ya no revienta una jornada de reposicion sobre un dia con novedad) y usa la regla del contrato (USPEC puede marcar un paro de fin de semana); devuelve el total de dias marcados.
- **A5**: importador reescrito con tablas temporales: cada nombre de sede se resuelve una sola vez y las sumas van en temporal. 2.040 filas: de 4,3 s a 0,08 s (exactas) y de 8,0 s a 0,09 s (por parecido). Tope de 5.000 filas por carga.
- **M1**: `estado_ciclo('vigente')` exige todas las casillas obligatorias (menus x componentes obligatorios menos los excluidos por la variante) y pasa a historico el vigente anterior de la misma variante.
- **M3**: la programacion calcula el gramaje de la celda con `crudo_ingrediente` (misma regla que la explosion): se ven los gramajes por grupo guardados en Minutas, con la nota del ajuste.
- **M4**: grants explicitos a authenticated (y service_role) para las 35 funciones de la etapa; regla agregada al protocolo.
- **M5**: `minutas_contrato` y `calendario_contrato` aplican `mi_sede` (el administrador de sede ve solo la suya).
- **M6**: el importador vuelve a previsualizar al cambiar la fecha, la hoja o la modalidad, y arranca con hoy (no con la fecha de consulta).
- **M8**: partes diarios con "= cupo en todas" y "Guardar todo (n)" para las sedes modificadas.
- **M9**: Excel de despacho con nombres de hoja unicos (hasta 200 sedes) y el boton dice cuantas hojas trae.
- Bajos (B1 a B11) y observaciones de diseno quedan en el pendiente; se retoman en el refresh de UI del final.

## 2026-11-05 · M3 Compras, parte 1: proveedores, homologacion y master de precios (migracion 024, version 0.9.0)
Apuntes nuevos de Osvaldo recogidos en el modelo:
- Un proveedor puede traer varias marcas de un producto en distintas unidades de empaque, y una marca la pueden traer varios proveedores (procesados); la materia prima natural muchas veces no tiene marca. Por eso la oferta es **proveedor x producto x marca (opcional) x presentacion (opcional)**, y todo se compara por **precio por unidad de compra** (precio / contenido de la presentacion x factor de compra).
- Los **proyectos productivos del INPEC** (en la practica las panaderias) son cada uno una razon social aparte que factura por su lado: se registran como proveedor propio, marcados "proyecto productivo", ligados a su establecimiento (sede del contrato), con prioridad contractual para lo que ofrecen (la seleccion automatica de la OC los pone de primeros para su establecimiento).
- Tablero de costo por tiempo de comida: ademas del costo por tiempo y componente, un resumen lateral por contrato con el menu mas y menos costoso, el tiempo de comida mas y menos costoso (por tiempo: el desayuno mas caro es el del menu X, el almuerzo mas barato el del menu Y), y una sugerencia de intercambios que bajarian el costo del ciclo o del mes. Se construye sobre el master de precios (siguiente paso).

Hecho:
- **Terceros** (`terceros`): maestro por empresa con NIT y DV calculado (`dv_nit`), tipo de proveedor (fabricante, distribuidor, importador, productor primario, proyecto productivo INPEC, transportador, servicios), categorias que surte, condiciones (entrega en CEDI / sede / ambos, condicion y plazo de pago, lead time, pedido minimo), datos tributarios y bancarios, estado de homologacion con vencimiento, calificacion; contactos por funcion; puntos de despacho.
- **Documentos exigidos** (catalogo de 15 tipos: RUT, camara, cedula RL, certificacion bancaria, datos personales, concepto sanitario, registro INVIMA, fichas tecnicas, BPM, saneamiento, carnets, transporte, referencias, estados financieros, resolucion INPEC) con fecha, vencimiento y estado (al dia, por vencer, vencido, falta); camara no se exige a personas naturales ni a proyectos productivos.
- **Bloqueos comerciales** (morosidad, calidad, incumplimiento, legal, documentos, otro) con vigencia; un bloqueo vigente saca al proveedor de la "mejor opcion" y frenara las OC; requiere Compras: aprobar; deja aviso en M3.
- **Evaluacion** por periodo (cumplimiento 35 %, calidad 30 %, precio 20 %, servicio 15 %) con concepto (confiable 85+, aceptable 70+, condicionado 50+, no confiable) que actualiza la calificacion del proveedor. El scorecard automatico llega con recepciones y facturas.
- **Marcas** y **presentaciones** (unidad de empaque de un producto con su contenido en unidad base) y **ofertas** (`proveedor_productos`) con estado de homologacion propio (propuesto, homologado, condicionado, rechazado, suspendido), primera opcion, lead time y entrega.
- **Master de precios** (`precios`): por oferta, con vigencia (cierre automatico del anterior, constraint de exclusion), IVA, origen (cotizacion, oferta del portal, negociacion, lista, factura, importacion), lugar de entrega; precio por unidad base calculado por trigger. `master_precios` compara todas las ofertas por producto y marca la mejor disponible (homologada, proveedor sin bloqueo) en la fecha que se consulte (sirve para revisar facturas).
- Pantallas: **Proveedores y homologacion** (lista con KPIs, filtro de pendientes, ficha con pestanas: productos y precios, documentos, bloqueos, evaluacion, contactos; alta de proveedor; alta de oferta con marca y presentacion nueva al vuelo y equivalencia inmediata por unidad de compra) y **Master de precios y ofertas** (por producto: mejor precio, mejor opcion, ofertas desplegables con diferencia porcentual vs. la mejor, registro de precio nuevo, Excel).
- Seguridad: RLS por empresa; escribir requiere Compras: crear (o Maestros: crear); homologar, bloquear y levantar bloqueos requieren Compras: aprobar; triggers validan que proveedor, producto y presentacion sean de la misma empresa; bitacora en todas las tablas.

Pendiente de M3 (siguiente): ordenes de compra con lugar de entrega por sede y generacion desde el requerimiento aprobado (sugerencia de proveedor por precio, homologacion, bloqueos y prioridad INPEC), tablero de costo por tiempo de comida con resumen lateral y sugerencia de intercambios, importacion de proveedores y precios desde Excel, portal de proveedores (M4).

## 2026-11-05 · M3 Compras, parte 2: ordenes de compra (migracion 025, version 0.10.0)
Apuntes nuevos de Osvaldo recogidos:
- **Portal de proveedores (e-procurement, M4)**: credenciales para los proveedores con sus restricciones; alli ofertan precio, comparten ficha tecnica y documentacion del producto, y pueden presentar **ofertas con condiciones distintas** (por ejemplo, un precio menor cambiando la forma de pago). Se reviso lo que hacen Ariba, Coupa, Jaggaer y Syspro y quedo la especificacion en `docs/ESPECIFICACION_PORTAL_PROVEEDORES_M4.md` (onboarding por invitacion, documentos con vencimiento, solicitudes de cotizacion con cierre, ofertas con variantes por linea, pronto pago, listas de precios propuestas que Compras acepta, confirmacion de OC, aviso de despacho, estado de factura, scorecard compartido, multiempresa del lado del proveedor, RLS con `mi_tercero()`).
- Para que todo quede sincronizado con esa estructura, `precios` ya trae las columnas que usaran las variantes del portal: plazo, descuento por pronto pago (porcentaje y dias), pedido minimo, estado (propuesto / aceptado / rechazado; hoy todo entra aceptado) y la variante de oferta de origen. La sugerencia de compra solo toma precios aceptados.

Hecho:
- **Ordenes de compra** (`ordenes_compra`, `oc_items`): consecutivo OC, proveedor, requerimiento y contrato de origen, **lugar de entrega** (CEDI o directo en el establecimiento, con la sede del contrato), fecha de entrega, condicion y plazo de pago, totales por trigger, estados borrador, aprobada, enviada, confirmada, recibida parcial, cerrada, anulada. Lineas con la descripcion congelada (producto, marca, presentacion), unidad de pedido, contenido en unidad base, cantidad, precio, IVA, lo que pedia el requerimiento y el motivo de la eleccion.
- **Sugerencia de compra** (`sugerir_compra`): por producto del requerimiento aprobado, lo requerido total y por establecimiento, lo ya cubierto con OC, y la asignacion propuesta: (a) el **proyecto productivo del INPEC** homologado y con precio cubre lo de su propio establecimiento con entrega directa; (b) el resto va al **preferido** o al de **mejor precio por unidad de compra** entre homologados o condicionados, sin bloqueo y con precio vigente; si el proveedor solo entrega en sede, una entrega por establecimiento, si no, una al CEDI. Trae todas las alternativas (incluidas las bloqueadas o sin precio, marcadas) para que compras cambie a mano.
- **Generacion de OC** (`generar_oc`): agrupa las lineas revisadas por proveedor + lugar + establecimiento, una OC en borrador por grupo, con las condiciones del proveedor; rechaza proveedores con bloqueo vigente. OC manual (`guardar_oc`, `guardar_oc_item`) para urgencias.
- **Flujo** (`estado_oc`): aprobar (Compras: aprobar; exige lineas y proveedor sin bloqueo), enviar (aviso en M3 y aviso a bodega en M5 con lugar y fecha de entrega), registrar confirmacion del proveedor (fecha comprometida y observaciones; en M4 lo hara el proveedor), cerrar, anular con motivo (no si ya tiene recepciones).
- Pantalla **Ordenes de compra**: KPIs; pestaña *Requerimientos por comprar* (aprobados, con avance de productos con OC) que abre la sugerencia: por producto el proveedor propuesto con motivo (INPEC prioritario, preferido, mejor precio, unica opcion), entrega, cantidad editable en unidad de pedido con su equivalencia, precio y total, cambiar proveedor entre las alternativas, quitar o asignar a mano, resumen de las OC que se van a crear y boton de generar; pestaña *Ordenes* con filtros, vistazo lateral y detalle imprimible (empresa, proveedor, lugar de entrega, lineas, totales) con las acciones del flujo y edicion de lineas en borrador.
- Probado en produccion (Demo USPEC): requerimiento de 3 dias (32.712 raciones, 63 productos) → sugerencia: arroz 4.819 kg = 555 kg a la panaderia del proyecto productivo de EPMSC Practica Norte (entrega directa) + 86 bultos de 50 kg a Distribuidora Costa Caribe al CEDI; 2 OC generadas, OC-000001 aprobada y enviada con avisos.

Pendiente de M3: tablero de costo por tiempo de comida y componente con resumen lateral y sugerencia de intercambios (migracion 026, en curso), importacion de proveedores y precios desde Excel, PDF/correo de la OC al proveedor (hoy: imprimir), recepcion contra OC (M5). Luego M4 segun la especificacion.

## 2026-11-05 · M3 Compras, parte 3: tablero de costo por tiempo de comida y componente (migracion 026, version 0.11.0)
Hecho:
- **`costo_ciclo`**: para un ciclo de menus, un grupo de referencia (por defecto el de mas cupos vigentes) y una fecha de precios, el costo por racion de cada casilla (menu x tiempo x componente) = suma de los ingredientes crudos de la receta (con los gramajes vigentes del contrato, misma regla `crudo_ingrediente` de la explosion) por el **mejor precio vigente por unidad base** del master (homologado o condicionado, sin bloqueo, aceptado). Marca las casillas con ingredientes sin precio (costo incompleto) y las que no tienen receta.
- **Resumen lateral** como lo pidio Osvaldo: de los N menus del ciclo, cual es el mas y el menos costoso; que tiempo pesa mas y cual menos; por tiempo, cual menu tiene el desayuno / almuerzo / cena / refrigerio mas caro y mas barato y que componente pesa mas; ranking de componentes; productos sin precio.
- **Sugerencias de intercambio**: por casilla, la alternativa mas barata de la misma familia de intercambio (o del mismo componente si no hay familia) con precio completo; ahorro por racion, por vuelta del ciclo y por mes (raciones por tiempo de la poblacion vigente x dias de servicio del mes / n menus) y el total si se aplicaran todas. El costo de cada alternativa se calcula una sola vez por (preparacion, componente): 285 casillas en 0,12 s local.
- **Precios simulados de practica** (`simular_precios_demo`): solo en empresas de practica, crea el proveedor "SIMULADO (practica)" y un precio a granel por categoria (rangos plausibles del mercado 2026, estables por producto) para lo que no tenga precio; todo marcado SIMULADO y el tablero avisa cuando los usa. Se reemplazan solos al registrar precios reales (el mejor precio gana) o se retiran bloqueando o inactivando ese proveedor.
- Pantalla **Costo por tiempo de comida** (menu Compras): selector de contrato, ciclo, grupo y fecha; KPIs; vista *Menu x tiempo* (con raciones/dia por tiempo, barra relativa, rojo y verde para el mas caro y el mas barato de cada tiempo) y vista *Menu x tiempo x componente* (casilla clicable con el detalle de ingredientes, crudo, precio, proveedor); resumen lateral en prosa; tabla de sugerencias con enlace al ciclo; Excel con las tres hojas.
- Probado en produccion (Demo USPEC, 116 precios simulados): racion-dia promedio $ 15.246 (desayuno 2.160, almuerzo 5.751, cena 5.741, refrigerio 1.594), menu 3 el mas caro ($ 18.317), menu 2 el mas barato ($ 13.348); 15 sugerencias con ahorro de hasta $ 34 millones al mes cada una (precios simulados, solo mecanica).

Notas: el ahorro de las sugerencias no revisa las reglas de variedad ni el aporte nutricional (eso lo valida nutricion al aplicarlas en el ciclo); con precios reales y familias bien cargadas las sugerencias se vuelven utiles. Pendiente en M3: importacion de proveedores y precios desde Excel, PDF/correo de la OC. Sigue la auditoria independiente de la etapa M3 (migraciones 024 a 026) y luego M4 portal.

## 2026-11-06 · M4 Portal de proveedores, parte 1 (migracion 028, version 0.12.0)
Hecho (segun `docs/ESPECIFICACION_PORTAL_PROVEEDORES_M4.md`):
- **Identidad del proveedor**: `usuarios_proveedor` liga una cuenta (correo) a un tercero por empresa; rol `proveedor` (solo M4). `es_miembro` ya NO incluye a los proveedores (ninguna policy "miembro de la empresa" les abre nada); `es_proveedor_de` y `mi_tercero(empresa)` son la llave del portal. Policies nuevas: el proveedor ve la empresa, su tercero, sus documentos, sus ofertas de catalogo y precios, sus OC (enviadas en adelante) y sus lineas, el catalogo de productos, marcas y presentaciones, las solicitudes publicadas a las que fue invitado, sus ofertas y sus propuestas. Storage: sube y ve solo bajo `<empresa>/proveedor/<su tercero>/`. Probado: un usuario proveedor ve 1 tercero (el suyo), 0 explosiones, 0 cupos, 0 OC ajenas.
- **Invitacion** (`invitar_usuario_proveedor`): Compras registra el correo en la ficha del proveedor (seccion *Usuarios del portal*); si la cuenta ya existe en Supabase Auth queda activa (membresia con rol proveedor, perfil tipo proveedor), si no, queda pendiente hasta que el administrador la invite en Authentication y vuelva a dar clic. Un correo de usuario interno no puede ser proveedor. `desactivar_usuario_proveedor` apaga cuenta y membresia.
- **Solicitudes de cotizacion** (consecutivo SO): cabecera (titulo, requerimiento o contrato, lugar y ventana de entrega, cierre con hora, condiciones), lineas (producto, cantidad en unidad de compra, establecimiento opcional, especificacion), invitados (automatico: homologados activos sin bloqueo de las categorias de las lineas; o elegidos). Desde un requerimiento aprobado trae las cantidades y puede limitarse a lo que no tiene precio homologado. Estados borrador, publicada (notifica), cerrada (los borradores de oferta no cuentan), reabierta, adjudicada, anulada.
- **Ofertas con variantes** (`ofertas`, `oferta_lineas`): el proveedor cotiza cada linea con una o varias opciones: marca, presentacion y contenido, precio por presentacion (o granel), IVA, forma de pago y plazo, descuento por pronto pago (% y dias), dias de entrega, pedido minimo, lugar de entrega, flete, origen, registro INVIMA, ficha tecnica, nota. El trigger normaliza a precio por unidad de compra. Envia la oferta (con validez y observaciones), puede ajustarla hasta el cierre (la ultima version vale) o retirarla. Marca "vio la solicitud".
- **Comparativo** (`comparar_ofertas`): por linea, todas las variantes enviadas ordenadas por **costo efectivo** (precio por unidad de compra menos pronto pago si la empresa lo aprovecha: `config_empresa` `compras.aprovecha_pronto_pago`, por defecto si), contra el precio del master de hoy, con calificacion, homologacion, bloqueo, INPEC, visto y enviado por invitado.
- **Adjudicacion** (`adjudicar_solicitud`, Compras: aprobar): por linea y variante, con cantidad (una linea puede partirse); cada variante adjudicada entra al catalogo del proveedor (producto x marca x presentacion homologada) y al master de precios con origen `oferta_portal` y sus condiciones; se generan OC en borrador por proveedor + lugar + establecimiento ligadas al requerimiento; estados de ofertas adjudicada / parcial / no adjudicada.
- **Precios propuestos** (`precios_propuestos`, tabla aparte para no chocar con la vigencia del master): el proveedor propone precio y condiciones sobre una oferta homologada o ofrece un producto nuevo (queda "propuesto" hasta homologar); Compras acepta (entra al master cerrando el anterior el dia antes) o rechaza con nota; avisos en M3.
- **Confirmacion de OC** desde el portal (`portal_confirmar_oc`): confirma con fecha o pide cambio (aviso de prioridad alta a Compras). **Documentos** (`portal_documento`): el proveedor sube o renueva cada documento requerido; vence se calcula con la vigencia del tipo; Compras valida.
- Pantallas: **/portal** (solo cuentas proveedor; un proveedor que entra a otra ruta es redirigido): Inicio con pendientes, Cotizaciones (cotizar con variantes y enviar), Mis productos y precios (proponer precio, ofrecer producto), Ordenes de compra (confirmar o pedir cambio, detalle), Documentos (subir, renovar, ver), Calificacion. **/cotizaciones** (Compras): lista, nueva (desde requerimiento o a mano, invitados automaticos o elegidos), detalle con invitados (estado de cuenta de portal, visto, oferta), comparativo con adjudicacion por cantidad y "elegir la mejor de cada linea", pestaña de precios propuestos. Ficha del proveedor: *Usuarios del portal*.
- Probado en local con roles reales (authenticator + claims): invitacion, solicitud desde requerimiento (48 lineas sin precio, 2 invitados), publicacion, el proveedor ve solo lo suyo, cotiza 2 variantes (contado $60.000 y credito 30 d $63.000 con 2 % a 10 d), envia, propone precio nuevo; Compras compara, adjudica la variante 1 y sale OC-000001 (18 cajas, $1.080.000) con el precio en el master origen oferta_portal; acepta la propuesta y entra al master desde hoy. En produccion: SO-000001 publicada sobre EXP-000003 (63 lineas, 2 invitados).

Para probar el portal con un proveedor de verdad falta un paso que hace el administrador: crear la cuenta del proveedor en Supabase (Authentication > Users > Add user, con su correo) y luego "Invitar / activar" en la ficha del proveedor.

Pendiente de M4 (parte 2): correo al proveedor con la invitacion a cotizar y la OC (edge function), aviso de despacho (ASN) con lotes y temperatura para la recepcion (M5), estado de factura y pago (M10), scorecard transaccional, ficha tecnica adjunta por variante desde el formulario de cotizacion (hoy: Documentos), alta de cuenta sin pasar por el dashboard (edge function con service role). Ajuste menor pendiente: `guardar_solicitud` debe avisar cuando el filtro "solo sin precio" deja cero lineas (se incluira en la migracion de correcciones de la auditoria M3).

## 2026-11-06 · Auditoria M3 + M4 parte 1 y correcciones (migracion 029, version 0.12.1)
Auditoria independiente (Opus 5.5, `docs/auditorias/AUDITORIA_2026-11-06_etapa_M3_M4.md`): 1 critico, 6 altos, 8 medios, 10 bajos. Paso bien: el proveedor no veia nada de otros proveedores ni de la empresa, las 18 funciones de Compras lo rechazan, el nuevo `es_miembro` no rompio a los internos, anon sin acceso y rutas de storage cerradas. **Correccion a v0.12.0**: alli dice que el proveedor "solo ve lo suyo"; la auditoria encontro que tambien leia por REST las notas internas de sus OC y otras columnas internas (A1). Quedo corregido aqui.

Corregido en la migracion 029 y frontend:
- **C1** Presentaciones con contenido fijo: `alta_oferta` y el portal ya no reescriben el contenido de una presentacion existente (error claro si no coincide) y un trigger lo impide para cualquier presentacion con ofertas. Probado: el intento de otro proveedor de cambiar "Bulto 50 kg" a 5.000 g se rechaza y la sugerencia sigue en 65 bultos.
- **A1** El proveedor ya no lee tablas internas: se quitaron sus policies sobre `ordenes_compra`, `oc_items`, `terceros`, `proveedor_productos`, `precios`, `solicitudes_cotizacion`, `solicitud_lineas` y `tercero_documentos`; el portal trabaja por RPC (`portal_oc_items` nuevo). Probado: 0 filas por REST en todas.
- **A2** Trigger `validar_empresa_m3m4` en 16 tablas de M3/M4 (tercero, requerimiento, contrato, sede, producto, oferta, solicitud, adjuntos...); `portal_resumen` filtrado por empresa. Probado: solicitud de Demo USPEC con requerimiento de Demo PAE y OC con tercero de PAE se rechazan.
- **A3** Documentos del proveedor: van a `documentos_propuestos` (pendientes) y Compras los valida o rechaza desde la ficha del proveedor (`resolver_documento_propuesto`); la ruta tiene que ser la del proveedor y el archivo tiene que existir; con vigencia fija el vencimiento lo calcula el sistema; el proveedor ya no edita ni borra adjuntos; la ficha tecnica de una variante tiene que ser un documento suyo; `portal_ofrecer_producto` no toca ofertas ya homologadas.
- **A4** Adjudicacion: solo con la solicitud cerrada (o pasado el cierre); tope de lo pedido + 10 %; una OC por proveedor + lugar + establecimiento + condicion de pago (contado sin plazo); unidad de pedido = la presentacion; ofertas vencidas rechazadas. Probado: contado 40 kg + credito 60 kg salen en dos OC (1 bulto contado, 2 bultos credito 60 d) rotuladas "Bulto 50 kg".
- **A5** La sugerencia de compra descuenta lo ya comprado (por establecimiento lo directo, en el CEDI lo del CEDI) y muestra "pendiente". Probado: 65 bultos, OC de 30, la sugerencia pasa a 35.
- **A6** Sugerencia liviana: reparto por sede compacto (se expande en el navegador), sin la lista completa por sede, filtro por categoria. PAE sintetico de 334 colegios y 90 dias: de 22,3 MB a 2,9 MB (0,7 MB por categoria, 1,7 s).
- **M1** Invitacion de usuario proveedor solo con correo confirmado; nunca un superadmin; no cambia el tipo de un usuario interno.
- **M2** Policies con initplan (`mis_empresas_internas`, `mis_empresas_compras`, `mis_terceros`): una evaluacion por consulta y no por fila.
- **M3** Comparativo sellado: sin precios hasta el cierre (aviso en pantalla); se puede "Cerrar ahora".
- **M4** Adjudicar sobre una oferta de catalogo suspendida o rechazada da error claro; si estaba propuesta, queda homologada.
- **M5** Solicitud desde requerimiento con entrega en el establecimiento: una linea por producto y establecimiento (probado: 564 lineas en 12 establecimientos).
- **M6** Bitacora en las tablas de OC y del portal; cada envio de oferta guarda una foto de sus variantes (`ofertas.envios`).
- **M7** `costo_ciclo` usa las raciones de las sedes con el ciclo vigente. Probado con Diestra: `CICLO_EP` pasa de 5.225 a 26 raciones por tiempo; la pantalla dice cuantas sedes usan el ciclo.
- **M8** Sin cambios a ofertas ya evaluadas; el comparativo marca "editada despues de enviada".
- **Bajos** B1 (funciones revocadas a anon), B4 (contado sin plazo en `generar_oc`), B6 (invitados solo homologados o condicionados y validos), B7 (enlace de precio propuesto), B10 (sin NOTICE). Aviso cuando "solo sin precio" deja la solicitud sin lineas.

Pendiente de la auditoria (bajos): B2 cast de storage con rutas no uuid, B3 mover el cierre al reabrir, B5 IVA como costo en el comparativo, B8 precio de OC distinto al master, B9 lugar de entrega del precio y precios INPEC en el costeo general; UI en celular del comparativo (tarjetas por linea).

## 2026-11-06 · Compras publicas locales por contrato y contratos reales en practica (migracion 030, version 0.13.0)

### Lo que se busco y se encontro (Drive y correo director.compras@fombisol.com.co)
- **Formato oficial PAE** "Seguimiento compras publicas locales de alimentos vigencia 2026" (correos de Yesid con los contadores de Malambo y Atlantic, y de Maria Camila): hoja `Seguimiento_Compras_de_Alimento` con operador, modelo y modalidad de atencion, complemento, proveedor, tipo, representante legal, factura, fecha, tipo de producto, alimento, especie, cantidad, unidad, valor, proveedor Ley 2046 SI/NO y lugar del productor; hoja `Actualizacion_Carac_Prod_` (caracterizacion del productor). La plataforma lo importa y lo exporta igual (probado con el de UT Malambo septiembre: 237 renglones, $447.691.951, cuadra exacto).
- **Gobernacion del Atlantico** (correo del 6-oct-2026, contratos 202602581 y 202602582): obligacion 48, compras locales **minimo 30 % del valor total facturado mensualmente**; zona: Atlantico, Magdalena, Bolivar, Cesar, La Guajira, Sucre, Cordoba, San Andres, Cundinamarca, Santander y Norte de Santander; ademas Formato de Demanda Territorial (antes de cada mesa publica y mensual) y reporte mensual; si no se entrega cuenta como incumplimiento en la liquidacion. UT Atlantic se agoto: Zona 2 el 8-sep y Zona 1 el 15-sep-2026; septiembre sigue pendiente para legalizar el informe en SIFWEB.
- **UT Cenit**: contrato 003-C23-1600-2026 (LP 002-2026, Municipio de Cienaga), $9.261.946.604 con AIU, 64 dias escolares JM/JT y almuerzo, internados 84 dias calendario. Solo la pagina 1 y la resolucion de adjudicacion (correo de Carlos Yepes, 14-oct).
- **No encontrado**: contrato de UT Altis; contrato de UT Capital USPEC 2025 (el buzon director.compras@capitaluspec.com esta en el Outlook nuevo del computador, que no deja leerse desde aqui); % del rubro de alimentos y puntos adicionales ofrecidos de cada contrato.

### Hecho
- `contratos`: meta de compras locales (30 %) + adicional ofrecido en la oferta, base de calculo (`rubro_alimentos` o `facturado_total`), % del rubro de alimentos, zona de compras locales, valor de racion de referencia y fuente de cada dato.
- `terceros`: proveedor Ley 2046 (pequeno productor, ACFC, organizacion), vencimiento del certificado y municipio del productor (`guardar_ley2046_tercero`).
- `compras_locales_soportes`: soportes del mes (manual, importado del formato oficial u OC), con RLS por empresa y bitacora; una OC con soporte no se suma dos veces.
- `compras_locales_tablero()`: por contrato y mes, requerido = (meta + adicional) x base; base = facturado x rubro % o facturado total; si el mes no tiene facturado usa el promedio de los ultimos 3 (estimado); cumplimiento, faltante y alertas (falta rubro, falta facturado).
- Pantalla **Compras locales (Ley 2046)** y tarjeta en el Tablero (mes en curso y dos anteriores): parametros por contrato, soportes, importar y exportar el formato oficial.
- **Contratos reales en practica** (empresas `UT ... (practica)`, NIT 9000001NN, grupo de practica): UT Capital USPEC 2025 (rubro 72,83 %, promedio nacional Anexo 25, por confirmar), UT Alfa SCJ-1921-2026 ($42.186.012.028, racion $50.407), UT Nutrifood 202604177, UT Atlantic 202602581 y 202602582 (en liquidacion, base facturado total), UT Alianza Integral, UT Malambo, UT Cenit 003-C23-1600-2026, UT Bienestar Corporativo (ARC Covenas), UT Brigadistas SA-005-2026, UT CDR LP-006-2026, UT Altis y UT Proposito Superior SA-008-2026. Los que no tienen valor llevan $1 y "por confirmar". UT Diestra (real) queda con rubro 73,72 % (Anexo 25, grupo 15).

### Decision que hay que confirmar
- Osvaldo pidio medir sobre el rubro de alimentos (ej. 72 % en USPEC). El contrato del Atlantico dice "30 % del valor total facturado". Por eso la base quedo **por contrato**: Atlantic y Nutrifood sobre el facturado total; los demas sobre el rubro de alimentos hasta que se lea cada clausula.

### Reglas nuevas registradas (por construir)
1. **Seguimiento de OC en dos tableros.** Compras: del proveedor a la empresa, separando entrega en bodega/CEDI y entrega directa en el establecimiento (el archivo de Bogota los mezcla en "municipios"); el ciclo de una OC termina cuando el proveedor entrega el 100 % a satisfaccion (entradas parciales con su EA, saldo, dias de adelanto o retraso atribuidos a proveedor o logistica). Planeacion: logistica interna (picking, prealistamiento, distribucion y entrega a unidades de servicio) y seguimiento de inventario. La explosion ya es automatica y la maneja Compras; Planeacion conserva la gestion de entregas y ajustes.
2. **Consumo real diario por unidad de servicio.** Cada unidad reporta lo que consumio; si es menos de lo proyectado (rendimiento, ninos ausentes, etc.) el sobrante queda en inventario de la sede y se descuenta de los siguientes envios y de la siguiente proyeccion de compra.
3. **Compras locales**: meta por contrato = 30 % + lo ofrecido en la licitacion; pago contra entrega a pequenos productores; demanda territorial mensual para el Atlantico.

### Pendiente
- Datos por contrato (numero, valor, fechas, rubro %, puntos adicionales, base): mensajes de WhatsApp a los equipos de Bogota y Barranquilla.
- Cargar el facturado mensual (Contratos > Ejecucion) para que el indicador salga con base real.
- Marcar en Proveedores los terceros Ley 2046 (pantalla de edicion en la siguiente entrega; ya existe la funcion).
- Bajos de la auditoria anterior: B2, B3, B5, B8, B9; comparativo en celular.

## 2026-11-06 (noche) · Requerimientos de Planeacion y datos reales de UT Atlantic y UT Nutrifood (migraciones 031 y 032, version 0.14.0)

### Fuentes revisadas
- **Propuesta UT Atlantic** (zip de 152 MB compartido por Ligia Vidal, Juridica, por OneDrive el 6-nov): ofrecimiento economico por grupo, puntaje adicional de compras locales, SECOP CO1.RPL.5464337. Hallazgos: UT Atlantic ofrecio **+1 % de compras locales en ambos grupos (meta 31 %)**; presupuesto oficial por 74 dias escolares: grupo 1 $15.458.351.756 y grupo 2 $16.905.297.734; cupos diarios por modalidad y grupo etario (A a E): G1 almuerzo en sitio 10.701, transportado 8.632, complemento 814, industrializada 555; G2 13.076, 7.201, 1.494 y 819; valor de racion por grupo etario (almuerzo en sitio de $8.274 grupo A a $11.108 grupo E; transportado $9.342 a $12.268; complemento $6.794 a $7.493; industrializada $8.242 a $11.707); ciclo de 20 menus. El rubro de alimentos dentro de la racion da ~59 % ponderado (almuerzo en sitio 57 a 67 %, transportado 51 a 61 %, complemento ~44 %).
- **UT Nutrifood** (correo de Karen Benedetti 3-nov y clausulado 202604177): NIT 902.116.853-7; Fombisol 46 %, Corporacion Agrosocial 45 %, ADISP 9 %; LP-0011-2026 grupo 1; $20.018.163.982; 41 dias escolares o hasta agotar, vigente a 31-dic-2026; cobertura 78.074 raciones/dia ($488.247.902/dia); obligacion 48: 30 % del total facturado mensual **+ 1 %** ofrecido; pago a 90 dias; interventoria Consorcio AS Atlantico 2026; intercambios antes de las 10 a. m. del dia anterior. Planeacion RPS: zona 1 16.409 (complemento 5.018, almuerzo 11.391), zona 2 24.742.
- **Requerimientos de Planeacion** en el correo: codigos por programa (C028 a C030 Nutrifood, C047 a C050 Cenit, C070 a C072 Alianza Integral, C0103 a C0105 Malambo, C0148 y C0173 Grupo 15, C0180 Carceles y URIs CDR/Altis), con actualizaciones, adicionales y cancelaciones; cada uno trae precio de matriz y descuento de inventario.

### Hecho
- Migracion 031: `requerimientos_planeacion` y `requerimiento_lineas` (versionado por codigo y contrato, tipos planificada / actualizacion / adicional / cancelada, estados recibido / en compra / cubierto / cancelado), `importar_requerimiento` (cruza con el catalogo por nombre normalizado y crea los productos que falten marcados para revision) y `estado_requerimiento`. Escritura solo por funciones; lectura por empresa.
- Pantalla **Requerimientos de Planeacion**: importa el Excel "NECESIDAD DE COMPRA DE MATERIA PRIMA" tal cual llega (bodega, fecha de envio, ciclo, cobertura, renglones con entrega, dia a consumir, cantidad, descuento de inventario y cantidad a comprar), lista por estado y detalle.
- Migracion 032 (modo practica): UT Atlantic Z1 y Z2 y UT Nutrifood con valores, meta 31 %, base facturado total y fuentes; requerimientos reales C050 (Cenit, 18 renglones, $185.257.782) y C028 zona 1 (Nutrifood, proteinas, $31.388.400).

### Pendiente
- Cargar el resto de requerimientos (Alianza, Malambo, Grupo 15, Carceles y URIs, zona 2 de Nutrifood) con el importador; quedan en el correo.
- Del requerimiento a la OC con un clic (hoy la OC sale de la explosion; falta tomarla tambien del requerimiento).
- Revisar con Planeacion la diferencia del C028 entre "cantidad" y "valor matriz" en cerdo y pechuga.
- Instituciones educativas de Nutrifood (no vienen en la propuesta; pedir el documento de cobertura).

## 2026-11-06 (noche) · Auditoria de compras locales y correcciones (migracion 033, version 0.14.1)

Auditoria independiente (Opus 5.5) de la migracion 030, la pantalla de compras locales y el cambio de nombre: 0 criticos, 5 altos, 6 medios, 8 bajos (docs/auditorias/AUDITORIA_2026-11-06_compras_locales_030.md).

### Corregido (mig 033 y frontend)
- A1 tablero de compras locales reescrito con agregados unicos e indice por contrato y fecha: de 65 s a 0,1 s (3 meses) y de 258 s a 0,18 s (12 meses) con 300.000 OC.
- A2 meta minima 30 % y meta + adicional maximo 100 % (constraint y funcion); el tablero ya no divide por cero.
- A3 soportes: un soporte amarrado a una OC es solo documentacion (la OC cuenta sola), una OC tiene a lo sumo un soporte y del mismo contrato, no se repiten soportes sueltos, la importacion pasa por `importar_soportes_cl` que descarta repetidos, renglones que ya son OC, sin proveedor o valor, y fechas de otro mes.
- A4 contratos terminados: el tablero solo cuenta meses entre el inicio y la fecha fin vigente.
- A5 / B3 `es_practica` solo lo cambia el administrador de la plataforma (trigger) y es la unica definicion de empresa de practica (base y frontend).
- M1 tablero y soportes exigen Compras o Contratos (ver).
- M2 proveedor Ley 2046 exige tipo de productor; certificado vencido no cuenta.
- M3 numeros en formato colombiano (1.500.000) y validacion en el servidor; tope de 10 MB por archivo.
- M6 `guardar_parametros_cl` valida rangos, permite borrar la fuente y acepta Contratos editar.
- B1 creado_por lo pone el servidor; B5 "(en curso)" solo en el mes actual y mensaje amable sin la migracion; B7 grants a service_role; B8 logo R360.

### Pendiente
- M4 OC por fecha de recepcion y por lo recibido (llega con Inventario); IVA homogeneo entre pantalla y exportacion.
- M5 actualizar SheetJS a 0.20.x (la red del entorno bloquea cdn.sheetjs.com; hacerlo desde un equipo con acceso).
- B2, B4 (datos reales en empresas de practica: decidir si se dejan), B6.
- Auditar la migracion 031 (requerimientos) en la siguiente ronda.

## 2026-11-06 · Nutrifood real, SECOP II y requerimientos de noviembre (version 0.15.0)

### Hecho
- Mig 034: UT Nutrifood deja de ser empresa de practica (NIT 902.116.853-7); la ficha provisional vacia queda anulada.
- Mig 035: datos de SECOP II (datos abiertos, conjunto jbjy-vk9h) en 11 contratos: numero real de Soledad (SG-LP-2026-C003), Bienestar (0013-ARC-ENSUB-DLENS-2026, Escuela Naval de Suboficiales Barranquilla) y Capital (USPEC-CTO-191-2025); procesos, valores y fechas donde estaban de relleno; el resto en notas (Atlantic con adicion del 50 %, Cenit modificado con fin 9-nov).
- Mig 035: requerimientos vigentes C071 y C070.1 (PAE Soledad), CEI-C027 (CEI Soledad), C0105 (PAE Malambo), CEI-C029 (CEI Malambo) y C050-RPS (Cenit), con las inconsistencias del archivo anotadas en observaciones.
- Concepto juridico sobre la base de calculo de compras locales (Claude Docs).

### Pendiente
- Tanda 2 de requerimientos: Grupo 15 (C0073, C0090, C0148, C0173), Carceles/URI (C0182, C0183), Malambo C0104 y C0103, Cenit C049 RI/RPS y C048.
- Cobertura por grupo etario y gramajes en la programacion (Nutrifood y Soledad).
- SECOP: el portal pide reCAPTCHA para ver documentos; Malambo y Altis no aparecen en el conjunto de contratos de SECOP II.
