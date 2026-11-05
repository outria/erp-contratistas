// Calculo de una explosion por tramos desde el navegador: el tamano del tramo sale de un presupuesto de sede-dias por llamada
// (USPEC con 4 tiempos y dietas pesa mas que PAE); si una llamada se pasa del limite de Supabase se parte a la mitad y se reintenta.
import { sb, q } from '@/lib/supabase';
import { fechaISO, desdeISO } from '@/lib/fmt';

export const sumarDias = (iso, n) => { const d = desdeISO(iso); d.setDate(d.getDate() + n); return fechaISO(d); };
export const diasEntre = (a, b) => Math.round((desdeISO(b) - desdeISO(a)) / 86400000) + 1;

// onProgreso({ hechos, total, hasta, tramos }) se llama al terminar cada tramo. Lanza si un tramo falla por algo distinto al tiempo.
export async function calcularPorTramos(expId, desde, hasta, nSedes, onProgreso, presupuesto = 160) {
  let porTramo = Math.max(1, Math.min(30, Math.floor(presupuesto / Math.max(1, nSedes))));
  const total = diasEntre(desde, hasta);
  let d = desde, hechos = 0, n = 0;
  while (d <= hasta) {
    const fin = sumarDias(d, porTramo - 1) < hasta ? sumarDias(d, porTramo - 1) : hasta;
    try {
      await q(sb().rpc('calcular_explosion', { p_explosion: expId, p_desde: d, p_hasta: fin, p_sedes: null }));
    } catch (e) {
      if (porTramo > 1 && /tard|timeout|statement/i.test(e.message)) { porTramo = Math.max(1, Math.floor(porTramo / 2)); continue; }
      throw e;
    }
    hechos += diasEntre(d, fin); n += 1;
    onProgreso?.({ hechos, total, hasta: fin, tramos: n });
    d = sumarDias(fin, 1);
  }
  return { hechos, total, tramos: n };
}
