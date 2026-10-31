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
