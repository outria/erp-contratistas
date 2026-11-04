'use client';
// Panel lateral de un dia en una sede: menu completo por tiempo y componente, intercambio desde la celda,
// novedades de servicio (dia sin clases) y las decisiones sobre ambas.
import { useEffect, useMemo, useState } from 'react';
import { useApp } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Panel, Estado, Campo, Falla, Info } from '@/components/ui';
import { fechaCorta, sumarDias, num } from '@/lib/fmt';
import { CLASES_INTERCAMBIO, TIPOS_NOVEDAD, ACCIONES_NOVEDAD } from '@/lib/catalogos';

export function PanelDia({ sede, fecha, celda, datos, onCerrar, onCambio }) {
  const { puede, empresaId } = useApp();
  const [modo, setModo] = useState(null);        // null | {tipo:'intercambio', item} | {tipo:'novedad'}
  const [msg, setMsg] = useState(null);
  const tiempos = datos.tiempos ?? [];
  const items = celda?.items ?? [];
  const porTiempo = useMemo(() => { const m = {}; for (const i of items) (m[i.tiempo] ??= []).push(i); return m; }, [items]);
  const novedades = (datos.novedades ?? []).filter((n) => n.fecha <= fecha && (n.fecha_hasta ?? n.fecha) >= fecha && (!n.sede_id || n.sede_id === sede.id));
  const puedeProponer = puede('M2', 'crear') || puede('M7', 'crear');
  const puedeAprobar = puede('M2', 'aprobar') || puede('M7', 'aprobar');
  const contrato = datos.contrato;

  const accion = async (fn, ok) => {
    setMsg(null);
    try { await fn(); setMsg({ ok: true, t: ok }); setModo(null); onCambio?.(); } catch (e) { setMsg({ ok: false, t: e.message }); }
  };
  const estadoIntercambio = (id, estado) => accion(() => q(sb().rpc('cambiar_estado_intercambio', { p_id: id, p_estado: estado })), `Intercambio ${estado}.`);
  const decidirNovedad = (id, d) => accion(() => q(sb().rpc('decidir_novedad_servicio', { p_id: id, p_decision: d })), `Novedad ${d === 'aprobar' ? 'aprobada y aplicada al calendario' : d === 'rechazar' ? 'rechazada' : 'anulada'}.`);
  const aviso = (id, a) => accion(() => q(sb().rpc('registrar_aviso_novedad', { p_id: id, p_a: a })), 'Aviso registrado.');

  return (
    <Panel titulo={`${sede.nombre}`} sub={`${fechaCorta(fecha)}${celda?.dia ? ` · menu ${celda.dia} del ciclo` : ''}${!celda?.servicio ? ' · sin servicio' : ''}`} onCerrar={onCerrar}>
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'}`}>{msg.t}</div>}

      {novedades.map((n) => (
        <div key={n.id} className={`aviso ${n.estado === 'aprobada' ? 'info' : ''}`}>
          <div className="row between gap8">
            <b>{TIPOS_NOVEDAD[n.tipo] ?? n.tipo} · {ACCIONES_NOVEDAD[n.accion] ?? n.accion}{n.fecha_destino ? ` al ${fechaCorta(n.fecha_destino)}` : ''}</b>
            <Estado e={n.estado} />
          </div>
          <div className="small">{n.motivo}{n.sede_id ? '' : ' · todas las sedes'}{n.fecha_hasta && n.fecha_hasta !== n.fecha ? ` · del ${fechaCorta(n.fecha)} al ${fechaCorta(n.fecha_hasta)}` : ''}</div>
          {n.materia_prima?.productos?.length > 0 && (
            <details className="small mt8"><summary>Materia prima de ese dia ({n.materia_prima.productos.length} productos, {num(n.materia_prima.raciones)} raciones)</summary>
              <ul style={{ margin: '4px 0 0 16px', padding: 0 }}>{n.materia_prima.productos.slice(0, 12).map((p) => <li key={p.producto_id}>{p.nombre}: <b>{num(p.cantidad_compra, 1)} {p.unidad_compra}</b></li>)}{n.materia_prima.productos.length > 12 && <li>… y {n.materia_prima.productos.length - 12} mas</li>}</ul>
            </details>)}
          <div className="row gap6 mt8 wrap">
            {n.estado === 'propuesta' && puedeAprobar && <><button className="btn btn-s btn-p" onClick={() => decidirNovedad(n.id, 'aprobar')}>Aprobar y aplicar</button><button className="btn btn-s" onClick={() => decidirNovedad(n.id, 'rechazar')}>Rechazar</button></>}
            {n.estado === 'aprobada' && <>
              <span className={`chip ${n.aviso_entidad_en ? 'ok' : 'warn'}`}>{n.aviso_entidad_en ? 'entidad avisada' : 'falta avisar a la entidad'}</span>
              <span className={`chip ${n.aviso_interventoria_en ? 'ok' : 'warn'}`}>{n.aviso_interventoria_en ? 'interventoria avisada' : 'falta avisar a la interventoria'}</span>
              {!n.aviso_entidad_en && (puede('M8', 'crear') || puedeAprobar) && <button className="btn btn-xs" onClick={() => aviso(n.id, 'entidad')}>Registrar aviso a entidad</button>}
              {!n.aviso_interventoria_en && (puede('M8', 'crear') || puedeAprobar) && <button className="btn btn-xs" onClick={() => aviso(n.id, 'interventoria')}>Registrar aviso a interventoria</button>}
              {!n.aprobada_entidad && puedeAprobar && <button className="btn btn-xs" onClick={() => aviso(n.id, 'aprobada_entidad')}>La entidad aprobo</button>}
              {n.aprobada_entidad && <span className="chip ok">aprobada por la entidad</span>}
              {puedeAprobar && <button className="btn btn-xs btn-x" onClick={() => { if (confirm('Anular la novedad devuelve el calendario y el menu a como estaban. ¿Continuar?')) decidirNovedad(n.id, 'anular'); }}>Anular</button>}
            </>}
          </div>
        </div>
      ))}

      {modo?.tipo === 'novedad' ? (
        <FormNovedad sede={sede} fecha={fecha} contrato={contrato} empresaId={empresaId} onListo={() => accion(async () => {}, 'Novedad propuesta. Operaciones recibira el aviso para aprobarla.')} onCancelar={() => setModo(null)} />
      ) : modo?.tipo === 'intercambio' ? (
        <FormIntercambio sede={sede} fecha={fecha} celda={celda} item={modo.item} contrato={contrato} empresaId={empresaId} tiempos={tiempos}
          onListo={() => accion(async () => {}, 'Intercambio registrado.')} onCancelar={() => setModo(null)} />
      ) : (
        <>
          {celda?.servicio && tiempos.map((t) => {
            const its = porTiempo[t.codigo];
            if (!its) return null;
            return (
              <div key={t.codigo} className="tiempo-bloque">
                <h4>{t.nombre}<span className="muted small">{t.codigo}</span></h4>
                {its.map((i) => (
                  <div key={i.componente_id} className="comp-fila">
                    <span className="cc">{i.componente}</span>
                    <span>
                      {i.preparacion ?? <span className="muted">(sin receta asignada)</span>}
                      {i.origen !== 'ciclo' && <div className={`origen${i.estado === 'propuesto' ? ' propuesto' : ''}`}>{CLASES_INTERCAMBIO[i.clase] ?? 'intercambio'}{i.estado ? ` · ${i.estado.replace(/_/g, ' ')}` : ''}</div>}
                    </span>
                    <span className="row gap4 nowrap">
                      {i.intercambio_id && i.estado === 'propuesto' && (puede('M2', 'aprobar') || puede('M7', 'aprobar')) && <button className="btn btn-xs" title="Concertar con la poblacion" onClick={() => estadoIntercambio(i.intercambio_id, 'concertado')}>Concertar</button>}
                      {i.intercambio_id && i.estado === 'concertado' && puede('M2', 'aprobar') && <button className="btn btn-xs" title="La entidad lo aprobo" onClick={() => estadoIntercambio(i.intercambio_id, 'aprobado_entidad')}>Entidad OK</button>}
                      {puedeProponer && <button className="btn btn-xs btn-n" onClick={() => setModo({ tipo: 'intercambio', item: i })}>Cambiar</button>}
                    </span>
                  </div>
                ))}
              </div>
            );
          })}
          {celda?.servicio && items.length === 0 && <div className="vacio">Este dia no tiene menu: la sede no tiene ciclo asignado o el ciclo aun no empieza.</div>}
          <div className="row gap8 wrap">
            {puedeProponer && celda?.servicio && !novedades.some((n) => n.estado === 'propuesta') && <button className="btn" onClick={() => setModo({ tipo: 'novedad' })}>⚠ Reportar dia sin servicio</button>}
            {puedeProponer && !celda?.servicio && !celda?.sin_servicio && <button className="btn" onClick={() => setModo({ tipo: 'novedad' })}>Registrar novedad</button>}
          </div>
        </>
      )}
    </Panel>
  );
}

// ---- Intercambio desde la celda: sugerencias de la familia, otra opcion en caliente, alcance y vigencia
function FormIntercambio({ sede, fecha, celda, item, contrato, empresaId, tiempos, onListo, onCancelar }) {
  const [sug, setSug] = useState(null);
  const [err, setErr] = useState(null);
  const [sel, setSel] = useState(null);
  const [otra, setOtra] = useState(false);
  const [nueva, setNueva] = useState({ nombre: '', producto: '' });
  const [f, setF] = useState({ clase: 'concertado', alcance: 'sede', vigencia: 'dia', hasta: '', motivo: '', soporte: '' });
  const [guardando, setGuardando] = useState(false);
  const tiempo = tiempos.find((t) => t.codigo === item.tiempo);
  const familiaId = (celda?.items ?? []).length ? null : null;

  useEffect(() => {
    q(sb().rpc('sugerir_intercambios', { p_contrato_sede: sede.id, p_fecha: fecha, p_tiempo_comida: tiempo?.id, p_componente: item.componente_id }))
      .then(setSug).catch((e) => setErr(e.message));
  }, [sede.id, fecha, tiempo?.id, item.componente_id]);

  const grupos = useMemo(() => {
    const g = new Map();
    for (const o of sug ?? []) { if (o.es_actual) continue; const k = o.subfamilia ?? 'Otros'; (g.get(k) ?? g.set(k, []).get(k)).push(o); }
    return [...g.entries()].sort((a, b) => (b[1].some((o) => o.misma_subfamilia) ? 1 : 0) - (a[1].some((o) => o.misma_subfamilia) ? 1 : 0));
  }, [sug]);

  const guardar = async () => {
    setGuardando(true); setErr(null);
    try {
      let prep = sel?.preparacion_id;
      if (otra) {
        if (!nueva.nombre.trim()) throw new Error('Escriba el nombre de la preparacion nueva.');
        const comp = await q(sb().from('componentes').select('familia_id').eq('id', item.componente_id).single());
        const op = await q(sb().rpc('agregar_opcion_familia', { p_familia: comp.familia_id, p_preparacion: null, p_producto: null, p_nombre: nueva.nombre.trim(), p_producto_nuevo: nueva.producto.trim() || nueva.nombre.trim(), p_nota: f.motivo || 'Agregada desde la programacion' }));
        const o = await q(sb().from('familia_opciones').select('preparacion_id').eq('id', op).single());
        prep = o.preparacion_id;
      }
      if (!prep) throw new Error('Escoja la preparacion que reemplaza.');
      if (!f.motivo.trim()) throw new Error('Escriba el motivo.');
      if (f.vigencia === 'hasta' && !f.hasta) throw new Error('Indique hasta que fecha.');
      if ((f.clase === 'temporada' || f.clase === 'contingencia') && f.vigencia === 'ciclo') throw new Error('Temporada y contingencia necesitan fecha final.');
      const fila = {
        empresa_id: empresaId, contrato_id: contrato.id, contrato_sede_id: f.alcance === 'sede' ? sede.id : null,
        clase: f.clase, tipo_cambio: 'preparacion', dia: f.vigencia === 'todos' ? null : celda.dia, tiempo_comida_id: tiempo?.id, componente_id: item.componente_id,
        preparacion_nueva_id: prep, vigente_desde: fecha, vigente_hasta: f.vigencia === 'dia' ? fecha : f.vigencia === 'hasta' ? f.hasta : null,
        motivo: f.motivo.trim(), soporte: f.soporte.trim() || null,
      };
      await q(sb().from('intercambios_menu').insert(fila));
      onListo();
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  };

  return (
    <div className="stack gap12">
      <div className="row between"><h3 className="m0">Cambiar {item.componente.toLowerCase()} de {tiempo?.nombre?.toLowerCase()}</h3><button className="btn btn-xs" onClick={onCancelar}>Volver</button></div>
      <div className="small muted">Hoy toca <b>{item.preparacion ?? '(sin receta)'}</b>. Las opciones salen de la familia de intercambio de este componente, con lo que dice la rotacion de la semana.</div>
      {err && <Falla msg={err} />}
      {!sug && !err && <div className="vacio">Buscando opciones…</div>}
      {sug && grupos.length === 0 && <div className="vacio">La familia de este componente no tiene otras opciones. Agregue una abajo.</div>}
      {grupos.map(([sub, ops]) => (
        <div key={sub}>
          <div className="grupo-sub">{sub}{ops.some((o) => o.misma_subfamilia) && <span className="chip info" style={{ marginLeft: 6 }}>misma familia</span>}</div>
          <div className="stack gap6">
            {ops.map((o) => (
              <button key={o.opcion_id} className={`opcion${sel?.opcion_id === o.opcion_id ? ' on' : ''}${o.rompe_rotacion ? ' rompe' : ''}`} onClick={() => { setSel(o); setOtra(false); }}>
                <span>{o.preparacion_nombre}{o.ultima_vez && <span className="sub">ultima vez {fechaCorta(o.ultima_vez)}</span>}</span>
                <span className="flags">
                  {o.en_minuta && <span className="chip">en minuta</span>}
                  {o.es_extraordinaria && <span className="chip warn">extraordinaria</span>}
                  {o.estado === 'propuesta' && <span className="chip warn">por aprobar</span>}
                  {o.rompe_rotacion && <span className="chip bad" title={`Ya aparece ${o.veces_en_ventana} veces en la ventana de rotacion`}>repite</span>}
                </span>
              </button>))}
          </div>
        </div>
      ))}
      <button className={`opcion${otra ? ' on' : ''}`} onClick={() => { setOtra(true); setSel(null); }}>
        <span>＋ Otra opcion que no esta en la lista<span className="sub">Contingencia: lo que se concerto con la poblacion (un chorizo, un embutido…). Queda propuesta para que planeacion la apruebe.</span></span>
      </button>
      {otra && (
        <div className="grid g2">
          <Campo l="Nombre de la preparacion" req><input value={nueva.nombre} onChange={(e) => setNueva({ ...nueva, nombre: e.target.value })} placeholder="Chorizo asado" /></Campo>
          <Campo l="Producto (materia prima)" ayuda="Si el producto no existe en el catalogo se crea pendiente de revision por maestros."><input value={nueva.producto} onChange={(e) => setNueva({ ...nueva, producto: e.target.value })} placeholder="Chorizo de cerdo" /></Campo>
        </div>
      )}

      <div className="tiempo-bloque stack gap10">
        <Campo l="Clase de intercambio">
          <div className="radio-fila">{Object.entries(CLASES_INTERCAMBIO).map(([k, v]) => <label key={k} className={f.clase === k ? 'on' : ''}><input type="radio" checked={f.clase === k} onChange={() => setF({ ...f, clase: k, vigencia: (k === 'temporada' || k === 'contingencia') && f.vigencia === 'ciclo' ? 'hasta' : f.vigencia })} />{v}</label>)}</div>
        </Campo>
        <Campo l="Alcance">
          <div className="radio-fila">
            <label className={f.alcance === 'sede' ? 'on' : ''}><input type="radio" checked={f.alcance === 'sede'} onChange={() => setF({ ...f, alcance: 'sede' })} />Solo {sede.nombre}</label>
            <label className={f.alcance === 'contrato' ? 'on' : ''}><input type="radio" checked={f.alcance === 'contrato'} onChange={() => setF({ ...f, alcance: 'contrato' })} />Todas las sedes del contrato</label>
          </div>
        </Campo>
        <Campo l="Vigencia">
          <div className="radio-fila">
            <label className={f.vigencia === 'dia' ? 'on' : ''}><input type="radio" checked={f.vigencia === 'dia'} onChange={() => setF({ ...f, vigencia: 'dia' })} />Solo este dia ({fechaCorta(fecha)})</label>
            <label className={f.vigencia === 'hasta' ? 'on' : ''}><input type="radio" checked={f.vigencia === 'hasta'} onChange={() => setF({ ...f, vigencia: 'hasta' })} />Cada vez que toque el menu {celda.dia}, hasta una fecha</label>
            {f.clase !== 'temporada' && f.clase !== 'contingencia' && <label className={f.vigencia === 'ciclo' ? 'on' : ''}><input type="radio" checked={f.vigencia === 'ciclo'} onChange={() => setF({ ...f, vigencia: 'ciclo' })} />Cada vez que toque el menu {celda.dia}, indefinido</label>}
          </div>
          {f.vigencia === 'hasta' && <input type="date" value={f.hasta} min={fecha} onChange={(e) => setF({ ...f, hasta: e.target.value })} style={{ maxWidth: 200, marginTop: 6 }} />}
        </Campo>
        <Campo l="Motivo" req><textarea rows={2} value={f.motivo} onChange={(e) => setF({ ...f, motivo: e.target.value })} placeholder={f.clase === 'contingencia' ? 'Derrumbe en la via: no llego la res' : f.clase === 'temporada' ? 'Escasez de pechuga por fenomeno del nino' : 'Concertado con la poblacion en reunion del…'} /></Campo>
        <Campo l="Soporte (oficio, correo, acta)" ayuda="Obligatorio para concertar un intercambio fuera de la ventana de los 15 dias habiles."><input value={f.soporte} onChange={(e) => setF({ ...f, soporte: e.target.value })} placeholder="Oficio 123 del …" /></Campo>
        {f.clase === 'contingencia' && <div className="aviso small">La contingencia rige de inmediato y dispara el aviso interno a planeacion y calidad: recuerde avisar a la entidad y a la interventoria segun el protocolo.</div>}
        <div className="row end gap8"><button className="btn" onClick={onCancelar}>Cancelar</button><button className="btn btn-p" disabled={guardando || (!sel && !otra)} onClick={guardar}>{guardando ? 'Guardando…' : 'Registrar intercambio'}</button></div>
      </div>
    </div>
  );
}

// ---- Novedad de servicio: "manana no hay clases"
function FormNovedad({ sede, fecha, contrato, empresaId, onListo, onCancelar }) {
  const [f, setF] = useState({ tipo: 'sin_clases', hasta: fecha, alcance: 'sede', accion: contrato?.dias_atencion === 'todos' ? 'perder' : 'correr', destino: sumarDias(fecha, 7), motivo: '', soporte: '' });
  const [err, setErr] = useState(null);
  const [guardando, setGuardando] = useState(false);
  const guardar = async () => {
    setGuardando(true); setErr(null);
    try {
      if (!f.motivo.trim()) throw new Error('Escriba el motivo.');
      await q(sb().from('novedades_servicio').insert({
        empresa_id: empresaId, contrato_id: contrato.id, contrato_sede_id: f.alcance === 'sede' ? sede.id : null,
        fecha, fecha_hasta: f.hasta && f.hasta !== fecha ? f.hasta : null, tipo: f.tipo, accion: f.accion, fecha_destino: f.accion === 'trasladar' ? f.destino : null,
        motivo: f.motivo.trim(), soporte: f.soporte.trim() || null,
      }));
      onListo();
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  };
  return (
    <div className="stack gap12">
      <div className="row between"><h3 className="m0">Dia sin servicio</h3><button className="btn btn-xs" onClick={onCancelar}>Volver</button></div>
      <div className="small muted">Se guarda la foto de la materia prima que pedia ese dia. La direccion de operaciones aprueba, se avisa a la entidad y a la interventoria, y el calendario y el menu se ajustan solos.</div>
      {err && <Falla msg={err} />}
      <div className="grid g2">
        <Campo l="Tipo"><select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })}>{Object.entries(TIPOS_NOVEDAD).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
        <Campo l="Hasta (si son varios dias)"><input type="date" value={f.hasta} min={fecha} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></Campo>
      </div>
      <Campo l="Alcance">
        <div className="radio-fila">
          <label className={f.alcance === 'sede' ? 'on' : ''}><input type="radio" checked={f.alcance === 'sede'} onChange={() => setF({ ...f, alcance: 'sede' })} />Solo {sede.nombre}</label>
          <label className={f.alcance === 'contrato' ? 'on' : ''}><input type="radio" checked={f.alcance === 'contrato'} onChange={() => setF({ ...f, alcance: 'contrato' })} />Todas las sedes (paro, orden publico)</label>
        </div>
      </Campo>
      <Campo l="Que pasa con el menu y la materia prima">
        <div className="stack gap6">
          {Object.entries(ACCIONES_NOVEDAD).map(([k, v]) => (
            <button key={k} className={`opcion${f.accion === k ? ' on' : ''}`} onClick={() => setF({ ...f, accion: k })}>
              <span>{v}<span className="sub">{k === 'correr' ? 'El menu de ese dia se sirve el siguiente dia de servicio y todo lo demas se corre. Lo normal en PAE: no se pierde nada.' : k === 'trasladar' ? 'Ese menu se sirve en la fecha que escoja (dentro de 2 o 3 dias o la semana siguiente); los demas dias no se mueven.' : 'El ciclo sigue como si el dia se hubiera servido; la materia prima queda para redistribuir.'}</span></span>
            </button>))}
        </div>
      </Campo>
      {f.accion === 'trasladar' && <Campo l="Fecha en que se sirve ese menu" req><input type="date" value={f.destino} min={sumarDias(fecha, 1)} onChange={(e) => setF({ ...f, destino: e.target.value })} style={{ maxWidth: 200 }} /></Campo>}
      <Campo l="Motivo" req><textarea rows={2} value={f.motivo} onChange={(e) => setF({ ...f, motivo: e.target.value })} placeholder="El rector avisa que manana no hay clases por jornada deportiva" /></Campo>
      <Campo l="Soporte (circular, correo del rector, comunicado)"><input value={f.soporte} onChange={(e) => setF({ ...f, soporte: e.target.value })} /></Campo>
      <div className="row end gap8"><button className="btn" onClick={onCancelar}>Cancelar</button><button className="btn btn-p" disabled={guardando} onClick={guardar}>{guardando ? 'Guardando…' : 'Proponer novedad'}</button></div>
    </div>
  );
}
