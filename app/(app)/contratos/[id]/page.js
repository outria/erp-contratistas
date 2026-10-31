'use client';
// M1 · Detalle del contrato: cabezote, agotamiento, anexos (adjuntos por categoria),
// adiciones y prorrogas (con tope del 50 % en SMLMV), unidades de servicio y ejecucion mensual.
import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Kpi, Cargando, Falla, Vacio, Modal, Estado, Barra, Info } from '@/components/ui';
import { Adjuntos } from '@/components/adjuntos';
import { cop, num, fechaCorta } from '@/lib/fmt';
import { MODALIDADES, TIPOS_MODIFICACION, CATEGORIAS_DOC_CONTRATO, SUBTIPOS_SEDE } from '@/lib/catalogos';

export default function DetalleContrato() {
  const { id } = useParams();
  const { empresaId, puede } = useApp();
  const [tab, setTab] = useState('resumen');
  const d = useCarga(() => q(sb().from('v_contratos_resumen').select('*').eq('id', id).single()), [id, empresaId]);
  const c = d.datos;
  if (d.err) return <Falla msg={d.err} />;
  if (!c) return <Cargando />;
  const edita = puede('M1', 'editar');
  return (
    <>
      <Encabezado titulo={`Contrato ${c.numero}`} sub={`${c.entidad_nombre} · ${MODALIDADES[c.modalidad] ?? c.modalidad} · ${c.codigo}`}>
        <Estado e={c.estado} />
        <Link href="/contratos" className="btn">← Contratos</Link>
      </Encabezado>
      <div className="grid g4" style={{ marginBottom: 16 }}>
        <Kpi v={cop(c.valor_total)} l={`valor total (inicial ${cop(c.valor_inicial)})`} />
        <Kpi v={c.agotamiento_pct == null ? '·' : `${num(c.agotamiento_pct, 1)} %`} l={`agotamiento · saldo ${cop(c.saldo)}`} />
        <Kpi v={fechaCorta(c.fecha_fin_vigente)} l={`fin vigente · ${c.dias_restantes} dias`} />
        <Kpi v={c.fecha_agotamiento_estimada ? fechaCorta(c.fecha_agotamiento_estimada) : '·'} l={`plata se acaba (ritmo ${cop(c.ritmo_mensual)}/mes)`} />
      </div>
      <div className="card" style={{ marginBottom: 16 }}>
        <Barra valor={Number(c.facturado)} meta={Number(c.valor_total)} etiqueta="Ejecucion presupuestal" de="del valor total" tope={1} />
        <div style={{ height: 10 }} />
        <Barra valor={Number(c.adiciones_pct_smlmv)} meta={50} etiqueta="Adiciones en SMLMV frente al tope legal del 50 %" de="del tope" tope={1} />
      </div>
      <div className="tabs">
        {[['resumen', 'Cabezote'], ['anexos', 'Anexos y documentos'], ['modificaciones', `Adiciones y prorrogas (${c.n_modificaciones})`], ['sedes', `Unidades de servicio (${c.n_sedes})`], ['ejecucion', 'Ejecucion mensual']].map(([k, t]) =>
          <button key={k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{t}</button>)}
      </div>
      {tab === 'resumen' && <Cabezote c={c} />}
      {tab === 'anexos' && <AnexosContrato c={c} edita={edita} />}
      {tab === 'modificaciones' && <Modificaciones c={c} edita={edita} onCambio={d.recargar} />}
      {tab === 'sedes' && <SedesContrato c={c} edita={edita} onCambio={d.recargar} />}
      {tab === 'ejecucion' && <Ejecucion c={c} edita={edita || puede('M9', 'crear')} onCambio={d.recargar} />}
    </>
  );
}

function Cabezote({ c }) {
  const F = ({ l, v }) => <div><div className="small muted">{l}</div><div>{v ?? '·'}</div></div>;
  return (
    <div className="card stack">
      <F l="Objeto" v={c.objeto} />
      {c.obligaciones && <F l="Obligaciones (resumen)" v={c.obligaciones} />}
      <div className="grid g4">
        <F l="Suscripcion" v={fechaCorta(c.fecha_suscripcion)} />
        <F l="Inicio" v={fechaCorta(c.fecha_inicio)} />
        <F l="Fin inicial" v={fechaCorta(c.fecha_fin_inicial)} />
        <F l="SMLMV del año de firma" v={cop(c.smlmv_suscripcion)} />
        <F l="Dias de atencion" v={c.dias_atencion} />
        <F l="Tiempos de comida" v={c.tiempos_comida} />
        <F l="Menus del ciclo" v={c.n_menus_ciclo} />
        <F l="Ciclo de reparto" v={c.ciclo_reparto} />
        <F l="Interventoria" v={c.interventoria} />
        <F l="Proceso SECOP" v={c.proceso_secop} />
        <F l="Dias para subsanar" v={c.dias_subsanacion} />
        <F l="Incluye IVA" v={c.incluye_iva ? 'Si' : 'No'} />
      </div>
      {c.notas && <F l="Notas" v={c.notas} />}
    </div>
  );
}

function AnexosContrato({ c, edita }) {
  const [cat, setCat] = useState('anexo_nutricional');
  return (
    <div className="stack">
      <div className="card">
        <div className="row between">
          <b>Documentos del contrato por categoria</b>
          <label className="campo" style={{ minWidth: 260 }}>Categoria<select value={cat} onChange={(e) => setCat(e.target.value)}>{Object.entries(CATEGORIAS_DOC_CONTRATO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
        </div>
        <p className="small muted">Suba aqui el contrato firmado, el anexo nutricional (minutas), el de calidad, el de talento humano, las polizas y los oficios. Cada categoria guarda sus archivos aparte para que la interventoria los encuentre rapido.</p>
        <Adjuntos entidad={`contrato_${cat}`} id={c.id} titulo={CATEGORIAS_DOC_CONTRATO[cat]} puedeSubir={edita} />
      </div>
    </div>
  );
}

function Modificaciones({ c, edita, onCambio }) {
  const { empresaId } = useApp();
  const d = useCarga(() => q(sb().from('contrato_modificaciones').select('*').eq('contrato_id', c.id).order('fecha')), [c.id]);
  const [nuevo, setNuevo] = useState(false);
  const [f, setF] = useState({ tipo: 'adicion', numero: '', fecha: '', valor_adicion: '', nueva_fecha_fin: '', dias_suspension: '', motivo: '', excepcion_legal: false });
  const [err, setErr] = useState(null);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value });
  async function guardar(e) {
    e.preventDefault(); setErr(null);
    try {
      await q(sb().from('contrato_modificaciones').insert({ empresa_id: empresaId, contrato_id: c.id, tipo: f.tipo, numero: f.numero || null, fecha: f.fecha,
        valor_adicion: Number(String(f.valor_adicion).replace(/[^\d.]/g, '')) || 0, nueva_fecha_fin: f.nueva_fecha_fin || null, dias_suspension: f.dias_suspension ? Number(f.dias_suspension) : null,
        motivo: f.motivo || null, excepcion_legal: f.excepcion_legal, estado: 'vigente' }));
      setNuevo(false); d.recargar(); onCambio();
    } catch (x) { setErr(x.message); }
  }
  const ms = d.datos ?? [];
  return (
    <div className="card stack">
      <div className="row between"><b>Adiciones, prorrogas y otrosies</b>{edita && <button className="btn btn-p" onClick={() => setNuevo(true)}>＋ Registrar</button>}</div>
      <Falla msg={d.err} />
      {ms.length === 0 ? <Vacio>Sin modificaciones. El contrato esta en su valor y plazo inicial.</Vacio> : (
        <table className="t"><thead><tr><th>Fecha</th><th>Tipo</th><th>Numero</th><th className="n">Valor adicion</th><th>Nueva fecha fin</th><th className="n">Dias susp.</th><th>Motivo</th><th>Soportes</th></tr></thead>
          <tbody>{ms.map((m) => (
            <tr key={m.id}><td>{fechaCorta(m.fecha)}</td><td>{TIPOS_MODIFICACION[m.tipo] ?? m.tipo}{m.excepcion_legal && <span className="chip warn" style={{ marginLeft: 6 }}>excepcion legal</span>}</td><td>{m.numero ?? '·'}</td>
              <td className="n">{m.valor_adicion ? cop(m.valor_adicion) : '·'}</td><td>{m.nueva_fecha_fin ? fechaCorta(m.nueva_fecha_fin) : '·'}</td><td className="n">{m.dias_suspension ?? '·'}</td><td className="small">{m.motivo}</td>
              <td><Adjuntos entidad="contrato_modificacion" id={m.id} titulo="Soporte" puedeSubir={edita} compacto /></td></tr>
          ))}</tbody></table>
      )}
      {nuevo && (
        <Modal titulo="Registrar adicion, prorroga u otrosi" onCerrar={() => setNuevo(false)}>
          <form className="stack" onSubmit={guardar}>
            <div className="grid g2">
              <label className="campo">Tipo<select value={f.tipo} onChange={set('tipo')}>{Object.entries(TIPOS_MODIFICACION).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
              <label className="campo">Numero del documento<input value={f.numero} onChange={set('numero')} placeholder="Otrosi No. 2" /></label>
              <label className="campo">Fecha<input required type="date" value={f.fecha} onChange={set('fecha')} /></label>
              <label className="campo">Valor de la adicion (COP) <Info>Se controla contra el 50 % del valor inicial medido en salarios minimos del año de firma. Si lo supera, el sistema no lo deja pasar salvo excepcion legal con soporte.</Info><input inputMode="numeric" value={f.valor_adicion} onChange={set('valor_adicion')} /></label>
              <label className="campo">Nueva fecha final<input type="date" value={f.nueva_fecha_fin} onChange={set('nueva_fecha_fin')} /></label>
              <label className="campo">Dias de suspension<input type="number" min={0} value={f.dias_suspension} onChange={set('dias_suspension')} /></label>
            </div>
            <label className="campo">Motivo<textarea rows={2} value={f.motivo} onChange={set('motivo')} /></label>
            <label className="campo" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}><input type="checkbox" checked={f.excepcion_legal} onChange={set('excepcion_legal')} /> La entidad justifica superar el tope (adjuntar soporte juridico)</label>
            {err && <div className="aviso bad">{err}</div>}
            <div className="row" style={{ justifyContent: 'flex-end' }}><button type="button" className="btn" onClick={() => setNuevo(false)}>Cancelar</button><button className="btn btn-p">Guardar</button></div>
          </form>
        </Modal>
      )}
    </div>
  );
}

function SedesContrato({ c, edita, onCambio }) {
  const { empresaId } = useApp();
  const d = useCarga(() => q(sb().from('contrato_sedes').select('*, sedes(nombre, subtipo, ciudad, departamento)').eq('contrato_id', c.id).order('creado_en')), [c.id]);
  const libres = useCarga(() => q(sb().from('sedes').select('id, nombre, subtipo, ciudad').eq('empresa_id', empresaId).eq('tipo', 'unidad_servicio').eq('estado', 'activa').order('nombre')), [empresaId]);
  const [nuevo, setNuevo] = useState(false);
  const [f, setF] = useState({ sede_id: '', nueva: '', subtipo: c.modalidad === 'pae' ? 'colegio' : 'eron', ciudad: '', codigo_entidad: '', cupos_referencia: '', firmante_1: '', firmante_2: '' });
  const [err, setErr] = useState(null);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  async function guardar(e) {
    e.preventDefault(); setErr(null);
    try {
      let sede_id = f.sede_id;
      if (!sede_id) {
        if (!f.nueva.trim()) throw new Error('Escoja una sede o escriba el nombre de la nueva.');
        const s = await q(sb().from('sedes').insert({ empresa_id: empresaId, nombre: f.nueva.trim(), tipo: 'unidad_servicio', subtipo: f.subtipo, ciudad: f.ciudad || null }).select('id').single());
        sede_id = s.id;
      }
      await q(sb().from('contrato_sedes').insert({ empresa_id: empresaId, contrato_id: c.id, sede_id, codigo_entidad: f.codigo_entidad || null, cupos_referencia: Number(f.cupos_referencia) || 0, firmante_1: f.firmante_1 || null, firmante_2: f.firmante_2 || null, fecha_inicio: c.fecha_inicio }));
      setNuevo(false); setF({ ...f, sede_id: '', nueva: '', codigo_entidad: '', cupos_referencia: '' }); d.recargar(); libres.recargar(); onCambio();
    } catch (x) { setErr(x.message); }
  }
  const ss = d.datos ?? [];
  const usadas = new Set(ss.map((s) => s.sede_id));
  return (
    <div className="card stack">
      <div className="row between"><b>Unidades de servicio del contrato</b>{edita && <button className="btn btn-p" onClick={() => setNuevo(true)}>＋ Agregar sede</button>}</div>
      <p className="small muted">Carceles, colegios o CDI que atiende este contrato, con sus cupos de referencia y quien firma el cuadro de raciones. Los cupos por fecha, grupo etario y dieta se cargan en Planeacion (F1).</p>
      <Falla msg={d.err} />
      {ss.length === 0 ? <Vacio>Sin sedes todavia.</Vacio> : (
        <table className="t"><thead><tr><th>Sede</th><th>Tipo</th><th>Ciudad</th><th>Codigo entidad</th><th className="n">Cupos ref.</th><th>Firmantes</th><th>Menu confirmado</th><th>Estado</th></tr></thead>
          <tbody>{ss.map((s) => (
            <tr key={s.id}><td><b>{s.sedes?.nombre}</b></td><td className="small">{SUBTIPOS_SEDE[s.sedes?.subtipo] ?? s.sedes?.subtipo ?? '·'}</td><td>{s.sedes?.ciudad ?? '·'}</td><td>{s.codigo_entidad ?? '·'}</td>
              <td className="n">{num(s.cupos_referencia)}</td><td className="small">{[s.firmante_1, s.firmante_2].filter(Boolean).join(' · ') || '·'}</td>
              <td>{s.menu_confirmado ? <span className="chip ok">si</span> : <span className="chip warn">pendiente</span>}</td><td><Estado e={s.estado} /></td></tr>
          ))}</tbody>
          <tfoot><tr><td colSpan={4}>Total</td><td className="n">{num(ss.reduce((a, s) => a + Number(s.cupos_referencia), 0))}</td><td colSpan={3}></td></tr></tfoot></table>
      )}
      {nuevo && (
        <Modal titulo="Agregar unidad de servicio" onCerrar={() => setNuevo(false)}>
          <form className="stack" onSubmit={guardar}>
            <label className="campo">Sede existente<select value={f.sede_id} onChange={set('sede_id')}><option value="">Crear una nueva…</option>{(libres.datos ?? []).filter((s) => !usadas.has(s.id)).map((s) => <option key={s.id} value={s.id}>{s.nombre}{s.ciudad ? ` · ${s.ciudad}` : ''}</option>)}</select></label>
            {!f.sede_id && (
              <div className="grid g3">
                <label className="campo">Nombre de la sede nueva<input value={f.nueva} onChange={set('nueva')} placeholder="EPMSC Cucuta / IE San Jose" /></label>
                <label className="campo">Tipo<select value={f.subtipo} onChange={set('subtipo')}>{Object.entries(SUBTIPOS_SEDE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
                <label className="campo">Ciudad<input value={f.ciudad} onChange={set('ciudad')} /></label>
              </div>
            )}
            <div className="grid g2">
              <label className="campo">Codigo en la entidad (DANE, ERON)<input value={f.codigo_entidad} onChange={set('codigo_entidad')} /></label>
              <label className="campo">Cupos de referencia<input type="number" min={0} value={f.cupos_referencia} onChange={set('cupos_referencia')} /></label>
              <label className="campo">Firmante 1 (jefe de guardia / rector)<input value={f.firmante_1} onChange={set('firmante_1')} /></label>
              <label className="campo">Firmante 2 (director / otro)<input value={f.firmante_2} onChange={set('firmante_2')} /></label>
            </div>
            {err && <div className="aviso bad">{err}</div>}
            <div className="row" style={{ justifyContent: 'flex-end' }}><button type="button" className="btn" onClick={() => setNuevo(false)}>Cancelar</button><button className="btn btn-p">Guardar</button></div>
          </form>
        </Modal>
      )}
    </div>
  );
}

function Ejecucion({ c, edita, onCambio }) {
  const { empresaId } = useApp();
  const d = useCarga(() => q(sb().from('contrato_ejecucion').select('*').eq('contrato_id', c.id).order('periodo')), [c.id]);
  const [f, setF] = useState({ periodo: '', raciones: '', valor_facturado: '', valor_pagado: '', fecha_radicacion: '', fecha_pago: '' });
  const [err, setErr] = useState(null);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  async function guardar(e) {
    e.preventDefault(); setErr(null);
    try {
      const n = (v) => Number(String(v).replace(/[^\d.]/g, '')) || 0;
      await q(sb().from('contrato_ejecucion').upsert({ empresa_id: empresaId, contrato_id: c.id, periodo: f.periodo + '-01', raciones: f.raciones ? Number(f.raciones) : null,
        valor_facturado: n(f.valor_facturado), valor_pagado: n(f.valor_pagado), fecha_radicacion: f.fecha_radicacion || null, fecha_pago: f.fecha_pago || null }, { onConflict: 'contrato_id,periodo' }));
      setF({ periodo: '', raciones: '', valor_facturado: '', valor_pagado: '', fecha_radicacion: '', fecha_pago: '' }); d.recargar(); onCambio();
    } catch (x) { setErr(x.message); }
  }
  const es = d.datos ?? [];
  return (
    <div className="card stack">
      <b>Facturado a la entidad por mes</b>
      <p className="small muted">Mientras llega el modulo de facturacion (F5), contabilidad carga aqui lo facturado y pagado cada mes. Con esto se calcula el agotamiento y la fecha en que se acaba la plata.</p>
      <Falla msg={d.err} />
      {edita && (
        <form className="row" style={{ alignItems: 'flex-end' }} onSubmit={guardar}>
          <label className="campo">Mes<input required type="month" value={f.periodo} onChange={set('periodo')} /></label>
          <label className="campo">Raciones<input type="number" min={0} value={f.raciones} onChange={set('raciones')} /></label>
          <label className="campo">Facturado (COP)<input required inputMode="numeric" value={f.valor_facturado} onChange={set('valor_facturado')} /></label>
          <label className="campo">Pagado (COP)<input inputMode="numeric" value={f.valor_pagado} onChange={set('valor_pagado')} /></label>
          <label className="campo">Radicacion<input type="date" value={f.fecha_radicacion} onChange={set('fecha_radicacion')} /></label>
          <label className="campo">Pago<input type="date" value={f.fecha_pago} onChange={set('fecha_pago')} /></label>
          <button className="btn btn-p">Guardar mes</button>
        </form>
      )}
      {err && <div className="aviso bad">{err}</div>}
      {es.length === 0 ? <Vacio>Sin meses cargados.</Vacio> : (
        <table className="t"><thead><tr><th>Mes</th><th className="n">Raciones</th><th className="n">Facturado</th><th className="n">Pagado</th><th>Radicado</th><th>Pagado el</th><th>Origen</th></tr></thead>
          <tbody>{es.map((x) => <tr key={x.id}><td>{x.periodo.slice(0, 7)}</td><td className="n">{num(x.raciones)}</td><td className="n">{cop(x.valor_facturado)}</td><td className="n">{cop(x.valor_pagado)}</td><td>{x.fecha_radicacion ? fechaCorta(x.fecha_radicacion) : '·'}</td><td>{x.fecha_pago ? fechaCorta(x.fecha_pago) : '·'}</td><td className="small">{x.origen}</td></tr>)}</tbody>
          <tfoot><tr><td>Total</td><td className="n">{num(es.reduce((a, x) => a + Number(x.raciones || 0), 0))}</td><td className="n">{cop(es.reduce((a, x) => a + Number(x.valor_facturado), 0))}</td><td className="n">{cop(es.reduce((a, x) => a + Number(x.valor_pagado), 0))}</td><td colSpan={3}></td></tr></tfoot></table>
      )}
    </div>
  );
}
