-- Ración360 · Migracion 032 · Datos reales de UT Atlantic y UT Nutrifood (modo practica) y primeros requerimientos
-- Fuentes:
--  * Propuesta UT Atlantic (zip compartido por Juridica, 6-nov-2026): LP-0004-2026, ofrecimiento economico por grupo,
--    "PUNTAJE ADICIONAL COMPRAS LOCALES" grupos 1 y 2: +1 % (meta 31 %). Presupuesto oficial 74 dias: G1 $15.458.351.756,
--    G2 $16.905.297.734. Rubro de alimentos en el ofrecimiento: ~59 % ponderado (almuerzo en sitio 57 a 67 %, transportado
--    51 a 61 %, complemento ~44 %); informativo, porque el contrato mide sobre el facturado total.
--  * UT Nutrifood (correo de Karen Benedetti, 3-nov-2026, y clausulado): contrato 202604177, LP-0011-2026 grupo 1,
--    $20.018.163.982, 41 dias escolares o hasta agotar, vigente a 31-dic-2026, adjudicacion 29-sep-2026, cobertura
--    78.074 raciones/dia ($488.247.902/dia), obligacion 48: 30 % del total facturado mensual + 1 % ofrecido.
--  * Requerimientos C050 (Cenit, 6-nov-2026) y C028 zona 1 (Nutrifood, 20-oct-2026) del correo de Planeacion.
set client_min_messages = warning;

do $$
declare v_z1 uuid; v_z2 uuid; v_nf uuid; v_cen uuid; v_ecen uuid; v_enf uuid;
begin
  -- UT Atlantic zona 1 = grupo 1, zona 2 = grupo 2
  update public.contratos
     set valor_inicial = 15458351756, meta_compras_locales_extra_pct = 1, rubro_alimentos_pct = 59,
         fecha_suscripcion = least(fecha_suscripcion, '2026-03-20'), fecha_inicio = '2026-04-06',
         notas = coalesce(notas, '') || ' | Grupo 1: almuerzo en sitio 10.701, transportado 8.632, complemento 814, industrializada 555 cupos/dia; 74 dias escolares.',
         fuente_parametros_cl = 'Propuesta UT Atlantic LP-0004-2026: +1 % compras locales (meta 31 %) sobre el facturado total (obligacion 48). Rubro alimentos ~59 % (informativo). Fecha de inicio aproximada.'
   where numero = '202602581' and coalesce(fuente_parametros_cl, '') not like 'Propuesta UT Atlantic%'
   returning id into v_z1;
  update public.contratos
     set valor_inicial = 16905297734, meta_compras_locales_extra_pct = 1, rubro_alimentos_pct = 59,
         fecha_suscripcion = least(fecha_suscripcion, '2026-03-20'), fecha_inicio = '2026-04-06',
         notas = coalesce(notas, '') || ' | Grupo 2: almuerzo en sitio 13.076, transportado 7.201, complemento 1.494, industrializada 819 cupos/dia; 74 dias escolares.',
         fuente_parametros_cl = 'Propuesta UT Atlantic LP-0004-2026: +1 % compras locales (meta 31 %) sobre el facturado total (obligacion 48). Rubro alimentos ~59 % (informativo). Fecha de inicio aproximada.'
   where numero = '202602582' and coalesce(fuente_parametros_cl, '') not like 'Propuesta UT Atlantic%'
   returning id into v_z2;

  -- UT Nutrifood
  update public.contratos
     set valor_inicial = 20018163982, meta_compras_locales_extra_pct = 1, base_compras_locales = 'facturado_total', rubro_alimentos_pct = 59,
         proceso_secop = 'LP-0011-2026', fecha_suscripcion = '2026-10-01', fecha_inicio = '2026-10-19', fecha_fin_inicial = '2026-12-31',
         objeto = 'Complemento alimentario PAE en los 20 municipios no certificados del Atlantico, grupo 1 (zonas 1 y 2): 41 dias escolares o hasta agotar',
         notas = coalesce(notas, '') || ' | Cobertura diaria 78.074 raciones (36.910 industrializadas, 23.916 almuerzos en sitio, 13.284 complementos en sitio, 3.964 almuerzos transportados); $488.247.902/dia. Planeacion RPS: zona 1 16.409, zona 2 24.742. Pago a 90 dias. Interventoria Consorcio AS Atlantico 2026. Integrantes: Fombisol 46 %, Corporacion Agrosocial 45 %, Asociacion ADISP 9 %. NIT real 902.116.853-7.',
         fuente_parametros_cl = 'Clausulado 202604177, obligacion 48: 30 % del total facturado mensual + 1 % ofrecido; zona costa + Cundinamarca y Santanderes. Fechas de suscripcion e inicio aproximadas (adjudicado 29-sep-2026).'
   where numero = '202604177' and coalesce(fuente_parametros_cl, '') not like 'Clausulado 202604177%'
   returning id into v_nf;
end $$;

-- Requerimientos reales (solo si aun no estan)
do $$
declare v_ct uuid; v_emp uuid;
begin
  select id, empresa_id into v_ct, v_emp from public.contratos where numero = '003-C23-1600-2026' limit 1;
  if v_ct is not null and not exists (select 1 from public.requerimientos_planeacion where contrato_id = v_ct and codigo = 'C050') then
    perform public.importar_requerimiento(jsonb_build_object(
      'empresa_id', v_emp, 'contrato_id', v_ct, 'codigo', 'C050', 'tipo', 'planificada', 'origen', 'correo',
      'categorias', jsonb_build_array('fruver', 'lacteos', 'panaderia'), 'consumo_desde', '2026-11-23', 'consumo_hasta', '2026-11-27',
      'fecha_envio', '2026-11-06', 'fecha_entrega', '2026-11-20', 'bodega', 'Cienaga', 'ciclo', 'Ciclo 3 semana 2, menus 11 a 15', 'modalidad', 'RI',
      'cobertura', 17106, 'analista', 'Jesus Martinez (Planeacion)', 'archivo', 'C050 NECESIDAD DE COMPRA CICLO 4 SEMANA 3 CIENAGA RI.xlsx',
      'observaciones', 'Frutas de mano en las fechas estipuladas a las 7 a. m.; si sale de Granabastos avisar a logistica y transporte.',
      'costo_total', 185257782,
      'lineas', jsonb_build_array(
        jsonb_build_object('descripcion', 'Naranja (unidad) X120gr', 'categoria', 'FRUVER', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-23', 'dia_consumo', '24/11/2026', 'cantidad', 34212, 'precio_ref', 450, 'costo', 7697700),
        jsonb_build_object('descripcion', 'Banano (unidad) X120gr', 'categoria', 'FRUVER', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-24', 'dia_consumo', '25/11/2026', 'cantidad', 17106, 'precio_ref', 420, 'costo', 7184520),
        jsonb_build_object('descripcion', 'Naranja (unidad) X120gr', 'categoria', 'FRUVER', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-25', 'dia_consumo', '26/11/2026', 'cantidad', 34212, 'precio_ref', 450, 'costo', 7697700),
        jsonb_build_object('descripcion', 'Leche saborizada Fresa X200cc', 'categoria', 'LACTEOS', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 17100, 'cantidad_comprar', 17100, 'precio_ref', 840, 'costo', 14364000),
        jsonb_build_object('descripcion', 'Leche saborizada Arequipe X200cc', 'categoria', 'LACTEOS', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 17100, 'cantidad_comprar', 17100, 'precio_ref', 840, 'costo', 14364000),
        jsonb_build_object('descripcion', 'Avena X200cc', 'categoria', 'LACTEOS', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 17100, 'precio_ref', 840, 'costo', 14364000),
        jsonb_build_object('descripcion', 'Leche Entera x200cc', 'categoria', 'LACTEOS', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 17100, 'precio_ref', 840, 'costo', 14364000),
        jsonb_build_object('descripcion', 'Leche saborizada Vainilla X200cc', 'categoria', 'LACTEOS', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 17100, 'precio_ref', 840, 'costo', 14364000),
        jsonb_build_object('descripcion', 'Galleta cuca X60gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8346, 'precio_ref', 723, 'costo', 6034158),
        jsonb_build_object('descripcion', 'Galleta cuca X95gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8760, 'precio_ref', 1136, 'costo', 9951360),
        jsonb_build_object('descripcion', 'Galleta de coco X60gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8346, 'precio_ref', 723, 'costo', 6034158),
        jsonb_build_object('descripcion', 'Galleta de coco X95gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8760, 'precio_ref', 1136, 'costo', 9951360),
        jsonb_build_object('descripcion', 'Pan largo x60gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8346, 'precio_ref', 663, 'costo', 5533398),
        jsonb_build_object('descripcion', 'Pan largo x95gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8760, 'precio_ref', 1041, 'costo', 9119160),
        jsonb_build_object('descripcion', 'Pan uva x60gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8346, 'precio_ref', 663, 'costo', 5533398),
        jsonb_build_object('descripcion', 'Pan uva x95gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8760, 'precio_ref', 1041, 'costo', 9119160),
        jsonb_build_object('descripcion', 'Torta de chocolate x60gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8346, 'precio_ref', 1335, 'costo', 11141910),
        jsonb_build_object('descripcion', 'Torta de chocolate x95gr', 'categoria', 'PANADERIA', 'unidad', 'UNIDAD', 'fecha_entrega', '2026-11-20', 'dia_consumo', '23 al 27/11/2026', 'cantidad', 8760, 'precio_ref', 2105, 'costo', 18439800)
      )));
  end if;

  select id, empresa_id into v_ct, v_emp from public.contratos where numero = '202604177' limit 1;
  if v_ct is not null and not exists (select 1 from public.requerimientos_planeacion where contrato_id = v_ct and codigo = 'C028') then
    perform public.importar_requerimiento(jsonb_build_object(
      'empresa_id', v_emp, 'contrato_id', v_ct, 'codigo', 'C028', 'tipo', 'planificada', 'origen', 'correo',
      'categorias', jsonb_build_array('proteinas'), 'consumo_desde', '2026-11-06', 'consumo_hasta', '2026-11-12',
      'fecha_envio', '2026-10-20', 'fecha_entrega', '2026-11-03', 'bodega', 'Calle 30 (zona 1)', 'ciclo', 'Ciclo 2 semana 2, menus 10 a 14', 'modalidad', 'RPS',
      'cobertura', 16409, 'analista', 'Dubbys Fonseca (Planeacion)', 'archivo', 'C028 - PLANEACION PROTEINAS DEL 06-12 DE NOV (Zona 1).xlsx',
      'observaciones', 'Zona 1: complemento 5.018, almuerzo 11.391. Despacho 5-nov; insumos en bodega el 4-nov para prealistamiento. Se descuenta inventario con corte al 19-oct (cerdo 453,6 kg, pechuga 403,2 kg). Ojo: el archivo trae cantidad 1.543 kg cerdo y 712 kg pechuga, pero la columna de valor matriz dice 1.938 y 2.849 y la cantidad a comprar 1.485 y 2.446; revisar con Planeacion.',
      'costo_total', 31388400,
      'lineas', jsonb_build_array(
        jsonb_build_object('descripcion', 'Carne de cerdo', 'categoria', 'PROTEINA', 'unidad', 'KILOGRAMOS', 'fecha_entrega', '2026-11-03', 'dia_consumo', '06 al 12/11/2026', 'cantidad', 1543, 'descuento_inventario', 453.6, 'cantidad_comprar', 1485, 'precio_ref', 12800, 'costo', 19750400),
        jsonb_build_object('descripcion', 'Cerdo porcionado x1kg', 'categoria', 'PROTEINA', 'unidad', 'KILOGRAMOS', 'fecha_entrega', '2026-11-03', 'dia_consumo', '06 al 12/11/2026', 'cantidad', 75, 'cantidad_comprar', 75, 'precio_ref', 23000, 'costo', 1725000),
        jsonb_build_object('descripcion', 'Cerdo porcionado x300gr', 'categoria', 'PROTEINA', 'unidad', 'KILOGRAMOS', 'fecha_entrega', '2026-11-03', 'dia_consumo', '06 al 12/11/2026', 'cantidad', 75, 'cantidad_comprar', 75, 'precio_ref', 23000, 'costo', 1725000),
        jsonb_build_object('descripcion', 'Pechuga', 'categoria', 'PROTEINA', 'unidad', 'KILOGRAMOS', 'fecha_entrega', '2026-11-03', 'dia_consumo', '06 al 12/11/2026', 'cantidad', 712, 'descuento_inventario', 403.2, 'cantidad_comprar', 2446, 'precio_ref', 11500, 'costo', 8188000)
      )));
  end if;
end $$;
