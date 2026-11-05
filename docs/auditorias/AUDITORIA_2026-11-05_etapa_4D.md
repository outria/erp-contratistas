# Auditoria independiente · Etapa 4D (cupos y dietas, explosion en pantalla, minutas y calendario, partes diarios)

Fecha: 5 de noviembre de 2026
Alcance: migraciones 017 a 021 (`20261117000000_poblacion_simulada.sql` a `20261121000000_minutas_calendario_partes.sql`), pantallas `/cupos`, `/explosion`, `/minutas`, componentes `cupos.js`, `minutas.js`, `lib/poblacion-excel.js`, `lib/tramos.js` y el rotulo de fila agrupada en `components/programacion.js`.
Base de pruebas: Postgres local (`sc9`, puerto 5499) con todas las migraciones y las empresas demo (Demo PAE 34 colegios, Demo USPEC 12 establecimientos, UT Diestra 6 ERON). Todas las pruebas que escriben corrieron dentro de `BEGIN ... ROLLBACK`. No se toco produccion ni el repositorio (solo se crea este informe).
Protocolo: `docs/PROTOCOLO_AUDITORIA.md` (orden funcional, seguridad, eficiencia, diseno, UI/UX; regla de `es_admin_sql()`).

## Veredicto

El nucleo de la etapa hace lo que dice: las vigencias de cupos y dietas se cierran el dia antes, el cero cierra, el importador resuelve sedes por parecido y solo carga cuando todo cuadra, el crudo proporcional escala la receta completa, la programacion por llave de menu separa bien a las sedes con intercambios propios y `dia_ciclo` set-based es identico al anterior (0 diferencias en 9.774 celdas). La seguridad entre empresas esta bien cerrada: ningun usuario de la empresa A pudo leer ni escribir nada de la empresa B por ninguna de las 25 funciones probadas, las vistas respetan RLS y anon no ejecuta nada.

Pero hay un critico y cinco altos que tocan directamente las raciones y los kilos que van a compras, y uno de ellos pega en el contrato real de Diestra con el flujo normal de la pantalla: el parte diario, tal como lo manda la pantalla, no reemplaza el cupo sino que se le suma. Tambien hay que arreglar antes de seguir las vigencias solapadas, la fila PAE sin modalidad en el importador, el tiempo de `explosion_resumen` despues de calcular y la precedencia de operadores en `marcar_calendario`.

## Resumen por severidad

| Severidad | Cantidad | Numeros |
|---|---|---|
| Critico | 1 | C1 |
| Alto | 5 | A1 a A5 |
| Medio | 9 | M1 a M9 |
| Bajo | 11 | B1 a B11 |

Criticos y altos se corrigen antes de seguir; medios y bajos van al pendiente del control de cambios.

---

## Hallazgos criticos

### C1 · El parte diario de la pantalla se SUMA al cupo en vez de reemplazarlo cuando el cupo no tiene variante (caso real de Diestra)

**Evidencia.** `poblacion_dia` (mig 010) considera que el parte reemplaza al cupo solo si coinciden grupo, variante y tiempo (`is not distinct from`). La pantalla de Partes (`components/minutas.js:257`) manda `variante_id: s.variante_id` (la variante del `sede_ciclo` de la sede). En Diestra los 6 ERON tienen cupos con `variante_id` nulo y `sede_ciclo` con variante ESTANDAR o EP:

```
nombre                           | var_cupo | var_sede | ppl
Batallon ASPC No. 30 Guasimales  |          | EP       |   26
COCUC Cucuta                     |          | ESTANDAR | 3985
EPMSC Aguachica                  |          | ESTANDAR |  186
... (los 6 ERON reales igual; las sedes simuladas si traen variante)
```

Prueba (COCUC, 10-nov-2026, `guardar_parte_diario` con `variante_id` = variante de la sede y cantidad 3000):

```
antes:   H | (null)    | total 3587 | en_dieta 1145 | linea 2442
despues: H | (null)    | total 3587 | en_dieta 1145 | linea 2442
         H | f3443324… | total 3000 | en_dieta 1145 | linea 1855
         M | (null)    | total  398 | ...
```

La poblacion H pasa de 3.587 a 6.587 y las 1.145 dietas se descuentan dos veces. En la explosion el join `p.variante_id is null or p.variante_id = m.variante_id` acepta ambas filas, asi que kilos, raciones y la cuadricula de programacion se duplican ese dia.

**Impacto.** El dia que el administrador de rancho registre el parte de guardia desde la pantalla (que es para lo que esta), la programacion y la explosion de Diestra duplican la poblacion de ese establecimiento. Es el contrato real, con el flujo normal, sin SQL.

**Arreglo propuesto.**
1. En `poblacion_dia`, el parte manda por grupo y tiempo, sin mirar la variante (la regla ya escrita en `guardar_cupos`: "la variante es de la sede, no de la poblacion"):
```sql
select * from c where not exists (select 1 from p where p.grupo_poblacion_id = c.grupo_poblacion_id
                                    and p.tiempo_comida_id is not distinct from c.tiempo_comida_id)
```
2. Normalizar datos: `update cupos c set variante_id = sc.variante_id from sede_ciclo sc ... where c.variante_id is null and contrato con mas de una variante`, o al reves, dejar la variante siempre nula en cupos y partes y tomarla de `sede_ciclo` (lo mas limpio, ver D1).
3. Mientras tanto la pantalla de Partes deberia usar la variante del cupo que muestra como referencia (`s.cupos[0].variante_id`) y no la de la sede.
4. Agregar una prueba de regresion: parte en sede con cupo sin variante debe dejar una sola fila por grupo.

---

## Hallazgos altos

### A1 · Vigencias solapadas: guardar con una fecha anterior a una vigencia futura no la cierra y la poblacion se duplica

**Evidencia.** `guardar_cupos` (mig 019, lineas 73 a 83) cierra solo las vigencias con `fecha_desde < p_desde`. Prueba en IE Antonio Narino, grupo G6_8 / RPS (cupo base 92 desde 1-sep):

```
guardar_cupos(..., '2026-12-01', 999)   -> 2026-09-01..2026-11-30 = 92 | 2026-12-01.. = 999   (bien)
guardar_cupos(..., '2026-11-20', 500)   -> 2026-09-01..2026-11-19 = 92 | 2026-11-20.. = 500 | 2026-12-01..2027-01-14 = 999
poblacion_dia(sede, '2026-12-05') -> total 1499   (deberia ser 999 o 500)
```

El mismo patron esta en `guardar_dietas`, `guardar_gramajes` (mig 021, lineas 232 a 240) y `asignar_ciclo` (lineas 207 a 210; en `sede_ciclo` no duplica porque `dia_ciclo` toma la de `vigente_desde` mayor, pero quedan dos filas abiertas y `minutas_contrato` puede mostrar una y la programacion otra segun la fecha). No hay constraint de exclusion que lo impida (`pg_constraint` de `cupos`, `dietas_poblacion`, `gramajes_ajuste`, `sede_ciclo`: solo checks de cantidad y modo).

**Impacto.** Escenario realista: se importa la focalizacion del proximo semestre (rige desde enero) y luego se corrige el cupo de hoy; desde enero la sede cuenta doble. Lo mismo con dietas y gramajes.

**Arreglo propuesto.**
1. Al abrir la vigencia nueva, cerrarla en el dia anterior a la siguiente vigencia futura del mismo grupo y tiempo, o rechazar con un mensaje claro ("ya hay una vigencia desde el 1-dic; edite esa"):
```sql
insert into public.cupos (..., fecha_desde, fecha_hasta, ...)
values (..., p_desde,
  (select min(c.fecha_desde) - 1 from public.cupos c where c.contrato_sede_id = p_contrato_sede
     and c.grupo_poblacion_id = v_g and c.tiempo_comida_id is not distinct from v_t and c.fecha_desde > p_desde), ...);
```
2. Blindar con `btree_gist`: `alter table cupos add constraint cupos_sin_solape exclude using gist (contrato_sede_id with =, grupo_poblacion_id with =, coalesce(tiempo_comida_id, '00000000-...') with =, daterange(fecha_desde, fecha_hasta, '[]') with &&)`. Igual en `dietas_poblacion` (dieta, grupo), `gramajes_ajuste` (contrato, sede, componente, preparacion, producto, grupo) y `sede_ciclo` (contrato_sede).
3. Aplicar la misma regla en `guardar_dietas`, `guardar_gramajes` y `asignar_ciclo`.

### A2 · El importador acepta filas PAE sin modalidad y crea cupos "para todos los tiempos": kilos para 4 modalidades que el colegio no sirve, y la pantalla los oculta

**Evidencia.** `importar_poblacion` (mig 019, lineas 164 a 169) solo resuelve el tiempo si viene; si la columna falta, `v_t` queda nulo y la fila pasa como ok. En PAE un cupo con tiempo nulo significa "este estudiante recibe todos los tiempos" (asi funciona para USPEC). Prueba: importar `{"sede":"IE Antonio Narino (Ponedera)","grupo":"G18","cantidad":"33"}` y explotar 1 dia de esa sede (solo RPS):

```
antes:  RPS G18 95 ... total 416 raciones, 140 filas
despues: RPS G18 95 + 33 (dos filas) | CAM G18 33 | CPM G18 33 | RI G18 33 -> 449 raciones, 187 filas
```

El contador de raciones sube 33 pero los kilos suben por 4 x 33 (incluidos CAM, CPM y RI que ese colegio no sirve). Ademas el cupo anterior G18/RPS no se cierra (el cierre compara tiempo con `is not distinct from`), asi que tambien duplica en RPS. En la pantalla de Cupos (`components/cupos.js:32`), en modo por tiempo solo se listan los tiempos con cupos; la fila sin modalidad no aparece en la tabla ni en el panel, aunque si entra a `totalSede` y a la explosion. `poblacion-excel.js` manda `tiempo: null` cuando no detecta una columna "modalidad/tiempo/complemento/racion".

**Impacto.** Un Excel real de focalizacion sin columna de modalidad (frecuente: una hoja por modalidad con el nombre en la pestana) infla la compra de un PAE de 147 colegios sin que nadie lo vea en pantalla.

**Arreglo propuesto.**
1. En `importar_poblacion`, si el contrato tiene `tiempos_comida` y la plantilla de la modalidad reparte cupos por tiempo (PAE, casinos: `plantillas_modalidad.esquema->>'cupos_por_tiempo'` o, mas simple, `modalidad <> 'uspec_ppl'`), exigir tiempo: `v_err := 'falta la modalidad (RPS, CAM, CPM, RI)'`.
2. En la pantalla, permitir elegir la modalidad para toda la hoja cuando el archivo no la trae (selector "Todas las filas son de: RPS").
3. En `TablaCupos`, mostrar una fila "sin modalidad" cuando existan cupos con tiempo nulo en un contrato por tiempo, con chip de advertencia.
4. Cerrar tambien las vigencias del mismo grupo con tiempo nulo cuando llega una con tiempo (o rechazar la mezcla).

### A3 · `explosion_resumen` justo despues de calcular se vuelve cuadratico (4,6 s con 45 k filas; con 170 k pasa de 8 s) y la pantalla lo llama tras cada tramo

**Evidencia.** El flujo real es: `calcular_explosion` inserta decenas de miles de filas y, antes de que corra autovacuum/analyze, la pantalla pide `explosion_resumen` (`app/(app)/explosion/page.js:144`, las dependencias de `useCarga` incluyen `progreso?.hechos`, es decir, una llamada por tramo). Con estadisticas viejas el planificador elige un nested loop para `sin_receta`:

```
PAE 34 colegios, 12 dias recien calculados (27 k filas):  sin_receta: Rows Removed by Join Filter: 4.132.155, 452 ms
PAE 34 colegios, 4 semanas (45 k filas):                  explosion_resumen = 4.586 ms
USPEC 12 x 30 dias (134 k filas):                         explosion_resumen = 3.629 ms sin analyze; 665 ms con analyze
Misma explosion de 27 k filas tras `analyze explosion_detalle`: explosion_resumen = 100 ms (antes 653 ms)
```

El costo crece con sede-dias x filas de detalle: un PAE de 147 colegios x 22 dias habiles (~3.200 sede-dias, ~200 k filas) supera con holgura los 8 s.

**Impacto.** La pantalla de explosion muestra "Falla" o se queda cargando justo en el caso para el que se hizo (PAE grande), y mientras calcula dispara una consulta pesada por tramo.

**Arreglo propuesto.**
1. Al final de `calcular_explosion`: `analyze public.explosion_detalle; analyze public.explosion_raciones;` (barato, 160 ms con 134 k filas).
2. Reescribir `sin_receta` sin correlacion:
```sql
'sin_receta', (select count(*) from (
    select contrato_sede_id, fecha from public.explosion_raciones where explosion_id = p_explosion and raciones > 0
    except
    select distinct contrato_sede_id, fecha from public.explosion_detalle where explosion_id = p_explosion) z)
```
3. En la pantalla, pedir el resumen al terminar (dependencia `progreso?.fin`) y, durante el calculo, solo el avance; o una funcion ligera `explosion_avance` que devuelva cubierto y raciones.

### A4 · `marcar_calendario`: precedencia de operadores; una jornada extra sobre un dia con marca de novedad rompe toda la operacion

**Evidencia.** Mig 021, lineas 288 y 289:
```sql
where not p_solo_habiles or p_atiende or public.es_dia_habil(g::date)
  and not exists (select 1 from public.calendario_servicio x where ... and x.fecha = g::date);
```
`and` liga mas fuerte que `or`, asi que el `not exists` solo protege la rama `es_dia_habil`. Con `p_atiende = true` (jornada de reposicion) o `p_solo_habiles = false` se intenta insertar sobre un dia que ya tiene marca de novedad (que el `delete` previo respeta a proposito):

```
marcar_calendario(pae, null, '2026-11-20', '2026-11-20', true, 'reposicion')
ERROR: duplicate key value violates unique constraint "calendario_servicio_unico"
```

La misma llamada con `p_atiende = false` y `p_solo_habiles = true` si respeta la marca (probado: 19-nov marcado, 20-nov con novedad intacto). "Volver a la regla" tambien respeta las de novedad (probado).

**Impacto.** Cualquier rango de reposicion que toque un dia con novedad aprobada falla completo con un error tecnico en pantalla; en PAE las novedades marcan el calendario solas, asi que va a pasar.

**Arreglo propuesto.** Parentesis y usar la regla del contrato (ver M2):
```sql
where (not p_solo_habiles or p_atiende or public.es_dia_servicio_base(p_contrato, g::date))
  and not exists (...)
```
y devolver el total acumulado (ver B1).

### A5 · `importar_poblacion` con el tamano real de un PAE (2.000 filas) tarda 8 s por parecido y 4,3 s exacto: se va a cortar

**Evidencia.** Prueba con las 34 sedes demo x 5 grupos x 3 modalidades x 4 repeticiones:

```
2.040 filas, nombres exactos:                     4.314 ms
2.040 filas, nombres con una letra de diferencia: 7.983 ms
  510 filas exactas: 812 ms; 510 por parecido con aplicar: 2.159 ms
```

Por cada fila se normaliza con `unaccent` toda la lista de sedes del contrato (dos veces cuando no hay exacto) y se recalcula `similarity`; con 147 colegios el barrido por fila es 4 veces mas largo. Ademas la pantalla llama la funcion dos veces (previsualizar y aplicar) y el acumulador `agr` es un jsonb que se reescribe por fila (`jsonb_set` sobre un objeto creciente).

**Impacto.** El caso de uso central de la pantalla (cargar la focalizacion de 147 colegios: 147 x 5 grupos x hasta 3 modalidades ≈ 2.200 filas) choca con el limite de 8 s.

**Arreglo propuesto.**
1. Resolver cada nombre de sede distinto una sola vez: `create temp table tmp_imp_nombres as select distinct trim(f->>'sede') ...` y resolver contra una temporal de sedes con `lower(unaccent(nombre))` ya calculado; luego hacer el join por nombre (de 2.000 busquedas a ~150).
2. Guardar `nombre_normalizado` como columna generada en `sedes` con indice `gin (nombre_normalizado gin_trgm_ops)`.
3. Acumular en una tabla temporal (`insert ... on conflict do update set cantidad = cantidad + excluded.cantidad`) en lugar del jsonb.
4. En la pantalla, previsualizar por lotes de 500 filas y mandar `p_aplicar` con las filas ya resueltas (ids), no volver a resolver nombres.

---

## Hallazgos medios

### M1 · `estado_ciclo('vigente')` no exige casillas completas: un ciclo vacio o con casillas borradas pasa a vigente, y puede haber varios vigentes

**Evidencia.** Mig 021, linea 181, solo revisa que las filas existentes de `ciclo_menu_items` tengan receta o descriptor; una casilla que nunca se creo (o que `guardar_ciclo_item` borro con preparacion y descriptor nulos, linea 143) no cuenta.
```
crear_ciclo(pae,'AUD_VACIO',...,5) -> estado_ciclo(vigente) -> AUD_VACIO | vigente | 0 items
copia de CICLO_DEMO (360 casillas), borrar 1 (359) -> estado_ciclo(vigente) -> vigente
ciclos vigentes del contrato: AUD_COPIA, AUD_VACIO (dos a la vez; CICLO_DEMO sigue en borrador aunque lo usan las 34 sedes)
```
La pantalla si bloquea el boton (`faltan > 0`, `minutas.js:35`) pero cuenta solo componentes `obligatorio !== false`, criterio distinto al de la base.

**Arreglo.** En `estado_ciclo`: contar `n_menus x componentes obligatorios del contrato (excluyendo los `componentes_excluidos` de la variante del ciclo)` contra las casillas con receta, y rechazar si faltan; al poner vigente, pasar a `historico` el vigente anterior de la misma variante (o exigir que no haya otro). Mismo criterio en la pantalla.

### M2 · "Sin servicio" solo se marca en dias habiles aunque el contrato atienda todos los dias (USPEC no puede marcar un paro de fin de semana)

**Evidencia.** `marcar_calendario` usa `es_dia_habil` y no `dias_atencion` del contrato:
```
marcar_calendario(uspec, null, '2026-11-14', '2026-11-15', false, 'paro') -> 0 filas; es_dia_servicio(uspec, null, '2026-11-14') = true
```
**Arreglo.** Reemplazar `es_dia_habil(g)` por `(v_dias = 'todos' or es_dia_habil(g))` leyendo `dias_atencion` del contrato (misma logica de `es_dia_servicio` sin el calendario).

### M3 · La programacion muestra gramajes de `minuta_patron` y la receta cruda, no los gramajes por grupo que se guardan en Minutas

**Evidencia.** `tmp_prg_gram` (mig 018, lineas 86 a 100) lee `minuta_patron.porcion_servida` y `preparacion_ingredientes.peso_bruto`; no pasa por `crudo_ingrediente`. Prueba: `guardar_gramajes(PAE, PROTEICO de RPS, todos los grupos, 999 g)`:
```
programacion -> gramaje: {"G6_8": {"crudo": 110, "servido": null}, ...}   (sin cambio)
explosion    -> ajuste_aplicado 'servido 999.00', crudo_por_racion 999 (principal) y 9,1 (otros)  (si aplica)
```
En PAE `servido` sale siempre nulo porque no hay `minuta_patron`.
**Impacto.** El planeador guarda gramajes y la cuadricula le dice otra cosa que la explosion.
**Arreglo.** Calcular `crudo` con `crudo_ingrediente(p_contrato, null, fecha, preparacion, producto, grupo, componente, peso_bruto)` por grupo (una vez por llave componente/preparacion/grupo, es barato) y `servido` como `crudo x factor`, con `gramajes_ajuste` por encima de `minuta_patron`.

### M4 · Funciones nuevas sin `grant execute ... to authenticated` explicito: dependen del privilegio por defecto de Supabase

**Evidencia.** Las 25 funciones de las migraciones 017 a 021 solo hacen `revoke all ... from public, anon`. En la base local `has_function_privilege('authenticated', ...)` es falso para todas (`poblacion_contrato`, `guardar_cupos`, `minutas_contrato`, ... ; `programacion` y `calcular_explosion` si lo tienen por migraciones anteriores). En produccion funcionan porque Supabase define `alter default privileges ... grant execute on functions to anon, authenticated, service_role` para el rol `postgres`; si una migracion corre con otro rol, o se restaura la base en otro sitio, dejan de ser ejecutables. El protocolo pide concederlo siempre.
**Arreglo.** Una migracion corta con `grant execute on function ... to authenticated` para las 25 funciones, y dejarlo como plantilla de toda funcion nueva.

### M5 · `minutas_contrato` y `calendario_contrato` no aplican `mi_sede`: el administrador de sede ve las 34 sedes

**Evidencia.** Usuario `admin_sede` de Demo PAE amarrado a una sede: `poblacion_contrato` 1 sede, `partes_dia` 1 sede, `programacion` 1 sede (bien), pero `minutas_contrato(...)->'sedes'` devuelve 34 y `calendario_contrato` las marcas de todas las sedes. Es la regla A2 de la auditoria anterior ("usuario amarrado a una sede solo ve la suya").
**Arreglo.** Filtrar `sedes` y las marcas por sede con `mi_sede(v_emp)` como en `poblacion_contrato`.

### M6 · Importador: cambiar "Rige desde" en el modal no refresca la previsualizacion y se aplica una fecha distinta a la mostrada

**Evidencia.** `app/(app)/cupos/page.js:141` cambia `imp.desde` sin volver a llamar `importar_poblacion`; la tabla sigue mostrando la fecha vieja por fila y `aplicar` (linea 83) usa la nueva. Ademas el chip "Rige desde" inicial es la fecha "lo que rige el" del filtro de la pantalla (puede ser una fecha pasada que el usuario puso solo para consultar).
**Arreglo.** Recalcular la previsualizacion al cambiar la fecha (o deshabilitar "Cargar" hasta refrescar), y arrancar con hoy, no con la fecha de consulta.

### M7 · La pantalla de explosion recalcula el resumen completo tras cada tramo y "Recalcular" rehace todo el rango

**Evidencia.** `page.js:144` (`useCarga(..., [id, progreso?.fin, progreso?.hechos])`): una explosion de 90 dias en 23 tramos dispara 23 `explosion_resumen` (ver A3). `onRecalcular` (linea 171) llama `calcular` sobre `e.desde..e.hasta` aunque la explosion este parcial y `cubierto` diga que falta un solo tramo.
**Arreglo.** Resumen solo al final; en parcial, calcular solo los dias fuera de `cubierto` (exponer `cubierto` en `explosion_resumen` y recorrer los huecos en `lib/tramos.js`).

### M8 · Partes diarios: un boton Guardar por sede; con 147 colegios son 147 clics por dia y 20 columnas

**Evidencia.** `components/minutas.js:253 a 263`: `guardarSede` por fila, `copiarCupos` por fila. No hay "= cupo para todas" ni "Guardar todo", ni importacion de partes (esta en el pendiente).
**Arreglo.** Boton "Guardar cambios" global que mande una llamada por sede modificada (o una funcion `guardar_partes_dia(p_contrato, p_fecha, p_items)`), "= cupo" para las filtradas, y en PAE mostrar solo las columnas con cupos del contrato.

### M9 · Excel de despacho: una hoja por sede con nombre truncado a 31 caracteres; si dos se repiten `book_append_sheet` lanza y no se descarga nada

**Evidencia.** `page.js:267`: `s.sede.replace(...).slice(0, 31)`. Nombres reales de colegios se parecen en los primeros 31 caracteres ("IE Tecnica Comercial de ..."). Tambien se cortan a 60 sedes sin avisar.
**Arreglo.** Deduplicar con sufijo numerico y avisar en el boton cuantas hojas trae.

---

## Hallazgos bajos

- **B1** `marcar_calendario` devuelve `n` del ultimo loop: con 2 sedes x 3 dias respondio 3 e inserto 6; el mensaje "3 dias marcados" miente. Acumular `n := n + v_n`.
- **B2** `asignar_ciclo(null, ...)` falla con "FOREACH expression must not be null"; validar `p_sedes` vacio con mensaje de operacion. `marcar_calendario` con `'{}'` no hace nada en silencio.
- **B3** Indice duplicado `explosion_detalle_idx` y `explosion_detalle_prod_idx` (ambos `(explosion_id, producto_id)`); falta `(explosion_id, contrato_sede_id)` para `explosion_por_sede` (349 ms con 45 k filas, una subconsulta por sede) y `explosion_producto`.
- **B4** Fechas: `estado_ciclo` usa `current_date` (UTC) en vez de Bogota; `poblacion_contrato->historial` es `distinct ... limit 24` sin `order by` (muestra 24 cualesquiera); `hoyISO()` toma la fecha del navegador.
- **B5** `importaciones`: `archivo = p_fuente`, `estado` siempre 'procesada', no se registra el intento con errores (`con_errores` existe en el check) ni `creado_por`.
- **B6** `lib/poblacion-excel.js`: `sede_alt` se manda y la funcion no lo lee; "Institucion Educativa X" no se normaliza a "IE X" (probado: no resuelve a 0,45); `cantidad` quita todo lo no numerico ("12,5" se vuelve 125, "-5" se vuelve 5); `fechaCelda` con `Date` usa `toISOString` (UTC) y puede correr un dia en zonas al oeste.
- **B7** Cupos: el panel dice "hoy X" y arranca "Rige desde" en hoy aunque la tabla muestre otra fecha de consulta; "Importar Excel" es un `label` sin foco de teclado; `CATEGORIAS` vive en la pagina de explosion y los nombres de estado en `ui.js`, no en `lib/catalogos.js` como pide el protocolo; `guardar_cupos` borra la misma fecha comparando variante pero cierra sin mirarla (si la sede cambia de variante y se re-guarda la misma fecha quedan dos filas).
- **B8** Calendario: la leyenda no explica el subrayado de festivo ni el borde de hoy; los botones de dia solo muestran el numero (sin `aria-label` con la fecha completa); la seleccion de rango por dos clics no tiene salida de escape visible mas que cerrar el panel; "Anular" en explosion usa `confirm()` nativo.
- **B9** Datos demo: los tres `CICLO_DEMO` estan en `borrador` y asignados a todas las sedes; `AsignarCiclo` permite asignar un borrador sin aviso y lo ofrece primero cuando no hay vigente.
- **B10** Rotulo de fila agrupada "Menu estandar · RPS+CAM · 13.341 estudiantes": suma cupos de varias modalidades, un estudiante con RPS y CAM cuenta dos veces (son raciones-dia, no estudiantes). Usar "raciones" cuando hay mas de un tiempo o el maximo por tiempo.
- **B11** `explosion_por_sede` muestra "del menu 18 al 4" cuando el tramo da la vuelta al ciclo; conviene "menus 18 a 20 y 1 a 4" o mostrar la lista.

---

## Diseno (observaciones, no bloquean)

- **D1 Variante en la poblacion.** `cupos` y `partes_diarios` llevan `variante_id` aunque la regla dice que la variante es de la sede (`sede_ciclo`). Eso creo C1 y obliga a que importador, pantalla y simulador adivinen la variante. Lo mas robusto: quitar la variante de la poblacion (o ignorarla en `poblacion_dia`) y tomarla siempre de `sede_ciclo` por fecha; la explosion ya hace `p.variante_id is null or ...`.
- **D2 Modelo de vigencias.** Cuatro tablas repiten el patron `fecha_desde / fecha_hasta` con la misma logica en cuatro funciones y sin constraint. Una funcion generica `abrir_vigencia(tabla, llave, desde)` o, mejor, constraints de exclusion con `daterange` (ver A1) evitan que cada pantalla nueva reinvente el cierre.
- **D3 `gramajes_ajuste` como mecanismo por grupo.** Funciona y es flexible (contrato, sede, componente, preparacion, producto, grupo), pero la prioridad `sede > producto > preparacion > grupo` hace que un ajuste de componente a nivel de sede le gane a un ajuste de producto del contrato; documentarlo o invertir sede/producto. La nota 'servido X (grupo)' se escribe aunque la receta no tenga principal (no hay ninguna hoy, pero `copiar_catalogo` podria crearla). La pantalla solo guarda `porcion_servida`; el `peso_bruto` del mismo item queda sin uso en UI.
- **D4 Llave de menu.** Bien resuelta y rapida (34 x 10 semanas en 2,1 s; estimado 147 colegios x 2 semanas ≈ 2 s, x 10 semanas ≈ 9 s, pero la pantalla ya limita a 2 semanas con mas de 20 sedes). La firma de agrupacion se arma concatenando strings por sede (O(sedes x celdas)); con 147 colegios sigue siendo lineal. Un intercambio propio saca a la sede de la llave aunque caiga en un dia fuera del rango (`coalesce(vigente_hasta, p_hasta) >= p_desde` solo acota por vigencia, no por el dia del ciclo): correcto pero conservador.
- **D5 Lo que va a doler con 147 colegios o 6 empresas.** (1) `explosion_resumen` y `explosion_por_sede` sobre 200 k filas (A3, B3); (2) importador por fila (A5); (3) partes diarios sede por sede (M8); (4) `calendario_servicio` marcado dia a dia y sede a sede: un receso de 3 semanas para 147 colegios son 2.200 filas, y `es_dia_servicio` consulta por celda; con el `where` de `programacion` sigue bien, pero conviene marcar por contrato y excepciones por sede; (5) `tmp_prg_pob` llama `poblacion_dia` por sede-dia (147 x 14 = 2.058 llamadas, hoy ~0,3 ms cada una, bien); (6) `simular_poblacion` y `crear_empresa_demo` siguen siendo fila a fila pero son de una sola vez.
- **D6 Codigo que sobra o esta duplicado.** `sede_alt` en el importador; indice duplicado (B3); `tmp_prg_gram` reimplementa la logica de `crudo_ingrediente` (M3); en `explosiones_contrato` se calcula `productos` con `count(distinct)` sobre el detalle por cada explosion listada (60 x escaneo), mejor guardarlo en `explosiones` al calcular.

## UI/UX (resumen; los puntos concretos estan en M6 a M9 y B7 a B11)

- Las tres pantallas siguen los tokens de `app/globals.css` (sin colores sueltos; los estilos en linea son anchos y alineaciones), reutilizan `Panel`, `Campo`, `Tabla`, `Estado`, `Kpi` y `Consejo`, y dan feedback de guardado (botones bloqueados, mensajes ok/bad). Legibles en celular salvo la cuadricula del ciclo (20 menus x 20 componentes) y los partes PAE (20 columnas), que requieren desplazamiento horizontal con la primera columna sin fijar.
- Flujos confusos: en Minutas se puede editar un ciclo vigente casilla por casilla sin confirmacion (el texto lo dice, pero un cambio accidental altera el menu real desde el proximo calculo); el ciclo "borrador" que usan todas las sedes de la demo contradice el texto "el vigente es el que rige"; en Cupos la fecha "lo que rige el" sirve para consultar pero arrastra la fecha del importador (M6).
- Textos: bien en lenguaje de operacion ("Sin permiso para editar los cupos de esta sede"), pero los errores de la base que no se traducen (clave duplicada de A4, FOREACH de B2) llegan crudos a la pantalla.
- Accesibilidad basica: los botones de dia del calendario, el `label` de importar y las celdas del ciclo (td con onClick, sin rol ni teclado) no son operables sin raton.

---

## Lo que se probo y paso bien

Funcional
- `guardar_cupos`: cierre de la vigencia anterior el dia antes (92 hasta 30-nov, 999 desde 1-dic); cero cierra sin abrir (999 hasta 14-ene); misma fecha reemplaza; `poblacion_dia` toma la vigencia correcta en 30-nov y 1-dic.
- `guardar_dietas` y `guardar_gramajes`: mismo comportamiento de vigencias; gramaje vacio cierra sin abrir.
- `importar_poblacion`: resolucion exacta sin acentos y por trigramas ("IE Antonio Nariño Ponedera" -> "IE Antonio Narino (Ponedera)"); grupo por codigo (G6_8) y por nombre ("6 a 8"); cantidad "1.200" -> 1200; filas repetidas se suman (100 + 50 = 150); con una fila con error no aplica nada (`aplicado = false`, 0 filas); fila de rastro en `importaciones`.
- `crudo_ingrediente`: sin ajuste devuelve el peso de la receta; ajuste por componente y grupo H duplica el principal y escala el resto en la misma proporcion (18/12/10 -> 36/24/20) y el grupo M queda intacto; ajuste por producto cambia solo ese producto (azucar 10 -> 1) y el resto conserva el ajuste de componente; la explosion registra `ajuste_aplicado` y el crudo proporcional (999 principal, 9,1 el otro).
- `marcar_calendario`: "no atiende" solo en habiles (sabado, domingo y festivo 16-nov se saltan); respeta marcas de novedad en la rama de "sin servicio"; "volver a la regla" borra las marcas propias y deja las de novedad; `cuenta_ciclo` se guarda; sede de otra empresa la bloquea el trigger de coherencia.
- `asignar_ciclo`: cierra la asignacion anterior el dia antes; rechaza sede de otro contrato, variante de otra empresa y ciclo anulado; `estado_ciclo('anulado')` rechaza si hay sedes asignadas; `crear_ciclo` copia las 360 casillas y rechaza codigo repetido (mayusculas/minusculas).
- `guardar_ciclo_item`: upsert, borrado con nulos, dia fuera de rango rechazado, componente de otra empresa rechazado por trigger. `ciclo_detalle` entrega opciones por componente (15 a 16 recetas de la familia).
- `guardar_parte_diario`: upsert por llave (3000 -> 2900), nulo borra, el parte manda sobre el cupo cuando las llaves coinciden (Batallon: 26 -> 1000).
- `partes_dia`: devuelve cupos agregados, parte y variante de la sede por sede.
- `calcular_explosion`: raciones del tramo en PAE = suma de poblaciones por sede-dia (1.746 = 1.746 en las 3 sedes mas grandes); estado pasa a `calculada` al cubrir todo el rango; tramos de 4, 8 y 14 dias consistentes (427.875 raciones acumuladas).
- `explosion_por_sede`: una fila por sede con periodo, dias con servicio, menu desde/hasta (4 a 18), raciones y 58 productos; `explosion_producto` por dia/sede/preparacion; `explosiones_contrato` lista sin anuladas.
- `programacion` por llave: 34 colegios en 5 filas (15 estandar, 15, 2, 1, 1); un intercambio concertado propio saca a la sede a una fila de 1 y la estandar baja a 14; la celda muestra `origen = intercambio` solo en esa sede; propuesto sin `p_incluye_propuestos` sigue agrupada y con la bandera se separa; intercambio de todo el contrato lo muestran los 5 representantes y la agrupacion no cambia; la firma separa RPS de RI (filas distintas con el mismo ciclo); `cupos` de celda con `por_tiempo`.
- `dia_ciclo` set-based vs. version anterior: 0 diferencias en 9.774 celdas (todas las sedes de las 4 empresas, 1-sep-2026 a 28-feb-2027), incluidas marcas de reposicion en sabado, paro que cuenta ciclo y paro que no cuenta.
- Vistas `v_poblacion_vigente` y `v_dietas_vigentes`: filas de la empresa del usuario unicamente (12 y 58 para el planeador de Demo USPEC).

Seguridad (simulando PostgREST: `es_admin_sql()` falso, `set role authenticated`, JWT con `sub`)
- Planeador de Demo USPEC contra Demo PAE: rechazadas `guardar_cupos`, `guardar_dietas`, `guardar_parte_diario`, `importar_poblacion`, `ciclo_detalle`, `minutas_contrato`, `poblacion_contrato`, `partes_dia`, `calendario_contrato`, `marcar_calendario`, `guardar_gramajes`, `crear_ciclo`, `estado_ciclo`, `guardar_ciclo_item`, `asignar_ciclo`, `explosiones_contrato`, `explosion_resumen`, `explosion_por_sede`, `explosion_producto`, `anular_explosion`, `calcular_explosion`, `programacion`, `simular_poblacion` (23 de 23).
- Administrador de sede (M7) de Demo PAE: ve 1 sede en `poblacion_contrato`, `partes_dia` y `programacion`; edita cupos y parte de su sede y no de otra; sin acceso a importar, calendario, gramajes.
- Auxiliar de compras (M3 ver): lee explosiones y poblacion, no edita cupos ni anula; puede proyectar (por diseno).
- Planeador con referencias de otra empresa (componente, sede): el trigger `validar_empresa_coherente` lo bloquea. `guardar_cupos(null, ...)` -> sin permiso.
- Anon: `permission denied` en funciones y vistas. Ninguna funcion nueva usa `auth.uid() is null`; todas usan `es_admin_sql()`.

Eficiencia (local, sin JIT)
- `programacion` PAE 34 x 4 semanas 969 ms; 34 x 10 semanas 2.079 ms; Demo USPEC 12 x 4 semanas 180 ms; Diestra 101 ms; sin agrupar 120 ms.
- `calcular_explosion` PAE 34 colegios: tramo de 4 dias 833 ms, 8 dias 1.143 ms, 14 dias 1.356 ms. Demo USPEC 12 x 13 dias con dietas 3,3 a 3,5 s (58 k filas por tramo): el presupuesto de 160 sede-dias deja margen al partir a la mitad.
- `calendario_contrato` 400 dias 16 ms; `minutas_contrato` 49 ms; `partes_dia` 7 ms; `poblacion_contrato` 8 ms; `ciclo_detalle` 13 ms; `explosion_por_sede` 134 k filas 585 ms sin analyze y 193 ms con analyze; `explosion_producto` 10 ms.

## Archivos de prueba

Los scripts SQL usados (t1 a t15 y sec.sql) quedaron en el scratchpad de la sesion, no en el repositorio: `/tmp/claude-0/-home-claude/c2f15321-1fda-5e67-b6b0-3ef22ed48bfc/scratchpad/`. Todos terminan en `rollback`.
