# Auditoria independiente · Etapa M3 Compras (mig 024 a 026) y M4 Portal de proveedores parte 1 (mig 028)

Fecha: 6 de noviembre de 2026
Alcance: `20261124000000_m3_terceros_homologacion_precios.sql`, `20261125000000_m3_ordenes_compra.sql`, `20261126000000_tablero_costo_menu.sql`, `20261128000000_m4_portal_proveedores.sql`; pantallas `/proveedores`, `/precios`, `/ordenes-compra`, `/costos`, `/cotizaciones`, `/portal`, `layout.js`; componentes `proveedores.js`, `ordenes.js`, `portal-usuarios.js`, `ui.js`. Reglas: control de cambios v0.9.0 a v0.12.0 y `docs/ESPECIFICACION_PORTAL_PROVEEDORES_M4.md`.
Base de pruebas: Postgres local `sc9` (puerto 5499) con todas las migraciones. Pruebas de seguridad con usuarios reales simulados (`authenticator` + `request.jwt.claim.sub`), siempre dentro de `BEGIN ... ROLLBACK`. Usuarios de prueba: comprador `dir_compras` de Demo USPEC, dos usuarios proveedor (DistriPrueba y Granos del Caribe), un `aux_compras` interno, un `dir_compras` de Demo PAE y un tercero de Demo PAE. No se toco produccion ni el repositorio (solo este informe).
Scripts: `/tmp/claude-0/-home-claude/c2f15321-1fda-5e67-b6b0-3ef22ed48bfc/scratchpad/t1.sql` a `t8.sql`, `perf1.sql`, `perf2.sql`.

## Veredicto

El cerco basico del portal funciona: un usuario proveedor no ve por REST ninguna fila de otros proveedores (0 OC, 0 precios, 0 ofertas, 0 solicitudes ajenas), no ve explosiones, cupos, contratos, notificaciones ni perfiles de otros, y las 18 funciones de Compras probadas lo rechazan. El cambio de `es_miembro` no rompio a los internos (el comprador sigue viendo sus 55 tablas igual) y anon no tiene acceso a ninguna tabla. Las reglas de normalizacion (precio por unidad base y de compra), la vigencia del master, el reemplazo de la fila generica por la del grupo en `costo_ciclo` y la cadena solicitud, oferta, comparativo, adjudicacion y OC dan los numeros correctos en el caso feliz.

Pero hay un critico y seis altos que hay que cerrar antes de abrir el portal a un proveedor real. El critico: **cualquier usuario proveedor puede cambiar el contenido de una presentacion compartida** ("Bulto 50 kg" pasa a 5.000 g) y con eso multiplica por diez las cantidades que la sugerencia manda a las OC y el precio por kilo del master, propio o de la competencia. Los altos: el proveedor lee por REST las **notas internas** de la OC y de su ficha; un comprador puede **mezclar datos de otra empresa** pasando ids (requerimiento, tercero, sede); el proveedor **auto-certifica documentos** (vence 2099, ruta cualquiera) y edita la fila del adjunto; la adjudicacion **mezcla contado y credito en una OC y rotula "2 kg a $150.000"** lo que son bultos; la sugerencia de compra **no descuenta lo ya comprado** (doble compra) y en PAE grande devuelve **22 MB en 2,9 s**.

## Resumen por severidad

| Severidad | Cantidad | Numeros |
|---|---|---|
| Critico | 1 | C1 |
| Alto | 6 | A1 a A6 |
| Medio | 8 | M1 a M8 |
| Bajo | 10 | B1 a B10 |

Criticos y altos se corrigen antes de seguir; medios y bajos van al pendiente del control de cambios.

---

## Hallazgo critico

### C1 · Un proveedor (o una adjudicacion) reescribe el contenido de una presentacion compartida: cantidades x10 en la OC y precio por kilo falseado en el master

**Evidencia.** `presentaciones` es unica por `(empresa_id, producto_id, nombre)` y la comparten todos los proveedores. `portal_ofrecer_producto` (mig 028, linea 639) y `alta_oferta` (mig 024, linea 448, que tambien llama `adjudicar_solicitud`) hacen `on conflict (empresa_id, producto_id, nombre) do update set contenido = excluded.contenido`. El proveedor ve todas las presentaciones de la empresa (`presentaciones_prov`), asi que conoce los nombres de la competencia.

Prueba (`t3.sql`, bloque A): DistriPrueba tiene "Arroz · Diana · Bulto 50 kg" (50.000 g) a $160.000. El usuario de **Granos del Caribe** llama `portal_ofrecer_producto` con `presentacion = 'Bulto 50 kg', contenido = 5000`:

```
antes:   Bulto 50 kg | contenido 50000 | precio 160000 | por_unidad_base 3,20 $/g
despues: Bulto 50 kg | contenido  5000
Compras registra 160.000 por bulto a DistriPrueba:  por_unidad_base 32,00 $/g  (32.000 $/kg en vez de 3.200)
sugerir_compra (2 dias, 3.212 kg de arroz):  DistriPrueba · 643 bultos x $160.000   (lo correcto: 65 bultos)
```

**Impacto.** Un proveedor puede (a) inflar diez veces las cantidades de las OC que le salgan a el mismo, (b) hacer ver carisimo a un competidor en el master y en el tablero de costos en el siguiente precio que se le registre, o (c) desordenar el comparativo. La misma sobreescritura ocurre sin mala fe cuando Compras adjudica una variante cuyo proveedor escribio "Caja 12 kg" con otro contenido que el ya registrado. Es dinero y no deja rastro (las presentaciones tienen bitacora, pero nadie la mira).

**Arreglo.**
1. Nunca actualizar el contenido en un `on conflict`; si el nombre existe con otro contenido, error claro:
```sql
-- en alta_oferta y en portal_ofrecer_producto, reemplazar el insert de presentaciones por:
insert into public.presentaciones (empresa_id, producto_id, nombre, contenido, unidad_empaque)
values (v_emp, p_producto, trim(p_presentacion), p_contenido, coalesce(p_unidad_empaque, 'und'))
on conflict (empresa_id, producto_id, nombre) do update set nombre = excluded.nombre
returning id, contenido into v_pres, v_cont;
if v_cont <> p_contenido then
  raise exception 'Ya existe la presentacion "%" con % de contenido; use otro nombre (ej.: "%" %).', trim(p_presentacion), v_cont, trim(p_presentacion), p_contenido;
end if;
```
2. Blindaje en la tabla (cubre cualquier otro camino):
```sql
create or replace function public.presentaciones_contenido_fijo() returns trigger language plpgsql as $$
begin
  if new.contenido is distinct from old.contenido and exists (select 1 from public.proveedor_productos pp where pp.presentacion_id = old.id) then
    raise exception 'La presentacion % ya tiene ofertas; su contenido no se cambia. Cree otra presentacion.', old.nombre;
  end if;
  return new;
end $$;
drop trigger if exists presentaciones_contenido_fijo on public.presentaciones;
create trigger presentaciones_contenido_fijo before update of contenido on public.presentaciones
  for each row execute function public.presentaciones_contenido_fijo();
```
3. Revisar en produccion con la bitacora si algun contenido cambio despues de tener precios (`select * from bitacora where tabla = 'presentaciones' and accion = 'UPDATE'`) y recalcular `precios.por_unidad_base` de esas ofertas (`update public.precios set precio = precio where proveedor_producto_id in (...)` dispara el trigger).
4. Que el proveedor que ofrece un producto nuevo no cree presentaciones en el catalogo comun: guardar su propuesta en `proveedor_productos` con `estado = 'propuesto'` y la presentacion en texto, y que Compras la cree al homologar.

---

## Hallazgos altos

### A1 · El proveedor lee por REST columnas internas: notas internas de la OC, notas de su ficha, motivo de compra, notas de la solicitud

**Evidencia.** Las policies del proveedor abren la fila completa (`select` sobre la tabla). Prueba (`t3.sql`, bloque C): Compras crea una OC con `notas_internas = 'Proveedor caro, solo por urgencia; negociar 8% menos'`, la aprueba y la envia. El usuario proveedor hace `select codigo, notas_internas from ordenes_compra`:

```
OC-000001 | Proveedor caro, solo por urgencia; negociar 8% menos | creado_por 1111… | aprobada_por 1111…
oc_items: descripcion, motivo ('INPEC prioritario' / 'mejor precio' / 'unica opcion'), requerida_base
```
Mismo patron en `terceros_ver_propio` (columnas `notas`, `cupo_credito`, `calificacion`, `siigo_id`, `homologado_por`), `proveedor_productos_prov` (`notas`), `precios_prov` (`notas`, `soporte`), `solicitudes_prov` (`notas`, que es el campo interno de la solicitud, distinto de `condiciones`; ahi tambien queda el motivo de anulacion).

**Impacto.** El proveedor ve la estrategia de negociacion, lo que de verdad necesita la empresa (`requerida_base`), si fue "unica opcion" y las notas internas sobre el. La especificacion dice "nunca ve ... el comparativo"; esto es peor.

**Arreglo.** El portal ya trabaja por RPC (`portal_resumen`, `portal_solicitud`); solo `oc_items` y `adjuntos` se leen por REST. Quitar las policies de fila completa y exponer lo necesario por RPC:
```sql
drop policy if exists ordenes_compra_prov on public.ordenes_compra;
drop policy if exists oc_items_prov on public.oc_items;
drop policy if exists terceros_ver_propio on public.terceros;
drop policy if exists proveedor_productos_prov on public.proveedor_productos;
drop policy if exists precios_prov on public.precios;
drop policy if exists solicitudes_prov on public.solicitudes_cotizacion;
drop policy if exists solicitud_lineas_prov on public.solicitud_lineas;

create or replace function public.portal_oc_items(p_oc uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.ordenes_compra;
begin
  select * into o from public.ordenes_compra where id = p_oc;
  if o.id is null or public.mi_tercero(o.empresa_id) is distinct from o.tercero_id or o.estado in ('borrador', 'anulada') then raise exception 'Sin acceso a esta OC'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('descripcion', i.descripcion, 'unidad_pedido', i.unidad_pedido, 'cantidad', i.cantidad, 'precio', i.precio,
            'iva_pct', i.iva_pct, 'total', i.total, 'cantidad_recibida', i.cantidad_recibida) order by i.descripcion), '[]') from public.oc_items i where i.oc_id = p_oc);
end $$;
revoke all on function public.portal_oc_items(uuid) from public, anon;
grant execute on function public.portal_oc_items(uuid) to authenticated;
```
Y en `app/(app)/portal/page.js:282` cambiar el `from('oc_items')` por `sb().rpc('portal_oc_items', { p_oc: oc.id })`. Las policies de `ofertas`, `oferta_lineas`, `precios_propuestos`, `tercero_documentos` y `adjuntos` del proveedor pueden quedar (son datos que el mismo escribio), pero ver A3 para `adjuntos`.

### A2 · Referencias cruzadas entre empresas en M3/M4: un comprador de la empresa A lee el requerimiento, el contrato, terceros y sedes de la empresa B

**Evidencia.** Ninguna tabla nueva de M3 parte 2 ni de M4 tiene el trigger `validar_empresa_coherente` (solo `proveedor_productos`, `precios` y los de mig 024), y el trigger no valida `tercero_id`, `explosion_id`, `sede_entrega_id`, `proveedor_producto_id`, `ficha_tecnica_id`. Las funciones no validan los ids que reciben. Prueba (`t3.sql` bloque E y `t4.sql` bloque E2), como `dir_compras` de **Demo USPEC**:

```
guardar_solicitud(empresa Demo USPEC, explosion_id = requerimiento de Demo PAE, invitados = [tercero de Demo PAE])
  -> 89 lineas, 140.541,96 en cantidades del requerimiento de PAE
comparar_ofertas -> contrato "DEMO-PAE-2026", invitado "PROVEEDOR SOLO PAE", productos de PAE
guardar_oc(empresa Demo USPEC, tercero de PAE, contrato_sede de PAE)
  -> oc_detalle: proveedor "PROVEEDOR SOLO PAE", entrega "IE Tecnica de Practica"
```
Lo mismo aplica a `generar_oc` (tercero y `pp_id` sin validar), `guardar_oc_item` (`pp_id`, `producto_id`), `adjudicar` no (toma todo de la solicitud). Ademas `portal_resumen` lista solicitudes y OC por `tercero_id` sin filtrar `empresa_id`, asi que un proveedor de B veria la solicitud de A en la que lo invitaron por id.

**Impacto.** Requiere conocer uuids, pero rompe la promesa de aislamiento entre empresas (las UT del grupo son contratistas distintos) y deja datos mezclados que luego nadie puede explicar.

**Arreglo.** Un validador propio para M3/M4 (no se extiende el generico para no chocar con columnas homonimas de otras tablas):
```sql
create or replace function public.validar_empresa_m3m4() returns trigger language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); v_emp uuid := (j->>'empresa_id')::uuid; col text; tbl text; v_e uuid;
begin
  for col, tbl in select * from (values ('tercero_id','terceros'), ('explosion_id','explosiones'), ('contrato_id','contratos'), ('contrato_sede_id','contrato_sedes'),
      ('sede_entrega_id','sedes'), ('producto_id','productos'), ('proveedor_producto_id','proveedor_productos'), ('solicitud_id','solicitudes_cotizacion'),
      ('oferta_id','ofertas'), ('linea_id','solicitud_lineas'), ('oferta_linea_id','oferta_lineas'), ('oc_id','ordenes_compra'),
      ('ficha_tecnica_id','adjuntos'), ('adjunto_id','adjuntos'), ('marca_id','marcas'), ('presentacion_id','presentaciones')) x(c, t) loop
    if j ? col and j->>col is not null then
      execute format('select empresa_id from public.%I where id = $1', tbl) into v_e using (j->>col)::uuid;
      if v_e is distinct from v_emp then raise exception 'Referencia de otra empresa en %.%.', tg_table_name, col; end if;
    end if;
  end loop;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['ordenes_compra','oc_items','solicitudes_cotizacion','solicitud_lineas','solicitud_invitados','ofertas','oferta_lineas','adjudicaciones','precios_propuestos','usuarios_proveedor','presentaciones','tercero_documentos','terceros'] loop
    execute format('drop trigger if exists %I_empresa_m3m4 on public.%I', t, t);
    execute format('create trigger %I_empresa_m3m4 before insert or update on public.%I for each row execute function public.validar_empresa_m3m4()', t, t);
  end loop; end $$;
```
Y en `portal_resumen` agregar `and s.empresa_id = p_empresa` en solicitudes y `and o.empresa_id = p_empresa` en ordenes y evaluaciones (`ev.empresa_id = p_empresa`).

### A3 · El proveedor auto-certifica documentos: vencimiento libre, ruta libre, sobreescribe el documento ya validado y edita la fila del adjunto por REST

**Evidencia.**
1. `portal_documento` acepta `p_ruta` y `p_vence` tal cual y hace `on conflict (tercero_id, codigo) do update` sobre `tercero_documentos` (el registro que Compras ya habia revisado). Prueba (`t3.sql` bloque B): `portal_documento(emp, 'rut', ..., 'cualquier/ruta/que/no/es/mia.pdf', ..., vence '2099-12-31')` queda `rut | 2099-12-31`, estado "al dia". El calculo de vencimiento por `vigencia_dias` solo existe en el navegador (`portal/page.js:330`) y el campo es editable.
2. La policy `adjuntos_editar` deja actualizar a quien subio (`subido_por = auth.uid()`), y el adjunto lo inserto la funcion con el uid del proveedor. Prueba (`t5.sql`): el proveedor hace `update adjuntos set ruta = '<empresa>/contratos/secreto.pdf', vigente_hasta = '2099-01-01'` y queda aplicado. Tambien puede borrarlo (`adjuntos_borrar`) si no lo referencia un documento.
3. `portal_ofrecer_producto` con `on conflict ... do update set ficha_tecnica_id, registro_sanitario` cambia la ficha y el registro INVIMA de una oferta **ya homologada**, y `portal_guardar_variante` acepta cualquier `ficha_tecnica_id` (incluso de otra empresa), que luego `adjudicar_solicitud` copia a `proveedor_productos`.

**Impacto.** La especificacion dice "todo lo que el proveedor cambia queda en estado propuesto hasta que Compras lo acepta". Hoy el proveedor puede dejar "al dia" un concepto sanitario vencido o apuntar el RUT a otro archivo, y eso alimenta la homologacion y los KPI de documentos vencidos. En contratos de alimentacion del Estado es un tema de interventoria.

**Arreglo.**
```sql
alter table public.tercero_documentos add column if not exists estado_validacion text not null default 'validado'
  check (estado_validacion in ('pendiente', 'validado', 'rechazado'));
-- en portal_documento:
--   if p_ruta not like p_empresa::text || '/proveedor/' || v_t::text || '/%' then raise exception 'Ruta no valida'; end if;
--   v_vence := coalesce(p_fecha, hoy) + (select vigencia_dias from tipos_documento_tercero where codigo = p_codigo)  (ignorar p_vence si hay vigencia fija)
--   guardar en tercero_documentos con estado_validacion = 'pendiente' (o en una tabla documentos_propuestos) sin pisar el validado;
--   proveedores_lista/proveedor_ficha cuentan como 'ok' solo lo validado.
drop policy if exists adjuntos_editar on public.adjuntos;
create policy adjuntos_editar on public.adjuntos for update to authenticated
  using (public.es_superadmin() or (subido_por = auth.uid() and public.es_miembro(empresa_id)) or public.tiene_permiso(empresa_id, 'M0', 'editar'))
  with check (public.es_superadmin() or (subido_por = auth.uid() and public.es_miembro(empresa_id)) or public.tiene_permiso(empresa_id, 'M0', 'editar'));
drop policy if exists adjuntos_borrar on public.adjuntos;
create policy adjuntos_borrar on public.adjuntos for delete to authenticated
  using (public.es_superadmin() or (subido_por = auth.uid() and public.es_miembro(empresa_id)) or public.tiene_permiso(empresa_id, 'M0', 'editar'));
```
En `portal_ofrecer_producto`: `on conflict do nothing` y, si la oferta ya existe y no esta `propuesto`, error "use Proponer precio" (la ficha nueva va como documento pendiente). En `portal_guardar_variante` y `portal_ofrecer_producto`: validar que `ficha_tecnica_id` sea un adjunto `entidad = 'proveedor' and entidad_id = v_t`.

### A4 · La adjudicacion arma OC con condiciones de pago mezcladas, unidad de pedido equivocada y sin tope de cantidad, y se puede adjudicar con la solicitud abierta

**Evidencia** (`t3.sql`, bloque I). Solicitud con una linea de 10 kg de arroz. DistriPrueba cotiza dos variantes del mismo bulto de 50 kg sin llenar "tipo de empaque": contado $150.000 y credito 60 d $155.000. Con la solicitud **publicada y abierta** (cierre en dos dias), Compras adjudica 900 a la variante 2 y 100 a la 1, y luego otras 500 a la 1:

```
pedida 10 | adjudicada 1.500
OC-000003 | credito | 60 d |  2 | kg | 150000   <- precio de contado, condiciones de credito 60 d
OC-000003 | credito | 60 d | 18 | kg | 155000
OC-000004 | contado | 30 d | 10 | kg | 150000   <- "contado 30 dias"
master: 150000 contado (la variante de credito se perdio)
```
Causas en `adjudicar_solicitud` (mig 028): agrupa por proveedor + lugar + sede y toma `condicion_pago`/`plazo_dias` de `... limit 1` de cualquier linea del proveedor (lineas 436-437); `unidad = coalesce(v.unidad_empaque, v.unidad_compra)` rotula "kg" una presentacion de 50 kg cuando el empaque viene vacio (la `contenido_base` 50.000 si queda bien, el texto no); no compara la suma adjudicada contra `solicitud_lineas.cantidad`; no exige cierre; no mira `ofertas.validez_hasta`; `plazo_dias` cae al del tercero aunque sea contado.

**Impacto.** La OC impresa le dice al proveedor "2 kg a $150.000" y "credito 60 dias" sobre un precio de contado; recepcion y cuentas por pagar heredan el error. La sobreadjudicacion genera OC por 150 veces lo pedido sin alerta.

**Arreglo.**
- Agregar `condicion_pago` y `plazo_dias` a `tmp_adj` (desde la variante) y agrupar las OC por `tercero_id, lugar, contrato_sede_id, condicion_pago, plazo_dias`; usar esos valores en la cabecera; si es contado, `plazo_dias = null`.
- `unidad_pedido = case when v.contenido is null then v.unidad_compra else coalesce(nullif(trim(v.presentacion), ''), v.unidad_empaque, 'empaque') end` y en `portal_guardar_variante` exigir `presentacion` cuando hay `contenido`.
- Validaciones antes de insertar:
```sql
if s.estado = 'publicada' and s.cierre > now() then raise exception 'La solicitud sigue abierta hasta %; cierrela antes de adjudicar.', s.cierre; end if;
if exists (select 1 from (select l.id, l.cantidad, coalesce((select sum(a.cantidad) from public.adjudicaciones a where a.linea_id = l.id), 0)
                                + coalesce((select sum((x->>'cantidad')::numeric) from jsonb_array_elements(p_items) x where (x->>'linea_id')::uuid = l.id), 0) total
                            from public.solicitud_lineas l where l.solicitud_id = p_solicitud) q where q.total > q.cantidad * 1.10) then
  raise exception 'La cantidad adjudicada supera lo pedido en mas de 10 %%.';
end if;
-- y por item: if v.validez_hasta < hoy then raise exception 'La oferta vencio el %', ...
```
- El master guarda una sola condicion por oferta de catalogo: si se adjudican dos variantes del mismo producto x marca x presentacion, registrar la de menor costo efectivo (o la mas adjudicada) y dejar la otra en `notas`; ver tambien M4.

### A5 · La sugerencia de compra no descuenta lo que ya esta en OC: doble compra

**Evidencia.** `sugerir_compra` calcula `ya_en_oc_base` pero las asignaciones salen de `req`/`resto` completos. La pantalla (`components/ordenes.js:28`) deja seleccionado todo producto con `ya_en_oc_base < requerido_base` y con la cantidad sugerida completa. Prueba (`t8.sql`): arroz del requerimiento de 2 dias, sugerencia 65 bultos; se genera una OC de 30 bultos (1.500 kg); la sugerencia sigue diciendo **65** con `ya_en_oc_base = 1.500.000`. Lo mismo pasa con lo adjudicado desde una solicitud (sus OC quedan ligadas al requerimiento).

**Impacto.** Si el comprador cubre una parte por solicitud de cotizacion o por una OC manual y despues usa "Generar OC" sobre el mismo requerimiento, compra de nuevo la cantidad completa (en el ejemplo, 95 bultos para una necesidad de 65).

**Arreglo.** Descontar en la base de la sugerencia; por establecimiento lo entregado en sede y en el CEDI lo que va al CEDI:
```sql
ya_sede as (select i.producto_id, o.contrato_sede_id, sum(i.cantidad_base) base from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id
             where o.explosion_id = p_explosion and o.estado <> 'anulada' and o.lugar_entrega = 'sede' group by 1, 2),
ya_cedi as (select i.producto_id, sum(i.cantidad_base) base from public.oc_items i join public.ordenes_compra o on o.id = i.oc_id
             where o.explosion_id = p_explosion and o.estado <> 'anulada' and o.lugar_entrega = 'cedi' group by 1),
req as (select d.producto_id, d.contrato_sede_id, greatest(sum(d.cantidad_bruta) - coalesce(max(ys.base), 0), 0) base
          from public.explosion_detalle d left join ya_sede ys on ys.producto_id = d.producto_id and ys.contrato_sede_id = d.contrato_sede_id
         where d.explosion_id = p_explosion group by 1, 2),
```
y en la rama CEDI del `lateral g`: `greatest(sum(r.base) - coalesce((select base from ya_cedi c where c.producto_id = p.id), 0), 0)`. En la pantalla, ademas, mostrar "pendiente" como cantidad por defecto.

### A6 · `sugerir_compra` en un PAE de tamano real: 22 MB de respuesta y 2,9 s en local

**Evidencia** (`perf1.sql`): contrato Demo PAE con 334 colegios, requerimiento de 90 dias (2,67 millones de filas en `explosion_detalle`, 89 productos), 10 proveedores homologados con precio para todo, 3 de ellos con entrega en sede (los mas baratos):

| Funcion | Tiempo local | Respuesta |
|---|---|---|
| `sugerir_compra` | 2.894 ms (2.716 ms en caliente) | **22.323.216 bytes** |

El grueso es una asignacion jsonb por producto y por colegio cuando el proveedor entrega en sede (89 x 334), mas `por_sede` (otra vez 89 x 334) y 10 alternativas por producto con todos sus campos.

**Impacto.** En Supabase (CPU mas lenta que el local) el tiempo queda entre 4 y 9 s, al borde del corte de 8 s, y 22 MB de JSON por PostgREST tumban el navegador del comprador en un celular o en una red de bodega. USPEC (12 sedes) no lo nota; PAE con cientos de colegios si.

**Arreglo.** (1) Parametro `p_categoria` y `p_producto` para traer por bloques (la pantalla ya filtra); (2) devolver las asignaciones por sede en forma compacta (`[contrato_sede_id, base, cantidad]` en un arreglo, con los datos del proveedor una sola vez por producto) y `por_sede` solo cuando se abre el producto (RPC `sugerir_compra_producto`); (3) indice ya existe (`explosion_detalle_prod_idx`), el agregado de 2,7 M filas toma ~1 s: materializar `req` en una tabla temporal con `analyze` si se mantiene en una sola llamada. Meta: menos de 1 MB y 1 s por llamada.

---

## Hallazgos medios

### M1 · `invitar_usuario_proveedor` activa cuentas con el correo sin confirmar, y convierte en proveedor a un usuario interno de otra empresa
**Evidencia.** Busca `auth.users` por correo sin mirar `email_confirmed_at` (prueba `t4.sql` F: las dos cuentas quedan activas con `email_confirmed_at` nulo). Si en Supabase quedan abiertos el registro publico o el inicio sin confirmar, quien se registre primero con `ventas@proveedor.com` queda dentro del portal de ese proveedor. Ademas, invitar el correo de un usuario interno de **otra** empresa funciona y le cambia `perfiles.tipo` a `proveedor` a nivel global (F2: el comprador de Demo PAE quedo `tipo = proveedor`); si es un superadmin, `mi_rol` devuelve `proveedor` en esa empresa y el layout lo redirige a `/portal`.
**Arreglo.** `select id into v_user from auth.users where lower(email) = lower(trim(p_correo)) and email_confirmed_at is not null;` (si no, queda pendiente); no tocar `perfiles.tipo` si el usuario tiene membresias internas en cualquier empresa o es superadmin; rechazar si `perfiles.es_superadmin`.

### M2 · Policies que llaman funciones fila por fila: 18,4 s para que un proveedor lea `precios`, 1,7 s para un interno
**Evidencia** (`perf2.sql`, Demo PAE con 40 proveedores x 117 productos x 12 meses = 56.160 precios). `select count(*) from precios` como `dir_compras`: 1.671 ms; como proveedor: **18.452 ms**. El plan muestra `Filter: es_superadmin() OR es_miembro(empresa_id) OR (hashed SubPlan) OR puede_compras(empresa_id, 'crear')` evaluado en cada fila (para el proveedor ninguna rama corta, son ~6 consultas por fila). Pasa en todas las tablas con `_ver` + `_escribir for all` + `_prov`.
**Impacto.** Hoy la pantalla no lee esas tablas por REST, pero cualquier usuario puede lanzar la consulta (carga sobre la base) y cualquier pantalla futura que lo haga se corta.
**Arreglo.** Patron de Supabase con initplan y conjuntos, una sola evaluacion por consulta:
```sql
create or replace function public.mis_empresas_internas() returns setof uuid language sql stable security definer set search_path = public as $$
  select m.empresa_id from public.membresias m join public.roles r on r.id = m.rol_id where m.usuario_id = auth.uid() and m.activo and not r.es_proveedor $$;
-- y en cada policy _ver:  using ((select public.es_superadmin()) or empresa_id in (select public.mis_empresas_internas()))
```
(igual para `puede_compras`: `empresa_id in (select public.mis_empresas_con_permiso('M3', 'crear'))`). Con A1 desaparecen las policies `_prov` mas caras.

### M3 · El comparativo se ve y se adjudica antes del cierre (oferta sellada)
**Evidencia.** `comparar_ofertas` muestra precios de las ofertas `enviada` con la solicitud publicada y abierta; `adjudicar_solicitud` acepta `publicada` (ver A4). El portal le dice al proveedor "Compras vera su oferta al cierre junto con las demas".
**Impacto.** En compras para contratos del Estado la interventoria espera que nadie vea precios antes del cierre; hoy un comprador podria pasarle el precio a un proveedor que todavia esta cotizando.
**Arreglo.** En `comparar_ofertas`, si `s.estado = 'publicada' and s.cierre > now()`, devolver invitados y estado (visto, enviada) pero `variantes` vacias salvo para superadmin; cierre automatico al pasar la hora (la pantalla o un cron llaman `estado_solicitud('cerrar')`).

### M4 · La adjudicacion reutiliza ofertas de catalogo suspendidas o rechazadas y el precio queda invisible
**Evidencia** (`t4.sql` R). La oferta "Arroz · Diana · Bulto 50 kg" de DistriPrueba esta `suspendido`; se adjudica una variante con la misma marca y presentacion: `alta_oferta(..., 'homologado')` cae en el `on conflict` que no toca `estado`, el precio $150.000 entra al master pero la oferta sigue `suspendido`; `sugerir_compra` muestra 0 elegibles para el arroz y `costo_ciclo` no lo usa. Si estaba `rechazado` pasa igual (y el proveedor no puede proponer precio sobre una rechazada pero si ganar una adjudicacion).
**Arreglo.** En `adjudicar_solicitud`, despues de `alta_oferta`: si la oferta esta `suspendido` o `rechazado`, error explicito ("la oferta de catalogo esta suspendida; levantela o adjudique otra"); si esta `propuesto`, homologarla (`update proveedor_productos set estado = 'homologado' where id = v_pp and estado = 'propuesto'`). Usar el `v_pp` que devuelve `alta_oferta` en `tmp_adj` en vez de buscar por nombres (lineas 426-427 pisan `v_pp` con el id de la adjudicacion y luego lo reconstruyen por texto).

### M5 · Solicitud desde requerimiento con entrega "en el establecimiento" pierde el establecimiento
**Evidencia.** `guardar_solicitud` con `explosion_id` agrega por producto (sin `contrato_sede_id`); `adjudicar_solicitud` solo manda a sede si la linea trae `contrato_sede_id`, asi que con `lugar_entrega = 'sede'` todo sale en una OC al CEDI. En carceles grandes (perecederos directos, regla de Osvaldo) la solicitud no sirve.
**Arreglo.** Cuando `lugar_entrega in ('sede', 'ambos')` y hay requerimiento, crear una linea por producto y establecimiento (`group by d.producto_id, d.contrato_sede_id`), o guardar el reparto por sede en una tabla hija y repartir la cantidad adjudicada en OC por establecimiento.

### M6 · Sin bitacora ni historial en las tablas del portal (evidencia para la interventoria)
**Evidencia.** `solicitudes_cotizacion`, `solicitud_lineas`, `solicitud_invitados`, `ofertas`, `oferta_lineas`, `adjudicaciones`, `precios_propuestos`, `usuarios_proveedor` y `ordenes_compra`/`oc_items` no tienen trigger `registrar_bitacora` (si lo tienen las de mig 024). La variante editada despues de enviada se sobreescribe y se puede borrar (`borrar: true`) mientras la solicitud este abierta. La especificacion pide "bitacora completa; descarga de evidencias (quien oferto que y cuando)".
**Arreglo.**
```sql
do $$ declare t text; begin
  foreach t in array array['solicitudes_cotizacion','solicitud_lineas','solicitud_invitados','ofertas','oferta_lineas','adjudicaciones','precios_propuestos','usuarios_proveedor','ordenes_compra','oc_items'] loop
    execute format('drop trigger if exists %I_bitacora on public.%I', t, t);
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
  end loop; end $$;
```
Y en `portal_estado_oferta('enviar')` guardar una foto (`ofertas.snapshot jsonb` con las variantes) por cada envio.

### M7 · `costo_ciclo` usa las raciones de todo el contrato aunque el ciclo lo use una sola sede (caso real de Diestra)
**Evidencia.** `tmp_rac` suma los cupos vigentes de todas las sedes del contrato. En UT Diestra `CICLO_EP` esta asignado a 1 sede (el batallon, 26 PPL) y `CICLO_ERON` a 5; los dos devuelven `raciones_dia = 5.251` por tiempo. El ahorro mensual de las sugerencias del ciclo EP sale unas 200 veces inflado.
**Arreglo.** Filtrar por las sedes con el ciclo vigente a la fecha:
```sql
join public.sede_ciclo sc on sc.contrato_sede_id = cs.id and sc.ciclo_id = p_ciclo and sc.vigente_desde <= v_f and (sc.vigente_hasta is null or sc.vigente_hasta >= v_f)
```
(si ninguna sede lo tiene asignado, usar el contrato completo y avisar "ciclo sin sedes asignadas").

### M8 · Cambios del proveedor que no pasan por "propuesto" y datos de su ficha que no ve ni puede corregir
**Evidencia.** Ademas de A3: `portal_guardar_variante` deja editar y borrar variantes de una oferta `parcial` mientras la solicitud siga publicada (solo el trigger impide editar, no borrar), y la oferta editada conserva el `enviada_en` viejo, asi que el comparativo no muestra que cambio despues de enviada. Al reves, el proveedor no tiene como proponer cambios a sus datos de contacto o bancarios (la especificacion pide doble aprobacion para los bancarios).
**Arreglo.** Prohibir borrar variantes de ofertas que no esten en `borrador`/`enviada` (agregar `delete` al trigger `oferta_lineas_antes` o validar en la funcion), actualizar `ofertas.actualizado_en` y mostrarlo en el comparativo ("editada despues de enviada"), y dejar los datos bancarios para la parte 2 con tabla de cambios propuestos.

---

## Hallazgos bajos

| # | Hallazgo | Arreglo |
|---|---|---|
| B1 | `precio_base_producto`, `tercero_bloqueado`, `ve_sede`, `es_empresa_demo` y `dv_nit` siguen ejecutables por PUBLIC (anon). Son de invocador o de solo lectura, pero rompen la regla del protocolo. | `revoke all on function ... from public, anon; grant execute ... to authenticated;` |
| B2 | Policies de storage hacen `((storage.foldername(name))[1])::uuid`: un objeto con primer segmento no uuid (por ejemplo subido por superadmin a `logos/`) hace fallar con "invalid input syntax for type uuid" cualquier listado que lo toque. Las rutas maliciosas del proveedor se rechazan bien (probado: su ruta si, la de otro tercero no, la de otra empresa no). | Funcion `public.uuid_o_nulo(text)` con `exception when others then return null` y usarla en las 5 policies. |
| B3 | `estado_solicitud('reabrir')` exige cierre futuro pero no hay forma de mover el cierre de una solicitud publicada o cerrada (`guardar_solicitud` solo edita borradores). | Parametro `p_cierre` en `reabrir`. |
| B4 | OC de adjudicacion o `generar_oc` con "contado" heredan `plazo_dias` del tercero ("contado 30 d"). | `plazo_dias = case when condicion_pago = 'contado' then null else ... end`. |
| B5 | El costo efectivo del comparativo ignora el IVA: un exento y uno con 19 % se comparan sin IVA aunque la UT no lo descuente. | Config `compras.iva_es_costo` (por defecto si en contratos sin IVA descontable) y sumar el IVA al costo efectivo. |
| B6 | Invitados automaticos incluyen proveedores `en_proceso` (la especificacion dice homologados) y no se valida que los invitados elegidos a mano sean proveedores activos de la empresa (lo cubre A2 para la empresa). | Filtrar `estado_homologacion in ('homologado', 'condicionado')` y validar invitados manuales. |
| B7 | La notificacion de precio propuesto enlaza a `/precios?propuestos=1`, pero los propuestos viven en `/cotizaciones?t=propuestos` (la pagina de precios ignora el parametro). | Cambiar el enlace en `portal_proponer_precio`. |
| B8 | `generar_oc` y `guardar_oc_item` toman el precio del navegador sin compararlo con el master; no se avisa si difiere. | Guardar `precio_master` en `oc_items` y marcar la diferencia en el detalle. |
| B9 | `sugerir_compra` ignora `precios.lugar_entrega` (un precio puesto en sede se compara igual que uno en CEDI) y `precio_base_producto` toma precios de proyectos productivos INPEC que solo sirven a su establecimiento para costear todo el contrato. | Filtrar por lugar compatible y excluir INPEC de `precio_base_producto` salvo costeo por sede. |
| B10 | Cada llamada a `costo_ciclo` y `adjudicar_solicitud` emite NOTICE "table tmp_... does not exist, skipping". | `set local client_min_messages = warning` dentro de la funcion o `drop table if exists` solo cuando exista. |

---

## Tiempos medidos (local, Postgres 16)

| Funcion o consulta | Tamano | Tiempo | Respuesta |
|---|---|---|---|
| `sugerir_compra` | PAE sintetico 334 colegios, 90 dias, 2,67 M filas, 10 proveedores | 2.894 ms | 22,3 MB (A6) |
| `guardar_solicitud` desde ese requerimiento | 89 lineas, 10 invitados | 645 ms | |
| `comparar_ofertas` | 89 lineas x 10 proveedores x 2 variantes (1.780) | 167 ms | 1,35 MB |
| `costo_ciclo` | Demo PAE 360 casillas / Demo USPEC 285 / Diestra 285 | 173 / 66 / 61 ms | 0,25 a 0,32 MB |
| `master_precios` | Demo PAE, 1.170 ofertas | 82 ms | 0,66 MB |
| `portal_resumen` | proveedor con 117 ofertas de catalogo | 14 ms | 88 KB |
| `solicitudes_lista` | | 3 ms | |
| `select count(*) from precios` por REST | 56.160 precios; interno / proveedor | 1.671 / 18.452 ms | (M2) |

---

## Seguridad: lo que se probo y paso bien

- Proveedor por REST (`t1.sql`, recorrido de las 78 tablas y vistas): ve solo `empresas` (la suya), su `terceros`, sus `proveedor_productos` y `precios`, `productos`/`marcas`/`presentaciones` de la empresa, su `usuarios_proveedor`, su `membresias`, su `perfiles` y catalogos globales (`festivos`, `modulos`, `roles`, `permisos`, `tipos_dieta`, `reglas_dieta`, `smlmv`, `plantillas_modalidad`, `tipos_documento_tercero`). Cero filas en explosiones, cupos, contratos, sedes, notificaciones, solicitudes no invitadas, ofertas y OC de otros, adjuntos de otros. Las vistas son `security_invoker`.
- Segundo proveedor (`t3.sql` D): 0 OC, 0 precios, 0 variantes ajenas; `portal_confirmar_oc` y `portal_proponer_precio` sobre lo de otro: "Sin acceso"; `portal_solicitud` y `portal_guardar_variante` en una solicitud a la que no fue invitado: "Sin acceso"; `portal_estado_oferta` sin oferta: error; `portal_vista` no hace nada.
- Funciones de Compras como proveedor (`t2.sql`): `comparar_ofertas`, `sugerir_compra`, `master_precios`, `proveedor_ficha` (propia y ajena), `ocs_lista`, `solicitudes_lista`, `precios_propuestos_lista`, `registrar_precio`, `alta_oferta`, `invitar_usuario_proveedor`, `guardar_solicitud`, `estado_solicitud`, `explosion_resumen`: "Sin permiso"; `catalogos_compras` devuelve nulo; `usuarios_empresa` 0 filas.
- Todas las funciones `security definer` de `public` tienen control (ninguna sin `puede_*`, `tiene_permiso`, `es_miembro`, `mi_tercero` o `auth.uid`, salvo `es_empresa_demo`, que solo devuelve un booleano). Las 18 de M4 y las de M3 estan revocadas a public/anon y concedidas a authenticated.
- `es_miembro` nuevo: ningun rol interno tiene `es_proveedor`; el comprador interno ve lo mismo que antes; `perfiles_ver` no filtra perfiles de otros proveedores (la subconsulta sobre `membresias` respeta RLS); el proveedor no puede escalar (no tiene M0, `membresias_crear` y `asignar_usuario` lo rechazan; cambiar su `perfiles.tipo` no da nada porque nadie lo usa para permisos).
- Storage: la expresion de las policies del proveedor da verdadero solo para `<empresa>/proveedor/<su tercero>/...` y falso o nulo para otro tercero u otra empresa.
- Anon: 0 tablas con `select`; no hay tablas de `public` sin RLS.
- Reglas correctas: precio por unidad base (`precio / contenido`, granel `/ factor_compra`) y por unidad de compra (`x factor_compra`) coinciden entre trigger, comparativo, master y formulario del portal; `registrar_precio` cierra el anterior el dia antes y respeta la exclusion; `costo_ciclo` reemplaza la fila generica por la del grupo (probado: res 111 g a 222 g con fila del grupo, sin duplicar); INPEC primero en su establecimiento y preferido antes que precio en `sugerir_compra`; cantidades de la OC de adjudicacion (`ceil(cantidad x factor / contenido)`) correctas cuando hay contenido.

## Diseno (observaciones, no bloquean)

- **Presentaciones compartidas** (raiz de C1): el modelo mezcla catalogo comun (lo que la empresa compra) con lo que cada proveedor ofrece. Recomiendo que la presentacion sea de la oferta (`proveedor_productos.contenido`, `unidad_empaque`, nombre) y que `presentaciones` quede como catalogo de referencia que solo Compras edita.
- **Una condicion por oferta en el master**: las variantes "contado" y "credito" del mismo empaque colapsan en un solo `precio`. Si las condiciones alternativas son parte del negocio (pedido de Osvaldo), el master necesita la condicion en la llave (`unique ... (proveedor_producto_id, condicion_pago)` en la exclusion) o una tabla de precios alternos.
- **Grupo de referencia en `costo_ciclo`**: el costo por racion se calcula para un grupo y se multiplica por las raciones de todos los grupos. Para contratos con gramajes muy distintos por grupo (PAE por niveles) conviene ponderar por grupo.
- `adjudicar_solicitud` y `generar_oc` repiten la logica de cabecera de OC; una funcion interna `crear_oc_borrador(...)` evita que diverjan (hoy ya divergen en condicion de pago).
- `estado_oc('confirmar')` (Compras) y `portal_confirmar_oc` (proveedor) hacen lo mismo con reglas distintas; unificar.

## UI/UX (breve)

- El menu muestra "Portal de proveedores" a los internos con permiso M4 (dir_compras, jefe_compras, calidad...) y la pantalla les responde con un error; ocultarlo si el rol no es `proveedor`.
- Portal: el boton "Ver" de un documento cargado antes por Compras (ruta fuera de `/proveedor/<tercero>/`) falla con error de storage; mostrar "cargado por Compras" sin enlace.
- Formulario de variante: si se llena presentacion y no "tipo de empaque", la OC sale en kg (A4); hacer obligatorio el nombre de presentacion como unidad de pedido y mostrar la equivalencia antes de guardar (ya se muestra el precio por unidad de compra, bien).
- Comparativo con 8 a 10 columnas por variante: en celular no cabe; agrupar por linea con tarjetas y dejar la tabla para escritorio.
- Sugerencia de compra: mostrar "pendiente" (requerido menos ya en OC) como cantidad por defecto y una alerta cuando lo seleccionado supera lo pendiente (A5).
- Positivo: el portal es claro (pendientes en Inicio, conteos en pestanas, consejos cortos), las variantes con ejemplo de contado y credito se entienden, y "Elegir la mejor de cada linea" ahorra muchos clics.

## Archivos de prueba

Todos en `/tmp/claude-0/-home-claude/c2f15321-1fda-5e67-b6b0-3ef22ed48bfc/scratchpad/`: `base.sql` (comprador, proveedor, requerimiento, solicitud publicada), `t1.sql` (recorrido de tablas interno y proveedor), `t2.sql` (funciones de Compras como proveedor), `t3.sql` (C1, A1, A2, A4, segundo proveedor), `t4.sql` (A3, A2 OC, M1, M4), `t5.sql` (edicion de adjuntos), `t6.sql` (expresiones de storage), `t7.sql` (fila de grupo en `costo_ciclo`), `t8.sql` (A5), `perf1.sql` (A6 y tiempos), `perf2.sql` (M2).
