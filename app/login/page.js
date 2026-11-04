'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { sb, supabaseConfigurado, leerAvisoEnlace, limpiarAvisoEnlace } from '@/lib/supabase';
import { useApp } from '@/lib/ctx';

export default function Login() {
  const { sesion } = useApp();
  const router = useRouter();
  const [correo, setCorreo] = useState('');
  const [clave, setClave] = useState('');
  const [modo, setModo] = useState(null); // entrar | olvido | nueva (null mientras se revisa el enlace)
  const [msg, setMsg] = useState(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    // enlace de invitacion o recuperacion: Supabase abre la sesion y pedimos la clave nueva
    const av = leerAvisoEnlace();
    if (av.error) {
      limpiarAvisoEnlace();
      setMsg({ t: 'bad', m: av.error === 'otp_expired'
        ? 'El enlace del correo ya vencio o ya se habia usado (sirve una sola vez y vence a las 24 horas). Pida una invitacion nueva al administrador o use "Olvide mi clave".'
        : 'El enlace del correo no es valido. Pida una invitacion nueva al administrador o use "Olvide mi clave".' });
      setModo('entrar');
    } else setModo(av.crear ? 'nueva' : 'entrar');
  }, []);
  useEffect(() => {
    // llego por enlace pero no se abrio sesion: el enlace no sirvio
    if (modo === 'nueva' && sesion === null) {
      const t = setTimeout(() => {
        limpiarAvisoEnlace();
        setMsg({ t: 'bad', m: 'No se pudo abrir la sesion con el enlace (vencido o ya usado). Pida uno nuevo al administrador o use "Olvide mi clave".' });
        setModo('entrar');
      }, 2500);
      return () => clearTimeout(t);
    }
  }, [modo, sesion]);
  useEffect(() => {
    if (sesion && modo === 'entrar') router.replace('/tablero');
  }, [sesion, modo, router]);

  if (!supabaseConfigurado()) {
    return <div className="login"><div className="card"><div className="aviso">Falta configurar la conexion a la base de datos (variables de Supabase en Vercel).</div></div></div>;
  }

  async function enviar(e) {
    e.preventDefault();
    setOcupado(true); setMsg(null);
    try {
      if (modo === 'entrar') {
        const { error } = await sb().auth.signInWithPassword({ email: correo.trim(), password: clave });
        if (error) throw error;
      } else if (modo === 'olvido') {
        const { error } = await sb().auth.resetPasswordForEmail(correo.trim(), { redirectTo: `${window.location.origin}/login` });
        if (error) throw error;
        setMsg({ t: 'ok', m: 'Te enviamos un correo con el enlace para crear una clave nueva.' });
      } else {
        if (clave.length < 10) throw new Error('La clave debe tener al menos 10 caracteres.');
        const { error } = await sb().auth.updateUser({ password: clave });
        if (error) throw error;
        limpiarAvisoEnlace();
        setMsg({ t: 'ok', m: 'Clave guardada. Entrando…' });
        setTimeout(() => router.replace('/tablero'), 800);
      }
    } catch (err) {
      setMsg({ t: 'bad', m: err.message === 'Invalid login credentials' ? 'Correo o clave incorrectos.' : err.message });
    } finally { setOcupado(false); }
  }

  if (modo === null) return <div className="login"><span className="muted">Cargando…</span></div>;

  return (
    <div className="login">
      <form className="card stack" onSubmit={enviar}>
        <div className="brand p0">
          <div className="brand-logo">SE</div>
          <div><b>Supply ERP</b><span className="muted">Contratistas de alimentación del Estado</span></div>
        </div>
        <h2 className="m0">{modo === 'entrar' ? 'Ingresar' : modo === 'olvido' ? 'Recuperar clave' : 'Crear clave nueva'}</h2>
        {modo !== 'nueva' && (
          <label className="campo">Correo
            <input type="email" autoComplete="username" required value={correo} onChange={(e) => setCorreo(e.target.value)} />
          </label>
        )}
        {modo !== 'olvido' && (
          <label className="campo">{modo === 'nueva' ? 'Clave nueva (minimo 10 caracteres)' : 'Clave'}
            <input type="password" autoComplete={modo === 'nueva' ? 'new-password' : 'current-password'} required value={clave} onChange={(e) => setClave(e.target.value)} />
          </label>
        )}
        {msg && <div className={`aviso ${msg.t}`}>{msg.m}</div>}
        <button className="btn btn-p" disabled={ocupado}>{ocupado ? 'Un momento…' : modo === 'entrar' ? 'Entrar' : modo === 'olvido' ? 'Enviar enlace' : 'Guardar clave'}</button>
        {modo === 'entrar' && <button type="button" className="btn" onClick={() => setModo('olvido')}>Olvide mi clave</button>}
        {modo === 'olvido' && <button type="button" className="btn" onClick={() => setModo('entrar')}>Volver</button>}
        <p className="muted small m0">Los usuarios se crean por invitacion del administrador de cada empresa.</p>
      </form>
    </div>
  );
}
