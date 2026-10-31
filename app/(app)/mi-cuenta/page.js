'use client';
import { useState } from 'react';
import { useApp } from '@/lib/ctx';
import { sb } from '@/lib/supabase';
import { Encabezado } from '@/components/ui';

// Cada usuario crea o cambia su propia clave. Nadie mas la ve ni la carga.
export default function MiCuenta() {
  const { sesion, perfil } = useApp();
  const [c1, setC1] = useState('');
  const [c2, setC2] = useState('');
  const [msg, setMsg] = useState(null);
  const [ocupado, setOcupado] = useState(false);

  async function guardar(e) {
    e.preventDefault();
    setMsg(null);
    if (c1.length < 10) return setMsg({ t: 'bad', m: 'La clave debe tener al menos 10 caracteres.' });
    if (c1 !== c2) return setMsg({ t: 'bad', m: 'Las dos claves no coinciden.' });
    setOcupado(true);
    try {
      const { error } = await sb().auth.updateUser({ password: c1 });
      if (error) throw error;
      setC1(''); setC2('');
      setMsg({ t: 'ok', m: 'Clave guardada. La proxima vez entras con tu correo y esta clave.' });
    } catch (err) {
      setMsg({ t: 'bad', m: /different from the old/i.test(err.message) ? 'La clave nueva debe ser distinta a la anterior.' : err.message });
    } finally { setOcupado(false); }
  }

  return (
    <>
      <Encabezado titulo="Mi cuenta" sub="Tus datos de ingreso. La clave solo la conoces tu." />
      {/* avisos al celular: llegan con las notificaciones de la carrera de relevos (F2) */}
      <div className="card stack" style={{ maxWidth: 460 }}>
        <div className="small">
          <div><b>Correo:</b> {sesion?.user?.email}</div>
          {perfil?.nombre && <div><b>Nombre:</b> {perfil.nombre}</div>}
          {perfil?.es_superadmin && <div><b>Perfil:</b> superadministrador</div>}
        </div>
        <form className="stack" onSubmit={guardar}>
          <h3 style={{ margin: 0 }}>Crear o cambiar mi clave</h3>
          <label className="campo">Clave nueva (minimo 10 caracteres)
            <input type="password" autoComplete="new-password" required value={c1} onChange={(e) => setC1(e.target.value)} />
          </label>
          <label className="campo">Repite la clave nueva
            <input type="password" autoComplete="new-password" required value={c2} onChange={(e) => setC2(e.target.value)} />
          </label>
          {msg && <div className={`aviso ${msg.t}`}>{msg.m}</div>}
          <button className="btn btn-p" disabled={ocupado}>{ocupado ? 'Un momento…' : 'Guardar clave'}</button>
        </form>
      </div>
    </>
  );
}
