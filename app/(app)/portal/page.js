'use client';
// M4 · Portal de proveedores: lo que ve el proveedor con su propia cuenta. Solo su informacion: ficha, documentos,
// solicitudes de cotizacion a las que fue invitado (cotiza con variantes), su catalogo y precios (propone cambios),
// sus ordenes de compra (confirma o pide cambio) y su calificacion.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado, Modal, Campo } from '@/components/ui';
import { CATEGORIAS } from '@/components/proveedores';
import { num, cop, fechaCorta, hoyISO } from '@/lib/fmt';

const PAGOS = { contado: 'Contado', anticipo: 'Anticipo', credito: 'Credito' };
const fechaHora = (s) => s ? new Date(s).toLocaleString('es-CO', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '·';

export default function Portal() {
  const { empresaId, empresa, sesion } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const tab = params.get('t') ?? 'inicio';
  const soId = params.get('so');
  const [msg, setMsg] = useState(null);
  const d = useCarga(() => q(sb().rpc('portal_resumen', { p_empresa: empresaId })), [empresaId]);
  const r = d.datos;
  const ir = (t, extra = '') => router.push(`/portal?t=${t}${extra}`);
  if (d.err) return <><Encabezado titulo="Portal de proveedores" /><Falla msg={d.err} /><p className="small muted">Esta pantalla es para las cuentas de proveedores. Si usted es usuario interno, use el menu de Compras.</p></>;
  if (!r) return <Cargando />;
  const t = r.tercero;
  const abiertas = r.solicitudes.filter((s) => s.abierta);
  const porConfirmar = r.ordenes.filter((o) => o.estado === 'enviada');
  const docsMal = r.documentos.filter((x) => x.obligatorio && x.estado !== 'ok');
  return (
    <>
      <Encabezado titulo={t.nombre_comercial ?? t.razon_social} sub={`Portal de proveedores de ${r.empresa.nombre} · ${t.tipo_documento} ${t.numero}${t.dv != null ? `-${t.dv}` : ''} · ${sesion?.user?.email ?? ''}`}>
        <Estado e={t.estado_homologacion} />
        {t.bloqueado && <span className="chip bad" title={t.bloqueo}>bloqueado</span>}
      </Encabezado>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="tabs mb12">
        {[['inicio', 'Inicio'], ['cotizaciones', `Cotizaciones${abiertas.length ? ` (${abiertas.length} abiertas)` : ''}`], ['catalogo', 'Mis productos y precios'], ['ordenes', `Ordenes de compra${porConfirmar.length ? ` (${porConfirmar.length} por confirmar)` : ''}`], ['documentos', `Documentos${docsMal.length ? ` (${docsMal.length})` : ''}`], ['calificacion', 'Calificacion']].map(([k, l]) => <button key={k} className={tab === k ? 'on' : ''} onClick={() => ir(k)}>{l}</button>)}
      </div>

      {tab === 'inicio' && (
        <>
          <div className="grid g4 mb12">
            <div className={`card kpi${abiertas.length ? '' : ''}`}><span className="v">{abiertas.length}</span><span className="l">solicitudes de cotizacion abiertas</span></div>
            <div className={`card kpi${porConfirmar.length ? ' warn' : ''}`}><span className="v">{porConfirmar.length}</span><span className="l">ordenes de compra por confirmar</span></div>
            <div className={`card kpi${docsMal.length ? ' warn' : ''}`}><span className="v">{docsMal.length}</span><span className="l">documentos obligatorios faltantes o vencidos</span></div>
            <div className="card kpi"><span className="v">{t.calificacion != null ? num(t.calificacion, 1) : '·'}</span><span className="l">calificacion vigente (sobre 100)</span></div>
          </div>
          <Consejo titulo="Como funciona este portal" abierto>
            Aqui usted ve solo lo suyo. En <b>Cotizaciones</b> responde las solicitudes de {r.empresa.nombre}: por cada producto puede dar <b>una o varias opciones</b> (por ejemplo, un precio de contado y otro a credito, o dos marcas o empaques distintos) con su ficha tecnica. En <b>Mis productos y precios</b> propone precios nuevos o productos nuevos; Compras los revisa y los acepta. En <b>Ordenes de compra</b> confirma cada OC o pide un cambio de fecha o cantidad. En <b>Documentos</b> mantiene al dia su documentacion legal y sanitaria. Lo que usted envia queda registrado con fecha y hora.
          </Consejo>
          {t.bloqueado && <div className="aviso bad mb12">Su empresa tiene un bloqueo vigente ({t.bloqueo}). Mientras siga, no se le adjudican compras ni se emiten OC nuevas. Comuniquese con Compras.</div>}
          <div className="grid g2">
            <div className="card"><h3 className="m0 mb8">Condiciones registradas</h3><div className="small">Entrega: {t.entrega_en === 'sede' ? 'en el establecimiento' : t.entrega_en === 'ambos' ? 'CEDI o establecimiento' : 'en el CEDI'}{t.lead_time_dias != null ? ` · ${t.lead_time_dias} dias` : ''}<br />Pago: {PAGOS[t.condicion_pago] ?? 'por definir'}{t.plazo_dias ? ` a ${t.plazo_dias} dias` : ''}<br />Categorias: {(t.categorias ?? []).map((c) => CATEGORIAS[c] ?? c).join(', ') || '·'}{t.proyecto_productivo ? <><br /><span className="chip info">Proyecto productivo INPEC</span></> : null}</div></div>
            <div className="card"><h3 className="m0 mb8">Pendientes</h3><ul className="small lista-limpia">{abiertas.map((s) => <li key={s.id}><a onClick={() => ir('cotizaciones', `&so=${s.id}`)} href="#" >{s.codigo} · {s.titulo}</a>: cierra {fechaHora(s.cierre)}{s.oferta_estado === 'enviada' ? ' · oferta enviada' : s.cotizadas ? ` · ${s.cotizadas} de ${s.lineas} cotizadas, sin enviar` : ' · sin cotizar'}</li>)}{porConfirmar.map((o) => <li key={o.id}><a href="#" onClick={() => ir('ordenes')}>{o.codigo}</a>: {cop(o.total)}, entrega {o.fecha_entrega ? fechaCorta(o.fecha_entrega) : 'por definir'} · por confirmar</li>)}{docsMal.map((x) => <li key={x.codigo}>{x.nombre}: {x.estado === 'falta' ? 'falta' : x.estado === 'vencido' ? `vencio ${fechaCorta(x.vence)}` : `vence ${fechaCorta(x.vence)}`}</li>)}{!abiertas.length && !porConfirmar.length && !docsMal.length && <li className="muted">Nada pendiente. Todo al dia.</li>}</ul></div>
          </div>
        </>
      )}

      {tab === 'cotizaciones' && !soId && (
        <div className="card"><Tabla cols={[
          { t: 'Solicitud', r: (s) => <><b>{s.codigo}</b> · {s.titulo}<div className="small muted">{s.lineas} productos · entrega {s.lugar_entrega === 'sede' ? 'en establecimiento' : s.lugar_entrega === 'ambos' ? 'CEDI o establecimiento' : 'en CEDI'}{s.entrega_desde ? ` · ${fechaCorta(s.entrega_desde)}${s.entrega_hasta ? ` a ${fechaCorta(s.entrega_hasta)}` : ''}` : ''}</div></> },
          { t: 'Cierre', r: (s) => <span className={s.abierta ? '' : 'muted'}>{fechaHora(s.cierre)}</span> },
          { t: 'Estado', r: (s) => s.abierta ? <span className="chip ok">abierta</span> : <Estado e={s.estado} /> },
          { t: 'Mi oferta', r: (s) => s.oferta_estado ? <><Estado e={s.oferta_estado} /><div className="small muted">{s.cotizadas} de {s.lineas} lineas{s.adjudicadas ? ` · ${s.adjudicadas} adjudicadas` : ''}</div></> : <span className="muted">sin cotizar</span> },
          { t: '', r: (s) => <button className={`btn btn-xs ${s.abierta && s.oferta_estado !== 'enviada' ? 'btn-p' : ''}`} onClick={() => ir('cotizaciones', `&so=${s.id}`)}>{s.abierta ? 'Cotizar' : 'Ver'}</button> },
        ]} filas={r.solicitudes} vacio="Todavia no lo han invitado a ninguna solicitud de cotizacion." /></div>
      )}
      {tab === 'cotizaciones' && soId && <Cotizar soId={soId} onVolver={() => ir('cotizaciones')} onMsg={setMsg} onCambio={d.recargar} />}

      {tab === 'catalogo' && <Catalogo r={r} empresaId={empresaId} onMsg={setMsg} onCambio={d.recargar} />}

      {tab === 'ordenes' && <Ordenes ordenes={r.ordenes} onMsg={setMsg} onCambio={d.recargar} />}

      {tab === 'documentos' && <Documentos docs={r.documentos} empresaId={empresaId} terceroId={t.id} onMsg={setMsg} onCambio={d.recargar} />}

      {tab === 'calificacion' && (
        <div className="card">
          <p className="small muted">Calificacion por periodo que registra {r.empresa.nombre}: cumplimiento de entregas (35 %), calidad (30 %), precio (20 %) y servicio (15 %). Sobre 100: confiable de 85 en adelante, aceptable de 70 a 84, por debajo de 70 entra en plan de mejora.</p>
          <Tabla cols={[{ t: 'Periodo', r: (e) => <b>{e.periodo}</b> }, { t: 'Cumplimiento', n: true, r: (e) => num(e.cumplimiento, 1) }, { t: 'Calidad', n: true, r: (e) => num(e.calidad, 1) }, { t: 'Precio', n: true, r: (e) => num(e.precio, 1) }, { t: 'Servicio', n: true, r: (e) => num(e.servicio, 1) }, { t: 'Total', n: true, r: (e) => <b>{num(e.total, 1)}</b> }, { t: 'Concepto', r: (e) => <Estado e={e.concepto} /> }]} filas={r.evaluaciones} idKey="periodo" vacio="Todavia no tiene evaluaciones registradas." />
        </div>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Cotizar una solicitud: por linea, mis variantes (agregar, editar, quitar) y enviar la oferta
// ---------------------------------------------------------------------------------------------------------------
function Cotizar({ soId, onVolver, onMsg, onCambio }) {
  const d = useCarga(() => q(sb().rpc('portal_solicitud', { p_solicitud: soId })), [soId]);
  const [form, setForm] = useState(null);   // {linea, variante|null}
  const [enviar, setEnviar] = useState(false);
  const [validez, setValidez] = useState('');
  const [condiciones, setCondiciones] = useState('');
  const [ocupado, setOcupado] = useState(false);
  useEffect(() => { sb().rpc('portal_vista', { p_solicitud: soId }).then(() => {}, () => {}); }, [soId]);
  if (d.err) return <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  const { solicitud: s, oferta: o, lineas } = d.datos;
  const cotizadas = lineas.filter((l) => l.mis_variantes.length).length;
  const recargar = () => { d.recargar(); onCambio?.(); };
  const accion = async (tipo) => {
    setOcupado(true);
    try { await q(sb().rpc('portal_estado_oferta', { p_solicitud: soId, p_accion: tipo, p_validez: validez || null, p_condiciones: condiciones || null })); onMsg?.({ ok: true, t: tipo === 'enviar' ? 'Oferta enviada. Puede seguir ajustandola hasta el cierre; la ultima version es la que vale.' : 'Oferta retirada.' }); setEnviar(false); recargar(); }
    catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); }
  };
  return (
    <>
      <div className="row between wrap gap10 mb12">
        <button className="btn btn-s" onClick={onVolver}>← Cotizaciones</button>
        <div className="row gap6 wrap">
          {s.abierta && cotizadas > 0 && <button className="btn btn-p" onClick={() => setEnviar(true)}>{o?.estado === 'enviada' ? 'Reenviar oferta actualizada' : 'Enviar oferta'}</button>}
          {s.abierta && o && ['borrador', 'enviada'].includes(o.estado) && <button className="btn" disabled={ocupado} onClick={() => accion('retirar')}>Retirar oferta</button>}
        </div>
      </div>
      <div className="card mb12">
        <div className="row between wrap gap10">
          <div><b>{s.codigo}</b> · {s.titulo} {s.abierta ? <span className="chip ok">abierta</span> : <Estado e={s.estado} />}<div className="small muted">{s.empresa} · cierra {fechaHora(s.cierre)} · entrega {s.lugar_entrega === 'sede' ? 'en establecimiento' : s.lugar_entrega === 'ambos' ? 'CEDI o establecimiento' : 'en CEDI'}{s.entrega_desde ? ` del ${fechaCorta(s.entrega_desde)}${s.entrega_hasta ? ` al ${fechaCorta(s.entrega_hasta)}` : ''}` : ''}</div></div>
          <div className="right small">{o ? <>Mi oferta: <Estado e={o.estado} />{o.enviada_en ? <div className="muted">enviada {fechaHora(o.enviada_en)}</div> : null}</> : <span className="muted">sin cotizar</span>}<div className="muted">{cotizadas} de {lineas.length} lineas cotizadas</div></div>
        </div>
        {s.condiciones && <div className="small mt8"><b>Condiciones de la solicitud:</b> {s.condiciones}</div>}
        {!s.permite_variantes && <div className="small warn mt8">Esta solicitud admite una sola opcion por producto.</div>}
      </div>
      <Consejo>Por cada producto puede dar varias opciones: por ejemplo "Caja 12 kg, contado $60.000" y "la misma caja a credito 30 dias $63.000 con 2 % de descuento si pagan a 10 dias". El precio es por la presentacion que indique (sin IVA); el sistema lo convierte a precio por {lineas[0]?.unidad_compra ?? 'unidad de compra'} para comparar. Si no indica presentacion, se entiende precio por {lineas[0]?.unidad_compra ?? 'unidad de compra'} a granel.</Consejo>
      <div className="card">
        <div className="scroll"><table className="t">
          <thead><tr><th>Producto</th><th className="n">Cantidad</th><th>Mis opciones</th><th /></tr></thead>
          <tbody>
            {lineas.map((l) => (
              <tr key={l.id} className={l.mis_variantes.length ? '' : 'sin-cupos'}>
                <td><b>{l.producto}</b><div className="small muted">{CATEGORIAS[l.categoria] ?? l.categoria}{l.especificacion ? ` · ${l.especificacion}` : ''}{l.sede ? ` · entregar en ${l.sede}` : ''}</div></td>
                <td className="n">{num(l.cantidad, 2)} {l.unidad_compra}</td>
                <td>{l.mis_variantes.length === 0 ? <span className="muted small">sin cotizar</span> : l.mis_variantes.map((v) => (
                  <div key={v.id} className="row gap6 wrap small" style={{ marginBottom: 4 }}>
                    <span className="chip">{v.variante}</span>
                    <span><b>{cop(v.precio)}</b> por {v.presentacion ? `${v.presentacion}${v.marca ? ` ${v.marca}` : ''}` : `${l.unidad_compra} granel`} = {cop(v.por_unidad_compra)}/{l.unidad_compra}{v.iva_pct ? ` + IVA ${v.iva_pct} %` : ''} · {PAGOS[v.condicion_pago] ?? 'pago por definir'}{v.plazo_dias ? ` ${v.plazo_dias} d` : ''}{v.descuento_pronto_pago_pct ? ` · ${v.descuento_pronto_pago_pct} % pronto pago a ${v.descuento_pronto_pago_dias ?? '·'} d` : ''}{v.lead_time_dias != null ? ` · entrega ${v.lead_time_dias} d` : ''}{v.ficha_tecnica_id ? ' · ficha adjunta' : ''}</span>
                    {s.abierta && <><button className="btn btn-xs" onClick={() => setForm({ linea: l, variante: v })}>Editar</button><button className="btn btn-xs" onClick={async () => { try { await q(sb().rpc('portal_guardar_variante', { p: { linea_id: l.id, id: v.id, borrar: 'true' } })); recargar(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } }}>Quitar</button></>}
                    {l.adjudicado_a_mi > 0 && <span className="chip ok">adjudicado {num(l.adjudicado_a_mi, 2)} {l.unidad_compra}</span>}
                  </div>))}</td>
                <td>{s.abierta && (s.permite_variantes || !l.mis_variantes.length) && <button className="btn btn-xs btn-p" onClick={() => setForm({ linea: l, variante: null })}>{l.mis_variantes.length ? 'Otra opcion' : 'Cotizar'}</button>}</td>
              </tr>))}
          </tbody>
        </table></div>
      </div>
      {form && <FormVariante linea={form.linea} variante={form.variante} onCerrar={() => setForm(null)} onGuardado={() => { setForm(null); recargar(); }} />}
      {enviar && <Modal titulo="Enviar oferta" onCerrar={() => setEnviar(false)}>
        <p className="small">Va a enviar {cotizadas} de {lineas.length} lineas. Compras vera su oferta al cierre junto con las demas. Puede seguir editandola hasta el cierre.</p>
        <Campo l="Validez de los precios hasta"><input type="date" value={validez} onChange={(e) => setValidez(e.target.value)} /></Campo>
        <Campo l="Observaciones generales"><textarea rows={3} value={condiciones} onChange={(e) => setCondiciones(e.target.value)} placeholder="Ej.: precios sujetos a volumen minimo de 1 tonelada; entrega en vehiculo refrigerado" /></Campo>
        <div className="row end gap6 mt12"><button className="btn" onClick={() => setEnviar(false)}>Cancelar</button><button className="btn btn-p" disabled={ocupado} onClick={() => accion('enviar')}>Enviar</button></div>
      </Modal>}
    </>
  );
}

function FormVariante({ linea, variante, onCerrar, onGuardado }) {
  const v = variante ?? {};
  const [f, setF] = useState({ marca: v.marca ?? '', presentacion: v.presentacion ?? '', contenido: v.contenido ?? '', unidad_empaque: v.unidad_empaque ?? '', precio: v.precio ?? '', iva_pct: v.iva_pct ?? 0, condicion_pago: v.condicion_pago ?? 'credito', plazo_dias: v.plazo_dias ?? 30, descuento_pronto_pago_pct: v.descuento_pronto_pago_pct ?? '', descuento_pronto_pago_dias: v.descuento_pronto_pago_dias ?? '', lead_time_dias: v.lead_time_dias ?? '', minimo_pedido: v.minimo_pedido ?? '', lugar_entrega: v.lugar_entrega ?? '', incluye_flete: v.incluye_flete ?? true, origen: v.origen ?? '', registro_sanitario: v.registro_sanitario ?? '', nota: v.nota ?? '' });
  const [err, setErr] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }));
  const porCompra = f.precio ? (f.contenido ? Number(f.precio) / Number(f.contenido) * linea.factor_compra : Number(f.precio)) : null;
  const usarPres = (p) => setF((x) => ({ ...x, marca: p.marca ?? '', presentacion: p.presentacion ?? '', contenido: p.contenido ?? '', unidad_empaque: p.unidad_empaque ?? '' }));
  const guardar = async () => {
    setOcupado(true); setErr(null);
    try { await q(sb().rpc('portal_guardar_variante', { p: { linea_id: linea.id, id: v.id ?? null, ...f, contenido: f.contenido === '' ? null : f.contenido, plazo_dias: f.plazo_dias === '' ? null : f.plazo_dias, descuento_pronto_pago_pct: f.descuento_pronto_pago_pct === '' ? null : f.descuento_pronto_pago_pct, descuento_pronto_pago_dias: f.descuento_pronto_pago_dias === '' ? null : f.descuento_pronto_pago_dias, lead_time_dias: f.lead_time_dias === '' ? null : f.lead_time_dias, minimo_pedido: f.minimo_pedido === '' ? null : f.minimo_pedido } })); onGuardado(); }
    catch (e) { setErr(e.message); } finally { setOcupado(false); }
  };
  return (
    <Modal titulo={`${variante ? 'Editar opcion' : 'Cotizar'}: ${linea.producto}`} onCerrar={onCerrar} ancho>
      <p className="small muted">Piden {num(linea.cantidad, 2)} {linea.unidad_compra}{linea.especificacion ? ` · ${linea.especificacion}` : ''}. Unidad base: {linea.unidad_base}.</p>
      {linea.mis_presentaciones?.length > 0 && !variante && <div className="small mb8">Sus presentaciones registradas: {linea.mis_presentaciones.map((p, i) => <button key={i} className="btn btn-xs" style={{ marginRight: 4 }} onClick={() => usarPres(p)}>{[p.marca, p.presentacion].filter(Boolean).join(' · ') || 'granel'}</button>)}</div>}
      <div className="grid g4">
        <Campo l="Marca"><input value={f.marca} onChange={set('marca')} placeholder="Diana, Roa…" /></Campo>
        <Campo l="Presentacion" ayuda="Vacio = precio a granel por unidad de compra"><input value={f.presentacion} onChange={set('presentacion')} placeholder="Bulto 50 kg" /></Campo>
        <Campo l={`Contenido (${linea.unidad_base} por empaque)`} req={!!f.presentacion}><input type="number" min={0} value={f.contenido} onChange={set('contenido')} placeholder={linea.unidad_base === 'g' ? '50000' : linea.unidad_base === 'ml' ? '1000' : '12'} /></Campo>
        <Campo l="Tipo de empaque"><input value={f.unidad_empaque} onChange={set('unidad_empaque')} placeholder="bulto, caja, canasta" /></Campo>
      </div>
      <div className="grid g4">
        <Campo l={`Precio por ${f.presentacion || linea.unidad_compra} (sin IVA)`} req><input type="number" min={0} value={f.precio} onChange={set('precio')} /></Campo>
        <Campo l="IVA %"><input type="number" min={0} max={100} value={f.iva_pct} onChange={set('iva_pct')} /></Campo>
        <Campo l="Forma de pago"><select value={f.condicion_pago} onChange={set('condicion_pago')}><option value="contado">Contado</option><option value="anticipo">Anticipo</option><option value="credito">Credito</option></select></Campo>
        <Campo l="Plazo (dias)"><input type="number" min={0} value={f.plazo_dias} onChange={set('plazo_dias')} disabled={f.condicion_pago === 'contado'} /></Campo>
      </div>
      <div className="grid g4">
        <Campo l="Descuento pronto pago %" ayuda="Ej.: 2 % si pagan a 10 dias"><input type="number" min={0} max={100} value={f.descuento_pronto_pago_pct} onChange={set('descuento_pronto_pago_pct')} /></Campo>
        <Campo l="…si pagan a (dias)"><input type="number" min={0} value={f.descuento_pronto_pago_dias} onChange={set('descuento_pronto_pago_dias')} /></Campo>
        <Campo l="Dias de entrega"><input type="number" min={0} value={f.lead_time_dias} onChange={set('lead_time_dias')} /></Campo>
        <Campo l={`Pedido minimo (${linea.unidad_compra})`}><input type="number" min={0} value={f.minimo_pedido} onChange={set('minimo_pedido')} /></Campo>
      </div>
      <div className="grid g4">
        <Campo l="Entrega"><select value={f.lugar_entrega} onChange={set('lugar_entrega')}><option value="">Segun la solicitud</option><option value="cedi">En el CEDI</option><option value="sede">En el establecimiento</option><option value="ambos">Donde pidan</option></select></Campo>
        <Campo l="Flete"><label className="row gap6 small" style={{ marginTop: 8 }}><input type="checkbox" checked={f.incluye_flete} onChange={set('incluye_flete')} /> Precio incluye flete</label></Campo>
        <Campo l="Origen"><select value={f.origen} onChange={set('origen')}><option value="">·</option><option value="nacional">Nacional</option><option value="importado">Importado</option></select></Campo>
        <Campo l="Registro sanitario INVIMA"><input value={f.registro_sanitario} onChange={set('registro_sanitario')} /></Campo>
      </div>
      <Campo l="Nota para el comprador"><input value={f.nota} onChange={set('nota')} placeholder="Ficha tecnica en Documentos; disponible desde el 15" /></Campo>
      {porCompra != null && <div className="aviso info mb12">Equivale a <b>{cop(porCompra)} por {linea.unidad_compra}</b>{f.descuento_pronto_pago_pct ? ` (${cop(porCompra * (1 - Number(f.descuento_pronto_pago_pct) / 100))} con pronto pago)` : ''} · total de la linea {cop(porCompra * linea.cantidad)}</div>}
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || f.precio === '' || (f.presentacion && !f.contenido)} onClick={guardar}>Guardar opcion</button></div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Catalogo del proveedor: sus ofertas con precio vigente, proponer precio nuevo, ofrecer producto nuevo
// ---------------------------------------------------------------------------------------------------------------
function Catalogo({ r, empresaId, onMsg, onCambio }) {
  const [precioDe, setPrecioDe] = useState(null);
  const [nuevo, setNuevo] = useState(false);
  const [filtro, setFiltro] = useState('');
  const filas = useMemo(() => r.ofertas_catalogo.filter((o) => !filtro || `${o.producto} ${o.marca ?? ''}`.toLowerCase().includes(filtro.toLowerCase())), [r.ofertas_catalogo, filtro]);
  return (
    <>
      <Consejo>Estas son sus ofertas registradas con {r.empresa.nombre}. Para cambiar un precio o sus condiciones, use <b>Proponer precio</b>: la propuesta llega a Compras y, si la aceptan, entra a regir desde la fecha que usted indique. Para un producto que todavia no le compran, use <b>Ofrecer producto</b>; queda "propuesto" hasta que lo homologuen.</Consejo>
      <div className="row between wrap gap10 mb12"><input placeholder="Buscar…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 240 }} /><button className="btn btn-p" onClick={() => setNuevo(true)}>Ofrecer producto nuevo</button></div>
      <div className="card"><Tabla cols={[
        { t: 'Producto', r: (o) => <><b>{o.producto}</b><div className="small muted">{[o.marca, o.presentacion ? `${o.presentacion} (${num(o.contenido)} ${o.unidad_base})` : `granel (${o.unidad_compra})`].filter(Boolean).join(' · ')}</div></> },
        { t: 'Homologacion', r: (o) => <><Estado e={o.estado} />{o.preferido && <span className="chip ok" style={{ marginLeft: 6 }}>1a opcion</span>}</> },
        { t: 'Precio vigente', n: true, r: (o) => o.precio != null ? <><b>{cop(o.precio)}</b><div className="small muted">{cop(o.por_compra)}/{o.unidad_compra}{o.iva_pct ? ` + IVA ${o.iva_pct} %` : ''} · desde {fechaCorta(o.desde)}{o.hasta ? ` hasta ${fechaCorta(o.hasta)}` : ''}</div></> : <span className="chip warn">sin precio</span> },
        { t: 'Condiciones', r: (o) => <span className="small">{PAGOS[o.condicion_pago] ?? '·'}{o.plazo_dias ? ` ${o.plazo_dias} d` : ''}</span> },
        { t: 'Propuesta', r: (o) => o.propuesta ? <span className="small"><Estado e={o.propuesta.estado} /> {cop(o.propuesta.precio)} desde {fechaCorta(o.propuesta.desde)}{o.propuesta.nota_resolucion ? <div className="muted">{o.propuesta.nota_resolucion}</div> : null}</span> : '·' },
        { t: '', r: (o) => <button className="btn btn-xs" disabled={o.estado === 'rechazado'} onClick={() => setPrecioDe(o)}>Proponer precio</button> },
      ]} filas={filas} idKey="pp_id" vacio="Todavia no tiene ofertas registradas. Use Ofrecer producto nuevo." /></div>
      {precioDe && <FormPropuesta oferta={precioDe} onCerrar={() => setPrecioDe(null)} onGuardado={() => { setPrecioDe(null); onMsg?.({ ok: true, t: 'Propuesta enviada a Compras.' }); onCambio?.(); }} />}
      {nuevo && <FormProductoNuevo productos={r.productos} empresaId={empresaId} onCerrar={() => setNuevo(false)} onGuardado={() => { setNuevo(false); onMsg?.({ ok: true, t: 'Producto ofrecido. Compras lo revisara para homologarlo.' }); onCambio?.(); }} />}
    </>
  );
}

function FormPropuesta({ oferta, onCerrar, onGuardado }) {
  const [f, setF] = useState({ precio: oferta.precio ?? '', iva_pct: oferta.iva_pct ?? 0, vigente_desde: hoyISO(), vigente_hasta: '', condicion_pago: oferta.condicion_pago ?? '', plazo_dias: oferta.plazo_dias ?? '', descuento_pronto_pago_pct: '', descuento_pronto_pago_dias: '', minimo_pedido: '', nota: '' });
  const [err, setErr] = useState(null); const [ocupado, setOcupado] = useState(false);
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.value }));
  const porCompra = f.precio ? Number(f.precio) / (oferta.contenido ?? oferta.factor_compra) * oferta.factor_compra : null;
  const guardar = async () => { setOcupado(true); setErr(null); try { await q(sb().rpc('portal_proponer_precio', { p: { pp_id: oferta.pp_id, ...f, plazo_dias: f.plazo_dias === '' ? null : f.plazo_dias, descuento_pronto_pago_pct: f.descuento_pronto_pago_pct === '' ? null : f.descuento_pronto_pago_pct, descuento_pronto_pago_dias: f.descuento_pronto_pago_dias === '' ? null : f.descuento_pronto_pago_dias, minimo_pedido: f.minimo_pedido === '' ? null : f.minimo_pedido } })); onGuardado(); } catch (e) { setErr(e.message); } finally { setOcupado(false); } };
  return (
    <Modal titulo={`Proponer precio: ${oferta.producto}`} onCerrar={onCerrar}>
      <p className="small muted">{[oferta.marca, oferta.presentacion].filter(Boolean).join(' · ') || `granel por ${oferta.unidad_compra}`}{oferta.precio != null ? ` · vigente ${cop(oferta.precio)}` : ''}</p>
      <div className="grid g3"><Campo l={`Precio por ${oferta.presentacion || oferta.unidad_compra} (sin IVA)`} req><input type="number" min={0} value={f.precio} onChange={set('precio')} /></Campo><Campo l="IVA %"><input type="number" value={f.iva_pct} onChange={set('iva_pct')} /></Campo><Campo l="Rige desde" req><input type="date" value={f.vigente_desde} onChange={set('vigente_desde')} /></Campo></div>
      <div className="grid g3"><Campo l="Hasta (opcional)"><input type="date" value={f.vigente_hasta} onChange={set('vigente_hasta')} /></Campo><Campo l="Forma de pago"><select value={f.condicion_pago} onChange={set('condicion_pago')}><option value="">Igual que hoy</option><option value="contado">Contado</option><option value="anticipo">Anticipo</option><option value="credito">Credito</option></select></Campo><Campo l="Plazo (dias)"><input type="number" value={f.plazo_dias} onChange={set('plazo_dias')} /></Campo></div>
      <div className="grid g3"><Campo l="Pronto pago %"><input type="number" value={f.descuento_pronto_pago_pct} onChange={set('descuento_pronto_pago_pct')} /></Campo><Campo l="…a (dias)"><input type="number" value={f.descuento_pronto_pago_dias} onChange={set('descuento_pronto_pago_dias')} /></Campo><Campo l={`Minimo (${oferta.unidad_compra})`}><input type="number" value={f.minimo_pedido} onChange={set('minimo_pedido')} /></Campo></div>
      <Campo l="Motivo o nota"><input value={f.nota} onChange={set('nota')} placeholder="Alza del dolar, promocion de temporada…" /></Campo>
      {porCompra != null && <div className="aviso info mb12">Equivale a <b>{cop(porCompra)} por {oferta.unidad_compra}</b>{oferta.por_compra ? ` (hoy ${cop(oferta.por_compra)})` : ''}</div>}
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || f.precio === ''} onClick={guardar}>Enviar propuesta</button></div>
    </Modal>
  );
}

function FormProductoNuevo({ productos, empresaId, onCerrar, onGuardado }) {
  const [f, setF] = useState({ producto_id: '', marca: '', presentacion: '', contenido: '', unidad_empaque: '', precio: '', iva_pct: 0, condicion_pago: 'credito', plazo_dias: 30, lead_time_dias: '', entrega_en: '', origen: '', registro_sanitario: '', codigo_proveedor: '' });
  const [filtro, setFiltro] = useState('');
  const [err, setErr] = useState(null); const [ocupado, setOcupado] = useState(false);
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.value }));
  const lista = useMemo(() => productos.filter((p) => !filtro || p.nombre.toLowerCase().includes(filtro.toLowerCase())), [productos, filtro]);
  const prod = productos.find((p) => p.id === f.producto_id);
  const guardar = async () => { setOcupado(true); setErr(null); try { await q(sb().rpc('portal_ofrecer_producto', { p: { empresa_id: empresaId, ...f, contenido: f.contenido === '' ? null : f.contenido, precio: f.precio === '' ? null : f.precio, lead_time_dias: f.lead_time_dias === '' ? null : f.lead_time_dias } })); onGuardado(); } catch (e) { setErr(e.message); } finally { setOcupado(false); } };
  return (
    <Modal titulo="Ofrecer un producto" onCerrar={onCerrar} ancho>
      <Campo l="Producto del catalogo del comprador" req><input placeholder="Buscar…" value={filtro} onChange={(e) => setFiltro(e.target.value)} /><select size={6} value={f.producto_id} onChange={set('producto_id')}>{lista.map((p) => <option key={p.id} value={p.id}>{p.nombre} · {CATEGORIAS[p.categoria] ?? p.categoria} · por {p.unidad_compra}</option>)}</select></Campo>
      <div className="grid g4"><Campo l="Marca"><input value={f.marca} onChange={set('marca')} /></Campo><Campo l="Presentacion"><input value={f.presentacion} onChange={set('presentacion')} placeholder="Bulto 50 kg" /></Campo><Campo l={`Contenido (${prod?.unidad_base ?? 'unidad base'})`} req={!!f.presentacion}><input type="number" value={f.contenido} onChange={set('contenido')} /></Campo><Campo l="Empaque"><input value={f.unidad_empaque} onChange={set('unidad_empaque')} /></Campo></div>
      <div className="grid g4"><Campo l="Precio (sin IVA)"><input type="number" value={f.precio} onChange={set('precio')} /></Campo><Campo l="IVA %"><input type="number" value={f.iva_pct} onChange={set('iva_pct')} /></Campo><Campo l="Pago"><select value={f.condicion_pago} onChange={set('condicion_pago')}><option value="contado">Contado</option><option value="anticipo">Anticipo</option><option value="credito">Credito</option></select></Campo><Campo l="Plazo (dias)"><input type="number" value={f.plazo_dias} onChange={set('plazo_dias')} /></Campo></div>
      <div className="grid g4"><Campo l="Dias de entrega"><input type="number" value={f.lead_time_dias} onChange={set('lead_time_dias')} /></Campo><Campo l="Entrega"><select value={f.entrega_en} onChange={set('entrega_en')}><option value="">·</option><option value="cedi">CEDI</option><option value="sede">Establecimiento</option><option value="ambos">Ambos</option></select></Campo><Campo l="Origen"><select value={f.origen} onChange={set('origen')}><option value="">·</option><option value="nacional">Nacional</option><option value="importado">Importado</option></select></Campo><Campo l="Registro INVIMA"><input value={f.registro_sanitario} onChange={set('registro_sanitario')} /></Campo></div>
      <p className="small muted">La ficha tecnica y el registro sanitario se suben en la pestaña Documentos (o se envian a Compras); el producto queda "propuesto" hasta que lo homologuen.</p>
      {err && <Falla msg={err} />}
      <div className="row end gap6 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn btn-p" disabled={ocupado || !f.producto_id || (f.presentacion && !f.contenido)} onClick={guardar}>Ofrecer</button></div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Ordenes de compra del proveedor: confirmar o pedir cambio
// ---------------------------------------------------------------------------------------------------------------
function Ordenes({ ordenes, onMsg, onCambio }) {
  const [conf, setConf] = useState(null);  // {oc, acepta}
  const [fecha, setFecha] = useState(''); const [nota, setNota] = useState(''); const [ocupado, setOcupado] = useState(false);
  const [items, setItems] = useState({});
  const verItems = async (oc) => { if (items[oc.id]) { setItems((x) => ({ ...x, [oc.id]: null })); return; } const r = await q(sb().rpc('portal_oc_items', { p_oc: oc.id })); setItems((x) => ({ ...x, [oc.id]: r })); };
  const ejecutar = async () => { setOcupado(true); try { await q(sb().rpc('portal_confirmar_oc', { p_oc: conf.oc.id, p_fecha: fecha || null, p_nota: nota || null, p_acepta: conf.acepta })); onMsg?.({ ok: true, t: conf.acepta ? 'OC confirmada.' : 'Solicitud de cambio enviada a Compras.' }); setConf(null); setFecha(''); setNota(''); onCambio?.(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); } };
  return (
    <>
      <div className="card"><div className="scroll"><table className="t">
        <thead><tr><th>OC</th><th>Entrega</th><th className="n">Total</th><th>Pago</th><th>Estado</th><th /></tr></thead>
        <tbody>{ordenes.map((o) => [
          <tr key={o.id}>
            <td><b>{o.codigo}</b><div className="small muted">emitida {fechaCorta(o.fecha_emision)} · {o.items} lineas{o.notas ? ` · ${o.notas}` : ''}</div></td>
            <td className="small">{o.lugar_entrega === 'sede' ? <>directo en <b>{o.sede}</b></> : <>CEDI <b>{o.sede}</b></>}{o.direccion ? <div className="muted">{o.direccion}{o.ciudad ? `, ${o.ciudad}` : ''}</div> : null}<div>{o.fecha_entrega_confirmada ? `confirmada ${fechaCorta(o.fecha_entrega_confirmada)}` : o.fecha_entrega ? `solicitada ${fechaCorta(o.fecha_entrega)}` : 'fecha por definir'}</div></td>
            <td className="n"><b>{cop(o.total)}</b></td><td className="small">{PAGOS[o.condicion_pago] ?? '·'}{o.plazo_dias ? ` ${o.plazo_dias} d` : ''}</td>
            <td><Estado e={o.estado} />{o.observaciones_proveedor && <div className="small muted">{o.observaciones_proveedor}</div>}</td>
            <td><span className="row gap4 nowrap"><button className="btn btn-xs" onClick={() => verItems(o)}>{items[o.id] ? 'Ocultar' : 'Detalle'}</button>{o.estado === 'enviada' && <><button className="btn btn-xs btn-p" onClick={() => setConf({ oc: o, acepta: true })}>Confirmar</button><button className="btn btn-xs" onClick={() => setConf({ oc: o, acepta: false })}>Pedir cambio</button></>}</span></td>
          </tr>,
          items[o.id] && <tr key={`${o.id}-i`}><td colSpan={6} style={{ background: 'var(--fondo-2)' }}><Tabla cols={[{ t: 'Producto', r: (i) => i.descripcion }, { t: 'Cantidad', n: true, r: (i) => `${num(i.cantidad, i.cantidad % 1 ? 2 : 0)} ${i.unidad_pedido}` }, { t: 'Precio', n: true, r: (i) => cop(i.precio) }, { t: 'IVA', n: true, r: (i) => i.iva_pct ? `${i.iva_pct} %` : '·' }, { t: 'Total', n: true, r: (i) => <b>{cop(i.total)}</b> }, { t: 'Recibido', n: true, r: (i) => i.cantidad_recibida ? num(i.cantidad_recibida, 2) : '·' }]} filas={items[o.id]} idKey="descripcion" /></td></tr>,
        ])}{ordenes.length === 0 && <tr><td colSpan={6} className="vacio">Todavia no tiene ordenes de compra.</td></tr>}</tbody>
      </table></div></div>
      {conf && <Modal titulo={`${conf.acepta ? 'Confirmar' : 'Pedir cambio en'} ${conf.oc.codigo}`} onCerrar={() => setConf(null)}>
        <Campo l={conf.acepta ? 'Fecha de entrega que confirma' : 'Fecha de entrega que propone'}><input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></Campo>
        <Campo l={conf.acepta ? 'Observaciones' : 'Que cambio pide'} req={!conf.acepta}><textarea rows={3} value={nota} onChange={(e) => setNota(e.target.value)} placeholder={conf.acepta ? 'Opcional' : 'Ej.: solo tengo 60 bultos para esa fecha; el resto el viernes'} /></Campo>
        <div className="row end gap6 mt12"><button className="btn" onClick={() => setConf(null)}>Cancelar</button><button className="btn btn-p" disabled={ocupado || (!conf.acepta && !nota.trim())} onClick={ejecutar}>{conf.acepta ? 'Confirmar OC' : 'Enviar solicitud'}</button></div>
      </Modal>}
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Documentos del proveedor: lista de los requeridos con estado; subir o renovar
// ---------------------------------------------------------------------------------------------------------------
function Documentos({ docs, empresaId, terceroId, onMsg, onCambio }) {
  const [sub, setSub] = useState(null);  // doc
  const [fecha, setFecha] = useState(hoyISO()); const [vence, setVence] = useState(''); const [numero, setNumero] = useState(''); const [ocupado, setOcupado] = useState(false); const [err, setErr] = useState(null);
  const ref = useRef(null);
  const limpio = (s) => s.normalize('NFD').replace(/[^\w.\-]+/g, '_');
  const subir = async () => {
    const f = ref.current?.files?.[0];
    if (!f) { setErr('Elija el archivo.'); return; }
    if (f.size > 15 * 1048576) { setErr('El archivo pesa mas de 15 MB.'); return; }
    setOcupado(true); setErr(null);
    try {
      const ruta = `${empresaId}/proveedor/${terceroId}/${Date.now()}_${limpio(f.name)}`;
      const { error } = await sb().storage.from('adjuntos').upload(ruta, f, { contentType: f.type || 'application/octet-stream', upsert: false });
      if (error) throw new Error(error.message);
      await q(sb().rpc('portal_documento', { p_empresa: empresaId, p_codigo: sub.codigo, p_nombre: f.name, p_ruta: ruta, p_tipo_mime: f.type || null, p_tamano: f.size, p_fecha: fecha || null, p_vence: vence || null, p_numero: numero || null }));
      onMsg?.({ ok: true, t: `${sub.nombre} cargado. Queda pendiente hasta que Compras lo valide.` }); setSub(null); setVence(''); setNumero(''); onCambio?.();
    } catch (e) { setErr(e.message); } finally { setOcupado(false); }
  };
  const abrir = async (ruta) => { const { data, error } = await sb().storage.from('adjuntos').createSignedUrl(ruta, 300); if (error) { onMsg?.({ ok: false, t: error.message }); return; } window.open(data.signedUrl, '_blank'); };
  useEffect(() => { if (sub?.vigencia_dias && fecha) { const d = new Date(fecha); d.setDate(d.getDate() + sub.vigencia_dias); setVence(d.toISOString().slice(0, 10)); } }, [sub, fecha]);
  return (
    <>
      <Consejo>Suba cada documento en PDF o imagen (hasta 15 MB). Los obligatorios faltantes o vencidos frenan la homologacion y las adjudicaciones. Cuando renueve uno, suba la version nueva: la fecha de vencimiento se calcula sola si el documento tiene vigencia fija.</Consejo>
      <div className="card"><Tabla cols={[
        { t: 'Documento', r: (x) => <><b>{x.nombre}</b>{x.obligatorio && <span className="chip warn" style={{ marginLeft: 6 }}>obligatorio</span>}{x.ayuda && <div className="small muted">{x.ayuda}</div>}</> },
        { t: 'Estado', r: (x) => <span className={`chip ${x.estado === 'ok' ? 'ok' : x.estado === 'por_vencer' ? 'warn' : 'bad'}`}>{{ ok: 'al dia', por_vencer: 'por vencer', vencido: 'vencido', falta: 'falta' }[x.estado]}</span> },
        { t: 'Por validar', r: (x) => x.pendiente ? <span className={`chip ${x.pendiente.estado === 'propuesto' ? 'warn' : x.pendiente.estado === 'rechazado' ? 'bad' : 'ok'}`} title={x.pendiente.nota ?? ''}>{x.pendiente.estado === 'propuesto' ? `subido ${fechaCorta(x.pendiente.subido_en)}` : x.pendiente.estado}{x.pendiente.estado === 'rechazado' && x.pendiente.nota ? `: ${x.pendiente.nota}` : ''}</span> : '·' },
        { t: 'Fecha', r: (x) => x.fecha ? fechaCorta(x.fecha) : '·' }, { t: 'Vence', r: (x) => x.vence ? fechaCorta(x.vence) : (x.fecha ? 'no vence' : '·') }, { t: 'Numero', r: (x) => x.numero ?? '·' },
        { t: '', r: (x) => <span className="row gap4 nowrap">{x.ruta && <button className="btn btn-xs" onClick={() => abrir(x.ruta)}>Ver</button>}<button className="btn btn-xs btn-p" onClick={() => { setSub(x); setFecha(hoyISO()); }}>{x.fecha ? 'Renovar' : 'Subir'}</button></span> },
      ]} filas={docs} idKey="codigo" /></div>
      {sub && <Modal titulo={`${sub.fecha ? 'Renovar' : 'Subir'}: ${sub.nombre}`} onCerrar={() => setSub(null)}>
        <Campo l="Archivo (PDF o imagen)" req><input type="file" ref={ref} accept=".pdf,image/*" /></Campo>
        <div className="grid g3"><Campo l="Fecha del documento"><input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></Campo><Campo l="Vence"><input type="date" value={vence} onChange={(e) => setVence(e.target.value)} /></Campo><Campo l="Numero o radicado"><input value={numero} onChange={(e) => setNumero(e.target.value)} /></Campo></div>
        {err && <Falla msg={err} />}
        <div className="row end gap6 mt12"><button className="btn" onClick={() => setSub(null)}>Cancelar</button><button className="btn btn-p" disabled={ocupado} onClick={subir}>{ocupado ? 'Subiendo…' : 'Subir'}</button></div>
      </Modal>}
    </>
  );
}
