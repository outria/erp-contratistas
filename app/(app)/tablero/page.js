'use client';
// Tablero de inicio (F0). En F1 se convierte en el tablero de menus de la semana con costo por
// componente y por racion; por ahora muestra el estado de los contratos y la ruta del proyecto.
import Link from 'next/link';
import { useApp, useCarga } from '@/lib/ctx';
import { sb, q } from '@/lib/supabase';
import { Encabezado, Kpi, Cargando, Falla, Consejo } from '@/components/ui';
import { cop, num, fechaCorta } from '@/lib/fmt';
import { ResumenComprasLocales } from '@/components/compras-locales';

const FASES = [
  { f: 'F0', t: 'Cimientos: empresas, usuarios, roles, adjuntos', estado: 'en_curso' },
  { f: 'F1', t: 'Contratos, minutas, cupos y explosion de materiales', estado: 'pendiente' },
  { f: 'F2', t: 'Compras, portal de proveedores y seguimiento de OC', estado: 'pendiente' },
  { f: 'F3', t: 'Bodega (lotes, PEPS) y traslados a sedes', estado: 'pendiente' },
  { f: 'F4', t: 'Operacion en sede, calidad e interventoria', estado: 'pendiente' },
  { f: 'F5', t: 'Facturacion a la entidad y pagos a proveedores', estado: 'pendiente' },
  { f: 'F6', t: 'Talento humano, IA del buzon y tableros', estado: 'pendiente' },
];

export default function Tablero() {
  const { empresaId, empresa, puede } = useApp();
  const d = useCarga(() => puede('M1') ? q(sb().from('v_contratos_resumen').select('*').eq('empresa_id', empresaId).neq('estado', 'anulado').order('fecha_fin_vigente')) : Promise.resolve([]), [empresaId]);
  const cs = d.datos ?? [];
  const vigentes = cs.filter((c) => c.estado === 'vigente');
  const total = vigentes.reduce((a, c) => a + Number(c.valor_total), 0);
  const fact = vigentes.reduce((a, c) => a + Number(c.facturado), 0);
  return (
    <>
      <Encabezado titulo={`Tablero · ${empresa?.nombre_corto || empresa?.razon_social || ''}`} sub="Lo que hay que mirar hoy. Cuando lleguen minutas y precios, aqui se veran los menus de la semana con su costo por componente y por racion." />
      <Consejo abierto>
        Esta es la version de cimientos (F0). Ya funciona: empresas independientes, usuarios y roles por modulo, contratos con adiciones y agotamiento presupuestal, y adjuntos en cada registro.
        Lo que aparece apagado en el menu llega en las fases siguientes.
      </Consejo>
      {d.err && <Falla msg={d.err} />}
      {puede('M1') && (d.cargando && !d.datos ? <Cargando /> : (
        <div className="grid g4 mb20">
          <Kpi v={vigentes.length} l="contratos vigentes" />
          <Kpi v={cop(total)} l="valor total contratado (con adiciones)" />
          <Kpi v={total ? `${num(fact / total * 100, 1)} %` : '·'} l="agotamiento presupuestal" />
          <Kpi v={vigentes.reduce((a, c) => a + Number(c.cupos_referencia), 0)} l="cupos de referencia" />
        </div>
      ))}
      {puede('M1') && cs.length > 0 && (
        <div className="card mb20">
          <h2>Contratos</h2>
          <table className="t">
            <thead><tr><th>Contrato</th><th>Entidad</th><th>Modalidad</th><th className="n">Valor total</th><th className="n">Agotado</th><th>Fin vigente</th><th className="n">Dias</th></tr></thead>
            <tbody>{cs.map((c) => (
              <tr key={c.id}>
                <td><Link href={`/contratos/${c.id}`}><b>{c.numero}</b></Link><div className="small muted">{c.codigo}</div></td>
                <td>{c.entidad_nombre}</td>
                <td className="small">{c.modalidad}</td>
                <td className="n">{cop(c.valor_total)}</td>
                <td className="n">{c.agotamiento_pct == null ? '·' : `${num(c.agotamiento_pct, 1)} %`}</td>
                <td>{fechaCorta(c.fecha_fin_vigente)}</td>
                <td className="n">{c.dias_restantes}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
      )}
      {(puede('M3') || puede('M1')) && (
        <div className="card mb20">
          <div className="row between"><h2>Compras publicas locales (Ley 2046)</h2><Link href="/compras-locales" className="small">Ver detalle</Link></div>
          <ResumenComprasLocales empresaId={empresaId} meses={3} compacto />
        </div>
      )}
      <div className="card">
        <h2>Ruta del proyecto</h2>
        <table className="t">
          <tbody>{FASES.map((x) => (
            <tr key={x.f}><td style={{ width: 50 }}><b>{x.f}</b></td><td>{x.t}</td><td style={{ width: 120 }}><span className={`chip ${x.estado === 'en_curso' ? 'warn' : ''}`}>{x.estado === 'en_curso' ? 'en curso' : 'pendiente'}</span></td></tr>
          ))}</tbody>
        </table>
      </div>
    </>
  );
}
