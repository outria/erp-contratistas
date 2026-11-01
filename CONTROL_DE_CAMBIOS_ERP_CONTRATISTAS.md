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
