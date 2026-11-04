'use client';
// M2 · Intercambios y novedades: la lista de lo que se aparta de la minuta oficial (para planeacion, operaciones e interventoria).
import { useState } from 'react';
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Tabla, Estado, Consejo } from '@/components/ui';
import { fechaCorta } from '@/lib/fmt';
import { CLASES_INTERCAMBIO, TIPOS_NOVEDAD, ACCIONES_NOVEDAD } from '@/lib/catalogos';

export default function Intercambios() {
  const { empresaId, puede } = useApp();
  const [tab, setTab] = useState('intercambios');
  const [msg, setMsg] = useState(null);
  const x = useCarga(() => q(sb().from('v_intercambios').select('*').eq('empresa_id', empresaId).order('creado_en', { ascending: false }).limit(300)), [empresaId]);
  const n = useCarga(() => q(sb().from('novedades_servicio').select('*, contrato_sedes(sedes(nombre))').eq('empresa_id', empresaId).order('fecha', { ascending: false }).limit(300)), [empresaId]);
  const puedeAprobar = puede('M2', 'aprobar') || puede('M7', 'aprobar');
  const act = async (fn, ok) => { setMsg(null); try { await fn(); setMsg({ ok: true, t: ok }); x.recargar(); n.recargar(); } catch (e) { setMsg({ ok: false, t: e.message }); } };
  const estado = (id, e) => act(() => q(sb().rpc('cambiar_estado_intercambio', { p_id: id, p_estado: e })), `Intercambio ${e.replace('_', ' ')}.`);
  const dec = (id, d) => { if (d === 'anular' && !confirm('Anular devuelve el calendario y el menu a como estaban. ¿Continuar?')) return; act(() => q(sb().rpc('decidir_novedad_servicio', { p_id: id, p_decision: d, p_desplazar: false })), `Novedad ${d === 'aprobar' ? 'aprobada' : d === 'rechazar' ? 'rechazada' : 'anulada'}.`); };

  const colsX = [
    { k: 'sede_nombre', t: 'Sede' },
    { t: 'Que cambia', r: (r) => <><b>{r.tiempo_nombre ?? 'todos los tiempos'}</b> · {r.componente_nombre ?? r.producto_origen}<div className="small muted">{r.preparacion_nueva ?? r.componente_nuevo ?? `${r.producto_origen} → ${r.producto_destino}`}</div></> },
    { t: 'Clase', r: (r) => <span className="small">{CLASES_INTERCAMBIO[r.clase] ?? r.clase}</span> },
    { t: 'Vigencia', r: (r) => <span className="small">{r.dia ? `menu ${r.dia}` : 'todos los dias'} · {fechaCorta(r.vigente_desde)}{r.vigente_hasta ? ` a ${fechaCorta(r.vigente_hasta)}` : ' en adelante'}{r.fuera_de_ventana ? <div className="chip warn">fuera de ventana</div> : null}</span> },
    { k: 'motivo', t: 'Motivo', r: (r) => <span className="small">{r.motivo}{r.soporte ? <div className="muted">Soporte: {r.soporte}</div> : null}</span> },
    { t: 'Estado', r: (r) => <><Estado e={r.estado} />{r.aplica_hoy && r.estado === 'propuesto' ? <div className="small muted">rige (contingencia)</div> : null}</> },
    { t: '', r: (r) => <span className="row gap4 nowrap end">
        {r.estado === 'propuesto' && puedeAprobar && <button className="btn btn-xs" onClick={() => estado(r.id, 'concertado')}>Concertar</button>}
        {r.estado === 'concertado' && puede('M2', 'aprobar') && <button className="btn btn-xs" onClick={() => estado(r.id, 'aprobado_entidad')}>Aprobado por la entidad</button>}
        {['propuesto', 'concertado'].includes(r.estado) && puede('M2', 'aprobar') && <button className="btn btn-xs" onClick={() => estado(r.id, 'rechazado')}>Rechazar</button>}
        {['propuesto', 'concertado', 'aprobado_entidad'].includes(r.estado) && puede('M2', 'aprobar') && <button className="btn btn-xs btn-x" onClick={() => { if (confirm('¿Anular este intercambio?')) estado(r.id, 'anulado'); }}>Anular</button>}
      </span> },
  ];
  const colsN = [
    { t: 'Sede', r: (r) => r.contrato_sedes?.sedes?.nombre ?? 'Todas las sedes' },
    { t: 'Fecha', r: (r) => <>{fechaCorta(r.fecha)}{r.fecha_hasta ? ` a ${fechaCorta(r.fecha_hasta)}` : ''}</> },
    { t: 'Tipo', r: (r) => TIPOS_NOVEDAD[r.tipo] ?? r.tipo },
    { t: 'Accion', r: (r) => <>{ACCIONES_NOVEDAD[r.accion] ?? r.accion}{r.fecha_destino ? <div className="small muted">al {fechaCorta(r.fecha_destino)}</div> : null}</> },
    { k: 'motivo', t: 'Motivo' },
    { t: 'Avisos', r: (r) => r.estado === 'aprobada' ? <span className="row gap4 wrap"><span className={`chip ${r.aviso_entidad_en ? 'ok' : 'warn'}`}>entidad</span><span className={`chip ${r.aviso_interventoria_en ? 'ok' : 'warn'}`}>interventoria</span>{r.aprobada_entidad && <span className="chip ok">aprobada</span>}</span> : '·' },
    { t: 'Estado', r: (r) => <Estado e={r.estado} /> },
    { t: '', r: (r) => <span className="row gap4 nowrap end">
        {r.estado === 'propuesta' && puedeAprobar && <><button className="btn btn-xs btn-p" onClick={() => dec(r.id, 'aprobar')}>Aprobar</button><button className="btn btn-xs" onClick={() => dec(r.id, 'rechazar')}>Rechazar</button></>}
        {r.estado === 'aprobada' && puedeAprobar && <button className="btn btn-xs btn-x" onClick={() => dec(r.id, 'anular')}>Anular</button>}
      </span> },
  ];
  return (
    <>
      <Encabezado titulo="Intercambios y novedades" sub="Todo lo que se aparta de la minuta oficial, con su estado y sus soportes: es lo que se le muestra a la interventoria.">
        <Link href="/programacion" className="btn">Ir a la programacion</Link>
      </Encabezado>
      <Consejo>Los intercambios y las novedades se crean desde la programacion, parado en la celda del dia. Aqui se concertan, se registra la aprobacion de la entidad, se rechazan o se anulan. Una contingencia rige desde que se propone; las demas clases solo cuando estan concertadas.</Consejo>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      <div className="tabs"><button className={tab === 'intercambios' ? 'on' : ''} onClick={() => setTab('intercambios')}>Intercambios de menu ({x.datos?.length ?? '…'})</button><button className={tab === 'novedades' ? 'on' : ''} onClick={() => setTab('novedades')}>Dias sin servicio ({n.datos?.length ?? '…'})</button></div>
      {x.err && <Falla msg={x.err} />}{n.err && <Falla msg={n.err} />}
      <div className="card">
        {tab === 'intercambios' ? (x.cargando && !x.datos ? <Cargando /> : <Tabla cols={colsX} filas={x.datos ?? []} vacio="Todavia no hay intercambios. Se crean desde la programacion." />)
          : (n.cargando && !n.datos ? <Cargando /> : <Tabla cols={colsN} filas={n.datos ?? []} vacio="No hay novedades de servicio registradas." />)}
      </div>
    </>
  );
}
