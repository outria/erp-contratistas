'use client';
// Contexto de la aplicacion: sesion, perfil, empresas visibles, empresa activa, permisos y sedes.
// Heredado de A2 PAN ERP (F0) y simplificado: aqui no hay turnos de produccion.
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { sb, q, supabaseConfigurado } from './supabase';

const Ctx = createContext(null);
export const useApp = () => useContext(Ctx);

const leer = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const guardar = (k, v) => { try { localStorage.setItem(k, v); } catch {} };
const leerSes = (k) => { try { return sessionStorage.getItem(k); } catch { return null; } };
const guardarSes = (k, v) => { try { if (v == null) sessionStorage.removeItem(k); else sessionStorage.setItem(k, v); } catch {} };
// empresas de practica: NIT 90000000x o "Demo" en la razon social
export const esDemo = (e) => !!e && (/^90000000\d$/.test(String(e.nit ?? '')) || /demo/i.test(e.razon_social ?? ''));

export function AppProvider({ children }) {
  const [sesion, setSesion] = useState(undefined); // undefined = cargando, null = sin sesion
  const [perfil, setPerfil] = useState(null);
  const [empresas, setEmpresas] = useState([]);
  const [empresaId, setEmpresaIdState] = useState(null);
  const [permisos, setPermisos] = useState(new Set());
  const [sedes, setSedes] = useState([]);
  const [rol, setRol] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!supabaseConfigurado()) { setSesion(null); return; }
    sb().auth.getSession().then(({ data }) => setSesion(data.session ?? null));
    const { data: sub } = sb().auth.onAuthStateChange((ev, s) => {
      if (ev === 'PASSWORD_RECOVERY') { try { sessionStorage.setItem('sc_crear_clave', '1'); } catch {} }
      setSesion(s ?? null);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const uid = sesion?.user?.id ?? null;
  useEffect(() => {
    setRol(null); setPermisos(new Set()); setSedes([]); setEmpresaIdState(null);
    if (!sesion) { setPerfil(null); setEmpresas([]); return; }
    (async () => {
      try {
        const p = await q(sb().from('perfiles').select('*').eq('id', sesion.user.id).maybeSingle());
        setPerfil(p);
        const lst = await q(sb().from('empresas').select('id, razon_social, nombre_corto, nit, color_primario, color_acento').eq('estado', 'activa').order('razon_social'));
        const es = [...lst.filter((e) => !esDemo(e)), ...lst.filter(esDemo)];
        setEmpresas(es);
        const uidK = sesion.user.id;
        const real = es.find((e) => e.id === leer(`sc_empresa_${uidK}`) && !esDemo(e)) ?? es.find((e) => !esDemo(e)) ?? es[0];
        const demoSes = es.find((e) => e.id === leerSes(`sc_empresa_demo_${uidK}`) && esDemo(e));
        setEmpresaIdState(demoSes?.id ?? real?.id ?? null);
      } catch (e) { setError(e.message); }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid]);

  useEffect(() => {
    if (!empresaId || !uid) return;
    (async () => {
      try {
        const [ps, ss, r] = await Promise.all([
          q(sb().rpc('mis_permisos', { p_empresa: empresaId })),
          q(sb().from('sedes').select('id, nombre, tipo').eq('empresa_id', empresaId).eq('estado', 'activa').order('nombre')),
          sb().rpc('mi_rol', { p_empresa: empresaId }).then((x) => x.data ?? null, () => null),
        ]);
        setRol(r);
        setPermisos(new Set(ps.map((x) => `${x.modulo}:${x.accion}`)));
        setSedes(ss);
      } catch (e) { setError(e.message); }
    })();
  }, [empresaId, uid]);

  const setEmpresaId = useCallback((id) => {
    const e = empresas.find((x) => x.id === id);
    if (uid) {
      if (esDemo(e)) guardarSes(`sc_empresa_demo_${uid}`, id);
      else { guardarSes(`sc_empresa_demo_${uid}`, null); guardar(`sc_empresa_${uid}`, id); }
    }
    setEmpresaIdState(id);
  }, [empresas, uid]);
  const puede = useCallback((modulo, accion = 'ver') => permisos.has(`${modulo}:${accion}`), [permisos]);
  const empresa = useMemo(() => empresas.find((e) => e.id === empresaId) ?? null, [empresas, empresaId]);
  // marca de la empresa: sus colores alimentan los tokens de diseno
  useEffect(() => {
    const r = document.documentElement.style;
    const hex = (c) => /^#[0-9a-f]{6}$/i.test(c ?? '') ? c : null;
    const p = hex(empresa?.color_primario), ac = hex(empresa?.color_acento);
    const lum = (c) => { const n = parseInt(c.slice(1), 16); const [R, G, B] = [n >> 16 & 255, n >> 8 & 255, n & 255].map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }); return 0.2126 * R + 0.7152 * G + 0.0722 * B; };
    if (p) {
      r.setProperty('--primario', p); r.setProperty('--primario-2', p + 'e6');
      const claro = lum(p) > 0.4;   // primario claro: texto oscuro encima
      r.setProperty('--sobre-primario', claro ? '#1c2433' : '#ffffff'); r.setProperty('--primario-texto', claro ? '#2c3a5c' : '#c9d2e3');
    } else { ['--primario', '--primario-2', '--sobre-primario', '--primario-texto'].forEach((k) => r.removeProperty(k)); }
    if (ac) { r.setProperty('--acento', ac); r.setProperty('--acento-2', ac + 'd9'); r.setProperty('--acento-suave', ac + '1f'); } else { r.removeProperty('--acento'); r.removeProperty('--acento-2'); r.removeProperty('--acento-suave'); }
  }, [empresa]);
  const salir = useCallback(async () => {
    try { await sb().auth.signOut(); } finally { window.location.replace('/login'); }
  }, []);

  const valor = { sesion, perfil, empresas, empresa, empresaId, setEmpresaId, sedes, rol, puede, salir, error, setError };
  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

// Carga datos con estado de carga y error; recarga cuando cambian las dependencias
export function useCarga(fn, deps) {
  const [datos, setDatos] = useState(null);
  const [cargando, setCargando] = useState(true);
  const [err, setErr] = useState(null);
  const [n, setN] = useState(0);
  useEffect(() => {
    let vivo = true;
    setCargando(true);
    fn().then((d) => { if (vivo) { setDatos(d); setErr(null); } })
        .catch((e) => { if (vivo) setErr(e.message); })
        .finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, n]);
  return { datos, cargando, err, recargar: () => setN((x) => x + 1) };
}
