'use client';
// M3 · Proveedores y homologacion: el maestro de proveedores de la empresa, su homologacion, documentos, bloqueos,
// evaluacion y lo que ofrecen (producto x marca x presentacion) con su precio vigente.
import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Cargando, Falla, Consejo, Tabla, Estado } from '@/components/ui';
import { FormProveedor, FichaProveedor, TIPOS_PROVEEDOR, CATEGORIAS } from '@/components/proveedores';
import { UsuariosPortal, DocumentosPortal } from '@/components/portal-usuarios';
import { num, fechaCorta } from '@/lib/fmt';

export default function Proveedores() {
  const { empresaId, puede } = useApp();
  const params = useSearchParams();
  const router = useRouter();
  const id = params.get('id');
  const [filtro, setFiltro] = useState('');
  const [soloProblemas, setSoloProblemas] = useState(false);
  const [form, setForm] = useState(null);     // null | {} nuevo | tercero
  const [msg, setMsg] = useState(null);
  const puedeEditar = puede('M3', 'crear') || puede('M13', 'crear');
  const puedeAprobar = puede('M3', 'aprobar');
  const lista = useCarga(() => q(sb().rpc('proveedores_lista', { p_empresa: empresaId })), [empresaId]);
  const catalogos = useCarga(() => q(sb().rpc('catalogos_compras', { p_empresa: empresaId })), [empresaId]);
  const ficha = useCarga(async () => id ? q(sb().rpc('proveedor_ficha', { p_tercero: id })) : null, [id]);
  const filas = useMemo(() => (lista.datos ?? []).filter((t) => (!filtro || `${t.razon_social} ${t.nombre_comercial ?? ''} ${t.numero}`.toLowerCase().includes(filtro.toLowerCase())) && (!soloProblemas || t.bloqueado || t.docs_vencidos > 0 || t.docs_faltantes > 0 || t.estado_homologacion !== 'homologado')), [lista.datos, filtro, soloProblemas]);
  const kpi = useMemo(() => { const l = lista.datos ?? []; return { total: l.length, homologados: l.filter((t) => t.estado_homologacion === 'homologado').length, bloqueados: l.filter((t) => t.bloqueado).length, inpec: l.filter((t) => t.proyecto_productivo).length, docs: l.filter((t) => t.docs_vencidos > 0 || t.docs_faltantes > 0).length }; }, [lista.datos]);
  const recargar = () => { lista.recargar(); ficha.recargar(); catalogos.recargar(); };

  return (
    <>
      <Encabezado titulo="Proveedores y homologacion" sub="Quien nos vende que, con que marca y empaque, a que precio, con que documentos al dia y con que calificacion. Los proyectos productivos del INPEC van de primeros.">
        <Link href="/precios" className="btn">Master de precios</Link>
        {puedeEditar && <button className="btn btn-p" onClick={() => setForm({})}>Nuevo proveedor</button>}
      </Encabezado>
      {!id && <Consejo>
        Cada proveedor es un tercero con su NIT (una panaderia del INPEC es un proveedor aparte, ligado a su establecimiento). Dentro del proveedor se registran sus <b>ofertas</b>: producto, marca y presentacion, cada una con su precio y su homologacion. Un proveedor puede traer la misma cosa en varias marcas y empaques, y una marca la pueden traer varios proveedores: el sistema compara todo por precio por unidad de compra. Un <b>bloqueo</b> vigente (morosidad, calidad, documentos) lo saca de la seleccion automatica.
      </Consejo>}
      {msg && <div className={`aviso ${msg.ok ? 'ok' : 'bad'} mb12`}>{msg.t}</div>}
      {!id && (
        <>
          <div className="grid g4 mb12">
            {[['total', 'proveedores'], ['homologados', 'homologados'], ['inpec', 'proyectos productivos INPEC'], ['bloqueados', 'bloqueados'], ['docs', 'con documentos pendientes']].map(([k, l]) => <div key={k} className="card kpi"><span className="v">{num(kpi[k])}</span><span className="l">{l}</span></div>)}
          </div>
          <div className="row gap10 mb12 wrap">
            <input placeholder="Buscar por nombre o NIT…" value={filtro} onChange={(e) => setFiltro(e.target.value)} style={{ minWidth: 260 }} />
            <label className="row gap6 small"><input type="checkbox" checked={soloProblemas} onChange={(e) => setSoloProblemas(e.target.checked)} /> Solo con pendientes (sin homologar, bloqueados o documentos)</label>
          </div>
          {lista.err && <Falla msg={lista.err} />}
          <div className="card">
            {lista.cargando && !lista.datos ? <Cargando /> : <Tabla cols={[
              { t: 'Proveedor', r: (t) => <><b>{t.nombre_comercial ?? t.razon_social}</b>{t.nombre_comercial && <div className="small muted">{t.razon_social}</div>}<div className="small muted">{t.tipo_documento} {t.numero}{t.dv != null ? `-${t.dv}` : ''}{t.ciudad ? ` · ${t.ciudad}` : ''}</div></> },
              { t: 'Tipo', r: (t) => <>{t.proyecto_productivo ? <span className="chip info">INPEC · {t.establecimiento}</span> : (TIPOS_PROVEEDOR[t.tipo_proveedor] ?? '·')}<div className="small muted">{(t.categorias ?? []).map((c) => CATEGORIAS[c] ?? c).join(', ')}</div></> },
              { t: 'Homologacion', r: (t) => <><Estado e={t.estado_homologacion} />{t.homologacion_vence && <div className="small muted">vence {fechaCorta(t.homologacion_vence)}</div>}</> },
              { t: 'Ofertas', n: true, r: (t) => <>{num(t.productos)}{t.productos_propuestos ? <div className="small warn">{t.productos_propuestos} por homologar</div> : null}</> },
              { t: 'Precios vigentes', n: true, r: (t) => num(t.precios_vigentes) },
              { t: 'Documentos', r: (t) => (t.docs_vencidos || t.docs_faltantes) ? <span className="chip warn">{[t.docs_faltantes ? `${t.docs_faltantes} faltan` : null, t.docs_vencidos ? `${t.docs_vencidos} vencidos` : null].filter(Boolean).join(' · ')}</span> : <span className="chip ok">al dia</span> },
              { t: 'Calificacion', n: true, r: (t) => t.calificacion != null ? num(t.calificacion, 1) : '·' },
              { t: 'Condiciones', r: (t) => <span className="small">{t.entrega_en === 'sede' ? 'en sede' : t.entrega_en === 'ambos' ? 'CEDI o sede' : 'CEDI'}{t.condicion_pago ? ` · ${t.condicion_pago}${t.plazo_dias ? ` ${t.plazo_dias} d` : ''}` : ''}{t.lead_time_dias != null ? ` · ${t.lead_time_dias} d entrega` : ''}</span> },
              { t: 'Estado', r: (t) => t.bloqueado ? <span className="chip bad" title={t.bloqueo}>bloqueado</span> : <Estado e={t.estado} /> },
              { t: '', r: (t) => <Link href={`/proveedores?id=${t.id}`} className="btn btn-xs">Abrir</Link> },
            ]} filas={filas} vacio="No hay proveedores. Cree el primero o importelos desde Excel (pronto)." />}
          </div>
        </>
      )}
      {id && (
        <>
          <Link href="/proveedores" className="btn btn-s mb12">← Todos los proveedores</Link>
          {ficha.err && <Falla msg={ficha.err} />}
          {!ficha.datos ? <Cargando /> : <FichaProveedor ficha={ficha.datos} catalogos={catalogos.datos} puedeEditar={puedeEditar} puedeAprobar={puedeAprobar} onRecargar={recargar} onEditar={() => setForm(ficha.datos.tercero)} onMsg={setMsg} />}
          {ficha.datos && <DocumentosPortal terceroId={id} puedeEditar={puedeEditar} onMsg={setMsg} />}
          {ficha.datos && <UsuariosPortal terceroId={id} puedeEditar={puedeEditar} onMsg={setMsg} />}
        </>
      )}
      {form && <FormProveedor empresaId={empresaId} tercero={form.id ? form : null} catalogos={catalogos.datos} onCerrar={() => setForm(null)} onGuardado={(tid) => { setForm(null); setMsg({ ok: true, t: 'Proveedor guardado.' }); recargar(); if (!id) router.push(`/proveedores?id=${tid}`); }} />}
    </>
  );
}
