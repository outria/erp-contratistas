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

## Reglas para funciones nuevas
- El atajo de administrador SQL es `public.es_admin_sql()`; nunca `auth.uid() is null` (anon tambien tiene uid nulo).
- Toda funcion nueva se revoca a public y anon y se concede EXPLICITAMENTE a authenticated (`grant execute ... to authenticated`), sin depender del privilegio por defecto.
- Todo `update` y `delete` lleva `where` (incluso sobre temporales): Supabase lo exige al rol autenticado.
- Las tablas con vigencia (`fecha_desde`/`fecha_hasta`) se blindan con una constraint de exclusion `daterange ... with &&`; la funcion que abre una vigencia cierra la anterior el dia antes y la nueva termina el dia antes de la siguiente futura.
- Las funciones de lectura por contrato aplican `mi_sede(empresa)` para el usuario amarrado a una sede.
- En `update ... from` no se puede referenciar la tabla destino dentro de un `lateral`; usar subconsulta correlacionada en el `set`.

## Historial
| Fecha | Alcance | Resultado |
|---|---|---|
| 2026-11-02 | M2 Planeacion backend (mig 006 a 009) y frontend actual | 2 criticos, 7 altos, 5 medios, 4 bajos. Criticos, altos y 3 medios corregidos en mig 010 (v0.5.0); el resto en el pendiente del control de cambios. |
| 2026-11-03 | Etapa 4C: programacion multisemana, novedades PAE, empresas demo, UI/UX | 5 altos, 7 medios, 7 bajos. Altos y medios corregidos en mig 013 (v0.6.1) con las mejoras UI/UX 1 a 10; bajos en el pendiente. |
| 2026-11-05 | Etapa 4D: cupos y dietas, explosion, minutas y calendario, partes, negociacion (mig 017 a 022) | 1 critico, 5 altos, 9 medios, 11 bajos (`docs/auditorias/AUDITORIA_2026-11-05_etapa_4D.md`). Critico, altos y medios M1 a M9 corregidos en mig 023 y frontend (v0.8.2); bajos en el pendiente. |
| 2026-11-06 | Etapa M3 Compras (mig 024 a 026) y M4 portal parte 1 (mig 028), con Opus 5.5 | 1 critico, 6 altos, 8 medios, 10 bajos (`docs/auditorias/AUDITORIA_2026-11-06_etapa_M3_M4.md`). Critico, altos, medios y 5 bajos corregidos en mig 029 (v0.12.1); resto en el pendiente. |
