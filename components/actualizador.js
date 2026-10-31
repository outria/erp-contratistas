'use client';
// Actualizacion automatica (v1.42): cuando se publica una version nueva, la pantalla se recarga sola
// apenas no haya un registro abierto (para no perder lo que el operario esta digitando).
// Revisa /api/version cada minuto y al volver a la pantalla.
import { useEffect, useRef, useState } from 'react';

export function Actualizador() {
  const base = useRef(null);
  const [nueva, setNueva] = useState(false);

  useEffect(() => {
    let vivo = true;
    const revisar = async () => {
      try {
        const r = await fetch('/api/version', { cache: 'no-store' });
        if (!r.ok) return;
        const { v } = await r.json();
        if (!v) return;
        if (base.current === null) { base.current = v; return; }
        if (v !== base.current && vivo) setNueva(true);
      } catch { /* sin red: se intenta en la siguiente vuelta */ }
    };
    revisar();
    const id = setInterval(revisar, 60000);
    const alVolver = () => { if (document.visibilityState === 'visible') revisar(); };
    document.addEventListener('visibilitychange', alVolver);
    return () => { vivo = false; clearInterval(id); document.removeEventListener('visibilitychange', alVolver); };
  }, []);

  useEffect(() => {
    if (!nueva) return;
    const intentar = () => { if (!document.querySelector('.modal-fondo')) window.location.reload(); };
    intentar();
    const id = setInterval(intentar, 5000);
    return () => clearInterval(id);
  }, [nueva]);

  if (!nueva) return null;
  return (
    <div className="aviso" style={{ position: 'sticky', top: 0, zIndex: 50, marginBottom: 12, display: 'flex', gap: 12, alignItems: 'center', justifyContent: 'space-between' }}>
      <span>🔄 Hay una versión nueva de la plataforma. Se aplica sola al terminar el registro abierto.</span>
      <button type="button" className="btn" onClick={() => window.location.reload()}>Actualizar ya</button>
    </div>
  );
}
