'use client';
// Programacion multisemana: cuadricula sede x dia con el menu real de cada sede (ciclo + intercambios + novedades).
// Componentes de dominio reutilizables: <SelectorSemanas/>, <Semana/>, <CeldaDia/>, <Leyenda/>.
import { fechaISO, desdeISO, sumarDias, hoyISO } from '@/lib/fmt';

const DIAS_L = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
const MESES_L = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// numero de semana ISO (para el rotulo "Semana 45")
export function semanaISO(iso) {
  const d = desdeISO(iso);
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const dia = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dia);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return Math.ceil(((t - y0) / 86400000 + 1) / 7);
}
export function rotuloSemana(lunes) {
  const a = desdeISO(lunes), b = desdeISO(sumarDias(lunes, 6));
  const r = a.getMonth() === b.getMonth()
    ? `${a.getDate()} al ${b.getDate()} de ${MESES_L[a.getMonth()]}`
    : `${a.getDate()} de ${MESES_L[a.getMonth()]} al ${b.getDate()} de ${MESES_L[b.getMonth()]}`;
  return r + (a.getFullYear() !== new Date().getFullYear() ? ` de ${a.getFullYear()}` : '');
}

// Selector de semanas relativas: -2 -1 | Actual | +1 +2 +3 ... y "agregar semana"
export function SelectorSemanas({ offsets, onChange, maxSemanas = 10 }) {
  const min = Math.min(...offsets), max = Math.max(...offsets);
  const span = max - min + 1;
  const alternar = (o) => {
    const s = new Set(offsets);
    if (s.has(o)) { if (s.size > 1) s.delete(o); } else s.add(o);
    onChange([...s].sort((a, b) => a - b));
  };
  const hoy = hoyISO();
  const rotulo = (o) => { const l = semanasARango([o], hoy).desde; return `Semana ${semanaISO(l)} · ${rotuloSemana(l)}`; };
  const visibles = [];
  for (let o = Math.min(min, -1); o <= Math.max(max, 1); o++) visibles.push(o);
  return (
    <div className="row gap8 centro">
      <div className="prg-semanas" role="group" aria-label="Semanas a mostrar">
        {visibles.map((o) => <button key={o} className={`${offsets.includes(o) ? 'on' : ''}${o === 0 ? ' hoy' : ''}`} onClick={() => alternar(o)} title={rotulo(o)}>{o === 0 ? 'Actual' : o > 0 ? `+${o}` : o}</button>)}
      </div>
      <button className="btn btn-s" disabled={span >= maxSemanas} title={span >= maxSemanas ? `Maximo ${maxSemanas} semanas; quite una para agregar otra` : 'Agrega la semana siguiente a la ultima mostrada'} onClick={() => onChange([...offsets, max + 1].sort((a, b) => a - b))}>Agregar semana siguiente</button>
      <button className="btn btn-s" disabled={span >= maxSemanas} onClick={() => onChange([min - 1, ...offsets].sort((a, b) => a - b))} title="Agrega la semana anterior a la primera mostrada">Semana anterior</button>
    </div>
  );
}

// que se muestra de cada tiempo en la celda: el proteico si existe, si no el primer componente
function resumenTiempo(items) {
  const p = items.find((i) => i.componente === 'PROTEICO') ?? items[0];
  return p;
}

const fechaDM = (iso) => { if (!iso) return ''; const d = desdeISO(iso); return `${d.getDate()}/${d.getMonth() + 1}`; };

export function CeldaDia({ celda, tiempos, novedad, novedadAplicada, sel, onClick, hoy, unidad = 'cupos' }) {
  if (!celda) return <div className="celda-dia sin" />;
  const pasado = celda.fecha < hoy;
  if (!celda.servicio) {
    const ss = celda.sin_servicio;
    const motivo = ss?.motivo ?? '';
    // que paso con el menu de ese dia
    let nota = null;
    if (ss && novedadAplicada) {
      nota = novedadAplicada.accion === 'correr' ? { t: 'el menu se corre al siguiente dia', c: '' }
        : novedadAplicada.accion === 'trasladar' ? { t: `menu trasladado al ${fechaDM(novedadAplicada.fecha_destino)}`, c: 'repo' }
        : { t: 'menu perdido (el ciclo sigue)', c: 'perdido' };
    } else if (ss?.cuenta_ciclo) nota = { t: 'menu perdido (el ciclo sigue)', c: 'perdido' };
    return (
      <button className={`celda-dia sin${sel ? ' sel' : ''}`} onClick={onClick} title={motivo || 'Dia sin servicio'} aria-label={`${celda.fecha}: sin servicio. ${motivo}`}>
        <div className="celda-menu"><span className="n">sin servicio</span>{novedad && <span className="punto novedad" aria-label="novedad propuesta" />}</div>
        {motivo && <div className="small" style={{ lineHeight: 1.25 }}>{motivo}</div>}
        {nota && <div className={`nota ${nota.c}`}>{nota.t}</div>}
      </button>
    );
  }
  const porTiempo = {};
  for (const i of celda.items ?? []) (porTiempo[i.tiempo] ??= []).push(i);
  const clases = new Set((celda.items ?? []).filter((i) => i.clase).map((i) => (i.estado === 'propuesto' && i.clase !== 'contingencia') ? 'propuesto' : i.clase));
  // tiempos que la sede realmente sirve: si hay cupos por tiempo (PAE), solo los que tienen cupos; si no, todos
  const pt = celda.cupos?.por_tiempo;
  const activos = pt ? tiempos.filter((t) => (pt[t.codigo] ?? 0) > 0 && porTiempo[t.codigo]) : tiempos.filter((t) => porTiempo[t.codigo]);
  // una sola modalidad (un colegio solo RPS, o solo RI): caben todos los componentes en la celda
  const completo = activos.length === 1;
  return (
    <button className={`celda-dia${sel ? ' sel' : ''}${pasado ? ' pasado' : ''}`} onClick={onClick} aria-label={`${celda.fecha}: menu ${celda.dia ?? ''}`}>
      <div className="celda-menu"><span className="n">Menu {celda.dia ?? '·'}</span>
        <span className="row gap4 nowrap">
          {celda.cupos?.total != null && <span className="cupos" title={`${nf(celda.cupos.total)} ${unidad}${celda.cupos.dieta ? ` · ${nf(celda.cupos.dieta)} en dieta` : ''}${celda.cupos.por_tiempo ? ' · ' + Object.entries(celda.cupos.por_tiempo).map(([k, v]) => `${k} ${nf(v)}`).join(', ') : ''}`}>{nf(celda.cupos.total)}{celda.cupos.dieta ? <i> +{nf(celda.cupos.dieta)}d</i> : null}</span>}
          {novedad && <span className="punto novedad" title="Novedad propuesta para este dia" aria-label="novedad propuesta" />}
        </span></div>
      {celda.excepcion?.tipo === 'dia_forzado' && <div className="nota repo">{celda.excepcion.desde ? `trasladado del ${fechaDM(celda.excepcion.desde)}` : 'dia forzado'}</div>}
      {celda.reposicion && <div className="nota repo">jornada de reposicion</div>}
      {completo ? (
        <>
          <div className="celda-tiempo"><b>{activos[0].codigo}</b><span className="muted">{activos[0].nombre}</span></div>
          {porTiempo[activos[0].codigo].map((i) => (
            <div key={i.componente_id} className={`celda-tiempo comp${i.origen !== 'ciclo' ? ' cambio' : ''}${i.estado === 'propuesto' && i.clase !== 'contingencia' ? ' propuesto' : ''}`} title={`${i.componente}: ${i.preparacion ?? '(sin receta)'}`}><b>{i.componente.slice(0, 5)}</b><span>{i.preparacion ?? '(sin receta)'}</span></div>))}
        </>
      ) : activos.map((t) => {
        const its = porTiempo[t.codigo];
        const r = resumenTiempo(its);
        const cambio = its.some((i) => i.origen !== 'ciclo');
        const prop = its.some((i) => i.estado === 'propuesto' && i.clase !== 'contingencia');
        return <div key={t.codigo} className={`celda-tiempo${cambio ? ' cambio' : ''}${prop ? ' propuesto' : ''}`} title={its.map((i) => `${i.componente}: ${i.preparacion ?? '(sin receta)'}`).join('\n')}><b>{t.codigo}</b><span>{r?.preparacion ?? '(sin receta)'}</span></div>;
      })}
      {clases.size > 0 && <div className="celda-marcas">{[...clases].map((c) => <span key={c} className={`punto ${c}`} title={c} />)}</div>}
    </button>
  );
}

export const unidadCupos = (modalidad) => modalidad === 'uspec_ppl' ? 'PPL' : modalidad === 'pae' ? 'estudiantes' : modalidad === 'icbf_primera_infancia' ? 'ninos' : 'cupos';
const nf = (n) => n == null ? '·' : Number(n).toLocaleString('es-CO');

// Fila de la cuadricula: una sede, o un grupo de sedes que comparten exactamente el mismo menu en el rango
export function FilaRotulo({ fila, sedesMap, unidad, abierto, onAbrir, servidos, total }) {
  const nombres = fila.sedes.map((id) => sedesMap.get(id)?.nombre ?? '·');
  if (fila.n === 1) {
    const s = sedesMap.get(fila.rep);
    return <div className="prg-sede">{s?.nombre}<span>{s?.ciudad}{s?.cupos ? ` · ${nf(s.cupos)} ${unidad}` : ''}</span></div>;
  }
  return (
    <div className="prg-sede">
      <span style={{ color: fila.estandar ? 'var(--primario)' : 'inherit' }}>{fila.estandar ? 'Menu estandar' : 'Mismo menu'}{servidos?.length ? ` · ${servidos.join('+')}` : ''}</span>
      {total > 0 && <span>{nf(total)} {unidad}</span>}
      <button className="btn btn-xs" style={{ alignSelf: 'flex-start' }} onClick={onAbrir} aria-expanded={abierto}>{fila.n} sedes {abierto ? '▴' : '▾'}</button>
      {abierto && <div className="small" style={{ lineHeight: 1.3 }}>{nombres.join(' · ')}</div>}
    </div>
  );
}

export function Semana({ lunes, filas, sedesMap, celdas, tiempos, novedades, dias, hoy, sel, onCelda, unidad, abiertos, onAbrir }) {
  const fechas = Array.from({ length: 7 }, (_, i) => sumarDias(lunes, i));
  const festivo = (f) => dias.find((d) => d.fecha === f)?.festivo;
  return (
    <section className="prg-semana">
      <h3><b>Semana {semanaISO(lunes)}</b> {rotuloSemana(lunes)}{lunes <= hoy && sumarDias(lunes, 6) >= hoy && <span className="chip info">esta semana</span>}</h3>
      <div className="prg-scroll">
        <div className="prg-tabla">
          <div />
          {fechas.map((f, i) => <div key={f} className={`prg-cab${f === hoy ? ' hoy' : ''}${festivo(f) ? ' festivo' : ''}`} title={festivo(f) ?? ''}>{DIAS_L[i]}<b>{desdeISO(f).getDate()}</b>{festivo(f) && <span className="small">festivo</span>}</div>)}
          {filas.map((fila) => {
            const s = sedesMap.get(fila.rep);
            return (
            <div key={fila.rep} style={{ display: 'contents' }}>
              <FilaRotulo fila={fila} sedesMap={sedesMap} unidad={unidad} abierto={!!abiertos[fila.rep]} onAbrir={() => onAbrir(fila.rep)}
                servidos={tiempos.filter((t) => fechas.some((f) => (celdas.get(`${fila.rep}|${f}`)?.cupos?.por_tiempo?.[t.codigo] ?? 0) > 0)).map((t) => t.codigo)}
                total={Math.max(0, ...fechas.map((f) => celdas.get(`${fila.rep}|${f}`)?.cupos?.total ?? 0))} />
              {fechas.map((f) => {
                const c = celdas.get(`${fila.rep}|${f}`);
                const enFecha = novedades.filter((n) => n.fecha <= f && (n.fecha_hasta ?? n.fecha) >= f && (!n.sede_id || fila.sedes.includes(n.sede_id)));
                const nov = enFecha.find((n) => n.estado === 'propuesta');
                const apl = enFecha.find((n) => n.estado === 'aprobada' && (c?.sin_servicio?.novedad_id ? n.id === c.sin_servicio.novedad_id : true));
                return <CeldaDia key={f} celda={c} tiempos={tiempos} novedad={nov} novedadAplicada={apl} hoy={hoy} unidad={unidad} sel={sel?.sede_id === fila.rep && sel?.fecha === f} onClick={() => onCelda(s, f, c, fila)} />;
              })}
            </div>);
          })}
        </div>
      </div>
    </section>
  );
}

export function Leyenda() {
  return (
    <div className="leyenda" aria-label="Leyenda">
      <span><b style={{ color: 'var(--info)' }}>Texto azul</b>: menu distinto al ciclo oficial</span>
      <span><i className="punto concertado" /> concertado</span>
      <span><i className="punto temporada" /> temporada</span>
      <span><i className="punto contingencia" /> contingencia</span>
      <span><i className="punto especial" /> especial</span>
      <span><i className="punto propuesto" /> intercambio propuesto (no rige)</span>
      <span><i className="punto novedad" /> novedad por aprobar</span>
      <span><i className="punto sin" /> sin servicio</span>
      <span><i className="punto festivo" /> festivo</span>
      <span><b style={{ color: 'var(--acento-texto)' }}>Fecha ambar</b>: hoy</span>
    </div>
  );
}

export function semanasARango(offsets, hoy = hoyISO()) {
  const d = desdeISO(hoy); const dow = (d.getDay() + 6) % 7; d.setDate(d.getDate() - dow);
  const lunes0 = fechaISO(d);
  const lunes = offsets.map((o) => sumarDias(lunes0, o * 7));
  return { lunes, desde: lunes[0], hasta: sumarDias(lunes[lunes.length - 1], 6) };
}
