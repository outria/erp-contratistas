'use client';
import { useEffect, useRef, useState } from 'react';
import { num } from '@/lib/fmt';

export function Encabezado({ titulo, sub, children }) {
  return (
    <div className="top">
      <div>
        <h1>{titulo}</h1>
        {sub && <p className="muted">{sub}</p>}
      </div>
      {children && <div className="row no-print">{children}</div>}
    </div>
  );
}

export function Kpi({ v, l, d = 0, sufijo }) {
  return (
    <div className="card kpi">
      <span className="v">{typeof v === 'number' ? num(v, d) : v}{sufijo ? <small className="muted"> {sufijo}</small> : null}</span>
      <span className="l">{l}</span>
    </div>
  );
}

export function Barra({ valor, meta, etiqueta, de = 'de la meta', tope = 1.05 }) {
  const pct = meta ? Math.min(100, (valor / meta) * 100) : 0;
  const clase = !meta ? '' : valor > meta * tope ? 'bad' : valor >= meta * 0.95 ? 'ok' : '';
  return (
    <div className="stack gap4">
      <div className="row between small">
        <span>{etiqueta}</span>
        <span className="muted">{meta ? `${num((valor / meta) * 100)} % ${de}` : 'sin meta'}</span>
      </div>
      <div className={`barra ${clase}`}><i style={{ width: `${pct}%` }} /></div>
    </div>
  );
}

// Estados del dominio de Supply ERP (contratos, planeacion, intercambios, explosiones, proveedores...)
const ESTADOS = {
  // generales
  borrador: '', activo: 'ok', activa: 'ok', vigente: 'ok', inactivo: 'warn', inactiva: 'warn', suspendido: 'warn', suspendida: 'warn', anulado: 'bad', anulada: 'bad', liquidado: 'info', terminado: 'info', pendiente: 'warn',
  // intercambios y novedades
  propuesto: 'warn', propuesta: 'warn', concertado: 'info', aprobado_entidad: 'ok', rechazado: 'bad', vencido: '', retirada: 'bad',
  // explosiones y requerimientos
  parcial: 'warn', calculada: 'info', calculando: 'warn', aprobada: 'ok', aprobado: 'ok', enviada_compras: 'ok',
  // mapeo maestro
  sugerido: 'warn',
  // compras: homologacion, evaluacion
  en_proceso: 'warn', enviada: 'ok', confirmada: 'ok', recibida_parcial: 'info', cerrada: 'info', homologado: 'ok', condicionado: 'warn', confiable: 'ok', aceptable: 'info', no_confiable: 'bad', bloqueado: 'bad',
};
const NOMBRES = {
  aprobado_entidad: 'aprobada por la entidad', enviada_compras: 'enviada a compras', retirada: 'retirada', parcial: 'parcial (faltan tramos)', calculada: 'calculada', calculando: 'calculando…',
  propuesto: 'propuesto', concertado: 'concertado', rechazado: 'rechazado', sugerido: 'sugerido, por aprobar', en_proceso: 'en proceso', recibida_parcial: 'recibida parcial', no_confiable: 'no confiable',
};
export function Estado({ e }) {
  return <span className={`chip ${ESTADOS[e] ?? ''}`}>{NOMBRES[e] ?? String(e ?? '').replace(/_/g, ' ')}</span>;
}

// Campo de formulario: etiqueta arriba, control abajo. <Campo l="Nombre" req><input .../></Campo>
export function Campo({ l, req = false, ayuda, children, className = '' }) {
  return (
    <label className={`campo ${className}`}>
      <span>{l}{req && <span className="req"> *</span>}{ayuda && <Info>{ayuda}</Info>}</span>
      {children}
    </label>
  );
}

// Tabla: columnas [{k, t, n (numerica), r (render)}], filas con id. Envuelta en scroll horizontal.
export function Tabla({ cols, filas, idKey = 'id', vacio = 'Sin datos', pie, onFila, selId, grande = false }) {
  return (
    <div className="scroll">
      <table className={`t${grande ? ' t-grande' : ''}`}>
        <thead><tr>{cols.map((c) => <th key={c.k ?? c.t} className={c.n ? 'n' : ''}>{c.t}</th>)}</tr></thead>
        <tbody>
          {(!filas || filas.length === 0) ? <tr><td colSpan={cols.length} className="vacio">{vacio}</td></tr> :
            filas.map((f, i) => (
              <tr key={f[idKey] ?? i} className={selId != null && f[idKey] === selId ? 'sel' : ''} onClick={onFila ? () => onFila(f) : undefined} style={onFila ? { cursor: 'pointer' } : undefined}>
                {cols.map((c) => <td key={c.k ?? c.t} className={c.n ? 'n' : ''}>{c.r ? c.r(f) : c.n && typeof f[c.k] === 'number' ? num(f[c.k], c.d ?? 0) : f[c.k] ?? '·'}</td>)}
              </tr>))}
        </tbody>
        {pie && <tfoot><tr>{cols.map((c) => <td key={c.k ?? c.t} className={c.n ? 'n' : ''}>{pie[c.k] ?? ''}</td>)}</tr></tfoot>}
      </table>
    </div>
  );
}

// Panel lateral deslizante (detalle de una celda, formulario largo) que no tapa toda la pantalla
export function Panel({ titulo, sub, onCerrar, children, acciones }) {
  const ref = useRef(null);
  useEffect(() => {
    const antes = document.activeElement;
    ref.current?.focus();
    const esc = (e) => { if (e.key === 'Escape') onCerrar?.(); };
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('keydown', esc); antes?.focus?.(); };
  }, [onCerrar]);
  return (
    <>
      <div className="panel-fondo" onClick={onCerrar} />
      <aside className="panel-lateral" role="dialog" aria-modal="true" aria-label={titulo} tabIndex={-1} ref={ref}>
        <header>
          <div><h2 className="m0">{titulo}</h2>{sub && <div className="small muted">{sub}</div>}</div>
          <div className="row gap6">{acciones}<button className="btn btn-s" onClick={onCerrar} aria-label="Cerrar">✕</button></div>
        </header>
        <div className="cuerpo">{children}</div>
      </aside>
    </>
  );
}

export function Cargando({ texto = 'Cargando…' }) {
  return <div className="vacio">{texto}</div>;
}
export function Falla({ msg }) {
  if (!msg) return null;
  return <div className="aviso bad">{msg}</div>;
}
export function Vacio({ children }) {
  return <div className="vacio">{children}</div>;
}

export function Modal({ titulo, onCerrar, children, ancho = false }) {
  return (
    <div className="modal-fondo" onClick={onCerrar}>
      <div className={`modal${ancho ? ' ancho' : ''}`} onClick={(e) => e.stopPropagation()}>
        <div className="row between mb12">
          <h2 className="m0">{titulo}</h2>
          <button className="btn" onClick={onCerrar} aria-label="Cerrar">✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}

// Globo informativo: una "i" pequena que al pasar el mouse, enfocar o tocar muestra una ayuda corta.
// Se posiciona con coordenadas de pantalla para que no lo corten las tablas con scroll.
export function Info({ children, ancho = 280 }) {
  const [pos, setPos] = useState(null);
  const [fijo, setFijo] = useState(false);
  const ref = useRef(null);
  const abrir = () => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    const izq = Math.max(8, Math.min(r.left + r.width / 2 - ancho / 2, window.innerWidth - ancho - 8));
    const abajo = r.bottom + 160 < window.innerHeight;
    setPos({ left: izq, top: abajo ? r.bottom + 6 : undefined, bottom: abajo ? undefined : window.innerHeight - r.top + 6 });
  };
  useEffect(() => {
    if (!fijo) return;
    const cerrar = (e) => { if (!ref.current?.contains(e.target)) { setFijo(false); setPos(null); } };
    const esc = (e) => { if (e.key === 'Escape') { setFijo(false); setPos(null); } };
    document.addEventListener('pointerdown', cerrar); document.addEventListener('keydown', esc);
    window.addEventListener('scroll', cerrar, true);
    return () => { document.removeEventListener('pointerdown', cerrar); document.removeEventListener('keydown', esc); window.removeEventListener('scroll', cerrar, true); };
  }, [fijo]);
  return (
    <span className="info-i" ref={ref}
      onMouseEnter={() => !fijo && abrir()} onMouseLeave={() => !fijo && setPos(null)}>
      <button type="button" aria-label="Mas informacion" onFocus={() => !fijo && abrir()} onBlur={() => !fijo && setPos(null)}
        onClick={(e) => { e.stopPropagation(); if (fijo) { setFijo(false); setPos(null); } else { setFijo(true); abrir(); } }}>i</button>
      {pos && <span role="tooltip" className="info-globo" style={{ ...pos, width: ancho }}>{children}</span>}
    </span>
  );
}

// Bloque plegable "Como se usa": tips cortos de la pantalla
export function Consejo({ titulo = 'Como se usa esta pantalla', children, abierto = false }) {
  return (
    <details className="consejo no-print" open={abierto}>
      <summary>💡 {titulo}</summary>
      <div className="small">{children}</div>
    </details>
  );
}
