-- =====================================================================
-- Supply ERP · Seed 002 · UT Diestra: estructura USPEC, productos y preparaciones del Anexo 4 (N-N009),
-- factores de coccion (N-N000), ciclos estandar ERON (N-N007) y EP (N-N008), minuta patron resumida (N-N001/002),
-- cupos de referencia del contrato y una explosion de prueba.
-- Generado desde el Excel oficial el 31-oct-2026. Las preparaciones genericas del ciclo (SOPA O CREMA, JUGO DE FRUTA,
-- POSTRE VARIEDAD...) quedan con una preparacion por defecto que planeacion debe variar segun las reglas de rotacion.
-- =====================================================================
do $seed$
declare e uuid; c uuid; v_est uuid; v_ep uuid; t_des uuid; t_alm uuid; t_cen uuid; t_ref uuid; g_h uuid; g_m uuid; cic uuid; cic_ep uuid; r record;
begin
  select id into e from public.empresas where nit = '901942965';
  select id into c from public.contratos where numero = 'USPEC-CTO-199-2025';
  insert into public.tiempos_comida (empresa_id, contrato_id, codigo, nombre, orden, hora_inicio, hora_fin, facturable, cambiable_especial) values
    (e, c, 'DES', 'Desayuno', 1, '06:00', '08:00', true, true),
    (e, c, 'ALM', 'Almuerzo', 2, '11:00', '13:30', true, true),
    (e, c, 'CEN', 'Cena', 3, '15:00', '17:00', true, true),
    (e, c, 'REF', 'Refrigerio nocturno', 4, '15:00', '17:30', true, false);
  select id into t_des from public.tiempos_comida where contrato_id = c and codigo = 'DES';
  select id into t_alm from public.tiempos_comida where contrato_id = c and codigo = 'ALM';
  select id into t_cen from public.tiempos_comida where contrato_id = c and codigo = 'CEN';
  select id into t_ref from public.tiempos_comida where contrato_id = c and codigo = 'REF';
  insert into public.grupos_poblacion (empresa_id, contrato_id, codigo, nombre, tipo, orden) values (e, c, 'H', 'Hombres', 'sexo', 1), (e, c, 'M', 'Mujeres', 'sexo', 2);
  select id into g_h from public.grupos_poblacion where contrato_id = c and codigo = 'H';
  select id into g_m from public.grupos_poblacion where contrato_id = c and codigo = 'M';
  insert into public.componentes (empresa_id, contrato_id, tiempo_comida_id, codigo, nombre, orden) values
    (e, c, t_des, 'FRUTA', 'Fruta entera', 1), (e, c, t_des, 'PROTEICO', 'Proteico', 2), (e, c, t_des, 'CEREAL', 'Derivado de cereal', 3), (e, c, t_des, 'BEBIDA', 'Bebida caliente o fria', 4),
    (e, c, t_alm, 'SOPA', 'Sopa', 1), (e, c, t_alm, 'PROTEICO', 'Proteico', 2), (e, c, t_alm, 'CEREAL', 'Cereal (arroz)', 3), (e, c, t_alm, 'VERDURA', 'Hortalizas y verduras', 4), (e, c, t_alm, 'TUBERCULO', 'Tuberculo, raiz o platano', 5), (e, c, t_alm, 'JUGO', 'Bebida de fruta', 6), (e, c, t_alm, 'POSTRE', 'Postre', 7),
    (e, c, t_cen, 'SOPA', 'Sopa', 1), (e, c, t_cen, 'PROTEICO', 'Proteico', 2), (e, c, t_cen, 'CEREAL', 'Cereal (arroz)', 3), (e, c, t_cen, 'VERDURA', 'Hortalizas y verduras', 4), (e, c, t_cen, 'TUBERCULO', 'Tuberculo, raiz o platano', 5), (e, c, t_cen, 'JUGO', 'Bebida de fruta', 6),
    (e, c, t_ref, 'BEBIDA', 'Bebida', 1), (e, c, t_ref, 'CEREAL', 'Panificado', 2);
  insert into public.variantes_racion (empresa_id, contrato_id, codigo, nombre, es_estandar, componentes_excluidos, descripcion) values
    (e, c, 'ESTANDAR', 'Racion estandar ERON', true, '{}', 'Minuta patron N-N001/N-N002'),
    (e, c, 'EP', 'Estacion de policia / UT (sin sopa)', false, '{SOPA}', 'Anexo 20 tabla 12: proteico 100 g, arroz 180 g, tuberculo 100 g, verdura 80 g, bebida 250/200 ml');
  select id into v_est from public.variantes_racion where contrato_id = c and codigo = 'ESTANDAR';
  select id into v_ep from public.variantes_racion where contrato_id = c and codigo = 'EP';
  insert into public.reglas_rotacion (empresa_id, contrato_id, componente_codigo, min_variedades_semana, max_dias_consecutivos, ventana_no_repetir_dias, nota) values
    (e, c, 'FRUTA', 4, 2, 3, 'Anexo 4: minimo 4 frutas distintas en la semana, sin repetir 3 dias seguidos (Anexo 20 dice 3; Osvaldo: 4)'),
    (e, c, 'POSTRE', 4, 1, 4, 'Minimo 4 postres distintos sin repetir 4 dias seguidos'),
    (e, c, 'JUGO', 2, 1, 3, '2 sabores diarios, distintos durante 3 dias seguidos'),
    (e, c, 'BEBIDA', 4, null, null, 'Minimo 4 variedades de bebida de refrigerio a la semana'),
    (e, c, 'CEREAL', 4, null, null, 'Minimo 4 variedades de panificado a la semana (desayuno y refrigerio)'),
    (e, c, 'PROTEICO', null, null, 4, 'No repetir preparacion de proteico en 4 dias'),
    (e, c, 'SOPA', null, null, 4, 'No repetir sopa en 4 dias'),
    (e, c, 'VERDURA', null, null, 4, 'No repetir hortaliza en 4 dias'),
    (e, c, 'TUBERCULO', null, null, 4, 'No repetir tuberculo en 4 dias; distinto entre almuerzo y cena del mismo dia');
  -- productos (ingredientes del Anexo 4)
  insert into public.productos (empresa_id, codigo, nombre, categoria, unidad_base, unidad_compra, factor_compra, perecedero) values
    (e, 'PERA_CRUDA', 'Pera, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CIRUELA_COMUN_CRUDA', 'Ciruela, común, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'GRANADILLA_CRUDA', 'Granadilla, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'NARANJA_CRUDA', 'Naranja, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MANZANA_COMUN_CRUDA', 'Manzana común, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MANGO_COMUN_CRUDO', 'Mango común, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'DURAZNO_CRUDO', 'Durazno, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'BANANO_COMUN_CRUDO', 'Banano común, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MANDARINA_CRUDA', 'Mandarina, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'ESPINACA_CRUDA', 'Espinaca, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'HABICHUELA_CRUDA', 'Habichuela, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'ZANAHORIA_SIN_CASCARA_CRUDA', 'Zanahoria, sin cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'Papa, variedad harinosa, pastusa, con cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'POLLO_HIGADO_CRUDO', 'Pollo, hígado, crudo', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'LECHE_DE_VACA_ENTERA_EN_POLVO', 'Leche de vaca, entera, en polvo', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'AJO_CRUDO', 'Ajo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CEBOLLA_JUNCA_HOJAS_CRUDA', 'Cebolla junca, hojas, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'SAL', 'Sal', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'AHUYAMA_CRUDA', 'Ahuyama, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'ARVEJA_SECA_CRUDA', 'Arveja seca, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CILANTRO_CRUDO', 'Cilantro, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MAIZ_BLANCO_TRILLADO', 'Maíz blanco, trillado', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PANELA', 'Panela', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'ESPECIAS_DE_ASTILLAS_DE_CANELA', 'Especias de astillas de canela', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'MORA_DE_CASTILLA_CRUDA', 'Mora de Castilla, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'FRESA_MADURA_CRUDA', 'Fresa, madura, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'LULO_CRUDO', 'Lulo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CURUBA_CRUDA', 'Curuba, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'GUANABANA_CRUDA', 'Guanábana, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'TOMATE_DE_ARBOL_ROJO_CRUDO', 'Tomate de árbol rojo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'GUAYABA_MADURA_CRUDA', 'Guayaba, madura, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MARACUYA_CRUDA', 'Maracuyá, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'AREQUIPE_O_DULCE_DE_LECHE', 'Arequipe o dulce de leche', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'BOCADILLO_O_DULCE_DE_GUAYABA_TRADICIONAL', 'Bocadillo o dulce de guayaba, tradicional', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PANELITA_DE_LECHE_DE_VACA_CON_AZUCAR', 'Panelita de leche de vaca, con azúcar', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'COCADAS_CON_PANELA', 'Cocadas, con panela', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'MASMELOS', 'Masmelos', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'GELATINA_DE_PATA', 'Gelatina de pata', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'CARAMELOS_O_CONFITES_DUROS', 'Caramelos o confites, duros', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'CHOCOLATINA_O_CHOCOLATE_DE_LECHE', 'Chocolatina o chocolate de leche', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'PAN_BLANCO_REGULAR_HORNEADO', 'Pan blanco, regular, horneado', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'PAN_DE_DULCE_REGULAR_HORNEADO', 'Pan de dulce, regular, horneado', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'PAN_DE_SAL_REGULAR_HORNEADO', 'Pan de sal, regular, horneado', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'PAN_INTEGRAL_REGULAR_HORNEADO', 'Pan integral, regular, horneado', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'PAN_FRANCES_HORNEADO', 'Pan francés, horneado', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'PAN_DE_QUESO_HORNEADO', 'Pan de queso, horneado', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'TOSTADAS_O_CALADOS_HORNEADOS', 'Tostadas o calados, horneados', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'NECTAR_DE_PERA_CON_AZUCAR', 'Néctar de pera, con azúcar', 'bebidas', 'ml', 'l', 1000, false),
    (e, 'NECTAR_DE_MANZANA_CON_AZUCAR', 'Néctar de manzana, con azúcar', 'bebidas', 'ml', 'l', 1000, false),
    (e, 'NECTAR_DE_MANGO_CON_AZUCAR', 'Néctar de mango, con azúcar', 'bebidas', 'ml', 'l', 1000, false),
    (e, 'NECTAR_DE_GUAYABA_CON_AZUCAR', 'Néctar de guayaba, con azúcar', 'bebidas', 'ml', 'l', 1000, false),
    (e, 'NECTAR_DE_DURAZNO_CON_AZUCAR', 'Néctar de durazno, con azúcar', 'bebidas', 'ml', 'l', 1000, false),
    (e, 'YOGURT_BEBIBLE_ENTERO_CON_AZUCAR', 'Yogurt, bebible, entero, con azúcar', 'lacteos', 'ml', 'l', 1000, true),
    (e, 'KUMIS_ENTERO_CON_AZUCAR', 'Kumis, entero, con azúcar', 'lacteos', 'ml', 'l', 1000, true),
    (e, 'BEBIDA_CON_LECHE_Y_AVENA_PASTEURIZADA_SABOR_NATU', 'Bebida con leche y avena, pasteurizada, sabor natural', 'lacteos', 'ml', 'l', 1000, true),
    (e, 'LECHE_DE_VACA_ENTERA_LIQUIDA_PASTEURIZADA', 'Leche de vaca, entera, líquida, pasteurizada', 'lacteos', 'ml', 'l', 1000, true),
    (e, 'HUEVO_DE_GALLINA_ENTERO_CRUDO', 'Huevo de gallina, entero, crudo', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'CEBOLLA_JUNCA_TALLOS_CRUDA', 'Cebolla junca, tallos, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'RES_CARNE_MAGRA_CRUDA', 'Res, carne magra, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'ARROZ_BLANCO_PULIDO_CRUDO', 'Arroz blanco, pulido, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CHOCOLATE_EN_PASTILLA_CON_AZUCAR', 'Chocolate, en pastilla, con azúcar', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'LENTEJA_COMUN_CRUDA', 'Lenteja común, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'Papa, variedad cerosa, sabanera, con cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CEBOLLA_CABEZONA_CRUDA', 'Cebolla cabezona, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MAIZ_AMARILLO_CRUDO', 'Maíz amarillo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'MAYONESA_CON_SAL', 'Mayonesa, con sal', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PLATANO_HARTON_VERDE_CRUDO', 'Plátano hartón, verde, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'TOMATE_CRUDO', 'Tomate. crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PEREJIL_CRUDO', 'Perejil, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'Papa, variedad harinosa, criolla, con cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'LECHUGA_COMUN_CRUDA', 'Lechuga común, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'VINAGRE', 'Vinagre', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'HARINA_DE_AVENA_CRUDA', 'Harina de avena, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'QUESO_FRESCO_SEMIDURO_SEMIMAGRO_TIPO_DOBLE_CREMA', 'Queso fresco, semiduro, semimagro, tipo doble crema', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'CEBADA_PERLADA_CRUDA', 'Cebada, perlada, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'REMOLACHA_SIN_CASCARA_CRUDA', 'Remolacha, sin cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PEPINO_COHOMBRO_CRUDO', 'Pepino cohombro, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'YUCA_BLANCA_SIN_CASCARA_CRUDA', 'Yuca blanca, sin cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'ALMIDON_DE_MAIZ_CRUDO', 'Almidón de maíz, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'AVENA_EN_HOJUELAS_PRECOCIDA', 'Avena en hojuelas, precocida', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'Pollo, pechuga con piel, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'ESPECIAS_DE_ROMERO_SECO', 'Especias de romero seco', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'ESPECIAS_DE_TOMILLO_SECO', 'Especias de tomillo seco', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PLATANO_HARTON_MADURO_CRUDO', 'Plátano hartón, maduro, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CERDO_CARNE_MAGRA_CRUDA', 'Cerdo, carne magra, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'MANI_CON_PIEL_TOSTADO_SIN_SAL', 'Maní, con piel, tostado, sin sal', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_CAMPESINO', 'Queso fresco, semiduro, semigraso, tipo campesino', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'AREPA_DE_MAIZ_PRECOCIDO_CON_SAL', 'Arepa de maíz precocido, con sal', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'GUASCAS_CRUDAS', 'Guascas, crudas', 'fruver', 'g', 'kg', 1000, true),
    (e, 'POLLO_PIERNA_O_COLOMBINA_CON_PIEL_CRUDA', 'Pollo, pierna o colombina con piel, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'CUCHUCO_DE_TRIGO_CRUDO', 'Cuchuco de trigo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CAFE_SOLUBLE_EN_POLVO', 'Café soluble, en polvo', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PASTA_ALIMENTICIA_ENRIQUECIDA_CRUDA', 'Pasta alimenticia, enriquecida, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'Bagre, magro, sin cabeza, crudo', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'HARINA_DE_TRIGO_FORTIFICADA_TODO_PROPOSITO_CRUDA', 'Harina de trigo, fortificada, todo propósito, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'FRIJOL_BOLA_ROJA_CRUDO', 'Fríjol bola roja, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'AGUACATE_LORENA_CRUDO', 'Aguacate Lorena, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'LIMON_CRUDO', 'Limón, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'HARINA_DE_PLATANO_CRUDA', 'Harina de plátano, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'REPOLLO_MORADO_CRUDO', 'Repollo morado, crudo', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'TILAPIA_O_MOJARRA_FILETE_CRUDA', 'Tilapia o mojarra, filete, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'BAGRE_MAGRO_FILETE_CRUDO', 'Bagre, magro, filete, crudo', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'MAIZ_MUTE_COCIDO_SIN_SAL', 'Maíz mute, cocido, sin sal', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'PIMENTON_ROJO_CRUDO', 'Pimentón rojo, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PLATANO_COLI_O_GUINEO_VERDE_CRUDO', 'Plátano colí o guíneo, verde. crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'PIMENTON_VERDE_CRUDO', 'Pimentón verde, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'BEBIDA_VEGETAL_DE_SOYA_LIQUIDA_SIN_AZUCAR', 'Bebida vegetal, de soya, líquida, sin azúcar', 'abarrotes', 'ml', 'l', 1000, false),
    (e, 'COCO_CRUDO', 'Coco, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'AZUCAR_BLANCO_GRANULADO', 'Azúcar blanco, granulado', 'abarrotes', 'g', 'kg', 1000, false),
    (e, 'FRIJOL_GUANDUL_CRUDO', 'Fríjol guandul, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'NAME_CON_CASCARA_CRUDO', 'Ñame, con cáscara, crudo', 'fruver', 'g', 'kg', 1000, true),
    (e, 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_COSTENO', 'Queso fresco, semiduro, semigraso, tipo costeño', 'lacteos', 'g', 'kg', 1000, true),
    (e, 'ENVUELTO_DE_MAZORCA_PRECOCIDO', 'Envuelto de mazorca, precocido', 'panaderia', 'g', 'kg', 1000, true),
    (e, 'ARVEJA_VERDE_CRUDA', 'Arveja verde, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'CALABAZA_SIN_CASCARA_CRUDA', 'Calabaza, sin cáscara, cruda', 'fruver', 'g', 'kg', 1000, true),
    (e, 'SALCHICHA_CRUDA', 'Salchicha, cruda', 'proteinas', 'g', 'kg', 1000, true),
    (e, 'CALADO_TOSTADA', 'Calado o tostada', 'panaderia', 'g', 'kg', 1000, true);
  update public.productos set rendimiento = 2.3 where empresa_id = e and codigo = 'ARROZ_BLANCO_PULIDO_CRUDO';
  insert into public.factores_coccion (empresa_id, producto_id, metodo, factor, fuente)
  select e, p.id, x.metodo, x.factor, 'Anexo 4 N-N000' from (values
    ('SALCHICHA_CRUDA', 'hervido', 0.89),
    ('FRIJOL_BOLA_ROJA_CRUDO', 'presión', 2.1),
    ('LENTEJA_COMUN_CRUDA', 'presión', 2.4),
    ('ARVEJA_SECA_CRUDA', 'presión', 2.2),
    ('ARROZ_BLANCO_PULIDO_CRUDO', 'hervido', 2.3),
    ('PASTA_ALIMENTICIA_ENRIQUECIDA_CRUDA', 'hervido', 2.27),
    ('LECHE_DE_VACA_ENTERA_EN_POLVO', 'reconstitución', 8.33),
    ('HUEVO_DE_GALLINA_ENTERO_CRUDO', 'cocido', 1.0),
    ('HUEVO_DE_GALLINA_ENTERO_CRUDO', 'revuelto', 0.95),
    ('HUEVO_DE_GALLINA_ENTERO_CRUDO', 'frito', 0.9),
    ('BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'asado', 0.69),
    ('BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'horneado', 0.69),
    ('BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'fritura', 0.65),
    ('BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'hervido', 0.76),
    ('PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'cocida', 0.99),
    ('PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'dorado', 0.89),
    ('PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'frito', 0.79),
    ('YUCA_BLANCA_SIN_CASCARA_CRUDA', 'cocida', 0.99),
    ('YUCA_BLANCA_SIN_CASCARA_CRUDA', 'dorado', 0.89),
    ('YUCA_BLANCA_SIN_CASCARA_CRUDA', 'frito', 0.79),
    ('PLATANO_HARTON_VERDE_CRUDO', 'cocida', 0.99),
    ('PLATANO_HARTON_VERDE_CRUDO', 'dorado', 0.89),
    ('PLATANO_HARTON_VERDE_CRUDO', 'frito', 0.79),
    ('NAME_CON_CASCARA_CRUDO', 'cocida', 0.99),
    ('NAME_CON_CASCARA_CRUDO', 'dorado', 0.89),
    ('NAME_CON_CASCARA_CRUDO', 'frito', 0.79)
  ) as x(codigo, metodo, factor) join public.productos p on p.empresa_id = e and p.codigo = x.codigo
  on conflict do nothing;
  -- preparaciones y sus ingredientes (peso bruto H / M)
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_PERA', 'Fruta: Pera', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_PERA', 'PERA_CRUDA', null, 82.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_CIRUELA', 'Fruta: Ciruela', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_CIRUELA', 'CIRUELA_COMUN_CRUDA', null, 73.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_GRANADILLA', 'Fruta: Granadilla', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_GRANADILLA', 'GRANADILLA_CRUDA', null, 150.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_NARANJA', 'Fruta: Naranja', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_NARANJA', 'NARANJA_CRUDA', null, 116.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_MANZANA_COMUN', 'Fruta: Manzana común', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_MANZANA_COMUN', 'MANZANA_COMUN_CRUDA', null, 82.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_MANGO_COMUN', 'Fruta: Mango común', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_MANGO_COMUN', 'MANGO_COMUN_CRUDO', null, 140.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_DURAZNO', 'Fruta: Durazno', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_DURAZNO', 'DURAZNO_CRUDO', null, 82.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_BANANO_COMUN', 'Fruta: Banano común', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_BANANO_COMUN', 'BANANO_COMUN_CRUDO', null, 100.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FRUTA_MANDARINA', 'Fruta: Mandarina', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FRUTA_MANDARINA', 'MANDARINA_CRUDA', null, 100.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CREMA_DE_VERDURAS', 'Crema de verduras', 'SOPA', 'Lavar, pelar y picar y desinfectar las verduras y la papa de acuerdo al Manual de Manipulación de Alimentos, cocinar con agua, las vísceras, la cebolla, el ajo y sal. Una vez complete cocción retirar del fuego, pelar y licuar con la leche y reservar. Aparte rayar la papa. Incorporar esta mezcla con las verduras, llevar nuevamente a calor a fuego bajo, revolver frecuentemente para evitar que se que');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CREMA_DE_VERDURAS', 'ESPINACA_CRUDA', null, 41.0, true, 1),
    ('CREMA_DE_VERDURAS', 'HABICHUELA_CRUDA', null, 55.0, false, 2),
    ('CREMA_DE_VERDURAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 3),
    ('CREMA_DE_VERDURAS', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 4),
    ('CREMA_DE_VERDURAS', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 5),
    ('CREMA_DE_VERDURAS', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, false, 6),
    ('CREMA_DE_VERDURAS', 'AJO_CRUDO', null, 1.0, false, 7),
    ('CREMA_DE_VERDURAS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('CREMA_DE_VERDURAS', 'SAL', null, 1.0, false, 9)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_VERDURAS', 'Sopa de verduras', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo Lavar, pelar y picar y desinfectar las verduras y la papa, de acuerdo al Manual de Manipulación de Alimentos. Aparte coloque una olla prepare un caldo básico con ajo, sal, cebolla, cilantro (una parte) y las vísceras, adicione a este caldo la papa, cuando rompa el hervor adicione las verduras, dejar cocer antes de se');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_VERDURAS', 'HABICHUELA_CRUDA', null, 55.0, true, 1),
    ('SOPA_DE_VERDURAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 2),
    ('SOPA_DE_VERDURAS', 'AHUYAMA_CRUDA', null, 29.0, false, 3),
    ('SOPA_DE_VERDURAS', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 4),
    ('SOPA_DE_VERDURAS', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 5),
    ('SOPA_DE_VERDURAS', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPA_DE_VERDURAS', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPA_DE_VERDURAS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPA_DE_VERDURAS', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_VERDURAS', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'MAZAMORRA_DULCE', 'Mazamorra dulce', 'SOPA', 'Dejar en remojo el día anterior el maíz, desechar el agua de remojo. Cocinar el maíz y la canela en olla con presión, cuando este blando agregar la leche junto la panela, mezclar para que se integren los ingrediente. Sirva de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('MAZAMORRA_DULCE', 'MAIZ_BLANCO_TRILLADO', null, 100.0, true, 1),
    ('MAZAMORRA_DULCE', 'PANELA', null, 12.0, false, 2),
    ('MAZAMORRA_DULCE', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, false, 3),
    ('MAZAMORRA_DULCE', 'ESPECIAS_DE_ASTILLAS_DE_CANELA', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MORA_DE_CASTILLA', 'Jugo de mora de castilla', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MORA_DE_CASTILLA', 'MORA_DE_CASTILLA_CRUDA', null, 66.0, true, 1),
    ('JUGO_DE_MORA_DE_CASTILLA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_FRESA', 'Jugo de fresa', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_FRESA', 'FRESA_MADURA_CRUDA', null, 63.0, true, 1),
    ('JUGO_DE_FRESA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_LULO', 'Jugo de lulo', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_LULO', 'LULO_CRUDO', null, 100.0, true, 1),
    ('JUGO_DE_LULO', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_CURUBA', 'Jugo de curuba', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_CURUBA', 'CURUBA_CRUDA', null, 120.0, true, 1),
    ('JUGO_DE_CURUBA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MANGO_COMUN', 'Jugo de mango común', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MANGO_COMUN', 'MANGO_COMUN_CRUDO', null, 120.0, true, 1),
    ('JUGO_DE_MANGO_COMUN', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_GUANABANA', 'Jugo de guanábana', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_GUANABANA', 'GUANABANA_CRUDA', null, 85.0, true, 1),
    ('JUGO_DE_GUANABANA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_TOMATE_DE_ARBOL_ROJO', 'Jugo de tomate de árbol rojo', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_TOMATE_DE_ARBOL_ROJO', 'TOMATE_DE_ARBOL_ROJO_CRUDO', null, 69.0, true, 1),
    ('JUGO_DE_TOMATE_DE_ARBOL_ROJO', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_GUAYABA', 'Jugo de guayaba', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_GUAYABA', 'GUAYABA_MADURA_CRUDA', null, 80.0, true, 1),
    ('JUGO_DE_GUAYABA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MARACUYA', 'Jugo de maracuyá', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MARACUYA', 'MARACUYA_CRUDA', null, 187.0, true, 1),
    ('JUGO_DE_MARACUYA', 'AZUCAR_BLANCO_GRANULADO', null, 12.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_AREQUIPE_O_DULCE_DE_LECHE', 'Postre: Arequipe o dulce de leche', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_AREQUIPE_O_DULCE_DE_LECHE', 'AREQUIPE_O_DULCE_DE_LECHE', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'Postre: Bocadillo o dulce de guayaba', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'BOCADILLO_O_DULCE_DE_GUAYABA_TRADICIONAL', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_PANELITA_DE_LECHE_DE_VACA', 'Postre: Panelita de leche de vaca', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_PANELITA_DE_LECHE_DE_VACA', 'PANELITA_DE_LECHE_DE_VACA_CON_AZUCAR', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_COCADAS', 'Postre: Cocadas', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_COCADAS', 'COCADAS_CON_PANELA', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_MASMELOS', 'Postre: Masmelos', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_MASMELOS', 'MASMELOS', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_GELATINA_DE_PATA', 'Postre: Gelatina de pata', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_GELATINA_DE_PATA', 'GELATINA_DE_PATA', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_CARAMELOS_O_CONFITES', 'Postre: Caramelos o confites', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_CARAMELOS_O_CONFITES', 'CARAMELOS_O_CONFITES_DUROS', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'POSTRE_CHOCOLATINA_O_CHOCOLATE_DE_LECHE', 'Postre: Chocolatina o chocolate de leche', 'POSTRE', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('POSTRE_CHOCOLATINA_O_CHOCOLATE_DE_LECHE', 'CHOCOLATINA_O_CHOCOLATE_DE_LECHE', null, 10.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_BLANCO', 'Pan blanco', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_BLANCO', 'PAN_BLANCO_REGULAR_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_BLANCO', 'PAN_BLANCO_REGULAR_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_DE_DULCE', 'Pan de dulce', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_DE_DULCE', 'PAN_DE_DULCE_REGULAR_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_DE_DULCE', 'PAN_DE_DULCE_REGULAR_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_DE_SAL', 'Pan de sal', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_DE_SAL', 'PAN_DE_SAL_REGULAR_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_DE_SAL', 'PAN_DE_SAL_REGULAR_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_INTEGRAL', 'Pan integral', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_INTEGRAL', 'PAN_INTEGRAL_REGULAR_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_INTEGRAL', 'PAN_INTEGRAL_REGULAR_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_FRANCES', 'Pan francés', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_FRANCES', 'PAN_FRANCES_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_FRANCES', 'PAN_FRANCES_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAN_DE_QUESO', 'Pan de queso', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAN_DE_QUESO', 'PAN_DE_QUESO_HORNEADO', 'H', 60.0, true, 1),
    ('PAN_DE_QUESO', 'PAN_DE_QUESO_HORNEADO', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TOSTADAS_O_CALADOS', 'Tostadas o calados', 'PANIFICADO', 'Alistar el alimento y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TOSTADAS_O_CALADOS', 'TOSTADAS_O_CALADOS_HORNEADOS', 'H', 60.0, true, 1),
    ('TOSTADAS_O_CALADOS', 'TOSTADAS_O_CALADOS_HORNEADOS', 'M', 50.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_NECTAR_DE_PERA', 'Bebida: Néctar de pera', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_NECTAR_DE_PERA', 'NECTAR_DE_PERA_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_NECTAR_DE_MANZANA', 'Bebida: Néctar de manzana', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_NECTAR_DE_MANZANA', 'NECTAR_DE_MANZANA_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_NECTAR_DE_MANGO', 'Bebida: Néctar de mango', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_NECTAR_DE_MANGO', 'NECTAR_DE_MANGO_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_NECTAR_DE_GUAYABA', 'Bebida: Néctar de guayaba', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_NECTAR_DE_GUAYABA', 'NECTAR_DE_GUAYABA_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_NECTAR_DE_DURAZNO', 'Bebida: Néctar de durazno', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_NECTAR_DE_DURAZNO', 'NECTAR_DE_DURAZNO_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_YOGURT', 'Bebida: Yogurt', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_YOGURT', 'YOGURT_BEBIBLE_ENTERO_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_KUMIS', 'Bebida: Kumis', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_KUMIS', 'KUMIS_ENTERO_CON_AZUCAR', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_BEBIDA_CON_LECHE_Y_AVENA', 'Bebida: Bebida con leche y avena', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_BEBIDA_CON_LECHE_Y_AVENA', 'BEBIDA_CON_LECHE_Y_AVENA_PASTEURIZADA_SABOR_NATU', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BEBIDA_LECHE_DE_VACA', 'Bebida: Leche de vaca', 'BEBIDA_REF', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento y servir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BEBIDA_LECHE_DE_VACA', 'LECHE_DE_VACA_ENTERA_LIQUIDA_PASTEURIZADA', null, 200.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CHANGUA_DE_HUEVO', 'Changua de huevo', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En una olla sofreír el ajo, a continuación, poner el agua con unas ramas de cebolla junca y tallos de cilantro y sal, posteriormente agregar la leche y cuando esté a punto de hervir retirar los tallos cilantro y las ramas de cebolla. Agregar el huevo con mucho cuidado para no romperlo, se deja hasta que cocin');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CHANGUA_DE_HUEVO', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', null, 55.0, true, 1),
    ('CHANGUA_DE_HUEVO', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, false, 2),
    ('CHANGUA_DE_HUEVO', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 3),
    ('CHANGUA_DE_HUEVO', 'CILANTRO_CRUDO', null, 1.0, false, 4),
    ('CHANGUA_DE_HUEVO', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'RES_DORADA', 'Res Dorada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos.\nPrecalentar la plancha; previamente cubrir la carne de res con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('RES_DORADA', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('RES_DORADA', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('RES_DORADA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ARROZ_BLANCO', 'Arroz Blanco', 'CEREAL', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar el arroz con abundante agua y dejar escurrir. En una olla sofreír el ajo, sal y cebolla finamente picada a fuego medio, a continuación, añadir el arroz y mezclar, añadir el agua y cocinar a fuego alto hasta que el agua se evapore, pasar a fuego lento y tapar la olla de dejar a fuego lento hasta que le g');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ARROZ_BLANCO', 'ARROZ_BLANCO_PULIDO_CRUDO', 'H', 74.0, true, 1),
    ('ARROZ_BLANCO', 'ARROZ_BLANCO_PULIDO_CRUDO', 'M', 69.0, true, 1),
    ('ARROZ_BLANCO', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 2),
    ('ARROZ_BLANCO', 'AJO_CRUDO', null, 1.0, false, 3),
    ('ARROZ_BLANCO', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CHOCOLATE_EN_LECHE', 'Chocolate en leche', 'BEBIDA_DES', 'Reconstituir la leche en agua. En la licuadora colocar agua y leche por partes iguales, agregar la mezcla en polvo de chocolate instantáneo con azúcar y mezclar con un poco de hielo si se desea. En caso de preparación caliente seguir los mismos pasos, una vez reconstituida la mezcla en la licuadora llevar a una olla, poner a calentar a fuego medio/ alto y servir caliente. En caso de preparar choco');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CHOCOLATE_EN_LECHE', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, true, 1),
    ('CHOCOLATE_EN_LECHE', 'CHOCOLATE_EN_PASTILLA_CON_AZUCAR', null, 12.0, false, 2),
    ('CHOCOLATE_EN_LECHE', 'AZUCAR_BLANCO_GRANULADO', null, 10.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CAZUELA_DE_LENTEJAS', 'Cazuela de lentejas', 'SOPA', 'Dejar el día anterior las lentejas en remojo, deseche el agua del remojo. Lave, pele y pique la papa en cuadros, lave y desinfecte las verduras, de acuerdo a lo establecido en  el Manual de Manipulación de Alimentos. Preparar un caldo básico con ajo, sal, cebolla y cilantro (una parte), adicione a este caldo las lentejas Y las vísceras, deje que hiervan suficiente, adicione la papa y zanahoria con');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CAZUELA_DE_LENTEJAS', 'LENTEJA_COMUN_CRUDA', null, 60.0, true, 1),
    ('CAZUELA_DE_LENTEJAS', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', null, 25.0, false, 2),
    ('CAZUELA_DE_LENTEJAS', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 3),
    ('CAZUELA_DE_LENTEJAS', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 4),
    ('CAZUELA_DE_LENTEJAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 2.0, false, 5),
    ('CAZUELA_DE_LENTEJAS', 'AJO_CRUDO', null, 1.0, false, 6),
    ('CAZUELA_DE_LENTEJAS', 'SAL', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'VERDURAS_CAMPESINAS', 'Verduras Campesinas', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y cortar en las verduras en cubos homogéneos. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir las habichuelas y dejar cocinar hasta que adquieran un color verde brillante. Sacar del agua caliente y en un recipiente sumergir en agua fría, para mantener al dente, luego e');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('VERDURAS_CAMPESINAS', 'CEBOLLA_CABEZONA_CRUDA', 'H', 21.0, true, 1),
    ('VERDURAS_CAMPESINAS', 'CEBOLLA_CABEZONA_CRUDA', 'M', 15.0, true, 1),
    ('VERDURAS_CAMPESINAS', 'HABICHUELA_CRUDA', 'H', 22.0, false, 2),
    ('VERDURAS_CAMPESINAS', 'HABICHUELA_CRUDA', 'M', 16.0, false, 2),
    ('VERDURAS_CAMPESINAS', 'MAIZ_AMARILLO_CRUDO', 'H', 20.0, false, 3),
    ('VERDURAS_CAMPESINAS', 'MAIZ_AMARILLO_CRUDO', 'M', 15.0, false, 3),
    ('VERDURAS_CAMPESINAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 23.0, false, 4),
    ('VERDURAS_CAMPESINAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 17.0, false, 4),
    ('VERDURAS_CAMPESINAS', 'MAYONESA_CON_SAL', null, 2.0, false, 5),
    ('VERDURAS_CAMPESINAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_PLATANO', 'Sopa de plátano', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar, desinfecte las verduras, de acuerdo al Manual de Manipulación de Alimentos. Lavar y pelar el plátano hartón, y la papa. Tajar la papa, cortar en trozos el plátano y rallar una parte. Poner en una olla agua y preparar un caldo básico con el ajo, la cebolla y una parte del cilantro, las vísceras ');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_PLATANO', 'PLATANO_HARTON_VERDE_CRUDO', null, 88.0, true, 1),
    ('SOPA_DE_PLATANO', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPA_DE_PLATANO', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPA_DE_PLATANO', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPA_DE_PLATANO', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPA_DE_PLATANO', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPA_DE_PLATANO', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPA_DE_PLATANO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPA_DE_PLATANO', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_PLATANO', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'RES_SUDADA', 'Res sudada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla y el ajo; previamente sofreír algunos aderezos por unos minutos. Agregar aceite en un recipiente y el sofrito anterior,  el tomate, la cebolla, ajo, la carne, agua y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando, revolver, re');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('RES_SUDADA', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('RES_SUDADA', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('RES_SUDADA', 'TOMATE_CRUDO', null, 6.0, false, 2),
    ('RES_SUDADA', 'CEBOLLA_CABEZONA_CRUDA', null, 5.0, false, 3),
    ('RES_SUDADA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('RES_SUDADA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ARROZ_CON_ZANAHORIA', 'Arroz con zanahoria', 'CEREAL', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en cubos pequeños la zanahoria. Lavar el arroz con abundante agua y dejar escurrir. En una olla sofreír el ajo, sal y cebolla finamente picada a fuego medio, a continuación, añadir el arroz y la zanahoria, revolver hasta mezclar los ingredientes, añadir el agua y cocinar a fuego alto has');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ARROZ_CON_ZANAHORIA', 'ARROZ_BLANCO_PULIDO_CRUDO', 'H', 74.0, true, 1),
    ('ARROZ_CON_ZANAHORIA', 'ARROZ_BLANCO_PULIDO_CRUDO', 'M', 69.0, true, 1),
    ('ARROZ_CON_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 11.0, false, 2),
    ('ARROZ_CON_ZANAHORIA', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 3),
    ('ARROZ_CON_ZANAHORIA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('ARROZ_CON_ZANAHORIA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAPA_AL_PEREJIL', 'Papa al perejil', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar la papa en cubos, Agregar agua en un recipiente junto con las papas y aderezos y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar retirar agua, agregar el perejil finamente picado y la mayonesa, revolver, rectifica el sabor. Servir caliente de acuerdo al gra');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAPA_AL_PEREJIL', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PAPA_AL_PEREJIL', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PAPA_AL_PEREJIL', 'PEREJIL_CRUDO', null, 2.0, false, 2),
    ('PAPA_AL_PEREJIL', 'MAYONESA_CON_SAL', null, 2.0, false, 3),
    ('PAPA_AL_PEREJIL', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('PAPA_AL_PEREJIL', 'AJO_CRUDO', null, 1.0, false, 5),
    ('PAPA_AL_PEREJIL', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CRIOLLAS_CHORREADAS', 'Criollas chorreadas', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla; previamente sofreír algunos aderezos por unos minutos agregar leche reconstituida y reservar. En un recipiente agregar agua suficiente en un recipiente junto con las papas y cocinar hasta que todo esté blando; para finalizar retirar agua, adicionar ');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CRIOLLAS_CHORREADAS', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('CRIOLLAS_CHORREADAS', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('CRIOLLAS_CHORREADAS', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 2.0, false, 2),
    ('CRIOLLAS_CHORREADAS', 'TOMATE_CRUDO', null, 2.0, false, 3),
    ('CRIOLLAS_CHORREADAS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('CRIOLLAS_CHORREADAS', 'AJO_CRUDO', null, 1.0, false, 5),
    ('CRIOLLAS_CHORREADAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_CURUBA_2', 'Jugo de curuba', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_CURUBA_2', 'CURUBA_CRUDA', null, 120.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'LECHUGA_TOMATE_Y_ZANAHORIA', 'Lechuga, tomate y zanahoria', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'TOMATE_CRUDO', 'H', 31.0, true, 1),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'TOMATE_CRUDO', 'M', 25.0, true, 1),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 29.0, false, 2),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 23.0, false, 2),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'LECHUGA_COMUN_CRUDA', 'H', 54.0, false, 3),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'LECHUGA_COMUN_CRUDA', 'M', 36.0, false, 3),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'SAL', null, 1.0, false, 4),
    ('LECHUGA_TOMATE_Y_ZANAHORIA', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'AVENA_EN_LECHE', 'Avena en leche', 'BEBIDA_DES', 'Reconstituir la leche en agua (cuando se utilice leche en polvo). En una olla colocar el agua con la canela, el azúcar y poner a hervir, a continuación se agrega la avena previamente disuelta en un pocillo de agua, remueva constantemente con una cuchara para que no se pegue, cocine a fuego medio durante unos minutos. Retire del fuego, deje reposar evitando la formación de natas. Servir caliente de');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('AVENA_EN_LECHE', 'HARINA_DE_AVENA_CRUDA', null, 12.0, true, 1),
    ('AVENA_EN_LECHE', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, false, 2),
    ('AVENA_EN_LECHE', 'ESPECIAS_DE_ASTILLAS_DE_CANELA', null, 1.0, false, 3),
    ('AVENA_EN_LECHE', 'AZUCAR_BLANCO_GRANULADO', null, 10.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'QUESO_DOBLE_CREMA', 'Queso doble crema', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('QUESO_DOBLE_CREMA', 'QUESO_FRESCO_SEMIDURO_SEMIMAGRO_TIPO_DOBLE_CREMA', 'H', 35.0, true, 1),
    ('QUESO_DOBLE_CREMA', 'QUESO_FRESCO_SEMIDURO_SEMIMAGRO_TIPO_DOBLE_CREMA', 'M', 25.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_CEBADA_PERLADA', 'Sopa de cebada perlada', 'SOPA', 'Dejar el día anterior la cebada perlada y la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y tajar la papa y yuca, lave y desinfecte las verduras, de acuerdo al Manual de Manipulación de Alimentos. Colocar una olla un caldo básico con ajo sal cebolla y cilantro (una parte) y las vísceras, adicione a este caldo la cebada perlada, y el aceite, dejar que hiervan suficiente, a');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_CEBADA_PERLADA', 'CEBADA_PERLADA_CRUDA', null, 40.0, true, 1),
    ('SOPA_DE_CEBADA_PERLADA', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPA_DE_CEBADA_PERLADA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPA_DE_CEBADA_PERLADA', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPA_DE_CEBADA_PERLADA', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPA_DE_CEBADA_PERLADA', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPA_DE_CEBADA_PERLADA', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPA_DE_CEBADA_PERLADA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPA_DE_CEBADA_PERLADA', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_CEBADA_PERLADA', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'RES_ENCEBOLLADA', 'Res encebollada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar la cebolla; Previamente sofreír algunos aderezos por unos minutos. Agregar aceite en un recipiente y el sofrito anterior, la carne, agua y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar agregar  la cebolla, revolver, dejar cocinar u');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('RES_ENCEBOLLADA', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('RES_ENCEBOLLADA', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('RES_ENCEBOLLADA', 'CEBOLLA_CABEZONA_CRUDA', null, 10.0, false, 2),
    ('RES_ENCEBOLLADA', 'AJO_CRUDO', null, 1.0, false, 3),
    ('RES_ENCEBOLLADA', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'REMOLACHA_Y_ZANAHORIA', 'Remolacha y Zanahoria', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar la zanahoria en cubos pequeños. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir la remolacha, la sal y dejar cocinar hasta que este blanda. Sacar del agua caliente y escurrir, para luego cortar en cubos pequeños escurrir y reservar en frío. Por otro lado, en un');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('REMOLACHA_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 47.0, true, 1),
    ('REMOLACHA_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 35.0, true, 1),
    ('REMOLACHA_Y_ZANAHORIA', 'REMOLACHA_SIN_CASCARA_CRUDA', 'H', 50.0, false, 2),
    ('REMOLACHA_Y_ZANAHORIA', 'REMOLACHA_SIN_CASCARA_CRUDA', 'M', 37.0, false, 2),
    ('REMOLACHA_Y_ZANAHORIA', 'MAYONESA_CON_SAL', null, 2.0, false, 3),
    ('REMOLACHA_Y_ZANAHORIA', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAPA_SALADA', 'Papa salada', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En un recipiente agregar agua suficiente en un recipiente junto con las papas y aderezos, cocinar hasta que todo esté blando; para finalizar retirar agua, adicionar sal en cantidad suficiente, revolver, rectifica el sabor. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAPA_SALADA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PAPA_SALADA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PAPA_SALADA', 'SAL', null, 2.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_FRESA_2', 'Jugo de Fresa', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_FRESA_2', 'FRESA_MADURA_CRUDA', null, 63.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TOMATE_Y_PEPINO', 'Tomate y pepino', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar.  Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TOMATE_Y_PEPINO', 'TOMATE_CRUDO', 'H', 50.0, true, 1),
    ('TOMATE_Y_PEPINO', 'TOMATE_CRUDO', 'M', 37.0, true, 1),
    ('TOMATE_Y_PEPINO', 'PEPINO_COHOMBRO_CRUDO', 'H', 53.0, false, 2),
    ('TOMATE_Y_PEPINO', 'PEPINO_COHOMBRO_CRUDO', 'M', 40.0, false, 2),
    ('TOMATE_Y_PEPINO', 'CILANTRO_CRUDO', null, 1.0, false, 3),
    ('TOMATE_Y_PEPINO', 'SAL', null, 1.0, false, 4),
    ('TOMATE_Y_PEPINO', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'YUCA_DORADA', 'Yuca dorada', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Previamente cocinar la yuca en agua y aderezos; precalentar el aceite en el recipiente de dorado; pasar las yucas por esté recipiente por unos minutos hasta que la yuca tome un color dorado leve. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('YUCA_DORADA', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', 'H', 126.0, true, 1),
    ('YUCA_DORADA', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', 'M', 96.0, true, 1),
    ('YUCA_DORADA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MORA', 'Jugo de mora', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MORA', 'MORA_DE_CASTILLA_CRUDA', null, 66.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'GRANADILLA', 'Granadilla', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('GRANADILLA', 'GRANADILLA_CRUDA', null, 150.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FECULA_DE_MAIZ', 'Fécula de maíz', 'BEBIDA_DES', 'Reconstituir la leche en agua. En una olla colocar el agua con el azúcar y la canela, poner a hervir, a continuación se agregar la Fécula de maíz previamente disuelta, remueva constantemente con una cuchara o cucharón para que no se pegue, cocine a fuego medio e incorporar la leche que debe de haber conservado a temperatura media. Retire del fuego, dejar reposar evitando la formación de natas. Ser');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FECULA_DE_MAIZ', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, true, 1),
    ('FECULA_DE_MAIZ', 'ALMIDON_DE_MAIZ_CRUDO', null, 12.0, false, 2),
    ('FECULA_DE_MAIZ', 'ESPECIAS_DE_ASTILLAS_DE_CANELA', null, 1.0, false, 3),
    ('FECULA_DE_MAIZ', 'AZUCAR_BLANCO_GRANULADO', null, 10.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'HUEVOS_PERICOS', 'Huevos pericos', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar la cebolla y el tomate, luego cortarlos en muy pequeños cubos. En una sartén calentar el aceite a fuego medio, añadir los tomates y cebollas cortados. Cocinar por unos minutos y revolver ocasionalmente. Por otro lado, en un tazón batir los huevos y la sal. Incorporar los huevos en la sartén con la mezcl');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('HUEVOS_PERICOS', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', null, 55.0, true, 1),
    ('HUEVOS_PERICOS', 'TOMATE_CRUDO', null, 2.0, false, 2),
    ('HUEVOS_PERICOS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 3),
    ('HUEVOS_PERICOS', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPAS_DE_AVENA', 'Sopas de avena', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar, desinfecte las verduras y la papa de acuerdo al Manual de Manipulación de Alimentos. Aparte coloque una olla prepare un caldo básico con ajo sal cebolla y cilantro (una parte) y las vísceras, adicione a este caldo la papa, yuca, plátano y el aceite, permita la cocción de estos ingredientes (mez');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPAS_DE_AVENA', 'AVENA_EN_HOJUELAS_PRECOCIDA', null, 40.0, true, 1),
    ('SOPAS_DE_AVENA', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPAS_DE_AVENA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPAS_DE_AVENA', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPAS_DE_AVENA', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPAS_DE_AVENA', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPAS_DE_AVENA', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPAS_DE_AVENA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPAS_DE_AVENA', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPAS_DE_AVENA', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PECHUGA_ASADA', 'Pechuga asada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la pechuga con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PECHUGA_ASADA', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'H', 125.0, true, 1),
    ('PECHUGA_ASADA', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'M', 112.0, true, 1),
    ('PECHUGA_ASADA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PECHUGA_AL_PEREJIL', 'Pechuga al perejil', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la pechuga con una capa fina de aceite y ajo finamente picado; colocar en la plancha agregando perejil finamente picado finalizando la cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PECHUGA_AL_PEREJIL', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'H', 125.0, true, 1),
    ('PECHUGA_AL_PEREJIL', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'M', 112.0, true, 1),
    ('PECHUGA_AL_PEREJIL', 'PEREJIL_CRUDO', null, 2.0, false, 2),
    ('PECHUGA_AL_PEREJIL', 'AJO_CRUDO', null, 1.0, false, 3),
    ('PECHUGA_AL_PEREJIL', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PECHUGA_FINAS_HIERBAS', 'Pechuga finas hierbas', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la pechuga con una capa fina de aceite y aderezos; colocar en la plancha agregando perejil finamente picado finalizando la cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PECHUGA_FINAS_HIERBAS', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'H', 125.0, true, 1),
    ('PECHUGA_FINAS_HIERBAS', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'M', 112.0, true, 1),
    ('PECHUGA_FINAS_HIERBAS', 'PEREJIL_CRUDO', null, 1.0, false, 2),
    ('PECHUGA_FINAS_HIERBAS', 'ESPECIAS_DE_ROMERO_SECO', null, 1.0, false, 3),
    ('PECHUGA_FINAS_HIERBAS', 'ESPECIAS_DE_TOMILLO_SECO', null, 1.0, false, 4),
    ('PECHUGA_FINAS_HIERBAS', 'AJO_CRUDO', null, 1.0, false, 5),
    ('PECHUGA_FINAS_HIERBAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PLATANO_MELAO', 'Plátano melao', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar el plátano en cortas gruesos, Agregar agua en un recipiente junto con el plátano, panela y canela y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar retirar agua. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PLATANO_MELAO', 'PLATANO_HARTON_MADURO_CRUDO', 'H', 140.0, true, 1),
    ('PLATANO_MELAO', 'PLATANO_HARTON_MADURO_CRUDO', 'M', 106.0, true, 1),
    ('PLATANO_MELAO', 'PANELA', null, 5.0, false, 2),
    ('PLATANO_MELAO', 'ESPECIAS_DE_ASTILLAS_DE_CANELA', null, 1.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TOMATE_HABICHUELA_Y_CEBOLLA', 'Tomate, habichuela y cebolla', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'TOMATE_CRUDO', 'H', 31.0, true, 1),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'TOMATE_CRUDO', 'M', 25.0, true, 1),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'HABICHUELA_CRUDA', 'H', 33.0, false, 2),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'HABICHUELA_CRUDA', 'M', 22.0, false, 2),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'H', 26.0, false, 3),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'M', 21.0, false, 3),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'VINAGRE', null, 2.0, false, 4),
    ('TOMATE_HABICHUELA_Y_CEBOLLA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_GUANABANA_2', 'Jugo de guanábana', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_GUANABANA_2', 'GUANABANA_CRUDA', null, 85.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CERDO_ASADO', 'Cerdo asado', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la carne de cerdo con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción.  Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CERDO_ASADO', 'CERDO_CARNE_MAGRA_CRUDA', null, 114.0, true, 1),
    ('CERDO_ASADO', 'SAL', null, 1.0, false, 2),
    ('CERDO_ASADO', 'AJO_CRUDO', null, 1.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAPA_DORADA', 'Papa dorada', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Previamente cocinar la papa en agua y aderezos; precalentar el aceite en el recipiente de dorado; pasar las papas por esté recipiente por unos minutos hasta que la papa tome un color dorado leve. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAPA_DORADA', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PAPA_DORADA', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PAPA_DORADA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_LULO_2', 'Jugo de lulo', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_LULO_2', 'LULO_CRUDO', null, 100.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ESPINACA_MANZANA_Y_MANI', 'Espinaca, manzana y maní', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ESPINACA_MANZANA_Y_MANI', 'ESPINACA_CRUDA', 'H', 83.0, true, 1),
    ('ESPINACA_MANZANA_Y_MANI', 'ESPINACA_CRUDA', 'M', 58.0, true, 1),
    ('ESPINACA_MANZANA_Y_MANI', 'MANZANA_COMUN_CRUDA', 'H', 29.0, false, 2),
    ('ESPINACA_MANZANA_Y_MANI', 'MANZANA_COMUN_CRUDA', 'M', 23.0, false, 2),
    ('ESPINACA_MANZANA_Y_MANI', 'MANI_CON_PIEL_TOSTADO_SIN_SAL', null, 5.0, false, 3),
    ('ESPINACA_MANZANA_Y_MANI', 'SAL', null, 1.0, false, 4),
    ('ESPINACA_MANZANA_Y_MANI', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'MANZANA', 'Manzana', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('MANZANA', 'MANZANA_COMUN_CRUDA', null, 82.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'QUESO_CAMPESINO', 'Queso campesino', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Porcionar y servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('QUESO_CAMPESINO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_CAMPESINO', 'H', 35.0, true, 1),
    ('QUESO_CAMPESINO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_CAMPESINO', 'M', 25.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'AREPA_ASADA', 'Arepa asada', 'PANIFICADO', 'Alistar el alimento, calentar en plancha o en horno y servir caliente de acuerdo al gramaje establecido');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('AREPA_ASADA', 'AREPA_DE_MAIZ_PRECOCIDO_CON_SAL', null, 60.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_AJIACO', 'Sopa de ajiaco', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Desinfecte las verduras, de acuerdo a lo establecido en  el Manual de Manipulación de Alimentos, pelar y picar finamente. Preparar un caldo básico con agua cebolla, cilantro ajo y sal y las vísceras. Lavar y desinfectar la papa criolla, la papa común y la arracacha y pelar. Cortar en rodajas finas la papa criolla, l');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_AJIACO', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', null, 40.0, true, 1),
    ('SOPA_DE_AJIACO', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', null, 40.0, false, 2),
    ('SOPA_DE_AJIACO', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 3),
    ('SOPA_DE_AJIACO', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPA_DE_AJIACO', 'MAIZ_AMARILLO_CRUDO', null, 50.0, false, 5),
    ('SOPA_DE_AJIACO', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPA_DE_AJIACO', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPA_DE_AJIACO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPA_DE_AJIACO', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_AJIACO', 'SAL', null, 1.0, false, 10),
    ('SOPA_DE_AJIACO', 'GUASCAS_CRUDAS', null, 2.0, false, 11)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PIERNA_DE_POLLO_DORADA', 'Pierna de pollo Dorada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Previamente cocinar la pierna en agua y aderezos; precalentar el aceite en el recipiente de dorado; pasar las piernas por esté recipiente por unos minutos hasta que la pierna tome un color dorado leve. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PIERNA_DE_POLLO_DORADA', 'POLLO_PIERNA_O_COLOMBINA_CON_PIEL_CRUDA', 'H', 135.0, true, 1),
    ('PIERNA_DE_POLLO_DORADA', 'POLLO_PIERNA_O_COLOMBINA_CON_PIEL_CRUDA', 'M', 128.0, true, 1),
    ('PIERNA_DE_POLLO_DORADA', 'SAL', null, 1.0, false, 2),
    ('PIERNA_DE_POLLO_DORADA', 'AJO_CRUDO', null, 1.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PURE_DE_PAPA_CRIOLLA', 'Puré de papa criolla', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar la papa en cubos, Agregar agua en un recipiente junto con las papas y aderezos y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; retirar agua adicionar aderezos, leche, margarina, y macerar, revolver, rectifica el sabor. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PURE_DE_PAPA_CRIOLLA', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PURE_DE_PAPA_CRIOLLA', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PURE_DE_PAPA_CRIOLLA', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 5.0, false, 2),
    ('PURE_DE_PAPA_CRIOLLA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 3),
    ('PURE_DE_PAPA_CRIOLLA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('PURE_DE_PAPA_CRIOLLA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_GUAYABA_2', 'Jugo de guayaba', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_GUAYABA_2', 'GUAYABA_MADURA_CRUDA', null, 80.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CUCHUCO_DE_TRIGO', 'Cuchuco de trigo', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar y desinfectar las verduras y la papa, de acuerdo al Manual de Manipulación de Alimentos, preparar un caldo básico con ajo sal cebolla y cilantro (una parte), adicionar a este caldo la papa, el  aceite y las vísceras, permita la cocción de estos ingredientes (mezcle frecuentemente para que se inc');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CUCHUCO_DE_TRIGO', 'CUCHUCO_DE_TRIGO_CRUDO', null, 40.0, true, 1),
    ('CUCHUCO_DE_TRIGO', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('CUCHUCO_DE_TRIGO', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('CUCHUCO_DE_TRIGO', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('CUCHUCO_DE_TRIGO', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('CUCHUCO_DE_TRIGO', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('CUCHUCO_DE_TRIGO', 'AJO_CRUDO', null, 1.0, false, 7),
    ('CUCHUCO_DE_TRIGO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('CUCHUCO_DE_TRIGO', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('CUCHUCO_DE_TRIGO', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOBREBARRIGA_GUISADA', 'Sobrebarriga Guisada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar cebolla, tomate, ajo ; sofreír estos junto con algunos aderezos que sirvan para formar un guiso y reservar. Agregar aceite en un recipiente, la carne, agua y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar agregar el guiso reservado,');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOBREBARRIGA_GUISADA', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('SOBREBARRIGA_GUISADA', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('SOBREBARRIGA_GUISADA', 'CEBOLLA_CABEZONA_CRUDA', null, 5.0, false, 2),
    ('SOBREBARRIGA_GUISADA', 'TOMATE_CRUDO', null, 6.0, false, 3),
    ('SOBREBARRIGA_GUISADA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('SOBREBARRIGA_GUISADA', 'AJO_CRUDO', null, 1.0, false, 5),
    ('SOBREBARRIGA_GUISADA', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PICO_DE_GALLO', 'Pico de gallo', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en cubos pequeños. En un recipiente mezclar todas las verduras con la sal hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PICO_DE_GALLO', 'TOMATE_CRUDO', 'H', 50.0, true, 1),
    ('PICO_DE_GALLO', 'TOMATE_CRUDO', 'M', 37.0, true, 1),
    ('PICO_DE_GALLO', 'CEBOLLA_CABEZONA_CRUDA', 'H', 42.0, false, 2),
    ('PICO_DE_GALLO', 'CEBOLLA_CABEZONA_CRUDA', 'M', 31.0, false, 2),
    ('PICO_DE_GALLO', 'CILANTRO_CRUDO', null, 2.0, false, 3),
    ('PICO_DE_GALLO', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CHIPS_PLATANO_VERDE', 'Chips plátano verde', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Cortar el plátano finamente (moneditas) y reservar. Precalentar en un recipiente aceite suficiente, adicionar el plátano previamente reservado en el aceite freír hasta obtener un color dorado y tostado. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CHIPS_PLATANO_VERDE', 'PLATANO_HARTON_VERDE_CRUDO', 'H', 148.0, true, 1),
    ('CHIPS_PLATANO_VERDE', 'PLATANO_HARTON_VERDE_CRUDO', 'M', 113.0, true, 1),
    ('CHIPS_PLATANO_VERDE', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MARACUYA_2', 'Jugo de maracuyá', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MARACUYA_2', 'MARACUYA_CRUDA', null, 187.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CAFE_CON_LECHE', 'Café con leche', 'BEBIDA_DES', 'Reconstituir la leche en agua. En una olla poner a hervir el agua, cuando alcance el punto de ebullición incorporar el café, revolver para lograr que se disuelva completamente en el agua. Adicionar la leche y endulzar con azúcar, dejar reposar. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CAFE_CON_LECHE', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, true, 1),
    ('CAFE_CON_LECHE', 'CAFE_SOLUBLE_EN_POLVO', null, 5.0, false, 2),
    ('CAFE_CON_LECHE', 'AZUCAR_BLANCO_GRANULADO', null, 10.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPAS_DE_FIDEOS', 'Sopas de fideos', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar y desinfectar las verduras y la papa , de acuerdo al Manual de manipulación de Alimentos. Aparte coloque una olla prepare un caldo básico con ajo sal cebolla y cilantro (una parte) y las vísceras, adicione a este caldo la papa y el aceite, cuando rompa el hervor adicione la pasta, deje cocer ant');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPAS_DE_FIDEOS', 'PASTA_ALIMENTICIA_ENRIQUECIDA_CRUDA', null, 40.0, true, 1),
    ('SOPAS_DE_FIDEOS', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPAS_DE_FIDEOS', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPAS_DE_FIDEOS', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPAS_DE_FIDEOS', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPAS_DE_FIDEOS', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPAS_DE_FIDEOS', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPAS_DE_FIDEOS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPAS_DE_FIDEOS', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPAS_DE_FIDEOS', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BAGRE_APANADO', 'Bagre apanado', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En un recipiente colocar la harina de trigo con los aderezos al gusto, adicionar huevo batido y leche y miga de pan y reservar. Precalentar en un recipiente aceite suficiente, mezclar el bagre con la pre mezcla reservada y adicionar al aceite para freír el bagre. Servir caliente de acuerdo al gramaje establec');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BAGRE_APANADO', 'BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'H', 126.0, true, 1),
    ('BAGRE_APANADO', 'BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'M', 116.0, true, 1),
    ('BAGRE_APANADO', 'HARINA_DE_TRIGO_FORTIFICADA_TODO_PROPOSITO_CRUDA', null, 10.0, false, 2),
    ('BAGRE_APANADO', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 5.0, false, 3),
    ('BAGRE_APANADO', 'SAL', null, 1.0, false, 4),
    ('BAGRE_APANADO', 'AJO_CRUDO', null, 1.0, false, 5),
    ('BAGRE_APANADO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 2.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TOMATE_ZANAHORIA_Y_CEBOLLA', 'Tomate, zanahoria y cebolla', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. Picar finamente el cilantro. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'TOMATE_CRUDO', 'H', 31.0, true, 1),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'TOMATE_CRUDO', 'M', 25.0, true, 1),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 35.0, false, 2),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 23.0, false, 2),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'H', 26.0, false, 3),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'M', 21.0, false, 3),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'CILANTRO_CRUDO', null, 1.0, false, 4),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'SAL', null, 1.0, false, 5),
    ('TOMATE_ZANAHORIA_Y_CEBOLLA', 'VINAGRE', null, 2.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAPAS_CHORREADAS', 'Papas chorreadas', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla; previamente sofreír algunos aderezos por unos minutos agregar leche y reservar. En un recipiente agregar agua suficiente en un recipiente junto con las papas y cocinar hasta que todo esté blando; para finalizar retirar agua, adicionar la preparación');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAPAS_CHORREADAS', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PAPAS_CHORREADAS', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PAPAS_CHORREADAS', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 2.0, false, 2),
    ('PAPAS_CHORREADAS', 'TOMATE_CRUDO', null, 2.0, false, 3),
    ('PAPAS_CHORREADAS', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('PAPAS_CHORREADAS', 'AJO_CRUDO', null, 1.0, false, 5),
    ('PAPAS_CHORREADAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'JUGO_DE_MANGO', 'Jugo de mango', 'JUGO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar, pelar y cortar en trozos. En una licuadora agregar ¾ del agua medida y la fruta de día, licuar hasta homogeneizar, retirar y colar en una jarra y llevar a refrigeración. Antes de servir, licuar en el agua restante el azúcar y mezclar hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('JUGO_DE_MANGO', 'MANGO_COMUN_CRUDO', null, 120.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CAZUELA_DE_FRIJOL', 'Cazuela de frijol', 'SOPA', 'Dejar el día anterior los frijoles en remojo, desechar el agua del remojo. Lavar, pelar y picar el plátano hartón, lave y desinfecte las verduras de acuerdo al Manual de Manipulación de Alimentos. En una olla preparar un caldo básico con ajo, sal, cebolla y las vísceras, adicionar a este caldo los frijoles y el plátano, deje que hiervan suficiente, adicione el plátano continúe la cocción. Sirva de');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CAZUELA_DE_FRIJOL', 'FRIJOL_BOLA_ROJA_CRUDO', null, 60.0, true, 1),
    ('CAZUELA_DE_FRIJOL', 'PLATANO_HARTON_VERDE_CRUDO', null, 36.0, false, 2),
    ('CAZUELA_DE_FRIJOL', 'TOMATE_CRUDO', null, 2.0, false, 3),
    ('CAZUELA_DE_FRIJOL', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 4),
    ('CAZUELA_DE_FRIJOL', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 5),
    ('CAZUELA_DE_FRIJOL', 'AJO_CRUDO', null, 1.0, false, 6),
    ('CAZUELA_DE_FRIJOL', 'SAL', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'GUACAMOLE', 'Guacamole', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar finamente en las verduras. En un recipiente mezclar todas las verduras con la sal y el zumo de limón hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('GUACAMOLE', 'AGUACATE_LORENA_CRUDO', 'H', 77.0, true, 1),
    ('GUACAMOLE', 'AGUACATE_LORENA_CRUDO', 'M', 64.0, true, 1),
    ('GUACAMOLE', 'CEBOLLA_CABEZONA_CRUDA', 'H', 10.0, false, 2),
    ('GUACAMOLE', 'CEBOLLA_CABEZONA_CRUDA', 'M', 5.0, false, 2),
    ('GUACAMOLE', 'TOMATE_CRUDO', 'H', 12.0, false, 3),
    ('GUACAMOLE', 'TOMATE_CRUDO', 'M', 6.0, false, 3),
    ('GUACAMOLE', 'CILANTRO_CRUDO', null, 2.0, false, 4),
    ('GUACAMOLE', 'LIMON_CRUDO', null, 2.0, false, 5),
    ('GUACAMOLE', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'MANGO', 'Mango', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('MANGO', 'MANGO_COMUN_CRUDO', null, 140.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'COLADA_DE_PLATANO', 'Colada de plátano', 'BEBIDA_DES', 'Reconstituir la leche en agua. En una olla colocar el agua, canela con el azúcar y poner a hervir, a continuación agregar la colada de plátano previamente disuelta, remueva constantemente con una cuchara o cucharón para que no se pegue, cocine a fuego medio e incorporar la leche. Retire del fuego, dejar reposar evitando la formación de natas. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('COLADA_DE_PLATANO', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 18.0, true, 1),
    ('COLADA_DE_PLATANO', 'HARINA_DE_PLATANO_CRUDA', null, 12.0, false, 2),
    ('COLADA_DE_PLATANO', 'ESPECIAS_DE_ASTILLAS_DE_CANELA', null, 1.0, false, 3),
    ('COLADA_DE_PLATANO', 'AZUCAR_BLANCO_GRANULADO', null, 10.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'REPOLLO_TOMATE_Y_PEPINO', 'Repollo, tomate y pepino', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar.  Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('REPOLLO_TOMATE_Y_PEPINO', 'TOMATE_CRUDO', 'H', 31.0, true, 1),
    ('REPOLLO_TOMATE_Y_PEPINO', 'TOMATE_CRUDO', 'M', 25.0, true, 1),
    ('REPOLLO_TOMATE_Y_PEPINO', 'REPOLLO_MORADO_CRUDO', 'H', 35.0, false, 2),
    ('REPOLLO_TOMATE_Y_PEPINO', 'REPOLLO_MORADO_CRUDO', 'M', 23.0, false, 2),
    ('REPOLLO_TOMATE_Y_PEPINO', 'PEPINO_COHOMBRO_CRUDO', 'H', 33.0, false, 3),
    ('REPOLLO_TOMATE_Y_PEPINO', 'PEPINO_COHOMBRO_CRUDO', 'M', 26.0, false, 3),
    ('REPOLLO_TOMATE_Y_PEPINO', 'SAL', null, 1.0, false, 4),
    ('REPOLLO_TOMATE_Y_PEPINO', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'YUCA_CON_HOGAO', 'Yuca con hogao', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla; previamente sofreír algunos aderezos por unos minutos y reservar. En un recipiente agregar agua suficiente en un recipiente junto con la yuca y cocinar hasta que todo esté blando; para finalizar retirar agua, adicionar la preparación reservada, revo');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('YUCA_CON_HOGAO', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', 'H', 126.0, true, 1),
    ('YUCA_CON_HOGAO', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', 'M', 96.0, true, 1),
    ('YUCA_CON_HOGAO', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 2.0, false, 2),
    ('YUCA_CON_HOGAO', 'TOMATE_CRUDO', null, 2.0, false, 3),
    ('YUCA_CON_HOGAO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('YUCA_CON_HOGAO', 'AJO_CRUDO', null, 1.0, false, 5),
    ('YUCA_CON_HOGAO', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_SANCOCHO', 'Sopa de sancocho', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Desinfectar las verduras, de acuerdo al Manual de Manipulación de Alimentos, pelar cortar y picar finamente. Lavar y pelar el plátano, la yuca y la papa. Tajar la papa, y la yuca. Rallar el plátano coli, la papa y el plátano hartón, cortar en trozos grandes de acuerdo al gramaje establecido. Poner en una olla agua y');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_SANCOCHO', 'PLATANO_HARTON_VERDE_CRUDO', null, 44.0, true, 1),
    ('SOPA_DE_SANCOCHO', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', null, 37.0, false, 2),
    ('SOPA_DE_SANCOCHO', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 3),
    ('SOPA_DE_SANCOCHO', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 4),
    ('SOPA_DE_SANCOCHO', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 5),
    ('SOPA_DE_SANCOCHO', 'HABICHUELA_CRUDA', null, 55.0, false, 6),
    ('SOPA_DE_SANCOCHO', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 7),
    ('SOPA_DE_SANCOCHO', 'AJO_CRUDO', null, 1.0, false, 8),
    ('SOPA_DE_SANCOCHO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 9),
    ('SOPA_DE_SANCOCHO', 'CILANTRO_CRUDO', null, 1.0, false, 10),
    ('SOPA_DE_SANCOCHO', 'SAL', null, 1.0, false, 11)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TILAPIA_FINAS_HIERBAS', 'Tilapia  finas hierbas', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la tilapia con una capa fina de aceite y aderezos; colocar en la plancha agregando perejil finamente picado finalizando la cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TILAPIA_FINAS_HIERBAS', 'TILAPIA_O_MOJARRA_FILETE_CRUDA', 'H', 110.0, true, 1),
    ('TILAPIA_FINAS_HIERBAS', 'TILAPIA_O_MOJARRA_FILETE_CRUDA', 'M', 103.0, true, 1),
    ('TILAPIA_FINAS_HIERBAS', 'PEREJIL_CRUDO', null, 1.0, false, 2),
    ('TILAPIA_FINAS_HIERBAS', 'ESPECIAS_DE_ROMERO_SECO', null, 1.0, false, 3),
    ('TILAPIA_FINAS_HIERBAS', 'ESPECIAS_DE_TOMILLO_SECO', null, 1.0, false, 4),
    ('TILAPIA_FINAS_HIERBAS', 'AJO_CRUDO', null, 1.0, false, 5),
    ('TILAPIA_FINAS_HIERBAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CRIOLLA_DORADA', 'Criolla dorada', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Servir caliente de acuerdo al gramaje establecido. Previamente cocinar la papa criolla en agua y aderezos; precalentar el aceite en el recipiente de dorado; pasar las papas criollas por esté recipiente por unos minutos hasta que la papa criolla tome un color dorado leve. Servir caliente de acuerdo al gramaje ');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CRIOLLA_DORADA', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('CRIOLLA_DORADA', 'PAPA_VARIEDAD_HARINOSA_CRIOLLA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('CRIOLLA_DORADA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FILETE_DE_BAGRE_FINAS_HIERBAS', 'Filete de Bagre finas hierbas', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir el bagre con una capa fina de aceite y aderezos; colocar en la plancha agregando perejil finamente picado finalizando la cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'BAGRE_MAGRO_FILETE_CRUDO', 'H', 110.0, true, 1),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'BAGRE_MAGRO_FILETE_CRUDO', 'M', 102.0, true, 1),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'PEREJIL_CRUDO', null, 1.0, false, 2),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'ESPECIAS_DE_ROMERO_SECO', null, 1.0, false, 3),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'ESPECIAS_DE_TOMILLO_SECO', null, 1.0, false, 4),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'AJO_CRUDO', null, 1.0, false, 5),
    ('FILETE_DE_BAGRE_FINAS_HIERBAS', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'MANDARINA', 'Mandarina', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('MANDARINA', 'MANDARINA_CRUDA', null, 100.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'HUEVOS_REVUELTOS', 'Huevos revueltos', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En un tazón batir los huevos, sal y pimienta. Por otro lado, en una sartén calentar el aceite a fuego medio, añadir los huevos y cocinar a fuego medio, sin revolver, hasta que la mezcla comienza a secarse. Dejar cocinar y revolver ocasionalmente hasta que los huevos tengan consistencia y servir caliente de ac');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('HUEVOS_REVUELTOS', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', null, 55.0, true, 1),
    ('HUEVOS_REVUELTOS', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPAS_DE_ARROZ', 'Sopas de arroz', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar y desinfectar las verduras y la papa , de acuerdo al Manual de manipulación de Alimentos. Aparte coloque una olla prepare un caldo básico con ajo sal cebolla, cilantro (una parte) y las vísceras, adicione a este caldo la papa y el aceite, cuando rompa el hervor adicione el arroz de sopa, deje co');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPAS_DE_ARROZ', 'ARROZ_BLANCO_PULIDO_CRUDO', null, 40.0, true, 1),
    ('SOPAS_DE_ARROZ', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPAS_DE_ARROZ', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPAS_DE_ARROZ', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPAS_DE_ARROZ', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPAS_DE_ARROZ', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPAS_DE_ARROZ', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPAS_DE_ARROZ', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPAS_DE_ARROZ', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPAS_DE_ARROZ', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CERDO_A_LA_CRIOLLA', 'Cerdo a la criolla', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos; Picar el tomate, la cebolla, ajo, cilantro y aderezos; Agregar aceite en un recipiente sofreír los ingredientes anteriores y reservar. Precalentar la plancha; previamente cubrir la carne de cerdo con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción, al final de esta cocción agregar e');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CERDO_A_LA_CRIOLLA', 'CERDO_CARNE_MAGRA_CRUDA', null, 114.0, true, 1),
    ('CERDO_A_LA_CRIOLLA', 'TOMATE_CRUDO', null, 6.0, false, 2),
    ('CERDO_A_LA_CRIOLLA', 'CEBOLLA_CABEZONA_CRUDA', null, 5.0, false, 3),
    ('CERDO_A_LA_CRIOLLA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('CERDO_A_LA_CRIOLLA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PATACON_DE_PLATANO_VERDE', 'Patacón de plátano verde', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Cortar el plátano con un grosor adecuado y reservar. Precalentar en un recipiente aceite suficiente, adicionar el plátano previamente reservado, dorarlo inicialmente por ambos lados y retirar del aceite, en una superficie plana aplicar presión hasta obtener la forma de patacón y de inmediato agregarlo al acei');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PATACON_DE_PLATANO_VERDE', 'PLATANO_HARTON_VERDE_CRUDO', 'H', 148.0, true, 1),
    ('PATACON_DE_PLATANO_VERDE', 'PLATANO_HARTON_VERDE_CRUDO', 'M', 113.0, true, 1),
    ('PATACON_DE_PLATANO_VERDE', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TOMATE_Y_CEBOLLA', 'Tomate y cebolla', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos; Picar el tomate, la cebolla, cilantro y aderezos; Agregar aceite en un recipiente sofreír los ingredientes anteriores y reservar. Precalentar la plancha; previamente cubrir la carne de cerdo con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción, al final de esta cocción agregar el sof');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TOMATE_Y_CEBOLLA', 'TOMATE_CRUDO', 'H', 50.0, true, 1),
    ('TOMATE_Y_CEBOLLA', 'TOMATE_CRUDO', 'M', 37.0, true, 1),
    ('TOMATE_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'H', 42.0, false, 2),
    ('TOMATE_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'M', 31.0, false, 2),
    ('TOMATE_Y_CEBOLLA', 'CILANTRO_CRUDO', null, 1.0, false, 3),
    ('TOMATE_Y_CEBOLLA', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PECHUGA_A_LA_CRIOLLA', 'Pechuga a la criolla', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla, ajo y cilantro; previamente sofreír algunos aderezos por unos minutos. Agregar aceite en un recipiente y el sofrito anterior, el tomate, la cebolla, ajo, la pechuga, agua y deja cocinar revolviendo de vez en cuando hasta que todo esté blando; para f');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PECHUGA_A_LA_CRIOLLA', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'H', 126.0, true, 1),
    ('PECHUGA_A_LA_CRIOLLA', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'M', 112.0, true, 1),
    ('PECHUGA_A_LA_CRIOLLA', 'TOMATE_CRUDO', null, 6.0, false, 2),
    ('PECHUGA_A_LA_CRIOLLA', 'CEBOLLA_CABEZONA_CRUDA', null, 5.0, false, 3),
    ('PECHUGA_A_LA_CRIOLLA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('PECHUGA_A_LA_CRIOLLA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ARROZ_CON_FIDEOS', 'Arroz con fideos', 'CEREAL', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar el arroz con abundante agua y dejar escurrir. En una olla sofreír el ajo, sal, cebolla finamente picada y fideos a fuego medio hasta que los fideos queden dorados, a continuación, añadir el arroz revolver hasta mezclar los ingredientes, añadir el agua y cocinar a fuego alto hasta que el agua se evapore,');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ARROZ_CON_FIDEOS', 'ARROZ_BLANCO_PULIDO_CRUDO', 'H', 74.0, true, 1),
    ('ARROZ_CON_FIDEOS', 'ARROZ_BLANCO_PULIDO_CRUDO', 'M', 69.0, true, 1),
    ('ARROZ_CON_FIDEOS', 'PASTA_ALIMENTICIA_ENRIQUECIDA_CRUDA', null, 5.0, false, 2),
    ('ARROZ_CON_FIDEOS', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 3),
    ('ARROZ_CON_FIDEOS', 'AJO_CRUDO', null, 1.0, false, 4),
    ('ARROZ_CON_FIDEOS', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'TAJADAS_PLATANO_MADURO', 'Tajadas plátano maduro', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Cortar el plátano en tajadas y reservar. Precalentar en un recipiente aceite suficiente, adicionar el plátano previamente reservado en el aceite freír hasta obtener un color dorado y tostado. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('TAJADAS_PLATANO_MADURO', 'PLATANO_HARTON_MADURO_CRUDO', 'H', 140.0, true, 1),
    ('TAJADAS_PLATANO_MADURO', 'PLATANO_HARTON_MADURO_CRUDO', 'M', 106.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CALDO_DE_PAPA_Y_HUEVO', 'Caldo de papa y huevo', 'SOPA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En una olla sofreír el ajo, a continuación, poner el agua con unas ramas de cebolla junca, tallos de cilantro, sal y papas, cocinar a fuego medio hasta que la papa este cocinada. Retirar los tallos cilantro y las ramas de cebolla. Agregar el huevo con mucho cuidado para no romperlo, se deja hasta que cocine e');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CALDO_DE_PAPA_Y_HUEVO', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', null, 55.0, true, 1),
    ('CALDO_DE_PAPA_Y_HUEVO', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 100.0, false, 2),
    ('CALDO_DE_PAPA_Y_HUEVO', 'AJO_CRUDO', null, 1.0, false, 3),
    ('CALDO_DE_PAPA_Y_HUEVO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('CALDO_DE_PAPA_Y_HUEVO', 'CILANTRO_CRUDO', null, 1.0, false, 5),
    ('CALDO_DE_PAPA_Y_HUEVO', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_MUTE', 'Sopa de mute', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lave, pele y pique y desinfecte las verduras, taje la papa, (el plátano hartón y la yuca rállelos) de acuerdo al protocolo establecido en cada servicio de alimentación. Aparte coloque una olla prepare un caldo básico con ajo sal cebolla, cilantro (una parte) y las vísceras, adicione a este caldo la papa, el aceite, ');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_MUTE', 'MAIZ_MUTE_COCIDO_SIN_SAL', null, 40.0, true, 1),
    ('SOPA_DE_MUTE', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPA_DE_MUTE', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPA_DE_MUTE', 'PLATANO_HARTON_VERDE_CRUDO', null, 14.0, false, 4),
    ('SOPA_DE_MUTE', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', null, 12.0, false, 5),
    ('SOPA_DE_MUTE', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 6),
    ('SOPA_DE_MUTE', 'HABICHUELA_CRUDA', null, 55.0, false, 7),
    ('SOPA_DE_MUTE', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 8),
    ('SOPA_DE_MUTE', 'AJO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_MUTE', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 10),
    ('SOPA_DE_MUTE', 'CILANTRO_CRUDO', null, 1.0, false, 11),
    ('SOPA_DE_MUTE', 'SAL', null, 1.0, false, 12)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PLATANO_COCIDO', 'Plátano cocido', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar el plátano en cortas gruesos, Agregar agua en un recipiente junto con el plátano y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar retirar agua. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PLATANO_COCIDO', 'PLATANO_HARTON_MADURO_CRUDO', 'H', 140.0, true, 1),
    ('PLATANO_COCIDO', 'PLATANO_HARTON_MADURO_CRUDO', 'M', 106.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'RES_AL_PIMENTON', 'Res al pimentón', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el pimentón; Previamente sofreír algunos aderezos por unos minutos. Agregar aceite en un recipiente y el sofrito anterior, la carne, agua y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para finalizar agregar  el pimentón, revolver, dejar cocinar');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('RES_AL_PIMENTON', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('RES_AL_PIMENTON', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('RES_AL_PIMENTON', 'PIMENTON_ROJO_CRUDO', null, 11.0, false, 2),
    ('RES_AL_PIMENTON', 'AJO_CRUDO', null, 1.0, false, 3),
    ('RES_AL_PIMENTON', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'NARANJA', 'Naranja', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('NARANJA', 'NARANJA_CRUDA', null, 116.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'REPOLLO_TOMATE_Y_MANZANA', 'Repollo, tomate y manzana', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño pequeño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar.  Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('REPOLLO_TOMATE_Y_MANZANA', 'TOMATE_CRUDO', 'H', 31.0, true, 1),
    ('REPOLLO_TOMATE_Y_MANZANA', 'TOMATE_CRUDO', 'M', 25.0, true, 1),
    ('REPOLLO_TOMATE_Y_MANZANA', 'REPOLLO_MORADO_CRUDO', 'H', 35.0, false, 2),
    ('REPOLLO_TOMATE_Y_MANZANA', 'REPOLLO_MORADO_CRUDO', 'M', 23.0, false, 2),
    ('REPOLLO_TOMATE_Y_MANZANA', 'MANZANA_COMUN_CRUDA', 'H', 29.0, false, 3),
    ('REPOLLO_TOMATE_Y_MANZANA', 'MANZANA_COMUN_CRUDA', 'M', 23.0, false, 3),
    ('REPOLLO_TOMATE_Y_MANZANA', 'VINAGRE', null, 2.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'AGUA_DE_PANELA_EN_LECHE', 'Agua de panela en leche', 'BEBIDA_DES', 'Reconstituir la leche en agua (cuando se utilice leche en polvo). Colocar en una olla el agua, adicionar la panela y dejar que rompa hervor y que se cocine, retire del fuego incorporar la leche disuelta la cual se debe de haber conservado a temperatura media, dejar reposar unos minutos. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('AGUA_DE_PANELA_EN_LECHE', 'PANELA', null, 12.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'RES_ASADA', 'Res asada', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la carne de res con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('RES_ASADA', 'RES_CARNE_MAGRA_CRUDA', 'H', 111.0, true, 1),
    ('RES_ASADA', 'RES_CARNE_MAGRA_CRUDA', 'M', 103.0, true, 1),
    ('RES_ASADA', 'AJO_CRUDO', null, 1.0, false, 2),
    ('RES_ASADA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 2.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CERDO_FRITO', 'Cerdo frito', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Precalentar la plancha; previamente cubrir la carne de cerdo con una capa fina de aceite y aderezos; colocar en la plancha hasta su cocción. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CERDO_FRITO', 'CERDO_CARNE_MAGRA_CRUDA', null, 114.0, true, 1),
    ('CERDO_FRITO', 'SAL', null, 1.0, false, 2),
    ('CERDO_FRITO', 'AJO_CRUDO', null, 1.0, false, 3)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'COCIDO_HABICHUELA_Y_ZANAHORIA', 'Cocido habichuela y zanahoria', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar finamente el tomate y cebolla, la zanahoria y habichuela en cubos pequeños. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir las habichuelas y dejar cocinar hasta que adquieran un color verde brillante. Sacar del agua caliente y en un recipiente sumergir en agua');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'HABICHUELA_CRUDA', 'H', 44.0, true, 1),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'HABICHUELA_CRUDA', 'M', 33.0, true, 1),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 47.0, false, 2),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 35.0, false, 2),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 5.0, false, 3),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'TOMATE_CRUDO', null, 2.0, false, 4),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'AJO_CRUDO', null, 1.0, false, 5),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 6),
    ('COCIDO_HABICHUELA_Y_ZANAHORIA', 'SAL', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PURE_DE_PAPA', 'Puré de papa', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar la papa en cubos, Agregar agua en un recipiente junto con las papas y aderezos y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; retirar agua adicionar aderezos, leche , margarina, y macerar, revolver, rectifica el sabor. Servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PURE_DE_PAPA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PURE_DE_PAPA', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PURE_DE_PAPA', 'LECHE_DE_VACA_ENTERA_EN_POLVO', null, 5.0, false, 2),
    ('PURE_DE_PAPA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 3),
    ('PURE_DE_PAPA', 'AJO_CRUDO', null, 1.0, false, 4),
    ('PURE_DE_PAPA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_COLI', 'Sopa de coli', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo, desechar el agua del remojo. Lavar, pelar y picar, desinfecte las verduras, de acuerdo al Manual de manipulación de alimentos. Lavar y pelar el plátano Coli, y la papa. Tajar la papa, cortar en trozos el plátano coli y rallar una parte. Poner en una olla agua y preparar un caldo básico con el ajo, la cebolla y una parte del cilantro, aceite y v');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_COLI', 'PLATANO_COLI_O_GUINEO_VERDE_CRUDO', null, 100.0, true, 1),
    ('SOPA_DE_COLI', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 2),
    ('SOPA_DE_COLI', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 3),
    ('SOPA_DE_COLI', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 4),
    ('SOPA_DE_COLI', 'HABICHUELA_CRUDA', null, 55.0, false, 5),
    ('SOPA_DE_COLI', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 6),
    ('SOPA_DE_COLI', 'AJO_CRUDO', null, 1.0, false, 7),
    ('SOPA_DE_COLI', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 8),
    ('SOPA_DE_COLI', 'CILANTRO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_COLI', 'SAL', null, 1.0, false, 10)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'LECHUGA_MAIZ_Y_ZANAHORIA', 'Lechuga, maíz y zanahoria', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 29.0, true, 1),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 23.0, true, 1),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'MAIZ_AMARILLO_CRUDO', 'H', 25.0, false, 2),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'MAIZ_AMARILLO_CRUDO', 'M', 20.0, false, 2),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'LECHUGA_COMUN_CRUDA', 'H', 54.0, false, 3),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'LECHUGA_COMUN_CRUDA', 'M', 36.0, false, 3),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'SAL', null, 1.0, false, 4),
    ('LECHUGA_MAIZ_Y_ZANAHORIA', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'VERDURA_SALTEADA', 'Verdura salteada', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('VERDURA_SALTEADA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 23.0, true, 1),
    ('VERDURA_SALTEADA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 17.0, true, 1),
    ('VERDURA_SALTEADA', 'PIMENTON_ROJO_CRUDO', 'H', 23.0, false, 2),
    ('VERDURA_SALTEADA', 'PIMENTON_ROJO_CRUDO', 'M', 17.0, false, 2),
    ('VERDURA_SALTEADA', 'PIMENTON_VERDE_CRUDO', 'H', 25.0, false, 3),
    ('VERDURA_SALTEADA', 'PIMENTON_VERDE_CRUDO', 'M', 18.0, false, 3),
    ('VERDURA_SALTEADA', 'CEBOLLA_CABEZONA_CRUDA', 'H', 21.0, false, 4),
    ('VERDURA_SALTEADA', 'CEBOLLA_CABEZONA_CRUDA', 'M', 15.0, false, 4),
    ('VERDURA_SALTEADA', 'BEBIDA_VEGETAL_DE_SOYA_LIQUIDA_SIN_AZUCAR', null, 5.0, false, 5),
    ('VERDURA_SALTEADA', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 6),
    ('VERDURA_SALTEADA', 'AJO_CRUDO', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ARROZ_CON_PIMENTON', 'Arroz con pimentón', 'CEREAL', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Lavar el arroz con abundante agua y dejar escurrir. En una olla sofreír el ajo, sal, achote en polvo, cebolla y pimentón finamente picados a fuego medio, a continuación, añadir el arroz revolver hasta mezclar los ingredientes, añadir el agua y cocinar a fuego alto hasta que el agua se evapore, pasar a fuego l');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ARROZ_CON_PIMENTON', 'ARROZ_BLANCO_PULIDO_CRUDO', 'H', 74.0, true, 1),
    ('ARROZ_CON_PIMENTON', 'ARROZ_BLANCO_PULIDO_CRUDO', 'M', 69.0, true, 1),
    ('ARROZ_CON_PIMENTON', 'PIMENTON_ROJO_CRUDO', null, 11.0, false, 2),
    ('ARROZ_CON_PIMENTON', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 3),
    ('ARROZ_CON_PIMENTON', 'AJO_CRUDO', null, 1.0, false, 4),
    ('ARROZ_CON_PIMENTON', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'FILETE_DE_BAGRE_SUDADO', 'Filete de bagre sudado', 'PROTEICO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar y lavar los ingredientes; Picar el tomate, la cebolla, ajo y cilantro; previamente sofreír algunos aderezos por unos minutos. Agregar aceite en un recipiente y el sofrito anterior, el tomate, la cebolla, ajo, el bagre, agua y deja cocinar revolviendo de vez en cuando o hasta que todo esté blando; para f');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('FILETE_DE_BAGRE_SUDADO', 'BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'H', 126.0, true, 1),
    ('FILETE_DE_BAGRE_SUDADO', 'BAGRE_MAGRO_SIN_CABEZA_CRUDO', 'M', 116.0, true, 1),
    ('FILETE_DE_BAGRE_SUDADO', 'AJO_CRUDO', null, 1.0, false, 2),
    ('FILETE_DE_BAGRE_SUDADO', 'CEBOLLA_CABEZONA_CRUDA', null, 5.0, false, 3),
    ('FILETE_DE_BAGRE_SUDADO', 'TOMATE_CRUDO', null, 6.0, false, 4),
    ('FILETE_DE_BAGRE_SUDADO', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ARROZ_CON_COCO', 'Arroz con coco', 'CEREAL', 'Separar la pulpa de la cáscara del coco, colocándolo en una sartén caliente (el propósito es que el calor ayude despegarla), posteriormente cortar o rallar la pulpa del coco. En una licuadora, poner la pula de coco con un poco de agua tibia, cuando el coco esté completamente licuado, colarlo para obtener la leche de coco. Reservar la ralladura del coco. En una olla, verter la leche de coco llévala');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ARROZ_CON_COCO', 'ARROZ_BLANCO_PULIDO_CRUDO', 'H', 74.0, true, 1),
    ('ARROZ_CON_COCO', 'ARROZ_BLANCO_PULIDO_CRUDO', 'M', 69.0, true, 1),
    ('ARROZ_CON_COCO', 'COCO_CRUDO', null, 22.0, false, 2),
    ('ARROZ_CON_COCO', 'AZUCAR_BLANCO_GRANULADO', null, 2.0, false, 3),
    ('ARROZ_CON_COCO', 'SAL', null, 1.0, false, 4)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SOPA_DE_GUANDUL', 'Sopa de guandul', 'SOPA', 'Dejar el día anterior la arveja verde seca en remojo y el guandul, desechar el agua del remojo. Lavar, pelar y picar el plátano hartón, ñame, la yuca, la papa y la zanahoria; lave y desinfecte las verduras de acuerdo al Manual de Manipulación de Alimentos. En una olla preparar un caldo básico con ajo, sal, cebolla, cilantro y las vísceras, adicionar a este caldo los frijoles y el aceite, deje que ');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SOPA_DE_GUANDUL', 'FRIJOL_GUANDUL_CRUDO', null, 20.0, true, 1),
    ('SOPA_DE_GUANDUL', 'PLATANO_HARTON_VERDE_CRUDO', null, 29.0, false, 2),
    ('SOPA_DE_GUANDUL', 'NAME_CON_CASCARA_CRUDO', null, 20.0, false, 3),
    ('SOPA_DE_GUANDUL', 'YUCA_BLANCA_SIN_CASCARA_CRUDA', null, 25.0, false, 4),
    ('SOPA_DE_GUANDUL', 'ARVEJA_SECA_CRUDA', null, 10.0, false, 5),
    ('SOPA_DE_GUANDUL', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 40.0, false, 6),
    ('SOPA_DE_GUANDUL', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 58.0, false, 7),
    ('SOPA_DE_GUANDUL', 'POLLO_HIGADO_CRUDO', null, 10.0, false, 8),
    ('SOPA_DE_GUANDUL', 'AJO_CRUDO', null, 1.0, false, 9),
    ('SOPA_DE_GUANDUL', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 10),
    ('SOPA_DE_GUANDUL', 'CILANTRO_CRUDO', null, 1.0, false, 11),
    ('SOPA_DE_GUANDUL', 'SAL', null, 1.0, false, 12)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CALDO_DE_PAPA_Y_POLLO', 'Caldo de papa y pollo', 'SOPA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar las papas, lavarlas y cortarlas en trozos (reservar con agua).  Retirar la piel y grasa del pollo (porcionar de ser necesario). En una olla sofreír el ajo, a continuación, poner el agua con unas ramas de cebolla y tallos de cilantro, sal y pollo, cocinar a fuego medio hasta que el pollo este blando, aña');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CALDO_DE_PAPA_Y_POLLO', 'POLLO_PECHUGA_CON_PIEL_CRUDA', null, 45.0, true, 1),
    ('CALDO_DE_PAPA_Y_POLLO', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 100.0, false, 2),
    ('CALDO_DE_PAPA_Y_POLLO', 'AJO_CRUDO', null, 1.0, false, 3),
    ('CALDO_DE_PAPA_Y_POLLO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('CALDO_DE_PAPA_Y_POLLO', 'CILANTRO_CRUDO', null, 1.0, false, 5),
    ('CALDO_DE_PAPA_Y_POLLO', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'BANANO', 'Banano', 'FRUTA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Alistar el alimento (porcionar de ser necesario) y servir el gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('BANANO', 'BANANO_COMUN_CRUDO', null, 100.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'QUESO_COSTENO', 'Queso costeño', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('QUESO_COSTENO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_COSTENO', 'H', 35.0, true, 1),
    ('QUESO_COSTENO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_COSTENO', 'M', 25.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'ENVUELTO', 'Envuelto', 'PANIFICADO', 'Porcionar y servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('ENVUELTO', 'ENVUELTO_DE_MAZORCA_PRECOCIDO', null, 60.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'MOTE_DE_QUESO', 'Mote de queso', 'SOPA', 'Lave y desinfecte el ñame y las verduras dos o tres veces de acuerdo al Manual de Manipulación de Alimentos. hervir agua en una olla y empezar a cortar el ñame para así pelarlo. Una vez tenga pelados los pedazos de ñame, licuar. Cocinar esta mezcla junto con el ajo y las cebollas, Agregar zumo de limón a la preparación lista para servir junto con el queso costeño en cubos. Servir caliente de acuer');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('MOTE_DE_QUESO', 'NAME_CON_CASCARA_CRUDO', null, 100.0, true, 1),
    ('MOTE_DE_QUESO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO_TIPO_COSTENO', null, 35.0, false, 2),
    ('MOTE_DE_QUESO', 'AJO_CRUDO', null, 1.0, false, 3),
    ('MOTE_DE_QUESO', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('MOTE_DE_QUESO', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PIMENTON_ZANAHORIA_Y_CEBOLLA', 'Pimentón, zanahoria y cebolla', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar.  Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'H', 31.0, true, 1),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', 'M', 21.0, true, 1),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'PIMENTON_ROJO_CRUDO', 'H', 11.0, false, 2),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'PIMENTON_ROJO_CRUDO', 'M', 5.0, false, 2),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 47.0, false, 3),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 41.0, false, 3),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'SAL', null, 1.0, false, 4),
    ('PIMENTON_ZANAHORIA_Y_CEBOLLA', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'HUEVO_FRITO', 'Huevo frito', 'PROTEICO_DES', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. En una sartén calentar el aceite a fuego medio, añadir el huevo, retirar cuando este cocida la yema, agregar sal y servir caliente de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('HUEVO_FRITO', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', null, 55.0, true, 1),
    ('HUEVO_FRITO', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'PAPA_FRITA', 'Papa frita', 'TUBERCULO', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Cortar la papa tipo francesa con un grosor adecuado y homogéneo, reservar. Precalentar en un recipiente aceite suficiente, adicionar la papa previamente reservado, adicionar el papa previamente reservada en el aceite freír hasta obtener un color dorado y tostado. Servir caliente de acuerdo al gramaje establec');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('PAPA_FRITA', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'H', 101.0, true, 1),
    ('PAPA_FRITA', 'PAPA_VARIEDAD_CEROSA_SABANERA_CON_CASCARA_CRUDA', 'M', 78.0, true, 1),
    ('PAPA_FRITA', 'SAL', null, 1.0, false, 2)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CALDO_DE_PAPA_Y_CARNE', 'Caldo de papa y carne', 'SOPA', 'Seguir el procedimiento de lavado y desinfección de la guía de manipulación de alimentos. Pelar las papas, lavarlas y cortarlas en cuadros (reservar con agua).  Lavar y porcionar la carne. En una olla sofreír el ajo, a continuación, poner el agua con unas ramas de cebolla y tallos de cilantro, sal y la carne, cocinar a fuego medio hasta que la carne este blanda, añadir la papa cortada.  Dejar al f');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CALDO_DE_PAPA_Y_CARNE', 'RES_CARNE_MAGRA_CRUDA', null, 40.0, true, 1),
    ('CALDO_DE_PAPA_Y_CARNE', 'PAPA_VARIEDAD_HARINOSA_PASTUSA_CON_CASCARA_CRUDA', null, 100.0, false, 2),
    ('CALDO_DE_PAPA_Y_CARNE', 'AJO_CRUDO', null, 1.0, false, 3),
    ('CALDO_DE_PAPA_Y_CARNE', 'CEBOLLA_JUNCA_HOJAS_CRUDA', null, 4.0, false, 4),
    ('CALDO_DE_PAPA_Y_CARNE', 'CILANTRO_CRUDO', null, 1.0, false, 5),
    ('CALDO_DE_PAPA_Y_CARNE', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'LECHUGA_PEPINO_Y_MANI', 'Lechuga, pepino y maní', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar en las verduras en tamaño homogéneo. En un recipiente mezclar todas las verduras con la vinagreta hasta homogeneizar. Servir frío de acuerdo al gramaje establecido.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('LECHUGA_PEPINO_Y_MANI', 'LECHUGA_COMUN_CRUDA', 'H', 72.0, true, 1),
    ('LECHUGA_PEPINO_Y_MANI', 'LECHUGA_COMUN_CRUDA', 'M', 54.0, true, 1),
    ('LECHUGA_PEPINO_Y_MANI', 'PEPINO_COHOMBRO_CRUDO', 'H', 53.0, false, 2),
    ('LECHUGA_PEPINO_Y_MANI', 'PEPINO_COHOMBRO_CRUDO', 'M', 40.0, false, 2),
    ('LECHUGA_PEPINO_Y_MANI', 'MANI_CON_PIEL_TOSTADO_SIN_SAL', null, 5.0, false, 3),
    ('LECHUGA_PEPINO_Y_MANI', 'SAL', null, 1.0, false, 4),
    ('LECHUGA_PEPINO_Y_MANI', 'VINAGRE', null, 2.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'GUISO_AHUYAMA_Y_ARVEJA', 'Guiso ahuyama y arveja', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar finamente el tomate y cebolla, la ahuyama se corta en trozos. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir las arvejas y dejar cocinar por unos minutos. Sacar del agua caliente y en un recipiente sumergir en agua fría, para mantener al dente, luego escurrir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('GUISO_AHUYAMA_Y_ARVEJA', 'AHUYAMA_CRUDA', 'H', 70.0, true, 1),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'AHUYAMA_CRUDA', 'M', 58.0, true, 1),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'ARVEJA_VERDE_CRUDA', 'H', 50.0, false, 2),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'ARVEJA_VERDE_CRUDA', 'M', 25.0, false, 2),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'TOMATE_CRUDO', null, 6.0, false, 3),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 4),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'AJO_CRUDO', null, 1.0, false, 5),
    ('GUISO_AHUYAMA_Y_ARVEJA', 'SAL', null, 1.0, false, 6)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'Guiso calabaza, zanahoria y arveja', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar finamente el tomate y cebolla, la ahuyama se corta en trozos. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir las arvejas y dejar cocinar por unos minutos. Sacar del agua caliente y en un recipiente sumergir en agua fría, para mantener al dente, luego escurrir.');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'CALABAZA_SIN_CASCARA_CRUDA', 'H', 66.0, true, 1),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'CALABAZA_SIN_CASCARA_CRUDA', 'M', 44.0, true, 1),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'ARVEJA_VERDE_CRUDA', null, 25.0, false, 2),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'ZANAHORIA_SIN_CASCARA_CRUDA', null, 11.0, false, 3),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'TOMATE_CRUDO', null, 6.0, false, 4),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'CEBOLLA_JUNCA_TALLOS_CRUDA', null, 5.0, false, 5),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'AJO_CRUDO', null, 1.0, false, 6),
    ('GUISO_CALABAZA_ZANAHORIA_Y_ARVEJA', 'SAL', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'GUISO_VERDURAS_CAMPESINAS', 'Guiso Verduras Campesinas', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y portar el tomate, la cebolla, la zanahoria y la calabaza . En una olla poner agua con sal a hervir, cuando esté en ebullición añadir las arvejas, las zanahorias y la calabaza, dejar cocinar por unos minutos. Sacar del agua caliente, escurrir y reservar. Por otro lado, en una olla calentar sof');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('GUISO_VERDURAS_CAMPESINAS', 'CEBOLLA_CABEZONA_CRUDA', 'H', 21.0, true, 1),
    ('GUISO_VERDURAS_CAMPESINAS', 'CEBOLLA_CABEZONA_CRUDA', 'M', 15.0, true, 1),
    ('GUISO_VERDURAS_CAMPESINAS', 'HABICHUELA_CRUDA', 'H', 22.0, false, 2),
    ('GUISO_VERDURAS_CAMPESINAS', 'HABICHUELA_CRUDA', 'M', 16.0, false, 2),
    ('GUISO_VERDURAS_CAMPESINAS', 'MAIZ_AMARILLO_CRUDO', 'H', 20.0, false, 3),
    ('GUISO_VERDURAS_CAMPESINAS', 'MAIZ_AMARILLO_CRUDO', 'M', 15.0, false, 3),
    ('GUISO_VERDURAS_CAMPESINAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 23.0, false, 4),
    ('GUISO_VERDURAS_CAMPESINAS', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 17.0, false, 4),
    ('GUISO_VERDURAS_CAMPESINAS', 'TOMATE_CRUDO', null, 6.0, false, 5),
    ('GUISO_VERDURAS_CAMPESINAS', 'SAL', null, 1.0, false, 6),
    ('GUISO_VERDURAS_CAMPESINAS', 'AJO_CRUDO', null, 1.0, false, 7)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'Remolacha, zanahoria y cebolla', 'VERDURA', 'Seguir el procedimiento de lavado y desinfección de la Manual de Manipulación de Alimentos. Lavar, pelar y picar la cebolla y la zanahoria en cubos pequeños. En una olla poner agua con sal a hervir, cuando esté en ebullición añadir la remolacha, la sal y dejar cocinar hasta que este blanda. Sacar del agua caliente y escurrir, para luego cortar en cubos pequeños, reservar. Por otro lado, en una oll');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'H', 41.0, true, 1),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'ZANAHORIA_SIN_CASCARA_CRUDA', 'M', 29.0, true, 1),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'REMOLACHA_SIN_CASCARA_CRUDA', 'H', 43.0, false, 2),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'REMOLACHA_SIN_CASCARA_CRUDA', 'M', 31.0, false, 2),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'CEBOLLA_CABEZONA_CRUDA', null, 10.0, false, 3),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'LIMON_CRUDO', null, 2.0, false, 4),
    ('REMOLACHA_ZANAHORIA_Y_CEBOLLA', 'SAL', null, 1.0, false, 5)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'SALCHICHA_COCIDA', 'Salchicha cocida', 'PROTEICO_DES', 'Minuta patron: salchicha 39 g bruto, 35 g servido');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('SALCHICHA_COCIDA', 'SALCHICHA_CRUDA', null, 39.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.preparaciones (empresa_id, contrato_id, codigo, nombre, componente_codigo, procedimiento) values (e, null, 'CALADO_TOSTADA', 'Calado / tostada', 'PANIFICADO', 'Minuta patron: 45 g (3 unidades)');
  insert into public.preparacion_ingredientes (empresa_id, preparacion_id, producto_id, grupo_poblacion_id, peso_bruto, es_principal, orden)
  select e, pr.id, p.id, case x.g when 'H' then g_h when 'M' then g_m end, x.peso, x.principal, x.orden from (values
    ('CALADO_TOSTADA', 'CALADO_TOSTADA', null, 45.0, true, 1)
  ) as x(prep, prod, g, peso, principal, orden) join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  insert into public.ciclos_menu (empresa_id, contrato_id, codigo, nombre, n_menus, variante_id, tipo, vigente_desde, estado) values (e, c, 'CICLO_ERON', 'Ciclo estandar ERON (N-N007)', 15, v_est, 'estandar', '2025-04-01', 'vigente') returning id into cic;
  insert into public.ciclo_menu_items (empresa_id, ciclo_id, dia, tiempo_comida_id, componente_id, preparacion_id, descriptor)
  select e, cic, x.dia, x.t, co.id, pr.id, x.descriptor from (values
    (1, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (2, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (3, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (4, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (5, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (6, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (7, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (8, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (9, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (10, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (11, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (12, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (13, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (14, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (15, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (1, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (2, t_des, 'PROTEICO', 'SALCHICHA_COCIDA', 'SALCHICHA'),
    (3, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (4, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (5, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (6, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (7, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (8, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (9, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (10, t_des, 'PROTEICO', 'SALCHICHA_COCIDA', 'SALCHICHA'),
    (11, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (12, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (13, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (14, t_des, 'PROTEICO', 'CHANGUA_DE_HUEVO', 'CALDO/CHANGUA'),
    (15, t_des, 'PROTEICO', 'SALCHICHA_COCIDA', 'SALCHICHA'),
    (1, t_des, 'CEREAL', 'CALADO_TOSTADA', 'CALADO/ TOSTADA'),
    (2, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (3, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (4, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (5, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (6, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (7, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (8, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (9, t_des, 'CEREAL', 'CALADO_TOSTADA', 'CALADO/ TOSTADA'),
    (10, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (11, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (12, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (13, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (14, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (15, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (1, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (2, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (3, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (4, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (5, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (6, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (7, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (8, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (9, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (10, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (11, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (12, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (13, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (14, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (15, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (1, t_alm, 'SOPA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (2, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (3, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (4, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (5, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (6, t_alm, 'SOPA', 'MAZAMORRA_DULCE', 'MAZAMORRA DULCE'),
    (7, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (8, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (9, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (10, t_alm, 'SOPA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (11, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (12, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (13, t_alm, 'SOPA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (14, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (15, t_alm, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (1, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (2, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (3, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (4, t_alm, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (5, t_alm, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (6, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (7, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (8, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (9, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (10, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (11, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (12, t_alm, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (13, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (14, t_alm, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (15, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (1, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (2, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (3, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (4, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (5, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (6, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (7, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (8, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (9, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (10, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (11, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (12, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (13, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (14, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (15, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (1, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (2, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (3, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (4, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (5, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (6, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (7, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (8, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (9, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (10, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (11, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (12, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (13, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (14, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (15, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (1, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (2, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (3, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (4, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (5, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (6, t_alm, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (7, t_alm, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (8, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (9, t_alm, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (10, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (11, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (12, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (13, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (14, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (15, t_alm, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (1, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (2, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (3, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (4, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (5, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (6, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (7, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (8, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (9, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (10, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (11, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (12, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (13, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (14, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (15, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (1, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (2, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (3, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (4, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (5, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (6, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (7, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (8, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (9, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (10, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (11, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (12, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (13, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (14, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (15, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (1, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (2, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (3, t_cen, 'SOPA', 'MAZAMORRA_DULCE', 'MAZAMORRA DULCE'),
    (4, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (5, t_cen, 'SOPA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (6, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (7, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (8, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (9, t_cen, 'SOPA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (10, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (11, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (12, t_cen, 'SOPA', 'MAZAMORRA_DULCE', 'MAZAMORRA DULCE'),
    (13, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (14, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (15, t_cen, 'SOPA', 'CREMA_DE_VERDURAS', 'SOPA O CREMA'),
    (1, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (2, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (3, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (4, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (5, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (6, t_cen, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (7, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (8, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (9, t_cen, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (10, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (11, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (12, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (13, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (14, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (15, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (1, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (2, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (3, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (4, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (5, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (6, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (7, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (8, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (9, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (10, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (11, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (12, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (13, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (14, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (15, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (1, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (2, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (3, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (4, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (5, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (6, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (7, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (8, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (9, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (10, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (11, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (12, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (13, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (14, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (15, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'ENSALADA/VERDURA'),
    (1, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (2, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (3, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (4, t_cen, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (5, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (6, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (7, t_cen, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (8, t_cen, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (9, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (10, t_cen, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (11, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (12, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (13, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (14, t_cen, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (15, t_cen, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (1, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (2, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (3, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (4, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (5, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (6, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (7, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (8, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (9, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (10, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (11, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (12, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (13, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (14, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (15, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (1, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (2, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (3, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (4, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (5, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (6, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (7, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (8, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (9, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (10, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (11, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (12, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (13, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (14, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (15, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (1, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (2, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (3, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (4, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (5, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (6, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (7, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (8, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (9, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (10, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (11, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (12, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (13, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (14, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (15, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO')
  ) as x(dia, t, comp, prep, descriptor) join public.componentes co on co.contrato_id = c and co.tiempo_comida_id = x.t and co.codigo = x.comp left join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep;
  insert into public.ciclos_menu (empresa_id, contrato_id, codigo, nombre, n_menus, variante_id, tipo, vigente_desde, estado) values (e, c, 'CICLO_EP', 'Ciclo estandar estaciones de policia (N-N008)', 15, v_ep, 'estandar', '2025-04-01', 'vigente') returning id into cic_ep;
  insert into public.ciclo_menu_items (empresa_id, ciclo_id, dia, tiempo_comida_id, componente_id, preparacion_id, descriptor)
  select e, cic_ep, x.dia, x.t, co.id, pr.id, x.descriptor from (values
    (1, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (2, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (3, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (4, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (5, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (6, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (7, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (8, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (9, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (10, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (11, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (12, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (13, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (14, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (15, t_des, 'FRUTA', 'FRUTA_BANANO_COMUN', 'FRUTA ENTERA'),
    (1, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (2, t_des, 'PROTEICO', 'SALCHICHA_COCIDA', 'SALCHICHA'),
    (3, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (4, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (5, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (6, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (7, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (8, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (9, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (10, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (11, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (12, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (13, t_des, 'PROTEICO', 'QUESO_DOBLE_CREMA', 'QUESO'),
    (14, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (15, t_des, 'PROTEICO', 'HUEVOS_REVUELTOS', 'HUEVOS'),
    (1, t_des, 'CEREAL', 'CALADO_TOSTADA', 'CALADO/ TOSTADA'),
    (2, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (3, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (4, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (5, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (6, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (7, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (8, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (9, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (10, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (11, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (12, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (13, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (14, t_des, 'CEREAL', 'AREPA_ASADA', 'AREPA'),
    (15, t_des, 'CEREAL', 'PAN_BLANCO', 'PAN VARIEDAD'),
    (1, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (2, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (3, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (4, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (5, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (6, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (7, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (8, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (9, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (10, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (11, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (12, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (13, t_des, 'BEBIDA', 'CAFE_CON_LECHE', 'BEBIDA CON LECHE'),
    (14, t_des, 'BEBIDA', 'CHOCOLATE_EN_LECHE', 'BEBIDA DULCE CON LECHE'),
    (15, t_des, 'BEBIDA', 'AVENA_EN_LECHE', 'COLADA/AVENA CON LECHE'),
    (1, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (2, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (3, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (4, t_alm, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (5, t_alm, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (6, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (7, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (8, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (9, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (10, t_alm, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (11, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (12, t_alm, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (13, t_alm, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (14, t_alm, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (15, t_alm, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (1, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (2, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (3, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (4, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (5, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (6, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (7, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (8, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (9, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (10, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (11, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (12, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (13, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (14, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (15, t_alm, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (1, t_alm, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (2, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (3, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (4, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (5, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (6, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (7, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (8, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (9, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (10, t_alm, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (11, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (12, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (13, t_alm, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (14, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (15, t_alm, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (1, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (2, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (3, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (4, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (5, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (6, t_alm, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (7, t_alm, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (8, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (9, t_alm, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (10, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (11, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (12, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (13, t_alm, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (14, t_alm, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (15, t_alm, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (1, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (2, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (3, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (4, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (5, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (6, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (7, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (8, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (9, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (10, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (11, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (12, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (13, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (14, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (15, t_alm, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (1, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (2, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (3, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (4, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (5, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (6, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (7, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (8, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (9, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (10, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (11, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (12, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (13, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (14, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (15, t_alm, 'POSTRE', 'POSTRE_BOCADILLO_O_DULCE_DE_GUAYABA', 'POSTRE VARIEDAD'),
    (1, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (2, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (3, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (4, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (5, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (6, t_cen, 'PROTEICO', 'FILETE_DE_BAGRE_SUDADO', 'PESCADO'),
    (7, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (8, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (9, t_cen, 'PROTEICO', 'PIERNA_DE_POLLO_DORADA', 'PERNIL DE POLLO'),
    (10, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (11, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (12, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (13, t_cen, 'PROTEICO', 'PECHUGA_ASADA', 'PECHUGA DE POLLO'),
    (14, t_cen, 'PROTEICO', 'RES_SUDADA', 'CARNE DE RES'),
    (15, t_cen, 'PROTEICO', 'CERDO_ASADO', 'CARNE DE CERDO'),
    (1, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (2, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (3, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (4, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (5, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (6, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (7, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (8, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (9, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (10, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (11, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (12, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (13, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (14, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (15, t_cen, 'CEREAL', 'ARROZ_BLANCO', 'ARROZ'),
    (1, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (2, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (3, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (4, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (5, t_cen, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (6, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (7, t_cen, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (8, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (9, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (10, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (11, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (12, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (13, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (14, t_cen, 'VERDURA', 'CAZUELA_DE_LENTEJAS', 'CAZUELA DE LEGUMINOSAS'),
    (15, t_cen, 'VERDURA', 'LECHUGA_TOMATE_Y_ZANAHORIA', 'VERDURA'),
    (1, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (2, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (3, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (4, t_cen, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (5, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (6, t_cen, 'TUBERCULO', 'CRIOLLA_DORADA', 'PAPA CRIOLLA'),
    (7, t_cen, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (8, t_cen, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (9, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (10, t_cen, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (11, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (12, t_cen, 'TUBERCULO', 'PAPA_SALADA', 'PAPA PASTUSA / SABANERA'),
    (13, t_cen, 'TUBERCULO', 'YUCA_DORADA', 'YUCA'),
    (14, t_cen, 'TUBERCULO', 'TAJADAS_PLATANO_MADURO', 'PLATANO MADURO'),
    (15, t_cen, 'TUBERCULO', 'PATACON_DE_PLATANO_VERDE', 'PLATANO VERDE'),
    (1, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (2, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (3, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (4, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (5, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (6, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (7, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (8, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (9, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (10, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (11, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (12, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (13, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (14, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (15, t_cen, 'JUGO', 'JUGO_DE_MORA', 'JUGO DE FRUTA'),
    (1, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (2, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (3, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (4, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (5, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (6, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (7, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (8, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (9, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (10, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (11, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (12, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (13, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (14, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (15, t_ref, 'BEBIDA', 'BEBIDA_NECTAR_DE_PERA', 'BEBIDA'),
    (1, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (2, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (3, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (4, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (5, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (6, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (7, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (8, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (9, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (10, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (11, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (12, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (13, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (14, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO'),
    (15, t_ref, 'CEREAL', 'PAN_BLANCO', 'PANIFICADO')
  ) as x(dia, t, comp, prep, descriptor) join public.componentes co on co.contrato_id = c and co.tiempo_comida_id = x.t and co.codigo = x.comp left join public.preparaciones pr on pr.empresa_id = e and pr.codigo = x.prep;
  -- minuta patron resumida (porcion servida minima) H / M, Anexo 4 N-N001/N-N002
  insert into public.minuta_patron (empresa_id, contrato_id, grupo_poblacion_id, componente_id, producto_id, metodo_coccion, porcion_servida, unidad, peso_bruto_ref, fuente)
  select e, c, case x.g when 'H' then g_h else g_m end, co.id, p.id, x.metodo, x.servido, x.unidad, x.bruto, 'Anexo 4 N-N001/002' from (values
    ('H', 'DES', 'FRUTA', null, 'entera', 70, 'g', null), ('M', 'DES', 'FRUTA', null, 'entera', 70, 'g', null),
    ('H', 'DES', 'BEBIDA', null, 'pocillo', 240, 'ml', null), ('M', 'DES', 'BEBIDA', null, 'pocillo', 240, 'ml', null),
    ('H', 'DES', 'PROTEICO', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', 'cocido', 50, 'g', 55), ('M', 'DES', 'PROTEICO', 'HUEVO_DE_GALLINA_ENTERO_CRUDO', 'cocido', 50, 'g', 55),
    ('H', 'DES', 'PROTEICO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO', 'porcion', 35, 'g', 35), ('M', 'DES', 'PROTEICO', 'QUESO_FRESCO_SEMIDURO_SEMIGRASO', 'porcion', 25, 'g', 25),
    ('H', 'DES', 'PROTEICO', 'SALCHICHA_CRUDA', 'cocido', 35, 'g', 39), ('M', 'DES', 'PROTEICO', 'SALCHICHA_CRUDA', 'cocido', 35, 'g', 39),
    ('H', 'DES', 'CEREAL', null, 'porcion', 60, 'g', 60), ('M', 'DES', 'CEREAL', null, 'porcion', 50, 'g', 50),
    ('H', 'ALM', 'SOPA', null, 'cocido', 240, 'ml', null), ('M', 'ALM', 'SOPA', null, 'cocido', 240, 'ml', null),
    ('H', 'ALM', 'PROTEICO', 'RES_CARNE_MAGRA_CRUDA', 'cocido', 68, 'g', 111), ('M', 'ALM', 'PROTEICO', 'RES_CARNE_MAGRA_CRUDA', 'cocido', 63, 'g', 103),
    ('H', 'ALM', 'PROTEICO', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'cocido', 78, 'g', 126), ('M', 'ALM', 'PROTEICO', 'POLLO_PECHUGA_CON_PIEL_CRUDA', 'cocido', 70, 'g', 113),
    ('H', 'ALM', 'PROTEICO', 'CERDO_CARNE_MAGRA_CRUDA', 'cocido', 72, 'g', 114), ('M', 'ALM', 'PROTEICO', 'CERDO_CARNE_MAGRA_CRUDA', 'cocido', 72, 'g', 114),
    ('H', 'ALM', 'CEREAL', 'ARROZ_BLANCO_PULIDO_CRUDO', 'cocido', 170, 'g', 74), ('M', 'ALM', 'CEREAL', 'ARROZ_BLANCO_PULIDO_CRUDO', 'cocido', 159, 'g', 69),
    ('H', 'ALM', 'VERDURA', null, 'porcion', 80, 'g', null), ('M', 'ALM', 'VERDURA', null, 'porcion', 60, 'g', null),
    ('H', 'ALM', 'TUBERCULO', null, 'cocido', 100, 'g', 101), ('M', 'ALM', 'TUBERCULO', null, 'cocido', 77, 'g', 78),
    ('H', 'ALM', 'JUGO', null, 'pulpa', 250, 'ml', 60), ('M', 'ALM', 'JUGO', null, 'pulpa', 250, 'ml', 60),
    ('H', 'ALM', 'POSTRE', null, 'unidad', 10, 'g', 10), ('M', 'ALM', 'POSTRE', null, 'unidad', 10, 'g', 10),
    ('H', 'REF', 'CEREAL', null, 'porcion', 60, 'g', 60), ('M', 'REF', 'CEREAL', null, 'porcion', 45, 'g', 45),
    ('H', 'REF', 'BEBIDA', null, 'envase', 200, 'ml', null), ('M', 'REF', 'BEBIDA', null, 'envase', 200, 'ml', null)
  ) as x(g, t, comp, prod, metodo, servido, unidad, bruto)
  join public.tiempos_comida tc on tc.contrato_id = c and tc.codigo = x.t
  join public.componentes co on co.contrato_id = c and co.tiempo_comida_id = tc.id and co.codigo = x.comp
  left join public.productos p on p.empresa_id = e and p.codigo = x.prod;
  -- la cena hereda proteico, cereal, verdura, tuberculo y jugo del almuerzo
  insert into public.minuta_patron (empresa_id, contrato_id, grupo_poblacion_id, componente_id, producto_id, metodo_coccion, porcion_servida, unidad, peso_bruto_ref, fuente)
  select m.empresa_id, m.contrato_id, m.grupo_poblacion_id, cc.id, m.producto_id, m.metodo_coccion, m.porcion_servida, m.unidad, m.peso_bruto_ref, m.fuente
    from public.minuta_patron m join public.componentes ca on ca.id = m.componente_id and ca.tiempo_comida_id = t_alm and ca.codigo <> 'POSTRE'
    join public.componentes cc on cc.contrato_id = c and cc.tiempo_comida_id = t_cen and cc.codigo = ca.codigo
   where m.contrato_id = c;
  -- ciclo por sede: ERON con ciclo estandar; el batallon con ciclo EP (sin sopa). Menu 1 el dia de inicio del contrato (provisional).
  for r in select cs.id, s.nombre, cs.cupos_referencia from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id where cs.contrato_id = c loop
    insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, menu_confirmado)
    values (e, r.id, case when r.nombre like 'Batallon%' then cic_ep else cic end, case when r.nombre like 'Batallon%' then v_ep else v_est end, '2025-04-01', 'continuo', true, '2025-04-01', false);
    -- cupos de referencia: todo hombres salvo COCUC Cucuta, que tiene reclusion de mujeres (reparto provisional 90/10 hasta tener el parte real)
    if r.nombre = 'COCUC Cucuta' then
      insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, fecha_desde, cantidad, fuente) values
        (e, r.id, g_h, '2025-04-01', round(r.cupos_referencia * 0.9), 'Contrato (PPL estimada 2025), reparto H/M provisional'),
        (e, r.id, g_m, '2025-04-01', r.cupos_referencia - round(r.cupos_referencia * 0.9), 'Contrato (PPL estimada 2025), reparto H/M provisional');
    else
      insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, fecha_desde, cantidad, fuente) values (e, r.id, g_h, '2025-04-01', r.cupos_referencia, 'Contrato (PPL estimada 2025)');
    end if;
  end loop;
  -- correccion de categorias (la heuristica del generador marco granos y abarrotes como fruver)
  update public.productos set categoria = 'abarrotes', perecedero = false where empresa_id = e and (
    nombre ~* '^(arroz|pasta|lenteja|fr[ií]jol|arveja seca|ma[ií]z|harina|avena|cebada|cuchuco|panela|az[uú]car|sal$|sal |aceite|caf[eé]|chocolate|almid[oó]n|especias|vinagre|mayonesa|man[ií]|coco|garbanzo|cocadas|arequipe|bocadillo|panelita|gelatina|dulce)');
  update public.productos set categoria = 'bebidas' where empresa_id = e and nombre ~* '^(n[eé]ctar|bebida con leche)';
  update public.productos set categoria = 'lacteos', perecedero = true where empresa_id = e and nombre ~* '^(leche|queso|yogurt|kumis)';
  update public.productos set categoria = 'proteinas', perecedero = true where empresa_id = e and nombre ~* '^(res|pollo|cerdo|bagre|tilapia|huevo|salchicha|chorizo|pescado)';
  update public.productos set categoria = 'panaderia', perecedero = true where empresa_id = e and nombre ~* '^(pan |pan,|arepa|envuelto|calado|galleta|mogolla)';
end $seed$;
