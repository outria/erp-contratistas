'use client';
// Compras publicas locales (Ley 2046 de 2020): resumen por contrato y mes, parametros del contrato,
// soportes (carga manual o importada del formato oficial) y exportacion al formato
// "Seguimiento compras publicas locales de alimentos vigencia 2026".
import { useState } from 'react';
import { sb, q } from '@/lib/supabase';
import { useCarga } from '@/lib/ctx';
import { Cargando, Falla, Vacio, Modal, Campo } from '@/components/ui';
import { cop, num, fechaCorta, hoyISO } from '@/lib/fmt';

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
export const nombreMes = (iso) => { const [y, m] = String(iso).split('-'); return `${MESES[Number(m) - 1]} ${y}`; };
const claseCumpl = (p) => (p == null ? '' : p >= 100 ? 'ok' : p >= 70 ? 'warn' : 'bad');

// agrupa las filas del tablero por contrato, con los meses en columnas
function agrupar(filas) {
  const m = new Map();
  for (const f of filas) {
    if (!m.has(f.contrato_id)) m.set(f.contrato_id, { ...f, meses: {} });
    m.get(f.contrato_id).meses[f.periodo] = f;
  }
  return [...m.values()];
}

export function ResumenComprasLocales({ empresaId = null, meses = 3, compacto = false, onElegir, ver = 0 }) {
  const d = useCarga(() => q(sb().rpc('compras_locales_tablero', { p_empresa: empresaId, p_meses: meses })), [empresaId, meses, ver]);
  if (d.err) return compacto ? <p className="small muted">El indicador aun no esta disponible ({d.err}).</p> : <Falla msg={d.err} />;
  if (!d.datos) return <Cargando />;
  const filas = d.datos;
  if (!filas.length) return <Vacio>No hay contratos vigentes o en liquidacion para medir.</Vacio>;
  const periodos = [...new Set(filas.map((f) => f.periodo))].sort().reverse();
  const grupos = agrupar(filas);
  return (
    <div className="scroll-x">
      <table className="t">
        <thead><tr>
          <th>Contrato</th>
          {!compacto && <th>Meta</th>}
          {periodos.map((p, i) => <th key={p} className="n">{nombreMes(p)}{i === 0 ? ' (en curso)' : ''}</th>)}
        </tr></thead>
        <tbody>{grupos.map((g) => (
          <tr key={g.contrato_id} onClick={onElegir ? () => onElegir(g) : undefined} style={onElegir ? { cursor: 'pointer' } : undefined}>
            <td>
              <b>{g.numero}</b>{g.practica && <span className="chip info" style={{ marginLeft: 6 }}>practica</span>}
              <div className="small muted">{g.empresa}</div>
            </td>
            {!compacto && (
              <td className="small">
                {num(g.meta_pct, 2)} %{Number(g.extra_pct) > 0 ? ` (30 + ${num(g.extra_pct, 2)})` : ''}
                <div className="muted">{g.base_tipo === 'facturado_total' ? 'sobre el facturado total' : `sobre rubro alimentos ${g.rubro_pct == null ? '(falta %)' : num(g.rubro_pct, 2) + ' %'}`}</div>
              </td>
            )}
            {periodos.map((p) => {
              const f = g.meses[p];
              if (!f) return <td key={p} className="n muted">·</td>;
              return (
                <td key={p} className="n">
                  {f.cumplimiento_pct == null
                    ? <span className="chip" title={f.alerta || ''}>sin base</span>
                    : <span className={`chip ${claseCumpl(f.cumplimiento_pct)}`}>{num(f.cumplimiento_pct, 1)} %</span>}
                  {!compacto && (
                    <div className="small muted">
                      {cop(f.comprado_local)} de {f.requerido == null ? '·' : cop(f.requerido)}
                      {f.facturado_estimado ? ' · facturado estimado' : ''}
                    </div>
                  )}
                  {!compacto && f.alerta && <div className="small" style={{ color: 'var(--warn)' }}>{f.alerta}</div>}
                </td>
              );
            })}
          </tr>
        ))}</tbody>
      </table>
      <p className="small muted mt8">
        Cumplimiento = compras a proveedores Ley 2046 del mes / requerido. Requerido = (30 % + lo ofrecido de mas) x base;
        la base es el facturado del mes por el % del rubro de alimentos de la racion, o el facturado total si el contrato lo dice asi.
        Si el mes no tiene facturado cargado se usa el promedio de los ultimos 3 meses (estimado).
      </p>
    </div>
  );
}

export function ParametrosCL({ contrato, onCerrar, onGuardado }) {
  const [f, setF] = useState({
    meta_compras_locales_pct: contrato.meta_compras_locales_pct ?? 30,
    meta_compras_locales_extra_pct: contrato.meta_compras_locales_extra_pct ?? 0,
    base_compras_locales: contrato.base_compras_locales ?? 'rubro_alimentos',
    rubro_alimentos_pct: contrato.rubro_alimentos_pct ?? '',
    valor_racion_ref: contrato.valor_racion_ref ?? '',
    zona: (contrato.zona_compras_locales ?? []).join(', '),
    fuente_parametros_cl: contrato.fuente_parametros_cl ?? '',
  });
  const [err, setErr] = useState(null); const [gu, setGu] = useState(false);
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value });
  const guardar = async () => {
    setErr(null); setGu(true);
    try {
      await q(sb().rpc('guardar_parametros_cl', { p_contrato: contrato.id, p: {
        meta_compras_locales_pct: Number(f.meta_compras_locales_pct), meta_compras_locales_extra_pct: Number(f.meta_compras_locales_extra_pct || 0),
        base_compras_locales: f.base_compras_locales,
        rubro_alimentos_pct: f.rubro_alimentos_pct === '' ? null : Number(f.rubro_alimentos_pct),
        valor_racion_ref: f.valor_racion_ref === '' ? null : Number(f.valor_racion_ref),
        zona_compras_locales: f.zona.split(',').map((s) => s.trim()).filter(Boolean),
        fuente_parametros_cl: f.fuente_parametros_cl,
      } }));
      onGuardado?.(); onCerrar();
    } catch (e) { setErr(e.message); } finally { setGu(false); }
  };
  return (
    <Modal titulo={`Compras locales · ${contrato.numero}`} onCerrar={onCerrar}>
      {err && <Falla msg={err} />}
      <div className="grid g2">
        <Campo l="Meta legal (%)" ayuda="Ley 2046: minimo 30 %."><input type="number" step="0.01" value={f.meta_compras_locales_pct} onChange={set('meta_compras_locales_pct')} /></Campo>
        <Campo l="Adicional ofrecido (%)" ayuda="Lo que la UT ofrecio de mas en la licitacion (ej. 1 para llegar a 31 %)."><input type="number" step="0.01" value={f.meta_compras_locales_extra_pct} onChange={set('meta_compras_locales_extra_pct')} /></Campo>
        <Campo l="Se mide sobre">
          <select value={f.base_compras_locales} onChange={set('base_compras_locales')}>
            <option value="rubro_alimentos">Facturado x % del rubro de alimentos</option>
            <option value="facturado_total">Facturado total del mes</option>
          </select>
        </Campo>
        <Campo l="Rubro de alimentos (%)" ayuda="Participacion de los alimentos en el valor de la racion (USPEC Anexo 25: G15 73,72 %)."><input type="number" step="0.01" value={f.rubro_alimentos_pct} onChange={set('rubro_alimentos_pct')} /></Campo>
        <Campo l="Valor racion de referencia"><input type="number" value={f.valor_racion_ref} onChange={set('valor_racion_ref')} /></Campo>
        <Campo l="Zona de compras locales" ayuda="Departamentos separados por coma. Vacio = no se valida el origen."><input value={f.zona} onChange={set('zona')} /></Campo>
      </div>
      <Campo l="Fuente (anexo, clausula, quien lo confirmo)"><textarea rows={3} value={f.fuente_parametros_cl} onChange={set('fuente_parametros_cl')} /></Campo>
      <div className="row end gap8 mt12"><button className="btn" onClick={onCerrar}>Cancelar</button><button className="btn pri" disabled={gu} onClick={guardar}>{gu ? 'Guardando…' : 'Guardar'}</button></div>
    </Modal>
  );
}

// columnas del formato oficial (hoja Seguimiento_Compras_de_Alimento)
const COLS = [
  ['operador', 'NOMBRE OPERADOR PAE'], ['modelo', 'MODELO DE ATENCIÓN'], ['modalidad', 'MODALIDAD DE ATENCION'], ['complemento', 'TIPO DE COMPLEMENTO (OPCIONAL)'],
  ['proveedor_nombre', 'RAZÓN SOCIAL/ NOMBRE PROVEEDOR DE ALIMENTOS'], ['tipo_proveedor', 'TIPO DE PROVEEDOR'], ['rep_legal', 'REPRESENTANTE LEGAL'],
  ['factura', 'Nº FACTURA /RECIBO /SOPORTE'], ['fecha_compra', 'FECHA COMPRA'], ['tipo_producto', 'TIPO DE PRODUCTO'], ['alimento', 'ALIMENTO COMPRADO'],
  ['especie_variedad', 'ESPECIE /VARIEDAD'], ['cantidad', 'CANTIDAD TOTAL COMPRADA'], ['unidad', 'UNIDAD DE MEDIDA'], ['valor', 'VALOR TOTAL COMPRADO (COP $)'],
  ['ley2046', 'PROVEEDOR LEY 2046 (SI / NO)'], ['lugar_productor', 'LUGAR UBICACIÓN PRODUCTOR LOCAL (Plataforma Sec. Agricultura ETC)'],
];
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toUpperCase();
const fechaExcel = (v) => {
  if (v == null || v === '') return null;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (typeof v === 'string' && /^\d{5}$/.test(v.trim())) v = Number(v);
  if (typeof v === 'number') return new Date(Math.round((v - 25569) * 86400000)).toISOString().slice(0, 10);
  const m = String(v).match(/(\d{1,2})[/-](\d{1,2})[/-](\d{4})/); if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  const n = String(v).match(/^\d{4}-\d{2}-\d{2}/); return n ? n[0] : null;
};

// lee el formato oficial: busca la fila de encabezados por "VALOR TOTAL COMPRADO" y mapea columnas por nombre
export function leerFormatoOficial(matriz) {
  const iHead = matriz.findIndex((r) => (r || []).some((c) => norm(c).startsWith('VALOR TOTAL COMPRADO')));
  if (iHead < 0) return { error: 'No encontre la fila de encabezados (columna "VALOR TOTAL COMPRADO").' };
  const head = matriz[iHead].map(norm);
  const idx = {};
  for (const [k, t] of COLS) { const j = head.findIndex((h) => h && (h === norm(t) || h.startsWith(norm(t).slice(0, 18)))); if (j >= 0) idx[k] = j; }
  if (idx.valor == null || idx.proveedor_nombre == null) return { error: 'Faltan las columnas de proveedor o valor.' };
  const filas = [];
  for (const r of matriz.slice(iHead + 1)) {
    if (!r) continue;
    const prov = r[idx.proveedor_nombre]; const val = Number(String(r[idx.valor] ?? '').replace(/[^0-9.-]/g, ''));
    if (!prov || !val || /^TOTAL/i.test(String(r[0] ?? ''))) continue;
    const g = (k) => (idx[k] == null ? null : r[idx[k]]);
    filas.push({
      proveedor_nombre: String(prov).trim(), tipo_proveedor: g('tipo_proveedor'), factura: g('factura') == null ? null : String(g('factura')),
      fecha_compra: fechaExcel(g('fecha_compra')), tipo_producto: g('tipo_producto'), alimento: g('alimento') == null ? null : String(g('alimento')).trim(),
      especie_variedad: g('especie_variedad'), cantidad: Number(g('cantidad')) || null, unidad: g('unidad'), valor: val,
      ley2046: /^S/i.test(String(g('ley2046') ?? '')), lugar_productor: g('lugar_productor'),
    });
  }
  return { filas };
}

export function SoportesCL({ contrato, periodo, puedeEditar, onCambio }) {
  const [ver, setVer] = useState(0);
  const [imp, setImp] = useState(null); const [err, setErr] = useState(null); const [nuevo, setNuevo] = useState(null);
  const d = useCarga(() => q(sb().from('compras_locales_soportes').select('*').eq('contrato_id', contrato.id).eq('periodo', periodo).order('fecha_compra')), [contrato.id, periodo, ver]);
  const ocs = useCarga(() => q(sb().from('ordenes_compra')
    .select('id, codigo, fecha_emision, total, estado, terceros(razon_social, numero, ley2046, tipo_proveedor, rep_legal_nombre, municipio_productor, ciudad), oc_items(descripcion, cantidad, unidad_pedido, total)')
    .eq('contrato_id', contrato.id).not('estado', 'in', '(borrador,anulada)')
    .gte('fecha_emision', periodo).lt('fecha_emision', sigMes(periodo))), [contrato.id, periodo, ver]);
  const refrescar = () => { setVer(ver + 1); onCambio?.(); };

  const importar = async (file) => {
    setErr(null);
    try {
      const XLSX = await import('xlsx');
      const wb = XLSX.read(await file.arrayBuffer(), { cellDates: true });
      const hoja = wb.SheetNames.find((n) => /seguimiento/i.test(n)) ?? wb.SheetNames[0];
      const r = leerFormatoOficial(XLSX.utils.sheet_to_json(wb.Sheets[hoja], { header: 1, raw: true, defval: null }));
      if (r.error) { setErr(r.error); return; }
      setImp({ archivo: file.name, hoja, filas: r.filas });
    } catch (e) { setErr(e.message); }
  };
  const aplicar = async () => {
    setErr(null);
    try {
      const filas = imp.filas.map((f) => ({ ...f, empresa_id: contrato.empresa_id, contrato_id: contrato.id, periodo, origen: 'importado', notas: imp.archivo }));
      for (let i = 0; i < filas.length; i += 500) await q(sb().from('compras_locales_soportes').insert(filas.slice(i, i + 500)));
      setImp(null); refrescar();
    } catch (e) { setErr(e.message); }
  };
  const borrar = async (id) => {
    if (!window.confirm('¿Quitar este soporte?')) return;
    try { await q(sb().from('compras_locales_soportes').delete().eq('id', id).eq('contrato_id', contrato.id)); refrescar(); } catch (e) { setErr(e.message); }
  };
  const guardarNuevo = async () => {
    setErr(null);
    try {
      if (!nuevo.proveedor_nombre || !Number(nuevo.valor)) throw new Error('Proveedor y valor son obligatorios.');
      await q(sb().from('compras_locales_soportes').insert({ ...nuevo, valor: Number(nuevo.valor), cantidad: nuevo.cantidad ? Number(nuevo.cantidad) : null,
        empresa_id: contrato.empresa_id, contrato_id: contrato.id, periodo, origen: 'manual' }));
      setNuevo(null); refrescar();
    } catch (e) { setErr(e.message); }
  };

  const exportar = async () => {
    const XLSX = await import('xlsx');
    const filas = [];
    const base = { operador: contrato.empresa ?? '', modelo: contrato.modalidad === 'pae' ? 'PAE Convencional' : '', modalidad: '', complemento: '' };
    for (const s of d.datos ?? []) filas.push({ ...base, ...s, rep_legal: '', ley2046: s.ley2046 ? 'SI' : 'NO' });
    for (const o of ocs.datos ?? []) {
      if ((d.datos ?? []).some((s) => s.oc_id === o.id)) continue;
      for (const it of o.oc_items ?? []) filas.push({ ...base, proveedor_nombre: o.terceros?.razon_social, tipo_proveedor: o.terceros?.tipo_proveedor ?? '', rep_legal: o.terceros?.rep_legal_nombre ?? '',
        factura: o.codigo, fecha_compra: o.fecha_emision, tipo_producto: '', alimento: it.descripcion, especie_variedad: '', cantidad: it.cantidad, unidad: it.unidad_pedido,
        valor: Number(it.total), ley2046: o.terceros?.ley2046 ? 'SI' : 'NO', lugar_productor: o.terceros?.municipio_productor ?? o.terceros?.ciudad ?? '' });
    }
    const total = filas.reduce((a, f) => a + Number(f.valor || 0), 0);
    const local = filas.filter((f) => f.ley2046 === 'SI').reduce((a, f) => a + Number(f.valor || 0), 0);
    const aoa = [
      ['PROGRAMA DE ALIMENTACIÓN ESCOLAR – PAE'],
      ['SEGUIMIENTO COMPRAS PÚBLICAS LOCALES DE ALIMENTOS VIGENCIA ' + periodo.slice(0, 4)],
      [`Entidad Territorial: ${contrato.entidad ?? ''}`, '', '', '', '', '', '', 'Nombre del cargo responsable del reporte:', '', '', '', '', '', '', `Periodo de Reporte: ${nombreMes(periodo)}`],
      COLS.map(([, t]) => t),
      ...filas.map((f) => COLS.map(([k]) => f[k] ?? '')),
      [],
      ['TOTAL MES', ...Array(13).fill(''), total],
      ['TOTAL PROVEEDORES LEY 2046 (SI)', ...Array(13).fill(''), local],
    ];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), 'Seguimiento_Compras_de_Alimento');
    XLSX.writeFile(wb, `COMPRAS LOCALES ${contrato.numero} ${nombreMes(periodo).toUpperCase()}.xlsx`);
  };

  const sop = d.datos ?? [];
  const tot = sop.reduce((a, s) => a + Number(s.valor), 0); const loc = sop.filter((s) => s.ley2046).reduce((a, s) => a + Number(s.valor), 0);
  return (
    <div className="card mt16">
      <div className="row between wrap gap8">
        <h2>Soportes de {nombreMes(periodo)} · {contrato.numero}</h2>
        <div className="row gap8 wrap">
          <button className="btn" onClick={exportar} disabled={!d.datos || !ocs.datos}>Exportar formato oficial</button>
          {puedeEditar && <label className="btn">Importar formato oficial<input type="file" accept=".xlsx,.xls" hidden onChange={(e) => e.target.files[0] && importar(e.target.files[0])} /></label>}
          {puedeEditar && <button className="btn pri" onClick={() => setNuevo({ proveedor_nombre: '', valor: '', ley2046: true, fecha_compra: hoyISO() })}>Agregar soporte</button>}
        </div>
      </div>
      {(err || d.err || ocs.err) && <Falla msg={err || d.err || ocs.err} />}
      <p className="small muted">
        OC de la plataforma en el mes: {ocs.datos ? `${ocs.datos.length} (${cop(ocs.datos.reduce((a, o) => a + Number(o.total), 0))}; Ley 2046: ${cop(ocs.datos.filter((o) => o.terceros?.ley2046).reduce((a, o) => a + Number(o.total), 0))})` : '…'}.
        Soportes cargados: {sop.length} ({cop(tot)}; Ley 2046: {cop(loc)}).
      </p>
      {imp && (
        <div className="card mb12" style={{ background: 'var(--fondo-2)' }}>
          <b>{imp.archivo}</b> · hoja {imp.hoja}: {imp.filas.length} renglones, {cop(imp.filas.reduce((a, f) => a + f.valor, 0))};
          Ley 2046 (SI): {cop(imp.filas.filter((f) => f.ley2046).reduce((a, f) => a + f.valor, 0))}.
          <div className="row gap8 mt8"><button className="btn" onClick={() => setImp(null)}>Cancelar</button><button className="btn pri" onClick={aplicar}>Cargar al mes {nombreMes(periodo)}</button></div>
        </div>
      )}
      {d.cargando && !d.datos ? <Cargando /> : sop.length === 0 ? <Vacio>Sin soportes cargados para este mes.</Vacio> : (
        <div className="scroll-x"><table className="t">
          <thead><tr><th>Fecha</th><th>Proveedor</th><th>Factura / OC</th><th>Alimento</th><th className="n">Cantidad</th><th className="n">Valor</th><th>Ley 2046</th><th>Lugar</th>{puedeEditar && <th />}</tr></thead>
          <tbody>{sop.map((s) => (
            <tr key={s.id}>
              <td>{fechaCorta(s.fecha_compra)}</td><td>{s.proveedor_nombre}<div className="small muted">{s.proveedor_nit}</div></td>
              <td className="small">{s.factura}{s.oc_codigo ? ` · ${s.oc_codigo}` : ''}</td><td className="small">{s.alimento}</td>
              <td className="n">{s.cantidad == null ? '' : `${num(s.cantidad)} ${s.unidad ?? ''}`}</td><td className="n">{cop(s.valor)}</td>
              <td><span className={`chip ${s.ley2046 ? 'ok' : ''}`}>{s.ley2046 ? 'SI' : 'NO'}</span></td><td className="small">{s.lugar_productor}</td>
              {puedeEditar && <td><button className="btn sm" onClick={() => borrar(s.id)}>Quitar</button></td>}
            </tr>
          ))}</tbody>
        </table></div>
      )}
      {nuevo && (
        <Modal titulo="Agregar soporte de compra local" onCerrar={() => setNuevo(null)}>
          <div className="grid g2">
            <Campo l="Proveedor" req><input value={nuevo.proveedor_nombre} onChange={(e) => setNuevo({ ...nuevo, proveedor_nombre: e.target.value })} /></Campo>
            <Campo l="NIT / cedula"><input value={nuevo.proveedor_nit ?? ''} onChange={(e) => setNuevo({ ...nuevo, proveedor_nit: e.target.value })} /></Campo>
            <Campo l="Factura / recibo"><input value={nuevo.factura ?? ''} onChange={(e) => setNuevo({ ...nuevo, factura: e.target.value })} /></Campo>
            <Campo l="Fecha"><input type="date" value={nuevo.fecha_compra ?? ''} onChange={(e) => setNuevo({ ...nuevo, fecha_compra: e.target.value })} /></Campo>
            <Campo l="Alimento"><input value={nuevo.alimento ?? ''} onChange={(e) => setNuevo({ ...nuevo, alimento: e.target.value })} /></Campo>
            <Campo l="Valor (COP)" req><input type="number" value={nuevo.valor} onChange={(e) => setNuevo({ ...nuevo, valor: e.target.value })} /></Campo>
            <Campo l="Lugar del productor"><input value={nuevo.lugar_productor ?? ''} onChange={(e) => setNuevo({ ...nuevo, lugar_productor: e.target.value })} /></Campo>
            <Campo l="Proveedor Ley 2046"><select value={nuevo.ley2046 ? 'SI' : 'NO'} onChange={(e) => setNuevo({ ...nuevo, ley2046: e.target.value === 'SI' })}><option>SI</option><option>NO</option></select></Campo>
          </div>
          <div className="row end gap8 mt12"><button className="btn" onClick={() => setNuevo(null)}>Cancelar</button><button className="btn pri" onClick={guardarNuevo}>Guardar</button></div>
        </Modal>
      )}
    </div>
  );
}

function sigMes(iso) { const [y, m] = iso.split('-').map(Number); return m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`; }
