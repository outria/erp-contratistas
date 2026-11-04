// Lectura y escritura de la plantilla Excel de cobertura (cupos y dietas). Sin dependencia de React.
// Reconoce las hojas de la plantilla de recoleccion y tambien un Excel cualquiera con encabezados parecidos.
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

// que columna juega que papel, por el texto del encabezado
const PAPELES = [
  ['sede', /^(sede|establecimiento|institucion|colegio|ie\b|unidad|carcel|centro|nombre)/],
  ['sede2', /^sede educativa/],
  ['municipio', /^(municipio|ciudad)/],
  ['grupo', /^(grupo|sexo|rango|edad)/],
  ['tiempo', /^(tiempo|modalidad|complemento|racion)/],
  ['variante', /^variante/],
  ['dieta', /^dieta/],
  ['hombres', /^(hombres|h\b|masculino)/],
  ['mujeres', /^(mujeres|m\b|femenino)/],
  ['cantidad', /^(cantidad|estudiantes|cupos|cobertura|total|ppl|poblacion|beneficiarios|focalizad)/],
  ['desde', /^(fecha|desde|vigencia|rige)/],
];

export function detectarColumnas(encabezados) {
  const cols = {};
  encabezados.forEach((h, i) => {
    const n = norm(h); if (!n) return;
    for (const [papel, re] of PAPELES) {
      if (re.test(n) && cols[papel] == null) {
        // "sede educativa" es sede2, no sede; "total ppl" es cantidad aunque empiece por total
        if (papel === 'sede' && /^sede educativa/.test(n)) continue;
        cols[papel] = i; break;
      }
    }
  });
  return cols;
}

const fechaCelda = (v) => {
  if (v == null || v === '') return null;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const s = String(v).trim();
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/); if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  m = s.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})/); if (m) return `${m[3].length === 2 ? '20' + m[3] : m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  if (typeof v === 'number' && v > 30000 && v < 80000) { const d = new Date(Math.round((v - 25569) * 86400 * 1000)); return d.toISOString().slice(0, 10); }
  return null;
};

// Convierte una hoja (matriz de filas) en filas para importar_poblacion. tipo: 'cupos' | 'dietas'
export function filasDesdeHoja(matriz, tipo) {
  // la fila de encabezados es la primera con 3 o mas celdas de texto que casen con algun papel
  let iEnc = -1, cols = {};
  for (let i = 0; i < Math.min(matriz.length, 15); i++) {
    const c = detectarColumnas(matriz[i] ?? []);
    if (Object.keys(c).length >= 3) { iEnc = i; cols = c; break; }
  }
  if (iEnc < 0) return { error: 'No encontre la fila de encabezados (sede, grupo, cantidad…).', filas: [] };
  if (cols.sede == null) return { error: 'Falta una columna de sede / establecimiento / institucion.', filas: [] };
  if (tipo === 'dietas' && cols.dieta == null) return { error: 'Falta la columna de dieta.', filas: [] };
  const filas = [];
  for (let i = iEnc + 1; i < matriz.length; i++) {
    const r = matriz[i] ?? []; const sedeRaw = r[cols.sede];
    if (sedeRaw == null || String(sedeRaw).trim() === '') continue;
    if (r.some((v) => typeof v === 'string' && /^ejemplo/i.test(v.trim()))) continue;   // fila de ejemplo de la plantilla
    const sedeEd = cols.sede2 != null && r[cols.sede2] && !/principal/i.test(String(r[cols.sede2])) ? ` - ${String(r[cols.sede2]).trim()}` : '';
    const mun = cols.municipio != null && r[cols.municipio] ? String(r[cols.municipio]).trim() : '';
    const sede = String(sedeRaw).trim() + sedeEd;
    const base = { fila: i + 1, sede: mun && !sede.includes('(') ? `${sede} (${mun})` : sede, sede_alt: sede, municipio: mun || null,
      tiempo: cols.tiempo != null ? r[cols.tiempo] ?? null : null, variante: cols.variante != null ? r[cols.variante] ?? null : null,
      dieta: cols.dieta != null ? r[cols.dieta] ?? null : null, desde: cols.desde != null ? fechaCelda(r[cols.desde]) : null };
    if (cols.hombres != null || cols.mujeres != null) {
      // formato USPEC: una fila por establecimiento con hombres y mujeres
      if (cols.hombres != null && r[cols.hombres] !== '' && r[cols.hombres] != null) filas.push({ ...base, grupo: 'H', cantidad: r[cols.hombres] });
      if (cols.mujeres != null && r[cols.mujeres] !== '' && r[cols.mujeres] != null) filas.push({ ...base, grupo: 'M', cantidad: r[cols.mujeres] });
      if (cols.hombres == null && cols.mujeres == null && cols.cantidad != null) filas.push({ ...base, grupo: null, cantidad: r[cols.cantidad] });
    } else {
      filas.push({ ...base, grupo: cols.grupo != null ? r[cols.grupo] ?? null : null, cantidad: cols.cantidad != null ? r[cols.cantidad] : null });
    }
  }
  return { error: null, filas, columnas: cols, encabezados: matriz[iEnc] };
}

// Elige la hoja segun el tipo y la modalidad; devuelve el nombre
export function elegirHoja(nombres, tipo, modalidad) {
  const n = nombres.map(norm);
  const buscar = (re) => { const i = n.findIndex((x) => re.test(x)); return i >= 0 ? nombres[i] : null; };
  if (tipo === 'dietas') return buscar(/dieta/) ?? nombres[0];
  if (modalidad === 'pae') return buscar(/pae|focaliz/) ?? buscar(/cupo/) ?? nombres[0];
  if (modalidad === 'uspec_ppl') return buscar(/uspec cupos|ppl|cupos/) ?? nombres[0];
  return buscar(/casino|otros|cobertura/) ?? buscar(/cupo/) ?? nombres[0];
}

// Arma las hojas para descargar lo vigente en el formato de la plantilla
export function hojasExportacion(datos, unidad) {
  const g = (id) => datos.grupos.find((x) => x.id === id);
  const t = (id) => datos.tiempos.find((x) => x.id === id);
  const d = (id) => datos.dietas.find((x) => x.id === id);
  const modalidad = datos.contrato.modalidad;
  const cupos = [];
  if (modalidad === 'uspec_ppl') {
    cupos.push(['Contrato', 'Establecimiento', 'Variante (ERON/EP)', 'Fecha desde', 'Total PPL', 'Hombres', 'Mujeres', 'Fuente']);
    for (const s of datos.sedes) {
      const h = (s.cupos ?? []).filter((c) => g(c.grupo_id)?.codigo === 'H').reduce((a, c) => a + c.cantidad, 0);
      const m = (s.cupos ?? []).filter((c) => g(c.grupo_id)?.codigo === 'M').reduce((a, c) => a + c.cantidad, 0);
      cupos.push([datos.contrato.numero, s.nombre, datos.variantes.find((v) => v.id === s.variante_id)?.codigo === 'EP' ? 'EP' : 'ERON', s.cupos?.[0]?.desde ?? '', h + m, h, m, s.cupos?.[0]?.fuente ?? '']);
    }
  } else {
    cupos.push(['Contrato', 'Municipio', 'Institucion educativa / sede', 'Modalidad', 'Grupo', 'Cantidad (' + unidad + ')', 'Fecha desde', 'Fuente']);
    for (const s of datos.sedes) for (const c of s.cupos ?? []) cupos.push([datos.contrato.numero, s.ciudad ?? '', s.nombre, t(c.tiempo_id)?.codigo ?? '', g(c.grupo_id)?.nombre ?? '', c.cantidad, c.desde, c.fuente ?? '']);
  }
  const dietas = [['Contrato', 'Establecimiento', 'Dieta', 'Sexo / grupo', 'Fecha desde', 'Cantidad', 'Fuente']];
  for (const s of datos.sedes) for (const x of s.dietas ?? []) dietas.push([datos.contrato.numero, s.nombre, d(x.dieta_id)?.nombre ?? '', g(x.grupo_id)?.codigo ?? '', x.desde, x.cantidad, x.fuente ?? '']);
  return { cupos, dietas };
}
