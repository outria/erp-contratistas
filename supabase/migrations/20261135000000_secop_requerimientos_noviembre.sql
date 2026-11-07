-- Ración360 · Migracion 035 · Datos de SECOP II en los contratos + requerimientos vigentes de noviembre (tanda 1)
-- 1) Con los datos abiertos de SECOP II (datos.gov.co, conjunto jbjy-vk9h, consulta del 6-nov-2026) se completan numero,
--    proceso, valor y fechas de los contratos que estaban "por confirmar". Solo se llenan campos vacios; lo demas queda en notas.
-- 2) Requerimientos de Planeacion vigentes (consumo 9 al 30 de noviembre) leidos de los adjuntos del correo:
--    PAE Soledad C071 (2da actualizacion), C070.1; CEI Soledad C027; PAE Malambo C0105; CEI Malambo C029; Cenit C050 RPS.
--    Los productos que no cruzan con el catalogo quedan creados como RQ-xxxxx pendientes de revision (lo hace importar_requerimiento).
set client_min_messages = warning;

-- ============ 1. SECOP ============
create or replace function pg_temp.secop(p_num_actual text, p_num text, p_proceso text, p_valor numeric, p_suscr date, p_ini date,
                                          p_fin date, p_nota text) returns void language plpgsql as $$
begin
  -- Los contratos de practica sembrados con valor 1 tienen fechas de relleno: ahi manda SECOP.
  update public.contratos c
     set numero = coalesce(p_num, c.numero),
         proceso_secop = case when c.valor_inicial <= 1 or nullif(c.proceso_secop, '') is null then coalesce(p_proceso, c.proceso_secop) else c.proceso_secop end,
         valor_inicial = case when c.valor_inicial is null or c.valor_inicial <= 1 then coalesce(p_valor, c.valor_inicial) else c.valor_inicial end,
         fecha_suscripcion = case when c.valor_inicial <= 1 or c.fecha_suscripcion is null then coalesce(p_suscr, c.fecha_suscripcion) else c.fecha_suscripcion end,
         fecha_inicio = case when c.valor_inicial <= 1 or c.fecha_inicio is null then coalesce(p_ini, c.fecha_inicio) else c.fecha_inicio end,
         fecha_fin_inicial = case when c.valor_inicial <= 1 or c.fecha_fin_inicial is null then coalesce(p_fin, c.fecha_fin_inicial) else c.fecha_fin_inicial end,
         notas = trim(both ' ' from coalesce(c.notas, '') || ' SECOP II (datos abiertos, 6-nov-2026): ' || p_nota)
   where c.numero = p_num_actual
     and coalesce(c.notas, '') not like '%SECOP II (datos abiertos, 6-nov-2026)%';
end $$;

select pg_temp.secop('PAE-SOLEDAD-2026 (por confirmar)', 'SG-LP-2026-C003', 'CO1.NTC.10276832', 97049306811.19, '2026-06-02', '2026-06-03', '2028-03-31',
  'Municipio de Soledad, UT Alianza Integral NIT 902072275, contrato CO1.PCCNTR.9542672, en ejecucion. Complementos y almuerzos PAE.');
select pg_temp.secop('003-C23-1600-2026', null, 'CO1.NTC.10216032', null, null, null, null,
  'Municipio de Cienaga, UT Cenit NIT 902081982, contrato CO1.PCCNTR.9604765, estado Modificado: valor actual $10.941.631.264 (incluye adicion) y fin registrado 9-nov-2026; confirmar prorroga.');
select pg_temp.secop('202604177', null, 'CO1.NTC.10862869', null, '2026-10-20', null, '2026-12-31',
  'Departamento del Atlantico, contrato CO1.PCCNTR.10017260, aprobado, valor $20.018.163.982, fin 31-dic-2026.');
select pg_temp.secop('202602581', null, 'CO1.NTC.10051804', null, '2026-03-20', '2026-03-27', null,
  'UT Atlantic NIT 902049253, contrato CO1.PCCNTR.9408256, estado Modificado: valor actual $23.187.527.634 (inicial + 50 %), fin 6-oct-2026.');
select pg_temp.secop('202602582', null, 'CO1.NTC.10051804', null, '2026-03-20', '2026-03-27', null,
  'UT Atlantic NIT 902049253, contrato CO1.PCCNTR.9408571, estado Modificado: valor actual $25.357.946.602 (inicial + 50 %), fin 6-oct-2026.');
select pg_temp.secop('ARC-COVENAS-2026 (por confirmar)', '0013-ARC-ENSUB-DLENS-2026', 'CO1.NTC.10024999', 4683626800, '2026-03-05', '2026-03-05', '2026-12-15',
  'Entidad: Armada Nacional, Escuela Naval de Suboficiales ARC Barranquilla (no Covenas). Estado Modificado; el valor puede incluir adicion.');
select pg_temp.secop('SA-005-2026', null, 'CO1.NTC.10284328', 1300000000, '2026-06-05', '2026-06-16', '2026-12-31',
  'Distrito de Barranquilla, UT Brigadistas NIT 902073189, contrato CO1.PCCNTR.9548024, en ejecucion.');
select pg_temp.secop('SA-008-2026', null, 'CO1.NTC.10222347', 800000000, '2026-05-07', '2026-05-14', '2026-12-31',
  'Distrito de Barranquilla, UT Proposito Superior NIT 902063610, contrato CO1.PCCNTR.9493587, en ejecucion. Objeto: alimentos para personal de apoyo.');
select pg_temp.secop('LP-006-2026', null, 'CO1.BDOS.10072211', 15000000000, '2026-06-03', '2026-06-03', '2026-12-31',
  'Distrito de Barranquilla, UT CDR NIT 902072280, alimentacion personal recluido, en ejecucion. Inicio aproximado (= firma); confirmar acta.');
select pg_temp.secop('CAPITAL-USPEC-2025 (por confirmar)', 'USPEC-CTO-191-2025', 'CO1.BDOS.7485182', 66821809151, '2025-05-09', '2025-05-09', '2026-12-15',
  'USPEC, contrato CO1.PCCNTR.7834930, estado Modificado, valor actual $66.821.809.151 (incluye modificaciones).');
select pg_temp.secop('SCJ-1921-2026', null, 'CO1.BDOS.10438998', null, '2026-09-17', null, '2027-07-26',
  'Secretaria Distrital de Seguridad, Convivencia y Justicia, en ejecucion, valor $42.186.012.028.');

-- ============ 2. Requerimientos ============
-- Renglones en texto: una linea por producto "descripcion|CATEGORIA|UM|cantidad|precio[|cantidad_comprar]".
create or replace function pg_temp.rq(p_contrato text, p_codigo text, p_tipo text, p_cab jsonb, p_entrega date, p_dia text, p_lineas text)
returns void language plpgsql as $$
declare v_ct uuid; v_emp uuid; r text; f text[]; v_l jsonb := '[]'::jsonb;
begin
  select id, empresa_id into v_ct, v_emp from public.contratos where numero = p_contrato limit 1;
  if v_ct is null then raise notice 'Contrato % no existe; se omite %.', p_contrato, p_codigo; return; end if;
  if exists (select 1 from public.requerimientos_planeacion where contrato_id = v_ct and codigo = upper(p_codigo)
              and fecha_envio is not distinct from (p_cab->>'fecha_envio')::date) then return; end if;
  for r in select trim(x) from regexp_split_to_table(p_lineas, E'\n') x loop
    if r = '' then continue; end if;
    f := string_to_array(r, '|');
    v_l := v_l || jsonb_build_object('descripcion', f[1], 'categoria', f[2], 'unidad', f[3], 'fecha_entrega', p_entrega, 'dia_consumo', p_dia,
             'cantidad', f[4]::numeric, 'precio_ref', f[5]::numeric, 'costo', round(f[4]::numeric * f[5]::numeric),
             'cantidad_comprar', case when array_length(f, 1) >= 6 then f[6]::numeric end);
  end loop;
  perform public.importar_requerimiento(p_cab || jsonb_build_object('empresa_id', v_emp, 'contrato_id', v_ct, 'codigo', p_codigo,
           'tipo', p_tipo, 'origen', 'correo', 'fecha_entrega', p_entrega, 'lineas', v_l));
end $$;

-- PAE Soledad C071, segunda actualizacion (6-nov): reemplaza la del 5-nov
select pg_temp.rq('SG-LP-2026-C003', 'C071', 'actualizacion', jsonb_build_object(
  'categorias', jsonb_build_array('fruver', 'panaderia'), 'consumo_desde', '2026-11-12', 'consumo_hasta', '2026-11-18', 'fecha_envio', '2026-11-06',
  'bodega', 'Granabasto 4B', 'ciclo', 'Ciclo 3 semanas 3 y 4, menus 14-15-17-18 (x4 dias)', 'modalidad', 'RPS', 'cobertura', 51928,
  'analista', 'Ana Lucia Diaz (Planeacion)', 'archivo', 'C071 - UT ALIANZA INTEGRAL - CICLO 3 - SEMANA 3-4 - PLANEACION (FRUVER, PANADERIA) DEL 12 AL 18 NOVIEMBRE.xlsx',
  'costo_total', 71216740,
  'observaciones', 'Complemento 34.702 y almuerzo 17.226. Fruver para 51 IE publicas y 14 privadas; faltan 20 privadas para el 90 % de cobertura universal. Ajuste por inasistencias y cierre de calendario. Descuento de 31 kg de habichuela de aprovechamiento ($263.500). Despacho 10-nov. Revisar: la columna "cantidad a comprar" del archivo quedo con la version anterior; se toma la columna CANTIDAD.'),
  '2026-11-09', '12/11/2026 al 18/11/2026', $l$
Ajo|FRUVER|KILOGRAMOS|191|6100
Banano|FRUVER|KILOGRAMOS|418|2200
Cebolla blanca|FRUVER|KILOGRAMOS|874|3200
Cebollin|FRUVER|KILOGRAMOS|131|5500
Guayaba|FRUVER|KILOGRAMOS|2781|3300
Lechuga|FRUVER|KILOGRAMOS|206|4000
Melon|FRUVER|KILOGRAMOS|3269|3700
Papa|FRUVER|KILOGRAMOS|1508|2800
Pepino|FRUVER|KILOGRAMOS|336|2800
Pimenton verde|FRUVER|KILOGRAMOS|900|4700
Platano verde|FRUVER|KILOGRAMOS|3716|3300
Tomate|FRUVER|KILOGRAMOS|784|3700
Zanahoria|FRUVER|KILOGRAMOS|734|1900
Pan bola x50gr|PANADERIA|UNIDAD|32531|540
$l$);

-- PAE Soledad C070.1, queso para el Dia Especial de la Alimentacion
select pg_temp.rq('SG-LP-2026-C003', 'C070.1', 'adicional', jsonb_build_object(
  'categorias', jsonb_build_array('proteinas'), 'consumo_desde', '2026-11-11', 'consumo_hasta', '2026-11-11', 'fecha_envio', '2026-11-05',
  'bodega', 'Granabasto 4B', 'ciclo', 'Menu 01, evento Dia Especial de la Alimentacion', 'modalidad', 'RPS', 'cobertura', 52341,
  'analista', 'Ana Lucia Diaz (Planeacion)', 'archivo', 'C070.1 - UT ALIANZA INTEGRAL - PLANEACION (PROTEINA) DEL 09 NOVIEMBRE.xlsx', 'costo_total', 132000,
  'observaciones', 'Queso tajado para IE con cobertura menor a 20 ninos (segmentacion). Despacho 9-nov.'),
  '2026-11-09', '11/11/2026', $l$
Queso tajado x20Und|PROTEINA|PAQUETES|8|16500
$l$);

-- CEI Soledad C027 (contingencia: mango por mandarina/patilla)
select pg_temp.rq('SG-LP-2026-C003', 'CEI-C027', 'planificada', jsonb_build_object(
  'categorias', jsonb_build_array('fruver'), 'consumo_desde', '2026-11-10', 'consumo_hasta', '2026-11-17', 'fecha_envio', '2026-11-03',
  'bodega', 'Granabasto 4B', 'ciclo', 'CEI ciclo 2 semanas 1-2, menus 02-03-04-05-07 (x5 dias)', 'modalidad', 'RPS', 'cobertura', 398,
  'analista', 'Ana Lucia Diaz (Planeacion)', 'archivo', 'C027 - (CEI) UT ALIANZA INTEGRAL - CICLO 2 - SEMANA 1-2 - PLANEACION (FRUVER, PANADERIA) DEL 10 AL 17 NOVIEMBRE.xlsx',
  'costo_total', 2794850,
  'observaciones', 'Programa CEI (Centros de Educacion Inicial). Reemplazo de mango por mandarina/patilla por cosecha; confirmar disponibilidad de mandarina (minuta estricta). Mango con maduracion grado 4. Revisar: lechuga con descuento de 121 en el archivo deja cantidad negativa; se carga la cantidad de la matriz.'),
  '2026-11-07', '10/11/2026 al 17/11/2026', $l$
Ahuyama|FRUVER|KILOGRAMOS|12|3500
Ajo|FRUVER|KILOGRAMOS|7|6400
Apio|FRUVER|KILOGRAMOS|3|3500
Banano|FRUVER|KILOGRAMOS|51|2500
Cebolla blanca|FRUVER|KILOGRAMOS|13|4000
Cebollin|FRUVER|KILOGRAMOS|3|5300
Cilantro|FRUVER|KILOGRAMOS|3|12500
Guayaba|FRUVER|KILOGRAMOS|33|4000
Habichuela|FRUVER|KILOGRAMOS|7|9000
Lechuga|FRUVER|KILOGRAMOS|8|4000
Limon|FRUVER|KILOGRAMOS|6|3300
Mandarina|FRUVER|UNIDAD|199|750
Patilla (reemplaza mango)|FRUVER|KILOGRAMOS|65|3500
Manzana|FRUVER|UNIDAD|121|2100
Mazorca|FRUVER|KILOGRAMOS|5|3500
Melon|FRUVER|KILOGRAMOS|33|4900
Papa|FRUVER|KILOGRAMOS|29|2800
Papaya|FRUVER|KILOGRAMOS|30|3400
Patilla|FRUVER|KILOGRAMOS|66|3500
Pepino|FRUVER|KILOGRAMOS|23|3500
Pimenton verde|FRUVER|KILOGRAMOS|6|4700
Pina|FRUVER|KILOGRAMOS|98|4100
Platano maduro|FRUVER|KILOGRAMOS|35|3700
Tomate|FRUVER|KILOGRAMOS|41|4500
Yuca|FRUVER|KILOGRAMOS|42|3800
Zanahoria|FRUVER|KILOGRAMOS|5|1900
$l$);

-- PAE Malambo C0105, RI
select pg_temp.rq('PAE-MALAMBO-2026 (por confirmar)', 'C0105', 'planificada', jsonb_build_object(
  'categorias', jsonb_build_array('fruver', 'panaderia'), 'consumo_desde', '2026-11-24', 'consumo_hasta', '2026-11-30', 'fecha_envio', '2026-11-05',
  'bodega', 'Granabasto 4B', 'ciclo', 'Ciclo 4 semanas 1 y 2, menus 02-03-04-05-06 (x5 dias)', 'modalidad', 'RI', 'cobertura', 8513,
  'analista', 'Jesus Martinez Mejia (Planeacion)', 'archivo', 'C0105 - UT MALAMBO - CICLO 4 - SEMANA 1 y 2 - PLANEACION RI (FRUVER, PANADERIA) DEL 24 AL 30 DE NOVIEMBRE.xlsx',
  'costo_total', 41883960,
  'observaciones', 'Industrializada 8.513 ninos. Despacho 23-nov (el archivo dice lunes 17); producto disponible en la manana porque se despacha el mismo dia. Revisar: el archivo trae #N/A y #REF! en embalaje y la naranja (17.026 = 2 por nino) no concilia con la matriz (7.286).'),
  '2026-11-21', '24/11/2026 al 30/11/2026', $l$
Naranja (unidad) X120gr|FRUVER|UNIDAD|17026|500
Pan ocanero x70gr|PANADERIA|UNIDAD|8513|756
Galleta punto rojo x70gr|PANADERIA|UNIDAD|8513|826
Pan mantequilla x70gr|PANADERIA|UNIDAD|8513|756
Pan bola x70gr|PANADERIA|UNIDAD|8513|756
Galleta de chocolate x70gr|PANADERIA|UNIDAD|8513|826
$l$);

-- CEI Malambo C029
select pg_temp.rq('PAE-MALAMBO-2026 (por confirmar)', 'CEI-C029', 'planificada', jsonb_build_object(
  'categorias', jsonb_build_array('fruver'), 'consumo_desde', '2026-11-10', 'consumo_hasta', '2026-11-17', 'fecha_envio', '2026-11-03',
  'bodega', 'Granabasto 4B', 'ciclo', 'CEI ciclo 2 semanas 1-2, menus 02-03-04-05-07 (x5 dias)', 'modalidad', 'RPS', 'cobertura', 154,
  'analista', 'Ana Lucia Diaz (Planeacion)', 'archivo', 'C029 - (CEI) UT MALAMBO - CICLO 2 - SEMANA 1-2 - PLANEACION (FRUVER) DEL 10 AL 17 NOVIEMBRE.xlsx',
  'costo_total', 1006228,
  'observaciones', 'Programa CEI Malambo. Mango reemplazado por patilla/mandarina; confirmar mandarina. El archivo trae cantidades con decimales; se carga la cantidad redondeada que el mismo archivo propone.'),
  '2026-11-07', '10/11/2026 al 17/11/2026', $l$
Ahuyama|FRUVER|KILOGRAMOS|4|3500
Ajo|FRUVER|KILOGRAMOS|2|6400
Banano|FRUVER|KILOGRAMOS|15|2500
Cebolla blanca|FRUVER|KILOGRAMOS|3|4000
Cebollin|FRUVER|KILOGRAMOS|3|5300
Guayaba|FRUVER|KILOGRAMOS|8|4000
Habichuela|FRUVER|KILOGRAMOS|2|9000
Lechuga|FRUVER|KILOGRAMOS|3|4000
Limon|FRUVER|KILOGRAMOS|2|3300
Mandarina|FRUVER|UNIDAD|154|750
Patilla (reemplaza mango)|FRUVER|KILOGRAMOS|15|3500
Manzana|FRUVER|UNIDAD|62|2100
Mazorca|FRUVER|KILOGRAMOS|1|3500
Melon|FRUVER|KILOGRAMOS|12|4900
Papa|FRUVER|KILOGRAMOS|9|2800
Papaya|FRUVER|KILOGRAMOS|13|3400
Patilla|FRUVER|KILOGRAMOS|22|3500
Pepino|FRUVER|KILOGRAMOS|8|3500
Pina|FRUVER|KILOGRAMOS|35|4100
Platano maduro|FRUVER|KILOGRAMOS|11|3700
Tomate|FRUVER|KILOGRAMOS|15|4500
Yuca|FRUVER|KILOGRAMOS|15|3800
$l$);

-- Cenit C050 RPS (la C050 RI ya estaba cargada; esta es paralela)
select pg_temp.rq('003-C23-1600-2026', 'C050-RPS', 'planificada', jsonb_build_object(
  'categorias', jsonb_build_array('fruver', 'panaderia'), 'consumo_desde', '2026-11-23', 'consumo_hasta', '2026-11-27', 'fecha_envio', '2026-11-06',
  'bodega', 'Cienaga', 'ciclo', 'Ciclo 4 semana 3, menus 11-12-13-14-15 (x5 dias)', 'modalidad', 'RPS', 'cobertura', 1349,
  'analista', 'Jesus Martinez Mejia (Planeacion)', 'archivo', 'C050 NECESIDAD DE COMPRA CICLO 4 SEMANA 3 CIENAGA PREPARADOS.xlsx', 'costo_total', 6080685,
  'observaciones', 'Paralela a la C050 RI (no la reemplaza). Frutas de mano a las 7 a. m.; si sale de Granabasto avisar a logistica. Despacho 20-nov. Revisar: el tomate viene a $37.000/kg (seguramente $3.700) y hay una fila de 339 almuerzos sin producto.'),
  '2026-11-20', '23/11/2026 al 27/11/2026', $l$
Ajo|FRUVER|KILOGRAMOS|9|6400
Banano|FRUVER|KILOGRAMOS|62|2200
Cebolla blanca|FRUVER|KILOGRAMOS|50|3400
Cilantro|FRUVER|KILOGRAMOS|1|12500
Guayaba|FRUVER|KILOGRAMOS|90|3300
Guineo verde|FRUVER|KILOGRAMOS|47|2000
Lechuga|FRUVER|KILOGRAMOS|9|4000
Melon|FRUVER|KILOGRAMOS|38|3700
Mora|FRUVER|KILOGRAMOS|20|7500
Naranja (unidad) X120gr|FRUVER|UNIDAD|1349|450
Papa|FRUVER|KILOGRAMOS|179|2800
Pepino|FRUVER|KILOGRAMOS|9|3500
Pimenton verde|FRUVER|KILOGRAMOS|22|4700
Pina|FRUVER|KILOGRAMOS|112|3600
Platano verde|FRUVER|KILOGRAMOS|160|3300
Remolacha|FRUVER|KILOGRAMOS|9|2300
Repollo blanco|FRUVER|KILOGRAMOS|9|2900
Tomate|FRUVER|KILOGRAMOS|44|37000
Tomate de arbol|FRUVER|KILOGRAMOS|21|4300
Zanahoria|FRUVER|KILOGRAMOS|29|1800
Pan bola X60gr|PANADERIA|UNIDAD|744|663
Pan bola X95gr|PANADERIA|UNIDAD|266|1041
Pan largo x60gr|PANADERIA|UNIDAD|339|663
$l$);
