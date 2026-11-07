'use client';
// Lector del archivo "NECESIDAD DE COMPRA DE MATERIA PRIMA" que envia Planeacion (C0xx por programa).
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toUpperCase();
const num = (v) => {
  if (v == null || v === '') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const t = String(v).trim();
  if (!t || t.startsWith('#')) return null;
  const n = Number(t.replace(/\./g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : (Number.isFinite(Number(t)) ? Number(t) : null);
};
export const fechaXls = (v) => {
  if (v == null || v === '') return null;
  if (v instanceof Date && !isNaN(v)) return v.toISOString().slice(0, 10);
  if (typeof v === 'string' && /^\d{5}$/.test(v.trim())) v = Number(v);
  if (typeof v === 'number' && v > 30000 && v < 80000) return new Date(Math.round((v - 25569) * 86400000)).toISOString().slice(0, 10);
  const m = String(v).match(/(\d{1,2})[/-](\d{1,2})[/-](\d{4})/);
  return m ? `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null;
};
const fechasEn = (t) => [...String(t ?? '').matchAll(/(\d{1,2})\/(\d{1,2})\/(\d{4})/g)].map((m) => `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`);

// matriz = filas de la hoja principal (sheet_to_json header:1)
export function leerNecesidadCompra(matriz) {
  const filas = matriz.map((r) => (r || []).map((c) => (c == null ? null : c)));
  const buscar = (txt) => { for (const r of filas) { const j = r.findIndex((c) => norm(c).startsWith(txt)); if (j >= 0) return r.slice(j + 1).find((c) => c != null && String(c).trim() !== ''); } return null; };
  const iHead = filas.findIndex((r) => r.some((c) => norm(c).startsWith('DESCRIPCI')) && r.some((c) => norm(c) === 'CANTIDAD') && r.some((c) => norm(c).startsWith('CATEGOR')));
  if (iHead < 0) return { error: 'No encontre la fila de encabezados (DESCRIPCION, CANTIDAD, CATEGORIA).' };
  const h = filas[iHead].map(norm);
  const col = (pref, from = 0) => h.findIndex((x, k) => k >= from && x.startsWith(pref));
  const c = {
    entrega: col('FECHA DE ENTREGA'), dia: col('DIA A CONSUMIR'), desc: col('DESCRIPCI'), cant: col('CANTIDAD'), um: h.findIndex((x) => x === 'UM' || x.startsWith('UNIDAD')),
    cat: col('CATEGOR'), precio: col('PRECIO'), costo: col('COSTO'), desc_inv: col('DESCUENTO'),
    comprar: h.lastIndexOf('CANTIDAD A COMPRAR') >= 0 ? h.lastIndexOf('CANTIDAD A COMPRAR') : -1,
  };
  const lineas = []; let entrega = null; let dia = null; let catPrev = null;
  for (const r of filas.slice(iHead + 1)) {
    const d = c.desc >= 0 ? r[c.desc] : null;
    const primero = norm(r.find((x) => x != null && String(x).trim() !== ''));
    if (primero.startsWith('CICLO DE MENU') || primero.startsWith('OBSERVACI') || primero.startsWith('PLANEACION:')) break;
    if (c.entrega >= 0 && r[c.entrega] != null && String(r[c.entrega]).trim() !== '') entrega = fechaXls(r[c.entrega]) ?? entrega;
    if (c.dia >= 0 && r[c.dia] != null && String(r[c.dia]).trim() !== '') dia = String(typeof r[c.dia] === 'number' ? fechaXls(r[c.dia]) : r[c.dia]).replace(/\s+/g, ' ').trim();
    if (!d || !String(d).trim()) continue;
    const cant = num(r[c.cant]);
    if (cant == null || cant <= 0) continue;
    const cat = c.cat >= 0 && r[c.cat] ? String(r[c.cat]).trim() : catPrev; catPrev = cat;
    const comprar = c.comprar >= 0 ? num(r[c.comprar]) : null;
    lineas.push({
      descripcion: String(d).trim().slice(0, 200), categoria: cat, unidad: c.um >= 0 && r[c.um] ? String(r[c.um]).trim() : null,
      fecha_entrega: entrega, dia_consumo: dia ? dia.slice(0, 60) : null, cantidad: cant,
      descuento_inventario: c.desc_inv >= 0 ? Math.max(num(r[c.desc_inv]) ?? 0, 0) : 0,
      cantidad_comprar: comprar != null && comprar > 0 ? comprar : null,
      precio_ref: c.precio >= 0 ? num(r[c.precio]) : null, costo: c.costo >= 0 ? num(r[c.costo]) : null,
    });
  }
  const ciclo = buscar('CICLO DE MENU');
  const obs = buscar('OBSERVACI');
  const fechas = fechasEn(ciclo);
  const todo = filas.slice(iHead + 1).map((r) => r.filter((x) => typeof x === 'string').join(' ')).join(' ');
  const cob = todo.match(/COBERTURA[^0-9]{0,30}([0-9][0-9.]*)/i);
  const totalRow = filas.find((r) => r.some((x) => norm(x) === 'COSTO TOTAL'));
  const costoTotal = totalRow ? num(totalRow[totalRow.findIndex((x) => norm(x) === 'COSTO TOTAL') + 1]) : null;
  return {
    documento: num(buscar('N° DOCUMENTO')) ?? num(buscar('N DOCUMENTO')) ?? num(buscar('NO DOCUMENTO')),
    union_temporal: buscar('UNION TEMPORAL'), bodega: buscar('BODEGA'), fecha_envio: fechaXls(buscar('FECHA DE ENVIO')),
    ciclo: ciclo ? String(ciclo).replace(/\s+/g, ' ').slice(0, 200) : null, observaciones: obs ? String(obs).replace(/\s+/g, ' ').slice(0, 1000) : null,
    consumo_desde: fechas[0] ?? null, consumo_hasta: fechas[fechas.length - 1] ?? null,
    cobertura: cob ? Number(cob[1].replace(/\./g, '')) : null, costo_total: costoTotal,
    categorias: [...new Set(lineas.map((l) => l.categoria).filter(Boolean))],
    lineas,
  };
}
