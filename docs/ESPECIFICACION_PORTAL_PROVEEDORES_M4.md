# Portal de proveedores (e-procurement, M4) · Especificacion funcional

Fecha: 5-nov-2026. Pedido de Osvaldo: credenciales para los proveedores con sus restricciones, donde oferten precio, compartan ficha tecnica y documentacion del producto, y hagan ofertas con condiciones distintas (por ejemplo, un precio menor cambiando la forma de pago). Revisado contra lo que hoy hacen las plataformas de referencia (SAP Ariba Supplier Lifecycle, Coupa Supplier Portal, Jaggaer ONE, Syspro Supply Chain Portal) y adaptado a contratistas de alimentacion del Estado.

## 1. Que hacen los referentes y que se toma
| Capacidad | Referentes | Se toma asi en Supply ERP |
|---|---|---|
| Autorregistro y onboarding por niveles segun riesgo, con validacion de documentos y estado en tiempo real | Ariba SLP, Coupa, Jaggaer | Invitacion desde Compras (no registro abierto): el proveedor completa su ficha, sube documentos y ve en que va su homologacion. Nivel de exigencia segun categoria (alimentos frescos > abarrotes > servicios). |
| Documentos con vencimiento y renovacion | Ariba, Coupa | Ya existe `tercero_documentos` con vencimiento; el portal deja subir la renovacion y avisa 30 dias antes. Carnets de manipulacion y conceptos sanitarios por producto o planta. |
| RFx (solicitud de cotizacion) con lineas, fecha de cierre y comparacion lado a lado | Ariba Sourcing, Jaggaer, Coupa Sourcing | `solicitudes_cotizacion` que nacen del requerimiento (explosion) o a mano: lineas por producto maestro con cantidad y periodo; se invita a proveedores homologados de la categoria; cierre con fecha y hora; comparativo automatico por precio por unidad de compra, condiciones y calificacion. |
| Ofertas alternativas (bid variants): el proveedor cotiza la linea con mas de una condicion (marca, presentacion, forma de pago, plazo de entrega, volumen minimo) | Ariba (alternative bids), Jaggaer | `ofertas` con N variantes por linea: cada variante trae precio, marca, presentacion, condicion de pago, plazo, lead time, minimo, vigencia y nota. "Contado $3.150, credito 30 dias $3.280" son dos variantes de la misma oferta. |
| Descuento por pronto pago / dynamic discounting (2/10 neto 30) | Coupa Pay, Ariba | Campo `descuento_pronto_pago` (porcentaje y dias) en la variante y en el precio del master; el comparativo muestra el costo efectivo segun la politica de pago de la empresa. |
| Catalogos y listas de precios con vigencia cargadas por el proveedor y aprobadas por el comprador | Coupa catalogs, Ariba catalogs | El proveedor carga o actualiza su lista (Excel o formulario); entra al master como `precios` en estado "propuesto" hasta que Compras lo acepte; si acepta, queda como precio vigente con origen `oferta_portal`. |
| Ficha tecnica y documentos por producto | Jaggaer (item attachments), Coupa | Adjuntos ligados a la oferta (`proveedor_productos.ficha_tecnica_id`, registro INVIMA, certificados de analisis por lote cuando aplique). |
| Confirmacion de OC, cambios y fecha de entrega comprometida | Ariba Network, Coupa | El proveedor ve sus OC, confirma, propone otra fecha o cantidad parcial; Compras acepta o rechaza el cambio. |
| Aviso de despacho (ASN) y guia | Ariba Network | Aviso de despacho con fecha, vehiculo, placa, temperatura de salida para perecederos, lotes y vencimientos; alimenta la recepcion en bodega (M5) y el control de calidad (M8). |
| Factura electronica y estado de pago | Coupa, Ariba | El proveedor ve el estado de su factura (recibida, conciliada, con diferencias, programada, pagada) y las fechas; la conciliacion de tres vias vive en M10. |
| Scorecard compartido con el proveedor | Coupa Supplier Performance, Ariba SLP | El proveedor ve su calificacion por periodo (cumplimiento, calidad, precio, servicio) y los rechazos con evidencia. |
| Mensajes y notificaciones | Todos | Buzon por evento (invitacion a cotizar, OC nueva, cambio, rechazo de lote, documento por vencer) por correo y en el portal; WhatsApp opcional (M12). |
| Multiempresa del lado del proveedor | Ariba (una cuenta, varios clientes) | Un mismo usuario proveedor puede atender a UT Diestra y a UT Nutrifood: la cuenta es del NIT, la relacion es por empresa. |

## 2. Seguridad y restricciones
- Rol `proveedor` (plantilla ya prevista en M0, `es_proveedor = true`): solo modulo M4. Usuarios creados por invitacion de Compras, ligados a un `tercero` (NIT) y con acceso solo a: sus datos, sus documentos, sus ofertas, sus OC, sus facturas y su scorecard. Nunca ve otros proveedores, precios ajenos ni el comparativo.
- RLS con una funcion `mi_tercero()` (el tercero del usuario autenticado) en todas las tablas del portal; las funciones de Compras siguen con `tiene_permiso(M3/M4)`.
- Todo lo que el proveedor cambia queda en estado "propuesto" hasta que Compras lo acepta (precios, documentos, datos bancarios). Los datos bancarios cambian solo con soporte y doble aprobacion (prevencion de fraude de cambio de cuenta).
- Bitacora completa; descarga de evidencias (quien oferto que y cuando) para la interventoria.

## 3. Modelo de datos (ya compatible con lo construido en M3)
- `terceros`, `tercero_documentos`, `tercero_bloqueos`, `tercero_evaluaciones`: ya existen (mig 024).
- `proveedor_productos` (oferta base: producto x marca x presentacion) y `precios` (vigencia, origen `oferta_portal`, y desde la mig 025: `condicion_pago`, `plazo_dias`, `descuento_pronto_pago_pct`, `descuento_pronto_pago_dias`, `minimo_pedido`, `oferta_linea_id`). Las propuestas del proveedor viven en `precios_propuestos` (tabla aparte, mig 028) para no chocar con la exclusion de vigencias del master; al aceptarlas entran a `precios`.
- Nuevas en M4: `solicitudes_cotizacion` (cabecera: empresa, origen explosion, fecha cierre, estado, invitados), `solicitud_lineas` (producto maestro, cantidad, unidad, periodo, lugar de entrega), `ofertas` (por proveedor y solicitud, estado enviada / retirada / adjudicada parcial), `oferta_lineas` (variante: linea, proveedor_producto, precio, condicion de pago, plazo, lead time, minimo, vigencia, nota), `adjudicaciones` (linea, variante, cantidad, motivo), `usuarios_proveedor` (perfil -> tercero, empresas a las que atiende), `oc_confirmaciones`, `avisos_despacho`.
- Comparativo: funcion `comparar_ofertas(solicitud)` que normaliza a precio por unidad de compra, aplica la politica de pago de la empresa (costo efectivo con descuento por pronto pago), muestra calificacion, lead time, bloqueos y prioridad INPEC, y propone la adjudicacion.

## 4. Flujo completo (como se vera en el dia a dia)
1. Planeacion aprueba un requerimiento (explosion) y Compras lo abre en Ordenes de compra.
2. Para lo que tiene precio homologado vigente, el sistema propone la OC directo (mejor opcion disponible, INPEC primero en su establecimiento). Para lo que no, o lo que Compras quiera licitar, crea una **solicitud de cotizacion** con fecha de cierre e invita a los homologados de la categoria.
3. El proveedor entra al portal, ve la solicitud, cotiza linea por linea con una o varias variantes (marca, empaque, contado vs. credito, pronto pago), adjunta ficha tecnica, y envia.
4. Al cierre, Compras ve el comparativo normalizado, adjudica (puede partir una linea entre dos proveedores) y el sistema genera las OC y actualiza el master de precios con origen `oferta_portal`.
5. El proveedor confirma la OC (o propone cambio), manda el aviso de despacho, la bodega recibe (M5), calidad registra (M8), la factura se concilia (M10) y el proveedor ve el estado de pago. Todo alimenta el scorecard.

## 5. Estado
Parte 1 construida en la migracion 028 (6-nov-2026): usuarios proveedor y RLS, solicitudes con variantes, comparativo, adjudicacion, precios propuestos, confirmacion de OC, documentos, pantallas /portal y /cotizaciones. Ver control de cambios v0.12.0.

## 6. Orden de construccion
M3 (ahora): OC con lugar de entrega y sugerencia de proveedor; master de precios con condiciones (variantes). Luego M4: usuarios proveedor y RLS, solicitudes de cotizacion y ofertas con variantes, comparativo y adjudicacion, confirmacion de OC, documentos desde el portal; despues, con M5/M8/M10: aviso de despacho, estado de factura y scorecard transaccional.

Fuentes consultadas: [Syspro Supply Chain Portal](https://www.syspro.com/product/supply-chain-portal/), [Vendor and supplier portals](https://customer-portals.pages.dev/use-cases/vendor-portals/), [Top 10 supplier portal platforms](https://www.rajeshkumar.xyz/blog/?p=1532), [Jaggaer features (G2)](https://www.g2.com/products/jaggaer/features), [SAP Ariba vs Coupa (Jaggaer)](https://www.jaggaer.com/blog/sap-ariba-vs-coupa), [What modern supplier portals must become](https://www.businessprocessincubator.com/content/what-modern-supplier-portals-must-become), [Coupa alternatives 2026](https://www.slash.com/blog/coupa-alternatives), [Supplier portal software for IT leaders](https://technologymatch.com/blog/best-supplier-portal-software-for-it-leaders).
