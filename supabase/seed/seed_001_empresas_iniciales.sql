-- =====================================================================
-- Supply ERP · Seed 001 · Empresas iniciales (30 oct 2026, con OK de Osvaldo)
-- Dos contratos reales de arranque: UT Diestra (USPEC, PPL) y UT Nutrifood (PAE Atlantico),
-- mas una empresa de practica. Los NIT se corrigen cuando Osvaldo pase la documentacion
-- (placeholders POR-DEFINIR-*, como se hizo en A2 PAN con UT Capital USPEC).
-- Se corre desde el editor SQL de Supabase (sin sesion: auth.uid() nulo = permitido).
-- =====================================================================

select public.alta_empresa(
  'UNION TEMPORAL DIESTRA', 'POR-DEFINIR-DIESTRA', null, 'Cucuta',
  'UT Diestra', 'union_temporal', 'Grupo Fombisol / Alimentar Capital', 'CEDI Cucuta',
  '{"dia_inicio_semana_reparto": 5, "ciclo_reparto_defecto": "semanal"}'::jsonb);

select public.alta_empresa(
  'UNION TEMPORAL NUTRIFOOD', 'POR-DEFINIR-NUTRIFOOD', null, 'Barranquilla',
  'UT Nutrifood', 'union_temporal', 'Grupo Fombisol / Alimentar Capital', 'CEDI Barranquilla',
  '{"dia_inicio_semana_reparto": 1, "ciclo_reparto_defecto": "2+3"}'::jsonb);

select public.alta_empresa(
  'Demo Contratistas (practica)', '900000001', '1', 'Bogota',
  'Demo', 'otro', null, 'CEDI de practica', '{}'::jsonb);

-- Entidades contratantes de arranque
insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Unidad de Servicios Penitenciarios y Carcelarios (USPEC)', 'uspec', 'Bogota' from public.empresas e where e.nit = 'POR-DEFINIR-DIESTRA';
insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Gobernacion del Atlantico (PAE)', 'gobernacion', 'Barranquilla' from public.empresas e where e.nit = 'POR-DEFINIR-NUTRIFOOD';
insert into public.entidades_contratantes (empresa_id, nombre, tipo, ciudad)
select e.id, 'Entidad de practica', 'otra', 'Bogota' from public.empresas e where e.nit = '900000001';

-- Superadministrador: outria@gmail.com queda marcado al crear su perfil (trigger de la mig. 001).
-- Si el usuario ya existia antes de la migracion, descomentar:
-- update public.perfiles set es_superadmin = true where id = (select id from auth.users where lower(email) = 'outria@gmail.com');
