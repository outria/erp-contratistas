'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useApp, esDemo } from '@/lib/ctx';
import { supabaseConfigurado } from '@/lib/supabase';
import { Actualizador } from '@/components/actualizador';

// Menu por modulo. m = modulo (o lista, o funcion sobre puede) que da acceso a la pantalla.
// Las pantallas marcadas pronto: true todavia no existen; se muestran apagadas para que el equipo
// vea hacia donde va la plataforma (se quitan a medida que llegan sus fases).
const MENU = [
  { g: 'Dia a dia' },
  { h: '/tablero', t: 'Tablero', m: null },
  { h: '/seguimiento-oc', t: 'Seguimiento de OC (TV)', m: 'M3', pronto: true },
  { g: 'Contrato y planeacion' },
  { h: '/contratos', t: 'Contratos y anexos', m: 'M1' },
  { h: '/programacion', t: 'Programacion de menus', m: ['M2', 'M3', 'M7'] },
  { h: '/minutas', t: 'Minutas y calendario', m: ['M2', 'M3', 'M7'] },
  { h: '/cupos', t: 'Cupos y dietas', m: ['M2', 'M3', 'M7'] },
  { h: '/explosion', t: 'Explosion de materiales', m: ['M2', 'M3'] },
  { h: '/intercambios', t: 'Intercambios y novedades', m: ['M2', 'M7'] },
  { g: 'Compras' },
  { h: '/negociacion', t: 'Negociacion por volumen', m: ['M3', 'M2'] },
  { h: '/proveedores', t: 'Proveedores y homologacion', m: ['M3', 'M13'] },
  { h: '/precios', t: 'Master de precios y ofertas', m: ['M3', 'M2'] },
  { h: '/ordenes-compra', t: 'Ordenes de compra', m: 'M3' },
  { h: '/costos', t: 'Costo por tiempo de comida', m: ['M3', 'M2'] },
  { h: '/cotizaciones', t: 'Solicitudes de cotizacion', m: 'M3' },
  { h: '/requerimientos', t: 'Requerimientos de Planeacion', m: ['M2', 'M3'] },
  { h: '/compras-locales', t: 'Compras locales (Ley 2046)', m: ['M3', 'M1'] },
  { h: '/portal', t: 'Portal de proveedores', m: 'M4' },
  { g: 'Logistica' },
  { h: '/inventario', t: 'Inventario y bodegas', m: 'M5', pronto: true },
  { h: '/traslados', t: 'Traslados y entregas a sedes', m: 'M6', pronto: true },
  { h: '/sedes', t: 'Operacion en sede', m: 'M7', pronto: true },
  { h: '/vehiculos', t: 'Vehiculos', m: 'M14', pronto: true },
  { g: 'Calidad y dinero' },
  { h: '/calidad', t: 'Calidad e interventoria', m: 'M8', pronto: true },
  { h: '/facturacion', t: 'Facturacion a la entidad', m: 'M9', pronto: true },
  { h: '/pagos', t: 'Facturas y pagos a proveedores', m: 'M10', pronto: true },
  { g: 'Maestros y personas' },
  { h: '/maestros', t: 'Productos, terceros y fichas', m: 'M13', pronto: true },
  { h: '/talento', t: 'Talento humano del contrato', m: 'M11', pronto: true },
  { h: '/empresa', t: 'Empresa y parametros', m: 'M0' },
  { h: '/usuarios', t: 'Usuarios y roles', m: 'M0' },
];

export default function AppLayout({ children }) {
  const { sesion, perfil, empresas, empresa, empresaId, setEmpresaId, puede, salir, error, rol } = useApp();
  const ruta = usePathname();
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);

  useEffect(() => { if (sesion === null) router.replace('/login'); }, [sesion, router]);
  useEffect(() => { setAbierto(false); }, [ruta]);
  // un usuario proveedor solo ve el portal
  useEffect(() => { if (rol === 'proveedor' && !ruta.startsWith('/portal') && !ruta.startsWith('/mi-cuenta')) router.replace('/portal'); }, [rol, ruta, router]);

  if (!supabaseConfigurado()) return <div className="login"><div className="card"><div className="aviso">Falta configurar Supabase en Vercel.</div></div></div>;
  if (!sesion) return <div className="login"><span className="muted">Cargando…</span></div>;
  if (perfil && empresas.length === 0) {
    return (
      <div className="login"><div className="card stack">
        <h2>Sin empresa asignada</h2>
        <p className="muted">Tu usuario ({sesion.user.email}) todavia no tiene una empresa asignada. Pidele al administrador que te de acceso.</p>
        <button className="btn" onClick={salir}>Salir</button>
      </div></div>
    );
  }

  const ve = (m) => !m || (typeof m === 'function' ? m(puede) : Array.isArray(m) ? m.some((x) => puede(x)) : puede(m));
  const enRuta = (h) => ruta === h || ruta.startsWith(`${h}/`);
  const pantalla = MENU.find((x) => x.h && enRuta(x.h));
  const bloqueada = pantalla && empresaId && !ve(pantalla.m);
  const nombre = empresa?.nombre_corto || empresa?.razon_social;
  return (
    <div className="shell">
      <button className="burger" onClick={() => setAbierto(true)}>☰ <b>Ración360</b> <span className="op70">{nombre}</span></button>
      <aside className={`side ${abierto ? 'abierto' : ''}`}>
        <div className="brand">
          <div className="brand-logo">R360</div>
          <div><b>Ración360</b><span>cadena de suministro</span></div>
        </div>
        {empresas.length > 1 ? (
          <select value={empresaId ?? ''} onChange={(e) => setEmpresaId(e.target.value)} aria-label="Empresa">
            {empresas.map((e) => <option key={e.id} value={e.id}>{esDemo(e) ? `${e.nombre_corto || e.razon_social} (práctica)` : (e.nombre_corto || e.razon_social)}</option>)}
          </select>
        ) : <div className="small p0">{nombre}</div>}
        {esDemo(empresa) && <div className="aviso-demo">Empresa de práctica: lo que registres aquí no cuenta en la operación real.</div>}
        <nav className="nav">
          {MENU.map((x, i) => x.g ? <div key={i} className="grupo">{x.g}</div> :
            ve(x.m) && (x.pronto
              ? <span key={x.h} className="pronto" title="Llega en una fase posterior">{x.t}</span>
              : <Link key={x.h} href={x.h} className={enRuta(x.h) ? 'on' : ''}>{x.t}</Link>))}
        </nav>
        <div className="side-pie">
          <span>{perfil?.nombre ?? sesion.user.email}{perfil?.es_superadmin ? ' · superadmin' : ''}</span>
          <Link href="/mi-cuenta" className="btn">Mi cuenta y clave</Link>
          <button className="btn" onClick={salir}>Salir</button>
        </div>
      </aside>
      <main className="main">
        <Actualizador />
        {error && <div className="aviso bad mb12">{error}</div>}
        {bloqueada ? <div className="aviso bad">Su rol no tiene acceso a esta pantalla.</div> : empresaId ? children : <span className="muted">Cargando empresa…</span>}
      </main>
    </div>
  );
}
