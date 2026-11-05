'use client';
// M3 · Ordenes de compra: bandeja de requerimientos aprobados por comprar (con sugerencia de proveedor), lista de OC
// con filtros, detalle con acciones de estado e impresion, y OC manual.
import { useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado } from '@/components/ui';
import { SugerenciaCompra, DetalleOC, FormOC, VistazoOC } from '@/components/ordenes';
import { num, cop, fechaCorta } from '@/lib/fmt';

const ESTADOS_OC = ['borrador', 'aprobada', 'enviada', 'confirmada', 'recibida_parcial', 'cerrada', 'anulada'];

export default function OrdenesCompra() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const id = params.get('id');
  const req = params.get('req');
  const [tab, setTab] = useState(req ? 'req' : 'ocs');
  const [estado, setEstado] = useState('');
  const [filtro, setFiltro] = useState('');
  const [nueva, setNueva] = useState(false);
  const [vistazo, setVistazo] = useState(null);
  const [msg, setMsg] = useState(null);
  const puedeCrear = puede('M3', 'crear');
  const puedeAprobar = puede('M3', 'aprobar');
  const ocs = useCarga(() => q(sb().rpc('ocs_lista', { p_empresa: empresaId, p_estado: estado || null })), [empresaId, estado]);
  const reqs = useCarga(() => q(sb().rpc('requerimientos_compras', { p_empresa: empresaId })), [empresaId]);
  const catalogos = useCarga(() => q(sb().rpc('catalogos_compras', { p_empresa: empresaId })), [empresaId]);
  const proveedores = useCarga(() => q(sb().rpc('proveedores_lista', { p_empresa: empresaId })), [empresaId]);
  const filas = useMemo(() => (ocs.datos ?? []).filter((o) => !filtro || `${o.codigo} ${o.proveedor} ${o.requerimiento ?? ''} ${o.contrato ?? ''}`.toLowerCase().includes(filtro.toLowerCase())), [ocs.datos, filtro]);
  const kpi = useMemo(() => { const l = ocs.datos ?? []; return { borrador: l.filter((o) => o.estado === 'borrador').length, porEnviar: l.filter((o) => o.estado === 'aprobada').length, abiertas: l.filter((o) => ['enviada', 'confirmada', 'recibida_parcial'].includes(o.estado)).length, total: l.filter((o) => !['anulada'].includes(o.estado)).reduce((a, o) => a + Number(o.total), 0) }; }, [ocs.datos]);
  const recargar = () => { ocs.recargar(); reqs.recargar(); };

  return (
    <>
      <Encabezado titulo="Ordenes de compra" sub="Del requerimiento aprobado a la OC: el sistema propone proveedor (homologado, sin bloqueo, mejor precio; el proyecto productivo del INPEC primero en su establecimiento) y lugar de entrega; compras revisa, ajusta, aprueba y envia.">
        <Link href="/precios" className="btn">Master de precios</Link>
        <Link href="/proveedores" className="btn">Proveedores</Link>
        {puedeCrear && !id && <button className="btn btn-p" onClick={() => setNueva(true)}>OC manual</button>}
      </Encabezado>
      {!id && <Consejo>
        <b>Requerimientos</b> muestra lo que planeacion aprobo y falta por comprar. Al abrir uno, cada producto trae su proveedor propuesto: si hay un proyecto productivo del INPEC homologado para ese establecimiento, se le asigna lo de su carcel con entrega directa; el resto va al preferido o al de mejor precio por unidad de compra. Puede cambiar proveedor, cantidad o quitar lineas antes de generar. Se crea una OC por proveedor y lugar de entrega, en <b>borrador</b>: luego se <b>aprueba</b> (Compras: aprobar) y se <b>envia</b>, lo que avisa a bodega. Cuando llegue el portal (M4) el proveedor confirmara desde alli.
      </Consejo>}
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {id ? <DetalleOC id={id} catalogos={catalogos.datos} puedeCrear={puedeCrear} puedeAprobar={puedeAprobar} onRecargar={recargar} onMsg={setMsg} /> : (
        <>
          <div className="grid g4 mb12">
            {[['borrador', 'OC en borrador'], ['porEnviar', 'aprobadas por enviar'], ['abiertas', 'enviadas en curso']].map(([k, l]) => <div key={k} className="card kpi"><span className="v">{num(kpi[k])}</span><span className="l">{l}</span></div>)}
            <div className="card kpi"><span className="v">{cop(kpi.total)}</span><span className="l">total comprado (no anuladas)</span></div>
          </div>
          <div className="tabs mb12">
            <button className={tab === 'req' ? 'on' : ''} onClick={() => setTab('req')}>Requerimientos por comprar{reqs.datos ? ` (${reqs.datos.length})` : ''}</button>
            <button className={tab === 'ocs' ? 'on' : ''} onClick={() => setTab('ocs')}>Ordenes de compra{ocs.datos ? ` (${ocs.datos.length})` : ''}</button>
          </div>
          {tab === 'req' && !req && (
            <div className="card">
              {reqs.err && <Falla msg={reqs.err} />}
              {reqs.cargando && !reqs.datos ? <Cargando /> : <Tabla cols={[
                { t: 'Requerimiento', r: (r) => <><b>{r.codigo}</b>{r.nombre ? ` · ${r.nombre}` : ''}<div className="small muted">Contrato {r.contrato} · {fechaCorta(r.desde)} a {fechaCorta(r.hasta)} · {num(r.raciones)} raciones</div></> },
                { t: 'Estado', r: (r) => <Estado e={r.estado} /> },
                { t: 'Productos', n: true, r: (r) => <>{num(r.productos)}<div className="small muted">{r.productos_con_oc} con OC</div></> },
                { t: 'Avance', r: (r) => { const pct = r.productos ? Math.round(100 * r.productos_con_oc / r.productos) : 0; return <span className={`chip ${pct >= 100 ? 'ok' : pct > 0 ? 'warn' : ''}`}>{pct} % de productos con OC</span>; } },
                { t: 'OC', n: true, r: (r) => <>{num(r.ocs)}<div className="small muted">{cop(r.total_oc)}</div></> },
                { t: '', r: (r) => <button className="btn btn-xs btn-p" onClick={() => router.push(`/ordenes-compra?req=${r.id}`)}>Comprar</button> },
              ]} filas={reqs.datos} vacio="No hay requerimientos aprobados pendientes. Planeacion los aprueba y envia desde Explosion de materiales." />}
            </div>
          )}
          {tab === 'req' && req && (
            <>
              <button className="btn btn-s mb12" onClick={() => router.push('/ordenes-compra')}>← Requerimientos</button>
              <SugerenciaCompra explosionId={req} puedeCrear={puedeCrear} onGenerado={recargar} onMsg={setMsg} />
            </>
          )}
          {tab === 'ocs' && (
            <>
              <div className="row gap10 mb12 wrap">
                <input placeholder="Buscar OC, proveedor, requerimiento…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 260 }} />
                <select value={estado} onChange={(e) => setEstado(e.target.value)}><option value="">Todos los estados</option>{ESTADOS_OC.map((s) => <option key={s} value={s}>{s.replace('_', ' ')}</option>)}</select>
              </div>
              {ocs.err && <Falla msg={ocs.err} />}
              <div className="card">
                {ocs.cargando && !ocs.datos ? <Cargando /> : <Tabla cols={[
                  { t: 'OC', r: (o) => <><b>{o.codigo}</b><div className="small muted">{fechaCorta(o.fecha_emision)}{o.requerimiento ? ` · ${o.requerimiento}` : ' · manual'}{o.contrato ? ` · ${o.contrato}` : ''}</div></> },
                  { t: 'Proveedor', r: (o) => <>{o.proveedor}{o.inpec && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}</> },
                  { t: 'Entrega', r: (o) => <span className="small">{o.lugar_entrega === 'sede' ? <>directo en <b>{o.sede}</b></> : `CEDI${o.sede ? ` · ${o.sede}` : ''}`}{o.fecha_entrega ? <div className="muted">{fechaCorta(o.fecha_entrega)}</div> : null}</span> },
                  { t: 'Lineas', n: true, r: (o) => num(o.items) },
                  { t: 'Total', n: true, r: (o) => <b>{cop(o.total)}</b> },
                  { t: 'Pago', r: (o) => <span className="small">{o.condicion_pago ?? '·'}{o.plazo_dias ? ` ${o.plazo_dias} d` : ''}</span> },
                  { t: 'Recibido', r: (o) => o.recibido_pct != null && o.recibido_pct > 0 ? <span className="chip info">{num(o.recibido_pct)} %</span> : '·' },
                  { t: 'Estado', r: (o) => <Estado e={o.estado} /> },
                  { t: '', r: (o) => <span className="row gap4 nowrap"><button className="btn btn-xs" onClick={() => setVistazo(o)}>Vistazo</button><Link href={`/ordenes-compra?id=${o.id}`} className="btn btn-xs">Abrir</Link></span> },
                ]} filas={filas} vacio="Sin ordenes de compra con ese filtro." />}
              </div>
            </>
          )}
        </>
      )}
      {nueva && <FormOC empresaId={empresaId} proveedores={proveedores.datos} catalogos={catalogos.datos} onCerrar={() => setNueva(false)} onGuardado={(nid) => { setNueva(false); setMsg({ ok: true, t: 'OC creada en borrador. Agregue las lineas.' }); recargar(); router.push(`/ordenes-compra?id=${nid}`); }} />}
      {vistazo && <VistazoOC oc={vistazo} onCerrar={() => setVistazo(null)} />}
    </>
  );
}
