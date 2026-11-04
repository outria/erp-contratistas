// Catalogos de pantalla del dominio (nombres en palabras de la operacion)
export const MODALIDADES = {
  uspec_ppl: 'USPEC · personas privadas de la libertad', pae: 'PAE · alimentacion escolar', icbf_primera_infancia: 'ICBF · primera infancia',
  fuerzas_casino: 'Fuerzas · casinos', adulto_mayor: 'Adulto mayor', bomberos: 'Bomberos', otro: 'Otro',
};
export const TIPOS_ENTIDAD = { nacional: 'Entidad nacional', gobernacion: 'Gobernacion', alcaldia: 'Alcaldia', icbf: 'ICBF', uspec: 'USPEC', fuerzas: 'Fuerzas', otra: 'Otra' };
export const TIPOS_MODIFICACION = { adicion: 'Adicion en valor', prorroga: 'Prorroga en tiempo', adicion_prorroga: 'Adicion y prorroga', suspension: 'Suspension', reinicio: 'Reinicio', otrosi: 'Otrosi', cesion: 'Cesion', terminacion_anticipada: 'Terminacion anticipada' };
export const CATEGORIAS_DOC_CONTRATO = {
  contrato: 'Contrato firmado', anexo_nutricional: 'Anexo nutricional / minuta', anexo_calidad: 'Anexo de calidad', anexo_talento_humano: 'Anexo de talento humano',
  anexo_tecnico: 'Anexo tecnico', pliego: 'Pliego de condiciones', poliza: 'Polizas', acta_inicio: 'Acta de inicio', otrosi: 'Otrosi / adicion', oficio: 'Oficios y comunicados', otro: 'Otro',
};
export const TIPOS_SEDE = { cedi: 'CEDI / bodega principal', bodega: 'Bodega', oficina: 'Oficina', unidad_servicio: 'Unidad de servicio', planta: 'Planta' };
export const SUBTIPOS_SEDE = { eron: 'ERON (carcel)', colegio: 'Institucion educativa', cdi: 'CDI / hogar infantil', casino: 'Casino', estacion: 'Estacion', otro: 'Otro' };

// Planeacion: intercambios de menu y novedades de servicio
export const CLASES_INTERCAMBIO = { concertado: 'Concertado con la poblacion', temporada: 'Temporada (cosecha o escasez)', contingencia: 'Contingencia', especial: 'Menu especial' };
export const ESTADOS_INTERCAMBIO = { propuesto: 'Propuesto', concertado: 'Concertado', aprobado_entidad: 'Aprobado por la entidad', rechazado: 'Rechazado', anulado: 'Anulado' };
export const TIPOS_NOVEDAD = { sin_clases: 'No hay clases', paro: 'Paro', acto_civico: 'Acto civico', actividad: 'Actividad deportiva o extracurricular', clima: 'Clima (lluvias, inundacion)', orden_publico: 'Orden publico', salud_publica: 'Salud publica', otro: 'Otro' };
export const ACCIONES_NOVEDAD = { correr: 'Correr el menu', trasladar: 'Trasladar ese menu a otra fecha', perder: 'El menu se pierde (el ciclo sigue)' };
