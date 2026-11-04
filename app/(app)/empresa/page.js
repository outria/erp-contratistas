'use client';
// M0 · Empresa y parametros: datos de la empresa, sedes (CEDI, bodegas, unidades de servicio),
// parametros del dominio (tope de adiciones, dias para aceptar factura, meta Ley 2046, ciclo de reparto...).
import { useState } from 'react';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Vacio, Modal, Estado, Consejo } from '@/components/ui';
import { fechaCorta } from '@/lib/fmt';
import { TIPOS_SEDE, SUBTIPOS_SEDE } from '@/lib/catalogos';

export default function Empresa() {
  const { empresaId, empresa, puede } = useApp();
  const [tab, setTab] = useState('datos');
  const edita = puede('M0', 'editar');
  return (
    <>
      <Encabezado titulo="Empresa y parametros" sub={`Datos de ${empresa?.razon_social ?? 'la empresa'}, sus sedes y los parametros con que trabaja la plataforma. Cada empresa tiene los suyos y todo cambio queda en la bitacora.`} />
      <div className="tabs">
        <button className={tab === 'datos' ? 'on' : ''} onClick={() => setTab('datos')}>Datos de la empresa</button>
        <button className={tab === 'sedes' ? 'on' : ''} onClick={() => setTab('sedes')}>Sedes y bodegas</button>
        <button className={tab === 'parametros' ? 'on' : ''} onClick={() => setTab('parametros')}>Parametros</button>
      </div>
      {tab === 'datos' && <Datos empresaId={empresaId} edita={edita} />}
      {tab === 'sedes' && <Sedes empresaId={empresaId} edita={edita} />}
      {tab === 'parametros' && <Parametros empresaId={empresaId} edita={edita} />}
    </>
  );
}

function Datos({ empresaId, edita }) {
  const d = useCarga(() => q(sb().from('empresas').select('*').eq('id', empresaId).single()), [empresaId]);
  const [f, setF] = useState(null);
  const [msg, setMsg] = useState(null);
  if (d.err) return <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  const e = f ?? d.datos;
  const set = (k) => (ev) => setF({ ...e, [k]: ev.target.value });
  async function guardar(ev) {
    ev.preventDefault(); setMsg(null);
    try {
      const { id, creado_por, creado_en, actualizado_por, actualizado_en, grupo_id, estado, ...resto } = e;
      await q(sb().from('empresas').update(resto).eq('id', empresaId));
      setMsg({ t: 'ok', m: 'Datos guardados.' }); setF(null); d.recargar();
    } catch (x) { setMsg({ t: 'bad', m: x.message }); }
  }
  return (
    <form className="card stack" onSubmit={guardar}>
      <div className="grid g3">
        <label className="campo">Razon social<input disabled={!edita} value={e.razon_social ?? ''} onChange={set('razon_social')} /></label>
        <label className="campo">Nombre corto (como lo llama el equipo)<input disabled={!edita} value={e.nombre_corto ?? ''} onChange={set('nombre_corto')} /></label>
        <label className="campo">Tipo<select disabled={!edita} value={e.tipo_empresa} onChange={set('tipo_empresa')}><option value="union_temporal">Union temporal</option><option value="consorcio">Consorcio</option><option value="sociedad">Sociedad</option><option value="persona_natural">Persona natural</option><option value="otro">Otro</option></select></label>
        <label className="campo">NIT<input disabled={!edita} value={e.nit ?? ''} onChange={set('nit')} /></label>
        <label className="campo">DV<input disabled={!edita} value={e.dv ?? ''} onChange={set('dv')} style={{ width: 70 }} /></label>
        <label className="campo">Ciudad<input disabled={!edita} value={e.ciudad ?? ''} onChange={set('ciudad')} /></label>
        <label className="campo">Direccion<input disabled={!edita} value={e.direccion ?? ''} onChange={set('direccion')} /></label>
        <label className="campo">Telefono<input disabled={!edita} value={e.telefono ?? ''} onChange={set('telefono')} /></label>
        <label className="campo">Correo<input disabled={!edita} type="email" value={e.correo ?? ''} onChange={set('correo')} /></label>
      </div>
      {msg && <div className={`aviso ${msg.t}`}>{msg.m}</div>}
      {edita && f && <div className="row end"><button type="button" className="btn" onClick={() => setF(null)}>Deshacer</button><button className="btn btn-p">Guardar</button></div>}
    </form>
  );
}

function Sedes({ empresaId, edita }) {
  const d = useCarga(() => q(sb().from('sedes').select('*').eq('empresa_id', empresaId).order('tipo').order('nombre')), [empresaId]);
  const [nuevo, setNuevo] = useState(null);
  const [err, setErr] = useState(null);
  async function guardar(ev) {
    ev.preventDefault(); setErr(null);
    try {
      const { id, ...resto } = nuevo;
      if (id) await q(sb().from('sedes').update(resto).eq('id', id));
      else await q(sb().from('sedes').insert({ ...resto, empresa_id: empresaId }));
      setNuevo(null); d.recargar();
    } catch (x) { setErr(x.message); }
  }
  const ss = d.datos ?? [];
  const set = (k) => (ev) => setNuevo({ ...nuevo, [k]: ev.target.value });
  return (
    <div className="card stack">
      <div className="row between"><b>Sedes de la empresa</b>{edita && <button className="btn btn-p" onClick={() => setNuevo({ nombre: '', tipo: 'unidad_servicio', subtipo: 'eron', ciudad: '', departamento: '', direccion: '', responsable: '', telefono: '', estado: 'activa' })}>＋ Nueva sede</button>}</div>
      <Consejo>El CEDI es la bodega principal donde entregan los proveedores. Las unidades de servicio (carceles, colegios, CDI) se crean aqui o directamente desde el contrato; luego se amarran a cada contrato con sus cupos.</Consejo>
      <Falla msg={d.err} />
      {ss.length === 0 ? <Vacio>Sin sedes.</Vacio> : (
        <table className="t"><thead><tr><th>Sede</th><th>Tipo</th><th>Ciudad</th><th>Responsable</th><th>Estado</th><th></th></tr></thead>
          <tbody>{ss.map((s) => (
            <tr key={s.id}><td><b>{s.nombre}</b><div className="small muted">{s.direccion}</div></td><td className="small">{TIPOS_SEDE[s.tipo] ?? s.tipo}{s.subtipo ? ` · ${SUBTIPOS_SEDE[s.subtipo] ?? s.subtipo}` : ''}</td><td>{[s.ciudad, s.departamento].filter(Boolean).join(', ') || '·'}</td><td>{s.responsable ?? '·'}</td><td><Estado e={s.estado} /></td>
              <td>{edita && <button className="btn" onClick={() => setNuevo({ ...s })}>Editar</button>}</td></tr>
          ))}</tbody></table>
      )}
      {nuevo && (
        <Modal titulo={nuevo.id ? 'Editar sede' : 'Nueva sede'} onCerrar={() => setNuevo(null)}>
          <form className="stack" onSubmit={guardar}>
            <div className="grid g2">
              <label className="campo">Nombre<input required value={nuevo.nombre} onChange={set('nombre')} /></label>
              <label className="campo">Tipo<select value={nuevo.tipo} onChange={set('tipo')}>{Object.entries(TIPOS_SEDE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
              {nuevo.tipo === 'unidad_servicio' && <label className="campo">Clase<select value={nuevo.subtipo ?? 'otro'} onChange={set('subtipo')}>{Object.entries(SUBTIPOS_SEDE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>}
              <label className="campo">Departamento<input value={nuevo.departamento ?? ''} onChange={set('departamento')} /></label>
              <label className="campo">Ciudad<input value={nuevo.ciudad ?? ''} onChange={set('ciudad')} /></label>
              <label className="campo">Direccion<input value={nuevo.direccion ?? ''} onChange={set('direccion')} /></label>
              <label className="campo">Responsable<input value={nuevo.responsable ?? ''} onChange={set('responsable')} /></label>
              <label className="campo">Telefono<input value={nuevo.telefono ?? ''} onChange={set('telefono')} /></label>
              {nuevo.id && <label className="campo">Estado<select value={nuevo.estado} onChange={set('estado')}><option value="activa">Activa</option><option value="anulada">Anulada</option></select></label>}
            </div>
            {err && <div className="aviso bad">{err}</div>}
            <div className="row end"><button type="button" className="btn" onClick={() => setNuevo(null)}>Cancelar</button><button className="btn btn-p">Guardar</button></div>
          </form>
        </Modal>
      )}
    </div>
  );
}

function Parametros({ empresaId, edita }) {
  const d = useCarga(() => q(sb().rpc('parametros_empresa', { p_empresa: empresaId })), [empresaId]);
  const [msg, setMsg] = useState(null);
  if (d.err) return <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  async function guardar(p, texto) {
    setMsg(null);
    try {
      let v = texto;
      if (typeof p.valor === 'number') { v = Number(String(texto).replace(',', '.')); if (Number.isNaN(v)) throw new Error(`${p.clave}: escriba un numero.`); }
      else if (typeof p.valor === 'object' && p.valor !== null) { v = JSON.parse(texto); }
      await q(sb().from('config_empresa').update({ valor: v }).eq('empresa_id', empresaId).eq('clave', p.clave));
      setMsg({ t: 'ok', m: `${p.clave}: guardado.` }); d.recargar();
    } catch (e) { setMsg({ t: 'bad', m: e.message }); }
  }
  return (
    <div className="card stack gap10">
      <b>Parametros de la empresa</b>
      {msg && <div className={`aviso ${msg.t}`}>{msg.m}</div>}
      {d.datos.map((p) => <Campo key={p.clave} p={p} edita={edita} onGuardar={(t) => guardar(p, t)} />)}
    </div>
  );
}

function Campo({ p, edita, onGuardar }) {
  const original = typeof p.valor === 'object' && p.valor !== null ? JSON.stringify(p.valor) : String(p.valor ?? '');
  const [t, setT] = useState(original);
  return (
    <div className="row between" style={{ gap: 8, alignItems: 'center', flexWrap: 'nowrap', paddingBottom: 8, borderBottom: '1px solid var(--linea-suave)' }}>
      <div className="flex1"><div>{p.descripcion ?? p.clave}</div><div className="small muted mono">{p.clave}</div></div>
      <input disabled={!edita} value={t} onChange={(e) => setT(e.target.value)} style={{ width: 220, textAlign: typeof p.valor === 'number' ? 'right' : 'left' }} />
      {edita && t !== original && <button className="btn btn-p" onClick={() => onGuardar(t)}>Guardar</button>}
    </div>
  );
}
