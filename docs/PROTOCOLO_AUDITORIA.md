# Protocolo de auditoria · Supply ERP

Acordado con Osvaldo el 2-nov-2026. Se corre al cerrar cada etapa, modulo o subrutina compleja (no en cada cambio menor).

## Quien audita
Un agente revisor independiente que no escribio el codigo: recibe el codigo y las reglas de negocio, no las conclusiones de quien lo construyo. Trabaja en solo lectura sobre una copia de la base de pruebas con datos reales (seed de Diestra); no toca produccion ni el repositorio. Para trabajo de mucho riesgo (dinero, facturacion, pagos, nomina) se usa el modelo mas fuerte disponible.

## Que revisa (siempre en este orden)
1. **Funciona y hace lo que debe**: cada regla de negocio del control de cambios contra el resultado real, con consultas que lo prueben (dobles conteos, filas que se pierden, nulos, prioridades, fechas y zona horaria America/Bogota).
2. **Seguridad**: RLS por empresa, funciones `security definer` sin control de permisos, fugas entre empresas, permisos de ejecucion de mas.
3. **Eficiencia**: tiempos contra el limite de 8 s de Supabase con tamanos realistas (USPEC: 6 a 30 sedes; PAE: cientos de colegios; 90 dias), indices, llamadas fila por fila.
4. **Diseno**: si el modelo es la forma mas eficaz y eficiente de cumplir las reglas, o que tan cerca esta; que va a doler cuando entren otras modalidades; codigo muerto o duplicado.
5. **Interfaz y experiencia (UI/UX)**: que sea intuitiva para quien la usa en su dia (comprador, planeador, administrador de rancho), legible en celular, consistente y agradable; flujos con el menor numero de pasos.

## Entrega
Informe en espanol con veredicto corto y hallazgos por severidad (Critico, Alto, Medio, Bajo), cada uno con evidencia, impacto y arreglo propuesto. Los criticos y altos se corrigen antes de seguir; medios y bajos quedan en el pendiente del control de cambios. El resumen de cada auditoria queda en la seccion de la version correspondiente.

## Frontend preparado para un refresh visual
Reglas para que cambiar la cara de la aplicacion sea cambiar pocos archivos:
- **Tokens de diseno** en `app/globals.css` (`:root`): colores, tipografia, radios, sombras y espaciados como variables CSS. Ninguna pagina usa colores o tamanos sueltos; si hace falta uno nuevo se crea el token.
- **Componentes base** en `components/ui.js` (botones, campos, tablas, tarjetas, avisos, modales, insignias de estado). Las paginas componen, no estilizan.
- **Componentes de dominio** (cuadricula de programacion, celda de menu, selector de intercambio, tabla de explosion) en `components/` con nombre propio, para reutilizarlos en otras pantallas y en la vista de TV.
- **Textos y catalogos** en `lib/catalogos.js` (etiquetas de estados, modalidades, tipos), no escritos dentro de las paginas.
- **Datos** por funciones RPC o vistas de la base; las paginas no arman logica de negocio en el navegador.
- Marca por empresa: `empresas.color_primario`, `color_acento` y `logo_url` alimentan los tokens al entrar a la empresa.

## Historial
| Fecha | Alcance | Resultado |
|---|---|---|
| 2026-11-02 | M2 Planeacion backend (mig 006 a 009) y frontend actual | En curso |
