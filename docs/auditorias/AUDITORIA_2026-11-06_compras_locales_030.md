# Auditoria independiente · Compras locales Ley 2046 (mig 030), contratos de practica y cambio de nombre a Ración360

Fecha: 6 de noviembre de 2026
Alcance: `supabase/migrations/20261130000000_compras_locales_contratos_practica.sql` (mig 030); `components/compras-locales.js`, `app/(app)/compras-locales/page.js`, cambios en `app/(app)/tablero/page.js`, `app/(app)/layout.js` y `lib/ctx.js` (`esDemo`); cambio de nombre "Supply ERP" a "Ración360" (commits `bd5f162`, `ed445b3`, `90004d5`; diff `e521773..HEAD`).
Base de pruebas: Postgres local `sc9` (puerto 5499) con migraciones hasta la 030. Pruebas con usuarios simulados (`authenticator` + `request.jwt.claim.sub`), siempre dentro de `BEGIN ... ROLLBACK`: `dir_compras` de Demo USPEC, `dir_compras` de Demo PAE, usuario proveedor de Demo USPEC, `conductor` y `aux_compras` de Demo USPEC, `admin_empresa` y `dir_compras` de UT Diestra. No se toco produccion ni el codigo (solo este informe).
Scripts: `/tmp/claude-0/-home-claude/c2f15321-1fda-5e67-b6b0-3ef22ed48bfc/scratchpad/a30/` (`setup.sql`, `t1.sql` a `t6.sql`, `perf.sql` a `perf4.sql`, `q.sql`, `q2.sql`, `leer.mjs`).

## Veredicto

El cerco entre empresas aguanta: un usuario de Demo USPEC no ve ni escribe soportes, parametros ni terceros de Demo PAE (por REST ni por las funciones nuevas), el proveedor del portal recibe 0 filas del tablero y no puede insertar soportes, anon no tiene permiso sobre la tabla ni las funciones, `crear_contrato_practica` rechaza a usuarios normales, el atajo de administrador usa `es_admin_sql()` y todos los `update` y `delete` llevan `where`. La siembra es idempotente en filas (17 empresas, 17 contratos, 17 entidades antes y despues de re-ejecutar la migracion). El cambio de nombre no rompio nada (manifest es JSON valido, el service worker solo cambia textos, no quedan cadenas "Supply ERP" fuera de comentarios SQL).

Pero el indicador de cumplimiento, que es lo que se le reporta a la entidad, no es confiable todavia: hay cinco altos. **El tablero tarda 258 s** (65 s en la tarjeta de inicio de 3 meses) con 300.000 OC y 25 s con 30.000, muy por encima de los 8 s de Supabase; **una meta en 0 (campo vacio en el formulario) tumba con division por cero** el tablero de toda la empresa; **los soportes permiten contar dos veces o borrar OC** (exportar y reimportar el formato oficial duplica las OC, un soporte de otro contrato se "roba" la OC, un soporte de 1 peso hace desaparecer una OC de 50 millones); **los contratos terminados siguen generando requerido estimado** despues de su fecha fin (UT Atlantic: 480 millones de faltante ficticio en octubre y noviembre); y **el administrador de una empresa real puede marcarla como practica** con `es_practica` y entonces cargar 117 precios simulados en el master real.

## Resumen por severidad

| Severidad | Cantidad | Numeros |
|---|---|---|
| Critico | 0 | |
| Alto | 5 | A1 a A5 |
| Medio | 6 | M1 a M6 |
| Bajo | 8 | B1 a B8 |

Criticos y altos se corrigen antes de seguir; medios y bajos van al pendiente del control de cambios.

---

## Hallazgos altos

### A1 · `compras_locales_tablero` excede por mucho los 8 s: subconsultas correlacionadas repetidas 16 veces y sin indice por contrato en `ordenes_compra`

**Evidencia.** `perf.sql`: 61 contratos en una empresa, 300.000 OC en 18 meses, 30.000 soportes (5.000 con `oc_id`).

```
compras_locales_tablero(empresa, 12 meses)  ->  723 filas en 258.596 ms (4 min 18 s)
compras_locales_tablero(empresa, 3 meses)   ->  183 filas en  65.552 ms   (tarjeta del tablero de inicio)
```
La consulta tuvo que cancelarse a mano (`pg_cancel_backend`) porque bloqueaba otras sesiones. Con 30.000 OC (`perf2.sql`, 10 % del caso anterior, volumen de un ano de una UT mediana): 24,8 s a 12 meses y 6,7 s a 3 meses.

El plan (`EXPLAIN` sin ANALYZE, `perf2.sql`) muestra la causa: el CTE `compras` se inlinea y, como `local` y `total` se usan varias veces en el `jsonb_build_object` (`comprado_local`, `pct_local_de_compras`, `cumplimiento_pct`, `pct_sobre_base`, `faltante`), Postgres ejecuta las cuatro subconsultas una vez por cada uso: **SubPlan 4 a SubPlan 19**, y cada subplan de OC es un `Seq Scan on ordenes_compra` con filtro `contrato_id = b_1.contrato_id AND date_trunc('month', fecha_emision)::date = b_1.periodo` (no hay indice por `contrato_id`, y `date_trunc` sobre la columna impide usar uno por fecha). Son unas 723 x 8 lecturas completas de la tabla de OC.

Prueba de la correccion (`perf3.sql`, `perf4.sql`): la misma consulta con la parte de compras agregada una sola vez (`q2.sql`, abajo) devuelve **el mismo resultado** (md5 identico al de la funcion original, `2bf0057b...` en 30.000 OC a 3 meses) y tarda **386 ms con 300.000 OC a 12 meses** sin indice nuevo (336 ms con el indice), contra 258 s.

**Impacto.** La tarjeta del tablero de inicio la carga todo usuario con M1 o M3; en produccion la consulta muere por `statement_timeout` y la tarjeta muestra el error crudo. La pantalla de compras locales queda inutilizable con 6 o 12 meses o con "Todas mis empresas".

**Arreglo.** Reemplazar el CTE `compras` por agregados unicos materializados y crear el indice:
```sql
create index if not exists oc_contrato_fecha_idx on public.ordenes_compra (contrato_id, fecha_emision)
  where estado not in ('borrador', 'anulada');

-- dentro de compras_locales_tablero, en lugar de "compras as (...)":
  ), rango as (
    select min(periodo) as desde, (v_hasta + interval '1 month')::date as hasta from meses
  ), oc as materialized (
    select o.contrato_id, date_trunc('month', o.fecha_emision)::date as periodo,
           sum(o.total) as total, coalesce(sum(o.total) filter (where t.ley2046), 0) as local
      from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id, rango r
     where o.contrato_id in (select id from ct) and o.estado not in ('borrador', 'anulada')
       and o.fecha_emision >= r.desde and o.fecha_emision < r.hasta
       and not exists (select 1 from public.compras_locales_soportes s where s.oc_id = o.id)
     group by 1, 2
  ), so as materialized (
    select s.contrato_id, s.periodo, sum(s.valor) as total, coalesce(sum(s.valor) filter (where s.ley2046), 0) as local
      from public.compras_locales_soportes s, rango r
     where s.contrato_id in (select id from ct) and s.periodo >= r.desde and s.periodo < r.hasta
     group by 1, 2
  ), compras as materialized (
    select b.contrato_id, b.periodo,
           coalesce(oc.local, 0) + coalesce(so.local, 0) as local,
           coalesce(oc.total, 0) + coalesce(so.total, 0) as total
      from base b left join oc on oc.contrato_id = b.contrato_id and oc.periodo = b.periodo
                  left join so on so.contrato_id = b.contrato_id and so.periodo = b.periodo
  ), calc as ( ... igual ... )
```
Marcar tambien `ct` y `base` como `materialized` y agregar el promedio de facturado con una ventana (`avg(...) over (partition by contrato order by periodo rows between 3 preceding and 1 preceding)`) en lugar de la subconsulta por fila si el numero de contratos crece.

### A2 · Una meta en 0 tumba el tablero de toda la empresa (division por cero), y el formulario guarda 0 si el campo queda vacio

**Evidencia.** `t4.sql`: `guardar_parametros_cl(contrato, '{"meta_compras_locales_pct": 0, "meta_compras_locales_extra_pct": 0}')` se acepta (el check es `between 0 and 100`). Despues:
```
compras_locales_tablero(empresa, 3)  ->  ERROR: division by zero
compras_locales_tablero(null, 3)     ->  ERROR: division by zero   ("Todas mis empresas")
```
La expresion es `case when base_valor > 0 then round(local / (base_valor * meta_pct / 100) * 100, 1) end`: con base positiva y meta 0 divide por cero. En `ParametrosCL` (`components/compras-locales.js`, linea 99) se envia `Number(f.meta_compras_locales_pct)`, y `Number('') = 0`: basta con borrar el campo y guardar.

**Impacto.** Un solo contrato mal parametrizado deja sin indicador a todos los contratos de la empresa (y a todas las empresas del usuario), incluida la tarjeta del tablero de inicio. Ademas la ley exige minimo 30 %.

**Arreglo.**
```sql
alter table public.contratos
  add constraint contratos_meta_cl_min check (meta_compras_locales_pct >= 30),
  add constraint contratos_meta_cl_total check (meta_compras_locales_pct + meta_compras_locales_extra_pct <= 100);
-- y en el tablero, defensa adicional:
'cumplimiento_pct', case when base_valor > 0 and meta_pct > 0 then round(local / (base_valor * meta_pct / 100) * 100, 1) end,
```
(antes de la constraint, `update contratos set meta_compras_locales_pct = 30 where meta_compras_locales_pct < 30`). En el formulario: no enviar la clave si el campo esta vacio y validar `>= 30` antes de llamar la funcion.

### A3 · Los soportes permiten contar dos veces una compra o hacer desaparecer una OC del cumplimiento

**Evidencia.** `t2.sql`, contrato Demo USPEC con facturado de 1.000 millones, rubro 70 %, meta 30 % (requerido 210 millones) y una OC aprobada `OC-T1` de 50 millones a un proveedor Ley 2046:

| Caso | Comprado local | Cumplimiento |
|---|---|---|
| Base (solo la OC) | 50.000.000 | 23,8 % |
| (b) Se exporta el formato oficial (la OC sale como fila con `factura = 'OC-T1'`) y se vuelve a importar ese archivo: el importador no pone `oc_id` | 100.000.000 | 47,6 % |
| (c) Se importa el mismo archivo otra vez (no hay control de duplicados) | 150.000.000 | 71,4 % |
| (d) Soporte del **otro** contrato de la misma empresa con `oc_id = OC-T1`: el trigger solo valida la empresa | contrato original 0; el otro 50.000.000 | 0 % y 23,8 % |
| (e) Soporte de **1 peso** y `ley2046 = false` con `oc_id = OC-T1` | 0 (total 1) | 0 % |
| (f) Dos soportes con el mismo `oc_id` | 100.000.000 | |

**Impacto.** El cumplimiento de la Ley 2046 se reporta a la Gobernacion o a la USPEC; con el flujo normal de la pantalla (exportar para completar columnas y volver a importar) el indicador sale inflado, y con un soporte mal amarrado una OC real desaparece o se cuenta en el contrato equivocado. El indicador deja de ser auditable.

**Arreglo.**
1. Validar coherencia en `cls_validar`:
```sql
if new.oc_id is not null then
  select o.contrato_id, o.total, t.ley2046 into v_ct, v_total, v_ley
    from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id
   where o.id = new.oc_id and o.empresa_id = new.empresa_id and o.estado not in ('borrador', 'anulada');
  if not found then raise exception 'La OC no existe, esta anulada o no es de la empresa.'; end if;
  if v_ct is distinct from new.contrato_id then raise exception 'La OC es de otro contrato.'; end if;
  new.ley2046 := v_ley; new.origen := 'oc';
  if new.valor > v_total then raise exception 'El soporte (%) supera el total de la OC (%).', new.valor, v_total; end if;
end if;
```
2. Un soporte por OC y sin duplicados de factura:
```sql
create unique index if not exists cls_oc_unico on public.compras_locales_soportes (oc_id) where oc_id is not null;
create unique index if not exists cls_factura_unica on public.compras_locales_soportes
  (contrato_id, coalesce(proveedor_nit, lower(proveedor_nombre)), factura, valor) where factura is not null;
```
3. En `aplicar` del importador: si `factura` coincide con el `codigo` de una OC del contrato, poner `oc_id` (o descartar la fila con aviso); insertar por una funcion RPC `importar_soportes_cl(contrato, periodo, filas jsonb, archivo)` que haga todo en una transaccion y reporte duplicados, en lugar de lotes de 500 por REST (hoy un error en el lote 2 deja cargado el lote 1).

### A4 · Contratos terminados o vencidos siguen generando requerido y faltante con facturado estimado

**Evidencia.** `t3.sql`. UT Atlantic 202602581 (fin 15-sep-2026, estado `liquidacion`) con facturado jul 2.000 M, ago 2.000 M, sep 800 M:
```
periodo     facturado        estimado  requerido     faltante
2026-11-01  1.600.000.000    true      480.000.000   480.000.000
2026-10-01  1.600.000.000    true      480.000.000   480.000.000
2026-09-01    800.000.000    false     240.000.000   240.000.000
```
Lo mismo con UT Diestra (`fecha_fin_inicial` 31-jul-2026, estado `vigente`): agosto a noviembre salen con 3.000 M estimados y 663 M de requerido cada mes. `base` solo filtra `m.periodo >= fecha_inicio`; no hay tope por fecha fin (ni prorrogas), y el estimado se aplica tambien a meses cerrados en contratos en liquidacion.

**Impacto.** El tablero muestra incumplimientos ficticios de cientos de millones en los contratos que estan en cierre, que son justo los que la Gobernacion esta revisando (UT Atlantic). Rojo falso en la tarjeta de inicio.

**Arreglo.** Usar la fecha fin vigente (la de `v_contratos_resumen`, que suma prorrogas) y no estimar fuera de ella:
```sql
where m.periodo >= date_trunc('month', ct.fecha_inicio)::date
  and m.periodo <= date_trunc('month', coalesce(ct.fecha_fin_vigente, ct.fecha_fin_inicial))::date
...
-- estimar solo el mes en curso de un contrato vigente:
case when ej.valor_facturado is null and m.periodo = v_mes_actual and ct.estado = 'vigente' then (promedio) end as facturado_prom
```
Para meses pasados sin facturado, mostrar la alerta "Falta el facturado del mes" en vez de inventarlo.

### A5 · El administrador de una empresa real puede marcarla como practica y cargar precios simulados en el master real

**Evidencia.** `t6.sql`, usuario `admin_empresa` de UNION TEMPORAL DIESTRA (empresa real):
```
update empresas set es_practica = true where id = <Diestra>   ->  UNION TEMPORAL DIESTRA | t   (la policy empresas_editar solo exige M0 editar)
es_empresa_demo(<Diestra>)                                    ->  t
-- el dir_compras de Diestra:
simular_precios_demo(<Diestra>)                               ->  {"precios_creados": 117}
```
La mig 030 agrego `es_practica` como nueva puerta de `es_empresa_demo`, pero la columna queda editable por cualquier usuario con M0 editar. Lo mismo pasa renombrando la razon social para que contenga "demo" o "practica".

**Impacto.** 117 precios "SIMULADO" de un proveedor ficticio entran al master de una operacion real y alimentan `costo_ciclo`, la sugerencia de compra y las OC. Tambien la empresa real aparece con el chip "practica" en el tablero de compras locales.

**Arreglo.**
```sql
create or replace function public.empresas_practica_protegida() returns trigger language plpgsql as $$
begin
  if new.es_practica is distinct from old.es_practica and not (public.es_admin_sql() or public.es_superadmin()) then
    raise exception 'Solo el administrador de la plataforma cambia la marca de practica.';
  end if;
  return new;
end $$;
create trigger empresas_practica_protegida before update of es_practica on public.empresas
  for each row execute function public.empresas_practica_protegida();

create or replace function public.es_empresa_demo(p_empresa uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.es_practica from public.empresas e where e.id = p_empresa), false);
$$;
```
Revisar en produccion `select * from bitacora where tabla = 'empresas' and datos_nuevos ? 'es_practica'` y `select count(*) from precios where notas = 'SIMULADO por categoria' and empresa_id in (select id from empresas where not es_practica)`.

---

## Hallazgos medios

### M1 · El tablero muestra facturado y compras a cualquier miembro interno, sin M1 ni M3 (y sin `mi_sede`)

**Evidencia.** `t1.sql`, bloque T3, usuario `conductor` de Demo USPEC (sin M1 ni M3): por REST ve 0 contratos y 0 filas de `contrato_ejecucion` (la policy exige M1 ver), pero `compras_locales_tablero(empresa, 3)` le devuelve el numero del contrato y `facturado = 1.000.000.000` de septiembre, octubre y noviembre, ademas de lo comprado. La funcion es `security definer` y solo verifica `mis_empresas_internas()`. Tampoco aplica `mi_sede` (regla del protocolo para lecturas por contrato), y `cls_ver` deja leer los soportes (facturas y valores) a cualquier interno.

**Impacto.** Fuga de informacion financiera dentro de la empresa (conductores, almacenistas, administradores de sede ven el facturado de todos los contratos).

**Arreglo.** En `ct` filtrar por permiso: `and (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M1', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver'))` y excluir contratos fuera de la sede del usuario amarrado (`public.mi_sede(c.empresa_id) is null or exists (select 1 from contrato_sedes ...)`). En `cls_ver`: `tiene_permiso(empresa_id, 'M3', 'ver') or tiene_permiso(empresa_id, 'M1', 'ver')`.

### M2 · La condicion Ley 2046 se auto-certifica: soporte marcado SI con proveedor que no lo es, tercero marcado sin tipo ni certificado, certificado vencido que sigue contando

**Evidencia.** `t2.sql`:
- T5g: soporte con `tercero_id` = "Mayorista Nacional" (`ley2046 = false`) y `ley2046 = true` en el soporte: se acepta y suma 30 millones al cumplimiento (50 M a 80 M).
- T5j: el `aux_compras` hace `update terceros set ley2046 = true` por REST sobre el mayorista: queda `ley2046 = t`, `tipo_productor_local = null`, `ley2046_certificado_vence = null`. La validacion de `guardar_ley2046_tercero` ("indique el tipo") se salta porque la policy `terceros_escribir` permite editar la columna directamente.
- T5i: con `ley2046_certificado_vence = 2026-01-31` el proveedor sigue contando en noviembre.

**Impacto.** Cualquier comprador sube el cumplimiento sin soporte documental; ante una verificacion de la entidad, el reporte no se sostiene.

**Arreglo.**
```sql
alter table public.terceros add constraint terceros_ley2046_tipo check (not ley2046 or tipo_productor_local is not null);
-- en cls_validar: si hay tercero, la marca sale del tercero y de la vigencia del certificado
if new.tercero_id is not null then
  select t.ley2046 and (t.ley2046_certificado_vence is null or t.ley2046_certificado_vence >= coalesce(new.fecha_compra, new.periodo))
    into new.ley2046 from public.terceros t where t.id = new.tercero_id;
end if;
```
En el tablero, contar OC solo si `t.ley2046 and (t.ley2046_certificado_vence is null or t.ley2046_certificado_vence >= o.fecha_emision)`. Considerar que marcar Ley 2046 requiera M3 aprobar (separacion de funciones) y quede en la bitacora con el adjunto del certificado.

### M3 · El importador del formato oficial lee mal los valores en texto y fechas raras, y no valida el periodo

**Evidencia.** `leer.mjs` ejecuta `leerFormatoOficial` con filas de prueba:
```
"1.500.000" (texto)        -> fila DESCARTADA en silencio (Number("1.500.000") = NaN)
"$ 2.350.000,50"           -> fila DESCARTADA en silencio
"1.500"                    -> valor = 1,5 pesos
"=1000*2" (texto)          -> valor = 10002
cantidad "12,5"            -> cantidad = null
Ley 2046 "S/N"             -> true      (regex /^S/)
fecha "11/25/2026"         -> "2026-25-11"   (luego el insert del lote falla entero)
fecha "31/02/2026"         -> "2026-02-31"   (idem)
valor -200000 (nota cred.) -> se lee; el insert del lote falla por el check valor >= 0
proveedor "   "            -> aceptado con nombre vacio
encabezado "RAZON SOCIAL / NOMBRE..." o "No. FACTURA" -> "Faltan las columnas de proveedor o valor."
```
Ademas todas las filas se cargan al mes elegido en la pantalla aunque `fecha_compra` sea de otro mes (T5g en `t2.sql`: soporte de marzo cargado en noviembre, aceptado), y las filas que no son de la primera columna "TOTAL" (subtotales por proveedor) se suman.

**Impacto.** Cumplimiento subestimado (filas perdidas sin aviso) o sobreestimado (subtotales), errores crudos de Postgres que abortan el lote, y meses mezclados.

**Arreglo.** Parser de numeros colombiano y reporte de filas rechazadas:
```js
const numCO = (v) => {
  if (typeof v === 'number') return v;
  let s = String(v ?? '').replace(/[^\d.,-]/g, '');
  if (/,\d{1,2}$/.test(s)) s = s.replace(/\./g, '').replace(',', '.');        // 2.350.000,50
  else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');           // 1.500.000
  else s = s.replace(/,/g, '');                                                // 1,500,000
  const n = Number(s); return Number.isFinite(n) ? n : null;
};
const fechaValida = (iso) => iso && !Number.isNaN(Date.parse(iso + 'T00:00:00')) && new Date(iso + 'T00:00:00').toISOString().slice(0, 10) === iso ? iso : null;
```
Rechazar (y listar) filas con valor no numerico, negativo, proveedor vacio o fecha invalida; `ley2046 = /^(SI|SÍ)$/i`; ignorar filas que contengan "TOTAL" o "SUBTOTAL" en cualquier columna de texto; mapear encabezados por sinonimos (`RAZON SOCIAL`, `PROVEEDOR`, `FACTURA`, `VALOR`). En la base, `check (fecha_compra is null or date_trunc('month', fecha_compra)::date = periodo)` o al menos aviso en la vista previa con las filas de otro mes.

### M4 · Lo que cuenta como "comprado" en OC: fecha del borrador, total completo aunque se reciba la mitad, y OC sin contrato que nunca cuentan

**Evidencia.** El tablero suma `o.total` de OC con `estado not in ('borrador','anulada')` por `date_trunc('month', o.fecha_emision)`. `fecha_emision` tiene default `now()` al crear el borrador (columna `date`), no la fecha de aprobacion ni de recepcion: un borrador de octubre aprobado en noviembre cuenta en octubre. Una OC `recibida_parcial` o `cerrada` con la mitad recibida (`oc_items.cantidad_recibida`) cuenta por el 100 %. Las OC con `contrato_id` nulo (compras consolidadas del CEDI) no cuentan en ningun contrato. El total incluye IVA mientras la exportacion valora las lineas por `oc_items.total`.

**Impacto.** El indicador mide pedidos, no compras realizadas; la entidad verifica con facturas. Diferencias entre la pantalla y el archivo exportado.

**Arreglo.** Contar por lo recibido: `sum(i.cantidad_recibida * i.precio * (1 + i.iva_pct/100))` agrupado por el mes de la recepcion (o `aprobada_en at time zone 'America/Bogota'` mientras no haya recepciones), y prorratear OC consolidadas por contrato segun la explosion de origen (o pedir el contrato al aprobarlas). Usar el mismo criterio en la exportacion.

### M5 · `xlsx` 0.18.5 con vulnerabilidades conocidas al leer archivos de terceros

**Evidencia.** `package.json`: `"xlsx": "^0.18.5"` (instalada 0.18.5, la ultima publicada en npm). Esa version tiene CVE-2023-30533 (contaminacion de prototipo al leer un archivo manipulado, corregida en 0.19.3) y CVE-2024-22363 (ReDoS, corregida en 0.20.2). El importador lee archivos que llegan por correo de entidades y proveedores.

**Impacto.** Un archivo malicioso puede alterar objetos de la aplicacion en el navegador del comprador o colgar la pestana.

**Arreglo.** `npm i https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz` (SheetJS dejo de publicar en npm) y limitar el tamano del archivo (por ejemplo 5 MB) antes de `XLSX.read`.

### M6 · `guardar_parametros_cl` sin validacion de negocio

**Evidencia.** `t3.sql`: acepta meta 5 % (por debajo del 30 legal) y meta 100 + extra 100 (tablero muestra `meta_pct = 200`, requerido 3.200 M sobre 1.600 M facturados); `fuente_parametros_cl = ''` no se puede borrar a nulo (`coalesce`); `{"meta_compras_locales_pct": ""}` y una zona que no es arreglo devuelven errores crudos de Postgres; no valida que `rubro_alimentos_pct` exista cuando la base es `rubro_alimentos`. Pide `M1 crear` mientras la policy de `contratos` usa `M1 editar` (gerencia tiene ambos, pero un rol personalizado con solo `editar` no podria).

**Arreglo.** Las constraints de A2, mas en la funcion: `raise exception` legibles para numeros invalidos (`jsonb_typeof(p->'meta_compras_locales_pct') = 'number'`), `jsonb_typeof(p->'zona_compras_locales') = 'array'`, `nullif(p->>'fuente_parametros_cl', '')` cuando la clave viene, y exigir `tiene_permiso(v_emp, 'M1', 'editar')`.

---

## Hallazgos bajos

### B1 · `creado_por` y `origen` de los soportes los pone el cliente
`t2.sql` T5h: insert con `origen = 'oc'` y `creado_por` = usuario de otra empresa: se guarda asi. Arreglo: en `cls_validar`, `if tg_op = 'INSERT' then new.creado_por := auth.uid(); end if; new.actualizado_por := auth.uid();` y forzar `origen` (`'oc'` solo si hay `oc_id`).

### B2 · Re-ejecutar la siembra o `crear_contrato_practica` pisa parametros editados
`t5.sql`: con `meta_compras_locales_extra_pct = 2` y fuente editada por el usuario, re-ejecutar la migracion los devuelve a 0 y al texto de la siembra (las filas no se duplican). El `update` de UT Diestra filtra solo por `numero` (hoy hay uno solo). Arreglo: llamar `guardar_parametros_cl` solo cuando el contrato se crea (`if v_ct is null then ... end if`) y filtrar el update de Diestra por `empresa_id = (select id from empresas where nit = '901942965')`.

### B3 · Tres definiciones distintas de "empresa de practica"
`es_empresa_demo` (SQL) usa `es_practica`, NIT `^90000000\d$` o "demo"/"practica" en la razon social; `esDemo` (`lib/ctx.js`) usa NIT `^900000[01]\d\d$` (900000000 a 900000199, rango donde existen NIT reales de empresas) o "demo|practica" en la razon social, sin mirar `es_practica`; `crear_contrato_practica` exige `9000001NN`. Una razon social como "Demoliciones..." o un cliente real con NIT 9000001xx quedaria como practica en el menu. Arreglo: traer `es_practica` en la consulta de empresas de `ctx.js` y usar solo esa columna en los tres lugares (protegida como en A5).

### B4 · Empresas de practica con datos reales en la base de produccion
La siembra crea 12 UT "(practica)" con numeros de contrato, valores, objetos y notas reales (nombres de personas: "confirmar con Wilson", "pedir a Yesid", "correo de Carlos Yepes"), contratos con `valor_inicial = 1` y fechas supuestas. "UT Nutrifood (practica)" convive con la empresa real "UNION TEMPORAL NUTRIFOOD" (NIT `POR-DEFINIR-NUTRIFOOD`) y su contrato real 202604177 queda en la de practica. Hoy solo las ve el superadministrador, pero cualquier usuario agregado al "Grupo de practica" (demostraciones a prospectos) veria esa informacion. Arreglo: decidir si los contratos reales van en la empresa real (no en practica) y quitar nombres de personas de `fuente_parametros_cl`; documentar que el grupo de practica no se usa para demostraciones externas.

### B5 · Detalles de la pantalla y la tarjeta
- Con "Todas mis empresas", `puede('M3', 'crear')` y `puede('M1', 'crear')` se evaluan contra la empresa activa, no contra la del contrato elegido: aparecen botones que luego fallan por RLS (o se ocultan cuando si se podria).
- La primera columna de meses siempre dice "(en curso)" aunque el mes en curso no tenga filas (por ejemplo si todos los contratos empezaron despues).
- Sin la migracion aplicada, la tarjeta del tablero muestra el texto crudo del error de PostgREST ("Could not find the function..."); mejor un mensaje fijo. La pagina en si muestra `Falla` y no rompe.
- El selector de periodo usa la fecha del navegador; el tablero usa America/Bogota (diferencia solo cerca de medianoche del cambio de mes).

### B6 · Exportacion
Las OC se exportan por linea con `oc_items.total`; el tablero usa `ordenes_compra.total`: el total del archivo y el de la pantalla pueden diferir. Una OC amarrada a un soporte de otro mes se exporta igual en su mes. Las filas de totales usan posiciones fijas (`Array(13)`); si se agrega una columna a `COLS` el total cae en la columna equivocada (calcular el indice de `valor`). La exportacion no genera formulas a partir de textos que empiezan por "=" (SheetJS los escribe como texto), asi que no hay inyeccion de formulas.

### B7 · Grants de las funciones nuevas
Correctos para anon y public; `es_empresa_demo` queda ejecutable por cualquier autenticado sobre cualquier `uuid` (devuelve la marca de una empresa ajena, `t1.sql` T1j); conviene filtrar a `es_miembro(p_empresa)` o dejarla solo para uso interno. A diferencia de la mig 029, no se concede explicitamente a `service_role` (funciona por ser dueno o por privilegio por defecto, pero rompe el patron).

### B8 · Cambio de nombre incompleto en el logo
`layout.js` y `login/page.js` siguen mostrando el logo con las iniciales "SE" (Supply ERP). El resto del cambio esta bien: `manifest.webmanifest` es JSON valido con "Ración360", `sw.js` solo cambia textos por defecto (sin cache que invalidar) y no quedan cadenas "Supply ERP" fuera de comentarios de migraciones. `PROTOCOLO_AUDITORIA.md` aun se titula "Supply ERP".

---

## Lo que se verifico y esta bien

- Aislamiento entre empresas (`t1.sql`): tablero de otra empresa "Sin acceso a esa empresa."; `guardar_parametros_cl` y `guardar_ley2046_tercero` sobre objetos de otra empresa "Sin permiso"; soporte con contrato o tercero de otra empresa rechazado por `cls_validar`; 0 soportes ajenos visibles.
- Proveedor del portal: 0 filas en el tablero, error al pedir su empresa, 0 soportes, no inserta, no marca Ley 2046 (ni por funcion ni por REST).
- anon: `permission denied` en la tabla y en las tres funciones.
- `crear_contrato_practica` por usuario normal: "Solo el administrador de la plataforma crea contratos de practica."
- Atajo de administrador: `es_admin_sql()` en todas las funciones nuevas; ningun `auth.uid() is null`.
- `where` en todos los `update`/`delete` (funciones, siembra y `borrar` del frontend, que ademas filtra por contrato).
- Base `facturado_total` contra `rubro_alimentos`: el calculo es correcto (requerido = (meta + extra) x facturado, o x facturado x rubro); sin rubro, cumplimiento nulo con alerta.
- Siembra idempotente en filas (17/17/17 antes y despues).
