'use client';
// M2 · Minutas y calendario: ciclos de menu, que ciclo lleva cada sede, gramajes por grupo (etario o sexo),
// calendario de servicio (dias de clase, receso, reposicion) y partes diarios.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado } from '@/components/ui';
import { EditorCiclo, FormCiclo, AsignarCiclo, Gramajes, Calendario, Partes } from '@/components/minutas';
import { unidadCupos } from '@/components/programacion';
import { hoyISO, num, fechaCorta } from '@/lib/fmt';
import { MODALIDADES } from '@/lib/catalogos';

const TABS = [['ciclos', 'Ciclos de menu'], ['sedes', 'Ciclo por sede'], ['gramajes', 'Gramajes por grupo'], ['calendario', 'Calendario'], ['partes', 'Partes diarios']];

export default function Minutas() {
  const { empresaId, puede } = useApp();
  const hoy = hoyISO();
  const [contratoId, setContratoId] = useState(null);
  const [tab, setTab] = useState('ciclos');
  const [cicloAbierto, setCicloAbierto] = useState(null);
  const [nuevoCiclo, setNuevoCiclo] = useState(false);
  const [selSedes, setSelSedes] = useState([]);
  const [asignar, setAsignar] = useState(false);
  const [msg, setMsg] = useState(null);
  const [guardando, setGuardando] = useState(false);
  const contratos = useCarga(() => q(sb().from('contratos').select('id, numero, modalidad, estado').eq('empresa_id', empresaId).in('estado', ['vigente', 'borrador', 'suspendido']).order('numero')).then((cs) => [...cs].sort((a, b) => (a.estado === 'vigente' ? 0 : 1) - (b.estado === 'vigente' ? 0 : 1))), [empresaId]);
  useEffect(() => { if (contratos.datos?.length && !contratos.datos.find((c) => c.id === contratoId)) setContratoId(contratos.datos[0].id); }, [contratos.datos, contratoId]);
  const d = useCarga(async () => contratoId ? q(sb().rpc('minutas_contrato', { p_contrato: contratoId })) : null, [contratoId]);
  const datos = d.datos;
  const contrato = contratos.datos?.find((c) => c.id === contratoId);
  const unidad = unidadCupos(contrato?.modalidad);
  const puedeEditar = puede('M2', 'editar');
  const ciclosMap = useMemo(() => new Map((datos?.ciclos ?? []).map((c) => [c.id, c])), [datos]);
  const act = async (fn, ok) => { setGuardando(true); setMsg(null); try { const r = await fn(); setMsg({ ok: true, t: typeof ok === 'function' ? ok(r) : ok }); d.recargar(); return r; } catch (e) { setMsg({ ok: false, t: e.message }); } finally { setGuardando(false); } };

  return (
    <>
      <Encabezado titulo="Minutas y calendario" sub="El ciclo de menus de cada contrato, que ciclo y variante lleva cada sede, los gramajes por grupo de poblacion, los dias con y sin servicio y el parte diario.">
        <Link href="/programacion" className="btn">Programacion</Link>
        <Link href="/explosion" className="btn">Explosion</Link>
      </Encabezado>
      <Consejo>
        <b>Ciclos</b>: la minuta oficial dia por dia; se edita casilla por casilla y se pone vigente cuando esta completa. <b>Ciclo por sede</b>: a que ciclo y variante esta pegada cada sede y desde que fecha arranca el menu 1. <b>Gramajes</b>: porcion servida por componente y por grupo etario o sexo, que escala las recetas. <b>Calendario</b>: receso, vacaciones, paros y jornadas de reposicion por rango. <b>Partes diarios</b>: la asistencia o el parte de guardia real del dia, que manda sobre el cupo.
      </Consejo>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="row gap10 mb12 wrap">
        {contratos.datos?.length > 1 && <select value={contratoId ?? ''} onChange={(e) => { setContratoId(e.target.value); setCicloAbierto(null); setSelSedes([]); }}>{contratos.datos.map((c) => <option key={c.id} value={c.id}>{c.numero} · {MODALIDADES[c.modalidad] ?? c.modalidad}</option>)}</select>}
        {datos && <span className="small muted">{datos.contrato.dias_atencion === 'todos' ? 'Atiende todos los dias' : 'Atiende dias habiles / de clase'} · {datos.ciclos.length} ciclos · {datos.sedes.length} sedes</span>}
      </div>
      <div className="tabs">{TABS.map(([k, t]) => <button key={k} className={tab === k ? 'on' : ''} onClick={() => { setTab(k); setCicloAbierto(null); }}>{t}</button>)}</div>
      {d.err && <Falla msg={d.err} />}
      <div className="card">
        {!datos ? <Cargando /> : (
          <>
            {tab === 'ciclos' && (cicloAbierto
              ? <EditorCiclo cicloId={cicloAbierto} datos={datos} puedeEditar={puedeEditar} onCambio={() => d.recargar()} onCerrar={() => setCicloAbierto(null)} />
              : <>
                <div className="row between mb12"><span className="muted small">Cada ciclo es una version de la minuta. El vigente es el que rige; los historicos quedan para la trazabilidad.</span>{puedeEditar && <button className="btn btn-p btn-s" onClick={() => setNuevoCiclo(true)}>Nuevo ciclo</button>}</div>
                <Tabla cols={[
                  { t: 'Ciclo', r: (c) => <><b>{c.codigo}</b>{c.nombre ? <div className="small muted">{c.nombre}</div> : null}</> },
                  { t: 'Menus', n: true, k: 'n_menus' },
                  { t: 'Casillas', n: true, r: (c) => <>{num(c.items)}{c.sin_receta ? <div className="small bad">{c.sin_receta} sin receta</div> : null}</> },
                  { t: 'Sedes que lo usan', n: true, k: 'sedes' },
                  { t: 'Tipo', k: 'tipo' },
                  { t: 'Estado', r: (c) => <Estado e={c.estado} /> },
                  { t: 'Oficio / vigencia', r: (c) => <span className="small">{c.oficio ?? '·'}{c.vigente_desde ? ` · desde ${fechaCorta(c.vigente_desde)}` : ''}</span> },
                  { t: '', r: (c) => <button className="btn btn-xs" onClick={() => setCicloAbierto(c.id)}>{puedeEditar && c.estado !== 'historico' ? 'Abrir y editar' : 'Ver'}</button> },
                ]} filas={datos.ciclos} vacio="Este contrato no tiene ciclos. Cree el primero." />
              </>)}
            {tab === 'sedes' && (
              <>
                <div className="row between mb12 wrap">
                  <span className="muted small">{selSedes.length ? `${selSedes.length} sedes seleccionadas` : 'Seleccione sedes para asignarles un ciclo, o use el boton de la fila.'}</span>
                  {puedeEditar && <span className="row gap6"><button className="btn btn-s" onClick={() => setSelSedes(datos.sedes.map((s) => s.id))}>Todas</button><button className="btn btn-s" onClick={() => setSelSedes([])}>Ninguna</button><button className="btn btn-s btn-p" disabled={!selSedes.length} onClick={() => setAsignar(true)}>Asignar ciclo a la seleccion</button></span>}
                </div>
                <Tabla cols={[
                  ...(puedeEditar ? [{ t: '', r: (s) => <input type="checkbox" checked={selSedes.includes(s.id)} onChange={(e) => setSelSedes(e.target.checked ? [...selSedes, s.id] : selSedes.filter((x) => x !== s.id))} /> }] : []),
                  { t: 'Sede', r: (s) => <><b>{s.nombre}</b><div className="small muted">{s.ciudad}</div></> },
                  { t: 'Ciclo', r: (s) => s.asignacion ? <>{ciclosMap.get(s.asignacion.ciclo_id)?.codigo ?? '·'}<div className="small muted">{datos.variantes.find((v) => v.id === s.asignacion.variante_id)?.codigo ?? ''} · {s.asignacion.modo_reinicio}</div></> : <span className="chip bad">sin ciclo</span> },
                  { t: 'Menu 1 el', r: (s) => s.asignacion ? fechaCorta(s.asignacion.fecha_inicio_menu1) : '·' },
                  { t: 'Rige desde', r: (s) => s.asignacion ? fechaCorta(s.asignacion.vigente_desde) : '·' },
                  { t: 'Menu de hoy', n: true, r: (s) => s.dia_hoy ? `menu ${s.dia_hoy}` : <span className="muted">sin servicio</span> },
                  { t: 'Marcas futuras', n: true, r: (s) => s.excepciones || '·' },
                  ...(puedeEditar ? [{ t: '', r: (s) => <button className="btn btn-xs" onClick={() => { setSelSedes([s.id]); setAsignar(true); }}>Cambiar</button> }] : []),
                ]} filas={datos.sedes} />
              </>
            )}
            {tab === 'gramajes' && <Gramajes datos={datos} hoy={hoy} puedeEditar={puedeEditar} guardando={guardando}
              onGuardar={(f) => act(() => q(sb().rpc('guardar_gramajes', { p_contrato: contratoId, p_desde: f.desde, p_items: f.items, p_motivo: f.motivo || null })), (n) => `${n} gramajes guardados desde el ${fechaCorta(f.desde)}. Las proyecciones nuevas ya los toman.`)} />}
            {tab === 'calendario' && <Calendario contratoId={contratoId} datos={datos} hoy={hoy} puedeEditar={puedeEditar}
              onMarcar={(f) => act(() => q(sb().rpc('marcar_calendario', { p_contrato: contratoId, p_sedes: f.sedes, p_desde: f.desde, p_hasta: f.hasta, p_atiende: f.atiende, p_motivo: f.motivo || null, p_cuenta_ciclo: f.cuenta })), (n) => f.atiende === null ? 'Marcas quitadas; vuelve a regir la regla del contrato.' : `${n} dias marcados${f.atiende ? ' con servicio' : ' sin servicio'}.`)} />}
            {tab === 'partes' && <Partes contratoId={contratoId} datos={datos} hoy={hoy} unidad={unidad} puedeEditar={puede('M2', 'editar') || puede('M7', 'editar')} />}
          </>
        )}
      </div>
      {nuevoCiclo && datos && <FormCiclo datos={datos} onCerrar={() => setNuevoCiclo(false)} onCrear={async (f) => { const id = await act(() => q(sb().rpc('crear_ciclo', { p_contrato: contratoId, p_codigo: f.codigo, p_nombre: f.nombre || null, p_n_menus: f.n, p_copiar_de: f.copiar })), 'Ciclo creado.'); if (id) { setNuevoCiclo(false); setCicloAbierto(id); } }} />}
      {asignar && datos && <AsignarCiclo datos={datos} sedes={datos.sedes.filter((s) => selSedes.includes(s.id))} hoy={hoy} onCerrar={() => setAsignar(false)}
        onGuardar={async (f) => { const n = await act(() => q(sb().rpc('asignar_ciclo', { p_sedes: f.sedes, p_ciclo: f.ciclo, p_variante: f.variante, p_fecha_inicio_menu1: f.menu1, p_desde: f.desde, p_modo: f.modo })), (n) => `Ciclo asignado a ${n} sedes desde el ${fechaCorta(f.desde)}.`); if (n) { setAsignar(false); setSelSedes([]); } }} />}
    </>
  );
}
