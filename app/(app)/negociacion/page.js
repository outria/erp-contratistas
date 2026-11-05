'use client';
// M3 · Negociacion por volumen: proyeccion consolidada de varios contratos (de una o varias empresas del grupo) y la
// calculadora de cobertura: con X kilos, toneladas o contenedores de un producto, que programas cubro y hasta que fecha.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Panel, Campo, Estado, Tabla, Kpi } from '@/components/ui';
import { hoyISO, num, fechaCorta } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';
import { calcularPorTramos, diasEntre, sumarDias } from '@/lib/tramos';

const PRESETS = [15, 30, 60, 90, 180];
const CATEGORIAS = { proteinas: 'Proteinas', fruver: 'Frutas y verduras', abarrotes: 'Abarrotes', lacteos: 'Lacteos', panaderia: 'Panaderia', bebidas: 'Bebidas', aseo: 'Aseo', otros: 'Otros' };

export default function Negociacion() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const hoy = hoyISO();
  const id = params.get('id');
  const [nueva, setNueva] = useState(false);
  const [msg, setMsg] = useState(null);
  const [progreso, setProgreso] = useState(null);   // {id, texto, hechos, total, fin}
  const lista = useCarga(() => q(sb().rpc('consolidadas_lista', { p_empresa: empresaId })), [empresaId, progreso?.fin]);
  const contratos = useCarga(() => q(sb().rpc('contratos_grupo', { p_empresa: empresaId })), [empresaId]);
  const puedeCrear = puede('M3', 'ver') || puede('M2', 'ver');

  // calcula cada explosion de la consolidada por tramos y luego la cierra
  const calcular = async (pcId, explosiones, desde, hasta) => {
    const totalDias = explosiones.reduce((a, e) => a + diasEntre(desde, hasta), 0);
    let hechos = 0;
    setProgreso({ id: pcId, hechos: 0, total: totalDias, texto: 'Calculando…' });
    try {
      for (const ex of explosiones) {
        let base = hechos;
        await calcularPorTramos(ex.id, desde, hasta, ex.n_sedes, (p) => { hechos = base + p.hechos; setProgreso({ id: pcId, hechos, total: totalDias, texto: `${ex.empresa} · ${ex.contrato}: hasta el ${fechaCorta(p.hasta)}` }); });
        hechos = base + diasEntre(desde, hasta);
      }
      const est = await q(sb().rpc('cerrar_proyeccion_consolidada', { p_id: pcId }));
      setProgreso({ id: pcId, hechos: totalDias, total: totalDias, fin: Date.now() });
      if (est !== 'calculada') setMsg({ ok: false, t: 'Quedo algun contrato sin calcular por completo. Use Recalcular.' });
    } catch (e) {
      setMsg({ ok: false, t: `El calculo quedo parcial: ${e.message}. Puede recalcular.` });
      setProgreso({ id: pcId, hechos: 0, total: 0, fin: Date.now() });
    }
  };
  const crear = async (f) => {
    setMsg(null);
    try {
      const pcId = await q(sb().rpc('crear_proyeccion_consolidada', { p_contratos: f.contratos, p_desde: f.desde, p_hasta: f.hasta, p_nombre: f.nombre || null, p_incluye_dietas: f.dietas, p_incluye_propuestos: false }));
      setNueva(false);
      const det = await q(sb().rpc('consolidada_detalle', { p_id: pcId }));
      router.push(`/negociacion?id=${pcId}`);
      await calcular(pcId, det.explosiones, f.desde, f.hasta);
    } catch (e) { setMsg({ ok: false, t: e.message }); }
  };

  return (
    <>
      <Encabezado titulo="Negociacion por volumen" sub="Junte varios contratos (de una o varias empresas del grupo), proyecte el consumo del periodo y calcule, con la cantidad que le ofrecen o que quiere negociar, que programas cubre y hasta que fecha.">
        <Link href="/explosion" className="btn">Explosion por contrato</Link>
        {puedeCrear && !id && <button className="btn btn-p" onClick={() => setNueva(true)}>Nueva proyeccion consolidada</button>}
      </Encabezado>
      {!id && <Consejo>
        Sirve para negociar precio por volumen o una importacion por contenedores: la proyeccion suma el consumo diario de los contratos elegidos por producto maestro (el catalogo unificado del grupo) y la calculadora reparte la cantidad dia a dia como la consume cada programa, asi se ve hasta que fecha alcanza y cuanto le toca a cada contrato. Cuando existan las bodegas (logistica) se podra agrupar por la bodega a la que llega el producto.
      </Consejo>}
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {!id && (
        <>
          {lista.err && <Falla msg={lista.err} />}
          <div className="card">
            {lista.cargando && !lista.datos ? <Cargando /> : (
              <Tabla cols={[
                { t: 'Proyeccion', r: (r) => <><b>{r.nombre ?? 'Consolidada'}</b><div className="small muted">{r.empresas}</div></> },
                { t: 'Periodo', r: (r) => <>{fechaCorta(r.desde)} a {fechaCorta(r.hasta)}<div className="small muted">{r.dias} dias · {r.n_contratos} contratos</div></> },
                { t: 'Raciones', n: true, r: (r) => r.raciones ? num(r.raciones) : '·' },
                { t: 'Estado', r: (r) => <Estado e={progreso?.id === r.id && !progreso.fin ? 'calculando' : r.estado} /> },
                { t: 'Creada', r: (r) => <span className="small">{fechaCorta(r.creado_en?.slice(0, 10))}</span> },
                { t: '', r: (r) => <Link href={`/negociacion?id=${r.id}`} className="btn btn-xs">Abrir</Link> },
              ]} filas={lista.datos ?? []} vacio="Todavia no hay proyecciones consolidadas. Cree la primera." />
            )}
          </div>
        </>
      )}
      {id && <Detalle id={id} progreso={progreso?.id === id ? progreso : null} onRecalcular={(det) => calcular(id, det.explosiones, det.proyeccion.desde, det.proyeccion.hasta)} puedeCrear={puedeCrear} setMsg={setMsg} />}
      {nueva && <FormNueva hoy={hoy} contratos={contratos.datos ?? []} onCerrar={() => setNueva(false)} onCrear={crear} />}
    </>
  );
}

function FormNueva({ hoy, contratos, onCerrar, onCrear }) {
  const [preset, setPreset] = useState(30);
  const [desde, setDesde] = useState(sumarDias(hoy, 1));
  const [hasta, setHasta] = useState(sumarDias(hoy, 30));
  const [sel, setSel] = useState(() => contratos.filter((c) => c.estado === 'vigente').map((c) => c.id));
  const [dietas, setDietas] = useState(true);
  const [nombre, setNombre] = useState('');
  const [enviando, setEnviando] = useState(false);
  useEffect(() => { setSel(contratos.filter((c) => c.estado === 'vigente').map((c) => c.id)); }, [contratos]);
  const empresas = useMemo(() => { const m = new Map(); for (const c of contratos) { if (!m.has(c.empresa)) m.set(c.empresa, []); m.get(c.empresa).push(c); } return [...m.entries()]; }, [contratos]);
  const dias = diasEntre(desde, hasta);
  const sedes = contratos.filter((c) => sel.includes(c.id)).reduce((a, c) => a + c.sedes, 0);
  const cupos = contratos.filter((c) => sel.includes(c.id)).reduce((a, c) => a + Number(c.cupos), 0);
  return (
    <Panel titulo="Nueva proyeccion consolidada" sub="Elija los contratos y el periodo; el calculo corre por tramos, contrato por contrato." onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={!sel.length || dias < 1 || enviando} onClick={async () => { setEnviando(true); await onCrear({ contratos: sel, desde, hasta, dietas, nombre }); setEnviando(false); }}>{enviando ? 'Creando…' : `Proyectar ${dias} dias`}</button>}>
      <Campo l="Periodo">
        <div className="row gap6 wrap">{PRESETS.map((n) => <button key={n} className={`btn btn-s${preset === n ? ' btn-p' : ''}`} onClick={() => { setPreset(n); setHasta(sumarDias(desde, n - 1)); }}>{n} dias</button>)}</div>
      </Campo>
      <div className="row gap10 mt8 mb12">
        <Campo l="Desde" req><input type="date" value={desde} onChange={(e) => { setDesde(e.target.value); if (preset) setHasta(sumarDias(e.target.value, preset - 1)); }} /></Campo>
        <Campo l="Hasta" req><input type="date" value={hasta} min={desde} onChange={(e) => { setHasta(e.target.value); setPreset(0); }} /></Campo>
      </div>
      <Campo l={`Contratos (${sel.length} elegidos · ${num(sedes)} sedes · ${num(cupos)} cupos)`} className="mb12">
        <div style={{ border: '1px solid var(--linea)', borderRadius: 8, padding: 8, maxHeight: 300, overflow: 'auto' }}>
          {empresas.map(([emp, cs]) => (
            <div key={emp} className="mb8">
              <label className="row gap6"><input type="checkbox" checked={cs.every((c) => sel.includes(c.id))} onChange={(e) => setSel(e.target.checked ? [...new Set([...sel, ...cs.map((c) => c.id)])] : sel.filter((x) => !cs.find((c) => c.id === x)))} /><b>{emp}</b></label>
              {cs.map((c) => <label key={c.id} className="row gap6 small" style={{ paddingLeft: 22 }}><input type="checkbox" checked={sel.includes(c.id)} onChange={(e) => setSel(e.target.checked ? [...sel, c.id] : sel.filter((x) => x !== c.id))} /> {c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad} · {c.sedes} sedes · {num(c.cupos)} cupos{c.estado !== 'vigente' ? ` · ${c.estado}` : ''}</label>)}
            </div>
          ))}
          {!contratos.length && <div className="muted small">No hay contratos visibles en el grupo. Si la empresa no esta en un grupo, pidale al administrador que la asigne.</div>}
        </div>
      </Campo>
      <label className="row gap6 mb12"><input type="checkbox" checked={dietas} onChange={(e) => setDietas(e.target.checked)} /> Incluir dietas terapeuticas</label>
      <Campo l="Nombre (opcional)"><input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="ej. Negociacion pechuga contenedor diciembre" /></Campo>
    </Panel>
  );
}

function Detalle({ id, progreso, onRecalcular, puedeCrear, setMsg }) {
  const calculando = progreso && !progreso.fin;
  const d = useCarga(() => q(sb().rpc('consolidada_detalle', { p_id: id })), [id, progreso?.fin]);
  const [filtro, setFiltro] = useState('');
  const [cat, setCat] = useState('');
  const [calc, setCalc] = useState(null);   // producto elegido para la calculadora
  const p = d.datos?.proyeccion;
  const productos = useMemo(() => (d.datos?.productos ?? []).filter((x) => (!cat || x.categoria === cat) && (!filtro || x.maestro_nombre.toLowerCase().includes(filtro.toLowerCase()))), [d.datos, cat, filtro]);
  const categorias = useMemo(() => { const m = new Map(); for (const x of d.datos?.productos ?? []) m.set(x.categoria, (m.get(x.categoria) ?? 0) + 1); return [...m.entries()]; }, [d.datos]);
  const anular = async () => { if (!confirm('¿Anular esta proyeccion consolidada?')) return; try { await q(sb().rpc('anular_consolidada', { p_id: id })); setMsg({ ok: true, t: 'Proyeccion anulada.' }); d.recargar(); } catch (e) { setMsg({ ok: false, t: e.message }); } };
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    const emps = [...new Set((d.datos.productos ?? []).flatMap((x) => x.por_empresa.map((e) => `${e.empresa} · ${e.contrato}`)))];
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Codigo', 'Producto', 'Categoria', 'Total compra', 'Unidad', 'Promedio por dia', ...emps],
      ...(d.datos.productos ?? []).map((x) => [x.maestro_codigo, x.maestro_nombre, x.categoria, x.cantidad_compra, x.unidad_compra, Math.round((x.promedio_dia_base / (x.cantidad_base / x.cantidad_compra || 1)) * 100) / 100, ...emps.map((k) => { const e = x.por_empresa.find((y) => `${y.empresa} · ${y.contrato}` === k); return e ? Math.round(e.cantidad / (x.cantidad_base / x.cantidad_compra || 1) * 100) / 100 : ''; })])]), 'Consolidado');
    XLSX.writeFile(wb, `Consolidada_${p.nombre ?? id}.xlsx`);
  };
  if (d.err) return <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  const raciones = d.datos.explosiones.reduce((a, e) => a + (e.raciones ?? 0), 0);
  return (
    <>
      <div className="row between mb12 wrap">
        <div className="row gap8"><Link href="/negociacion" className="btn btn-s">← Todas</Link><h2 className="m0">{p.nombre ?? 'Proyeccion consolidada'}</h2><Estado e={calculando ? 'calculando' : p.estado} /></div>
        <div className="row gap6">
          {p.estado === 'calculada' && <button className="btn btn-s" onClick={descargar}>Descargar Excel</button>}
          {puedeCrear && !calculando && p.estado !== 'anulada' && <button className="btn btn-s" onClick={() => onRecalcular(d.datos)}>Recalcular</button>}
          {puedeCrear && !calculando && p.estado !== 'anulada' && <button className="btn btn-s btn-x" onClick={anular}>Anular</button>}
        </div>
      </div>
      {calculando && <div className="aviso info mb12"><div className="row between"><span>{progreso.texto}</span><span>{progreso.hechos} / {progreso.total}</span></div><div className="barra mt8"><i style={{ width: `${(100 * progreso.hechos) / Math.max(1, progreso.total)}%` }} /></div></div>}
      <div className="grid g4 mb12">
        <Kpi v={`${fechaCorta(p.desde)} a ${fechaCorta(p.hasta)}`} l={`${p.dias} dias`} />
        <Kpi v={d.datos.explosiones.length} l={`contratos · ${d.datos.explosiones.reduce((a, e) => a + e.n_sedes, 0)} sedes`} />
        <Kpi v={raciones} l="raciones-dia proyectadas" />
        <Kpi v={d.datos.productos.length} l="productos (catalogo maestro)" />
      </div>
      <div className="card mb12">
        <Tabla cols={[
          { t: 'Empresa', k: 'empresa' }, { t: 'Contrato', r: (e) => <>{e.contrato}<div className="small muted">{MODALIDADES[e.modalidad] ?? e.modalidad} · {e.n_sedes} sedes</div></> },
          { t: 'Raciones', n: true, r: (e) => e.raciones ? num(e.raciones) : '·' }, { t: 'Dias calculados', n: true, r: (e) => `${e.dias_cubiertos} / ${p.dias}` },
          { t: 'Estado', r: (e) => <Estado e={e.estado} /> }, { t: '', r: (e) => <Link href={`/explosion?id=${e.id}`} className="btn btn-xs">Ver explosion</Link> },
        ]} filas={d.datos.explosiones} />
      </div>
      {p.estado === 'calculada' && (
        <div className="card">
          <div className="row gap8 mb12 wrap">
            <h3 className="m0">Consumo del periodo por producto</h3>
            <span className="muted small">Haga clic en "Calcular cobertura" para simular una cantidad.</span>
            <span className="crece" />
            <input placeholder="Buscar producto…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 200 }} />
            <button className={`btn btn-xs${cat === '' ? ' btn-p' : ''}`} onClick={() => setCat('')}>Todas</button>
            {categorias.map(([c, n]) => <button key={c} className={`btn btn-xs${cat === c ? ' btn-p' : ''}`} onClick={() => setCat(c)}>{CATEGORIAS[c] ?? c} ({n})</button>)}
          </div>
          <Tabla cols={[
            { t: 'Producto', r: (x) => <><b>{x.maestro_nombre}</b><div className="small muted">{CATEGORIAS[x.categoria] ?? x.categoria}{x.sin_maestro ? ' · sin catalogo maestro' : ''}{x.mapeo_pendiente ? ' · mapeo por aprobar' : ''}</div></> },
            { t: 'Total periodo', n: true, r: (x) => <b>{num(x.cantidad_compra, 1)} {x.unidad_compra}</b> },
            { t: 'Por dia', n: true, r: (x) => `${num(x.promedio_dia_base / (x.cantidad_base / x.cantidad_compra || 1), 2)} ${x.unidad_compra}` },
            { t: 'Por contrato', r: (x) => <span className="small">{x.por_empresa.map((e) => `${e.empresa} ${num(e.cantidad / (x.cantidad_base / x.cantidad_compra || 1), 0)}`).join(' · ')}</span> },
            { t: '', r: (x) => <button className="btn btn-xs btn-p" onClick={() => setCalc(x)}>Calcular cobertura</button> },
          ]} filas={productos} idKey="maestro_codigo" vacio="Sin productos." />
        </div>
      )}
      {calc && <Calculadora id={id} det={d.datos} prod={calc} onCerrar={() => setCalc(null)} />}
    </>
  );
}

function Calculadora({ id, det, prod, onCerrar }) {
  const factor = prod.cantidad_base / prod.cantidad_compra || 1;   // unidades base por unidad de compra
  const [modo, setModo] = useState('unidad');       // unidad | toneladas | contenedores
  const [cant, setCant] = useState(Math.round(prod.cantidad_compra));
  const [kgCont, setKgCont] = useState(24000);
  const [nCont, setNCont] = useState(1);
  const [sel, setSel] = useState(det.explosiones.map((e) => e.contrato_id));
  const [res, setRes] = useState(null);
  const [err, setErr] = useState(null);
  const [calculando, setCalculando] = useState(false);
  const cantidad = modo === 'unidad' ? Number(cant) : modo === 'toneladas' ? Number(cant) * 1000 : Number(nCont) * Number(kgCont);
  const maestro = prod.maestro_id ?? null;
  const calcular = async () => {
    setCalculando(true); setErr(null);
    try { setRes(await q(sb().rpc('cobertura_volumen', { p_id: id, p_maestro: maestro, p_cantidad: cantidad, p_contratos: sel.length === det.explosiones.length ? null : sel }))); }
    catch (e) { setErr(e.message); }
    finally { setCalculando(false); }
  };
  useEffect(() => { if (maestro) calcular(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, []);
  return (
    <Panel titulo={`Cobertura · ${prod.maestro_nombre}`} sub={`Consumo proyectado: ${num(prod.cantidad_compra, 1)} ${prod.unidad_compra} en ${det.proyeccion.dias} dias`} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={calculando || !cantidad || !sel.length || !maestro} onClick={calcular}>{calculando ? 'Calculando…' : 'Calcular'}</button>}>
      {!maestro && <div className="aviso bad mb12">Este producto no esta en el catalogo maestro del grupo; apruebe el mapeo en Maestros para poder consolidarlo.</div>}
      <Campo l="Cantidad a negociar" className="mb8">
        <div className="row gap6 wrap">
          <select value={modo} onChange={(e) => setModo(e.target.value)}><option value="unidad">en {prod.unidad_compra}</option>{prod.unidad_compra === 'kg' && <option value="toneladas">en toneladas</option>}{prod.unidad_compra === 'kg' && <option value="contenedores">en contenedores</option>}</select>
          {modo !== 'contenedores' && <input type="number" min="0" value={cant} onChange={(e) => setCant(e.target.value)} style={{ width: 140 }} />}
          {modo === 'contenedores' && <><input type="number" min="1" value={nCont} onChange={(e) => setNCont(e.target.value)} style={{ width: 70 }} title="Contenedores" /><span>x</span><input type="number" min="0" step="500" value={kgCont} onChange={(e) => setKgCont(e.target.value)} style={{ width: 110 }} title="kg por contenedor" /><span className="small muted">kg c/u</span></>}
          <span className="muted small">= {num(cantidad, 0)} {prod.unidad_compra}</span>
        </div>
      </Campo>
      <Campo l="Programas a cubrir" className="mb12">
        <div className="stack gap4">{det.explosiones.map((e) => <label key={e.contrato_id} className="row gap6 small"><input type="checkbox" checked={sel.includes(e.contrato_id)} onChange={(x) => setSel(x.target.checked ? [...sel, e.contrato_id] : sel.filter((y) => y !== e.contrato_id))} /> {e.empresa} · {e.contrato} <span className="muted">({MODALIDADES[e.modalidad] ?? e.modalidad})</span></label>)}</div>
      </Campo>
      {err && <div className="aviso bad mb12">{err}</div>}
      {res && (
        <>
          {res.sin_consumo ? <div className="aviso mb12">Los programas elegidos no consumen este producto en el periodo.</div> : (
            <div className="card mb12" style={{ background: 'var(--fondo-2)' }}>
              <div className="kpi"><span className="v">{res.hasta ? `hasta el ${fechaCorta(res.hasta)}` : 'no alcanza ni un dia'}</span><span className="l">{res.dias} dias de cobertura{res.extrapolado ? ' (mas alla del periodo proyectado, estimado con el promedio diario)' : ''}</span></div>
              <div className="row gap12 small mt8 wrap">
                <span><b>{num(res.consumo_diario, 1)}</b> {res.unidad} por dia entre los programas elegidos</span>
                <span><b>{num(res.consumo_cubierto, 0)}</b> {res.unidad} consumidos</span>
                {res.sobrante > 0 && <span><b>{num(res.sobrante, 0)}</b> {res.unidad} quedan para el dia siguiente</span>}
              </div>
            </div>
          )}
          <h3 className="mt8">Como se reparte</h3>
          <Tabla cols={[{ t: 'Programa', r: (c) => <>{c.empresa}<div className="small muted">{c.contrato}</div></> }, { t: 'Por dia', n: true, r: (c) => `${num(c.promedio_dia, 1)} ${res.unidad}` }, { t: 'Participacion', n: true, r: (c) => `${num(c.participacion, 1)} %` }, { t: 'Le toca', n: true, r: (c) => <b>{num(c.le_toca, 0)} {res.unidad}</b> }]} filas={res.por_contrato} idKey="contrato_id" />
          {res.por_mes?.length > 1 && <><h3 className="mt12">Consumo proyectado por mes</h3><Tabla cols={[{ t: 'Mes', k: 'mes' }, { t: 'Cantidad', n: true, r: (m) => `${num(m.cantidad, 0)} ${res.unidad}` }]} filas={res.por_mes.map((m) => ({ ...m, id: m.mes }))} /></>}
          <div className="small muted mt12">El reparto sigue la proporcion en que cada programa consume el producto; cuando haya bodegas, el despacho real sale de ahi. El precio y el presupuesto llegan con el master de precios.</div>
        </>
      )}
    </Panel>
  );
}
