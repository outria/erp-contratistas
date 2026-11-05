'use client';
// Componentes de dominio de Minutas y calendario: editor de ciclo, asignacion por sede, gramajes por grupo,
// calendario de servicio y partes diarios.
import { useEffect, useMemo, useState } from 'react';
import { sb, q } from '@/lib/supabase';
import { useCarga } from '@/lib/ctx';
import { Panel, Campo, Cargando, Estado, Tabla } from '@/components/ui';
import { num, fechaCorta, fechaISO, desdeISO } from '@/lib/fmt';

const sumar = (iso, n) => { const d = desdeISO(iso); d.setDate(d.getDate() + n); return fechaISO(d); };
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// ------------------------------------------------------------------ Ciclo de menus
export function EditorCiclo({ cicloId, datos, puedeEditar, onCambio, onCerrar }) {
  const d = useCarga(() => q(sb().rpc('ciclo_detalle', { p_ciclo: cicloId })), [cicloId]);
  const [tiempoSel, setTiempoSel] = useState('');
  const [msg, setMsg] = useState(null);
  const [edit, setEdit] = useState(null);   // {dia, tiempo_id, componente_id}
  const items = useMemo(() => { const m = new Map(); for (const i of d.datos?.items ?? []) m.set(`${i.dia}|${i.tiempo_id}|${i.componente_id}`, i); return m; }, [d.datos]);
  const c = d.datos?.ciclo;
  const tiempos = datos.tiempos.filter((t) => !tiempoSel || t.id === tiempoSel);
  const comps = (t) => datos.componentes.filter((x) => x.tiempo_id === t.id);
  const guardar = async (dia, tiempo_id, componente_id, preparacion_id) => {
    setMsg(null);
    try { await q(sb().rpc('guardar_ciclo_item', { p_ciclo: cicloId, p_dia: dia, p_tiempo: tiempo_id, p_componente: componente_id, p_preparacion: preparacion_id || null })); setEdit(null); d.recargar(); onCambio?.(); }
    catch (e) { setMsg({ ok: false, t: e.message }); }
  };
  const estado = async (est) => {
    setMsg(null);
    try { await q(sb().rpc('estado_ciclo', { p_ciclo: cicloId, p_estado: est })); d.recargar(); onCambio?.(); setMsg({ ok: true, t: `Ciclo ${est}.` }); }
    catch (e) { setMsg({ ok: false, t: e.message }); }
  };
  if (!d.datos) return <Cargando />;
  const dias = Array.from({ length: c.n_menus }, (_, i) => i + 1);
  const faltan = dias.reduce((s, dia) => s + datos.componentes.filter((x) => x.obligatorio !== false && !items.get(`${dia}|${x.tiempo_id}|${x.id}`)?.preparacion_id).length, 0);
  return (
    <>
      <div className="row between mb12 wrap">
        <div className="row gap8"><button className="btn btn-s" onClick={onCerrar}>← Ciclos</button><h2 className="m0">{c.codigo}{c.nombre ? ` · ${c.nombre}` : ''}</h2><Estado e={c.estado} /><span className="muted small">{c.n_menus} menus · {faltan ? `${faltan} casillas sin receta` : 'completo'}</span></div>
        <div className="row gap6">
          <select value={tiempoSel} onChange={(e) => setTiempoSel(e.target.value)}><option value="">Todos los tiempos</option>{datos.tiempos.map((t) => <option key={t.id} value={t.id}>{t.codigo} · {t.nombre}</option>)}</select>
          {puedeEditar && c.estado === 'borrador' && <button className="btn btn-s btn-p" disabled={faltan > 0} title={faltan ? 'Complete las casillas sin receta' : ''} onClick={() => estado('vigente')}>Poner vigente</button>}
          {puedeEditar && c.estado === 'vigente' && <button className="btn btn-s" onClick={() => estado('historico')}>Pasar a historico</button>}
        </div>
      </div>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="scroll">
        <table className="t t-ciclo">
          <thead><tr><th>Menu</th>{tiempos.map((t) => comps(t).map((x) => <th key={x.id} title={x.nombre}><span className="muted small">{t.codigo}</span><br />{x.codigo}</th>))}</tr></thead>
          <tbody>
            {dias.map((dia) => (
              <tr key={dia}>
                <td><b>Menu {dia}</b></td>
                {tiempos.map((t) => comps(t).map((x) => {
                  const it = items.get(`${dia}|${t.id}|${x.id}`);
                  const editando = edit && edit.dia === dia && edit.tiempo_id === t.id && edit.componente_id === x.id;
                  if (editando) {
                    const ops = d.datos.opciones[x.id] ?? [];
                    return <td key={x.id}><select autoFocus defaultValue={it?.preparacion_id ?? ''} onChange={(e) => guardar(dia, t.id, x.id, e.target.value)} onBlur={() => setEdit(null)}>
                      <option value="">(sin receta)</option>{ops.map((o) => <option key={o.id} value={o.id}>{o.en_minuta ? '★ ' : ''}{o.nombre}</option>)}</select></td>;
                  }
                  return <td key={x.id} className={`celda-ciclo${!it?.preparacion_id ? ' vacia' : ''}${puedeEditar && c.estado !== 'historico' ? ' editable' : ''}`} onClick={() => puedeEditar && c.estado !== 'historico' && setEdit({ dia, tiempo_id: t.id, componente_id: x.id })} title={it?.principal ?? ''}>
                    {it?.preparacion ?? it?.descriptor ?? <span className="muted">·</span>}
                  </td>;
                }))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="small muted mt8">Haga clic en una casilla para cambiar la receta (★ = ya esta en la minuta de este contrato). Un ciclo vigente se puede seguir ajustando; los cambios aplican desde el proximo calculo. Para una version nueva, copie el ciclo.</div>
    </>
  );
}

export function FormCiclo({ datos, onCerrar, onCrear }) {
  const [codigo, setCodigo] = useState('');
  const [nombre, setNombre] = useState('');
  const [n, setN] = useState(datos.contrato?.n_menus_ciclo ?? 15);
  const [copiar, setCopiar] = useState('');
  return (
    <Panel titulo="Nuevo ciclo de menus" sub="Vacio o copiando uno existente para ajustarlo" onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={!codigo || n < 1} onClick={() => onCrear({ codigo, nombre, n, copiar: copiar || null })}>Crear</button>}>
      <Campo l="Codigo" req className="mb8"><input value={codigo} onChange={(e) => setCodigo(e.target.value)} placeholder="ej. CICLO_2027_1" /></Campo>
      <Campo l="Nombre" className="mb8"><input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="ej. Ciclo aprobado oficio 123 de 2027" /></Campo>
      <Campo l="Numero de menus" req className="mb8"><input type="number" min="1" max="90" value={n} onChange={(e) => setN(Number(e.target.value))} /></Campo>
      <Campo l="Copiar de"><select value={copiar} onChange={(e) => setCopiar(e.target.value)}><option value="">Empezar vacio</option>{datos.ciclos.map((c) => <option key={c.id} value={c.id}>{c.codigo} ({c.n_menus} menus)</option>)}</select></Campo>
    </Panel>
  );
}

// ------------------------------------------------------------------ Asignacion de ciclo a sedes
export function AsignarCiclo({ datos, sedes, hoy, onCerrar, onGuardar }) {
  const [ciclo, setCiclo] = useState(datos.ciclos.find((c) => c.estado === 'vigente')?.id ?? datos.ciclos[0]?.id ?? '');
  const [variante, setVariante] = useState(datos.variantes.find((v) => v.es_estandar)?.id ?? '');
  const [desde, setDesde] = useState(hoy);
  const [menu1, setMenu1] = useState(hoy);
  const [modo, setModo] = useState('continuo');
  return (
    <Panel titulo={`Asignar ciclo a ${sedes.length} ${sedes.length === 1 ? 'sede' : 'sedes'}`} sub={sedes.map((s) => s.nombre).join(' · ')} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={!ciclo || !desde || !menu1} onClick={() => onGuardar({ sedes: sedes.map((s) => s.id), ciclo, variante: variante || null, desde, menu1, modo })}>Asignar</button>}>
      <Campo l="Ciclo" req className="mb8"><select value={ciclo} onChange={(e) => setCiclo(e.target.value)}>{datos.ciclos.map((c) => <option key={c.id} value={c.id}>{c.codigo} · {c.n_menus} menus · {c.estado}</option>)}</select></Campo>
      {datos.variantes.length > 1 && <Campo l="Variante de racion" className="mb8"><select value={variante} onChange={(e) => setVariante(e.target.value)}>{datos.variantes.map((v) => <option key={v.id} value={v.id}>{v.codigo} · {v.nombre}</option>)}</select></Campo>}
      <div className="row gap10 mb8">
        <Campo l="Rige desde" req><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo l="Fecha del menu 1" req ayuda="El dia en que arranca (o arranco) el menu 1; de ahi se cuenta que menu toca cada dia"><input type="date" value={menu1} onChange={(e) => setMenu1(e.target.value)} /></Campo>
      </div>
      <Campo l="Reinicio del ciclo"><select value={modo} onChange={(e) => setModo(e.target.value)}><option value="continuo">Continuo (sigue donde va)</option><option value="mensual">Cada mes vuelve al menu 1</option><option value="semanal">Cada semana vuelve al menu 1</option></select></Campo>
      <div className="small muted mt12">La asignacion anterior de cada sede se cierra el dia antes de la fecha. Los dias sin servicio cuentan o no en el ciclo segun la modalidad del contrato (USPEC corre todos los dias; PAE solo los dias de clase).</div>
    </Panel>
  );
}

// ------------------------------------------------------------------ Gramajes por componente y grupo
export function Gramajes({ datos, hoy, puedeEditar, onGuardar, guardando }) {
  const grupos = datos.grupos;
  const base = useMemo(() => { const m = new Map(); for (const g of datos.gramajes) m.set(`${g.componente_id}|${g.grupo_id ?? ''}`, g); return m; }, [datos.gramajes]);
  const ref = useMemo(() => new Map(datos.referencia.map((r) => [r.componente_id, r])), [datos.referencia]);
  const [vals, setVals] = useState({});
  const [desde, setDesde] = useState(hoy);
  const [motivo, setMotivo] = useState('');
  useEffect(() => { const o = {}; for (const [k, g] of base) o[k] = g.porcion_servida ?? ''; setVals(o); }, [base]);
  const k = (c, g) => `${c.id}|${g?.id ?? ''}`;
  const cambios = Object.entries(vals).filter(([key, v]) => String(v ?? '') !== String(base.get(key)?.porcion_servida ?? ''));
  const guardar = () => onGuardar({ desde, motivo, items: cambios.map(([key, v]) => { const [componente_id, grupo_id] = key.split('|'); return { componente_id, grupo_id: grupo_id || null, porcion_servida: v === '' ? null : Number(v) }; }) });
  return (
    <>
      <div className="row gap10 mb12 wrap">
        <Campo l="Rigen desde"><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo l="Motivo / soporte" className="crece"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. Lineamiento PAE 2026, tabla de gramajes por grupo de edad" /></Campo>
        {puedeEditar && <button className="btn btn-p" disabled={guardando || cambios.length === 0} onClick={guardar} style={{ alignSelf: 'flex-end' }}>{guardando ? 'Guardando…' : `Guardar ${cambios.length ? `(${cambios.length})` : ''}`}</button>}
      </div>
      <div className="aviso info small mb12">Porcion servida en gramos (o ml) por componente y grupo. Vacio = se usa la receta tal cual. Un valor escala toda la receta en proporcion al ingrediente principal; la columna "receta" muestra la porcion que da hoy la receta de referencia. El crudo se calcula con el factor de coccion del producto.</div>
      <div className="scroll">
        <table className="t t-gram">
          <thead><tr><th>Tiempo</th><th>Componente</th><th className="n">Receta (servido)</th>{grupos.map((g) => <th key={g.id} className="n">{g.nombre}</th>)}</tr></thead>
          <tbody>
            {datos.tiempos.map((t) => datos.componentes.filter((c) => c.tiempo_id === t.id).map((c, i, arr) => (
              <tr key={c.id}>
                {i === 0 && <td rowSpan={arr.length}><b>{t.codigo}</b><div className="small muted">{t.nombre}</div></td>}
                <td>{c.nombre}<div className="small muted">{c.codigo}{ref.get(c.id)?.principal ? ` · ${ref.get(c.id).principal}` : ''}</div></td>
                <td className="n muted">{ref.get(c.id) ? `${num(ref.get(c.id).servido)} g` : '·'}</td>
                {grupos.map((g) => { const key = k(c, g); const prev = base.get(key)?.porcion_servida ?? ''; return (
                  <td key={g.id} className="n">{puedeEditar
                    ? <input type="number" min="0" step="1" style={{ width: 80, textAlign: 'right' }} value={vals[key] ?? ''} placeholder={ref.get(c.id) ? String(Math.round(ref.get(c.id).servido)) : ''} onChange={(e) => setVals((o) => ({ ...o, [key]: e.target.value }))} className={String(vals[key] ?? '') !== String(prev) ? 'cambiado' : ''} />
                    : (prev !== '' ? `${num(prev)} g` : <span className="muted">receta</span>)}</td>); })}
              </tr>
            )))}
          </tbody>
        </table>
      </div>
    </>
  );
}

// ------------------------------------------------------------------ Calendario de servicio
export function Calendario({ contratoId, datos, hoy, puedeEditar, onMarcar }) {
  const [mes, setMes] = useState(hoy.slice(0, 7));
  const [n, setN] = useState(2);
  const desde = `${mes}-01`;
  const hasta = useMemo(() => { const d = desdeISO(desde); d.setMonth(d.getMonth() + n); d.setDate(0); return fechaISO(d); }, [desde, n]);
  const cal = useCarga(() => q(sb().rpc('calendario_contrato', { p_contrato: contratoId, p_desde: desde, p_hasta: hasta })), [contratoId, desde, hasta, datos]);
  const [sel, setSel] = useState(null);     // {desde, hasta}
  const [form, setForm] = useState(null);
  const dias = useMemo(() => new Map((cal.datos?.dias ?? []).map((d) => [d.fecha, d])), [cal.datos]);
  const meses = Array.from({ length: n }, (_, i) => { const d = desdeISO(desde); d.setMonth(d.getMonth() + i); return d; });
  const clic = (f) => {
    if (!puedeEditar) return;
    if (!sel || sel.hasta) setSel({ desde: f, hasta: null });
    else { const a = sel.desde < f ? sel.desde : f, b = sel.desde < f ? f : sel.desde; setSel({ desde: a, hasta: b }); setForm({ desde: a, hasta: b }); }
  };
  const estadoDia = (d) => {
    if (!d) return '';
    if (d.contrato) return d.contrato.atiende ? 'extra' : 'cerrado';
    if (d.sedes?.length) return 'parcial';
    return d.regla ? 'servicio' : 'sin';
  };
  return (
    <>
      <div className="row gap10 mb12 wrap">
        <button className="btn btn-s" onClick={() => { const d = desdeISO(desde); d.setMonth(d.getMonth() - 1); setMes(fechaISO(d).slice(0, 7)); }}>◀</button>
        <input type="month" value={mes} onChange={(e) => setMes(e.target.value)} />
        <button className="btn btn-s" onClick={() => { const d = desdeISO(desde); d.setMonth(d.getMonth() + 1); setMes(fechaISO(d).slice(0, 7)); }}>▶</button>
        <select value={n} onChange={(e) => setN(Number(e.target.value))}><option value={1}>1 mes</option><option value={2}>2 meses</option><option value={3}>3 meses</option><option value={6}>6 meses</option></select>
        <span className="crece" />
        <span className="small row gap8"><i className="cal-leyenda servicio" /> servicio <i className="cal-leyenda sin" /> sin servicio (regla) <i className="cal-leyenda cerrado" /> marcado sin servicio <i className="cal-leyenda extra" /> jornada extra <i className="cal-leyenda parcial" /> solo algunas sedes</span>
      </div>
      {puedeEditar && <div className="aviso info small mb12">{sel && !sel.hasta ? <>Inicio: <b>{fechaCorta(sel.desde)}</b>. Haga clic en el dia final del rango.</> : 'Haga clic en el primer y el ultimo dia de un rango (receso, vacaciones, paro, jornada de reposicion) para marcarlo.'}</div>}
      {cal.cargando && !cal.datos ? <Cargando /> : (
        <div className="cal-meses">
          {meses.map((m) => {
            const y = m.getFullYear(), mo = m.getMonth();
            const primero = new Date(y, mo, 1); const nd = new Date(y, mo + 1, 0).getDate();
            const off = (primero.getDay() + 6) % 7;
            return (
              <div key={`${y}-${mo}`} className="cal-mes">
                <h4>{MESES[mo]} {y}</h4>
                <div className="cal-grid">
                  {['L', 'M', 'X', 'J', 'V', 'S', 'D'].map((d) => <span key={d} className="cal-cab">{d}</span>)}
                  {Array.from({ length: off }).map((_, i) => <span key={`o${i}`} />)}
                  {Array.from({ length: nd }, (_, i) => { const f = fechaISO(new Date(y, mo, i + 1)); const d = dias.get(f); const enSel = sel && (sel.hasta ? f >= sel.desde && f <= sel.hasta : f === sel.desde); return (
                    <button key={f} className={`cal-dia ${estadoDia(d)}${f === hoy ? ' hoy' : ''}${enSel ? ' sel' : ''}${d?.festivo ? ' festivo' : ''}`} onClick={() => clic(f)} title={[d?.festivo, d?.contrato?.motivo, d?.sedes?.length ? `${d.sedes.length} sedes con marca` : null].filter(Boolean).join(' · ')}>{i + 1}</button>); })}
                </div>
              </div>
            );
          })}
        </div>
      )}
      {form && <FormCalendario datos={datos} form={form} onCerrar={() => { setForm(null); setSel(null); }} onMarcar={async (f) => { await onMarcar(f); setForm(null); setSel(null); cal.recargar(); }} />}
    </>
  );
}

function FormCalendario({ datos, form, onCerrar, onMarcar }) {
  const [accion, setAccion] = useState('cerrar');
  const [motivo, setMotivo] = useState('');
  const [todas, setTodas] = useState(true);
  const [sedes, setSedes] = useState([]);
  const [cuenta, setCuenta] = useState(false);
  const dias = Math.round((desdeISO(form.hasta) - desdeISO(form.desde)) / 86400000) + 1;
  return (
    <Panel titulo={`${fechaCorta(form.desde)} a ${fechaCorta(form.hasta)}`} sub={`${dias} dias`} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={accion !== 'regla' && !motivo} onClick={() => onMarcar({ desde: form.desde, hasta: form.hasta, atiende: accion === 'regla' ? null : accion === 'abrir', motivo, sedes: todas ? null : sedes, cuenta })}>Aplicar</button>}>
      <Campo l="Que pasa en estos dias" className="mb8">
        <select value={accion} onChange={(e) => setAccion(e.target.value)}>
          <option value="cerrar">Sin servicio (receso, vacaciones, paro, cierre)</option>
          <option value="abrir">Si hay servicio aunque la regla diga que no (sabado de reposicion, jornada extra)</option>
          <option value="regla">Volver a la regla del contrato (quitar marcas)</option>
        </select>
      </Campo>
      {accion !== 'regla' && <Campo l="Motivo" req className="mb8"><input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej. Receso escolar octubre, Semana Santa, paro de transportadores" /></Campo>}
      {accion === 'cerrar' && <label className="row gap6 mb8 small"><input type="checkbox" checked={cuenta} onChange={(e) => setCuenta(e.target.checked)} /> Estos dias si cuentan para avanzar el ciclo (el menu sigue corriendo aunque no se sirva)</label>}
      <Campo l="Sedes" className="mb8"><div className="row gap10"><label className="row gap4"><input type="radio" checked={todas} onChange={() => setTodas(true)} /> Todo el contrato</label><label className="row gap4"><input type="radio" checked={!todas} onChange={() => setTodas(false)} /> Algunas sedes</label></div></Campo>
      {!todas && <div className="scroll" style={{ maxHeight: 220, border: '1px solid var(--linea)', borderRadius: 8, padding: 8 }}>{datos.sedes.map((s) => <label key={s.id} className="row gap6 small" style={{ padding: '2px 0' }}><input type="checkbox" checked={sedes.includes(s.id)} onChange={(e) => setSedes(e.target.checked ? [...sedes, s.id] : sedes.filter((x) => x !== s.id))} /> {s.nombre}</label>)}</div>}
      <div className="small muted mt12">Un dia sin servicio no genera raciones ni compra; si no cuenta para el ciclo, el menu que tocaba se sirve el siguiente dia habil. Las novedades aprobadas (PAE) ya marcan el calendario solas.</div>
    </Panel>
  );
}

// ------------------------------------------------------------------ Partes diarios
export function Partes({ contratoId, datos, hoy, unidad, puedeEditar }) {
  const [fecha, setFecha] = useState(hoy);
  const [filtro, setFiltro] = useState('');
  const d = useCarga(() => q(sb().rpc('partes_dia', { p_contrato: contratoId, p_fecha: fecha })), [contratoId, fecha]);
  const [vals, setVals] = useState({});
  const [msg, setMsg] = useState(null);
  const [guardando, setGuardando] = useState(null);
  const grupos = datos.grupos;
  const porTiempo = datos.tiempos.length > 0 && (d.datos ?? []).some((s) => s.cupos.some((c) => c.tiempo_id));
  const cols = porTiempo ? datos.tiempos.flatMap((t) => grupos.map((g) => ({ t, g }))) : grupos.map((g) => ({ t: null, g }));
  useEffect(() => { const o = {}; for (const s of d.datos ?? []) for (const p of s.parte) o[`${s.id}|${p.grupo_id}|${p.tiempo_id ?? ''}`] = p.cantidad; setVals(o); }, [d.datos]);
  const cupo = (s, g, t) => s.cupos.filter((c) => c.grupo_id === g.id && (c.tiempo_id ?? '') === (t?.id ?? '')).reduce((a, c) => a + c.cantidad, 0);
  const guardarSede = async (s) => {
    setGuardando(s.id); setMsg(null);
    try {
      const items = cols.filter(({ t, g }) => porTiempo ? cupo(s, g, t) > 0 || vals[`${s.id}|${g.id}|${t?.id ?? ''}`] !== undefined : true)
        .map(({ t, g }) => ({ grupo_id: g.id, tiempo_id: t?.id ?? null, variante_id: null, cantidad: vals[`${s.id}|${g.id}|${t?.id ?? ''}`] === '' || vals[`${s.id}|${g.id}|${t?.id ?? ''}`] == null ? null : Number(vals[`${s.id}|${g.id}|${t?.id ?? ''}`]) }));
      await q(sb().rpc('guardar_parte_diario', { p_contrato_sede: s.id, p_fecha: fecha, p_items: items, p_fuente: 'parte diario' }));
      setMsg({ ok: true, t: `Parte de ${s.nombre} del ${fechaCorta(fecha)} guardado.` }); d.recargar();
    } catch (e) { setMsg({ ok: false, t: e.message }); }
    finally { setGuardando(null); }
  };
  const copiarCupos = (s) => setVals((o) => { const n = { ...o }; for (const { t, g } of cols) { const c = cupo(s, g, t); if (c > 0) n[`${s.id}|${g.id}|${t?.id ?? ''}`] = c; } return n; });
  const sedes = (d.datos ?? []).filter((s) => !filtro || s.nombre.toLowerCase().includes(filtro.toLowerCase()));
  // sedes con cambios respecto a lo guardado (para "Guardar todo")
  const modificadas = sedes.filter((s) => cols.some(({ t, g }) => { const v = vals[`${s.id}|${g.id}|${t?.id ?? ''}`]; const p = s.parte.find((x) => x.grupo_id === g.id && (x.tiempo_id ?? '') === (t?.id ?? ''))?.cantidad; return (v === '' || v == null ? null : Number(v)) !== (p ?? null); }));
  const guardarTodo = async () => { for (const s of modificadas) await guardarSede(s); if (modificadas.length) setMsg({ ok: true, t: `${modificadas.length} partes guardados del ${fechaCorta(fecha)}.` }); };
  const copiarTodas = () => { for (const s of sedes) copiarCupos(s); };
  const totParte = sedes.reduce((a, s) => a + s.parte.reduce((b, p) => b + p.cantidad, 0), 0);
  const totCupo = sedes.reduce((a, s) => a + s.cupos.reduce((b, c) => b + c.cantidad, 0), 0);
  return (
    <>
      <div className="row gap10 mb12 wrap">
        <button className="btn btn-s" onClick={() => setFecha(sumar(fecha, -1))}>◀</button>
        <input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
        <button className="btn btn-s" onClick={() => setFecha(sumar(fecha, 1))}>▶</button>
        <button className="btn btn-s" onClick={() => setFecha(hoy)}>Hoy</button>
        <input placeholder="Buscar sede…" value={filtro} onChange={(e) => setFiltro(e.target.value)} />
        <span className="crece" />
        <span className="small"><b>{num(totParte)}</b> en parte · {num(totCupo)} de cupo · {sedes.filter((s) => s.parte.length).length} de {sedes.length} sedes con parte</span>
        {puedeEditar && <><button className="btn btn-s" onClick={copiarTodas} title="Llenar todas las sedes visibles con su cupo">= cupo en todas</button><button className="btn btn-s btn-p" disabled={!modificadas.length || !!guardando} onClick={guardarTodo}>{guardando ? 'Guardando…' : `Guardar todo${modificadas.length ? ` (${modificadas.length})` : ''}`}</button></>}
      </div>
      <div className="aviso info small mb12">El parte del dia manda sobre el cupo: si hay parte, la programacion y la explosion de ese dia usan el parte; si no, el cupo vigente. Use "= cupo" para arrancar del cupo y corregir lo que cambio.</div>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {d.cargando && !d.datos ? <Cargando /> : (
        <div className="scroll">
          <table className="t t-partes">
            <thead><tr><th>Sede</th>{cols.map(({ t, g }) => <th key={`${t?.id}|${g.id}`} className="n">{t ? <><span className="muted small">{t.codigo}</span><br /></> : null}{g.codigo}</th>)}<th className="n">Parte</th><th className="n">Cupo</th><th /></tr></thead>
            <tbody>
              {sedes.map((s) => {
                const tp = cols.reduce((a, { t, g }) => a + (Number(vals[`${s.id}|${g.id}|${t?.id ?? ''}`]) || 0), 0);
                const tc = s.cupos.reduce((a, c) => a + c.cantidad, 0);
                return (
                  <tr key={s.id} className={!s.servicio ? 'sin-cupos' : ''}>
                    <td><b>{s.nombre}</b>{!s.servicio && <div className="small muted">sin servicio este dia</div>}{s.parte[0]?.fuente && s.parte[0].fuente !== 'parte diario' ? <div className="small muted">{s.parte[0].fuente}</div> : null}</td>
                    {cols.map(({ t, g }) => { const key = `${s.id}|${g.id}|${t?.id ?? ''}`; const c = cupo(s, g, t); if (porTiempo && c === 0 && !vals[key]) return <td key={key} className="n muted">·</td>; return (
                      <td key={key} className="n">{puedeEditar ? <input type="number" min="0" inputMode="numeric" style={{ width: 72, textAlign: 'right' }} placeholder={c ? String(c) : ''} value={vals[key] ?? ''} onChange={(e) => setVals((o) => ({ ...o, [key]: e.target.value }))} className={vals[key] !== undefined && vals[key] !== '' && Number(vals[key]) !== c ? 'cambiado' : ''} /> : (vals[key] ?? <span className="muted">{c}</span>)}</td>); })}
                    <td className="n"><b>{tp ? num(tp) : '·'}</b>{tp && tc && tp !== tc ? <div className={`small ${tp > tc ? 'bad' : 'muted'}`}>{tp > tc ? '+' : ''}{num(tp - tc)}</div> : null}</td>
                    <td className="n muted">{num(tc)}</td>
                    <td>{puedeEditar && <span className="row gap4 nowrap"><button className="btn btn-xs" onClick={() => copiarCupos(s)} title="Llenar con el cupo vigente">= cupo</button><button className="btn btn-xs btn-p" disabled={guardando === s.id} onClick={() => guardarSede(s)}>{guardando === s.id ? '…' : 'Guardar'}</button></span>}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
