'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useApp } from '@/lib/ctx';
import { supabaseConfigurado, leerAvisoEnlace } from '@/lib/supabase';

export default function Inicio() {
  const { sesion } = useApp();
  const router = useRouter();
  useEffect(() => {
    // enlaces de invitacion o recuperacion que caen en la raiz: mandarlos a crear la clave
    const av = leerAvisoEnlace();
    if (av.crear || av.error) { router.replace('/login'); return; }
    if (sesion === undefined) return;
    router.replace(sesion ? '/tablero' : '/login');
  }, [sesion, router]);
  if (!supabaseConfigurado()) {
    return (
      <div className="login">
        <div className="card stack">
          <h1>Supply ERP</h1>
          <div className="aviso">Falta configurar la conexion a la base de datos. En Vercel, Settings &gt; Environment Variables, cargar NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_ANON_KEY y volver a desplegar.</div>
        </div>
      </div>
    );
  }
  return <div className="login"><span className="muted">Cargando…</span></div>;
}
