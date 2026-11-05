'use client';
// Componentes de dominio de Compras: ficha de proveedor (datos, productos y precios, documentos, bloqueos, evaluacion) y alta de oferta.
import { useMemo, useState } from 'react';
import { sb, q } from '@/lib/supabase';
import { Panel, Campo, Tabla, Estado, Cargando } from '@/components/ui';
import { num, cop, fechaCorta, hoyISO } from '@/lib/fmt';

export const TIPOS_PROVEEDOR = { fabricante: 'Fabricante', distribuidor: 'Distribuidor', importador: 'Importador', productor_primario: 'Productor primario', proyecto_productivo_inpec: 'Proyecto productivo INPEC', transportador: 'Transportador', servicios: 'Servicios', otro: 'Otro' };
export const ESTADOS_HOMOLOGACION = { en_proceso: 'en proceso', homologado: 'homologado', condicionado: 'condicionado', rechazado: 'rechazado', suspendido: 'suspendido', propuesto: 'propuesto' };
export const CATEGORIAS = { proteinas: 'Proteinas', fruver: 'Frutas y verduras', abarrotes: 'Abarrotes', lacteos: 'Lacteos', panaderia: 'Panaderia', bebidas: 'Bebidas', aseo: 'Aseo', otros: 'Otros' };
const TIPOS_BLOQUEO = { morosidad: 'Morosidad', calidad: 'Calidad', incumplimiento: 'Incumplimiento', legal: 'Legal', documentos: 'Documentos vencidos', otro: 'Otro' };
const ENTREGA = { cedi: 'En el CEDI', sede: 'Directo en sede', ambos: 'CEDI o sede' };

const vacio = { tipo_persona: 'juridica', tipo_documento: 'NIT', numero: '', razon_social: '', nombre_comercial: '', tipo_proveedor: 'distribuidor', proyecto_productivo: false, contrato_sede_id: '', categorias: [], ciudad: '', direccion: '', telefono: '', celular: '', correo: '', correo_facturacion: '', entrega_en: 'cedi', condicion_pago: 'credito', plazo_dias: 30, lead_time_dias: 2, minimo_pedido: '', estado_homologacion: 'en_proceso', regimen: '', responsable_iva: null, notas: '' };

// formulario de proveedor (alta o edicion)
export function FormProveedor({ empresaId, tercero, catalogos, onCerrar, onGuardado }) {
  const [f, setF] = useState(() => ({ ...vacio, ...(tercero ?? {}), contrato_sede_id: tercero?.contrato_sede_id ?? '', categorias: tercero?.categorias ?? [] }));
  const [err, setErr] = useState(null); const [guardando, setGuardando] = useState(false);
  const set = (k, v) => setF((o) => ({ ...o, [k]: v }));
  const guardar = async () => {
    setGuardando(true); setErr(null);
    try {
      const fila = { empresa_id: empresaId, tipo_persona: f.tipo_persona, tipo_documento: f.tipo_documento, numero: f.numero, razon_social: f.razon_social, nombre_comercial: f.nombre_comercial || null,
        es_proveedor: true, tipo_proveedor: f.proyecto_productivo ? 'proyecto_productivo_inpec' : f.tipo_proveedor || null, proyecto_productivo: !!f.proyecto_productivo, contrato_sede_id: f.proyecto_productivo ? f.contrato_sede_id || null : null,
        categorias: f.categorias, ciudad: f.ciudad || null, direccion: f.direccion || null, telefono: f.telefono || null, celular: f.celular || null, correo: f.correo || null, correo_facturacion: f.correo_facturacion || null,
        entrega_en: f.entrega_en, condicion_pago: f.condicion_pago || null, plazo_dias: f.plazo_dias === '' ? null : Number(f.plazo_dias), lead_time_dias: f.lead_time_dias === '' ? null : Number(f.lead_time_dias), minimo_pedido: f.minimo_pedido === '' ? null : Number(f.minimo_pedido),
        estado_homologacion: f.estado_homologacion, regimen: f.regimen || null, responsable_iva: f.responsable_iva, notas: f.notas || null };
      const r = tercero?.id ? await q(sb().from('terceros').update(fila).eq('id', tercero.id).select('id').single()) : await q(sb().from('terceros').insert(fila).select('id').single());
      onGuardado(r.id);
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  };
  const cats = Object.keys(CATEGORIAS);
  return (
    <Panel titulo={tercero?.id ? 'Editar proveedor' : 'Nuevo proveedor'} sub="Lo obligatorio es el documento y la razon social; lo demas se completa con el tiempo." onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={guardando || !f.numero || !f.razon_social || (f.proyecto_productivo && !f.contrato_sede_id)} onClick={guardar}>{guardando ? 'Guardando…' : 'Guardar'}</button>}>
      {err && <div className="aviso bad mb12">{err}</div>}
      <div className="grid g3 mb8">
        <Campo l="Tipo de persona"><select value={f.tipo_persona} onChange={(e) => set('tipo_persona', e.target.value)}><option value="juridica">Juridica</option><option value="natural">Natural</option><option value="ut_consorcio">UT / consorcio</option></select></Campo>
        <Campo l="Documento"><select value={f.tipo_documento} onChange={(e) => set('tipo_documento', e.target.value)}>{['NIT', 'CC', 'CE', 'PAS', 'NIT_EXT'].map((x) => <option key={x}>{x}</option>)}</select></Campo>
        <Campo l="Numero" req><input value={f.numero} onChange={(e) => set('numero', e.target.value)} placeholder="sin DV" /></Campo>
      </div>
      <Campo l="Razon social" req className="mb8"><input value={f.razon_social} onChange={(e) => set('razon_social', e.target.value)} /></Campo>
      <Campo l="Nombre comercial" className="mb8"><input value={f.nombre_comercial ?? ''} onChange={(e) => set('nombre_comercial', e.target.value)} /></Campo>
      <div className="grid g2 mb8">
        <Campo l="Tipo de proveedor"><select value={f.proyecto_productivo ? 'proyecto_productivo_inpec' : f.tipo_proveedor ?? ''} disabled={f.proyecto_productivo} onChange={(e) => set('tipo_proveedor', e.target.value)}>{Object.entries(TIPOS_PROVEEDOR).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
        <Campo l="Estado de homologacion"><select value={f.estado_homologacion} onChange={(e) => set('estado_homologacion', e.target.value)}>{['en_proceso', 'homologado', 'condicionado', 'rechazado', 'suspendido'].map((x) => <option key={x} value={x}>{ESTADOS_HOMOLOGACION[x]}</option>)}</select></Campo>
      </div>
      <div className="aviso info small mb8">
        <label className="row gap6"><input type="checkbox" checked={!!f.proyecto_productivo} onChange={(e) => set('proyecto_productivo', e.target.checked)} /> <b>Proyecto productivo del INPEC</b> (panaderia u otro del establecimiento; razon social propia, factura por su lado, prioridad contractual para lo que ofrece)</label>
        {f.proyecto_productivo && <Campo l="Establecimiento al que pertenece" req className="mt8"><select value={f.contrato_sede_id ?? ''} onChange={(e) => set('contrato_sede_id', e.target.value)}><option value="">Elija…</option>{(catalogos?.establecimientos ?? []).map((s) => <option key={s.id} value={s.id}>{s.nombre} · {s.contrato}</option>)}</select></Campo>}
      </div>
      <Campo l="Categorias que surte" className="mb8"><div className="row gap8 wrap">{cats.map((c) => <label key={c} className="row gap4 small"><input type="checkbox" checked={f.categorias.includes(c)} onChange={(e) => set('categorias', e.target.checked ? [...f.categorias, c] : f.categorias.filter((x) => x !== c))} /> {CATEGORIAS[c]}</label>)}</div></Campo>
      <div className="grid g3 mb8">
        <Campo l="Entrega"><select value={f.entrega_en} onChange={(e) => set('entrega_en', e.target.value)}>{Object.entries(ENTREGA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
        <Campo l="Condicion de pago"><select value={f.condicion_pago ?? ''} onChange={(e) => set('condicion_pago', e.target.value)}><option value="">·</option><option value="contado">Contado</option><option value="anticipo">Anticipo</option><option value="credito">Credito</option></select></Campo>
        <Campo l="Plazo (dias)"><input type="number" min="0" value={f.plazo_dias ?? ''} onChange={(e) => set('plazo_dias', e.target.value)} /></Campo>
        <Campo l="Lead time (dias entre OC y entrega)"><input type="number" min="0" value={f.lead_time_dias ?? ''} onChange={(e) => set('lead_time_dias', e.target.value)} /></Campo>
        <Campo l="Pedido minimo ($)"><input type="number" min="0" value={f.minimo_pedido ?? ''} onChange={(e) => set('minimo_pedido', e.target.value)} /></Campo>
        <Campo l="Regimen"><select value={f.regimen ?? ''} onChange={(e) => set('regimen', e.target.value)}><option value="">·</option><option value="ordinario">Ordinario (responsable de IVA)</option><option value="simple">Regimen simple</option><option value="no_responsable_iva">No responsable de IVA</option><option value="especial">Especial</option></select></Campo>
      </div>
      <div className="grid g2 mb8">
        <Campo l="Ciudad"><input value={f.ciudad ?? ''} onChange={(e) => set('ciudad', e.target.value)} /></Campo>
        <Campo l="Direccion"><input value={f.direccion ?? ''} onChange={(e) => set('direccion', e.target.value)} /></Campo>
        <Campo l="Telefono"><input value={f.telefono ?? ''} onChange={(e) => set('telefono', e.target.value)} /></Campo>
        <Campo l="Celular / WhatsApp"><input value={f.celular ?? ''} onChange={(e) => set('celular', e.target.value)} /></Campo>
        <Campo l="Correo"><input value={f.correo ?? ''} onChange={(e) => set('correo', e.target.value)} /></Campo>
        <Campo l="Correo de facturacion electronica"><input value={f.correo_facturacion ?? ''} onChange={(e) => set('correo_facturacion', e.target.value)} /></Campo>
      </div>
      <Campo l="Notas"><textarea rows={2} value={f.notas ?? ''} onChange={(e) => set('notas', e.target.value)} /></Campo>
    </Panel>
  );
}

// alta de oferta: producto + marca + presentacion + precio
export function FormOferta({ tercero, catalogos, onCerrar, onGuardado, puedeAprobar }) {
  const [prod, setProd] = useState('');
  const [busca, setBusca] = useState('');
  const [marca, setMarca] = useState('');
  const [pres, setPres] = useState('');
  const [presNueva, setPresNueva] = useState({ nombre: '', contenido: '', empaque: 'bulto' });
  const [precio, setPrecio] = useState('');
  const [desde, setDesde] = useState(hoyISO());
  const [iva, setIva] = useState(0);
  const [estado, setEstado] = useState(puedeAprobar ? 'homologado' : 'propuesto');
  const [entrega, setEntrega] = useState('');
  const [lead, setLead] = useState('');
  const [err, setErr] = useState(null); const [guardando, setGuardando] = useState(false);
  const productos = useMemo(() => (catalogos?.productos ?? []).filter((p) => !busca || p.nombre.toLowerCase().includes(busca.toLowerCase())).slice(0, 60), [catalogos, busca]);
  const p = (catalogos?.productos ?? []).find((x) => x.id === prod);
  const presSel = p?.presentaciones?.find((x) => x.id === pres);
  const contenido = pres === 'nueva' ? Number(presNueva.contenido) : presSel?.contenido;
  const porCompra = precio && contenido && p ? (Number(precio) / contenido) * (p.factor_compra || 1) : null;
  const guardar = async () => {
    setGuardando(true); setErr(null);
    try {
      const id = await q(sb().rpc('alta_oferta', { p_tercero: tercero.id, p_producto: prod, p_marca: marca || null,
        p_presentacion: pres === 'nueva' ? presNueva.nombre : presSel?.nombre ?? null, p_contenido: pres === 'nueva' ? Number(presNueva.contenido) : presSel?.contenido ?? null, p_unidad_empaque: pres === 'nueva' ? presNueva.empaque : 'und',
        p_precio: precio === '' ? null : Number(precio), p_desde: desde, p_iva: Number(iva) || 0, p_estado: estado, p_codigo_proveedor: null, p_lead_time: lead === '' ? null : Number(lead), p_entrega_en: entrega || null }));
      onGuardado(id);
    } catch (e) { setErr(e.message); } finally { setGuardando(false); }
  };
  return (
    <Panel titulo={`Nueva oferta · ${tercero.nombre_comercial ?? tercero.razon_social}`} sub="Que producto ofrece, de que marca, en que empaque y a que precio" onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={guardando || !prod || (pres === 'nueva' && (!presNueva.nombre || !presNueva.contenido))} onClick={guardar}>{guardando ? 'Guardando…' : 'Guardar'}</button>}>
      {err && <div className="aviso bad mb12">{err}</div>}
      <Campo l="Producto" req className="mb8">
        <input placeholder="Buscar producto…" value={busca} onChange={(e) => setBusca(e.target.value)} className="mb8" />
        <select value={prod} onChange={(e) => { setProd(e.target.value); setPres(''); }} size={6}>{productos.map((x) => <option key={x.id} value={x.id}>{x.nombre} · {x.categoria}</option>)}</select>
      </Campo>
      {p && <div className="small muted mb8">Unidad base {p.unidad_base} · se compra por {p.unidad_compra} ({num(p.factor_compra)} {p.unidad_base})</div>}
      <div className="grid g2 mb8">
        <Campo l="Marca (vacio si es materia prima sin marca)"><input list="marcas" value={marca} onChange={(e) => setMarca(e.target.value)} placeholder="ej. Diana" /><datalist id="marcas">{(catalogos?.marcas ?? []).map((m) => <option key={m.id} value={m.nombre} />)}</datalist></Campo>
        <Campo l="Presentacion / unidad de empaque"><select value={pres} onChange={(e) => setPres(e.target.value)}><option value="">A granel (por {p?.unidad_compra ?? 'unidad de compra'})</option>{(p?.presentaciones ?? []).map((x) => <option key={x.id} value={x.id}>{x.nombre} ({num(x.contenido)} {p.unidad_base})</option>)}<option value="nueva">+ Nueva presentacion…</option></select></Campo>
      </div>
      {pres === 'nueva' && <div className="grid g3 mb8">
        <Campo l="Nombre" req><input value={presNueva.nombre} onChange={(e) => setPresNueva({ ...presNueva, nombre: e.target.value })} placeholder="Bulto 50 kg" /></Campo>
        <Campo l={`Contenido (${p?.unidad_base ?? 'g'})`} req><input type="number" min="0" value={presNueva.contenido} onChange={(e) => setPresNueva({ ...presNueva, contenido: e.target.value })} placeholder="50000" /></Campo>
        <Campo l="Empaque"><select value={presNueva.empaque} onChange={(e) => setPresNueva({ ...presNueva, empaque: e.target.value })}>{['bulto', 'caja', 'canasta', 'paca', 'bandeja', 'garrafa', 'bolsa', 'und', 'kg', 'l'].map((x) => <option key={x}>{x}</option>)}</select></Campo>
      </div>}
      <div className="grid g3 mb8">
        <Campo l={`Precio por ${pres ? 'presentacion' : p?.unidad_compra ?? 'unidad de compra'} (sin IVA)`}><input type="number" min="0" value={precio} onChange={(e) => setPrecio(e.target.value)} /></Campo>
        <Campo l="IVA %"><select value={iva} onChange={(e) => setIva(e.target.value)}><option value={0}>0 (excluido / exento)</option><option value={5}>5</option><option value={19}>19</option></select></Campo>
        <Campo l="Rige desde"><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
      </div>
      {porCompra != null && <div className="aviso ok small mb8">Equivale a <b>{cop(porCompra)}</b> por {p.unidad_compra}: asi se compara con las demas marcas y presentaciones.</div>}
      <div className="grid g3 mb8">
        <Campo l="Estado"><select value={estado} onChange={(e) => setEstado(e.target.value)}><option value="propuesto">Propuesto (por homologar)</option>{puedeAprobar && <option value="homologado">Homologado</option>}{puedeAprobar && <option value="condicionado">Condicionado</option>}</select></Campo>
        <Campo l="Entrega"><select value={entrega} onChange={(e) => setEntrega(e.target.value)}><option value="">Como el proveedor</option>{Object.entries(ENTREGA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
        <Campo l="Lead time (dias)"><input type="number" min="0" value={lead} onChange={(e) => setLead(e.target.value)} /></Campo>
      </div>
    </Panel>
  );
}

// precio nuevo para una oferta existente
export function FormPrecio({ oferta, onCerrar, onGuardado }) {
  const [precio, setPrecio] = useState(oferta.precio?.precio ?? '');
  const [desde, setDesde] = useState(hoyISO());
  const [iva, setIva] = useState(oferta.precio?.iva_pct ?? 0);
  const [origen, setOrigen] = useState('cotizacion');
  const [soporte, setSoporte] = useState('');
  const [err, setErr] = useState(null);
  const guardar = async () => {
    setErr(null);
    try { await q(sb().rpc('registrar_precio', { p_pp: oferta.id ?? oferta.pp_id, p_precio: Number(precio), p_desde: desde, p_iva: Number(iva) || 0, p_origen: origen, p_lugar: oferta.entrega_en ?? 'cedi', p_soporte: soporte || null })); onGuardado(); }
    catch (e) { setErr(e.message); }
  };
  return (
    <Panel titulo="Nuevo precio" sub={`${oferta.producto ?? ''}${oferta.marca ? ` · ${oferta.marca}` : ''}${oferta.presentacion ? ` · ${oferta.presentacion}` : ''}`} onCerrar={onCerrar}
      acciones={<button className="btn btn-p btn-s" disabled={precio === '' || !desde} onClick={guardar}>Guardar</button>}>
      {err && <div className="aviso bad mb12">{err}</div>}
      <div className="grid g2 mb8">
        <Campo l="Precio (sin IVA)" req><input type="number" min="0" value={precio} onChange={(e) => setPrecio(e.target.value)} /></Campo>
        <Campo l="Rige desde" req><input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></Campo>
        <Campo l="IVA %"><select value={iva} onChange={(e) => setIva(e.target.value)}><option value={0}>0</option><option value={5}>5</option><option value={19}>19</option></select></Campo>
        <Campo l="Origen"><select value={origen} onChange={(e) => setOrigen(e.target.value)}><option value="cotizacion">Cotizacion</option><option value="negociacion">Negociacion</option><option value="lista">Lista de precios</option><option value="factura">Ultima factura</option></select></Campo>
      </div>
      <Campo l="Soporte (correo, cotizacion No., acta)"><input value={soporte} onChange={(e) => setSoporte(e.target.value)} /></Campo>
      <div className="small muted mt12">El precio anterior se cierra el dia antes. El precio por unidad base se calcula solo (precio / contenido de la presentacion).</div>
    </Panel>
  );
}

// ficha del proveedor con pestanas
export function FichaProveedor({ ficha, catalogos, puedeEditar, puedeAprobar, onRecargar, onEditar, onMsg }) {
  const t = ficha.tercero;
  const [tab, setTab] = useState('productos');
  const [oferta, setOferta] = useState(false);
  const [precioDe, setPrecioDe] = useState(null);
  const [bloq, setBloq] = useState(null);
  const [evalF, setEvalF] = useState(null);
  const [docEdit, setDocEdit] = useState(null);
  const act = async (fn, ok) => { try { await fn(); onMsg({ ok: true, t: ok }); onRecargar(); } catch (e) { onMsg({ ok: false, t: e.message }); } };
  const cambiarEstadoOferta = (pp, estado) => act(() => q(sb().from('proveedor_productos').update({ estado }).eq('id', pp.id)), `Oferta ${ESTADOS_HOMOLOGACION[estado]}.`);
  const preferir = (pp) => act(() => q(sb().from('proveedor_productos').update({ preferido: !pp.preferido }).eq('id', pp.id)), pp.preferido ? 'Ya no es la primera opcion.' : 'Marcado como primera opcion para este producto.');
  const guardarDoc = (d) => act(() => q(sb().from('tercero_documentos').upsert({ empresa_id: t.empresa_id, tercero_id: t.id, codigo: d.codigo, fecha_documento: d.fecha_documento || null, vence: d.vence || null, numero: d.numero || null, notas: d.notas || null }, { onConflict: 'tercero_id,codigo' })), 'Documento registrado.');
  return (
    <>
      <div className="row between mb12 wrap">
        <div>
          <h2 className="m0">{t.razon_social}{t.nombre_comercial ? <span className="muted"> · {t.nombre_comercial}</span> : null}</h2>
          <div className="small muted">{t.tipo_documento} {t.numero}{t.dv != null ? `-${t.dv}` : ''} · {TIPOS_PROVEEDOR[t.tipo_proveedor] ?? t.tipo_proveedor ?? 'proveedor'}{t.ciudad ? ` · ${t.ciudad}` : ''}{t.establecimiento ? ` · ${t.establecimiento}` : ''}</div>
          <div className="row gap6 mt8 wrap">
            <Estado e={t.estado_homologacion} />{t.bloqueado && <span className="chip bad">bloqueado</span>}{t.proyecto_productivo && <span className="chip info">proyecto productivo INPEC · prioridad contractual</span>}
            {t.calificacion != null && <span className="chip">{num(t.calificacion, 1)} / 100</span>}<span className="chip">{ENTREGA[t.entrega_en]}</span>{t.condicion_pago && <span className="chip">{t.condicion_pago}{t.plazo_dias ? ` ${t.plazo_dias} dias` : ''}</span>}{t.lead_time_dias != null && <span className="chip">lead time {t.lead_time_dias} d</span>}
          </div>
        </div>
        <div className="row gap6">{puedeEditar && <button className="btn btn-s" onClick={onEditar}>Editar datos</button>}{puedeEditar && <button className="btn btn-s btn-p" onClick={() => setOferta(true)}>Nueva oferta</button>}</div>
      </div>
      <div className="tabs">
        {[['productos', `Productos y precios (${ficha.productos.length})`], ['documentos', `Documentos (${ficha.documentos.filter((d) => d.estado === 'ok').length}/${ficha.documentos.filter((d) => d.obligatorio).length} obligatorios)`], ['bloqueos', `Bloqueos (${ficha.bloqueos.filter((b) => b.vigente).length})`], ['evaluacion', 'Evaluacion'], ['contactos', `Contactos (${ficha.contactos.length})`]].map(([k, v]) => <button key={k} className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{v}</button>)}
      </div>
      <div className="card">
        {tab === 'productos' && <Tabla cols={[
          { t: 'Producto', r: (p) => <><b>{p.producto}</b><div className="small muted">{CATEGORIAS[p.categoria] ?? p.categoria}{p.codigo_proveedor ? ` · cod. ${p.codigo_proveedor}` : ''}{p.origen ? ` · ${p.origen}` : ''}</div></> },
          { t: 'Marca', r: (p) => p.marca ?? <span className="muted">sin marca</span> },
          { t: 'Presentacion', r: (p) => p.presentacion ? <>{p.presentacion}<div className="small muted">{num(p.contenido)} {p.unidad_base}</div></> : <span className="muted">granel ({p.unidad_compra})</span> },
          { t: 'Precio', n: true, r: (p) => p.precio ? <><b>{cop(p.precio.precio)}</b><div className="small muted">desde {fechaCorta(p.precio.desde)}{p.precio.iva_pct ? ` · IVA ${p.precio.iva_pct} %` : ''}</div></> : <span className="muted">sin precio</span> },
          { t: `Por unidad de compra`, n: true, r: (p) => p.precio_por_compra != null ? <b>{cop(p.precio_por_compra)} / {p.unidad_compra}</b> : '·' },
          { t: 'Estado', r: (p) => <>{p.preferido && <span className="chip ok">1a opcion</span>} <Estado e={p.estado} /></> },
          { t: '', r: (p) => <span className="row gap4 nowrap end">
              {puedeEditar && <button className="btn btn-xs" onClick={() => setPrecioDe(p)}>Precio</button>}
              {puedeAprobar && p.estado === 'propuesto' && <button className="btn btn-xs btn-p" onClick={() => cambiarEstadoOferta(p, 'homologado')}>Homologar</button>}
              {puedeAprobar && p.estado === 'homologado' && <button className="btn btn-xs" onClick={() => preferir(p)}>{p.preferido ? 'Quitar 1a' : '1a opcion'}</button>}
              {puedeAprobar && p.estado !== 'suspendido' && p.estado !== 'rechazado' && <button className="btn btn-xs btn-x" onClick={() => cambiarEstadoOferta(p, 'suspendido')}>Suspender</button>}
              {puedeAprobar && p.estado === 'suspendido' && <button className="btn btn-xs" onClick={() => cambiarEstadoOferta(p, 'homologado')}>Reactivar</button>}
            </span> },
        ]} filas={ficha.productos} vacio="Este proveedor todavia no tiene productos ofrecidos. Agregue la primera oferta." />}
        {tab === 'documentos' && <Tabla cols={[
          { t: 'Documento', r: (d) => <>{d.nombre}{d.obligatorio && <span className="req"> *</span>}<div className="small muted">{d.ayuda ?? ''}{d.vigencia_dias ? ` · vigencia ${d.vigencia_dias} dias` : ''}</div></> },
          { t: 'Estado', r: (d) => <span className={`chip ${d.estado === 'ok' ? 'ok' : d.estado === 'por_vencer' ? 'warn' : d.estado === 'vencido' ? 'bad' : d.obligatorio ? 'warn' : ''}`}>{{ ok: 'al dia', por_vencer: 'por vencer', vencido: 'vencido', falta: d.obligatorio ? 'falta' : 'no registrado' }[d.estado]}</span> },
          { t: 'Fecha', r: (d) => d.fecha_documento ? fechaCorta(d.fecha_documento) : '·' }, { t: 'Vence', r: (d) => d.vence ? fechaCorta(d.vence) : '·' }, { t: 'Numero / notas', r: (d) => <span className="small">{[d.numero, d.notas].filter(Boolean).join(' · ') || '·'}</span> },
          { t: '', r: (d) => puedeEditar && <button className="btn btn-xs" onClick={() => setDocEdit({ ...d })}>{d.id ? 'Actualizar' : 'Registrar'}</button> },
        ]} filas={ficha.documentos} idKey="codigo" />}
        {tab === 'bloqueos' && <>
          <div className="row between mb12"><span className="small muted">Un bloqueo vigente saca al proveedor de la seleccion automatica y frena las ordenes de compra.</span>{puedeAprobar && <button className="btn btn-s btn-x" onClick={() => setBloq({ tipo: 'morosidad', motivo: '', hasta: '' })}>Bloquear</button>}</div>
          <Tabla cols={[{ t: 'Tipo', r: (b) => TIPOS_BLOQUEO[b.tipo] ?? b.tipo }, { t: 'Motivo', k: 'motivo' }, { t: 'Desde', r: (b) => fechaCorta(b.desde) }, { t: 'Hasta', r: (b) => b.hasta ? fechaCorta(b.hasta) : 'indefinido' },
            { t: 'Estado', r: (b) => b.levantado_en ? <span className="chip">levantado</span> : b.vigente ? <span className="chip bad">vigente</span> : <span className="chip">no vigente</span> },
            { t: '', r: (b) => puedeAprobar && !b.levantado_en && <button className="btn btn-xs" onClick={() => act(() => q(sb().rpc('levantar_bloqueo', { p_id: b.id, p_nota: null })), 'Bloqueo levantado.')}>Levantar</button> }]} filas={ficha.bloqueos} vacio="Sin bloqueos." />
        </>}
        {tab === 'evaluacion' && <>
          <div className="row between mb12"><span className="small muted">Ponderacion: cumplimiento 35 %, calidad 30 %, precio 20 %, servicio 15 %. Confiable 85+, aceptable 70+, condicionado 50+.</span>{puedeEditar && <button className="btn btn-s btn-p" onClick={() => setEvalF({ periodo: hoyISO().slice(0, 7), cumplimiento: 90, calidad: 90, precio: 80, servicio: 85, notas: '' })}>Evaluar periodo</button>}</div>
          <Tabla cols={[{ t: 'Periodo', k: 'periodo' }, { t: 'Cumplimiento', n: true, k: 'cumplimiento' }, { t: 'Calidad', n: true, k: 'calidad' }, { t: 'Precio', n: true, k: 'precio' }, { t: 'Servicio', n: true, k: 'servicio' }, { t: 'Puntaje', n: true, r: (e) => <b>{num(e.puntaje, 1)}</b> }, { t: 'Concepto', r: (e) => <Estado e={e.concepto} /> }, { t: 'Notas', k: 'notas' }]} filas={ficha.evaluaciones} vacio="Sin evaluaciones todavia." />
        </>}
        {tab === 'contactos' && <ContactosProveedor t={t} contactos={ficha.contactos} puedeEditar={puedeEditar} act={act} />}
      </div>
      {oferta && <FormOferta tercero={t} catalogos={catalogos} puedeAprobar={puedeAprobar} onCerrar={() => setOferta(false)} onGuardado={() => { setOferta(false); onMsg({ ok: true, t: 'Oferta registrada.' }); onRecargar(); }} />}
      {precioDe && <FormPrecio oferta={precioDe} onCerrar={() => setPrecioDe(null)} onGuardado={() => { setPrecioDe(null); onMsg({ ok: true, t: 'Precio registrado.' }); onRecargar(); }} />}
      {bloq && <Panel titulo="Bloquear proveedor" onCerrar={() => setBloq(null)} acciones={<button className="btn btn-x btn-s" disabled={!bloq.motivo} onClick={() => act(() => q(sb().rpc('bloquear_tercero', { p_tercero: t.id, p_tipo: bloq.tipo, p_motivo: bloq.motivo, p_hasta: bloq.hasta || null, p_bloquea_oc: true })), 'Proveedor bloqueado.').then(() => setBloq(null))}>Bloquear</button>}>
        <Campo l="Tipo" className="mb8"><select value={bloq.tipo} onChange={(e) => setBloq({ ...bloq, tipo: e.target.value })}>{Object.entries(TIPOS_BLOQUEO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
        <Campo l="Motivo" req className="mb8"><textarea rows={3} value={bloq.motivo} onChange={(e) => setBloq({ ...bloq, motivo: e.target.value })} placeholder="ej. Facturas vencidas a mas de 60 dias; rechazo de lote por temperatura" /></Campo>
        <Campo l="Hasta (vacio = hasta que se levante)"><input type="date" value={bloq.hasta} onChange={(e) => setBloq({ ...bloq, hasta: e.target.value })} /></Campo>
      </Panel>}
      {evalF && <Panel titulo="Evaluar periodo" onCerrar={() => setEvalF(null)} acciones={<button className="btn btn-p btn-s" onClick={() => act(() => q(sb().rpc('evaluar_tercero', { p_tercero: t.id, p_periodo: evalF.periodo, p_cumplimiento: Number(evalF.cumplimiento), p_calidad: Number(evalF.calidad), p_precio: Number(evalF.precio), p_servicio: Number(evalF.servicio), p_notas: evalF.notas || null })), 'Evaluacion guardada.').then(() => setEvalF(null))}>Guardar</button>}>
        <Campo l="Periodo (mes o trimestre)" className="mb8"><input value={evalF.periodo} onChange={(e) => setEvalF({ ...evalF, periodo: e.target.value })} placeholder="2026-10 o 2026-T4" /></Campo>
        {[['cumplimiento', 'Cumplimiento (entregas a tiempo y completas)'], ['calidad', 'Calidad (rechazos, devoluciones, cadena de frio)'], ['precio', 'Precio (competitividad y estabilidad)'], ['servicio', 'Servicio (respuesta, documentos, facturacion)']].map(([k, l]) => (
          <Campo key={k} l={`${l}: ${evalF[k]}`} className="mb8"><input type="range" min="0" max="100" step="5" value={evalF[k]} onChange={(e) => setEvalF({ ...evalF, [k]: e.target.value })} /></Campo>))}
        <Campo l="Notas"><textarea rows={2} value={evalF.notas} onChange={(e) => setEvalF({ ...evalF, notas: e.target.value })} /></Campo>
        <div className="mt12"><b>Puntaje: {num(evalF.cumplimiento * 0.35 + evalF.calidad * 0.3 + evalF.precio * 0.2 + evalF.servicio * 0.15, 1)}</b></div>
      </Panel>}
      {docEdit && <Panel titulo={docEdit.nombre} onCerrar={() => setDocEdit(null)} acciones={<button className="btn btn-p btn-s" onClick={() => guardarDoc(docEdit).then(() => setDocEdit(null))}>Guardar</button>}>
        <div className="grid g2 mb8">
          <Campo l="Fecha del documento"><input type="date" value={docEdit.fecha_documento ?? ''} onChange={(e) => { const f = e.target.value; const v = f && docEdit.vigencia_dias ? new Date(new Date(f).getTime() + docEdit.vigencia_dias * 86400000).toISOString().slice(0, 10) : docEdit.vence; setDocEdit({ ...docEdit, fecha_documento: f, vence: v }); }} /></Campo>
          <Campo l="Vence"><input type="date" value={docEdit.vence ?? ''} onChange={(e) => setDocEdit({ ...docEdit, vence: e.target.value })} /></Campo>
          <Campo l="Numero / referencia"><input value={docEdit.numero ?? ''} onChange={(e) => setDocEdit({ ...docEdit, numero: e.target.value })} /></Campo>
          <Campo l="Notas"><input value={docEdit.notas ?? ''} onChange={(e) => setDocEdit({ ...docEdit, notas: e.target.value })} /></Campo>
        </div>
        <div className="small muted">El archivo se adjunta desde la gestion documental (adjuntos del tercero); aqui queda la fecha y el vencimiento para las alertas.</div>
      </Panel>}
    </>
  );
}

function ContactosProveedor({ t, contactos, puedeEditar, act }) {
  const [n, setN] = useState(null);
  return (
    <>
      <div className="row between mb12"><span className="small muted">Quien atiende cada tema: comercial, cartera, logistica, calidad, facturacion.</span>{puedeEditar && <button className="btn btn-s" onClick={() => setN({ funcion: 'comercial', nombre: '', cargo: '', telefono: '', correo: '' })}>Agregar contacto</button>}</div>
      <Tabla cols={[{ t: 'Funcion', k: 'funcion' }, { t: 'Nombre', r: (c) => <>{c.nombre}{c.cargo ? <div className="small muted">{c.cargo}</div> : null}</> }, { t: 'Telefono', k: 'telefono' }, { t: 'Correo', k: 'correo' },
        { t: '', r: (c) => puedeEditar && <button className="btn btn-xs btn-x" onClick={() => act(() => q(sb().from('tercero_contactos').delete().eq('id', c.id)), 'Contacto quitado.')}>Quitar</button> }]} filas={contactos} vacio="Sin contactos." />
      {n && <Panel titulo="Contacto" onCerrar={() => setN(null)} acciones={<button className="btn btn-p btn-s" disabled={!n.nombre} onClick={() => act(() => q(sb().from('tercero_contactos').insert({ empresa_id: t.empresa_id, tercero_id: t.id, ...n })), 'Contacto agregado.').then(() => setN(null))}>Guardar</button>}>
        <div className="grid g2">
          <Campo l="Funcion"><select value={n.funcion} onChange={(e) => setN({ ...n, funcion: e.target.value })}>{['comercial', 'cartera', 'contabilidad', 'logistica', 'calidad', 'facturacion', 'gerencia', 'otro'].map((x) => <option key={x}>{x}</option>)}</select></Campo>
          <Campo l="Nombre" req><input value={n.nombre} onChange={(e) => setN({ ...n, nombre: e.target.value })} /></Campo>
          <Campo l="Cargo"><input value={n.cargo} onChange={(e) => setN({ ...n, cargo: e.target.value })} /></Campo>
          <Campo l="Telefono"><input value={n.telefono} onChange={(e) => setN({ ...n, telefono: e.target.value })} /></Campo>
          <Campo l="Correo"><input value={n.correo} onChange={(e) => setN({ ...n, correo: e.target.value })} /></Campo>
        </div>
      </Panel>}
    </>
  );
}
