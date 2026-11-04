'use client';
// M2 · Cupos y dietas: la poblacion que rige en cada sede (PPL, estudiantes, cupos) por grupo y por tiempo,
// la poblacion en dieta terapeutica, con edicion por vigencias e importacion desde el Excel de recoleccion.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Modal, Campo } from '@/components/ui';
import { TablaCupos, TablaDietas, PanelCupos, PanelDietas, esSimulada } from '@/components/cupos';
import { unidadCupos } from '@/components/programacion';
import { hoyISO, num, fechaCorta } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';
import { filasDesdeHoja, elegirHoja, hojasExportacion } from '@/lib/poblacion-excel';

export default function Cupos() {
  const { empresaId, puede } = useApp();
  const hoy = hoyISO();
  const [contratoId, setContratoId] = useState(null);
  const [fecha, setFecha] = useState(hoy);
  const [tab, setTab] = useState('cupos');
  const [filtro, setFiltro] = useState('');
  const [edit, setEdit] = useState(null);       // {tipo, sede}
  const [imp, setImp] = useState(null);         // estado del importador
  const [msg, setMsg] = useState(null);
  const [guardando, setGuardando] = useState(false);

  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero, modalidad, estado').eq('empresa_id', empresaId).in('estado', ['vigente', 'borrador', 'suspendido']).order('numero')).then((cs) => [...cs].sort((a, b) => (a.estado === 'vigente' ? 0 : 1) - (b.estado === 'vigente' ? 0 : 1))), [empresaId]);
  useEffect(() => { if (contratos.datos?.length && !contratos.datos.find((c) => c.id === contratoId)) setContratoId(contratos.datos[0].id); }, [contratos.datos, contratoId]);
  const d = useCarga(async () => contratoId ? q(sb().rpc('poblacion_contrato', { p_contrato: contratoId, p_fecha: fecha })) : null, [contratoId, fecha]);
  const datos = d.datos;
  const contrato = contratos.datos?.find((c) => c.id === contratoId);
  const unidad = unidadCupos(contrato?.modalidad);
  const puedeEditar = puede('M2', 'editar') || puede('M7', 'editar');
  const tieneDietas = useMemo(() => datos?.grupos?.some((g) => g.tipo === 'sexo') || datos?.sedes?.some((s) => s.dietas?.length), [datos]);
  const simuladas = useMemo(() => datos?.sedes?.filter((s) => (s.cupos ?? []).some((c) => esSimulada(c.fuente)) || (s.dietas ?? []).some((c) => esSimulada(c.fuente))).length ?? 0, [datos]);
  const totales = useMemo(() => {
    if (!datos) return null;
    const pob = datos.sedes.reduce((a, s) => a + (s.cupos ?? []).reduce((b, c) => b + c.cantidad, 0), 0);
    const die = datos.sedes.reduce((a, s) => a + (s.dietas ?? []).reduce((b, c) => b + c.cantidad, 0), 0);
    return { pob, die, sinCupos: datos.sedes.filter((s) => !(s.cupos ?? []).length).length };
  }, [datos]);

  const guardar = async ({ desde, fuente, items }) => {
    setGuardando(true); setMsg(null);
    try {
      const fn = edit.tipo === 'cupos' ? 'guardar_cupos' : 'guardar_dietas';
      await q(sb().rpc(fn, { p_contrato_sede: edit.sede.id, p_desde: desde, p_items: items, p_fuente: fuente }));
      setMsg({ ok: true, t: `${edit.tipo === 'cupos' ? 'Cupos' : 'Dietas'} de ${edit.sede.nombre} guardados desde el ${fechaCorta(desde)}.` });
      setEdit(null); d.recargar();
    } catch (e) { setMsg({ ok: false, t: e.message }); }
    finally { setGuardando(false); }
  };

  // ---------- importar Excel ----------
  const leerArchivo = async (file, tipo) => {
    setImp({ tipo, archivo: file.name, leyendo: true });
    try {
      const XLSX = await import('xlsx');
      const wb = XLSX.read(await file.arrayBuffer(), { cellDates: true });
      const hoja = elegirHoja(wb.SheetNames, tipo, contrato?.modalidad);
      const matriz = XLSX.utils.sheet_to_json(wb.Sheets[hoja], { header: 1, raw: true, defval: null });
      const r0 = filasDesdeHoja(matriz, 'cupos');
      tipo = r0.columnas?.dieta != null ? 'dietas' : 'cupos';   // el archivo manda: si trae columna de dieta, son dietas
      const r = tipo === 'dietas' ? filasDesdeHoja(matriz, 'dietas') : r0;
      if (r.error) { setImp({ tipo, archivo: file.name, hoja, hojas: wb.SheetNames, error: r.error, wb }); return; }
      const prev = await q(sb().rpc('importar_poblacion', { p_contrato: contratoId, p_tipo: tipo, p_filas: r.filas, p_desde: fecha, p_fuente: file.name, p_aplicar: false }));
      setImp({ tipo, archivo: file.name, hoja, hojas: wb.SheetNames, filas: r.filas, prev, wb, desde: fecha });
    } catch (e) { setImp({ tipo, archivo: file.name, error: e.message }); }
  };
  const cambiarHoja = async (hoja) => {
    const XLSX = await import('xlsx');
    const matriz = XLSX.utils.sheet_to_json(imp.wb.Sheets[hoja], { header: 1, raw: true, defval: null });
    const r0 = filasDesdeHoja(matriz, 'cupos');
    const tipo = r0.columnas?.dieta != null ? 'dietas' : 'cupos';
    const r = tipo === 'dietas' ? filasDesdeHoja(matriz, 'dietas') : r0;
    if (r.error) { setImp({ ...imp, hoja, tipo, error: r.error, filas: null, prev: null }); return; }
    const prev = await q(sb().rpc('importar_poblacion', { p_contrato: contratoId, p_tipo: tipo, p_filas: r.filas, p_desde: imp.desde, p_fuente: imp.archivo, p_aplicar: false }));
    setImp({ ...imp, hoja, tipo, error: null, filas: r.filas, prev });
  };
  const aplicar = async () => {
    setGuardando(true); setMsg(null);
    try {
      const r = await q(sb().rpc('importar_poblacion', { p_contrato: contratoId, p_tipo: imp.tipo, p_filas: imp.filas, p_desde: imp.desde, p_fuente: imp.archivo, p_aplicar: true }));
      setMsg({ ok: true, t: `Importadas ${r.ok} filas en ${r.sedes} sedes desde ${imp.archivo}.` });
      setImp(null); d.recargar();
    } catch (e) { setMsg({ ok: false, t: e.message }); }
    finally { setGuardando(false); }
  };
  const descargar = async () => {
    const XLSX = await import('xlsx');
    const { cupos, dietas } = hojasExportacion(datos, unidad);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(cupos), contrato?.modalidad === 'uspec_ppl' ? 'USPEC cupos' : 'Cupos');
    if (dietas.length > 1 || tieneDietas) XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(dietas), 'Dietas');
    XLSX.writeFile(wb, `Cupos_${contrato?.numero ?? 'contrato'}_${fecha}.xlsx`);
  };

  return (
    <>
      <Encabezado titulo="Cupos y dietas" sub="La poblacion que rige en cada sede: PPL, estudiantes o cupos por grupo y modalidad, y cuantos estan en dieta terapeutica. De aqui salen las raciones de la programacion y la explosion.">
        <Link href="/programacion" className="btn">Ir a la programacion</Link>
      </Encabezado>
      <Consejo>
        Cada cifra rige desde una fecha: al cambiarla se cierra la anterior el dia antes, asi la historia queda intacta para facturar y para la interventoria.
        Para muchas sedes use <b>Importar Excel</b> con la plantilla de recoleccion (o cualquier Excel con columnas de sede, grupo, modalidad y cantidad): primero se previsualiza fila por fila y solo se carga cuando todo cuadra.
        Lo marcado <span className="chip warn">simulada</span> son datos de practica que se reemplazan al cargar los reales.
      </Consejo>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="row gap10 mb12">
        {contratos.datos?.length > 1 && <select value={contratoId ?? ''} onChange={(e) => setContratoId(e.target.value)}>{contratos.datos.map((c) => <option key={c.id} value={c.id}>{c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad}</option>)}</select>}
        <Campo l="Lo que rige el"><input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></Campo>
        <input placeholder="Buscar sede…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 200 }} />
        <span className="crece" />
        {datos && <button className="btn btn-s" onClick={descargar}>Descargar Excel</button>}
        {puede('M2', 'editar') && <label className="btn btn-s btn-p">Importar Excel<input type="file" accept=".xlsx,.xls,.csv" style={{ display: 'none' }} onChange={(e) => { const f = e.target.files?.[0]; if (f) leerArchivo(f, tab); e.target.value = ''; }} /></label>}
      </div>
      {totales && (
        <div className="row gap12 mb12 small">
          <span><b>{num(totales.pob)}</b> {unidad} en {datos.sedes.length} sedes</span>
          {tieneDietas && <span><b>{num(totales.die)}</b> en dieta ({totales.pob ? Math.round(100 * totales.die / totales.pob) : 0} %)</span>}
          {totales.sinCupos > 0 && <span className="chip warn">{totales.sinCupos} sedes sin cupos</span>}
          {simuladas > 0 && <span className="chip warn">{simuladas} sedes con datos simulados</span>}
          {datos.historial?.length > 0 && <span className="muted">Ultima carga: {fechaCorta(datos.historial[0].desde)} · {datos.historial[0].fuente}</span>}
        </div>
      )}
      {tieneDietas && <div className="tabs"><button className={tab === 'cupos' ? 'on' : ''} onClick={() => setTab('cupos')}>Cupos ({unidad})</button><button className={tab === 'dietas' ? 'on' : ''} onClick={() => setTab('dietas')}>Dietas terapeuticas</button></div>}
      {d.err && <Falla msg={d.err} />}
      <div className="card">
        {d.cargando && !datos ? <Cargando /> : !datos ? null
          : tab === 'cupos' ? <TablaCupos datos={datos} filtro={filtro} unidad={unidad} puedeEditar={puedeEditar} onEditar={(s) => setEdit({ tipo: 'cupos', sede: s })} />
          : <TablaDietas datos={datos} filtro={filtro} puedeEditar={puedeEditar} onEditar={(s) => setEdit({ tipo: 'dietas', sede: s })} />}
      </div>
      {edit?.tipo === 'cupos' && <PanelCupos datos={datos} sede={edit.sede} hoy={hoy} onCerrar={() => setEdit(null)} onGuardar={guardar} guardando={guardando} />}
      {edit?.tipo === 'dietas' && <PanelDietas datos={datos} sede={edit.sede} hoy={hoy} onCerrar={() => setEdit(null)} onGuardar={guardar} guardando={guardando} />}
      {imp && (
        <Modal titulo={`Importar ${imp.tipo} desde ${imp.archivo}`} onCerrar={() => setImp(null)} ancho>
          {imp.leyendo ? <Cargando texto="Leyendo el archivo…" /> : (
            <>
              <div className="row gap10 mb12">
                {imp.hojas?.length > 1 && <Campo l="Hoja"><select value={imp.hoja} onChange={(e) => cambiarHoja(e.target.value)}>{imp.hojas.map((h) => <option key={h}>{h}</option>)}</select></Campo>}
                <Campo l="Rige desde (si la fila no trae fecha)"><input type="date" value={imp.desde ?? fecha} onChange={(e) => setImp({ ...imp, desde: e.target.value })} /></Campo>
              </div>
              {imp.error && <div className="aviso bad mb12">{imp.error}</div>}
              {imp.prev && (
                <>
                  <div className={`aviso ${imp.prev.con_error ? 'bad' : 'ok'} mb12`}>
                    {imp.prev.ok} filas listas en {imp.prev.sedes} sedes{imp.prev.con_error ? ` · ${imp.prev.con_error} con error (corrija el archivo o la sede en el sistema y vuelva a cargar)` : ' · todo cuadra'}.
                  </div>
                  <div className="scroll" style={{ maxHeight: '50vh' }}>
                    <table className="t">
                      <thead><tr><th>Fila</th><th>Sede en el archivo</th><th>Sede en el sistema</th>{imp.tipo === 'cupos' ? <><th>Grupo</th><th>Modalidad</th></> : <><th>Dieta</th><th>Grupo</th></>}<th className="n">Cantidad</th><th>Desde</th><th>Resultado</th></tr></thead>
                      <tbody>
                        {imp.prev.filas.map((f, i) => { const o = imp.filas[i]; return (
                          <tr key={i} className={f.error ? 'fila-error' : ''}>
                            <td>{f.fila}</td><td>{f.sede}</td><td>{f.sede_resuelta ?? <span className="muted">·</span>}</td>
                            {imp.tipo === 'cupos' ? <><td>{o?.grupo ?? <span className="muted">unico</span>}</td><td>{o?.tiempo ?? '·'}</td></> : <><td>{o?.dieta}</td><td>{o?.grupo}</td></>}
                            <td className="n">{f.cantidad != null ? num(f.cantidad) : '·'}</td><td className="small">{f.desde ? fechaCorta(f.desde) : '·'}</td>
                            <td>{f.error ? <span className="chip bad">{f.error}</span> : <span className="chip ok">ok</span>}</td>
                          </tr>); })}
                      </tbody>
                    </table>
                  </div>
                  <div className="row end gap8 mt12">
                    <button className="btn" onClick={() => setImp(null)}>Cancelar</button>
                    <button className="btn btn-p" disabled={guardando || imp.prev.con_error > 0 || imp.prev.ok === 0} onClick={aplicar}>{guardando ? 'Cargando…' : `Cargar ${imp.prev.ok} filas`}</button>
                  </div>
                </>
              )}
            </>
          )}
        </Modal>
      )}
    </>
  );
}
