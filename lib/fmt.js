// Regla de decimales de la plataforma (v1.16): se guarda con precision y se muestra redondeado.
//   kg de masa y harina: 1 · insumos < 1 kg: gramos enteros · insumos >= 1 kg: kg con 2
//   % panadero: 2 · $ por gramo: 2 · totales COP: 0 · temperaturas: 1 · humedad y avance %: 0 · unidades: 0
// Los calculos internos nunca redondean; solo la vista.
export const num = (v, d = 0) =>
  v === null || v === undefined || v === '' || Number.isNaN(Number(v))
    ? '·'
    : Number(v).toLocaleString('es-CO', { minimumFractionDigits: d, maximumFractionDigits: d });

export const cop = (v) => (v === null || v === undefined ? '·' : '$ ' + num(v, 0));

export const BULTO_KG = 50;
export const bultos = (kg) => (kg === null || kg === undefined ? null : Number(kg) / BULTO_KG);

const DIAS = ['dom', 'lun', 'mar', 'mie', 'jue', 'vie', 'sab'];
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export function fechaISO(d) {
  const x = new Date(d);
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
}
export function desdeISO(s) {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d);
}
export function fechaCorta(s) {
  if (!s) return '·';
  const d = desdeISO(s);
  return `${DIAS[d.getDay()]} ${d.getDate()} ${MESES[d.getMonth()]}`;
}
export function hoyISO() {
  return fechaISO(new Date());
}
export function lunesDe(s) {
  const d = desdeISO(s);
  const dia = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - dia);
  return fechaISO(d);
}
export function sumarDias(s, n) {
  const d = desdeISO(s);
  d.setDate(d.getDate() + n);
  return fechaISO(d);
}
export function horaCorta(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit' });
}

export function descargarCSV(nombre, filas) {
  if (!filas.length) return;
  const cols = Object.keys(filas[0]);
  const esc = (v) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[";\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const txt = '﻿' + [cols.join(';'), ...filas.map((f) => cols.map((c) => esc(f[c])).join(';'))].join('\n');
  const url = URL.createObjectURL(new Blob([txt], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre;
  a.click();
  URL.revokeObjectURL(url);
}
