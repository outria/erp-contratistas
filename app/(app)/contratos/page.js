'use client';
// M1 · Contratos: lista con agotamiento presupuestal y alta del cabezote.
import { useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Vacio, Modal, Estado, Consejo, Info } from '@/components/ui';
import { cop, num, fechaCorta } from '@/lib/fmt';
import { MODALIDADES, TIPOS_ENTIDAD } from '@/lib/catalogos';

export default function Contratos() {
  const { empresaId, puede } = useApp();
  const [nuevo, setNuevo] = useState(false);
  const d = useCarga(() => q(sb().from('v_contratos_resumen').select('*').eq('empresa_id', empresaId).order('estado').order('fecha_fin_vigente')), [empresaId]);
  const cs = d.datos ?? [];
  return (
    <>
      <Encabezado titulo="Contratos y anexos" sub="El cabezote de cada contrato, sus adiciones y prorrogas, las unidades de servicio y el agotamiento presupuestal. De aqui sale la minuta para planeacion.">
        {puede('M1', 'crear') && <button className="btn btn-p" onClick={() => setNuevo(true)}>＋ Nuevo contrato</button>}
      </Encabezado>
      <Consejo>
        Cargue primero el cabezote (numero, entidad, objeto, valor y fechas) y despues, dentro del contrato, los anexos (nutricional, calidad, talento humano, polizas), las adiciones y las sedes.
        El tope de adiciones se controla en salarios minimos del año de firma, como lo exige la norma: el sistema avisa si una adicion lo supera.
      </Consejo>
      {d.err && <Falla msg={d.err} />}
      {d.cargando && !d.datos ? <Cargando /> : cs.length === 0 ? <Vacio>Todavia no hay contratos. Cree el primero con el boton de arriba.</Vacio> : (
        <div className="card">
          <table className="t">
            <thead><tr><th>Contrato</th><th>Entidad</th><th>Modalidad</th><th className="n">Valor inicial</th><th className="n">Adiciones <Info>Suma de adiciones vigentes y el porcentaje que representan medido en SMLMV del año de firma (tope legal 50 %).</Info></th><th className="n">Agotamiento</th><th>Inicio</th><th>Fin vigente</th><th>Sedes</th><th>Estado</th></tr></thead>
            <tbody>{cs.map((c) => (
              <tr key={c.id}>
                <td><Link href={`/contratos/${c.id}`}><b>{c.numero}</b></Link><div className="small muted">{c.codigo}</div></td>
                <td>{c.entidad_nombre}</td>
                <td className="small">{MODALIDADES[c.modalidad] ?? c.modalidad}</td>
                <td className="n">{cop(c.valor_inicial)}</td>
                <td className="n">{cop(c.adiciones)}<div className="small muted">{num(c.adiciones_pct_smlmv, 1)} %</div></td>
                <td className="n">{c.agotamiento_pct == null ? '·' : <><b>{num(c.agotamiento_pct, 1)} %</b><div className="small muted">saldo {cop(c.saldo)}</div></>}</td>
                <td>{fechaCorta(c.fecha_inicio)}</td>
                <td>{fechaCorta(c.fecha_fin_vigente)}<div className="small muted">{c.dias_restantes} dias</div></td>
                <td className="n">{c.n_sedes} <span className="small muted">/ {num(c.cupos_referencia)} cupos</span></td>
                <td><Estado e={c.estado} /></td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {nuevo && <NuevoContrato onCerrar={() => setNuevo(false)} onListo={() => { setNuevo(false); d.recargar(); }} />}
    </>
  );
}

function NuevoContrato({ onCerrar, onListo }) {
  const { empresaId } = useApp();
  const ents = useCarga(() => q(sb().from('entidades_contratantes').select('*').eq('empresa_id', empresaId).eq('estado', 'activa').order('nombre')), [empresaId]);
  const [f, setF] = useState({ numero: '', entidad_id: '', modalidad: 'uspec_ppl', objeto: '', valor_inicial: '', incluye_iva: false, fecha_suscripcion: '', fecha_inicio: '', fecha_fin_inicial: '', dias_atencion: 'todos', tiempos_comida: 4, n_menus_ciclo: '', ciclo_reparto: 'semanal', dias_subsanacion: 3, proceso_secop: '', interventoria: '', estado: 'vigente' });
  const [nuevaEnt, setNuevaEnt] = useState(null); // {nombre, tipo}
  const [err, setErr] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value });
  const cambioModalidad = (e) => {
    const m = e.target.value;
    const base = m === 'pae' ? { dias_atencion: 'habiles', tiempos_comida: 1, n_menus_ciclo: 20, ciclo_reparto: '2+3' }
      : m === 'uspec_ppl' ? { dias_atencion: 'todos', tiempos_comida: 4, n_menus_ciclo: 15, ciclo_reparto: 'semanal' } : {};
    setF({ ...f, modalidad: m, ...base });
  };
  async function guardar(e) {
    e.preventDefault(); setErr(null); setOcupado(true);
    try {
      let entidad_id = f.entidad_id;
      if (nuevaEnt) {
        if (!nuevaEnt.nombre.trim()) throw new Error('Escriba el nombre de la entidad.');
        const r = await q(sb().from('entidades_contratantes').insert({ empresa_id: empresaId, nombre: nuevaEnt.nombre.trim(), tipo: nuevaEnt.tipo }).select('id').single());
        entidad_id = r.id;
      }
      if (!entidad_id) throw new Error('Escoja la entidad contratante.');
      const p = { ...f, empresa_id: empresaId, entidad_id, valor_inicial: Number(String(f.valor_inicial).replace(/[^\d.]/g, '')), n_menus_ciclo: f.n_menus_ciclo ? Number(f.n_menus_ciclo) : null };
      await q(sb().rpc('crear_contrato', { p }));
      onListo();
    } catch (x) { setErr(x.message); } finally { setOcupado(false); }
  }
  return (
    <Modal titulo="Nuevo contrato" onCerrar={onCerrar} ancho>
      <form className="stack" onSubmit={guardar}>
        <div className="grid g3">
          <label className="campo">Numero del contrato (en la entidad)<input required value={f.numero} onChange={set('numero')} placeholder="202501642" /></label>
          <label className="campo">Modalidad
            <select value={f.modalidad} onChange={cambioModalidad}>{Object.entries(MODALIDADES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
          </label>
          <label className="campo">Estado<select value={f.estado} onChange={set('estado')}><option value="borrador">Borrador</option><option value="vigente">Vigente</option></select></label>
        </div>
        <div className="grid g2">
          {nuevaEnt ? (
            <div className="row" style={{ alignItems: 'flex-end' }}>
              <label className="campo" style={{ flex: 2 }}>Entidad nueva<input value={nuevaEnt.nombre} onChange={(e) => setNuevaEnt({ ...nuevaEnt, nombre: e.target.value })} placeholder="Alcaldia de Soledad" /></label>
              <label className="campo">Tipo<select value={nuevaEnt.tipo} onChange={(e) => setNuevaEnt({ ...nuevaEnt, tipo: e.target.value })}>{Object.entries(TIPOS_ENTIDAD).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
              <button type="button" className="btn" onClick={() => setNuevaEnt(null)}>Cancelar</button>
            </div>
          ) : (
            <div className="row" style={{ alignItems: 'flex-end' }}>
              <label className="campo" style={{ flex: 1 }}>Entidad contratante
                <select value={f.entidad_id} onChange={set('entidad_id')}><option value="">Escoja…</option>{(ents.datos ?? []).map((x) => <option key={x.id} value={x.id}>{x.nombre}</option>)}</select>
              </label>
              <button type="button" className="btn" onClick={() => setNuevaEnt({ nombre: '', tipo: 'alcaldia' })}>＋ Entidad</button>
            </div>
          )}
          <label className="campo">Interventoria / supervisor<input value={f.interventoria} onChange={set('interventoria')} /></label>
        </div>
        <label className="campo">Objeto del contrato<textarea required rows={2} value={f.objeto} onChange={set('objeto')} /></label>
        <div className="grid g4">
          <label className="campo">Valor inicial (COP)<input required inputMode="numeric" value={f.valor_inicial} onChange={set('valor_inicial')} placeholder="11720000000" /></label>
          <label className="campo">Fecha de suscripcion <Info>Define el salario minimo con el que se mide el tope del 50 % de adiciones.</Info><input required type="date" value={f.fecha_suscripcion} onChange={set('fecha_suscripcion')} /></label>
          <label className="campo">Fecha de inicio<input required type="date" value={f.fecha_inicio} onChange={set('fecha_inicio')} /></label>
          <label className="campo">Fecha final inicial<input required type="date" value={f.fecha_fin_inicial} onChange={set('fecha_fin_inicial')} /></label>
        </div>
        <div className="grid g4">
          <label className="campo">Dias de atencion<select value={f.dias_atencion} onChange={set('dias_atencion')}><option value="habiles">Dias habiles (colegios)</option><option value="todos">Todos los dias (carceles)</option><option value="calendario_propio">Calendario propio</option></select></label>
          <label className="campo">Tiempos de comida<input type="number" min={1} max={6} value={f.tiempos_comida} onChange={set('tiempos_comida')} /></label>
          <label className="campo">Menus del ciclo <Info>15, 18, 20 o 21 segun la minuta. El detalle se carga en Planeacion.</Info><input type="number" min={1} max={60} value={f.n_menus_ciclo} onChange={set('n_menus_ciclo')} /></label>
          <label className="campo">Ciclo de reparto a sedes<select value={f.ciclo_reparto} onChange={set('ciclo_reparto')}><option value="semanal">Semanal</option><option value="2+3">2 + 3 dias</option><option value="3+4">3 + 4 dias</option><option value="quincenal">Quincenal</option></select></label>
        </div>
        <div className="grid g3">
          <label className="campo">Proceso SECOP II (numero o enlace)<input value={f.proceso_secop} onChange={set('proceso_secop')} /></label>
          <label className="campo">Dias para subsanar hallazgos<input type="number" min={0} value={f.dias_subsanacion} onChange={set('dias_subsanacion')} /></label>
          <label className="campo" style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 22 }}><input type="checkbox" checked={f.incluye_iva} onChange={set('incluye_iva')} /> El valor incluye IVA</label>
        </div>
        {err && <div className="aviso bad">{err}</div>}
        <div className="row" style={{ justifyContent: 'flex-end' }}>
          <button type="button" className="btn" onClick={onCerrar}>Cancelar</button>
          <button className="btn btn-p" disabled={ocupado}>{ocupado ? 'Guardando…' : 'Crear contrato'}</button>
        </div>
      </form>
    </Modal>
  );
}
