-- =====================================================================
-- Supply ERP · Seed 001 · Empresas iniciales y contrato USPEC-CTO-199-2025 (aplicado en Supabase el 30-oct-2026)
-- UT Diestra (NIT 901.942.965-2, del RUT), UT Nutrifood (NIT pendiente) y empresa de practica.
-- Contrato Grupo 15: valor $42.132.296.516 (2025: 23.448.954.207 · 2026: 18.683.342.309), plazo hasta 31-jul-2026.
-- Fechas de suscripcion e inicio provisionales hasta cargar el acta de inicio.
-- =====================================================================
select public.alta_empresa('UNION TEMPORAL DIESTRA', '901942965', '2', 'Cucuta', 'UT Diestra', 'union_temporal', 'Grupo Fombisol / Alimentar Capital', 'CEDI Cucuta',
  '{"dia_inicio_semana_reparto": 5, "ciclo_reparto_defecto": "semanal"}'::jsonb);
select public.alta_empresa('UNION TEMPORAL NUTRIFOOD', 'POR-DEFINIR-NUTRIFOOD', null, 'Barranquilla', 'UT Nutrifood', 'union_temporal', 'Grupo Fombisol / Alimentar Capital', 'CEDI Barranquilla',
  '{"dia_inicio_semana_reparto": 1, "ciclo_reparto_defecto": "2+3"}'::jsonb);
select public.alta_empresa('Demo Contratistas (practica)', '900000001', '1', 'Bogota', 'Demo', 'otro', null, 'CEDI de practica', '{}'::jsonb);

insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Unidad de Servicios Penitenciarios y Carcelarios (USPEC)', 'uspec', 'Bogota' from public.empresas e where e.nit = '901942965';
insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Gobernacion del Atlantico (PAE)', 'gobernacion', 'Barranquilla' from public.empresas e where e.nit = 'POR-DEFINIR-NUTRIFOOD';
insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Entidad de practica', 'otra', 'Bogota' from public.empresas e where e.nit = '900000001';

select public.crear_contrato(jsonb_build_object(
  'empresa_id', (select id from public.empresas where nit = '901942965'),
  'numero', 'USPEC-CTO-199-2025',
  'entidad_id', (select id from public.entidades_contratantes where nombre like 'Unidad de Servicios%'),
  'modalidad', 'uspec_ppl',
  'objeto', 'Suministrar el servicio de alimentacion para la poblacion privada de la libertad a cargo del INPEC y la USPEC, asi como para las estaciones de policia y centro transitorio de detencion, el cual se compone de desayuno, almuerzo, cena y refrigerio - GRUPO 15',
  'obligaciones', 'Obligaciones generales y especificas: numeral 2.7.1 y siguientes del Estudio Previo USPEC-LP-002-2025. Forma de pago: numeral 4.4; requisitos para el pago: 4.4.2; descuentos: 2.9; ANS y multas: 1.21. Clausula penal 20 %. Oferta tecnica adicional: menu especial adicional, capacitacion de 127 personas (20 h), recurso humano adicional (supervisor de calidad y estaciones, distribuidores segun escala de PPL).',
  'proceso_secop', 'USPEC-LP-002-2025',
  'interventoria', 'Supervision: Direccion de Logistica USPEC; interventoria externa por designar',
  'valor_inicial', 42132296516,
  'incluye_iva', true,
  'fecha_suscripcion', '2025-03-15',
  'fecha_inicio', '2025-04-01',
  'fecha_fin_inicial', '2026-07-31',
  'dias_atencion', 'todos',
  'tiempos_comida', 4,
  'n_menus_ciclo', 15,
  'ciclo_reparto', 'semanal',
  'dias_subsanacion', 3,
  'poliza_cumplimiento', 'Cumplimiento 20 % (duracion + liquidacion); salarios y prestaciones 5 % (duracion + 3 años); RCE 5 %',
  'estado', 'vigente',
  'notas', 'Valor por vigencias: 2025 $23.448.954.207 (CDP 9525 del 06-feb-2025); 2026 $18.683.342.309 (vigencias futuras, oficio MinHacienda 2-2025-014887). Estaciones de policia y CTD solo hasta el 30-jun-2025 (Ley 2346 de 2024). Fechas de suscripcion e inicio son provisionales hasta cargar el acta de inicio.'
));

-- Unidades de servicio del Grupo 15 con PPL estimada del contrato (las estaciones de policia salieron el 30-jun-2025)
with emp as (select id from public.empresas where nit = '901942965'),
     ct as (select id from public.contratos where numero = 'USPEC-CTO-199-2025'),
     s as (
       insert into public.sedes (empresa_id, nombre, tipo, subtipo, departamento, ciudad)
       select emp.id, x.nombre, 'unidad_servicio', x.subtipo, x.depto, x.ciudad from emp, (values
         ('COCUC Cucuta', 'eron', 'Norte de Santander', 'Cucuta'),
         ('EPMSC Ocaña', 'eron', 'Norte de Santander', 'Ocaña'),
         ('EPMSC Aguachica', 'eron', 'Cesar', 'Aguachica'),
         ('EPMSC Pamplona', 'eron', 'Norte de Santander', 'Pamplona'),
         ('EPMSC Arauca', 'eron', 'Arauca', 'Arauca'),
         ('Batallon ASPC No. 30 Guasimales', 'otro', 'Norte de Santander', 'Cucuta')
       ) as x(nombre, subtipo, depto, ciudad)
       returning id, nombre)
insert into public.contrato_sedes (empresa_id, contrato_id, sede_id, cupos_referencia, ciclo_reparto, dia_inicio_semana, fecha_inicio)
select emp.id, ct.id, s.id,
       case s.nombre when 'COCUC Cucuta' then 3985 when 'EPMSC Ocaña' then 393 when 'EPMSC Aguachica' then 186 when 'EPMSC Pamplona' then 349 when 'EPMSC Arauca' then 312 else 26 end,
       'semanal', 5, '2025-04-01'
  from emp, ct, s;
