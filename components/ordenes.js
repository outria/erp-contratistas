'use client';
// M3 · Ordenes de compra: sugerencia de compra desde un requerimiento aprobado, generacion de OC por proveedor y
// lugar de entrega, detalle e impresion de la OC y OC manual.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { sb, q } from '@/lib/supabase';
import { Cargando, Falla, Tabla, Estado, Modal, Campo, Panel } from '@/components/ui';
import { CATEGORIAS } from '@/components/proveedores';
import { num, cop, fechaCorta, hoyISO } from '@/lib/fmt';

export const MOTIVOS = { 'INPEC prioritario': 'info', preferido: 'ok', 'mejor precio': 'ok', 'unica opcion': 'warn', manual: '' };
const sedeKey = (a) => `${a.tercero_id}|${a.lugar_entrega}|${a.contrato_sede_id ?? ''}`;

// ---------------------------------------------------------------------------------------------------------------
// Sugerencia de compra de un requerimiento: por producto, lo requerido, lo ya en OC y las asignaciones propuestas
// (editables: cantidad, proveedor, lugar). Al generar, agrupa por proveedor + lugar + establecimiento.
// ---------------------------------------------------------------------------------------------------------------
export function SugerenciaCompra({ explosionId, puedeCrear, onGenerado, onMsg }) {
  const [d, setD] = useState(null);
  const [err, setErr] = useState(null);
  const [cargando, setCargando] = useState(true);
  const [sel, setSel] = useState({});         // producto_id -> true
  const [asig, setAsig] = useState({});       // producto_id -> asignaciones editadas
  const [cambiando, setCambiando] = useState(null);  // {producto, idx}
  const [fechaEntrega, setFechaEntrega] = useState('');
  const [soloPendientes, setSoloPendientes] = useState(true);
  const [generando, setGenerando] = useState(false);
  const [cat, setCat] = useState('');
  // el servidor manda el reparto por establecimiento compacto ([id, nombre, base]); aqui se expande a una asignacion por sede
  const expandir = (p) => p.asignaciones.flatMap((a) => a.sedes ? a.sedes.map(([id, nombre, base]) => ({ ...a, sedes: undefined, contrato_sede_id: id, sede: nombre, cantidad_base: base, cantidad: Math.ceil(base / a.contenido) })) : [a]);
  const cargar = () => { setCargando(true); q(sb().rpc('sugerir_compra', { p_explosion: explosionId, p_categoria: cat || null })).then((r) => { (r.productos ?? []).forEach((p) => { p.asignaciones = expandir(p); }); setD(r); setErr(null); const s = {}; const a = {}; (r.productos ?? []).forEach((p) => { if (p.asignaciones.length && p.ya_en_oc_base < p.requerido_base) s[p.producto_id] = true; a[p.producto_id] = p.asignaciones; }); setSel(s); setAsig(a); }).catch((e) => setErr(e.message)).finally(() => setCargando(false)); };
  useEffect(cargar, [explosionId, cat]);  // eslint-disable-line react-hooks/exhaustive-deps
  const productos = useMemo(() => (d?.productos ?? []).filter((p) => !soloPendientes || p.ya_en_oc_base < p.requerido_base), [d, soloPendientes]);
  const resumen = useMemo(() => {
    const porProv = {};
    let total = 0, lineas = 0;
    productos.forEach((p) => { if (!sel[p.producto_id]) return; (asig[p.producto_id] ?? []).forEach((a) => { const k = sedeKey(a); porProv[k] ??= { proveedor: a.proveedor, lugar: a.lugar_entrega, sede: a.sede, total: 0, n: 0, inpec: a.inpec }; const t = a.cantidad * a.precio * (1 + (a.iva_pct ?? 0) / 100); porProv[k].total += t; porProv[k].n += 1; total += t; lineas += 1; }); });
    return { ocs: Object.values(porProv), total, lineas };
  }, [productos, sel, asig]);
  const kpi = useMemo(() => { const l = d?.productos ?? []; return { productos: l.length, conOferta: l.filter((p) => p.n_elegibles > 0).length, sinProveedor: l.filter((p) => p.n_elegibles === 0).length, inpec: l.filter((p) => p.asignaciones.some((a) => a.inpec)).length, comprados: l.filter((p) => p.ya_en_oc_base >= p.requerido_base && p.requerido_base > 0).length }; }, [d]);

  const setCantidad = (pid, idx, v) => setAsig((o) => ({ ...o, [pid]: o[pid].map((a, i) => i === idx ? { ...a, cantidad: Number(v) || 0, cantidad_base: (Number(v) || 0) * a.contenido } : a) }));
  const quitar = (pid, idx) => setAsig((o) => ({ ...o, [pid]: o[pid].filter((_, i) => i !== idx) }));
  const cambiarProveedor = (p, idx, alt) => {
    setAsig((o) => ({ ...o, [p.producto_id]: o[p.producto_id].map((a, i) => i === idx ? { ...a, tercero_id: alt.tercero_id, proveedor: alt.proveedor, pp_id: alt.pp_id, precio_id: alt.precio_id, marca: alt.marca, presentacion: alt.presentacion, unidad_pedido: alt.unidad_pedido, contenido: alt.contenido, precio: alt.precio ?? 0, por_compra: alt.por_compra, iva_pct: alt.iva_pct ?? 0, condicion_pago: alt.condicion_pago, plazo_dias: alt.plazo_dias, lead_time: alt.lead_time, inpec: alt.inpec, motivo: 'manual', cantidad: Math.ceil(a.cantidad_base / alt.contenido), lugar_entrega: alt.entrega_en === 'sede' ? 'sede' : a.lugar_entrega, contrato_sede_id: alt.entrega_en === 'sede' ? (a.contrato_sede_id ?? p.primera_sede?.contrato_sede_id) : (alt.entrega_en === 'cedi' ? null : a.contrato_sede_id), sede: alt.entrega_en === 'sede' ? (a.sede ?? p.primera_sede?.sede) : (alt.entrega_en === 'cedi' ? null : a.sede) } : a) }));
    setCambiando(null);
  };
  const generar = async () => {
    const lineas = [];
    productos.forEach((p) => { if (!sel[p.producto_id]) return; (asig[p.producto_id] ?? []).forEach((a) => { if (a.cantidad > 0) lineas.push({ producto_id: p.producto_id, tercero_id: a.tercero_id, pp_id: a.pp_id, cantidad: a.cantidad, cantidad_base: a.cantidad_base, precio: a.precio, iva_pct: a.iva_pct ?? 0, lugar_entrega: a.lugar_entrega, contrato_sede_id: a.contrato_sede_id, motivo: a.motivo }); }); });
    if (!lineas.length) { onMsg?.({ ok: false, t: 'No hay lineas seleccionadas.' }); return; }
    setGenerando(true);
    try {
      const r = await q(sb().rpc('generar_oc', { p_explosion: explosionId, p_asignaciones: lineas, p_fecha_entrega: fechaEntrega || null, p_notas: null }));
      onMsg?.({ ok: true, t: `${r.length} OC en borrador: ${r.map((o) => o.codigo).join(', ')}. Revise cada una y apruebela.` });
      cargar(); onGenerado?.(r);
    } catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setGenerando(false); }
  };

  if (cargando && !d) return <Cargando />;
  if (err) return <Falla msg={err} />;
  const e = d.explosion;
  return (
    <>
      <div className="card mb12">
        <div className="row between wrap gap10">
          <div><b>{e.codigo}</b>{e.nombre ? ` · ${e.nombre}` : ''} <Estado e={e.estado} /><div className="small muted">Del {fechaCorta(e.desde)} al {fechaCorta(e.hasta)} · {num(e.raciones)} raciones · {kpi.productos} productos</div></div>
          <Link href={`/explosion?id=${e.id}`} className="btn btn-xs">Ver requerimiento</Link>
        </div>
        {d.ordenes.length > 0 && <div className="small mt8">OC de este requerimiento: {d.ordenes.map((o) => <Link key={o.id} href={`/ordenes-compra?id=${o.id}`} className="chip" style={{ marginRight: 6 }}>{o.codigo} · {o.proveedor} · {cop(o.total)} <Estado e={o.estado} /></Link>)}</div>}
      </div>
      <div className="grid g4 mb12">
        {[['conOferta', 'productos con proveedor elegible'], ['sinProveedor', 'sin proveedor homologado con precio'], ['inpec', 'con proyecto productivo INPEC'], ['comprados', 'ya cubiertos con OC']].map(([k, l]) => <div key={k} className={`card kpi${k === 'sinProveedor' && kpi[k] ? ' warn' : ''}`}><span className="v">{num(kpi[k])}</span><span className="l">{l}</span></div>)}
      </div>
      <div className="row gap10 mb12 wrap between">
        <div className="row gap10 wrap">
          <select value={cat} onChange={(e) => setCat(e.target.value)} title="En contratos con muchas sedes, trabajar por categoria es mas rapido"><option value="">Todas las categorias</option>{(d.categorias ?? []).map((c) => <option key={c} value={c}>{CATEGORIAS[c] ?? c}</option>)}</select>
          <label className="row gap6 small"><input type="checkbox" checked={soloPendientes} onChange={(e) => setSoloPendientes(e.target.checked)} /> Solo lo que falta por comprar</label>
          <button className="btn btn-xs" onClick={() => { const s = {}; productos.forEach((p) => { if ((asig[p.producto_id] ?? []).length) s[p.producto_id] = true; }); setSel(s); }}>Marcar todo</button>
          <button className="btn btn-xs" onClick={() => setSel({})}>Desmarcar</button>
        </div>
        {puedeCrear && <div className="row gap10 wrap">
          <label className="row gap4 small">Entrega el <input type="date" value={fechaEntrega} onChange={(e) => setFechaEntrega(e.target.value)} /></label>
          <button className="btn btn-p" disabled={generando || !resumen.lineas} onClick={generar}>{generando ? 'Generando…' : `Generar ${resumen.ocs.length} OC (${resumen.lineas} lineas · ${cop(resumen.total)})`}</button>
        </div>}
      </div>
      {resumen.ocs.length > 0 && <div className="card mb12 small"><b>Se crearan:</b> {resumen.ocs.map((o, i) => <span key={i} className="chip" style={{ marginRight: 6, marginTop: 4 }}>{o.proveedor}{o.inpec ? ' (INPEC)' : ''} · {o.lugar === 'sede' ? `directo en ${o.sede}` : 'al CEDI'} · {o.n} lineas · {cop(o.total)}</span>)}</div>}
      <div className="card">
        <div className="scroll"><table className="t t-oc">
          <thead><tr><th /><th>Producto</th><th className="n">Requerido</th><th className="n">Ya en OC</th><th>Proveedor propuesto</th><th>Entrega</th><th className="n">Cantidad</th><th className="n">Precio</th><th className="n">Total</th><th /></tr></thead>
          <tbody>
            {productos.map((p) => {
              const as = asig[p.producto_id] ?? [];
              const cubierto = p.ya_en_oc_base >= p.requerido_base && p.requerido_base > 0;
              if (!as.length) return (
                <tr key={p.producto_id} className={cubierto ? '' : 'sin-cupos'}>
                  <td /><td><b>{p.producto}</b><div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria}{p.perecedero ? ' · perecedero' : ''}</div></td>
                  <td className="n">{num(p.requerido_compra, 2)} {p.unidad_compra}</td><td className="n">{num(p.ya_en_oc_compra, 2)}</td>
                  <td colSpan={5}>{cubierto ? <span className="chip ok">cubierto</span> : p.n_ofertas === 0 ? <span className="chip bad">sin proveedor que lo ofrezca</span> : p.n_elegibles === 0 ? <span className="chip warn">{p.n_ofertas} oferta(s) sin precio vigente, sin homologar o bloqueadas</span> : <span className="chip warn">sin asignacion</span>}</td>
                  <td>{!cubierto && p.alternativas.length > 0 && puedeCrear && <button className="btn btn-xs" onClick={() => { setAsig((o) => ({ ...o, [p.producto_id]: [{ ...p.alternativas[0], precio: p.alternativas[0].precio ?? 0, cantidad_base: p.requerido_base - p.ya_en_oc_base, cantidad: Math.ceil((p.requerido_base - p.ya_en_oc_base) / p.alternativas[0].contenido), lugar_entrega: p.alternativas[0].entrega_en === 'sede' ? 'sede' : 'cedi', contrato_sede_id: p.alternativas[0].entrega_en === 'sede' ? p.primera_sede?.contrato_sede_id : null, sede: p.alternativas[0].entrega_en === 'sede' ? p.primera_sede?.sede : null, motivo: 'manual' }] })); setSel((s) => ({ ...s, [p.producto_id]: true })); }}>Asignar a mano</button>}</td>
                </tr>);
              return as.map((a, idx) => (
                <tr key={`${p.producto_id}-${idx}`} className={sel[p.producto_id] ? '' : 'apagado'}>
                  <td>{idx === 0 && <input type="checkbox" checked={!!sel[p.producto_id]} onChange={(e) => setSel((s) => ({ ...s, [p.producto_id]: e.target.checked }))} />}</td>
                  <td>{idx === 0 && <><b>{p.producto}</b><div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria}{p.perecedero ? ' · perecedero' : ''} · {p.n_elegibles} de {p.n_ofertas} ofertas elegibles</div></>}</td>
                  <td className="n">{idx === 0 && <>{num(p.requerido_compra, 2)} {p.unidad_compra}{p.ya_en_oc_compra > 0 ? <div className="small muted">pendiente {num(Math.max(p.requerido_compra - p.ya_en_oc_compra, 0), 2)}</div> : null}</>}</td>
                  <td className="n">{idx === 0 && (p.ya_en_oc_compra ? <span className="warn">{num(p.ya_en_oc_compra, 2)}</span> : '·')}</td>
                  <td>{a.proveedor}{a.inpec && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}<div className="small muted">{[a.marca, a.presentacion].filter(Boolean).join(' · ') || `granel (${a.unidad_pedido})`} · <span className={`chip ${MOTIVOS[a.motivo] ?? ''}`}>{a.motivo}</span>{a.condicion_pago ? ` · ${a.condicion_pago}${a.plazo_dias ? ` ${a.plazo_dias} d` : ''}` : ''}{a.lead_time != null ? ` · ${a.lead_time} d` : ''}</div></td>
                  <td className="small">{a.lugar_entrega === 'sede' ? <>directo en <b>{a.sede}</b></> : 'al CEDI'}</td>
                  <td className="n"><input type="number" min={0} step={1} value={a.cantidad} onChange={(e) => setCantidad(p.producto_id, idx, e.target.value)} style={{ width: 80, textAlign: 'right' }} disabled={!puedeCrear} /> <span className="small muted">{a.unidad_pedido}</span><div className="small muted">= {num(a.cantidad * a.contenido / p.factor_compra, 2)} {p.unidad_compra} (pide {num(a.cantidad_base / p.factor_compra, 2)})</div></td>
                  <td className="n">{cop(a.precio)}<div className="small muted">{cop(a.por_compra)} / {p.unidad_compra}{a.iva_pct ? ` · IVA ${a.iva_pct} %` : ''}</div></td>
                  <td className="n"><b>{cop(a.cantidad * a.precio * (1 + (a.iva_pct ?? 0) / 100))}</b></td>
                  <td><span className="row gap4 nowrap">{puedeCrear && p.alternativas.length > 1 && <button className="btn btn-xs" onClick={() => setCambiando({ p, idx })}>Cambiar</button>}{puedeCrear && as.length > 1 && <button className="btn btn-xs" onClick={() => quitar(p.producto_id, idx)}>Quitar</button>}</span></td>
                </tr>));
            })}
            {productos.length === 0 && <tr><td colSpan={10} className="vacio">Todo el requerimiento ya tiene OC.</td></tr>}
          </tbody>
        </table></div>
      </div>
      {cambiando && <Modal titulo={`Proveedor para ${cambiando.p.producto}`} onCerrar={() => setCambiando(null)} ancho>
        <p className="small muted">Todas las ofertas registradas para este producto, ordenadas por precio por {cambiando.p.unidad_compra}. Las bloqueadas, sin homologar o sin precio vigente no se recomiendan, pero compras decide.</p>
        <Tabla cols={[
          { t: 'Proveedor', r: (o) => <>{o.proveedor}{o.inpec && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}{o.preferido && <span className="chip ok" style={{ marginLeft: 6 }}>1a opcion</span>}{o.bloqueado && <span className="chip bad" style={{ marginLeft: 6 }}>bloqueado</span>}</> },
          { t: 'Marca · presentacion', r: (o) => [o.marca, o.presentacion].filter(Boolean).join(' · ') || `granel (${o.unidad_pedido})` },
          { t: 'Homologacion', r: (o) => <Estado e={o.estado} /> },
          { t: 'Precio', n: true, r: (o) => o.sin_precio ? <span className="chip warn">sin precio</span> : <>{cop(o.precio)}<div className="small muted">{cop(o.por_compra)} / {cambiando.p.unidad_compra}</div></> },
          { t: 'Entrega', r: (o) => <span className="small">{o.entrega_en === 'sede' ? 'en sede' : o.entrega_en === 'ambos' ? 'CEDI o sede' : 'CEDI'}{o.lead_time != null ? ` · ${o.lead_time} d` : ''}{o.condicion_pago ? ` · ${o.condicion_pago}${o.plazo_dias ? ` ${o.plazo_dias} d` : ''}` : ''}</span> },
          { t: '', r: (o) => <button className="btn btn-xs btn-p" disabled={o.sin_precio || o.bloqueado} onClick={() => cambiarProveedor(cambiando.p, cambiando.idx, o)}>Elegir</button> },
        ]} filas={cambiando.p.alternativas} idKey="pp_id" />
      </Modal>}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Detalle de una OC: cabecera, proveedor, entrega, lineas (editables en borrador), acciones de estado e impresion
// ---------------------------------------------------------------------------------------------------------------
export function DetalleOC({ id, catalogos, puedeCrear, puedeAprobar, onRecargar, onMsg }) {
  const [d, setD] = useState(null);
  const [err, setErr] = useState(null);
  const [item, setItem] = useState(null);      // null | {} nueva | item
  const [accion, setAccion] = useState(null);  // {tipo}
  const [nota, setNota] = useState('');
  const [fecha, setFecha] = useState('');
  const [ocupado, setOcupado] = useState(false);
  const cargar = () => q(sb().rpc('oc_detalle', { p_id: id })).then((r) => { setD(r); setErr(null); }).catch((e) => setErr(e.message));
  useEffect(() => { setD(null); cargar(); }, [id]);  // eslint-disable-line react-hooks/exhaustive-deps
  if (err) return <Falla msg={err} />;
  if (!d) return <Cargando />;
  const { oc, proveedor, empresa, entrega, requerimiento, contrato, items } = d;
  const borrador = oc.estado === 'borrador';
  const ejecutar = async (tipo) => {
    setOcupado(true);
    try {
      await q(sb().rpc('estado_oc', { p_id: id, p_accion: tipo, p_nota: nota || null, p_fecha: fecha || null }));
      onMsg?.({ ok: true, t: { aprobar: 'OC aprobada.', enviar: 'OC enviada al proveedor y avisada a bodega.', confirmar: 'Confirmacion del proveedor registrada.', cerrar: 'OC cerrada.', anular: 'OC anulada.' }[tipo] });
      setAccion(null); setNota(''); setFecha(''); cargar(); onRecargar?.();
    } catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); }
  };
  const imprimir = () => window.print();
  return (
    <>
      <div className="row between wrap gap10 mb12 no-print">
        <Link href="/ordenes-compra" className="btn btn-s">← Todas las OC</Link>
        <div className="row gap6 wrap">
          <button className="btn" onClick={imprimir}>Imprimir / PDF</button>
          {borrador && puedeAprobar && <button className="btn btn-p" disabled={ocupado || !items.length} onClick={() => ejecutar('aprobar')}>Aprobar</button>}
          {oc.estado === 'aprobada' && puedeAprobar && <button className="btn btn-p" disabled={ocupado} onClick={() => ejecutar('enviar')}>Enviar al proveedor</button>}
          {oc.estado === 'enviada' && puedeCrear && <button className="btn" onClick={() => setAccion('confirmar')}>Registrar confirmacion</button>}
          {['enviada', 'confirmada', 'recibida_parcial'].includes(oc.estado) && puedeAprobar && <button className="btn" onClick={() => setAccion('cerrar')}>Cerrar</button>}
          {!['cerrada', 'anulada'].includes(oc.estado) && (puedeAprobar || (borrador && puedeCrear)) && <button className="btn btn-d" onClick={() => setAccion('anular')}>Anular</button>}
        </div>
      </div>
      <div className="card oc-doc">
        <div className="row between wrap gap10">
          <div><div className="small muted">{empresa.razon_social} · NIT {empresa.nit}{empresa.ciudad ? ` · ${empresa.ciudad}` : ''}</div><h2 className="m0">Orden de compra {oc.codigo}</h2><div className="small">Emitida el {fechaCorta(oc.fecha_emision)}{oc.fecha_entrega ? ` · entrega solicitada el ${fechaCorta(oc.fecha_entrega)}` : ''}{oc.fecha_entrega_confirmada ? ` · confirmada para el ${fechaCorta(oc.fecha_entrega_confirmada)}` : ''}</div></div>
          <div className="right"><Estado e={oc.estado} />{oc.estado === 'anulada' && <div className="small bad">{oc.motivo_anulacion}</div>}<div className="small muted mt8">{requerimiento ? <>Requerimiento <Link href={`/explosion?id=${requerimiento.id}`}>{requerimiento.codigo}</Link> · {fechaCorta(requerimiento.desde)} a {fechaCorta(requerimiento.hasta)}</> : 'OC manual'}{contrato ? <div>Contrato {contrato.numero}{contrato.entidad ? ` · ${contrato.entidad}` : ''}</div> : null}</div></div>
        </div>
        <div className="grid g2 mt12">
          <div className="card plano"><div className="small muted">Proveedor</div><b>{proveedor.nombre_comercial ?? proveedor.razon_social}</b>{proveedor.nombre_comercial && <div className="small">{proveedor.razon_social}</div>}<div className="small">{proveedor.tipo_documento} {proveedor.numero}{proveedor.dv != null ? `-${proveedor.dv}` : ''}{proveedor.proyecto_productivo ? ' · Proyecto productivo INPEC' : ''}</div><div className="small muted">{[proveedor.direccion, proveedor.ciudad].filter(Boolean).join(', ')}{proveedor.telefono ? ` · ${proveedor.telefono}` : ''}{proveedor.correo ? ` · ${proveedor.correo}` : ''}</div>{proveedor.bloqueado && <span className="chip bad">bloqueado</span>}<div className="small mt8">Pago: {oc.condicion_pago ?? proveedor.condicion_pago ?? 'por definir'}{oc.plazo_dias ? ` a ${oc.plazo_dias} dias` : ''}</div></div>
          <div className="card plano"><div className="small muted">Entregar en</div><b>{entrega?.sede ?? (oc.lugar_entrega === 'sede' ? 'establecimiento' : 'CEDI')}</b> <span className="chip">{oc.lugar_entrega === 'sede' ? 'directo en sede' : 'CEDI'}</span><div className="small muted">{[entrega?.direccion, entrega?.ciudad].filter(Boolean).join(', ')}{entrega?.responsable ? ` · recibe ${entrega.responsable}` : ''}{entrega?.telefono ? ` · ${entrega.telefono}` : ''}</div>{oc.notas && <div className="small mt8"><b>Notas:</b> {oc.notas}</div>}{oc.observaciones_proveedor && <div className="small mt8"><b>Proveedor:</b> {oc.observaciones_proveedor}</div>}</div>
        </div>
        <div className="mt12">
          <div className="row between mb8 no-print"><b>Lineas ({items.length})</b>{borrador && puedeCrear && <button className="btn btn-xs" onClick={() => setItem({})}>Agregar linea</button>}</div>
          <Tabla cols={[
            { t: 'Producto', r: (i) => <><b>{i.descripcion}</b><div className="small muted">{i.codigo}{i.motivo && i.motivo !== 'manual' ? ` · ${i.motivo}` : ''}{i.notas ? ` · ${i.notas}` : ''}</div></> },
            { t: 'Cantidad', n: true, r: (i) => <>{num(i.cantidad, i.cantidad % 1 ? 2 : 0)} {i.unidad_pedido}<div className="small muted">= {num(i.cantidad_compra, 2)} {i.unidad_compra}{i.requerida_base != null ? ` (req. ${num(i.requerida_base / i.factor_compra, 2)})` : ''}</div></> },
            { t: 'Precio unit.', n: true, r: (i) => cop(i.precio) }, { t: 'IVA', n: true, r: (i) => i.iva_pct ? `${num(i.iva_pct)} %` : '·' },
            { t: 'Subtotal', n: true, r: (i) => cop(i.subtotal) }, { t: 'Total', n: true, r: (i) => <b>{cop(i.total)}</b> },
            { t: 'Recibido', n: true, r: (i) => i.cantidad_recibida ? `${num(i.cantidad_recibida, 2)} (${num(100 * i.cantidad_recibida / i.cantidad)} %)` : '·' },
            ...(borrador && puedeCrear ? [{ t: '', r: (i) => <span className="row gap4 nowrap no-print"><button className="btn btn-xs" onClick={() => setItem(i)}>Editar</button><button className="btn btn-xs" onClick={async () => { try { await q(sb().rpc('guardar_oc_item', { p: { id: i.id, oc_id: id, borrar: 'true' } })); cargar(); onRecargar?.(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } }}>Quitar</button></span> }] : []),
          ]} filas={items} vacio="Sin lineas. Agregue productos o genere la OC desde un requerimiento." />
          <div className="row end gap10 mt12 oc-totales"><div><div className="small muted">Subtotal</div><b>{cop(oc.subtotal)}</b></div><div><div className="small muted">IVA</div><b>{cop(oc.iva)}</b></div><div><div className="small muted">Total</div><b style={{ fontSize: 20 }}>{cop(oc.total)}</b></div></div>
        </div>
        <div className="small muted mt12 print-only">Generada en Supply ERP · {oc.aprobada_por_nombre ? `Aprobada por ${oc.aprobada_por_nombre}` : 'Borrador, sin aprobar'} · Esta OC no tiene validez sin aprobacion de compras.</div>
      </div>
      {item && <FormItem ocId={id} item={item.id ? item : null} catalogos={catalogos} proveedorId={proveedor.id} onCerrar={() => setItem(null)} onGuardado={() => { setItem(null); cargar(); onRecargar?.(); }} />}
      {accion && <Modal titulo={{ confirmar: 'Confirmacion del proveedor', cerrar: 'Cerrar OC', anular: 'Anular OC' }[accion]} onCerrar={() => setAccion(null)}>
        {accion === 'confirmar' && <Campo l="Fecha de entrega confirmada"><input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></Campo>}
        <Campo l={accion === 'anular' ? 'Motivo' : 'Nota'} req={accion === 'anular'}><textarea rows={3} value={nota} onChange={(e) => setNota(e.target.value)} /></Campo>
        {accion === 'cerrar' && <p className="small muted">Cierra la OC aunque falte recepcion (saldo no entregado). Si hay recepciones, quedan registradas.</p>}
        <div className="row end gap6 mt12"><button className="btn" onClick={() => setAccion(null)}>Cancelar</button><button className={`btn ${accion === 'anular' ? 'btn-d' : 'btn-p'}`} disabled={ocupado || (accion === 'anular' && !nota.trim())} onClick={() => ejecutar(accion)}>{accion === 'confirmar' ? 'Registrar' : accion === 'cerrar' ? 'Cerrar OC' : 'Anular'}</button></div>
      </Modal>}
    </>
  );
}

// linea de OC manual: producto (del catalogo), oferta del proveedor si existe, cantidad, precio
function FormItem({ ocId, item, catalogos, proveedorId, onCerrar, onGuardado }) {
  const [f, setF] = useState({ producto_id: '', pp_id: '', cantidad: item?.cantidad ?? 1, precio: item?.precio ?? 0, iva_pct: item?.iva_pct ?? 0, notas: item?.notas ?? '' });
  const [ofertas, setOfertas] = useState([]);
  const [err, setErr] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [filtro, setFiltro] = useState('');
  useEffect(() => {
    if (!proveedorId || item) return;
    q(sb().rpc('proveedor_ficha', { p_tercero: proveedorId })).then((r) => setOfertas((r.productos ?? []).filter((o) => o.estado !== 'rechazado'))).catch(() => setOfertas([]));
  }, [proveedorId, item]);
  const productos = useMemo(() => (catalogos?.productos ?? []).filter((p) => !filtro || p.nombre.toLowerCase().includes(filtro.toLowerCase())), [catalogos, filtro]);
  const ofertasProd = ofertas.filter((o) => o.producto_id === f.producto_id);
  const elegirOferta = (pp) => { const o = ofertas.find((x) => x.id === pp); setF((v) => ({ ...v, pp_id: pp, precio: o?.precio ?? v.precio, iva_pct: o?.iva_pct ?? v.iva_pct })); };
  const guardar = async () => {
    setOcupado(true); setErr(null);
    try { await q(sb().rpc('guardar_oc_item', { p: { id: item?.id ?? null, oc_id: ocId, producto_id: f.producto_id || null, pp_id: f.pp_id || null, cantidad: f.cantidad, precio: f.precio, iva_pct: f.iva_pct, notas: f.notas || null } })); onGuardado(); }
    catch (e) { setErr(e.message); } finally { setOcupado(false); }
  };
  return (
    <Modal titulo={item ? `Editar: ${item.descripcion}` : 'Agregar linea'} onCerrar={onCerrar}>
      {!item && <>
        <Campo l="Producto" req><input placeholder="Buscar…" value={filtro} onChange={(e) => setFiltro(e.target.value)} /><select value={f.producto_id} onChange={(e) => setF((v) => ({ ...v, producto_id: e.target.value, pp_id: '' }))} size={6}>{productos.map((p) => <option key={p.id} value={p.id}>{p.nombre} ({p.unidad_compra})</option>)}</select></Campo>
        {f.producto_id && <Campo l="Oferta del proveedor" ayuda="Si el proveedor tiene esta oferta registrada (marca, presentacion y precio), la linea toma su presentacion y precio. Si no, se pide a granel por unidad de compra."><select value={f.pp_id} onChange={(e) => elegirOferta(e.target.value)}><option value="">Granel, sin oferta registrada</option>{ofertasProd.map((o) => <option key={o.id} value={o.id}>{[o.marca, o.presentacion].filter(Boolean).join(' · ') || 'granel'}{o.precio != null ? ` · ${cop(o.precio)}` : ' · sin precio'} · {o.estado}</option>)}</select></Campo>}
      </>}
      <div className="grid g3">
        <Campo l="Cantidad" req><input type="number" min={0.01} step={1} value={f.cantidad} onChange={(e) => setF((v) => ({ ...v, cantidad: Number(e.target.value) }))} /></Campo>
        <Campo l="Precio unitario (sin IVA)"><input type="number" min={0} value={f.precio} onChange={(e) => setF((v) => ({ ...v, precio: Number(e.target.value) }))} /></Campo>
        <Campo l="IVA %"><input type="number" min={0} max={100} value={f.iva_pct} onChange={(e) => setF((v) => ({ ...v, iva_pct: Number(e.target.value) }))} /></Campo>
      </div>
      <Campo l="Nota"><input value={f.notas} onChange={(e) => setF((v) => ({ ...v, notas: e.target.value }))} /></Campo>
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || (!item && !f.producto_id) || !(f.cantidad > 0)} onClick={guardar}>Guardar</button></div>
    </Modal>
  );
}

// OC manual: proveedor, lugar de entrega, fecha, notas. Luego se agregan lineas en el detalle.
export function FormOC({ empresaId, proveedores, catalogos, onCerrar, onGuardado }) {
  const [f, setF] = useState({ tercero_id: '', lugar_entrega: 'cedi', contrato_sede_id: '', fecha_entrega: '', condicion_pago: '', plazo_dias: '', notas: '', notas_internas: '' });
  const [err, setErr] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const prov = (proveedores ?? []).find((t) => t.id === f.tercero_id);
  useEffect(() => { if (prov) setF((v) => ({ ...v, condicion_pago: prov.condicion_pago ?? '', plazo_dias: prov.plazo_dias ?? '', lugar_entrega: prov.entrega_en === 'sede' ? 'sede' : 'cedi' })); }, [prov?.id]);  // eslint-disable-line react-hooks/exhaustive-deps
  const guardar = async () => {
    setOcupado(true); setErr(null);
    try { const id = await q(sb().rpc('guardar_oc', { p: { empresa_id: empresaId, ...f, contrato_sede_id: f.lugar_entrega === 'sede' ? f.contrato_sede_id : null, plazo_dias: f.plazo_dias === '' ? null : Number(f.plazo_dias) } })); onGuardado(id); }
    catch (e) { setErr(e.message); } finally { setOcupado(false); }
  };
  return (
    <Modal titulo="Nueva orden de compra manual" onCerrar={onCerrar}>
      <p className="small muted">Para compras que no salen de un requerimiento (urgencias, reposiciones, servicios). Lo normal es generar las OC desde la pestaña Requerimientos.</p>
      <Campo l="Proveedor" req><select value={f.tercero_id} onChange={(e) => setF((v) => ({ ...v, tercero_id: e.target.value }))}><option value="">Elija…</option>{(proveedores ?? []).filter((t) => t.estado === 'activo').map((t) => <option key={t.id} value={t.id} disabled={t.bloqueado}>{t.nombre_comercial ?? t.razon_social}{t.bloqueado ? ' (bloqueado)' : t.estado_homologacion !== 'homologado' ? ` (${t.estado_homologacion})` : ''}</option>)}</select></Campo>
      <div className="grid g2">
        <Campo l="Entregar en"><select value={f.lugar_entrega} onChange={(e) => setF((v) => ({ ...v, lugar_entrega: e.target.value }))}><option value="cedi">CEDI / bodega</option><option value="sede">Directo en el establecimiento</option></select></Campo>
        {f.lugar_entrega === 'sede' && <Campo l="Establecimiento" req><select value={f.contrato_sede_id} onChange={(e) => setF((v) => ({ ...v, contrato_sede_id: e.target.value }))}><option value="">Elija…</option>{(catalogos?.establecimientos ?? []).map((s) => <option key={s.id} value={s.id}>{s.nombre} · {s.contrato}</option>)}</select></Campo>}
      </div>
      <div className="grid g3">
        <Campo l="Fecha de entrega"><input type="date" value={f.fecha_entrega} onChange={(e) => setF((v) => ({ ...v, fecha_entrega: e.target.value }))} /></Campo>
        <Campo l="Pago"><select value={f.condicion_pago} onChange={(e) => setF((v) => ({ ...v, condicion_pago: e.target.value }))}><option value="">Segun proveedor</option><option value="contado">Contado</option><option value="anticipo">Anticipo</option><option value="credito">Credito</option></select></Campo>
        <Campo l="Plazo (dias)"><input type="number" min={0} value={f.plazo_dias} onChange={(e) => setF((v) => ({ ...v, plazo_dias: e.target.value }))} /></Campo>
      </div>
      <Campo l="Notas para el proveedor"><textarea rows={2} value={f.notas} onChange={(e) => setF((v) => ({ ...v, notas: e.target.value }))} /></Campo>
      <Campo l="Notas internas"><input value={f.notas_internas} onChange={(e) => setF((v) => ({ ...v, notas_internas: e.target.value }))} /></Campo>
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || !f.tercero_id || (f.lugar_entrega === 'sede' && !f.contrato_sede_id)} onClick={guardar}>Crear borrador</button></div>
    </Modal>
  );
}

// Panel de recepcion/avance en la lista: reusa Panel para un vistazo rapido sin salir de la lista
export function VistazoOC({ oc, onCerrar }) {
  return (
    <Panel titulo={oc.codigo} sub={`${oc.proveedor} · ${cop(oc.total)}`} onCerrar={onCerrar} acciones={<Link href={`/ordenes-compra?id=${oc.id}`} className="btn btn-xs btn-p">Abrir</Link>}>
      <div className="small">Estado: <Estado e={oc.estado} /></div>
      <div className="small mt8">Entrega: {oc.lugar_entrega === 'sede' ? `directo en ${oc.sede ?? 'sede'}` : `CEDI (${oc.sede ?? ''})`}{oc.fecha_entrega ? ` · ${fechaCorta(oc.fecha_entrega)}` : ''}</div>
      <div className="small mt8">{oc.items} lineas{oc.recibido_pct != null ? ` · recibido ${num(oc.recibido_pct)} %` : ''}</div>
      {oc.requerimiento && <div className="small mt8">Requerimiento {oc.requerimiento}{oc.contrato ? ` · contrato ${oc.contrato}` : ''}</div>}
    </Panel>
  );
}
