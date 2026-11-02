'use client';
// v1.61: Usuarios y Roles. Pestaña Usuarios (invitar, reenviar acceso, editar nombre y rol, activar)
// y pestaña Roles al estilo Payana: cada rol muestra sus funciones por modulo y se pueden crear roles propios.
import { useMemo, useState } from 'react';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Vacio, Modal } from '@/components/ui';

const ACCIONES = ['ver', 'crear', 'editar', 'aprobar', 'anular'];
const NOMBRE_ACCION = { ver: 'Ver', crear: 'Crear', editar: 'Editar', aprobar: 'Aprobar', anular: 'Anular' };
const SENSIBLES = ['M0', 'M9', 'M10', 'M11', 'M15'];

// Funciones clave de cada modulo, en palabras de la operacion. listo: false = el modulo todavia no esta construido.
const FUNCIONES = {
  M0: { t: 'Usuarios, seguridad y empresa', listo: true, ver: 'Ver usuarios y roles', crear: 'Invitar usuarios y darles acceso', editar: 'Cambiar roles, crear roles propios, activar o desactivar usuarios, buzones e integraciones', aprobar: 'Parámetros generales de la empresa', anular: 'Quitar accesos' },
  M1: { t: 'Contratos y anexos', listo: true, ver: 'Ver contratos, cabezote, anexos y agotamiento presupuestal', crear: 'Crear contratos y cargar anexos', editar: 'Cambiar datos del contrato, adiciones y prórrogas', aprobar: 'Aprobar adiciones y cierres', anular: 'Anular contratos' },
  M2: { t: 'Planeación y explosión de materiales', listo: false, ver: 'Ver minutas, calendario, cupos, intercambios y correr proyecciones', crear: 'Cargar minutas, cupos y dietas; proponer intercambios; crear requerimientos', editar: 'Ajustar menús por sede, menús especiales y novedades de cobertura', aprobar: 'Concertar y aprobar intercambios, ajustar gramajes y aprobar el requerimiento a compras', anular: 'Anular explosiones e intercambios' },
  M3: { t: 'Compras y aprovisionamiento', listo: false, ver: 'Ver proveedores, máster de precios, OC y seguimiento', crear: 'Crear solicitudes de oferta, OC y novedades', editar: 'Negociar (aceptar, rechazar, contraofertar), homologar proveedores', aprobar: 'Aprobar órdenes de compra', anular: 'Anular órdenes de compra' },
  M4: { t: 'Portal de proveedores', listo: false, ver: 'Ver el portal (lado empresa)', crear: 'Invitar proveedores al portal', editar: 'Gestionar accesos de proveedores', aprobar: 'Aprobar homologación', anular: 'Bloquear proveedores' },
  M5: { t: 'Inventario y bodegas (WMS)', listo: false, ver: 'Ver existencias, lotes y movimientos', crear: 'Registrar recepciones, entradas y salidas', editar: 'Ajustes de inventario con causa', aprobar: 'Aprobar ajustes y conteos', anular: 'Anular movimientos' },
  M6: { t: 'Distribución y entregas a sedes', listo: false, ver: 'Ver traslados, rutas y actas', crear: 'Crear órdenes de traslado y registrar entregas', editar: 'Registrar novedades y evidencias', aprobar: 'Cerrar traslados', anular: 'Anular traslados' },
  M7: { t: 'Operación en unidad de servicio', listo: false, ver: 'Ver consumo diario y cuadros de raciones', crear: 'Registrar recibido, consumo y cuadro de raciones', editar: 'Corregir registros del día', aprobar: 'Cerrar el día con firmas', anular: 'Anular registros' },
  M8: { t: 'Calidad e interventoría', listo: false, ver: 'Ver evidencias, hallazgos y planes de mejora', crear: 'Cargar evidencias y hallazgos', editar: 'Gestionar subsanaciones', aprobar: 'Cerrar hallazgos', anular: 'Anular registros' },
  M9: { t: 'Facturación a la entidad', listo: false, ver: 'Ver raciones certificadas y cuentas de cobro', crear: 'Armar el cierre mensual y la cuenta de cobro', editar: 'Ajustar soportes', aprobar: 'Radicar ante la entidad', anular: 'Anular cuentas de cobro' },
  M10: { t: 'Contabilidad y pagos a proveedores', listo: false, ver: 'Ver facturas, causaciones y pagos', crear: 'Radicar facturas de proveedores', editar: 'Aceptar o rechazar facturas, causar', aprobar: 'Aprobar y programar pagos', anular: 'Anular causaciones' },
  M11: { t: 'Talento humano del contrato', listo: false, ver: 'Ver personal por sede y vencimientos', crear: 'Registrar personal y documentos', editar: 'Cambiar cargos y sedes', aprobar: 'Aprobar planta mínima', anular: 'Retirar personal' },
  M12: { t: 'IA y automatizaciones', listo: false, ver: 'Ver lo que leyó el buzón y el cotejo', crear: 'Correr lecturas y cotejos', editar: 'Configurar reglas', aprobar: 'Aprobar acciones sugeridas', anular: 'Apagar automatizaciones' },
  M13: { t: 'Maestros (productos, terceros, fichas técnicas)', listo: false, ver: 'Ver productos, terceros y fichas', crear: 'Crear productos, terceros y fichas técnicas', editar: 'Cambiar maestros', aprobar: 'Aprobar fichas técnicas', anular: 'Inactivar maestros' },
  M14: { t: 'Vehículos y flota', listo: false, ver: 'Ver vehículos y vencimientos', crear: 'Registrar kilometraje y novedades', editar: 'Crear vehículos y controles', aprobar: 'Aprobar mantenimientos', anular: 'Borrar registros' },
  M15: { t: 'Tableros e indicadores', listo: false, ver: 'Ver tableros gerenciales (costo por ración, OTIF, agotamiento, Ley 2046)', crear: 'Crear tableros', editar: 'Cambiar tableros', aprobar: 'Publicar tableros', anular: 'Quitar tableros' },
};
const ORDEN_MOD = ['M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M13', 'M14', 'M11', 'M9', 'M10', 'M15', 'M12', 'M0'];

const clave = (p) => p.modulo + ':' + p.accion;

export default function Usuarios() {
  const { puede } = useApp();
  const [tab, setTab] = useState('usuarios');
  return (
    <>
      <Encabezado titulo="Usuarios y roles" sub="Quién entra a esta empresa, con qué rol, y qué puede hacer cada rol. Las claves nunca pasan por aquí: cada persona crea la suya desde su correo." />
      <div className="tabs">
        <button className={tab === 'usuarios' ? 'on' : ''} onClick={() => setTab('usuarios')}>Usuarios</button>
        <button className={tab === 'roles' ? 'on' : ''} onClick={() => setTab('roles')}>Roles y funciones</button>
      </div>
      {tab === 'usuarios' ? <PestanaUsuarios /> : <PestanaRoles puedeEditar={puede('M0', 'editar')} />}
    </>
  );
}

// roles que este usuario puede asignar o dar: no se reparte una funcion sensible que uno no tiene
function useRolesPermitidos(roles) {
  const { puede, perfil } = useApp();
  return useMemo(() => (roles || []).filter((r) => perfil?.es_superadmin
    || !(r.permisos || []).some((p) => SENSIBLES.includes(p.modulo) && !puede(p.modulo, p.accion))), [roles, perfil, puede]);
}

function PestanaUsuarios() {
  const { empresaId, puede } = useApp();
  const [f, setF] = useState({ correo: '', nombre: '', rol: '' });
  const [err, setErr] = useState(null);
  const [ok, setOk] = useState(null);
  const [ocupado, setOcupado] = useState(null);
  const [editar, setEditar] = useState(null);
  const d = useCarga(async () => {
    const [us, roles] = await Promise.all([
      q(sb().rpc('usuarios_empresa', { p_empresa: empresaId })),
      q(sb().rpc('roles_empresa', { p_empresa: empresaId })),
    ]);
    return { us, roles };
  }, [empresaId]);
  const permitidos = useRolesPermitidos(d.datos?.roles);

  async function funcion(cuerpo) {
    const { data, error } = await sb().functions.invoke('usuarios-admin', { body: { empresa: empresaId, ...cuerpo } });
    if (error) throw new Error(error.message);
    if (data?.error) throw new Error(data.error);
    return data;
  }
  async function invitar() {
    setErr(null); setOk(null);
    const correo = f.correo.trim().toLowerCase();
    if (!correo || !f.rol) { setErr('Escriba el correo y escoja el rol.'); return; }
    setOcupado('invitar');
    try {
      let msg = '';
      const yaExiste = d.datos.us.some((u) => u.correo.toLowerCase() === correo);
      if (!yaExiste) {
        try { msg = (await funcion({ accion: 'invitar', correo, nombre: f.nombre })).mensaje; }
        catch (e) { if (!/ya tiene cuenta/i.test(e.message)) throw e; msg = 'El correo ya tenía cuenta.'; }
      }
      await q(sb().rpc('asignar_usuario', { p_empresa: empresaId, p_correo: correo, p_rol_codigo: f.rol, p_nombre: f.nombre || null }));
      setOk((msg ? msg + ' ' : '') + 'Quedó con acceso a esta empresa.');
      setF({ correo: '', nombre: '', rol: '' });
      d.recargar();
    } catch (e) { setErr(e.message); } finally { setOcupado(null); }
  }
  async function reenviar(u) {
    setErr(null); setOk(null); setOcupado(u.membresia_id);
    try { setOk((await funcion({ accion: 'reenviar', correo: u.correo })).mensaje); }
    catch (e) { setErr(e.message); } finally { setOcupado(null); }
  }
  async function activar(u, activo) {
    setErr(null); setOk(null);
    try { await q(sb().from('membresias').update({ activo }).eq('id', u.membresia_id)); d.recargar(); } catch (e) { setErr(e.message); }
  }

  if (d.err && !d.datos) return <Falla msg={d.err} />;
  if (d.cargando || !d.datos) return <Cargando />;
  const fecha = (x) => (x ? new Date(x).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' }) : null);
  return (
    <div className="stack">
      <Falla msg={err} />
      {ok && <div className="aviso ok">{ok}</div>}
      {puede('M0', 'crear') && (
        <div className="card stack">
          <h2 style={{ margin: 0 }}>Invitar o dar acceso</h2>
          <p className="muted small" style={{ margin: 0 }}>Si el correo es nuevo, le llega la invitación para crear su clave. Si ya tiene cuenta (por ejemplo, en otra empresa), solo se le da acceso a esta.</p>
          <div className="grid g4" style={{ alignItems: 'end' }}>
            <label className="campo">Correo<input type="email" value={f.correo} onChange={(e) => setF({ ...f, correo: e.target.value })} placeholder="persona@correo.com" /></label>
            <label className="campo">Nombre<input value={f.nombre} onChange={(e) => setF({ ...f, nombre: e.target.value })} placeholder="Nombre y apellido" /></label>
            <label className="campo">Rol
              <select value={f.rol} onChange={(e) => setF({ ...f, rol: e.target.value })}>
                <option value="">Escoja el rol…</option>
                {permitidos.map((r) => <option key={r.id} value={r.codigo}>{r.nombre}</option>)}
              </select>
            </label>
            <button className="btn btn-p" onClick={invitar} disabled={!!ocupado}>{ocupado === 'invitar' ? 'Enviando…' : 'Invitar y dar acceso'}</button>
          </div>
        </div>
      )}
      <div className="card scroll">
        {d.datos.us.length === 0 ? <Vacio>Todavía no hay usuarios en esta empresa.</Vacio> : (
          <table className="t">
            <thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th>Acceso</th><th>Estado</th><th /></tr></thead>
            <tbody>{d.datos.us.map((u) => (
              <tr key={u.membresia_id} style={{ opacity: u.activo ? 1 : 0.5 }}>
                <td><b>{u.nombre || '·'}</b></td>
                <td className="small">{u.correo}</td>
                <td>{u.rol_nombre}</td>
                <td className="small">{!u.confirmado ? <span className="chip warn">No ha creado su clave</span>
                  : u.ultimo_ingreso ? 'Último ingreso ' + fecha(u.ultimo_ingreso) : <span className="chip warn">Nunca ha entrado</span>}</td>
                <td>{u.activo ? <span className="chip ok">Activo</span> : <span className="chip">Inactivo</span>}</td>
                <td>
                  <div className="row" style={{ gap: 6, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
                    {puede('M0', 'crear') && u.activo && <button className="btn" style={{ padding: '5px 10px' }} disabled={!!ocupado} onClick={() => reenviar(u)}
                      title="Le llega un correo para crear o cambiar su clave">{ocupado === u.membresia_id ? 'Enviando…' : '✉ Reenviar acceso'}</button>}
                    {puede('M0', 'editar') && <button className="btn" style={{ padding: '5px 10px' }} onClick={() => setEditar(u)}>Editar</button>}
                    {puede('M0', 'editar') && <button className="btn" style={{ padding: '5px 10px' }} onClick={() => activar(u, !u.activo)}>{u.activo ? 'Desactivar' : 'Activar'}</button>}
                  </div>
                </td>
              </tr>
            ))}</tbody>
          </table>
        )}
      </div>
      <p className="muted small">El correo incluido de Supabase deja enviar pocos correos por hora. Si sale el aviso de límite, intente una hora después.</p>
      {editar && <EditarUsuario u={editar} roles={permitidos} onCerrar={() => setEditar(null)} onListo={(m) => { setEditar(null); setOk(m); d.recargar(); }} />}
    </div>
  );
}

function EditarUsuario({ u, roles, onCerrar, onListo }) {
  const { empresaId } = useApp();
  const [nombre, setNombre] = useState(u.nombre || '');
  const [rol, setRol] = useState(u.rol_codigo);
  const [err, setErr] = useState(null);
  const [guardando, setGuardando] = useState(false);
  const opciones = roles.some((r) => r.codigo === u.rol_codigo) ? roles : [{ id: 'actual', codigo: u.rol_codigo, nombre: u.rol_nombre }, ...roles];
  async function guardar() {
    setErr(null); setGuardando(true);
    try {
      if (nombre.trim() && nombre.trim() !== (u.nombre || '')) await q(sb().rpc('editar_nombre_usuario', { p_empresa: empresaId, p_usuario: u.usuario_id, p_nombre: nombre.trim() }));
      if (rol !== u.rol_codigo) await q(sb().rpc('asignar_usuario', { p_empresa: empresaId, p_correo: u.correo, p_rol_codigo: rol, p_nombre: null }));
      onListo('Usuario actualizado: ' + (nombre.trim() || u.correo) + '.');
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  }
  return (
    <Modal titulo="Editar usuario" onCerrar={onCerrar}>
      <div className="stack">
        <div className="small muted">{u.correo}</div>
        <label className="campo">Nombre<input value={nombre} onChange={(e) => setNombre(e.target.value)} /></label>
        <label className="campo">Rol
          <select value={rol} onChange={(e) => setRol(e.target.value)}>{opciones.map((r) => <option key={r.id} value={r.codigo}>{r.nombre}</option>)}</select>
        </label>
        <Falla msg={err} />
        <div className="row" style={{ gap: 8, justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onCerrar}>Cancelar</button>
          <button className="btn btn-p" onClick={guardar} disabled={guardando}>{guardando ? 'Guardando…' : 'Guardar'}</button>
        </div>
      </div>
    </Modal>
  );
}

// ------------------------------------------------------------------ Roles
function PestanaRoles({ puedeEditar }) {
  const { empresaId, perfil } = useApp();
  const [abierto, setAbierto] = useState(null);
  const [editor, setEditor] = useState(null);
  const [err, setErr] = useState(null);
  const [ok, setOk] = useState(null);
  const d = useCarga(() => q(sb().rpc('roles_empresa', { p_empresa: empresaId })), [empresaId]);
  if (d.err && !d.datos) return <Falla msg={d.err} />;
  if (d.cargando || !d.datos) return <Cargando />;
  const roles = d.datos;
  async function anular(r) {
    setErr(null); setOk(null);
    try { await q(sb().rpc('anular_rol', { p_rol: r.id })); setOk('Rol anulado: ' + r.nombre + '.'); d.recargar(); } catch (e) { setErr(e.message); }
  }
  return (
    <div className="stack">
      <div className="row between" style={{ flexWrap: 'wrap', gap: 8 }}>
        <span className="small muted">Toque un rol para ver sus funciones. Los roles de la plataforma solo los cambia el superadministrador; puede duplicarlos y ajustar la copia.</span>
        {puedeEditar && <button className="btn btn-p" onClick={() => setEditor({ nuevo: true, nombre: '', descripcion: '', permisos: [] })}>＋ Crear rol</button>}
      </div>
      <Falla msg={err} />
      {ok && <div className="aviso ok">{ok}</div>}
      {roles.map((r) => {
        const abre = abierto === r.id;
        const puedeCambiar = puedeEditar && (!r.sistema || perfil?.es_superadmin);
        return (
          <div key={r.id} className="card" style={{ padding: 0, borderColor: abre ? 'var(--naranja)' : undefined }}>
            <button onClick={() => setAbierto(abre ? null : r.id)} style={{ all: 'unset', cursor: 'pointer', display: 'block', width: '100%', padding: '14px 16px', boxSizing: 'border-box' }}>
              <div className="row between" style={{ gap: 8, flexWrap: 'wrap' }}>
                <div>
                  <b>{r.nombre}</b> {r.sistema ? <span className="chip">Plataforma</span> : <span className="chip info">Propio</span>}
                  <div className="small muted">{r.descripcion || resumenRol(r.permisos)}</div>
                </div>
                <span className="small muted">{r.usuarios} {r.usuarios === 1 ? 'usuario' : 'usuarios'} · {abre ? '▲ Ocultar funciones' : '▼ Ver funciones'}</span>
              </div>
            </button>
            {abre && (
              <div style={{ padding: '0 16px 14px' }}>
                <FuncionesRol permisos={r.permisos} />
                {puedeEditar && (
                  <div className="row" style={{ gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
                    {puedeCambiar && <button className="btn" onClick={() => setEditor({ id: r.id, nombre: r.nombre, descripcion: r.descripcion || '', permisos: r.permisos })}>Editar</button>}
                    <button className="btn" onClick={() => setEditor({ nuevo: true, nombre: r.nombre + ' (copia)', descripcion: r.descripcion || '', permisos: r.permisos })}>Duplicar</button>
                    {puedeCambiar && r.usuarios === 0 && <button className="btn" onClick={() => anular(r)}>Anular</button>}
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
      {editor && <EditorRol inicial={editor} onCerrar={() => setEditor(null)} onListo={(m) => { setEditor(null); setOk(m); d.recargar(); }} />}
    </div>
  );
}

function resumenRol(permisos) {
  const mods = [...new Set((permisos || []).map((p) => p.modulo))].sort((a, b) => ORDEN_MOD.indexOf(a) - ORDEN_MOD.indexOf(b));
  return mods.slice(0, 5).map((m) => FUNCIONES[m]?.t || m).join(', ') + (mods.length > 5 ? ' y ' + (mods.length - 5) + ' más' : '');
}

function FuncionesRol({ permisos }) {
  const tiene = new Set((permisos || []).map(clave));
  const mods = ORDEN_MOD.filter((m) => ACCIONES.some((a) => tiene.has(m + ':' + a)));
  if (!mods.length) return <div className="small muted">Este rol no tiene funciones.</div>;
  return (
    <div className="grid g2" style={{ gap: 12 }}>
      {mods.map((m) => (
        <div key={m}>
          <b className="small">{FUNCIONES[m]?.t || m}{SENSIBLES.includes(m) ? ' 🔒' : ''}{FUNCIONES[m] && !FUNCIONES[m].listo ? <span className="muted"> · próximamente</span> : null}</b>
          <ul className="small" style={{ margin: '4px 0 0', paddingLeft: 18 }}>
            {ACCIONES.filter((a) => tiene.has(m + ':' + a)).map((a) => <li key={a}>{FUNCIONES[m]?.[a] || NOMBRE_ACCION[a]}</li>)}
          </ul>
        </div>
      ))}
    </div>
  );
}

function EditorRol({ inicial, onCerrar, onListo }) {
  const { empresaId, puede, perfil } = useApp();
  const [nombre, setNombre] = useState(inicial.nombre);
  const [descripcion, setDescripcion] = useState(inicial.descripcion);
  const [sel, setSel] = useState(() => new Set((inicial.permisos || []).map(clave)));
  const [err, setErr] = useState(null);
  const [guardando, setGuardando] = useState(false);
  const bloqueada = (m, a) => !perfil?.es_superadmin && SENSIBLES.includes(m) && !puede(m, a);
  function cambiar(m, a) {
    setSel((s) => {
      const n = new Set(s);
      const k = m + ':' + a;
      if (n.has(k)) {
        n.delete(k);
        if (a === 'ver') ACCIONES.forEach((x) => n.delete(m + ':' + x)); // sin ver no hay lo demas
      } else {
        n.add(k);
        if (a !== 'ver' && !bloqueada(m, 'ver')) n.add(m + ':ver'); // lo implicito: quien crea o aprueba tambien ve
      }
      return n;
    });
  }
  async function guardar() {
    setErr(null);
    if (!nombre.trim()) { setErr('Escriba el nombre del rol.'); return; }
    if (!sel.size) { setErr('Escoja al menos una función.'); return; }
    setGuardando(true);
    try {
      const permisos = [...sel].map((k) => { const [modulo, accion] = k.split(':'); return { modulo, accion }; });
      await q(sb().rpc('guardar_rol', { p_empresa: empresaId, p_rol: inicial.nuevo ? null : inicial.id, p_nombre: nombre.trim(), p_descripcion: descripcion.trim() || null, p_permisos: permisos }));
      onListo((inicial.nuevo ? 'Rol creado: ' : 'Rol actualizado: ') + nombre.trim() + '.');
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  }
  return (
    <Modal titulo={inicial.nuevo ? 'Crear rol' : 'Editar rol'} onCerrar={onCerrar} ancho>
      <div className="stack" style={{ gap: 10 }}>
        <div className="grid g2">
          <label className="campo">Nombre del rol<input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Ej.: Auxiliar de despachos" /></label>
          <label className="campo">Descripción (opcional)<input value={descripcion} onChange={(e) => setDescripcion(e.target.value)} placeholder="Para qué cargo es" /></label>
        </div>
        <div className="small muted">Marque lo que puede hacer en cada módulo. Al marcar crear, editar, aprobar o anular se marca también ver. 🔒 = funciones de dinero o de usuarios: solo las puede dar quien las tiene.</div>
        <div style={{ overflowX: 'auto', maxHeight: '55vh' }}>
          <table className="t">
            <thead><tr><th>Módulo</th>{ACCIONES.map((a) => <th key={a} className="n">{NOMBRE_ACCION[a]}</th>)}</tr></thead>
            <tbody>{ORDEN_MOD.map((m) => (
              <tr key={m}>
                <td className="small"><b>{FUNCIONES[m]?.t || m}</b>{SENSIBLES.includes(m) ? ' 🔒' : ''}{FUNCIONES[m] && !FUNCIONES[m].listo ? <span className="muted"> · próximamente</span> : null}</td>
                {ACCIONES.map((a) => (
                  <td key={a} className="n" title={FUNCIONES[m]?.[a] || ''}>
                    <input type="checkbox" checked={sel.has(m + ':' + a)} disabled={bloqueada(m, a)} onChange={() => cambiar(m, a)} aria-label={(FUNCIONES[m]?.t || m) + ' ' + a} />
                  </td>
                ))}
              </tr>
            ))}</tbody>
          </table>
        </div>
        <details className="small"><summary>¿Qué da cada casilla?</summary><FuncionesRol permisos={ORDEN_MOD.flatMap((m) => ACCIONES.map((a) => ({ modulo: m, accion: a })))} /></details>
        <Falla msg={err} />
        <div className="row between" style={{ gap: 8, flexWrap: 'wrap' }}>
          <span className="small"><b>{sel.size}</b> funciones marcadas</span>
          <div className="row" style={{ gap: 8 }}>
            <button className="btn" onClick={onCerrar}>Cancelar</button>
            <button className="btn btn-p" onClick={guardar} disabled={guardando}>{guardando ? 'Guardando…' : 'Guardar rol'}</button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
