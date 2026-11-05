'use client';
// M2 · Explosion de materiales: de la programacion y la poblacion a los kilos por producto.
// Una proyeccion se calcula por tramos (varias llamadas cortas) para no chocar con el limite de 8 s;
// cuando esta calculada se puede convertir en requerimiento, aprobar y enviar a compras.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Panel, Campo, Estado, Tabla, Kpi } from '@/components/ui';
import { unidadCupos } from '@/components/programacion';
import { hoyISO, num, fechaCorta, fechaISO, desdeISO } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';

const sumar = (iso, n) => { const d = desdeISO(iso); d.setDate(d.getDate() + n); return fechaISO(d); };
const PRESETS = [8, 15, 30, 90];
const CATEGORIAS = { proteinas: 'Proteinas', fruver: 'Frutas y verduras', abarrotes: 'Abarrotes', lacteos: 'Lacteos', panaderia: 'Panaderia', bebidas: 'Bebidas', aseo: 'Aseo', otros: 'Otros' };

export default function Explosion() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const hoy = hoyISO();
  const [contratoId, setContratoId] = useState(null);
  const [nueva, setNueva] = useState(false);
  const [msg, setMsg] = useState(null);
  const [progreso, setProgreso] = useState(null);   // {id, hechos, total, texto}
  const id = params.get('id');

  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero, modalidad, estado').eq('empresa_id', empresaId).in('estado', ['vigente', 'borrador', 'suspendido']).order('numero')).then((cs) => [...cs].sort((a, b) => (a.estado === 'vigente' ? 0 : 1) - (b.estado === 'vigente' ? 0 : 1))), [empresaId]);
  useEffect(() => { if (contratos.datos?.length && !contratos.datos.find((c) => c.id === contratoId)) setContratoId(contratos.datos[0].id); }, [contratos.datos, contratoId]);
  const contrato = contratos.datos?.find((c) => c.id === contratoId);
  const lista = useCarga(async () => contratoId ? q(sb().rpc('explosiones_contrato', { p_contrato: contratoId })) : null, [contratoId, progreso?.fin]);
  const sedes = useCarga(async () => contratoId ? q(sb().from('contrato_sedes').select('id, sedes(nombre)').eq('contrato_id', contratoId).eq('estado', 'activa')).then((r) => r.map((x) => ({ id: x.id, nombre: x.sedes?.nombre ?? '·' })).sort((a, b) => a.nombre.localeCompare(b.nombre))) : [], [contratoId]);

  // calculo por tramos: el tamano sale de un presupuesto de sede-dias por llamada (USPEC con 4 tiempos y dietas pesa mas
  // que PAE); si una llamada se pasa del limite de Supabase se parte el tramo a la mitad y se reintenta.
  const calcular = async (expId, desde, hasta, nSedes) => {
    let porTramo = Math.max(1, Math.min(30, Math.floor(160 / Math.max(1, nSedes))));
    const totalDias = Math.round((desdeISO(hasta) - desdeISO(desde)) / 86400000) + 1;
    let d = desde, hechos = 0, n = 0;
    setProgreso({ id: expId, hechos: 0, total: totalDias, texto: 'Calculando…' });
    try {
      while (d <= hasta) {
        const fin = sumar(d, porTramo - 1) < hasta ? sumar(d, porTramo - 1) : hasta;
        try {
          await q(sb().rpc('calcular_explosion', { p_explosion: expId, p_desde: d, p_hasta: fin, p_sedes: null }));
        } catch (e) {
          if (porTramo > 1 && /tard|timeout|statement/i.test(e.message)) { porTramo = Math.max(1, Math.floor(porTramo / 2)); continue; }
          throw e;
        }
        hechos += Math.round((desdeISO(fin) - desdeISO(d)) / 86400000) + 1; n += 1;
        setProgreso({ id: expId, hechos, total: totalDias, texto: `Calculado hasta el ${fechaCorta(fin)} (${n} ${n === 1 ? 'tramo' : 'tramos'})` });
        d = sumar(fin, 1);
      }
      setProgreso({ id: expId, hechos: totalDias, total: totalDias, fin: Date.now() });
    } catch (e) {
      setMsg({ ok: false, t: `El calculo quedo parcial: ${e.message}. Puede recalcular los tramos que faltan.` });
      setProgreso({ id: expId, hechos: 0, total: 0, fin: Date.now() });
    }
  };
  const crear = async (f) => {
    setMsg(null);
    try {
      const expId = await q(sb().rpc('crear_explosion', { p_contrato: contratoId, p_desde: f.desde, p_hasta: f.hasta, p_sedes: f.sedes?.length ? f.sedes : null, p_incluye_dietas: f.dietas, p_modo_presupuesto: 'ninguno', p_nombre: f.nombre || null, p_tipo: 'proyeccion', p_incluye_propuestos: f.propuestos }));
      setNueva(false);
      router.push(`/explosion?id=${expId}`);
      await calcular(expId, f.desde, f.hasta, f.sedes?.length || sedes.datos?.length || 1);
    } catch (e) { setMsg({ ok: false, t: e.message }); }
  };

  return (
    <>
      <Encabezado titulo="Explosion de materiales" sub="Cuanto producto hace falta para servir la programacion: raciones por dia y por sede convertidas en kilos, litros y unidades por producto, con la linea y las dietas por separado.">
        <Link href="/programacion" className="btn">Programacion</Link>
        <Link href="/cupos" className="btn">Cupos y dietas</Link>
        {puede('M2', 'crear') && !id && <button className="btn btn-p" onClick={() => setNueva(true)}>Nueva proyeccion</button>}
      </Encabezado>
      {!id && <Consejo>
        Elija el periodo (8, 15, 30 o 90 dias, o un rango) y las sedes. La proyeccion toma el menu real de cada dia (ciclo + intercambios + novedades), la poblacion que rige y las dietas, y suma los crudos por producto.
        Cuando este calculada se convierte en <b>requerimiento</b>, se aprueba y se envia a compras. El presupuesto en pesos llega con el master de precios (M3).
      </Consejo>}
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {!id && (
        <>
          <div className="row gap10 mb12">
            {contratos.datos?.length > 1 && <select value={contratoId ?? ''} onChange={(e) => setContratoId(e.target.value)}>{contratos.datos.map((c) => <option key={c.id} value={c.id}>{c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad}</option>)}</select>}
          </div>
          {lista.err && <Falla msg={lista.err} />}
          <div className="card">
            {lista.cargando && !lista.datos ? <Cargando /> : (
              <Tabla cols={[
                { t: 'Codigo', r: (r) => <><b>{r.codigo}</b>{r.nombre ? <div className="small muted">{r.nombre}</div> : null}</> },
                { t: 'Tipo', r: (r) => r.tipo === 'requerimiento' ? <span className="chip info">requerimiento</span> : <span className="chip">proyeccion</span> },
                { t: 'Periodo', r: (r) => <>{fechaCorta(r.desde)} a {fechaCorta(r.hasta)}<div className="small muted">{r.dias} dias · {r.n_sedes} sedes{r.incluye_dietas ? '' : ' · sin dietas'}</div></> },
                { t: 'Raciones', n: true, r: (r) => r.raciones ? num(r.raciones) : '·' },
                { t: 'Productos', n: true, r: (r) => r.productos ? num(r.productos) : '·' },
                { t: 'Estado', r: (r) => <Estado e={progreso?.id === r.id && !progreso.fin ? 'calculando' : r.estado} /> },
                { t: 'Creada', r: (r) => <span className="small">{fechaCorta(r.creado_en?.slice(0, 10))}{r.creado_por ? <div className="muted">{r.creado_por}</div> : null}</span> },
                { t: '', r: (r) => <Link href={`/explosion?id=${r.id}`} className="btn btn-xs">Abrir</Link> },
              ]} filas={lista.datos ?? []} vacio="Todavia no hay proyecciones para este contrato. Cree la primera con el boton de arriba." />
            )}
          </div>
        </>
      )}
      {id && <Detalle id={id} progreso={progreso?.id === id ? progreso : null} onRecalcular={(e) => calcular(e.id, e.desde, e.hasta, e.sedes.length)} puede={puede} unidad={unidadCupos(contrato?.modalidad)} setMsg={setMsg} />}
      {nueva && <FormNueva hoy={hoy} sedes={sedes.datos ?? []} onCerrar={() => setNueva(false)} onCrear={crear} />}
    </>
  );
}

function FormNueva({ hoy, sedes, onCerrar, onCrear }) {
  const [preset, setPreset] = useState(15);
  const [desde, setDesde] = useState(sumar(hoy, 1));
  const [hasta, setHasta] = useState(sumar(hoy, 15));
  const [todas, setTodas] = useState(true);
  const [sel, setSel] = useState([]);
  const [dietas, setDietas] = useState(true);
  const [propuestos, setPropuestos] = useState(false);
  const [nombre, setNombre] = useState('');
  const [enviando, setEnviando] = useState(false);
  const elegir = (n) => { setPreset(n); setHasta(sumar(desde, n - 1)); };
  const dias = Math.round((desdeISO(hasta) - desdeISO(desde)) / 86400000) + 1;
  const ok = desde && hasta && dias >= 1 && dias <= 366 && (todas || sel.length > 0);
  return (
    <Panel titulo="Nueva proyeccion" sub="El calculo corre por tramos; puede seguir trabajando mientras avanza." onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={!ok || enviando} onClick={async () => { setEnviando(true); await onCrear({ desde, hasta, sedes: todas ? null : sel, dietas, propuestos, nombre }); setEnviando(false); }}>{enviando ? 'Creando…' : `Calcular ${dias} dias`}</button>}>
      <Campo l="Periodo">
        <div className="row gap6">{PRESETS.map((n) => <button key={n} className={`btn btn-s${preset === n ? ' btn-p' : ''}`} onClick={() => elegir(n)}>{n} dias</button>)}<button className={`btn btn-s${preset === 0 ? ' btn-p' : ''}`} onClick={() => setPreset(0)}>Rango</button></div>
      </Campo>
      <div className="row gap10 mt8 mb12">
        <Campo l="Desde" req><input type="date" value={desde} onChange={(e) => { setDesde(e.target.value); if (preset) setHasta(sumar(e.target.value, preset - 1)); }} /></Campo>
        <Campo l="Hasta" req><input type="date" value={hasta} min={desde} onChange={(e) => { setHasta(e.target.value); setPreset(0); }} /></Campo>
        <span className="muted small" style={{ alignSelf: 'flex-end' }}>{dias > 0 ? `${dias} dias` : ''}</span>
      </div>
      <Campo l="Sedes" className="mb12">
        <div className="row gap10"><label className="row gap4"><input type="radio" checked={todas} onChange={() => setTodas(true)} /> Todas ({sedes.length})</label><label className="row gap4"><input type="radio" checked={!todas} onChange={() => setTodas(false)} /> Elegir</label></div>
      </Campo>
      {!todas && (
        <div className="scroll mb12" style={{ maxHeight: 220, border: '1px solid var(--linea)', borderRadius: 8, padding: 8 }}>
          {sedes.map((s) => <label key={s.id} className="row gap6 small" style={{ padding: '2px 0' }}><input type="checkbox" checked={sel.includes(s.id)} onChange={(e) => setSel(e.target.checked ? [...sel, s.id] : sel.filter((x) => x !== s.id))} /> {s.nombre}</label>)}
        </div>
      )}
      <label className="row gap6 mb8"><input type="checkbox" checked={dietas} onChange={(e) => setDietas(e.target.checked)} /> Incluir dietas terapeuticas (reemplazos y porciones de dieta)</label>
      <label className="row gap6 mb12"><input type="checkbox" checked={propuestos} onChange={(e) => setPropuestos(e.target.checked)} /> Tomar los intercambios propuestos como si ya rigieran</label>
      <Campo l="Nombre (opcional)"><input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="ej. Compra quincena 2 de noviembre" /></Campo>
    </Panel>
  );
}

function Detalle({ id, progreso, onRecalcular, puede, unidad, setMsg }) {
  const [tab, setTab] = useState('productos');
  const [filtro, setFiltro] = useState('');
  const [cat, setCat] = useState('');
  const [prod, setProd] = useState(null);
  const calculando = progreso && !progreso.fin;
  const r = useCarga(() => q(sb().rpc('explosion_resumen', { p_explosion: id })), [id, progreso?.fin, progreso?.hechos]);
  const alertas = useCarga(async () => tab === 'alertas' ? q(sb().rpc('alertas_explosion', { p_explosion: id })) : null, [id, tab, progreso?.fin]);
  const e = r.datos?.explosion;
  const productos = useMemo(() => (r.datos?.productos ?? []).filter((p) => (!cat || p.categoria === cat) && (!filtro || p.nombre.toLowerCase().includes(filtro.toLowerCase()))), [r.datos, cat, filtro]);
  const accion = async (a) => {
    setMsg(null);
    try { await q(sb().rpc(a === 'anular' ? 'anular_explosion' : 'estado_requerimiento', a === 'anular' ? { p_explosion: id } : { p_explosion: id, p_accion: a })); setMsg({ ok: true, t: { convertir: 'Convertida en requerimiento.', aprobar: 'Requerimiento aprobado.', enviar: 'Enviado a compras.', anular: 'Proyeccion anulada.' }[a] }); r.recargar(); }
    catch (x) { setMsg({ ok: false, t: x.message }); }
  };
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Codigo', 'Producto', 'Categoria', 'Cantidad compra', 'Unidad compra', 'Cantidad base', 'Unidad base', 'De linea', 'De dietas', 'Dias', 'Promedio por dia'],
      ...(r.datos?.productos ?? []).map((p) => [p.codigo, p.nombre, p.categoria, p.cantidad_compra, p.unidad_compra, p.cantidad_base, p.unidad_base, p.de_linea, p.de_dietas, p.dias, p.promedio_dia])]), 'Productos');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Sede', 'Raciones', 'Dias con servicio', 'Promedio por dia'], ...(r.datos?.por_sede ?? []).map((s) => [s.sede, s.raciones, s.dias, s.promedio])]), 'Raciones por sede');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Fecha', 'Raciones', 'Sedes con servicio'], ...(r.datos?.por_dia ?? []).map((d) => [d.fecha, d.raciones, d.sedes])]), 'Raciones por dia');
    XLSX.writeFile(wb, `Explosion_${e?.codigo ?? id}.xlsx`);
  };
  if (r.err) return <Falla msg={r.err} />;
  if (!r.datos) return <Cargando />;
  const maxDia = Math.max(1, ...(r.datos.por_dia ?? []).map((d) => d.raciones));
  return (
    <>
      <div className="row between mb12">
        <div className="row gap8"><Link href="/explosion" className="btn btn-s">← Todas</Link><h2 className="m0">{e.codigo}{e.nombre ? ` · ${e.nombre}` : ''}</h2><Estado e={calculando ? 'calculando' : e.estado} />{e.tipo === 'requerimiento' && <span className="chip info">requerimiento</span>}</div>
        <div className="row gap6">
          <button className="btn btn-s" onClick={descargar}>Descargar Excel</button>
          {puede('M2', 'crear') && !calculando && ['borrador', 'parcial', 'calculada'].includes(e.estado) && <button className="btn btn-s" onClick={() => onRecalcular({ id, desde: e.desde, hasta: e.hasta, sedes: e.sedes })}>Recalcular</button>}
          {puede('M2', 'crear') && e.tipo === 'proyeccion' && e.estado === 'calculada' && <button className="btn btn-s btn-p" onClick={() => accion('convertir')}>Convertir en requerimiento</button>}
          {puede('M2', 'aprobar') && e.tipo === 'requerimiento' && e.estado === 'calculada' && <button className="btn btn-s btn-p" onClick={() => accion('aprobar')}>Aprobar</button>}
          {puede('M2', 'aprobar') && e.estado === 'aprobada' && <button className="btn btn-s btn-p" onClick={() => accion('enviar')}>Enviar a compras</button>}
          {puede('M2', 'crear') && !['enviada_compras', 'anulada'].includes(e.estado) && <button className="btn btn-s btn-x" onClick={() => { if (confirm('¿Anular esta proyeccion?')) accion('anular'); }}>Anular</button>}
        </div>
      </div>
      {calculando && <div className="aviso info mb12"><div className="row between"><span>{progreso.texto}</span><span>{progreso.hechos} / {progreso.total}</span></div><div className="barra mt8"><i style={{ width: `${(100 * progreso.hechos) / Math.max(1, progreso.total)}%` }} /></div></div>}
      {!calculando && e.estado === 'parcial' && <div className="aviso mb12">Calculada en {e.dias_cubiertos} de {e.dias} dias. Use Recalcular para completar.</div>}
      <div className="grid g4 mb12">
        <Kpi v={e.raciones ?? 0} l={`raciones (${unidad}-dia)`} />
        <Kpi v={r.datos.productos.length} l="productos" />
        <Kpi v={`${fechaCorta(e.desde)} a ${fechaCorta(e.hasta)}`} l={`${e.dias} dias · ${e.sedes.length} sedes`} />
        <Kpi v={r.datos.por_dia.filter((d) => d.raciones > 0).length} l="dias con servicio" />
        {r.datos.sin_receta > 0 && <Kpi v={r.datos.sin_receta} l="sede-dias sin receta (ver alertas)" />}
      </div>
      {r.datos.por_tiempo?.length > 1 && <div className="row gap12 small mb12">{r.datos.por_tiempo.map((t) => <span key={t.tiempo}><b>{t.tiempo}</b> {num(t.raciones)}</span>)}</div>}
      <div className="tabs">
        <button className={tab === 'productos' ? 'on' : ''} onClick={() => setTab('productos')}>Productos ({r.datos.productos.length})</button>
        <button className={tab === 'sedes' ? 'on' : ''} onClick={() => setTab('sedes')}>Por sede ({r.datos.por_sede.length})</button>
        <button className={tab === 'establecimiento' ? 'on' : ''} onClick={() => setTab('establecimiento')}>Por establecimiento (despacho)</button>
        <button className={tab === 'dias' ? 'on' : ''} onClick={() => setTab('dias')}>Por dia</button>
        <button className={tab === 'alertas' ? 'on' : ''} onClick={() => setTab('alertas')}>Alertas</button>
      </div>
      <div className="card">
        {tab === 'productos' && (
          <>
            <div className="row gap8 mb12 wrap">
              <input placeholder="Buscar producto…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 220 }} />
              <button className={`btn btn-xs${cat === '' ? ' btn-p' : ''}`} onClick={() => setCat('')}>Todas</button>
              {r.datos.categorias.map((c) => <button key={c.categoria} className={`btn btn-xs${cat === c.categoria ? ' btn-p' : ''}`} onClick={() => setCat(c.categoria)} title={`${num(c.kg)} kg/l`}>{CATEGORIAS[c.categoria] ?? c.categoria} ({c.productos})</button>)}
            </div>
            <Tabla cols={[
              { t: 'Producto', r: (p) => <><b>{p.nombre}</b><div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria}{p.perecedero ? ' · perecedero' : ''}{p.nivel_riesgo ? ` · riesgo ${p.nivel_riesgo}` : ''}</div></> },
              { t: 'A comprar', n: true, r: (p) => <b>{num(p.cantidad_compra, p.cantidad_compra < 10 ? 2 : 1)} {p.unidad_compra}</b> },
              { t: 'Promedio / dia', n: true, r: (p) => `${num(p.promedio_dia / (p.factor_compra || 1), 2)} ${p.unidad_compra}` },
              { t: 'Linea', n: true, r: (p) => num(p.de_linea / (p.factor_compra || 1), 1) },
              { t: 'Dietas', n: true, r: (p) => p.de_dietas ? num(p.de_dietas / (p.factor_compra || 1), 1) : '·' },
              { t: 'Dias', n: true, k: 'dias' },
              { t: '', r: (p) => <button className="btn btn-xs" onClick={() => setProd(p)}>Detalle</button> },
            ]} filas={productos} idKey="producto_id" vacio={calculando ? 'Calculando…' : 'Sin productos: revise que las sedes tengan ciclo, cupos y recetas (pestana Alertas).'} />
          </>
        )}
        {tab === 'sedes' && <Tabla cols={[{ t: 'Sede', k: 'sede' }, { t: 'Raciones', n: true, r: (s) => num(s.raciones) }, { t: 'Dias con servicio', n: true, k: 'dias' }, { t: 'Promedio por dia', n: true, r: (s) => num(s.promedio) }]} filas={r.datos.por_sede} idKey="sede_id" />}
        {tab === 'establecimiento' && <PorEstablecimiento id={id} e={e} />}
        {tab === 'dias' && (
          <div className="stack gap4">
            {r.datos.por_dia.map((d) => (
              <div key={d.fecha} className="row gap8 small" style={{ flexWrap: 'nowrap' }}>
                <span style={{ width: 90 }}>{fechaCorta(d.fecha)}</span>
                <div className="barra" style={{ flex: 1 }}><i style={{ width: `${(100 * d.raciones) / maxDia}%` }} /></div>
                <span style={{ width: 150, textAlign: 'right' }}>{d.raciones ? `${num(d.raciones)} · ${d.sedes} sedes` : <span className="muted">sin servicio</span>}</span>
              </div>
            ))}
          </div>
        )}
        {tab === 'alertas' && (alertas.cargando && !alertas.datos ? <Cargando texto="Revisando ciclos, cupos y recetas…" /> : (
          <Tabla cols={[{ t: 'Tipo', r: (a) => <span className={`chip ${a.tipo === 'sin_receta' ? 'warn' : 'bad'}`}>{a.tipo.replace('_', ' ')}</span> }, { t: 'Sede', k: 'sede' }, { t: 'Fecha', r: (a) => a.fecha ? fechaCorta(a.fecha) : '·' }, { t: 'Detalle', k: 'detalle' }]}
            filas={(alertas.datos ?? []).map((a, i) => ({ ...a, id: i }))} vacio="Sin alertas: todas las sedes tienen ciclo, cupos y recetas en el periodo." />
        ))}
      </div>
      {prod && <DetalleProducto id={id} prod={prod} onCerrar={() => setProd(null)} />}
    </>
  );
}

function DetalleProducto({ id, prod, onCerrar }) {
  const d = useCarga(() => q(sb().rpc('explosion_producto', { p_explosion: id, p_producto: prod.producto_id })), [id, prod.producto_id]);
  const f = prod.factor_compra || 1;
  return (
    <Panel titulo={prod.nombre} sub={`${num(prod.cantidad_compra, 1)} ${prod.unidad_compra} en ${prod.dias} dias · ${num(prod.promedio_dia / f, 2)} ${prod.unidad_compra} por dia`} onCerrar={onCerrar}>
      {!d.datos ? <Cargando /> : (
        <>
          <h3 className="mt8">En que preparaciones</h3>
          <Tabla cols={[{ t: 'Preparacion', r: (x) => <>{x.preparacion ?? '·'}<div className="small muted">{x.tiempo} · {x.componente}{x.dieta ? ' · dieta' : ''}{x.ajustes ? ` · ${x.ajustes}` : ''}</div></> }, { t: 'Crudo / racion', n: true, r: (x) => `${num(x.crudo_racion, 1)} ${prod.unidad_base}` }, { t: 'Raciones', n: true, r: (x) => num(x.raciones) }, { t: 'Total', n: true, r: (x) => `${num(x.cantidad / f, 1)} ${prod.unidad_compra}` }]}
            filas={d.datos.por_preparacion.map((x, i) => ({ ...x, id: i }))} />
          <h3 className="mt12">Por sede</h3>
          <Tabla cols={[{ t: 'Sede', k: 'sede' }, { t: 'Dias', n: true, k: 'dias' }, { t: 'Total', n: true, r: (x) => `${num(x.cantidad / f, 1)} ${prod.unidad_compra}` }]} filas={d.datos.por_sede.map((x, i) => ({ ...x, id: i }))} />
          <h3 className="mt12">Por dia</h3>
          <Tabla cols={[{ t: 'Fecha', r: (x) => fechaCorta(x.fecha) }, { t: 'Sedes', n: true, k: 'sedes' }, { t: 'Cantidad', n: true, r: (x) => `${num(x.cantidad / f, 1)} ${prod.unidad_compra}` }]} filas={d.datos.por_dia.map((x, i) => ({ ...x, id: i }))} />
        </>
      )}
    </Panel>
  );
}

// Requerimiento por establecimiento: lo que bodega debe alistar y despachar a cada sede, con el tramo de menus que cubre
function PorEstablecimiento({ id, e }) {
  const d = useCarga(() => q(sb().rpc('explosion_por_sede', { p_explosion: id })), [id, e?.calculada_en]);
  const [abierta, setAbierta] = useState(null);
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Sede', 'Ciudad', 'Desde', 'Hasta', 'Dias', 'Menus (del - al)', 'Raciones', 'Productos'], ...d.datos.map((s) => [s.sede, s.ciudad, s.desde, s.hasta, s.dias, `${s.menu_desde} - ${s.menu_hasta}`, s.raciones, s.productos.length])]), 'Resumen');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Sede', 'Codigo', 'Producto', 'Categoria', 'Cantidad', 'Unidad', 'Perecedero', 'Desde', 'Hasta', 'Menus'], ...d.datos.flatMap((s) => s.productos.map((p) => [s.sede, p.codigo, p.nombre, p.categoria, p.cantidad_compra, p.unidad_compra, p.perecedero ? 'si' : 'no', s.desde, s.hasta, `${s.menu_desde} - ${s.menu_hasta}`]))]), 'Detalle por sede');
    for (const s of d.datos.slice(0, 60)) {
      XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([[`Requerimiento ${e.codigo} · ${s.sede}`], [`Del ${s.desde} al ${s.hasta} · menus ${s.menu_desde} al ${s.menu_hasta} · ${s.raciones} raciones`], [], ['Codigo', 'Producto', 'Categoria', 'Cantidad', 'Unidad', 'Perecedero'], ...s.productos.map((p) => [p.codigo, p.nombre, p.categoria, p.cantidad_compra, p.unidad_compra, p.perecedero ? 'si' : 'no'])]), s.sede.replace(/[\\/?*\[\]:]/g, ' ').slice(0, 31));
    }
    XLSX.writeFile(wb, `Despacho_${e.codigo}.xlsx`);
  };
  if (!d.datos) return <Cargando />;
  return (
    <>
      <div className="row between mb12 wrap">
        <span className="small muted">Lo que hay que alistar y enviar a cada establecimiento para este periodo, con el tramo de menus que cubre. Es el insumo del picking en bodega (modulo de logistica) y de las entregas directas de proveedor en sede.</span>
        <button className="btn btn-s" onClick={descargar}>Descargar Excel (una hoja por sede)</button>
      </div>
      <Tabla cols={[
        { t: 'Establecimiento', r: (s) => <><b>{s.sede}</b><div className="small muted">{s.ciudad}</div></> },
        { t: 'Periodo', r: (s) => <>{fechaCorta(s.desde)} a {fechaCorta(s.hasta)}<div className="small muted">{s.dias} dias con servicio</div></> },
        { t: 'Menus', r: (s) => <>del <b>{s.menu_desde}</b> al <b>{s.menu_hasta}</b><div className="small muted">{s.menus} menus distintos</div></> },
        { t: 'Raciones', n: true, r: (s) => num(s.raciones) },
        { t: 'Productos', n: true, r: (s) => s.productos.length },
        { t: 'Perecederos', n: true, r: (s) => s.productos.filter((p) => p.perecedero).length },
        { t: '', r: (s) => <button className="btn btn-xs" onClick={() => setAbierta(s)}>Ver lista</button> },
      ]} filas={d.datos} idKey="sede_id" vacio="Sin detalle todavia." />
      {abierta && (
        <Panel titulo={abierta.sede} sub={`Del ${fechaCorta(abierta.desde)} al ${fechaCorta(abierta.hasta)} · menus ${abierta.menu_desde} al ${abierta.menu_hasta} · ${num(abierta.raciones)} raciones`} onCerrar={() => setAbierta(null)}>
          <Tabla cols={[{ t: 'Producto', r: (p) => <>{p.nombre}<div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria}{p.perecedero ? ' · perecedero' : ''}</div></> }, { t: 'Cantidad', n: true, r: (p) => <b>{num(p.cantidad_compra, p.cantidad_compra < 10 ? 2 : 1)} {p.unidad_compra}</b> }]} filas={abierta.productos} idKey="producto_id" />
        </Panel>
      )}
    </>
  );
}
