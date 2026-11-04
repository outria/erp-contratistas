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

export function CeldaDia({ celda, tiempos, novedad, novedadAplicada, sel, onClick, hoy }) {
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
  return (
    <button className={`celda-dia${sel ? ' sel' : ''}${pasado ? ' pasado' : ''}`} onClick={onClick} aria-label={`${celda.fecha}: menu ${celda.dia ?? ''}`}>
      <div className="celda-menu"><span className="n">Menu {celda.dia ?? '·'}</span>{novedad && <span className="punto novedad" title="Novedad propuesta para este dia" aria-label="novedad propuesta" />}</div>
      {celda.excepcion?.tipo === 'dia_forzado' && <div className="nota repo">{celda.excepcion.desde ? `trasladado del ${fechaDM(celda.excepcion.desde)}` : 'dia forzado'}</div>}
      {celda.reposicion && <div className="nota repo">jornada de reposicion</div>}
      {tiempos.map((t) => {
        const its = porTiempo[t.codigo];
        if (!its) return null;
        const r = resumenTiempo(its);
        const cambio = its.some((i) => i.origen !== 'ciclo');
        const prop = its.some((i) => i.estado === 'propuesto' && i.clase !== 'contingencia');
        return <div key={t.codigo} className={`celda-tiempo${cambio ? ' cambio' : ''}${prop ? ' propuesto' : ''}`} title={its.map((i) => `${i.componente}: ${i.preparacion ?? '(sin receta)'}`).join('\n')}><b>{t.codigo}</b><span>{r?.preparacion ?? '(sin receta)'}</span></div>;
      })}
      {clases.size > 0 && <div className="celda-marcas">{[...clases].map((c) => <span key={c} className={`punto ${c}`} title={c} />)}</div>}
    </button>
  );
}

export function Semana({ lunes, sedes, celdas, tiempos, novedades, dias, hoy, sel, onCelda }) {
  const fechas = Array.from({ length: 7 }, (_, i) => sumarDias(lunes, i));
  const festivo = (f) => dias.find((d) => d.fecha === f)?.festivo;
  return (
    <section className="prg-semana">
      <h3><b>Semana {semanaISO(lunes)}</b> {rotuloSemana(lunes)}{lunes <= hoy && sumarDias(lunes, 6) >= hoy && <span className="chip info">esta semana</span>}</h3>
      <div className="prg-scroll">
        <div className="prg-tabla">
          <div />
          {fechas.map((f, i) => <div key={f} className={`prg-cab${f === hoy ? ' hoy' : ''}${festivo(f) ? ' festivo' : ''}`} title={festivo(f) ?? ''}>{DIAS_L[i]}<b>{desdeISO(f).getDate()}</b>{festivo(f) && <span className="small">festivo</span>}</div>)}
          {sedes.map((s) => (
            <div key={s.id} style={{ display: 'contents' }}>
              <div className="prg-sede">{s.nombre}<span>{s.ciudad}{s.cupos ? ` · ${s.cupos} cupos` : ''}</span></div>
              {fechas.map((f) => {
                const c = celdas.get(`${s.id}|${f}`);
                const enFecha = novedades.filter((n) => n.fecha <= f && (n.fecha_hasta ?? n.fecha) >= f && (!n.sede_id || n.sede_id === s.id));
                const nov = enFecha.find((n) => n.estado === 'propuesta');
                const apl = enFecha.find((n) => n.estado === 'aprobada' && (c?.sin_servicio?.novedad_id ? n.id === c.sin_servicio.novedad_id : true));
                return <CeldaDia key={f} celda={c} tiempos={tiempos} novedad={nov} novedadAplicada={apl} hoy={hoy} sel={sel?.sede_id === s.id && sel?.fecha === f} onClick={() => onCelda(s, f, c)} />;
              })}
            </div>
          ))}
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
