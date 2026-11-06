'use client';
// Compras publicas locales (Ley 2046 de 2020): cumplimiento por contrato del mes en curso y los anteriores,
// parametros de cada contrato (meta + adicional ofrecido, base de calculo, rubro de alimentos), soportes del mes
// y exportacion al formato oficial de seguimiento.
import { useState } from 'react';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Consejo, Falla } from '@/components/ui';
import { ResumenComprasLocales, ParametrosCL, SoportesCL, nombreMes } from '@/components/compras-locales';

const mesActual = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`; };
const restarMes = (iso, n) => { const [y, m] = iso.split('-').map(Number); const t = y * 12 + (m - 1) - n; return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}-01`; };

export default function ComprasLocales() {
  const { empresaId, empresa, puede } = useApp();
  const [todas, setTodas] = useState(false);
  const [meses, setMeses] = useState(3);
  const [sel, setSel] = useState(null);
  const [periodo, setPeriodo] = useState(mesActual());
  const [editar, setEditar] = useState(null);
  const [ver, setVer] = useState(0);
  const ct = useCarga(() => sel ? q(sb().from('contratos').select('id, empresa_id, numero, modalidad, meta_compras_locales_pct, meta_compras_locales_extra_pct, base_compras_locales, rubro_alimentos_pct, zona_compras_locales, valor_racion_ref, fuente_parametros_cl, entidades_contratantes(nombre)').eq('id', sel.contrato_id).maybeSingle()) : Promise.resolve(null), [sel?.contrato_id, ver]);
  const c = ct.datos ? { ...ct.datos, empresa: sel?.empresa, entidad: ct.datos.entidades_contratantes?.nombre } : null;
  return (
    <>
      <Encabezado titulo="Compras publicas locales (Ley 2046)" sub={`Cumplimiento por contrato: mes en curso y anteriores · ${todas ? 'todas mis empresas' : (empresa?.nombre_corto || '')}`}>
        <div className="row gap8">
          <label className="row gap4 small"><input type="checkbox" checked={todas} onChange={(e) => setTodas(e.target.checked)} /> Todas mis empresas</label>
          <select value={meses} onChange={(e) => setMeses(Number(e.target.value))}>{[3, 6, 12].map((n) => <option key={n} value={n}>{n} meses</option>)}</select>
        </div>
      </Encabezado>
      <Consejo>
        La meta de cada contrato es el 30 % de ley mas lo que la UT ofrecio de mas en la licitacion. Se mide sobre el facturado del mes
        por el % del rubro de alimentos de la racion (por ejemplo USPEC: alimentos 72 a 74 % segun el grupo), salvo que el contrato diga
        "sobre el valor total facturado" (asi lo exige la Gobernacion del Atlantico). Cuentan las OC a proveedores marcados como Ley 2046
        y los soportes que cargue o importe del formato oficial. Toque un contrato para ver sus soportes y sus parametros.
      </Consejo>
      <div className="card mb16">
        <ResumenComprasLocales empresaId={todas ? null : empresaId} meses={meses} ver={ver} onElegir={(g) => { setSel(g); setPeriodo(g.meses ? Object.keys(g.meses).sort().reverse()[0] : mesActual()); }} />
      </div>
      {sel && (
        <>
          {ct.err && <Falla msg={ct.err} />}
          <div className="card">
            <div className="row between wrap gap8">
              <h2>{sel.numero} · {sel.empresa}</h2>
              <div className="row gap8">
                <select value={periodo} onChange={(e) => setPeriodo(e.target.value)}>
                  {Array.from({ length: 12 }, (_, i) => restarMes(mesActual(), i)).map((p) => <option key={p} value={p}>{nombreMes(p)}</option>)}
                </select>
                {c && puede('M1', 'crear') && <button className="btn" onClick={() => setEditar(c)}>Parametros del contrato</button>}
              </div>
            </div>
            {c && <p className="small muted">{c.fuente_parametros_cl || 'Sin fuente registrada para los parametros.'}</p>}
          </div>
          {c && <SoportesCL contrato={c} periodo={periodo} puedeEditar={puede('M3', 'crear')} onCambio={() => setVer((v) => v + 1)} />}
        </>
      )}
      {editar && <ParametrosCL contrato={editar} onCerrar={() => setEditar(null)} onGuardado={() => setVer((v) => v + 1)} />}
    </>
  );
}
