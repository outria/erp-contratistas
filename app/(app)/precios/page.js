'use client';
// M3 · Master de precios: por producto, todas las ofertas vigentes (proveedor, marca, presentacion) comparadas por precio
// por unidad de compra, la mejor opcion disponible y el registro de precios nuevos.
import { useMemo, useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado } from '@/components/ui';
import { FormPrecio, CATEGORIAS } from '@/components/proveedores';
import { num, cop, fechaCorta, hoyISO } from '@/lib/fmt';

export default function Precios() {
  const { empresaId, puede } = useApp();
  const [filtro, setFiltro] = useState('');
  const [cat, setCat] = useState('');
  const [fecha, setFecha] = useState(hoyISO());
  const [soloSinPrecio, setSoloSinPrecio] = useState(false);
  const [abierto, setAbierto] = useState({});
  const [precioDe, setPrecioDe] = useState(null);
  const [msg, setMsg] = useState(null);
  const puedeEditar = puede('M3', 'crear');
  const d = useCarga(() => q(sb().rpc('master_precios', { p_empresa: empresaId, p_categoria: cat || null, p_filtro: filtro || null, p_fecha: fecha })), [empresaId, cat, filtro, fecha]);
  const filas = useMemo(() => (d.datos ?? []).filter((p) => !soloSinPrecio || p.mejor == null), [d.datos, soloSinPrecio]);
  const kpi = useMemo(() => { const l = d.datos ?? []; return { productos: l.length, conPrecio: l.filter((p) => p.mejor != null).length, sinOferta: l.filter((p) => !p.n_ofertas).length, ofertas: l.reduce((a, p) => a + p.ofertas.length, 0) }; }, [d.datos]);
  const categorias = useMemo(() => [...new Set((d.datos ?? []).map((p) => p.categoria))], [d.datos]);
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Codigo', 'Producto', 'Categoria', 'Unidad compra', 'Mejor precio / unidad compra', 'Ofertas'], ...(d.datos ?? []).map((p) => [p.codigo, p.producto, p.categoria, p.unidad_compra, p.mejor, p.n_ofertas])]), 'Mejor precio');
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Producto', 'Proveedor', 'Marca', 'Presentacion', 'Contenido', 'Precio presentacion', 'Precio / unidad compra', 'IVA %', 'Desde', 'Hasta', 'Estado', 'Entrega', 'Lead time'],
      ...(d.datos ?? []).flatMap((p) => p.ofertas.map((o) => [p.producto, o.proveedor, o.marca, o.presentacion, o.contenido, o.precio, o.por_compra, o.iva_pct, o.desde, o.hasta, o.estado, o.entrega_en, o.lead_time]))]), 'Ofertas');
    XLSX.writeFile(wb, `Master_precios_${fecha}.xlsx`);
  };
  return (
    <>
      <Encabezado titulo="Master de precios y ofertas" sub="Por producto: todas las ofertas vigentes comparadas por precio por unidad de compra, la mejor opcion disponible (homologada y sin bloqueo) y el historial.">
        <Link href="/proveedores" className="btn">Proveedores</Link>
        <Link href="/negociacion" className="btn">Negociacion por volumen</Link>
        {d.datos && <button className="btn" onClick={descargar}>Descargar Excel</button>}
      </Encabezado>
      <Consejo>Las ofertas se registran en la ficha de cada proveedor (producto, marca, presentacion). Aqui se comparan: un bulto de 50 kg a $160.000 y uno de 25 kg a $82.000 se ven como $3.200 y $3.280 por kilo. "Mejor" solo considera ofertas homologadas de proveedores sin bloqueo. Con la fecha se consulta el precio que regia cualquier dia (sirve para revisar facturas).</Consejo>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="grid g4 mb12">
        {[['productos', 'productos activos'], ['conPrecio', 'con precio vigente'], ['sinOferta', 'sin ningun proveedor'], ['ofertas', 'ofertas vigentes']].map(([k, l]) => <div key={k} className="card kpi"><span className="v">{num(kpi[k])}</span><span className="l">{l}</span></div>)}
      </div>
      <div className="row gap10 mb12 wrap">
        <input placeholder="Buscar producto…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 240 }} />
        <select value={cat} onChange={(e) => setCat(e.target.value)}><option value="">Todas las categorias</option>{categorias.map((c) => <option key={c} value={c}>{CATEGORIAS[c] ?? c}</option>)}</select>
        <label className="row gap4 small">Precios que regian el <input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label>
        <label className="row gap6 small"><input type="checkbox" checked={soloSinPrecio} onChange={(e) => setSoloSinPrecio(e.target.checked)} /> Solo sin precio disponible</label>
      </div>
      {d.err && <Falla msg={d.err} />}
      <div className="card">
        {d.cargando && !d.datos ? <Cargando /> : (
          <div className="scroll"><table className="t">
            <thead><tr><th>Producto</th><th className="n">Mejor precio</th><th className="n">Ofertas</th><th>Mejor opcion</th><th /></tr></thead>
            <tbody>
              {filas.map((p) => {
                const ab = !!abierto[p.producto_id];
                const mejor = p.ofertas.find((o) => o.estado === 'homologado' && !o.bloqueado && o.por_compra != null && Math.abs(o.por_compra - p.mejor) < 0.01);
                return [
                  <tr key={p.producto_id} className={p.mejor == null ? 'sin-cupos' : ''}>
                    <td><b>{p.producto}</b><div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria} · por {p.unidad_compra}{p.perecedero ? ' · perecedero' : ''}</div></td>
                    <td className="n">{p.mejor != null ? <b>{cop(p.mejor)} / {p.unidad_compra}</b> : <span className="chip warn">{p.n_ofertas ? 'sin precio vigente' : 'sin proveedor'}</span>}</td>
                    <td className="n">{p.ofertas.length}</td>
                    <td className="small">{mejor ? <>{mejor.proveedor}{mejor.marca ? ` · ${mejor.marca}` : ''}{mejor.presentacion ? ` · ${mejor.presentacion}` : ''}{mejor.proyecto_productivo ? <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span> : null}</> : '·'}</td>
                    <td>{p.ofertas.length > 0 && <button className="btn btn-xs" onClick={() => setAbierto((o) => ({ ...o, [p.producto_id]: !ab }))}>{ab ? 'Ocultar' : 'Ver ofertas'}</button>}</td>
                  </tr>,
                  ab && <tr key={`${p.producto_id}-d`}><td colSpan={5} style={{ background: 'var(--fondo-2)' }}>
                    <Tabla cols={[
                      { t: 'Proveedor', r: (o) => <>{o.proveedor}{o.proyecto_productivo && <span className="chip info" style={{ marginLeft: 6 }}>INPEC</span>}{o.bloqueado && <span className="chip bad" style={{ marginLeft: 6 }}>bloqueado</span>}{o.preferido && <span className="chip ok" style={{ marginLeft: 6 }}>1a opcion</span>}</> },
                      { t: 'Marca', r: (o) => o.marca ?? <span className="muted">sin marca</span> }, { t: 'Presentacion', r: (o) => o.presentacion ? `${o.presentacion} (${num(o.contenido)} ${p.unidad_base})` : `granel (${p.unidad_compra})` },
                      { t: 'Precio', n: true, r: (o) => o.precio != null ? <>{cop(o.precio)}<div className="small muted">{o.iva_pct ? `IVA ${o.iva_pct} %` : 'sin IVA'}</div></> : <span className="muted">sin precio</span> },
                      { t: `Por ${p.unidad_compra}`, n: true, r: (o) => o.por_compra != null ? <b>{cop(o.por_compra)}</b> : '·' },
                      { t: 'Vs. mejor', n: true, r: (o) => o.por_compra != null && p.mejor ? (o.por_compra > p.mejor ? <span className="bad">+{num(100 * (o.por_compra / p.mejor - 1), 1)} %</span> : <span className="muted">mejor</span>) : '·' },
                      { t: 'Vigencia', r: (o) => o.desde ? <span className="small">{fechaCorta(o.desde)}{o.hasta ? ` a ${fechaCorta(o.hasta)}` : ''}</span> : '·' },
                      { t: 'Entrega', r: (o) => <span className="small">{o.entrega_en === 'sede' ? 'en sede' : o.entrega_en === 'ambos' ? 'CEDI o sede' : 'CEDI'}{o.lead_time != null ? ` · ${o.lead_time} d` : ''}</span> },
                      { t: 'Estado', r: (o) => <Estado e={o.estado} /> },
                      { t: '', r: (o) => <span className="row gap4 nowrap end">{puedeEditar && <button className="btn btn-xs" onClick={() => setPrecioDe({ ...o, id: o.pp_id, producto: p.producto })}>Precio</button>}<Link href={`/proveedores?id=${o.tercero_id}`} className="btn btn-xs">Ficha</Link></span> },
                    ]} filas={p.ofertas} idKey="pp_id" />
                  </td></tr>,
                ];
              })}
              {filas.length === 0 && <tr><td colSpan={5} className="vacio">Sin productos con ese filtro.</td></tr>}
            </tbody>
          </table></div>
        )}
      </div>
      {precioDe && <FormPrecio oferta={precioDe} onCerrar={() => setPrecioDe(null)} onGuardado={() => { setPrecioDe(null); setMsg({ ok: true, t: 'Precio registrado.' }); d.recargar(); }} />}
    </>
  );
}
