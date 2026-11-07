'use client';
// Requerimientos de Planeacion: la "necesidad de compra de materia prima" (C0xx) que Planeacion envia a Compras.
// Se importa el Excel tal cual, queda versionado por contrato y Compras le lleva el estado.
import { useState } from 'react';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Consejo, Cargando, Falla, Vacio, Modal, Campo } from '@/components/ui';
import { cop, num, fechaCorta } from '@/lib/fmt';
import { leerNecesidadCompra } from '@/components/requerimientos';

const ESTADOS = { recibido: 'Recibido', en_compra: 'En compra', cubierto: 'Cubierto', cancelado: 'Cancelado' };
const CLASE = { recibido: 'info', en_compra: 'warn', cubierto: 'ok', cancelado: '' };

export default function Requerimientos() {
  const { empresaId, puede } = useApp();
  const [ver, setVer] = useState(0);
  const [filtro, setFiltro] = useState('activos');
  const [sel, setSel] = useState(null);
  const [imp, setImp] = useState(null);
  const [err, setErr] = useState(null);
  const lista = useCarga(() => q(sb().from('requerimientos_planeacion')
    .select('id, codigo, version, tipo, categorias, consumo_desde, consumo_hasta, fecha_envio, fecha_entrega, bodega, modalidad, cobertura, estado, costo_total, contrato_id, contratos(numero)')
    .eq('empresa_id', empresaId).order('fecha_envio', { ascending: false, nullsFirst: false }).limit(300)), [empresaId, ver]);
  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero').eq('empresa_id', empresaId).in('estado', ['vigente', 'suspendido', 'liquidacion', 'borrador']).order('numero')), [empresaId]);
  const puedeImportar = puede('M2', 'crear') || puede('M3', 'crear');

  const leer = async (file) => {
    setErr(null);
    try {
      const XLSX = await import('xlsx');
      const wb = XLSX.read(await file.arrayBuffer(), { cellDates: false });
      const hoja = wb.SheetNames.find((n) => !/descuento|embalaje/i.test(n)) ?? wb.SheetNames[0];
      const r = leerNecesidadCompra(XLSX.utils.sheet_to_json(wb.Sheets[hoja], { header: 1, raw: true, defval: null }));
      if (r.error) { setErr(r.error); return; }
      if (!r.lineas.length) { setErr('El archivo no trae renglones con cantidad.'); return; }
      setImp({ ...r, archivo: file.name, hoja, codigo: r.documento ? `C${String(r.documento).padStart(3, '0')}` : '', tipo: /actualiz/i.test(file.name) ? 'actualizacion' : /adicional/i.test(file.name) ? 'adicional' : 'planificada', contrato_id: contratos.datos?.length === 1 ? contratos.datos[0].id : '' });
    } catch (e) { setErr(e.message); }
  };
  const guardar = async () => {
    setErr(null);
    try {
      if (!imp.contrato_id) throw new Error('Escoja el contrato.');
      if (!/^[A-Za-z0-9._-]{1,30}$/.test(imp.codigo || '')) throw new Error('Codigo no valido (ej. C050).');
      const res = await q(sb().rpc('importar_requerimiento', { p: {
        empresa_id: empresaId, contrato_id: imp.contrato_id, codigo: imp.codigo, tipo: imp.tipo, categorias: imp.categorias,
        consumo_desde: imp.consumo_desde, consumo_hasta: imp.consumo_hasta, fecha_envio: imp.fecha_envio, bodega: imp.bodega,
        ciclo: imp.ciclo, cobertura: imp.cobertura, observaciones: imp.observaciones, archivo: imp.archivo, costo_total: imp.costo_total,
        fecha_entrega: imp.lineas.map((l) => l.fecha_entrega).filter(Boolean).sort()[0] ?? null, lineas: imp.lineas,
      } }));
      setImp(null); setVer(ver + 1); setSel(res.id);
    } catch (e) { setErr(e.message); }
  };

  const filas = (lista.datos ?? []).filter((r) => filtro === 'todos' || (filtro === 'activos' ? ['recibido', 'en_compra'].includes(r.estado) : r.estado === filtro));
  return (
    <>
      <Encabezado titulo="Requerimientos de Planeacion" sub="Necesidad de compra de materia prima por programa (C0xx)">
        <div className="row gap8">
          <select value={filtro} onChange={(e) => setFiltro(e.target.value)}>
            <option value="activos">Por atender</option><option value="cubierto">Cubiertos</option><option value="cancelado">Cancelados</option><option value="todos">Todos</option>
          </select>
          {puedeImportar && <label className="btn pri">Importar Excel de Planeacion<input type="file" accept=".xlsx,.xls,.xlsm" hidden onChange={(e) => e.target.files[0] && leer(e.target.files[0])} /></label>}
        </div>
      </Encabezado>
      <Consejo>
        Suba el archivo "NECESIDAD DE COMPRA DE MATERIA PRIMA" tal como llega de Planeacion. Se leen bodega, ciclo, cobertura y cada renglon
        (fecha de entrega, dia a consumir, cantidad, descuento de inventario y cantidad a comprar). Los productos se cruzan con el catalogo;
        los que no existen se crean marcados para revision. Si el codigo ya existe queda como nueva version.
      </Consejo>
      {(err || lista.err) && <Falla msg={err || lista.err} />}
      {imp && (
        <div className="card mb16">
          <h2>{imp.archivo}</h2>
          <p className="small muted">{imp.union_temporal} · bodega {imp.bodega} · enviado {fechaCorta(imp.fecha_envio)} · consumo {fechaCorta(imp.consumo_desde)} a {fechaCorta(imp.consumo_hasta)} · cobertura {num(imp.cobertura)} · {imp.lineas.length} renglones · {cop(imp.costo_total)}</p>
          <div className="grid g3 mt8">
            <Campo l="Contrato" req><select value={imp.contrato_id} onChange={(e) => setImp({ ...imp, contrato_id: e.target.value })}><option value="">Escoja…</option>{(contratos.datos ?? []).map((c) => <option key={c.id} value={c.id}>{c.numero}</option>)}</select></Campo>
            <Campo l="Codigo" req><input value={imp.codigo} onChange={(e) => setImp({ ...imp, codigo: e.target.value.toUpperCase() })} /></Campo>
            <Campo l="Tipo"><select value={imp.tipo} onChange={(e) => setImp({ ...imp, tipo: e.target.value })}><option value="planificada">Planificada</option><option value="actualizacion">Actualizacion</option><option value="adicional">Adicional</option><option value="cancelada">Cancelada</option></select></Campo>
          </div>
          <div className="row gap8 mt8"><button className="btn" onClick={() => setImp(null)}>Cancelar</button><button className="btn pri" onClick={guardar}>Guardar requerimiento</button></div>
        </div>
      )}
      <div className="card">
        {lista.cargando && !lista.datos ? <Cargando /> : filas.length === 0 ? <Vacio>No hay requerimientos en este filtro.</Vacio> : (
          <div className="scroll-x"><table className="t">
            <thead><tr><th>Codigo</th><th>Contrato</th><th>Categorias</th><th>Consumo</th><th>Entrega</th><th className="n">Cobertura</th><th className="n">Costo</th><th>Estado</th></tr></thead>
            <tbody>{filas.map((r) => (
              <tr key={r.id} onClick={() => setSel(r.id)} style={{ cursor: 'pointer' }}>
                <td><b>{r.codigo}</b>{r.version > 1 ? ` v${r.version}` : ''}<div className="small muted">{r.tipo}</div></td>
                <td>{r.contratos?.numero}<div className="small muted">{r.bodega}</div></td>
                <td className="small">{(r.categorias ?? []).join(', ')}</td>
                <td className="small">{fechaCorta(r.consumo_desde)} a {fechaCorta(r.consumo_hasta)}</td>
                <td className="small">{fechaCorta(r.fecha_entrega)}</td>
                <td className="n">{r.cobertura == null ? '' : num(r.cobertura)}</td>
                <td className="n">{cop(r.costo_total)}</td>
                <td><span className={`chip ${CLASE[r.estado]}`}>{ESTADOS[r.estado]}</span></td>
              </tr>
            ))}</tbody>
          </table></div>
        )}
      </div>
      {sel && <Detalle id={sel} onCerrar={() => setSel(null)} puedeEstado={puede('M3', 'crear')} onCambio={() => setVer((v) => v + 1)} />}
    </>
  );
}

function Detalle({ id, onCerrar, puedeEstado, onCambio }) {
  const [err, setErr] = useState(null);
  const d = useCarga(() => q(sb().from('requerimientos_planeacion').select('*, contratos(numero), requerimiento_lineas(*, productos(codigo, nombre, pendiente_revision))').eq('id', id).maybeSingle()), [id]);
  const r = d.datos;
  const cambiar = async (estado) => {
    try { await q(sb().rpc('estado_req_planeacion', { p_id: id, p_estado: estado })); onCambio(); onCerrar(); } catch (e) { setErr(e.message); }
  };
  return (
    <Modal titulo={r ? `${r.codigo}${r.version > 1 ? ' v' + r.version : ''} · ${r.contratos?.numero}` : 'Requerimiento'} onCerrar={onCerrar} ancho>
      {(err || d.err) && <Falla msg={err || d.err} />}
      {!r ? <Cargando /> : (
        <>
          <p className="small muted">{r.ciclo} · {r.modalidad} · cobertura {r.cobertura == null ? '·' : num(r.cobertura)} · bodega {r.bodega} · enviado {fechaCorta(r.fecha_envio)} por {r.analista ?? '·'}</p>
          {r.observaciones && <p className="small">{r.observaciones}</p>}
          <div className="scroll-x"><table className="t">
            <thead><tr><th>Producto</th><th>Entrega</th><th>Consumo</th><th className="n">Cantidad</th><th className="n">Descuento inv.</th><th className="n">A comprar</th><th className="n">Precio ref.</th><th className="n">Costo</th></tr></thead>
            <tbody>{[...(r.requerimiento_lineas ?? [])].sort((a, b) => a.orden - b.orden).map((l) => (
              <tr key={l.id}>
                <td>{l.descripcion}<div className="small muted">{l.categoria} · {l.unidad}{l.productos ? ` · ${l.productos.codigo}` : ' · sin producto'}{l.productos?.pendiente_revision ? ' (nuevo, revisar)' : ''}</div></td>
                <td className="small">{fechaCorta(l.fecha_entrega)}</td><td className="small">{l.dia_consumo}</td>
                <td className="n">{num(l.cantidad)}</td><td className="n">{Number(l.descuento_inventario) ? num(l.descuento_inventario) : ''}</td>
                <td className="n">{l.cantidad_comprar == null ? num(Math.max(Number(l.cantidad) - Number(l.descuento_inventario), 0)) : num(l.cantidad_comprar)}</td>
                <td className="n">{l.precio_ref == null ? '' : cop(l.precio_ref)}</td><td className="n">{l.costo == null ? '' : cop(l.costo)}</td>
              </tr>
            ))}</tbody>
          </table></div>
          <div className="row between mt12">
            <b>Total {cop(r.costo_total)}</b>
            {puedeEstado && r.estado !== 'cancelado' && (
              <div className="row gap8">
                {r.estado === 'recibido' && <button className="btn" onClick={() => cambiar('en_compra')}>Pasar a compra</button>}
                {r.estado !== 'cubierto' && <button className="btn pri" onClick={() => cambiar('cubierto')}>Marcar cubierto</button>}
                <button className="btn" onClick={() => cambiar('cancelado')}>Cancelar</button>
              </div>
            )}
          </div>
        </>
      )}
    </Modal>
  );
}
