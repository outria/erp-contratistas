'use client';
// M4 (lado Compras) · Solicitudes de cotizacion: crear desde un requerimiento o a mano, invitar proveedores, publicar,
// ver el comparativo normalizado de las ofertas (variantes), adjudicar por linea (puede partirse) y generar las OC.
// Tambien: precios propuestos por los proveedores desde el portal (aceptar o rechazar).
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado, Modal, Campo } from '@/components/ui';
import { CATEGORIAS } from '@/components/proveedores';
import { num, cop, fechaCorta } from '@/lib/fmt';

const PAGOS = { contado: 'Contado', anticipo: 'Anticipo', credito: 'Credito' };
const fechaHora = (s) => s ? new Date(s).toLocaleString('es-CO', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '·';
const aLocal = (d) => { const z = new Date(d); z.setMinutes(z.getMinutes() - z.getTimezoneOffset()); return z.toISOString().slice(0, 16); };

export default function Cotizaciones() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const id = params.get('id');
  const tab = params.get('t') ?? 'solicitudes';
  const [nueva, setNueva] = useState(null);   // null | {} | {explosion_id}
  const [msg, setMsg] = useState(null);
  const [ver, setVer] = useState(0);
  const puedeCrear = puede('M3', 'crear');
  const puedeAprobar = puede('M3', 'aprobar');
  const lista = useCarga(() => q(sb().rpc('solicitudes_lista', { p_empresa: empresaId })), [empresaId]);
  const propuestos = useCarga(() => q(sb().rpc('precios_propuestos_lista', { p_empresa: empresaId })), [empresaId]);
  const pendientes = (propuestos.datos ?? []).filter((p) => p.estado === 'propuesto').length;
  const recargar = () => { lista.recargar(); propuestos.recargar(); };
  return (
    <>
      <Encabezado titulo="Solicitudes de cotizacion" sub="Pida precios a varios proveedores a la vez por el portal, compare las ofertas normalizadas (precio por unidad de compra, condiciones de pago, pronto pago, entrega) y adjudique por linea. Lo adjudicado entra al master de precios y sale como OC en borrador.">
        <Link href="/ordenes-compra" className="btn">Ordenes de compra</Link>
        <Link href="/proveedores" className="btn">Proveedores</Link>
        {puedeCrear && !id && <button className="btn btn-p" onClick={() => setNueva({})}>Nueva solicitud</button>}
      </Encabezado>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {id ? <DetalleSolicitud key={`${id}-${ver}`} id={id} puedeCrear={puedeCrear} puedeAprobar={puedeAprobar} onMsg={setMsg} onRecargar={recargar} onEditar={(s) => setNueva(s)} /> : (
        <>
          <Consejo>Una solicitud nace de un <b>requerimiento aprobado</b> (trae las cantidades; puede limitarse a lo que no tiene precio homologado) o a mano. Se invita a los proveedores homologados de esas categorias (o a los que usted elija) y se publica con fecha y hora de cierre. Cada proveedor entra con su cuenta al portal y cotiza linea por linea, con una o varias opciones (marca, empaque, contado o credito, pronto pago). Al cierre, el <b>comparativo</b> muestra todo normalizado y usted adjudica: una linea puede partirse entre dos proveedores. Los proveedores sin cuenta se crean desde su ficha (Usuarios del portal).</Consejo>
          <div className="tabs mb12">
            <button className={tab === 'solicitudes' ? 'on' : ''} onClick={() => router.push('/cotizaciones')}>Solicitudes{lista.datos ? ` (${lista.datos.length})` : ''}</button>
            <button className={tab === 'propuestos' ? 'on' : ''} onClick={() => router.push('/cotizaciones?t=propuestos')}>Precios propuestos por proveedores{pendientes ? ` (${pendientes} por resolver)` : ''}</button>
          </div>
          {tab === 'solicitudes' && <div className="card">
            {lista.err && <Falla msg={lista.err} />}
            {lista.cargando && !lista.datos ? <Cargando /> : <Tabla cols={[
              { t: 'Solicitud', r: (s) => <><b>{s.codigo}</b> · {s.titulo}<div className="small muted">{s.requerimiento ? `Req. ${s.requerimiento}` : 'manual'}{s.contrato ? ` · ${s.contrato}` : ''} · entrega {s.lugar_entrega}</div></> },
              { t: 'Cierre', r: (s) => <span className={s.abierta ? '' : 'muted'}>{fechaHora(s.cierre)}</span> },
              { t: 'Lineas', n: true, r: (s) => num(s.lineas) }, { t: 'Invitados', n: true, r: (s) => num(s.invitados) },
              { t: 'Ofertas', n: true, r: (s) => <b>{num(s.ofertas)}</b> }, { t: 'Adjudicadas', n: true, r: (s) => s.adjudicadas ? `${s.adjudicadas} / ${s.lineas}` : '·' },
              { t: 'Estado', r: (s) => s.abierta ? <span className="chip ok">abierta</span> : <Estado e={s.estado} /> },
              { t: '', r: (s) => <Link href={`/cotizaciones?id=${s.id}`} className="btn btn-xs">Abrir</Link> },
            ]} filas={lista.datos} vacio="Sin solicitudes. Cree la primera desde un requerimiento aprobado o a mano." />}
          </div>}
          {tab === 'propuestos' && <PreciosPropuestos d={propuestos} puedeAprobar={puedeAprobar} onMsg={setMsg} />}
        </>
      )}
      {nueva && <FormSolicitud empresaId={empresaId} solicitud={nueva.id ? nueva : null} onCerrar={() => setNueva(null)} onGuardado={(nid) => { setNueva(null); setMsg({ ok: true, t: 'Solicitud guardada en borrador. Revise lineas e invitados y publiquela.' }); recargar(); setVer((v) => v + 1); router.push(`/cotizaciones?id=${nid}`); }} />}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------
function FormSolicitud({ empresaId, solicitud, onCerrar, onGuardado }) {
  const s = solicitud ?? {};
  const [f, setF] = useState({ titulo: s.titulo ?? '', explosion_id: s.explosion_id ?? '', lugar_entrega: s.lugar_entrega ?? 'cedi', entrega_desde: s.entrega_desde ?? '', entrega_hasta: s.entrega_hasta ?? '', cierre: s.cierre ? aLocal(s.cierre) : aLocal(new Date(Date.now() + 3 * 86400000)), condiciones: s.condiciones ?? '', notas: s.notas ?? '', solo_sin_precio: true, invitados_modo: 'auto' });
  const [lineas, setLineas] = useState([]);           // manual: [{producto_id, cantidad, especificacion}]
  const [invitados, setInvitados] = useState([]);
  const [err, setErr] = useState(null); const [ocupado, setOcupado] = useState(false);
  const reqs = useCarga(() => q(sb().rpc('requerimientos_compras', { p_empresa: empresaId })), [empresaId]);
  const catalogos = useCarga(() => q(sb().rpc('catalogos_compras', { p_empresa: empresaId })), [empresaId]);
  const provs = useCarga(() => q(sb().rpc('proveedores_lista', { p_empresa: empresaId })), [empresaId]);
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }));
  const [filtroP, setFiltroP] = useState('');
  const productos = useMemo(() => (catalogos.datos?.productos ?? []).filter((p) => filtroP && p.nombre.toLowerCase().includes(filtroP.toLowerCase())).slice(0, 12), [catalogos.datos, filtroP]);
  const guardar = async () => {
    setOcupado(true); setErr(null);
    try {
      const p = { empresa_id: empresaId, id: s.id ?? null, titulo: f.titulo, explosion_id: f.explosion_id || null, lugar_entrega: f.lugar_entrega, entrega_desde: f.entrega_desde || null, entrega_hasta: f.entrega_hasta || null, cierre: new Date(f.cierre).toISOString(), condiciones: f.condiciones || null, notas: f.notas || null, solo_sin_precio: f.solo_sin_precio, lineas: f.explosion_id ? [] : lineas.filter((l) => l.producto_id && l.cantidad > 0), invitados: f.invitados_modo === 'auto' ? [] : invitados };
      if (!f.explosion_id && !p.lineas.length) throw new Error('Agregue al menos una linea o elija un requerimiento.');
      if (f.invitados_modo === 'manual' && !invitados.length) throw new Error('Elija al menos un proveedor.');
      const nid = await q(sb().rpc('guardar_solicitud', { p })); onGuardado(nid);
    } catch (e) { setErr(e.message); } finally { setOcupado(false); }
  };
  return (
    <Modal titulo={s.id ? `Editar ${s.codigo}` : 'Nueva solicitud de cotizacion'} onCerrar={onCerrar} ancho>
      <div className="grid g2">
        <Campo l="Titulo" req><input value={f.titulo} onChange={set('titulo')} placeholder="Abarrotes diciembre · Grupo 15" /></Campo>
        <Campo l="Cierre (fecha y hora)" req><input type="datetime-local" value={f.cierre} onChange={set('cierre')} /></Campo>
      </div>
      {!s.id && <Campo l="Origen de las lineas"><select value={f.explosion_id} onChange={set('explosion_id')}><option value="">A mano (agrego los productos abajo)</option>{(reqs.datos ?? []).map((r) => <option key={r.id} value={r.id}>{r.codigo} · {r.nombre ?? ''} · {r.contrato} · {fechaCorta(r.desde)} a {fechaCorta(r.hasta)} · {r.productos} productos</option>)}</select></Campo>}
      {f.explosion_id && <label className="row gap6 small mb12"><input type="checkbox" checked={f.solo_sin_precio} onChange={set('solo_sin_precio')} /> Solo los productos que hoy no tienen precio homologado vigente (lo demas se compra directo con el master)</label>}
      {!f.explosion_id && !s.id && (
        <div className="card plano mb12">
          <b className="small">Lineas</b>
          <div className="row gap6 mt8 wrap"><input placeholder="Buscar producto…" value={filtroP} onChange={(e) => setFiltroP(e.target.value)} style={{ minWidth: 240 }} />{productos.map((p) => <button key={p.id} className="btn btn-xs" onClick={() => { if (!lineas.find((l) => l.producto_id === p.id)) setLineas((x) => [...x, { producto_id: p.id, nombre: p.nombre, unidad: p.unidad_compra, cantidad: 0, especificacion: '' }]); setFiltroP(''); }}>+ {p.nombre}</button>)}</div>
          {lineas.map((l, i) => <div key={l.producto_id} className="row gap6 mt8 wrap small"><span style={{ minWidth: 220 }}>{l.nombre}</span><input type="number" min={0} value={l.cantidad} onChange={(e) => setLineas((x) => x.map((y, j) => j === i ? { ...y, cantidad: Number(e.target.value) } : y))} style={{ width: 100 }} /> {l.unidad}<input placeholder="Especificacion (calidad, empaque)" value={l.especificacion} onChange={(e) => setLineas((x) => x.map((y, j) => j === i ? { ...y, especificacion: e.target.value } : y))} style={{ minWidth: 220 }} /><button className="btn btn-xs" onClick={() => setLineas((x) => x.filter((_, j) => j !== i))}>Quitar</button></div>)}
        </div>
      )}
      <div className="grid g3">
        <Campo l="Lugar de entrega"><select value={f.lugar_entrega} onChange={set('lugar_entrega')}><option value="cedi">CEDI</option><option value="sede">Directo en establecimientos</option><option value="ambos">Segun la linea</option></select></Campo>
        <Campo l="Entrega desde"><input type="date" value={f.entrega_desde} onChange={set('entrega_desde')} /></Campo>
        <Campo l="Entrega hasta"><input type="date" value={f.entrega_hasta} onChange={set('entrega_hasta')} /></Campo>
      </div>
      <Campo l="Condiciones para el proveedor" ayuda="Lo que debe saber: pago estandar, documentos exigidos, vehiculo, horario de recibo"><textarea rows={2} value={f.condiciones} onChange={set('condiciones')} /></Campo>
      <Campo l="Invitados"><select value={f.invitados_modo} onChange={set('invitados_modo')}><option value="auto">Automatico: homologados activos sin bloqueo de las categorias de las lineas</option><option value="manual">Elegir proveedores</option></select></Campo>
      {f.invitados_modo === 'manual' && <div className="card plano mb12" style={{ maxHeight: 200, overflow: 'auto' }}>{(provs.datos ?? []).filter((t) => t.estado === 'activo').map((t) => <label key={t.id} className="row gap6 small" style={{ marginBottom: 4 }}><input type="checkbox" checked={invitados.includes(t.id)} onChange={(e) => setInvitados((x) => e.target.checked ? [...x, t.id] : x.filter((y) => y !== t.id))} /> {t.nombre_comercial ?? t.razon_social} <span className="muted">· {t.estado_homologacion}{t.bloqueado ? ' · bloqueado' : ''}</span></label>)}</div>}
      <Campo l="Notas internas"><input value={f.notas} onChange={set('notas')} /></Campo>
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || !f.titulo || !f.cierre} onClick={guardar}>Guardar borrador</button></div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------------------------------------------
function DetalleSolicitud({ id, puedeCrear, puedeAprobar, onMsg, onRecargar, onEditar }) {
  const d = useCarga(() => q(sb().rpc('comparar_ofertas', { p_solicitud: id })), [id]);
  const [adj, setAdj] = useState({});        // linea_id -> [{oferta_linea_id, cantidad}]
  const [fechaEntrega, setFechaEntrega] = useState('');
  const [cerrarAl, setCerrarAl] = useState(true);
  const [ocupado, setOcupado] = useState(false);
  const [anular, setAnular] = useState(false); const [nota, setNota] = useState('');
  useEffect(() => { setAdj({}); }, [id]);
  if (d.err) return <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  const { solicitud: s, invitados, lineas, ocs } = d.datos;
  const recargar = () => { d.recargar(); onRecargar?.(); };
  const accion = async (tipo) => { setOcupado(true); try { await q(sb().rpc('estado_solicitud', { p_id: id, p_accion: tipo, p_nota: nota || null })); onMsg?.({ ok: true, t: { publicar: 'Solicitud publicada: los proveedores invitados ya la ven en el portal.', cerrar: 'Solicitud cerrada. Ya puede adjudicar.', reabrir: 'Solicitud reabierta.', anular: 'Solicitud anulada.' }[tipo] }); setAnular(false); recargar(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); } };
  const elegir = (l, v, cant) => setAdj((a) => { const cur = (a[l.id] ?? []).filter((x) => x.oferta_linea_id !== v.id); return { ...a, [l.id]: cant > 0 ? [...cur, { oferta_linea_id: v.id, cantidad: cant, proveedor: v.proveedor }] : cur }; });
  const items = Object.entries(adj).flatMap(([linea_id, xs]) => xs.map((x) => ({ linea_id, oferta_linea_id: x.oferta_linea_id, cantidad: x.cantidad, motivo: 'comparativo ' + s.codigo })));
  const totalAdj = lineas.reduce((t, l) => t + (adj[l.id] ?? []).reduce((a, x) => { const v = l.variantes.find((y) => y.id === x.oferta_linea_id); return a + (v ? x.cantidad * v.costo_efectivo : 0); }, 0), 0);
  const adjudicar = async () => {
    setOcupado(true);
    try { const r = await q(sb().rpc('adjudicar_solicitud', { p_solicitud: id, p_items: items, p_fecha_entrega: fechaEntrega || null, p_cerrar: cerrarAl })); onMsg?.({ ok: true, t: `Adjudicado. ${r.length} OC en borrador: ${r.map((o) => o.codigo).join(', ')}. Los precios adjudicados ya estan en el master.` }); setAdj({}); recargar(); }
    catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); }
  };
  const mejorPor = (l) => l.variantes.filter((v) => !v.bloqueado)[0];
  const puedeAdjudicar = puedeAprobar && ['publicada', 'cerrada'].includes(s.estado);
  return (
    <>
      <div className="row between wrap gap10 mb12">
        <Link href="/cotizaciones" className="btn btn-s">← Solicitudes</Link>
        <div className="row gap6 wrap">
          {s.estado === 'borrador' && puedeCrear && <><button className="btn" onClick={() => onEditar(s)}>Editar</button><button className="btn btn-p" disabled={ocupado} onClick={() => accion('publicar')}>Publicar</button></>}
          {s.estado === 'publicada' && puedeCrear && <button className="btn" disabled={ocupado} onClick={() => accion('cerrar')}>Cerrar ahora</button>}
          {s.estado === 'cerrada' && puedeCrear && <button className="btn" disabled={ocupado} onClick={() => accion('reabrir')}>Reabrir</button>}
          {!['adjudicada', 'anulada'].includes(s.estado) && puedeCrear && <button className="btn btn-d" onClick={() => setAnular(true)}>Anular</button>}
        </div>
      </div>
      <div className="card mb12">
        <div className="row between wrap gap10">
          <div><b>{s.codigo}</b> · {s.titulo} {s.abierta ? <span className="chip ok">abierta</span> : <Estado e={s.estado} />}<div className="small muted">{s.requerimiento ? `Requerimiento ${s.requerimiento} · ` : ''}{s.contrato ? `Contrato ${s.contrato} · ` : ''}cierre {fechaHora(s.cierre)} · entrega {s.lugar_entrega}{s.entrega_desde ? ` del ${fechaCorta(s.entrega_desde)}${s.entrega_hasta ? ` al ${fechaCorta(s.entrega_hasta)}` : ''}` : ''}{s.publicada_en ? ` · publicada ${fechaHora(s.publicada_en)}` : ''}</div>{s.condiciones && <div className="small mt8"><b>Condiciones:</b> {s.condiciones}</div>}</div>
          <div className="right small">{lineas.length} lineas · {invitados.length} invitados · {invitados.filter((i) => ['enviada', 'adjudicada', 'parcial', 'no_adjudicada'].includes(i.oferta_estado)).length} ofertas{ocs.length > 0 && <div>OC: {ocs.map((o) => <Link key={o.id} href={`/ordenes-compra?id=${o.id}`} className="chip" style={{ marginLeft: 4 }}>{o.codigo} <Estado e={o.estado} /></Link>)}</div>}</div>
        </div>
      </div>
      <div className="card mb12">
        <b className="small">Proveedores invitados</b>
        <Tabla cols={[
          { t: 'Proveedor', r: (i) => <>{i.proveedor}{i.inpec && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}{i.bloqueado && <span className="chip bad" style={{ marginLeft: 6 }}>bloqueado</span>}<div className="small muted"><Estado e={i.homologacion} />{i.calificacion != null ? ` · ${num(i.calificacion, 1)} pts` : ''}</div></> },
          { t: 'Portal', r: (i) => i.usuarios ? <span className="chip ok">{i.usuarios} usuario(s)</span> : <Link href={`/proveedores?id=${i.tercero_id}`} className="chip warn">sin usuario · crear</Link> },
          { t: 'Vio la solicitud', r: (i) => i.visto_en ? fechaHora(i.visto_en) : <span className="muted">no</span> },
          { t: 'Oferta', r: (i) => i.oferta_estado ? <><Estado e={i.oferta_estado} /><div className="small muted">{i.lineas_cotizadas} lineas{i.enviada_en ? ` · ${fechaHora(i.enviada_en)}` : ''}{i.validez_hasta ? ` · valida hasta ${fechaCorta(i.validez_hasta)}` : ''}</div></> : <span className="muted">sin oferta</span> },
          { t: 'Observaciones', r: (i) => <span className="small">{i.condiciones ?? '·'}</span> },
        ]} filas={invitados} idKey="tercero_id" />
      </div>
      <div className="card">
        <div className="row between wrap gap6 mb8">
          <div><b>Comparativo por linea</b><div className="small muted">Ordenado por costo efectivo por unidad de compra{d.datos.aprovecha_pronto_pago ? ' (aplica el descuento por pronto pago cuando lo ofrecen)' : ''}. Marque la cantidad que adjudica a cada opcion; una linea puede partirse.</div></div>
          {puedeAdjudicar && <div className="row gap6 wrap"><button className="btn btn-xs" onClick={() => { const a = {}; lineas.forEach((l) => { const v = mejorPor(l); if (v && l.adjudicado < l.cantidad) a[l.id] = [{ oferta_linea_id: v.id, cantidad: l.cantidad - l.adjudicado, proveedor: v.proveedor }]; }); setAdj(a); }}>Elegir la mejor de cada linea</button><label className="row gap4 small">Entrega el <input type="date" value={fechaEntrega} onChange={(e) => setFechaEntrega(e.target.value)} /></label><label className="row gap4 small"><input type="checkbox" checked={cerrarAl} onChange={(e) => setCerrarAl(e.target.checked)} /> cerrar la solicitud al adjudicar</label><button className="btn btn-p" disabled={ocupado || !items.length} onClick={adjudicar}>Adjudicar {items.length} opcion(es) · {cop(totalAdj)}</button></div>}
        </div>
        <div className="scroll"><table className="t t-comparativo">
          <thead><tr><th>Producto</th><th className="n">Cantidad</th><th>Proveedor · opcion</th><th className="n">Precio</th><th className="n">Por unidad</th><th className="n">Efectivo</th><th>Pago</th><th>Entrega</th><th className="n">Total linea</th>{puedeAdjudicar && <th className="n">Adjudicar</th>}</tr></thead>
          <tbody>
            {lineas.map((l) => {
              const vs = l.variantes;
              if (!vs.length) return <tr key={l.id} className="sin-cupos"><td><b>{l.producto}</b><div className="small muted">{CATEGORIAS[l.categoria] ?? l.categoria}{l.especificacion ? ` · ${l.especificacion}` : ''}{l.sede ? ` · ${l.sede}` : ''}</div></td><td className="n">{num(l.cantidad, 2)} {l.unidad_compra}</td><td colSpan={puedeAdjudicar ? 8 : 7} className="muted small">sin ofertas{l.precio_master ? ` · master hoy ${cop(l.precio_master)}/${l.unidad_compra}` : ''}</td></tr>;
              return vs.map((v, i) => {
                const mejor = mejorPor(l)?.id === v.id;
                const cant = (adj[l.id] ?? []).find((x) => x.oferta_linea_id === v.id)?.cantidad ?? '';
                return (
                  <tr key={v.id} className={v.bloqueado ? 'apagado' : ''}>
                    <td>{i === 0 && <><b>{l.producto}</b><div className="small muted">{CATEGORIAS[l.categoria] ?? l.categoria}{l.especificacion ? ` · ${l.especificacion}` : ''}{l.sede ? ` · ${l.sede}` : ''}{l.precio_master ? ` · master ${cop(l.precio_master)}/${l.unidad_compra}` : ''}{l.adjudicado > 0 ? <div className="ok">adjudicado {num(l.adjudicado, 2)} de {num(l.cantidad, 2)}</div> : null}</div></>}</td>
                    <td className="n">{i === 0 && <>{num(l.cantidad, 2)} {l.unidad_compra}</>}</td>
                    <td>{v.proveedor}{v.inpec && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}{mejor && <span className="chip ok" style={{ marginLeft: 6 }}>mejor</span>}{v.bloqueado && <span className="chip bad" style={{ marginLeft: 6 }}>bloqueado</span>}<div className="small muted">op. {v.variante}: {[v.marca, v.presentacion ? `${v.presentacion} (${num(v.contenido)} ${l.unidad_base})` : `granel`].filter(Boolean).join(' · ')}{v.origen ? ` · ${v.origen}` : ''}{v.registro_sanitario ? ` · INVIMA ${v.registro_sanitario}` : ''}{v.nota ? ` · ${v.nota}` : ''}</div></td>
                    <td className="n">{cop(v.precio)}{v.iva_pct ? <div className="small muted">+ IVA {v.iva_pct} %</div> : null}</td>
                    <td className="n">{cop(v.por_unidad_compra)}</td>
                    <td className="n"><b>{cop(v.costo_efectivo)}</b>{v.pp_pct ? <div className="small ok">{v.pp_pct} % a {v.pp_dias} d</div> : null}{l.precio_master ? <div className={`small ${v.costo_efectivo < l.precio_master ? 'ok' : 'bad'}`}>{num(100 * (v.costo_efectivo / l.precio_master - 1), 1)} % vs master</div> : null}</td>
                    <td className="small">{PAGOS[v.condicion_pago] ?? '·'}{v.plazo_dias ? ` ${v.plazo_dias} d` : ''}{v.minimo ? <div className="muted">min. {num(v.minimo)} {l.unidad_compra}</div> : null}</td>
                    <td className="small">{v.lugar_entrega ?? s.lugar_entrega}{v.lead_time != null ? ` · ${v.lead_time} d` : ''}{v.flete === false ? <div className="warn">sin flete</div> : null}</td>
                    <td className="n">{cop(v.total_linea)}</td>
                    {puedeAdjudicar && <td className="n">{v.adjudicada > 0 ? <span className="chip ok">{num(v.adjudicada, 2)}</span> : <input type="number" min={0} max={l.cantidad} step="any" value={cant} disabled={v.bloqueado} placeholder="0" onChange={(e) => elegir(l, v, Number(e.target.value))} style={{ width: 90, textAlign: 'right' }} />}</td>}
                  </tr>);
              });
            })}
          </tbody>
        </table></div>
      </div>
      {anular && <Modal titulo="Anular solicitud" onCerrar={() => setAnular(false)}><Campo l="Motivo" req><textarea rows={3} value={nota} onChange={(e) => setNota(e.target.value)} /></Campo><div className="row end gap6 mt12"><button className="btn" onClick={() => setAnular(false)}>Cancelar</button><button className="btn btn-d" disabled={ocupado || !nota.trim()} onClick={() => accion('anular')}>Anular</button></div></Modal>}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------
function PreciosPropuestos({ d, puedeAprobar, onMsg }) {
  const [res, setRes] = useState(null); const [nota, setNota] = useState(''); const [ocupado, setOcupado] = useState(false);
  const [soloPend, setSoloPend] = useState(true);
  const filas = (d.datos ?? []).filter((p) => !soloPend || p.estado === 'propuesto');
  const resolver = async () => { setOcupado(true); try { await q(sb().rpc('resolver_precio_propuesto', { p_id: res.p.id, p_acepta: res.acepta, p_nota: nota || null })); onMsg?.({ ok: true, t: res.acepta ? 'Precio aceptado: ya rige en el master.' : 'Propuesta rechazada.' }); setRes(null); setNota(''); d.recargar(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); } };
  return (
    <>
      <label className="row gap6 small mb12"><input type="checkbox" checked={soloPend} onChange={(e) => setSoloPend(e.target.checked)} /> Solo pendientes</label>
      <div className="card">{d.err && <Falla msg={d.err} />}<Tabla cols={[
        { t: 'Proveedor · producto', r: (p) => <><b>{p.producto}</b><div className="small muted">{p.proveedor} · {[p.marca, p.presentacion].filter(Boolean).join(' · ') || 'granel'} · {fechaHora(p.creado_en)}</div></> },
        { t: 'Propone', n: true, r: (p) => <><b>{cop(p.precio)}</b><div className="small muted">{cop(p.por_compra)}/{p.unidad_compra}{p.iva_pct ? ` + IVA ${p.iva_pct} %` : ''}</div></> },
        { t: 'Hoy', n: true, r: (p) => p.vigente != null ? <>{cop(p.vigente)}<div className={`small ${p.precio > p.vigente ? 'bad' : 'ok'}`}>{num(100 * (p.precio / p.vigente - 1), 1)} %</div></> : <span className="muted">sin precio</span> },
        { t: 'Mejor del master', n: true, r: (p) => p.mejor_master != null ? <>{cop(p.mejor_master)}/{p.unidad_compra}<div className={`small ${p.por_compra <= p.mejor_master ? 'ok' : 'warn'}`}>{p.por_compra <= p.mejor_master ? 'seria el mejor' : `+${num(100 * (p.por_compra / p.mejor_master - 1), 1)} %`}</div></> : '·' },
        { t: 'Condiciones', r: (p) => <span className="small">desde {fechaCorta(p.desde)}{p.hasta ? ` hasta ${fechaCorta(p.hasta)}` : ''}{p.condicion_pago ? ` · ${PAGOS[p.condicion_pago]}${p.plazo_dias ? ` ${p.plazo_dias} d` : ''}` : ''}{p.pp_pct ? ` · ${p.pp_pct} % pronto pago a ${p.pp_dias} d` : ''}{p.minimo ? ` · min. ${num(p.minimo)}` : ''}{p.nota ? <div className="muted">{p.nota}</div> : null}</span> },
        { t: 'Estado', r: (p) => <Estado e={p.estado} /> },
        { t: '', r: (p) => p.estado === 'propuesto' && puedeAprobar ? <span className="row gap4 nowrap"><button className="btn btn-xs btn-p" onClick={() => setRes({ p, acepta: true })}>Aceptar</button><button className="btn btn-xs" onClick={() => setRes({ p, acepta: false })}>Rechazar</button></span> : null },
      ]} filas={filas} vacio="Sin propuestas de precio." /></div>
      {res && <Modal titulo={`${res.acepta ? 'Aceptar' : 'Rechazar'} propuesta: ${res.p.producto}`} onCerrar={() => setRes(null)}><p className="small">{res.p.proveedor} propone {cop(res.p.precio)} ({cop(res.p.por_compra)}/{res.p.unidad_compra}) desde {fechaCorta(res.p.desde)}.{res.acepta ? ' Al aceptar, el precio entra al master y cierra el anterior el dia antes.' : ''}</p><Campo l="Nota para el proveedor"><input value={nota} onChange={(e) => setNota(e.target.value)} /></Campo><div className="row end gap6 mt12"><button className="btn" onClick={() => setRes(null)}>Cancelar</button><button className={`btn ${res.acepta ? 'btn-p' : 'btn-d'}`} disabled={ocupado} onClick={resolver}>{res.acepta ? 'Aceptar' : 'Rechazar'}</button></div></Modal>}
    </>
  );
}
