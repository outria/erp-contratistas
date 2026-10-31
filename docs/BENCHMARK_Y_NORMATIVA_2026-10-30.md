# Informe de contraparte: referentes ERP/WMS, three-way match y normativa colombiana para el ERP de contratistas de alimentación (PAE / USPEC / ICBF)

Fecha de corte: 30 oct 2026. Todo lo que no encontré en fuente pública lo digo explícitamente.

## 1. Funcionalidades de líderes que vale la pena copiar

### ERP generalistas

| Idea | Quién la hace | Pro para este ERP | Contra / cuidado |
|---|---|---|---|
| **Política de control de factura por producto: "cantidades ordenadas" vs "cantidades recibidas"** y campo "Debe pagarse: Sí / No / Excepción" en la factura de proveedor | Odoo 17/18 (Purchase > Facturación; override por producto) | Simple de explicar al equipo de compras: la factura solo pasa si lo facturado = lo recibido; la excepción salta sola | Odoo nativo no tiene tolerancias (es exacto o excepción); para perecederos con merma de peso toca añadir tolerancia propia |
| **Matching policy a 3 niveles: entidad legal, ítem, ítem+proveedor**, con tolerancia de precio unitario (%) y de total (% y/o monto), y override por línea de OC | Dynamics 365 Finance | Permite tolerancia distinta para pollo (peso variable) vs arroz (exacto) y por proveedor | Más tablas de parametrización; arrancar solo con nivel entidad + ítem |
| **Estados de match "Failed" con ícono y aprobación explícita "Aprobar contabilización con discrepancias"** | Dynamics 365 | Deja trazabilidad de quién aceptó la diferencia (clave con interventoría) | Sin disciplina de aprobación, se vuelve un botón de "pasar todo" |
| **Documentos separados OC → Goods Receipt PO → AP Invoice**, con alerta de que precios distintos distorsionan la valoración del inventario | SAP Business One | Es el mismo flujo que ya tienen (OC → recepción en bodega → factura); refuerza que la recepción se registre por conteo físico, no por remisión del proveedor | SAP B1 permite variaciones de precio sin revisión; copiar el flujo, no la laxitud |
| **Scorecard de proveedores alimentado por transacciones (OC, recepciones, facturas, match)**: entrega a tiempo, calidad, exactitud de factura, cumplimiento de OC, con peso y umbral por KPI, y resultados compartidos con el proveedor | Coupa Supplier Performance / SAP Ariba SLP | Ya tienen los datos en el flujo; separa fallas del proveedor de fallas internas (ej. aprobación tardía) | Si el ERP no registra la hora real de llegada y el rechazo en recepción, el KPI de entrega se inventa |
| **Portal de proveedor con "PO flip"** (el proveedor convierte la OC en factura/remisión desde el portal) | Coupa, Ariba | Reduce reproceso de digitación y hace que la factura nazca ya referenciada a la OC | Pequeños productores ACFC (Ley 2046) no van a usar un portal; dejar canal WhatsApp/foto + documento soporte |

### Software de food service institucional (hospitales, cárceles, colegios)

| Idea | Quién | Pro | Contra |
|---|---|---|---|
| **Menú cíclico como objeto de primer nivel** con reportes "Production Worksheet" y "Shopping List" derivados del ciclo (explosión por día del ciclo × censo) | Computrition Hospitality Suite | Es exactamente minuta cíclica → explosión → requisición a bodega; una sola fuente de verdad para producción y compras | Requiere censo/población actualizada por sede y por día; sin eso la explosión sobra o falta |
| **Tipos de dieta terapéutica y "sustituciones" definidas por tipo** (una receta base, reglas de sustitución por dieta) | Computrition, CBORD NetMenu | Para USPEC/PPL (hiposódica, diabética, blanda) evita duplicar recetas: la dieta es una regla sobre el menú base | Modelar sustituciones bien es trabajo de nutricionista, no de TI |
| **Catálogo central de ingredientes/recetas/menús, sedes piden sobre un maestro estandarizado**; pedidos directos de "floor stock" por unidad | CBORD NetMenu (multi-hospital) | Mapea a bodega central → sedes/comedores: cada sede pide solo del maestro, no inventa ítems | Necesita gobierno del maestro (quién crea ítems); ver riesgo 4 |
| **Costo en vivo de receta a partir del último precio de compra** y etiquetado de alérgenos automático | Galley, Apicbase, MarketMan | Costo por ración real vs precio de ración contratado, por sede y por ciclo | Si el precio se toma de la OC y no de la factura aceptada, el costo queda optimista |
| **Compra semiautomática ligada a precio de proveedor, inventario y menú planeado** | Galley | Pre-órdenes por ciclo (ya lo tienen como "preórdenes minuta proyección compras") | Para perecederos la propuesta debe respetar frecuencia de entrega por sede, no solo cantidad |

Nota: no encontré documentación pública de Infor que agregue algo distinto a lo anterior para este caso; lo omito antes que inventarlo.

## 2. Three-way match: cómo lo hacen y qué automatizan

- **Mecánica**: línea de factura vs línea de OC (precio) y vs recepción (cantidad). Dynamics lo formaliza en tres chequeos: cantidad facturada = cantidad recibida (exacto), precio unitario neto dentro de tolerancia %, y total neto dentro de tolerancia % y/o monto. Odoo lo reduce a cantidades (sin tolerancia nativa). SAP B1 lo deja a documentos encadenados y recomienda umbrales de precio con aprobación para lo que se salga.
- **Tolerancias típicas**: no hay un estándar de industria publicado; la documentación de Microsoft usa ejemplos de 2 % y 8 % en precio unitario y 10 % a 15 % en total. Hyperbots (sobre SAP) dice que se configuran por organización. Recomendación práctica para alimentos: cantidad exacta en unidades contadas; tolerancia de peso (ej. 2 a 3 %) solo en ítems de peso variable (cárnicos, frutas); precio 0 % contra lista de precios vigente del proveedor, con excepción aprobada si la lista cambió. Ponerlo parametrizable por ítem y por ítem+proveedor como D365.
- **Puntos de falla documentados (SAP B1 / DOKKA)**: entregas parciales con factura por el total; flete o costos agregados solo en la factura; facturas sin OC posteadas directo a gasto; unidades de medida distintas (caja vs unidad) que igual contabilizan; recepciones hechas desde el papel del proveedor y no desde conteo; recepción y factura en periodos distintos sin provisión.
- **Qué automatizan con IA/OCR**: captura de la factura (en Colombia esto se reemplaza en gran parte por el XML de la factura electrónica DIAN, que ya trae NIT, ítems, cantidades, precios e impuestos), emparejamiento automático de líneas contra OC y recepción, enrutamiento de excepciones a un aprobador con comentarios y bitácora, y bloqueo preventivo antes de contabilizar. Para este ERP: parsear el XML UBL de la factura electrónica, no hacer OCR del PDF, y usar OCR solo para remisiones en papel y documentos soporte de pequeños productores.

## 3. Normativa colombiana a parametrizar

### (a) Aceptación tácita de la factura electrónica (3 días hábiles)
- Fuente oficial: Oficio DIAN 902369 de 2022 remite al Decreto 1074 de 2015, art. 2.2.2.53.4 (adicionado por el Decreto 1154 de 2020), numeral 2 (aceptación tácita), y al Anexo Técnico RADIAN v1.8, sección 6.5.5.7: la aceptación tácita aplica cuando no hay aceptación expresa ni reclamo "dentro de los tres días hábiles siguientes a la fecha del evento recibo del bien o prestación del servicio". El emisor la declara bajo juramento. Base legal: Ley 1231 de 2008 art. 2 modificado por Ley 2024 de 2020 art. 2 y C. de Co. arts. 772 y 773 (la ley 2024 la cito de memoria; las fuentes consultadas solo citan Decreto 1074/1154 y C. de Co.).
- Eventos RADIAN (Res. DIAN 085 de 2022 y Res. 15 de 2021 art. 7): acuse de recibo de la factura, recibo del bien o servicio, aceptación expresa / tácita, reclamo; además endosos, aval, pago. No registrar en RADIAN no impide que la factura sea título valor (Res. 15 de 2021 art. 31).
- Qué significa para radicación en el ERP: el reloj de 3 días hábiles arranca con el evento "recibo del bien/servicio", no con la radicación administrativa. El ERP debe (1) registrar fecha y hora del recibo físico en bodega como el hito que dispara el plazo, (2) correr el three-way match dentro de ese plazo, (3) emitir reclamo electrónico (evento RADIAN) antes de vencer si hay diferencia, y (4) marcar aceptación expresa cuando el match pasa. Vencido el plazo sin reclamo, la factura queda aceptada aunque la cantidad no cuadre.
- Alerta: hay proyecto de decreto del MinCIT (comentarios hasta 7 feb 2026) que contaría los 3 días desde la recepción de la factura, limitaría RADIAN a facturas con vocación de circulación y bloquearía notas crédito/débito tras la aceptación. No encontré que esté expedido. Parametrizar el "evento de inicio del plazo" como configurable (recibo del bien vs recepción de la factura).

### (b) Ley 2046 de 2020: mínimo 30 % compras locales
- Ley 2046 art. 7 y Concepto CCE C-1657 de 2025: entidades y privados que manejen recursos públicos y demanden alimentos deben comprar al menos 30 % del valor del presupuesto de alimentos a pequeños productores locales o ACFC y sus organizaciones; si no cumplen, reportan a la Mesa Técnica Nacional de Compra Pública de Alimentos. Pliegos deben dar mínimo 10 % de puntaje a quien se comprometa por encima del mínimo. Reglamento: Decreto 248 de 2021 (Decreto 1071 de 2015 arts. 2.20.1.2.1 a .3). La Res. UApA 0003 de 2026 lo recoge en su Anexo 4 de compras locales.
- Cómo se acredita en la práctica (guía ICBF a operadores, feb 2024): proveedor inscrito en el registro de la secretaría de agricultura departamental de la zona; organizaciones además en cámara de comercio; RUT con actividad agropecuaria; un pequeño productor obligado a facturar IVA no cuenta como pequeño productor; industrias transformadoras deben demostrar que la mayoría de su materia prima viene de PP/ACFC locales; carnes con guía de movilización y concepto sanitario; soporte de compra por factura electrónica, documento equivalente o documento soporte electrónico (no se exige FE al pequeño productor). Reporte mensual en formato F1.G5.ABS (Excel) cuyo total debe coincidir con las facturas, PDF de justificación si no se llega al 30 %, e informe anual a la Mesa Técnica en la primera quincena de octubre.
- Para el ERP: atributo "PP/ACFC local" en el tercero con número de registro departamental y vigencia, clasificación de cada compra, acumulador % por contrato y por mes, exportable al formato del supervisor.

### (c) Tope 50 % en adiciones (Ley 80 art. 40 parágrafo)
- Concepto CCE C-451 de 2025: los contratos no pueden adicionarse en más del 50 % de su valor inicial expresado en SMLMV. Cálculo: valor inicial ÷ SMLMV del año de suscripción = N salarios; tope de adición = N/2 salarios, convertidos al SMLMV vigente al momento de la adición (por eso el tope en pesos crece con el salario). El concepto no trata prórrogas en tiempo ni si el IVA cuenta; no encontré fuente oficial sobre IVA, así que dejarlo como parámetro.
- Para el ERP: guardar valor inicial, SMLMV de suscripción y acumulado de adiciones en SMLMV; alertar al 40 % y bloquear al 50 % salvo flag de excepción legal.

### (d) SIPSA del DANE
- Tres componentes: precios mayoristas, abastecimiento e insumos (SIPSA_I). Precios mayoristas: datos diarios y semanales actualizados a las 2:00 p.m. del mismo día, mensual el día 8; abastecimiento mensual, el día 10; insumos mensual (con subcomponentes bimestrales, trimestrales y semestrales), 197 municipios en 24 departamentos.
- Descarga estructurada: sí hay **servicio web SOAP** (WSDL: http://appweb.dane.gov.co/sipsaWS/SrvSipsaUpraBeanService?WSDL), con manual "DANE-webservice-SIPSA.pdf"; además tablero con exportación XLS y microdatos en el catálogo microdatos.dane.gov.co (serie SIPSA-I 2025 disponible). No hay API REST oficial.
- Para el ERP: job que consume el SOAP diario/semanal para las centrales relevantes (Barranquillita, Corabastos, etc.) y compara precio de OC vs precio mayorista como indicador de sobreprecio, no como precio de compra.

### (e) Lineamientos PAE (UApA) y USPEC
- **PAE**: la norma vigente es la **Resolución UApA 0003 del 7 ene 2026** (deroga la 335 de 2021 y las 421/2023, 374/2024 y 404/2024), ajustada por la **Resolución 0155 del 8 abr 2026**. Modalidades (art. 8): preparada en sitio, caliente transportada, industrializada, Canasta PAE en Casa y Bono Alimentario. La industrializada debe desmontarse progresivamente a más tardar en 2030, no se permite en preescolar de 6/8 horas ni en rural de difícil acceso, y se autoriza en emergencias de menos de 10 días. Aporte (art. 6): complemento jornada mañana/tarde 20 % de las RIEN, almuerzo 30 %, preescolar 6 horas 50 % y 8 horas 70 %, canasta en recesos mínimo 25 %. Grupos: la práctica territorial (Chía, Norte de Santander) usa cinco grupos por grado escolar (preescolar; 1° a 3°; 4° y 5°; 6° a 9°; 10° y 11°). Gramajes, ciclo de menús y límites de sodio/azúcar están en el Anexo 3 (alimentación saludable), que no está en el texto que pude leer. Talento humano: manipuladores idóneos y suficientes con condiciones laborales según Ley 2466 de 2025 art. 69. El rector certifica la entrega; la focalización se cruza con SIMAT y SISBÉN. Ciclos observados en territorio: 20 menús rotando cada 20 días (Chía).
- **USPEC/PPL**: no encontré en fuentes públicas abiertas el anexo técnico vigente (dietas terapéuticas, tiempos de comida, anexo de talento humano). Lo que hay: Res. USPEC 690 de 2018 (crea el comité de seguimiento al suministro por sistema de ración contratado vía Bolsa Mercantil, texto completo en Diario Oficial 50763), noticias de licitaciones 2023 (más de 124.000 PPL, interventoría > $800.000 millones, alertas de Procuraduría por falta de plan de contingencia) y el boletín INPEC 074/2024 (rancho El Pedregal, 3.687 PPL, énfasis en tiempos de entrega, temperatura y alimentación individualizada). El anexo técnico hay que bajarlo del proceso específico en SECOP II / BMC; recomiendo que Osvaldo lo aporte desde su contrato DIESTRA/G15. El procedimiento ICBF P13.PP sirve de modelo para parametrizar minutas: grupos etarios por modalidad, RIEN por tiempo de comida, listas de intercambios por GABAs y análisis con la TCAC.

## 4. Riesgos típicos y arranque por fases

Riesgos documentados (MRPeasy, DOKKA, SAP B1): elegir el sistema por una sola área; migrar datos sucios ("empezar de cero es mejor que construir sobre datos malos"); sponsor sin autoridad operativa; capacitación corta; sin integración contable (duplicación); recepciones hechas desde la remisión y no desde conteo; maestro de ítems/unidades sin dueño (caja vs unidad, ítems duplicados); costos de flete que solo aparecen en factura; esperar resultados inmediatos y abandonar el testeo.

MVP por fases sugerido:
1. **Fase 1 (bodega + recepción)**: maestro de ítems con UM y factor de conversión, lotes/vencimiento, recepción por conteo contra OC, PEPS/FEFO. Sin esto no hay three-way match ni costo real.
2. **Fase 2 (compras + match + factura electrónica)**: OC con lista de precios, lectura del XML DIAN, match con tolerancias por ítem/proveedor, reloj de 3 días hábiles y evento RADIAN, flag PP/ACFC y acumulador 30 %.
3. **Fase 3 (contrato → minuta → explosión)**: contrato con valor en SMLMV y tope 50 %, menú cíclico por modalidad y grupo, explosión por censo diario por sede, costo por ración vs precio contratado.
4. **Fase 4 (sedes, entrega, facturación a la entidad, scorecard)**: traslados, planillas de ración entregada certificadas, cuenta de cobro, KPIs de proveedor y comparador SIPSA.

Regla de oro: cada fase cierra con un KPI medible a 60 días (ej. % de facturas con match automático, % de recepciones con lote) antes de abrir la siguiente.

## Fuentes
- DIAN, Oficio 902369 de 2022 (Decreto 1074 art. 2.2.2.53.4, Anexo Técnico RADIAN 6.5.5.7): https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_902369_2022.htm
- Siempre al Día, factura electrónica título valor 2026: https://siemprealdia.co/colombia/impuestos/factura-electronica-como-titulo-valor/
- INCP, proyecto de decreto RADIAN 2026: https://incp.org.co/publicaciones/infoincp-publicaciones/impuestos/2026/01/proyecto-de-decreto-buscaria-aclarar-la-aplicacion-del-radian-y-la-aceptacion-de-la-factura-electronica-como-titulo-valor/
- CCE, Concepto C-1657 de 2025 (Ley 2046 / Decreto 248): https://relatoria.colombiacompra.gov.co/conceptos/c-1657-de-2025/
- Decreto 248 de 2021: https://www.unidadvictimas.gov.co/wp-content/uploads/Documentos/decretos/DECRETO_248_2021.pdf
- ICBF, capacitación operadores compras locales (feb 2024): https://www.icbf.gov.co/system/files/2024-02-29_capacitacion_operadores_-_ecl.pdf
- CCE, Concepto C-451 de 2025 (Ley 80 art. 40, 50 %): https://relatoria.colombiacompra.gov.co/conceptos/c-451-de-2025/
- DANE, servicio web SIPSA: https://www.dane.gov.co/index.php/estadisticas-por-tema/agropecuario/sistema-de-informacion-de-precios-sipsa/servicio-web-para-consulta-de-la-base-de-datos-de-sipsa
- DANE, ficha metodológica SIPSA_I: https://bibliotecadoctecnica.dane.gov.co/static/documentos/DIMPE/SIPSA_I/SIPSA_I_Ficha%20metodol%c3%b3gica.pdf
- DANE microdatos SIPSA-I 2025: https://microdatos.dane.gov.co/index.php/catalog/866/get-microdata
- UApA, Resolución 0003 de 2026 (PDF): https://caracoltv.brightspotcdn.com/89/e8/f24d26054e85b03916b1c70132e9/rsn-0003-lineamientos-tecnicos-0.pdf
- Norte de Santander, Mesa Pública PAE 2026 (Res. 0003 y 0155 de 2026): https://administrador.nortedesantander.gov.co/wp-content/uploads/2026/04/Informe-de-Rendicion-de-Cuentas-Primera-Mesa-Publica-PAE-2026-NdS.pdf
- Chía, cartilla PAE (modalidades, grupos, 20 menús): https://seceducacion.chia-cundinamarca.gov.co/2025/PAE/CARTILLA%20PAE.pdf
- MinEducación, Res. UApA 051 de 2025 (enfoque afro): https://www.mineducacion.gov.co/portal/salaprensa/Comunicados/425069:Gobierno-Nacional-lanza-lineamientos-del-PAE-con-enfoque-afro-alimentacion-escolar-con-identidad-y-justicia-etnica
- ICBF, procedimiento minutas patrón P13.PP: https://www.icbf.gov.co/system/files/procesos/p13.pp_procedimiento_elaboracion_actualizacion_minutas_patron_de_alimentos_para_las_modalidades_de_los_procesos_misionales_v1.pdf
- USPEC Res. 690 de 2018 (vLex): https://vlex.com.co/vid/resolucion-numero-000690-2018-744381573
- Asuntos Legales, alerta Procuraduría licitación USPEC: https://www.asuntoslegales.com.co/actualidad/procuraduria-alerta-sobre-riesgos-en-proceso-licitatorio-de-alimentacion-de-poblacion-carcelaria-3756329
- INPEC boletín 074/2024: https://inpec.gov.co/documents/d/guest/boletin-informativo-no-074-1
- Microsoft Learn, three-way matching policies D365: https://learn.microsoft.com/en-us/dynamics365/finance/accounts-payable/three-way-matching-policies
- Cybrosys, 3-way matching Odoo 18: https://www.cybrosys.com/blog/how-3-way-matching-works-in-odoo-18-purchase-module
- DOKKA, 3-way matching SAP Business One: https://dokka.com/3-way-matching-in-sap-business-one-how-to-eliminate-stock-variance-and-grpo-errors/
- Hyperbots, SAP invoice tolerance limits: https://www.hyperbots.com/glossary/sap-ecc-invoice-tolerance-limits
- Hyperbots, Coupa supplier scorecards: https://www.hyperbots.com/glossary/coupa-supplier-scorecards
- Computrition, hospital menu software: https://www.computrition.com/product-solutions/automated-hospital-menu-software
- CBORD NetMenu brochure: https://resources.cbord.com/hubfs/Collateral/Healthcare-Collateral/HC-NetMenu-IDN-HealthSystem-Enterprise-Brochure.pdf
- Galley vs Apicbase (comparación del vendedor): https://www.galleysolutions.com/galley-vs-apicbase
- MRPeasy, ERP implementation mistakes: https://www.mrpeasy.com/blog/erp-implementation-mistakes/

Nota para la sesión principal: no usé información de memoria en este informe; todo proviene de la web. Vacíos pendientes: anexo técnico USPEC vigente (dietas, tiempos de comida, talento humano) y Anexo 3 de la Res. 0003/2026 (gramajes, ciclo, sodio/azúcar); conviene pedírselos a Osvaldo desde sus contratos o bajarlos del proceso en SECOP II.