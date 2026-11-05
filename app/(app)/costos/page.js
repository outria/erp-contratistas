'use client';
// M3 · Tablero de costo por tiempo de comida y componente: para un ciclo de menus y un grupo de referencia, el costo por
// racion de cada casilla (menu x tiempo x componente) con el master de precios; resumen lateral (menu y tiempo mas y menos
// costosos, por tiempo cual menu, componente que mas pesa) y sugerencias de intercambio que bajan el costo.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga, esDemo } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado, Modal } from '@/components/ui';
import { num, cop, fechaCorta, hoyISO } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';

export default function Costos() {
  const { empresaId, empresa, puede } = useApp();
  const [contratoId, setContratoId] = useState(null);
  const [cicloId, setCicloId] = useState('');
  const [grupoId, setGrupoId] = useState('');
  const [fecha, setFecha] = useState(hoyISO());
  const [vista, setVista] = useState('tiempos');     // tiempos | componentes
  const [celda, setCelda] = useState(null);
  const [msg, setMsg] = useState(null);
  const [simulando, setSimulando] = useState(false);
  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero, modalidad, estado').eq('empresa_id', empresaId).in('estado', ['vigente', 'borrador', 'suspendido']).order('numero')).then((cs) => [...cs].sort((a, b) => (a.estado === 'vigente' ? 0 : 1) - (b.estado === 'vigente' ? 0 : 1))), [empresaId]);
  useEffect(() => { if (contratos.datos?.length && !contratos.datos.find((c) => c.id === contratoId)) { setContratoId(contratos.datos[0].id); setCicloId(''); } }, [contratos.datos, contratoId]);
  const min = useCarga(async () => contratoId ? q(sb().rpc('minutas_contrato', { p_contrato: contratoId })) : null, [contratoId]);
  useEffect(() => { const cs = (min.datos?.ciclos ?? []).filter((c) => c.estado !== 'anulado'); if (cs.length && !cs.find((c) => c.id === cicloId)) setCicloId((cs.find((c) => c.estado === 'vigente') ?? cs[0]).id); }, [min.datos, cicloId]);
  const d = useCarga(async () => cicloId ? q(sb().rpc('costo_ciclo', { p_ciclo: cicloId, p_grupo: grupoId || null, p_fecha: fecha, p_top: 15 })) : null, [cicloId, grupoId, fecha]);
  const datos = d.datos;
  const tiempos = useMemo(() => (min.datos?.tiempos ?? []).filter((t) => datos?.celdas?.some((c) => c.tiempo_id === t.id)), [min.datos, datos]);
  const componentes = min.datos?.componentes ?? [];
  const celdasPor = useMemo(() => { const m = {}; (datos?.celdas ?? []).forEach((c) => { m[`${c.dia}|${c.tiempo_id}|${c.componente_id}`] = c; }); return m; }, [datos]);
  const maxMenu = useMemo(() => Math.max(1, ...(datos?.menus ?? []).map((m) => Number(m.costo) || 0)), [datos]);
  const simular = async () => {
    setSimulando(true);
    try { const r = await q(sb().rpc('simular_precios_demo', { p_empresa: empresaId })); setMsg({ ok: true, t: `${r.precios_creados} precios simulados cargados (proveedor "SIMULADO (practica)"). Son solo para ver el tablero; se reemplazan con las listas reales.` }); d.recargar(); }
    catch (e) { setMsg({ ok: false, t: e.message }); } finally { setSimulando(false); }
  };
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Menu', ...tiempos.map((t) => t.nombre), 'Total racion-dia'], ...(datos.menus ?? []).map((m) => [m.dia, ...tiempos.map((t) => m.por_tiempo?.[t.id] ?? null), m.costo])]), 'Por tiempo');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Menu', 'Tiempo', 'Componente', 'Preparacion', 'Costo por racion', 'Ingredientes', 'Sin precio'], ...(datos.celdas ?? []).map((c) => [c.dia, tiempos.find((t) => t.id === c.tiempo_id)?.nombre, componentes.find((k) => k.id === c.componente_id)?.nombre, c.preparacion, c.costo, c.n_ing, c.sin_precio])]), 'Por componente');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Menu', 'Tiempo', 'Componente', 'Actual', 'Costo actual', 'Alternativa', 'Costo alternativa', 'Ahorro por racion', 'Raciones dia', 'Ahorro por vuelta de ciclo', 'Ahorro mes'], ...(datos.sugerencias ?? []).map((s) => [s.dia, s.tiempo, s.componente, s.actual, s.actual_costo, s.alternativa, s.alternativa_costo, s.ahorro_racion, s.raciones_dia, s.ahorro_ciclo, s.ahorro_mes])]), 'Sugerencias');
    XLSX.writeFile(wb, `Costo_ciclo_${datos.ciclo.codigo}_${fecha}.xlsx`);
  };
  const r = datos?.resumen;
  const tiempoMasCaro = r?.por_tiempo?.length ? [...r.por_tiempo].sort((a, b) => (b.promedio ?? 0) - (a.promedio ?? 0))[0] : null;
  const tiempoMasBarato = r?.por_tiempo?.length ? [...r.por_tiempo].sort((a, b) => (a.promedio ?? 0) - (b.promedio ?? 0))[0] : null;

  return (
    <>
      <Encabezado titulo="Costo por tiempo de comida y componente" sub="Cuanto cuesta cada racion de cada menu del ciclo, tiempo por tiempo y componente por componente, con los precios del master; y que intercambios bajarian el costo.">
        <Link href="/precios" className="btn">Master de precios</Link>
        <Link href="/minutas" className="btn">Minutas</Link>
        {datos && <button className="btn" onClick={descargar}>Descargar Excel</button>}
      </Encabezado>
      <Consejo>
        El costo de una casilla es la suma de sus ingredientes crudos (con los gramajes vigentes del grupo de referencia) por el <b>mejor precio vigente</b> por unidad base del master (homologado, sin bloqueo). Una casilla queda en gris si algun ingrediente no tiene precio: ese costo esta incompleto. El resumen lateral dice cual es el menu y el tiempo mas y menos costosos, y las <b>sugerencias</b> muestran, por casilla, la alternativa de la misma familia de intercambio mas barata, con el ahorro por racion, por vuelta del ciclo y por mes segun la poblacion vigente (respete las reglas de variedad al aplicarlas).
      </Consejo>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="row gap10 mb12 wrap">
        {contratos.datos?.length > 1 && <select value={contratoId ?? ''} onChange={(e) => { setContratoId(e.target.value); setCicloId(''); setGrupoId(''); }}>{contratos.datos.map((c) => <option key={c.id} value={c.id}>{c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad}</option>)}</select>}
        <select value={cicloId} onChange={(e) => setCicloId(e.target.value)}>{(min.datos?.ciclos ?? []).filter((c) => c.estado !== 'anulado').map((c) => <option key={c.id} value={c.id}>{c.codigo} · {c.nombre} ({c.estado})</option>)}</select>
        <select value={grupoId} onChange={(e) => setGrupoId(e.target.value)}><option value="">Grupo de referencia: el de mas cupos</option>{(min.datos?.grupos ?? []).map((g) => <option key={g.id} value={g.id}>{g.nombre}</option>)}</select>
        <label className="row gap4 small">Precios del <input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label>
        {esDemo(empresa) && puede('M3', 'crear') && <button className="btn btn-s" disabled={simulando} onClick={simular}>{simulando ? 'Cargando…' : 'Cargar precios simulados (practica)'}</button>}
      </div>
      {(d.err || min.err) && <Falla msg={d.err ?? min.err} />}
      {!datos ? (cicloId ? <Cargando /> : <div className="card vacio">Este contrato no tiene ciclos de menu. Cree uno en Minutas.</div>) : (
        <>
          {r.con_simulados && <div className="aviso warn mb12">Hay precios SIMULADOS en el calculo (proveedor de practica). Sirven para ver la mecanica, no para decidir.</div>}
          <div className="grid g4 mb12">
            <div className="card kpi"><span className="v">{cop(r.costo_racion_dia_prom)}</span><span className="l">costo promedio de la racion-dia ({tiempos.map((t) => t.nombre.toLowerCase()).join(' + ')}) · {datos.grupo?.nombre}</span></div>
            <div className="card kpi"><span className="v">{r.menu_mas_caro ? `Menu ${r.menu_mas_caro.dia}` : '·'}</span><span className="l">el mas costoso · {cop(r.menu_mas_caro?.costo)}</span></div>
            <div className="card kpi"><span className="v">{r.menu_mas_barato ? `Menu ${r.menu_mas_barato.dia}` : '·'}</span><span className="l">el menos costoso · {cop(r.menu_mas_barato?.costo)}</span></div>
            <div className={`card kpi${r.casillas_sin_precio ? ' warn' : ''}`}><span className="v">{num(r.casillas_sin_precio)}</span><span className="l">casillas con ingredientes sin precio{r.casillas_sin_receta ? ` · ${r.casillas_sin_receta} sin receta` : ''}</span></div>
          </div>
          <div className="costos-layout">
            <div className="card">
              <div className="row between mb8 wrap gap6">
                <div className="tabs m0" style={{ marginBottom: 0 }}><button className={vista === 'tiempos' ? 'on' : ''} onClick={() => setVista('tiempos')}>Menu x tiempo</button><button className={vista === 'componentes' ? 'on' : ''} onClick={() => setVista('componentes')}>Menu x tiempo x componente</button></div>
                <span className="small muted">{datos.ciclo.codigo} · {datos.ciclo.n_menus} menus · precios del {fechaCorta(datos.fecha)}</span>
              </div>
              <div className="scroll">
                {vista === 'tiempos' ? (
                  <table className="t t-costos">
                    <thead><tr><th>Menu</th>{tiempos.map((t) => <th key={t.id} className="n">{t.nombre}<div className="small muted">{datos.raciones_dia?.[t.id] ? `${num(datos.raciones_dia[t.id])} rac/dia` : ''}</div></th>)}<th className="n">Racion-dia</th><th style={{ width: 160 }} /></tr></thead>
                    <tbody>
                      {datos.menus.map((m) => (
                        <tr key={m.dia} className={m.dia === r.menu_mas_caro?.dia ? 'caro' : m.dia === r.menu_mas_barato?.dia ? 'barato' : ''}>
                          <td><b>Menu {m.dia}</b></td>
                          {tiempos.map((t) => { const pt = r.por_tiempo.find((x) => x.tiempo_id === t.id); const v = m.por_tiempo?.[t.id]; return <td key={t.id} className={`n ${pt?.mas_caro?.dia === m.dia ? 'bad' : pt?.mas_barato?.dia === m.dia ? 'ok' : ''}`}>{v != null ? cop(v) : '·'}</td>; })}
                          <td className="n"><b>{cop(m.costo)}</b>{m.sin_precio > 0 && <div className="small warn">{m.sin_precio} sin precio</div>}</td>
                          <td><div className="barra-costo"><span style={{ width: `${100 * (Number(m.costo) || 0) / maxMenu}%` }} /></div></td>
                        </tr>))}
                    </tbody>
                    <tfoot><tr><td>Promedio</td>{tiempos.map((t) => <td key={t.id} className="n">{cop(r.por_tiempo.find((x) => x.tiempo_id === t.id)?.promedio)}</td>)}<td className="n"><b>{cop(r.costo_racion_dia_prom)}</b></td><td /></tr></tfoot>
                  </table>
                ) : (
                  <table className="t t-costos small">
                    <thead><tr><th>Menu</th>{tiempos.map((t) => componentes.filter((k) => k.tiempo_id === t.id).map((k) => <th key={k.id} className="n" title={t.nombre}>{k.nombre}<div className="muted" style={{ fontWeight: 400 }}>{t.nombre}</div></th>))}<th className="n">Total</th></tr></thead>
                    <tbody>
                      {datos.menus.map((m) => (
                        <tr key={m.dia}>
                          <td><b>{m.dia}</b></td>
                          {tiempos.map((t) => componentes.filter((k) => k.tiempo_id === t.id).map((k) => { const c = celdasPor[`${m.dia}|${t.id}|${k.id}`]; return <td key={k.id} className={`n celda${c?.sin_precio ? ' incompleta' : ''}`} onClick={c ? () => setCelda({ ...c, tiempo: t.nombre, componente: k.nombre }) : undefined} title={c?.preparacion ?? ''}>{c ? <>{cop(c.costo)}<div className="muted trunc">{c.preparacion ?? 'sin receta'}</div></> : '·'}</td>; }))}
                          <td className="n"><b>{cop(m.costo)}</b></td>
                        </tr>))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
            <aside className="card resumen-costos">
              <h3 className="m0">Resumen del ciclo</h3>
              <p className="small">De los <b>{datos.ciclo.n_menus} menus</b> de este ciclo, el mas costoso es el <b>menu {r.menu_mas_caro?.dia}</b> ({cop(r.menu_mas_caro?.costo)} por racion-dia) y el menos costoso el <b>menu {r.menu_mas_barato?.dia}</b> ({cop(r.menu_mas_barato?.costo)}).</p>
              {tiempoMasCaro && <p className="small">El tiempo que mas pesa es <b>{tiempoMasCaro.tiempo.toLowerCase()}</b> ({cop(tiempoMasCaro.promedio)} en promedio) y el que menos, <b>{tiempoMasBarato.tiempo.toLowerCase()}</b> ({cop(tiempoMasBarato.promedio)}).</p>}
              <ul className="small lista-limpia">
                {r.por_tiempo.map((t) => <li key={t.tiempo_id}><b>{t.tiempo}</b>: el mas caro es el del menu {t.mas_caro?.dia} ({cop(t.mas_caro?.costo)}), el mas barato el del menu {t.mas_barato?.dia} ({cop(t.mas_barato?.costo)}).{t.componente_mas_caro ? ` Lo que mas pesa: ${t.componente_mas_caro.componente.toLowerCase()} (${cop(t.componente_mas_caro.promedio)} en promedio).` : ''}</li>)}
              </ul>
              <h4 className="mb8">Componentes que mas pesan</h4>
              <ul className="small lista-limpia">{r.componentes.slice(0, 6).map((c) => <li key={c.componente_id}>{c.componente} <span className="muted">({tiempos.find((t) => t.id === c.tiempo_id)?.nombre.toLowerCase()})</span>: {cop(c.promedio)}</li>)}</ul>
              {r.sin_precio.length > 0 && <><h4 className="mb8">Sin precio en el master</h4><ul className="small lista-limpia">{r.sin_precio.slice(0, 10).map((p) => <li key={p.producto}>{p.producto} <span className="muted">({p.casillas} casillas)</span></li>)}</ul><Link href="/precios" className="btn btn-xs">Registrar precios</Link></>}
            </aside>
          </div>
          <div className="card mt12">
            <div className="row between wrap gap6 mb8">
              <div><h3 className="m0">Sugerencias de intercambio</h3><div className="small muted">Alternativas de la misma familia que cuestan menos. Con la poblacion vigente ({Object.values(datos.raciones_dia ?? {}).length ? num(Math.max(...Object.values(datos.raciones_dia))) : '·'} raciones por tiempo al dia) y {datos.dias_mes} dias de servicio al mes.</div></div>
              {Number(datos.ahorro_total_mes) > 0 && <div className="right"><div className="small muted">Si se aplicaran todas</div><b style={{ fontSize: 20 }}>{cop(datos.ahorro_total_mes)}</b><div className="small muted">menos al mes</div></div>}
            </div>
            <Tabla cols={[
              { t: 'Donde', r: (s) => <><b>Menu {s.dia}</b> · {s.tiempo}<div className="small muted">{s.componente}</div></> },
              { t: 'Hoy', r: (s) => <>{s.actual}<div className="small muted">{cop(s.actual_costo)} por racion</div></> },
              { t: 'Cambiar por', r: (s) => <><b>{s.alternativa}</b><div className="small muted">{cop(s.alternativa_costo)} por racion</div></> },
              { t: 'Ahorro / racion', n: true, r: (s) => <span className="ok"><b>{cop(s.ahorro_racion)}</b><div className="small muted">{num(100 * s.ahorro_racion / s.actual_costo)} %</div></span> },
              { t: 'Por vuelta del ciclo', n: true, r: (s) => cop(s.ahorro_ciclo) },
              { t: 'Al mes', n: true, r: (s) => <b>{cop(s.ahorro_mes)}</b> },
              { t: '', r: (s) => <Link href={`/minutas?contrato=${datos.ciclo.contrato_id}&ciclo=${datos.ciclo.id}`} className="btn btn-xs">Ir al ciclo</Link> },
            ]} filas={datos.sugerencias} idKey="item_id" vacio="Sin alternativas mas baratas con precio: registre mas opciones en las familias de intercambio o mas precios en el master." />
          </div>
        </>
      )}
      {celda && <Modal titulo={`Menu ${celda.dia} · ${celda.tiempo} · ${celda.componente}`} onCerrar={() => setCelda(null)}>
        <p><b>{celda.preparacion}</b> · {cop(celda.costo)} por racion{celda.sin_precio ? <span className="chip warn" style={{ marginLeft: 8 }}>{celda.sin_precio} ingrediente(s) sin precio</span> : null}</p>
        <Tabla cols={[
          { t: 'Ingrediente', r: (i) => <>{i.producto}{i.principal && <span className="chip info" style={{ marginLeft: 6 }}>principal</span>}</> },
          { t: 'Crudo / racion', n: true, r: (i) => `${num(i.crudo, 1)} ${i.unidad}` },
          { t: `Precio / ${celda.ingredientes?.[0]?.unidad === 'und' ? 'und' : 'kg o l'}`, n: true, r: (i) => i.precio_base != null ? <>{cop(i.unidad === 'und' ? i.precio_base : i.precio_base * 1000)}<div className="small muted">{i.proveedor}{i.simulado ? ' · SIMULADO' : ''}</div></> : <span className="chip warn">sin precio</span> },
          { t: 'Costo', n: true, r: (i) => <b>{cop(i.costo)}</b> },
        ]} filas={celda.ingredientes ?? []} idKey="producto" />
      </Modal>}
    </>
  );
}
