'use client';
// M2 · Programacion de menus: varias semanas de una vez (semana -1, actual, +1, +2 y las que se agreguen),
// con el menu real de cada sede y el intercambio o la novedad desde la misma celda.
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Vacio, Consejo } from '@/components/ui';
import { SelectorSemanas, Semana, Leyenda, semanasARango, unidadCupos } from '@/components/programacion';
import { PanelDia } from '@/components/panel-dia';
import { hoyISO } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';

const leer = (k, d) => { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } };
const guardar = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };

export default function Programacion() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const hoy = hoyISO();
  const [contratoId, setContratoId] = useState(null);
  const [offsets, setOffsets] = useState(() => leer('sc_prg_semanas', [0, 1]));
  const [sedesSel, setSedesSel] = useState([]);
  const [propuestos, setPropuestos] = useState(false);
  const [agrupar, setAgrupar] = useState(true);
  const [abiertos, setAbiertos] = useState({});
  const [sel, setSel] = useState(null);

  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero, modalidad, estado, fecha_inicio, fecha_fin_inicial').eq('empresa_id', empresaId).in('estado', ['vigente', 'borrador', 'suspendido']).order('numero')).then((cs) => [...cs].sort((a, b) => (a.estado === 'vigente' ? 0 : 1) - (b.estado === 'vigente' ? 0 : 1))), [empresaId]);
  useEffect(() => { if (contratos.datos?.length && !contratos.datos.find((c) => c.id === contratoId)) setContratoId(contratos.datos[0].id); }, [contratos.datos, contratoId]);
  useEffect(() => { guardar('sc_prg_semanas', offsets); }, [offsets]);
  useEffect(() => { setSedesSel([]); setSel(null); }, [contratoId]);

  const contrato = contratos.datos?.find((c) => c.id === contratoId);
  const rango = useMemo(() => semanasARango(offsets, hoy), [offsets, hoy]);
  const d = useCarga(async () => contratoId ? q(sb().rpc('programacion', { p_contrato: contratoId, p_desde: rango.desde, p_hasta: rango.hasta, p_sedes: sedesSel.length ? sedesSel : null, p_incluye_propuestos: propuestos, p_agrupar: agrupar })) : null,
    [contratoId, rango.desde, rango.hasta, sedesSel.join(','), propuestos, agrupar]);
  const datos = d.datos;
  const celdas = useMemo(() => { const m = new Map(); for (const c of datos?.celdas ?? []) m.set(`${c.sede_id}|${c.fecha}`, c); return m; }, [datos]);
  const sedes = datos?.sedes ?? [];
  const sedesMap = useMemo(() => new Map(sedes.map((s) => [s.id, s])), [sedes]);
  const filas = datos?.filas ?? [];
  const unidad = unidadCupos(contrato?.modalidad);
  const tiempos = datos?.tiempos ?? [];
  const novedades = datos?.novedades ?? [];

  // abrir desde un aviso: /programacion?novedad=ID
  useEffect(() => {
    const nid = params.get('novedad');
    if (!nid || !datos) return;
    const n = novedades.find((x) => x.id === nid);
    if (n) { const fila = filas.find((f) => f.sedes.includes(n.sede_id)) ?? filas[0]; const s = sedesMap.get(n.sede_id) ?? sedesMap.get(fila?.rep); if (s) setSel({ sede: s, fecha: n.fecha, fila }); }
  }, [params, datos]); // eslint-disable-line react-hooks/exhaustive-deps

  const pendientes = novedades.filter((n) => n.estado === 'propuesta').length;
  const muchasSedes = (datos?.total_sedes ?? 0) > 20 && sedesSel.length === 0 && filas.length > 20;
  const propuestosN = (datos?.celdas ?? []).reduce((a, c) => a + (c.items ?? []).filter((i) => i.estado === 'propuesto').length, 0);

  return (
    <>
      <Encabezado titulo="Programacion de menus" sub="Lo que se sirve en cada sede cada dia: el ciclo oficial mas los intercambios concertados y las novedades. Parese en una celda para cambiar un componente o reportar un dia sin servicio.">
        {contratos.datos?.length > 1 && <select value={contratoId ?? ''} onChange={(e) => setContratoId(e.target.value)}>{contratos.datos.map((c) => <option key={c.id} value={c.id}>{c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad}</option>)}</select>}
      </Encabezado>
      <Consejo>
        Escoja las semanas con los botones (la actual, la anterior, las siguientes) o agregue mas hacia abajo. En cada celda se ve el menu del ciclo con el proteico de cada tiempo; el texto azul es un menu distinto al oficial (intercambio) y el punto de color dice de que clase.
        Al hacer clic en la celda se abre el detalle completo: desde ahi se cambia un componente (el sistema propone las opciones de la misma familia, respetando la rotacion), se agrega una opcion que no estaba (contingencia) o se reporta que ese dia no hay servicio.
      </Consejo>
      {contratos.err && <Falla msg={contratos.err} />}
      {d.err && <Falla msg={d.err} />}
      {contratos.datos && contratos.datos.length === 0 && <Vacio>Esta empresa no tiene contratos vigentes. Cree el contrato y asigne el ciclo de menus a sus sedes.</Vacio>}
      {contrato && (
        <>
          <div className="prg-barra">
            <SelectorSemanas offsets={offsets} onChange={setOffsets} maxSemanas={muchasSedes ? 2 : 10} />
            {sedes.length > 1 && (
              <select value={sedesSel[0] ?? ''} onChange={(e) => setSedesSel(e.target.value ? [e.target.value] : [])} title="Filtrar una sede">
                <option value="">Todas las sedes ({sedes.length})</option>
                {sedes.map((s) => <option key={s.id} value={s.id}>{s.nombre}</option>)}
              </select>
            )}
            <label className="row gap6 small" style={{ cursor: 'pointer' }}><input type="checkbox" checked={agrupar} onChange={(e) => setAgrupar(e.target.checked)} /> agrupar sedes con el mismo menu</label>
            <label className="row gap6 small" style={{ cursor: 'pointer' }}><input type="checkbox" checked={propuestos} onChange={(e) => setPropuestos(e.target.checked)} /> ver intercambios propuestos como si rigieran</label>
            {datos && sedes.length > 1 && <span className="chip">{filas.length === 1 ? `las ${sedes.length} sedes llevan el mismo menu` : `${filas.length} menus distintos en ${sedes.length} sedes`}</span>}
            {pendientes > 0 && <span className="chip warn">{pendientes} novedad{pendientes > 1 ? 'es' : ''} por aprobar</span>}
            {propuestosN > 0 && <span className="chip warn">{propuestosN} intercambio{propuestosN > 1 ? 's' : ''} propuesto{propuestosN > 1 ? 's' : ''}</span>}
            {d.cargando && <span className="muted small">actualizando…</span>}
          </div>
          {muchasSedes && <div className="aviso info small mb12">Hay {filas.length} menus distintos entre {datos.total_sedes} sedes: para ver mas de dos semanas filtre una sede.</div>}
          <Leyenda />
          <div className="mt12" />
          {d.cargando && !datos ? <Cargando texto="Armando la programacion…" /> : !datos ? null : sedes.length === 0 ? <Vacio>El contrato no tiene sedes activas.</Vacio> : (
            rango.lunes.map((l) => <Semana key={l} lunes={l} filas={filas} sedesMap={sedesMap} celdas={celdas} tiempos={tiempos} novedades={novedades} dias={datos.dias ?? []} hoy={hoy} unidad={unidad} abiertos={abiertos} onAbrir={(rep) => setAbiertos((a) => ({ ...a, [rep]: !a[rep] }))} sel={sel ? { sede_id: sel.fila?.rep ?? sel.sede.id, fecha: sel.fecha } : null} onCelda={(s, f, c, fila) => setSel({ sede: s, fecha: f, fila })} />)
          )}
          {sel && datos && <PanelDia sede={sel.sede} fecha={sel.fecha} fila={sel.fila} sedesMap={sedesMap} unidad={unidad} celda={celdas.get(`${sel.fila?.rep ?? sel.sede.id}|${sel.fecha}`)} datos={datos} onCerrar={() => setSel(null)} onCambio={() => d.recargar()} onSede={(s) => setSel((x) => ({ ...x, sede: s }))} />}
        </>
      )}
    </>
  );
}
