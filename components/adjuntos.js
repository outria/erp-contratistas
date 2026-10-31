'use client';
// v1.62: Adjuntos (gestion documental). Cualquier registro de la plataforma puede llevar sus soportes:
// PDF, fotos o documentos escaneados (SOAT, OC del cliente, recibido firmado, facturas, actas...).
// Se guardan en el almacenamiento privado de la empresa; se abren con un enlace temporal.
import { useRef, useState } from 'react';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';

const MAX_MB = 15;
const tamano = (b) => (b >= 1048576 ? (b / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(b / 1024)) + ' KB');
const limpio = (n) => n.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9._-]+/g, '_').slice(-80);

export function Adjuntos({ entidad, id, titulo = 'Documentos adjuntos', puedeSubir = true, compacto = false }) {
  const { empresaId, perfil, sesion } = useApp();
  const ref = useRef(null);
  const [err, setErr] = useState(null);
  const [subiendo, setSubiendo] = useState(false);
  const [desc, setDesc] = useState('');
  const d = useCarga(() => q(sb().from('adjuntos').select('*').eq('empresa_id', empresaId).eq('entidad', entidad).eq('entidad_id', id)
    .order('subido_en', { ascending: false })), [empresaId, entidad, id]);
  const yo = sesion?.user?.id;

  async function subir(files) {
    setErr(null);
    const lista = [...(files || [])];
    if (!lista.length) return;
    const grande = lista.find((f) => f.size > MAX_MB * 1048576);
    if (grande) { setErr('El archivo ' + grande.name + ' pesa más de ' + MAX_MB + ' MB. Redúzcalo o escanéelo en menor resolución.'); return; }
    setSubiendo(true);
    try {
      for (const f of lista) {
        const ruta = empresaId + '/' + entidad + '/' + id + '/' + Date.now() + '_' + limpio(f.name);
        const { error } = await sb().storage.from('adjuntos').upload(ruta, f, { contentType: f.type || 'application/octet-stream', upsert: false });
        if (error) throw new Error(error.message);
        await q(sb().from('adjuntos').insert({ empresa_id: empresaId, entidad, entidad_id: id, nombre: f.name, ruta, tipo_mime: f.type || null, tamano: f.size, descripcion: desc.trim() || null }));
      }
      setDesc('');
      if (ref.current) ref.current.value = '';
      d.recargar();
    } catch (e) { setErr(e.message); } finally { setSubiendo(false); }
  }
  async function abrir(a) {
    setErr(null);
    const { data, error } = await sb().storage.from('adjuntos').createSignedUrl(a.ruta, 300);
    if (error) { setErr(error.message); return; }
    window.open(data.signedUrl, '_blank', 'noopener');
  }
  async function quitar(a) {
    setErr(null);
    try {
      await q(sb().from('adjuntos').delete().eq('id', a.id));
      await sb().storage.from('adjuntos').remove([a.ruta]);
      d.recargar();
    } catch (e) { setErr(e.message); }
  }

  const filas = d.datos || [];
  return (
    <div className={compacto ? 'stack' : 'card stack'} style={{ gap: 8 }}>
      <div className="row between" style={{ flexWrap: 'wrap', gap: 8 }}>
        <b>📎 {titulo} {filas.length ? <span className="small muted">({filas.length})</span> : null}</b>
        {puedeSubir && (
          <div className="row" style={{ gap: 6, flexWrap: 'wrap', alignItems: 'center' }}>
            <input value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="Qué es (opcional): SOAT 2027, recibido firmado…" style={{ minWidth: 220 }} />
            <label className="btn btn-p" style={{ cursor: 'pointer', opacity: subiendo ? 0.6 : 1 }}>
              {subiendo ? 'Subiendo…' : '＋ Adjuntar'}
              <input ref={ref} type="file" multiple accept="application/pdf,image/*,.doc,.docx,.xls,.xlsx" style={{ display: 'none' }} disabled={subiendo} onChange={(e) => subir(e.target.files)} />
            </label>
          </div>
        )}
      </div>
      {err && <div className="aviso bad">{err}</div>}
      {d.cargando && !d.datos ? <span className="small muted">Cargando…</span> : filas.length === 0 ? <span className="small muted">Sin documentos adjuntos.</span> : (
        <table className="t">
          <tbody>{filas.map((a) => (
            <tr key={a.id}>
              <td><a href="#" onClick={(e) => { e.preventDefault(); abrir(a); }}>{/pdf/i.test(a.tipo_mime || a.nombre) ? '📄' : /image/i.test(a.tipo_mime || '') ? '🖼' : '📁'} {a.nombre}</a>
                {a.descripcion ? <div className="small muted">{a.descripcion}</div> : null}</td>
              <td className="small muted">{tamano(a.tamano || 0)}</td>
              <td className="small muted">{new Date(a.subido_en).toLocaleString('es-CO', { dateStyle: 'short', timeStyle: 'short' })}{a.subido_nombre ? ' · ' + a.subido_nombre : ''}</td>
              <td>{(perfil?.es_superadmin || a.subido_por === yo) && <button className="btn" style={{ padding: '3px 8px' }} onClick={() => quitar(a)} title="Quitar este adjunto">✕</button>}</td>
            </tr>
          ))}</tbody>
        </table>
      )}
    </div>
  );
}
