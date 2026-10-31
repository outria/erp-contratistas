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
      <span className="v">{typeof v === 'number' ? num(v, d) : v}{sufijo ? <small className="muted" style={{ fontSize: 14 }}> {sufijo}</small> : null}</span>
      <span className="l">{l}</span>
    </div>
  );
}

export function Barra({ valor, meta, etiqueta, de = 'de la meta', tope = 1.05 }) {
  const pct = meta ? Math.min(100, (valor / meta) * 100) : 0;
  const clase = !meta ? '' : valor > meta * tope ? 'bad' : valor >= meta * 0.95 ? 'ok' : '';
  return (
    <div className="stack" style={{ gap: 4 }}>
      <div className="row between small">
        <span>{etiqueta}</span>
        <span className="muted">{meta ? `${num((valor / meta) * 100)} % ${de}` : 'sin meta'}</span>
      </div>
      <div className={`barra ${clase}`}><i style={{ width: `${pct}%` }} /></div>
    </div>
  );
}

const ESTADOS = {
  borrador: '', aprobado: 'info', aprobada: 'info', programado: 'info', producido: 'ok', despachado: 'ok', entregado: 'ok', pendiente: 'warn', leyendo: 'warn', leida: 'info', creada: 'ok', descartada: 'bad', error: 'bad', anulado: 'bad', anulada: 'bad',
  planeada: '', en_proceso: 'warn', cerrada: 'ok', planeado: '', pesado: 'warn', mojado: 'warn', horneado: 'warn',
  formado: 'warn', fermentado: 'warn', empacado: 'ok', liberado: 'ok', arrastrado: 'warn', por_aprobar: 'warn', devuelto: 'bad', produce: 'ok', no_produce: 'bad', preparado_sitio: 'warn', otro_componente: '', por_revisar: 'warn',
  activo: 'ok', fuera_de_servicio: 'warn', vigente: 'ok',
};
const NOMBRES = { en_proceso: 'en proceso', por_aprobar: 'por aprobar', no_produce: 'no producimos', produce: 'producimos', preparado_sitio: 'en sitio', otro_componente: 'otro componente', por_revisar: 'por revisar', fuera_de_servicio: 'fuera de servicio', leida: 'leída, por revisar', creada: 'pedido creado', leyendo: 'leyendo con IA' };
export function Estado({ e }) {
  return <span className={`chip ${ESTADOS[e] ?? ''}`}>{NOMBRES[e] ?? e}</span>;
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
        <div className="row between" style={{ marginBottom: 12 }}>
          <h2 style={{ margin: 0 }}>{titulo}</h2>
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
