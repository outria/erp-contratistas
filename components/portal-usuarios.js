'use client';
// M4 · Usuarios del portal de un proveedor: invitar (correo), ver estado y desactivar. Vive en la ficha del proveedor.
import { useState } from 'react';
import { useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Tabla, Campo } from '@/components/ui';
import { fechaCorta } from '@/lib/fmt';

export function UsuariosPortal({ terceroId, puedeEditar, onMsg }) {
  const d = useCarga(() => q(sb().from('usuarios_proveedor').select('id, correo, nombre, cargo, activo, usuario_id, creado_en').eq('tercero_id', terceroId).order('creado_en')), [terceroId]);
  const [f, setF] = useState({ correo: '', nombre: '', cargo: '' });
  const [ocupado, setOcupado] = useState(false);
  const invitar = async () => {
    setOcupado(true);
    try { const r = await q(sb().rpc('invitar_usuario_proveedor', { p_tercero: terceroId, p_correo: f.correo, p_nombre: f.nombre || null, p_cargo: f.cargo || null })); onMsg?.({ ok: r.activo, t: r.mensaje }); setF({ correo: '', nombre: '', cargo: '' }); d.recargar(); }
    catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); }
  };
  return (
    <div className="card mt12">
      <h3 className="m0 mb8">Usuarios del portal de proveedores</h3>
      <p className="small muted">Con su cuenta, el proveedor cotiza, propone precios, sube documentos y confirma OC en <b>/portal</b>, viendo solo lo suyo. La cuenta se crea en dos pasos: el administrador la invita en Supabase (Authentication, Invite user, con este correo) y aqui se liga al proveedor; si la cuenta ya existe queda activa de una.</p>
      <Tabla cols={[
        { t: 'Correo', r: (u) => <><b>{u.correo}</b><div className="small muted">{[u.nombre, u.cargo].filter(Boolean).join(' · ')}</div></> },
        { t: 'Estado', r: (u) => !u.activo ? <span className="chip">desactivado</span> : u.usuario_id ? <span className="chip ok">activo</span> : <span className="chip warn">pendiente de cuenta en Auth</span> },
        { t: 'Desde', r: (u) => fechaCorta(u.creado_en) },
        { t: '', r: (u) => puedeEditar && u.activo ? <button className="btn btn-xs" onClick={async () => { try { await q(sb().rpc('desactivar_usuario_proveedor', { p_id: u.id })); d.recargar(); } catch (e) { onMsg?.({ ok: false, t: e.message }); } }}>Desactivar</button> : null },
      ]} filas={d.datos ?? []} vacio="Este proveedor todavia no tiene usuarios del portal." />
      {puedeEditar && <div className="row gap6 wrap mt12 end">
        <Campo l="Correo"><input type="email" value={f.correo} onChange={(e) => setF((x) => ({ ...x, correo: e.target.value }))} placeholder="ventas@proveedor.com" /></Campo>
        <Campo l="Nombre"><input value={f.nombre} onChange={(e) => setF((x) => ({ ...x, nombre: e.target.value }))} /></Campo>
        <Campo l="Cargo"><input value={f.cargo} onChange={(e) => setF((x) => ({ ...x, cargo: e.target.value }))} /></Campo>
        <button className="btn btn-p" disabled={ocupado || !f.correo.includes('@')} onClick={invitar}>Invitar / activar</button>
      </div>}
    </div>
  );
}

// A3 · documentos subidos por el proveedor desde el portal: quedan pendientes hasta que Compras los valide
export function DocumentosPortal({ terceroId, puedeEditar, onMsg }) {
  const d = useCarga(() => q(sb().rpc('documentos_propuestos_lista', { p_tercero: terceroId })), [terceroId]);
  const [ocupado, setOcupado] = useState(false);
  const pendientes = (d.datos ?? []).filter((x) => x.estado === 'propuesto').length;
  if (!d.datos?.length) return null;
  const abrir = async (ruta) => { const { data, error } = await sb().storage.from('adjuntos').createSignedUrl(ruta, 300); if (error) { onMsg?.({ ok: false, t: error.message }); return; } window.open(data.signedUrl, '_blank'); };
  const resolver = async (x, acepta) => {
    const nota = acepta ? null : window.prompt('Motivo del rechazo (lo vera el proveedor):');
    if (!acepta && !nota) return;
    setOcupado(true);
    try { await q(sb().rpc('resolver_documento_propuesto', { p_id: x.id, p_acepta: acepta, p_nota: nota })); onMsg?.({ ok: true, t: acepta ? `${x.tipo} validado.` : `${x.tipo} rechazado.` }); d.recargar(); }
    catch (e) { onMsg?.({ ok: false, t: e.message }); } finally { setOcupado(false); }
  };
  return (
    <div className="card mt12">
      <h3 className="m0 mb8">Documentos subidos por el proveedor{pendientes ? ` (${pendientes} por validar)` : ''}</h3>
      <p className="small muted">Lo que el proveedor sube en el portal no cuenta hasta que Compras lo revise. Al validarlo, pasa a sus documentos con la fecha y el vencimiento indicados (si el tipo tiene vigencia fija, el vencimiento lo calcula el sistema).</p>
      <Tabla cols={[
        { t: 'Documento', r: (x) => <><b>{x.tipo}</b><div className="small muted">{x.archivo} · {x.subido_por ?? 'proveedor'} · {fechaCorta(x.creado_en)}</div></> },
        { t: 'Fecha', r: (x) => x.fecha ? fechaCorta(x.fecha) : '·' }, { t: 'Vence', r: (x) => x.vence ? fechaCorta(x.vence) : '·' }, { t: 'Numero', r: (x) => x.numero ?? '·' },
        { t: 'Estado', r: (x) => <span className={`chip ${x.estado === 'propuesto' ? 'warn' : x.estado === 'aceptado' ? 'ok' : 'bad'}`} title={x.nota ?? ''}>{x.estado === 'propuesto' ? 'por validar' : x.estado}</span> },
        { t: '', r: (x) => <span className="row gap4 nowrap"><button className="btn btn-xs" onClick={() => abrir(x.ruta)}>Ver</button>{x.estado === 'propuesto' && puedeEditar && <><button className="btn btn-xs btn-p" disabled={ocupado} onClick={() => resolver(x, true)}>Validar</button><button className="btn btn-xs" disabled={ocupado} onClick={() => resolver(x, false)}>Rechazar</button></>}</span> },
      ]} filas={d.datos} />
    </div>
  );
}
