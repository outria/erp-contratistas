'use client';
// Componentes de dominio de Cupos y dietas: tabla por sede, panel de edicion de cupos y panel de dietas.
// Reglas: se guarda por vigencia (desde una fecha); una cantidad en cero cierra la vigencia anterior.
import { useMemo, useState } from 'react';
import { Panel, Campo } from '@/components/ui';
import { num, fechaCorta } from '@/lib/fmt';

export const esSimulada = (f) => /^SIMULADA/i.test(f ?? '');

// cupos de una sede como mapa "grupo|tiempo" -> {cantidad, desde, fuente}
export function mapaCupos(sede) {
  const m = new Map();
  for (const c of sede.cupos ?? []) {
    const k = `${c.grupo_id}|${c.tiempo_id ?? ''}`;
    const v = m.get(k);
    m.set(k, { cantidad: (v?.cantidad ?? 0) + c.cantidad, desde: c.desde, fuente: c.fuente, variante_id: c.variante_id });
  }
  return m;
}
export const totalSede = (sede) => (sede.cupos ?? []).reduce((s, c) => s + c.cantidad, 0);
export const totalDietas = (sede) => (sede.dietas ?? []).reduce((s, c) => s + c.cantidad, 0);

// Tabla de cupos: una fila por sede (y por tiempo cuando el contrato reparte por tiempo, como PAE)
export function TablaCupos({ datos, filtro, onEditar, puedeEditar, unidad }) {
  const porTiempo = datos.tiempos.length > 0 && datos.sedes.some((s) => (s.cupos ?? []).some((c) => c.tiempo_id));
  const grupos = datos.grupos;
  const filas = useMemo(() => {
    const out = [];
    for (const s of datos.sedes) {
      if (filtro && !`${s.nombre} ${s.ciudad ?? ''}`.toLowerCase().includes(filtro.toLowerCase())) continue;
      const m = mapaCupos(s);
      const tiempos = porTiempo ? datos.tiempos.filter((t) => grupos.some((g) => m.get(`${g.id}|${t.id}`)?.cantidad > 0)) : [null];
      if (tiempos.length === 0) tiempos.push(null);
      tiempos.forEach((t, i) => out.push({ sede: s, tiempo: t, primera: i === 0, n: tiempos.length, m }));
    }
    return out;
  }, [datos, filtro, porTiempo, grupos]);
  const tot = useMemo(() => {
    const t = { total: 0 }; for (const g of grupos) t[g.id] = 0;
    for (const f of filas) for (const g of grupos) { const v = f.m.get(`${g.id}|${f.tiempo?.id ?? ''}`)?.cantidad ?? 0; t[g.id] += v; t.total += v; }
    return t;
  }, [filas, grupos]);
  if (datos.sedes.length === 0) return <div className="vacio">Este contrato todavia no tiene sedes activas.</div>;
  return (
    <div className="scroll">
      <table className="t t-cupos">
        <thead>
          <tr>
            <th>Sede</th>
            {porTiempo && <th>Modalidad</th>}
            {grupos.map((g) => <th key={g.id} className="n" title={g.nombre}>{g.tipo === 'etario' ? g.nombre.replace(/ anos 11 meses/, '').replace('Preescolar (', '').replace(')', '') : g.nombre}</th>)}
            <th className="n">Total</th>
            <th>Rige desde</th>
            <th>Fuente</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => {
            const k = (g) => `${g.id}|${f.tiempo?.id ?? ''}`;
            const fila = grupos.map((g) => f.m.get(k(g)));
            const total = fila.reduce((s, v) => s + (v?.cantidad ?? 0), 0);
            const desde = fila.find((v) => v?.desde)?.desde;
            const fuente = fila.find((v) => v?.fuente)?.fuente;
            return (
              <tr key={`${f.sede.id}|${f.tiempo?.id ?? ''}`} className={total === 0 ? 'sin-cupos' : ''}>
                <td>{f.primera ? <><b>{f.sede.nombre}</b><div className="small muted">{f.sede.ciudad}{f.sede.cupos_referencia ? ` · ref. ${num(f.sede.cupos_referencia)}` : ''}{f.sede.parte_hoy != null ? <> · parte de hoy <b>{num(f.sede.parte_hoy)}</b></> : null}</div></> : null}</td>
                {porTiempo && <td>{f.tiempo ? <span className="chip">{f.tiempo.codigo}</span> : <span className="muted small">sin cupos</span>}</td>}
                {grupos.map((g, i) => <td key={g.id} className="n">{fila[i]?.cantidad ? num(fila[i].cantidad) : <span className="muted">·</span>}</td>)}
                <td className="n"><b>{total ? num(total) : '·'}</b></td>
                <td className="small">{desde ? fechaCorta(desde) : '·'}{f.sede.proxima && f.primera ? <div className="chip info" title="Hay una vigencia futura cargada">cambia el {fechaCorta(f.sede.proxima)}</div> : null}</td>
                <td className="small">{fuente ? (esSimulada(fuente) ? <span className="chip warn" title={fuente}>simulada</span> : <span className="muted" title={fuente}>{fuente.length > 28 ? fuente.slice(0, 28) + '…' : fuente}</span>) : '·'}</td>
                <td>{f.primera && puedeEditar && <button className="btn btn-xs" onClick={() => onEditar(f.sede)}>Editar</button>}</td>
              </tr>
            );
          })}
        </tbody>
        <tfoot>
          <tr>
            <td><b>Total</b> <span className="muted small">{datos.sedes.length} sedes</span></td>
            {porTiempo && <td />}
            {grupos.map((g) => <td key={g.id} className="n"><b>{num(tot[g.id])}</b></td>)}
            <td className="n"><b>{num(tot.total)}</b> <span className="small muted">{unidad}</span></td>
            <td colSpan={3} />
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

// Panel para editar los cupos de una sede desde una fecha
export function PanelCupos({ datos, sede, hoy, onCerrar, onGuardar, guardando }) {
  const porTiempo = datos.tiempos.length > 0;
  const m = useMemo(() => mapaCupos(sede), [sede]);
  const tiempos = porTiempo ? datos.tiempos : [null];
  const [desde, setDesde] = useState(hoy);
  const [fuente, setFuente] = useState('');
  const [vals, setVals] = useState(() => {
    const o = {};
    for (const t of tiempos) for (const g of datos.grupos) o[`${g.id}|${t?.id ?? ''}`] = m.get(`${g.id}|${t?.id ?? ''}`)?.cantidad ?? '';
    return o;
  });
  const [abiertos, setAbiertos] = useState(() => new Set(tiempos.filter((t) => datos.grupos.some((g) => (m.get(`${g.id}|${t?.id ?? ''}`)?.cantidad ?? 0) > 0)).map((t) => t?.id ?? '')));
  const set = (k, v) => setVals((o) => ({ ...o, [k]: v }));
  const totalT = (t) => datos.grupos.reduce((s, g) => s + (Number(vals[`${g.id}|${t?.id ?? ''}`]) || 0), 0);
  const total = tiempos.reduce((s, t) => s + totalT(t), 0);
  const cambios = Object.entries(vals).filter(([k, v]) => (Number(v) || 0) !== (m.get(k)?.cantidad ?? 0));
  const variante = sede.variante_id ?? datos.variantes.find((v) => v.es_estandar)?.id ?? null;
  const guardar = () => {
    const items = cambios.map(([k, v]) => { const [grupo_id, tiempo_id] = k.split('|'); return { grupo_id, tiempo_id: tiempo_id || null, variante_id: datos.variantes.length > 1 ? variante : null, cantidad: Number(v) || 0 }; });
    onGuardar({ desde, fuente: fuente || null, items });
  };
  return (
    <Panel titulo={sede.nombre} sub={`${sede.ciudad ?? ''} · cupos que rigen desde la fecha que indique`} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={guardando || cambios.length === 0 || !desde} onClick={guardar}>{guardando ? 'Guardando…' : `Guardar ${cambios.length ? `(${cambios.length})` : ''}`}</button>}>
      <div className="row gap10 mb12">
        <Campo l="Rige desde" req><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo l="Fuente (parte, oficio, SIMAT…)" className="crece"><input value={fuente} onChange={(e) => setFuente(e.target.value)} placeholder="ej. parte de guardia 3-nov" /></Campo>
      </div>
      <div className="aviso info mb12 small">Lo que estaba vigente se cierra el dia anterior a la fecha. Un cero quita el cupo de ese grupo desde esa fecha. Los dias anteriores no cambian.</div>
      {tiempos.map((t) => {
        const kid = t?.id ?? '';
        const abierto = !t || abiertos.has(kid);
        return (
          <section key={kid} className="mb12">
            {t && <button className="btn btn-s" style={{ width: '100%', justifyContent: 'space-between' }} onClick={() => setAbiertos((s) => { const n = new Set(s); n.has(kid) ? n.delete(kid) : n.add(kid); return n; })} aria-expanded={abierto}>
              <span><b>{t.codigo}</b> · {t.nombre}</span><span>{totalT(t) ? num(totalT(t)) : 'sin cupos'} {abierto ? '▴' : '▾'}</span></button>}
            {abierto && (
              <div className="grid-cupos">
                {datos.grupos.map((g) => {
                  const k = `${g.id}|${kid}`; const prev = m.get(k)?.cantidad ?? 0;
                  return (
                    <label key={g.id} className="campo">
                      <span>{g.nombre}{prev ? <span className="muted"> · hoy {num(prev)}</span> : null}</span>
                      <input type="number" min="0" inputMode="numeric" value={vals[k]} onChange={(e) => set(k, e.target.value)} className={(Number(vals[k]) || 0) !== prev ? 'cambiado' : ''} />
                    </label>
                  );
                })}
              </div>
            )}
          </section>
        );
      })}
      <div className="row between mt12"><span className="muted">Total desde {desde ? fechaCorta(desde) : '·'}</span><b style={{ fontSize: 18 }}>{num(total)}</b></div>
      {datos.grupos.length > 1 && total > 0 && (
        <div className="small muted mt12">Reparto: {datos.grupos.map((g) => `${g.codigo} ${Math.round(100 * tiempos.reduce((s, t) => s + (Number(vals[`${g.id}|${t?.id ?? ''}`]) || 0), 0) / total)} %`).join(' · ')}</div>
      )}
    </Panel>
  );
}

// Tabla de dietas: una fila por sede, columnas las dietas que tienen poblacion en el contrato
export function TablaDietas({ datos, filtro, onEditar, puedeEditar }) {
  const usadas = useMemo(() => {
    const ids = new Set(); for (const s of datos.sedes) for (const d of s.dietas ?? []) ids.add(d.dieta_id);
    return datos.dietas.filter((d) => ids.has(d.id));
  }, [datos]);
  const sedes = datos.sedes.filter((s) => !filtro || `${s.nombre} ${s.ciudad ?? ''}`.toLowerCase().includes(filtro.toLowerCase()));
  const porDieta = (s, id) => (s.dietas ?? []).filter((d) => d.dieta_id === id).reduce((a, d) => a + d.cantidad, 0);
  const tot = {}; for (const d of usadas) tot[d.id] = sedes.reduce((a, s) => a + porDieta(s, d.id), 0);
  return (
    <div className="scroll">
      <table className="t t-cupos">
        <thead><tr><th>Sede</th><th className="n">Poblacion</th><th className="n">En dieta</th><th className="n">%</th>{usadas.map((d) => <th key={d.id} className="n" title={d.nombre}>{d.nombre.replace(/^Dieta /, '')}</th>)}<th>Fuente</th><th /></tr></thead>
        <tbody>
          {sedes.map((s) => {
            const pob = totalSede(s); const die = totalDietas(s); const fuente = s.dietas?.[0]?.fuente;
            return (
              <tr key={s.id}>
                <td><b>{s.nombre}</b><div className="small muted">{s.ciudad}</div></td>
                <td className="n">{num(pob)}</td>
                <td className="n"><b>{die ? num(die) : '·'}</b></td>
                <td className="n">{pob && die ? `${Math.round(100 * die / pob)} %` : '·'}</td>
                {usadas.map((d) => <td key={d.id} className="n">{porDieta(s, d.id) ? num(porDieta(s, d.id)) : <span className="muted">·</span>}</td>)}
                <td className="small">{fuente ? (esSimulada(fuente) ? <span className="chip warn" title={fuente}>simulada</span> : <span className="muted" title={fuente}>{fuente.length > 24 ? fuente.slice(0, 24) + '…' : fuente}</span>) : '·'}</td>
                <td>{puedeEditar && <button className="btn btn-xs" onClick={() => onEditar(s)}>Editar</button>}</td>
              </tr>
            );
          })}
        </tbody>
        <tfoot><tr><td><b>Total</b></td><td className="n"><b>{num(sedes.reduce((a, s) => a + totalSede(s), 0))}</b></td><td className="n"><b>{num(sedes.reduce((a, s) => a + totalDietas(s), 0))}</b></td><td />{usadas.map((d) => <td key={d.id} className="n"><b>{num(tot[d.id])}</b></td>)}<td colSpan={2} /></tr></tfoot>
      </table>
    </div>
  );
}

// Panel para editar la poblacion en dieta de una sede: por dieta y por grupo (H / M)
export function PanelDietas({ datos, sede, hoy, onCerrar, onGuardar, guardando }) {
  const grupos = datos.grupos;
  const actual = useMemo(() => { const m = new Map(); for (const d of sede.dietas ?? []) { const k = `${d.dieta_id}|${d.grupo_id}`; m.set(k, (m.get(k) ?? 0) + d.cantidad); } return m; }, [sede]);
  const [desde, setDesde] = useState(hoy);
  const [fuente, setFuente] = useState('');
  const [vals, setVals] = useState(() => { const o = {}; for (const [k, v] of actual) o[k] = v; return o; });
  const [visibles, setVisibles] = useState(() => new Set([...actual.keys()].map((k) => k.split('|')[0])));
  const [nueva, setNueva] = useState('');
  const pob = totalSede(sede);
  const cambios = Object.entries(vals).filter(([k, v]) => (Number(v) || 0) !== (actual.get(k) ?? 0));
  const total = Object.values(vals).reduce((s, v) => s + (Number(v) || 0), 0);
  const porGrupo = (g) => (sede.cupos ?? []).filter((c) => c.grupo_id === g.id).reduce((s, c) => s + c.cantidad, 0);
  const guardar = () => onGuardar({ desde, fuente: fuente || null, items: cambios.map(([k, v]) => { const [dieta_id, grupo_id] = k.split('|'); return { dieta_id, grupo_id, cantidad: Number(v) || 0 }; }) });
  const lista = datos.dietas.filter((d) => visibles.has(d.id));
  return (
    <Panel titulo={`Dietas · ${sede.nombre}`} sub={`${num(pob)} de poblacion · ${num(total)} en dieta (${pob ? Math.round(100 * total / pob) : 0} %)`} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={guardando || cambios.length === 0 || !desde} onClick={guardar}>{guardando ? 'Guardando…' : `Guardar ${cambios.length ? `(${cambios.length})` : ''}`}</button>}>
      <div className="row gap10 mb12">
        <Campo l="Rige desde" req><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo l="Fuente (BD de dietas, oficio…)" className="crece"><input value={fuente} onChange={(e) => setFuente(e.target.value)} placeholder="ej. BD de dietas octubre" /></Campo>
      </div>
      {total > pob && pob > 0 && <div className="aviso bad mb12 small">Hay mas poblacion en dieta ({num(total)}) que poblacion total ({num(pob)}). El sistema prorratea, pero revise las cifras.</div>}
      <table className="t">
        <thead><tr><th>Dieta</th>{grupos.map((g) => <th key={g.id} className="n">{g.nombre}<div className="small muted" style={{ fontWeight: 400 }}>de {num(porGrupo(g))}</div></th>)}<th className="n">Total</th></tr></thead>
        <tbody>
          {lista.length === 0 && <tr><td colSpan={grupos.length + 2} className="vacio">Sin poblacion en dieta. Agregue una dieta abajo.</td></tr>}
          {lista.map((d) => {
            const tot = grupos.reduce((s, g) => s + (Number(vals[`${d.id}|${g.id}`]) || 0), 0);
            return (
              <tr key={d.id}>
                <td><b>{d.nombre.replace(/^Dieta /, '')}</b><div className="small muted">{d.categoria}</div></td>
                {grupos.map((g) => { const k = `${d.id}|${g.id}`; const prev = actual.get(k) ?? 0; return (
                  <td key={g.id} className="n"><input type="number" min="0" inputMode="numeric" style={{ width: 90, textAlign: 'right' }} value={vals[k] ?? ''} onChange={(e) => setVals((o) => ({ ...o, [k]: e.target.value }))} className={(Number(vals[k]) || 0) !== prev ? 'cambiado' : ''} /></td>); })}
                <td className="n"><b>{num(tot)}</b></td>
              </tr>
            );
          })}
        </tbody>
      </table>
      <div className="row gap8 mt12">
        <select value={nueva} onChange={(e) => setNueva(e.target.value)}>
          <option value="">Agregar dieta…</option>
          {datos.dietas.filter((d) => !visibles.has(d.id)).map((d) => <option key={d.id} value={d.id}>{d.nombre}</option>)}
        </select>
        <button className="btn btn-s" disabled={!nueva} onClick={() => { setVisibles((s) => new Set([...s, nueva])); setNueva(''); }}>Agregar</button>
      </div>
      <div className="small muted mt12">Las dietas se descuentan de la linea general en la explosion; en el menu se reemplaza la preparacion segun las reglas del contrato (hipoglucida, gestante, etc.).</div>
    </Panel>
  );
}
