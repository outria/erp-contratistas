'use client';
import { createClient } from '@supabase/supabase-js';

let cliente = null;

// Enlaces de invitacion o recuperacion: se leen ANTES de crear el cliente, porque
// Supabase limpia el hash de la URL al procesarlo. Se guardan para la pantalla de login.
if (typeof window !== 'undefined') {
  try {
    const h = window.location.hash || '';
    if (/type=(recovery|invite)/.test(h)) sessionStorage.setItem('sc_crear_clave', '1');
    if (/error_code=|[#&]error=/.test(h)) {
      const p = new URLSearchParams(h.replace(/^#/, ''));
      sessionStorage.setItem('sc_auth_error', p.get('error_code') || p.get('error') || 'error');
    }
  } catch {}
}

export function leerAvisoEnlace() {
  try { return { crear: sessionStorage.getItem('sc_crear_clave') === '1', error: sessionStorage.getItem('sc_auth_error') }; }
  catch { return { crear: false, error: null }; }
}
export function limpiarAvisoEnlace() {
  try { sessionStorage.removeItem('sc_crear_clave'); sessionStorage.removeItem('sc_auth_error'); } catch {}
}

export function supabaseConfigurado() {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}

export function sb() {
  if (!cliente) {
    cliente = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    });
  }
  return cliente;
}

// Lanza el error de Supabase con un mensaje legible
const TRADUCE = [
  [/row-level security/i, 'Su rol no puede hacer esto (o no para otras sedes). Pidale a planeacion o a la direccion de operaciones.'],
  [/duplicate key value/i, 'Ya existe un registro igual.'],
  [/violates foreign key/i, 'El registro esta en uso o hace referencia a algo que no existe.'],
  [/statement timeout|canceling statement/i, 'La consulta tardo demasiado. Filtre menos sedes o menos semanas e intente de nuevo.'],
  [/JWT expired|invalid claim/i, 'La sesion vencio. Vuelva a entrar.'],
];
export async function q(promesa) {
  const { data, error } = await promesa;
  if (error) {
    const t = TRADUCE.find(([re]) => re.test(error.message || ''));
    throw new Error(t ? t[1] : error.message);
  }
  return data;
}
