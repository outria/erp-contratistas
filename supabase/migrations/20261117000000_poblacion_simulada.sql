-- =====================================================================
-- 017 · Poblacion simulada mientras llega la real (4-nov-2026)
-- Pedido de Osvaldo: no vararse por falta de focalizacion PAE, parte de
-- guardia o BD de dietas. Reglas que dio:
--  - PAE: grupos etarios con participaciones entre 15 % y 25 % cada uno
--    (un colegio 18/23/20/25/15, otro distinto); cada colegio casi siempre
--    una sola modalidad (RPS o RI).
--  - USPEC: dietas entre 0 % y 40 % de la PPL por establecimiento, casi
--    todas hipercaloricas e hiperproteicas, pocas hiposodicas, el resto
--    contadas; mujeres solo donde hay patio de mujeres (COCUC si; los
--    grupos 6 y 7 de Bogota, 12 carceles, ninguna).
-- Todo lo simulado lleva fuente 'SIMULADA ...' para reemplazarlo luego.
-- =====================================================================

set client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. PAE: cinco grupos etarios en la plantilla (parametrizables por contrato)
-- ---------------------------------------------------------------------
update public.plantillas_modalidad
   set esquema = jsonb_set(esquema, '{grupos}', '[
     {"tipo":"etario","orden":1,"codigo":"G3_5","nombre":"Preescolar (3 a 5 anos 11 meses)"},
     {"tipo":"etario","orden":2,"codigo":"G6_8","nombre":"6 a 8 anos 11 meses"},
     {"tipo":"etario","orden":3,"codigo":"G9_13","nombre":"9 a 13 anos 11 meses"},
     {"tipo":"etario","orden":4,"codigo":"G14_17","nombre":"14 a 17 anos 11 meses"},
     {"tipo":"etario","orden":5,"codigo":"G18","nombre":"18 anos o mas (extraedad)"}]'::jsonb)
 where codigo = 'pae';

-- contratos PAE existentes: el grupo 4-8 pasa a 6-8 y se agregan preescolar y 18+
do $$
declare c record;
begin
  for c in select id, empresa_id from public.contratos where modalidad = 'pae' loop
    update public.grupos_poblacion set codigo = 'G6_8', nombre = '6 a 8 anos 11 meses', orden = 2 where contrato_id = c.id and codigo = 'G4_8';
    update public.grupos_poblacion set orden = 3 where contrato_id = c.id and codigo = 'G9_13';
    update public.grupos_poblacion set orden = 4 where contrato_id = c.id and codigo = 'G14_17';
    insert into public.grupos_poblacion (empresa_id, contrato_id, codigo, nombre, tipo, orden) values
      (c.empresa_id, c.id, 'G3_5', 'Preescolar (3 a 5 anos 11 meses)', 'etario', 1),
      (c.empresa_id, c.id, 'G18', '18 anos o mas (extraedad)', 'etario', 5)
    on conflict (contrato_id, codigo) do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Simulador (reproducible con la semilla)
-- ---------------------------------------------------------------------
create or replace function public.simular_poblacion(p_semilla double precision default 0.4211)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pae uuid; v_uspec uuid; v_diestra uuid;
  v_ct uuid; v_emp uuid; v_ini date; v_sede uuid; v_cs uuid; v_ciclo record;
  s record; g record; t record; d record; cs record;
  v_total int; v_resto int; v_pesos numeric[]; v_suma numeric; v_i int; v_n int;
  v_modal text; v_tiempos text[]; v_pct numeric; v_dietas int; v_ppl int; v_h int; v_m int;
  n_pae int := 0; n_usp int := 0; n_die int := 0; n_cup int := 0;
  -- municipios del Atlantico para los colegios de practica
  k_mun text[] := array['Barranquilla','Soledad','Malambo','Sabanalarga','Baranoa','Galapa','Puerto Colombia','Santo Tomas','Palmar de Varela','Sabanagrande',
                        'Ponedera','Polonuevo','Usiacuri','Juan de Acosta','Tubara','Piojo','Luruaco','Repelon','Manati','Candelaria','Campo de la Cruz',
                        'Santa Lucia','Suan','Barranquilla','Soledad','Malambo','Sabanalarga','Barranquilla','Soledad','Galapa'];
  k_nom text[] := array['IE Tecnica Comercial','IE Nuestra Senora del Carmen','IE San Jose','IE Francisco de Paula Santander','IE Simon Bolivar','IE La Esperanza',
                        'IE Tecnica Agropecuaria','IE Maria Auxiliadora','IE Jose Maria Cordoba','IE El Carmen','IE Antonio Narino','IE San Antonio',
                        'IE Normal Superior','IE Policarpa Salavarrieta','IE Las Mercedes','IE San Martin','IE Rural El Progreso','IE Rural La Playa',
                        'IE Rural San Pedro','IE Rural Villa Rosa','IE Jorge Eliecer Gaitan','IE Camilo Torres','IE Santa Teresita','IE Tecnica Industrial',
                        'IE La Milagrosa','IE Rural Los Campanos','IE Rural El Bajo','IE Divino Nino','IE Sagrado Corazon','IE Rural Las Flores'];
  k_usp text[] := array['EPMSC Practica Occidente','EPMSC Practica Oriente','EPMSC Practica Centro','EPMSC Practica Sabana','EPMSC Practica Rio','EPC Practica Capital',
                        'Estacion de Policia Practica Dos','Centro de Reclusion Militar Practica','Carcel Municipal Practica'];
begin
  if not (public.es_admin_sql() or public.es_superadmin()) then raise exception 'Solo el administrador de la plataforma simula poblacion.'; end if;
  perform setseed(p_semilla);
  select id into v_pae from public.empresas where nit = '900000002';
  select id into v_uspec from public.empresas where nit = '900000001';
  select id into v_diestra from public.empresas where nit = '901942965';

  -- ================= PAE =================
  if v_pae is not null then
    select id into v_ct from public.contratos where empresa_id = v_pae limit 1;
    select coalesce(min(fecha_desde), (select fecha_inicio from public.contratos where id = v_ct)) into v_ini from public.cupos c join public.contrato_sedes cs2 on cs2.id = c.contrato_sede_id where cs2.contrato_id = v_ct;
    select * into v_ciclo from public.sede_ciclo sc join public.contrato_sedes cs2 on cs2.id = sc.contrato_sede_id where cs2.contrato_id = v_ct limit 1;
    -- colegios nuevos hasta completar 34
    v_n := (select count(*) from public.contrato_sedes where contrato_id = v_ct);
    v_i := 0;
    while v_n < 34 and v_i < array_length(k_nom, 1) loop
      v_i := v_i + 1;
      if exists (select 1 from public.sedes where empresa_id = v_pae and nombre = k_nom[v_i] || ' (' || k_mun[v_i] || ')') then continue; end if;
      v_total := case when k_nom[v_i] like 'IE Rural%' then 60 + floor(random() * 300)::int else 250 + floor(random() * 1500)::int end;
      insert into public.sedes (empresa_id, nombre, tipo, subtipo, departamento, ciudad)
      values (v_pae, k_nom[v_i] || ' (' || k_mun[v_i] || ')', 'unidad_servicio', 'colegio', 'Atlantico', k_mun[v_i]) returning id into v_sede;
      insert into public.contrato_sedes (empresa_id, contrato_id, sede_id, cupos_referencia, fecha_inicio, notas)
      values (v_pae, v_ct, v_sede, v_total, v_ini, 'SIMULADA: colegio de practica generado automaticamente') returning id into v_cs;
      insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, menu_confirmado)
      values (v_pae, v_cs, v_ciclo.ciclo_id, v_ciclo.variante_id, v_ciclo.fecha_inicio_menu1, v_ciclo.modo_reinicio, v_ciclo.avanza_sin_servicio, v_ciclo.vigente_desde, true);
      v_n := v_n + 1; n_pae := n_pae + 1;
    end loop;

    -- cupos: se reemplazan todos los del contrato (focalizacion simulada)
    delete from public.cupos c using public.contrato_sedes cs2 where cs2.id = c.contrato_sede_id and cs2.contrato_id = v_ct;
    for cs in select cs2.id, cs2.cupos_referencia, se.nombre from public.contrato_sedes cs2 join public.sedes se on se.id = cs2.sede_id where cs2.contrato_id = v_ct order by se.nombre loop
      -- modalidad del colegio: rurales casi siempre RI; el resto RPS; pocos combinan
      v_pct := random();
      if cs.nombre like 'IE Rural%' or cs.nombre like 'IE Rural de%' then
        v_tiempos := case when v_pct < 0.85 then array['RI'] else array['RI','CPM'] end;
      elsif cs.nombre = 'IE Normal de Practica' then
        v_tiempos := array['RPS','CAM','CPM'];
      else
        v_tiempos := case when v_pct < 0.72 then array['RPS'] when v_pct < 0.88 then array['RI'] when v_pct < 0.96 then array['RPS','CAM'] else array['RPS','CAM','CPM'] end;
      end if;
      -- participacion de cada grupo etario entre 15 % y 25 %, normalizada a 100 %
      v_pesos := array[]::numeric[]; v_suma := 0;
      for g in select id, codigo from public.grupos_poblacion where contrato_id = v_ct order by orden loop
        v_pesos := v_pesos || (0.15 + random() * 0.10)::numeric; v_suma := v_suma + v_pesos[array_length(v_pesos, 1)];
      end loop;
      for t in select id, codigo from public.tiempos_comida where contrato_id = v_ct and codigo = any(v_tiempos) loop
        -- cuando combina, el complemento cubre una parte del colegio
        v_total := case when t.codigo in ('CAM','CPM') and array_length(v_tiempos, 1) > 1 then round(cs.cupos_referencia * (0.25 + random() * 0.25)) else cs.cupos_referencia end;
        v_resto := v_total; v_i := 0;
        for g in select id, codigo from public.grupos_poblacion where contrato_id = v_ct order by orden loop
          v_i := v_i + 1;
          v_n := case when v_i = 5 then v_resto else round(v_total * v_pesos[v_i] / v_suma)::int end;
          v_resto := v_resto - v_n;
          if v_n > 0 then
            insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, tiempo_comida_id, fecha_desde, cantidad, fuente)
            values (v_pae, cs.id, g.id, t.id, v_ini, v_n, 'SIMULADA: focalizacion de practica (reemplazar con SIMAT)');
            n_cup := n_cup + 1;
          end if;
        end loop;
      end loop;
    end loop;
  end if;

  -- ================= USPEC demo: 12 establecimientos, sin mujeres (como grupos 6 y 7) =================
  if v_uspec is not null then
    select id into v_ct from public.contratos where empresa_id = v_uspec limit 1;
    select coalesce(min(fecha_desde), (select fecha_inicio from public.contratos where id = v_ct)) into v_ini from public.cupos c join public.contrato_sedes cs2 on cs2.id = c.contrato_sede_id where cs2.contrato_id = v_ct;
    select * into v_ciclo from public.sede_ciclo sc join public.contrato_sedes cs2 on cs2.id = sc.contrato_sede_id where cs2.contrato_id = v_ct limit 1;
    v_n := (select count(*) from public.contrato_sedes where contrato_id = v_ct); v_i := 0;
    while v_n < 12 and v_i < array_length(k_usp, 1) loop
      v_i := v_i + 1;
      if exists (select 1 from public.sedes where empresa_id = v_uspec and nombre = k_usp[v_i]) then continue; end if;
      v_total := case when k_usp[v_i] like 'Estacion%' then 40 + floor(random() * 80)::int when k_usp[v_i] like 'Centro de Reclusion%' then 80 + floor(random() * 120)::int
                      when k_usp[v_i] like 'Carcel Municipal%' then 30 + floor(random() * 60)::int when k_usp[v_i] like 'EPC%' then 2500 + floor(random() * 2500)::int else 200 + floor(random() * 1300)::int end;
      insert into public.sedes (empresa_id, nombre, tipo, subtipo, ciudad)
      values (v_uspec, k_usp[v_i], 'unidad_servicio', case when k_usp[v_i] like 'Estacion%' or k_usp[v_i] like 'Carcel Municipal%' then 'estacion' when k_usp[v_i] like 'Centro de Reclusion%' then 'otro' else 'eron' end, 'Bogota') returning id into v_sede;
      insert into public.contrato_sedes (empresa_id, contrato_id, sede_id, cupos_referencia, fecha_inicio, notas)
      values (v_uspec, v_ct, v_sede, v_total, v_ini, 'SIMULADA: establecimiento de practica generado automaticamente') returning id into v_cs;
      insert into public.sede_ciclo (empresa_id, contrato_sede_id, ciclo_id, variante_id, fecha_inicio_menu1, modo_reinicio, avanza_sin_servicio, vigente_desde, menu_confirmado)
      values (v_uspec, v_cs, v_ciclo.ciclo_id,
              (select id from public.variantes_racion where contrato_id = v_ct and codigo = case when k_usp[v_i] like 'Estacion%' or k_usp[v_i] like 'Carcel Municipal%' then 'EP' else 'ESTANDAR' end),
              v_ciclo.fecha_inicio_menu1, v_ciclo.modo_reinicio, v_ciclo.avanza_sin_servicio, v_ciclo.vigente_desde, true);
      insert into public.cupos (empresa_id, contrato_sede_id, grupo_poblacion_id, variante_id, fecha_desde, cantidad, fuente)
      select v_uspec, v_cs, g2.id, (select id from public.variantes_racion where contrato_id = v_ct and codigo = case when k_usp[v_i] like 'Estacion%' or k_usp[v_i] like 'Carcel Municipal%' then 'EP' else 'ESTANDAR' end),
             v_ini, v_total, 'SIMULADA: parte de practica (reemplazar con parte de guardia)'
        from public.grupos_poblacion g2 where g2.contrato_id = v_ct and g2.codigo = 'H';
      v_n := v_n + 1; n_usp := n_usp + 1;
    end loop;
    -- sin patio de mujeres en la demo: lo que era M pasa a H
    update public.cupos c set grupo_poblacion_id = (select id from public.grupos_poblacion where contrato_id = v_ct and codigo = 'H'), fuente = 'SIMULADA: parte de practica (reemplazar con parte de guardia)'
      from public.contrato_sedes cs2, public.grupos_poblacion g2
     where cs2.id = c.contrato_sede_id and cs2.contrato_id = v_ct and g2.id = c.grupo_poblacion_id and g2.codigo = 'M';
    -- juntar H duplicados por sede/variante/fecha
    with dup as (
      select (array_agg(c.id order by c.creado_en, c.id))[1] keep_id, c.contrato_sede_id, c.variante_id, c.fecha_desde, sum(c.cantidad) total, array_agg(c.id) ids
        from public.cupos c join public.contrato_sedes cs2 on cs2.id = c.contrato_sede_id where cs2.contrato_id = v_ct
       group by c.contrato_sede_id, c.variante_id, c.fecha_desde having count(*) > 1)
    , upd as (update public.cupos c set cantidad = dd.total from dup dd where c.id = dd.keep_id returning c.id)
    delete from public.cupos c using dup dd where c.id = any(dd.ids) and c.id <> dd.keep_id;
  end if;

  -- ================= Dietas USPEC (demo y Diestra) =================
  for v_ct, v_emp in select c.id, c.empresa_id from public.contratos c where c.modalidad = 'uspec_ppl' and c.empresa_id in (v_uspec, v_diestra) loop
    delete from public.dietas_poblacion dp using public.contrato_sedes cs2 where cs2.id = dp.contrato_sede_id and cs2.contrato_id = v_ct;
    for cs in select cs2.id, se.nombre,
                     coalesce((select sum(cantidad) from public.cupos c join public.grupos_poblacion g2 on g2.id = c.grupo_poblacion_id where c.contrato_sede_id = cs2.id and g2.codigo = 'H' and c.fecha_hasta is null), 0) h,
                     coalesce((select sum(cantidad) from public.cupos c join public.grupos_poblacion g2 on g2.id = c.grupo_poblacion_id where c.contrato_sede_id = cs2.id and g2.codigo = 'M' and c.fecha_hasta is null), 0) m,
                     coalesce((select min(fecha_desde) from public.cupos c where c.contrato_sede_id = cs2.id), cs2.fecha_inicio) ini
                from public.contrato_sedes cs2 join public.sedes se on se.id = cs2.sede_id where cs2.contrato_id = v_ct loop
      v_ppl := cs.h + cs.m; if v_ppl = 0 then continue; end if;
      -- porcentaje en dieta: triangular entre 0 y 40 % con moda cerca del 14 %
      v_pct := (random() + random() + random()) / 3 * 0.40 * 1.05;
      if v_pct > 0.40 then v_pct := 0.40; end if;
      v_dietas := round(v_ppl * v_pct)::int;
      if v_dietas = 0 then continue; end if;
      for d in select * from (values
          ('HIPERCAL_HIPERPROT', 0.84 + random() * 0.08), ('HIPOSODICA', 0.03 + random() * 0.04), ('HIPOGLUCIDA', 0.01 + random() * 0.03),
          ('BLANDA', random() * 0.02), ('HIPOGRASA', random() * 0.015), ('SIN_LACTOSA', random() * 0.008), ('RENAL', random() * 0.004)) x(cod, peso) loop
        v_n := round(v_dietas * d.peso)::int; if v_n = 0 then continue; end if;
        v_h := round(v_n * cs.h::numeric / v_ppl)::int; v_m := v_n - v_h;
        if v_h > 0 then
          insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, cantidad, fuente)
          values (v_emp, cs.id, (select id from public.tipos_dieta where empresa_id is null and codigo = d.cod), (select id from public.grupos_poblacion where contrato_id = v_ct and codigo = 'H'), cs.ini, v_h, 'SIMULADA: BD de dietas de practica (reemplazar con la BD real)');
          n_die := n_die + 1;
        end if;
        if v_m > 0 then
          insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, cantidad, fuente)
          values (v_emp, cs.id, (select id from public.tipos_dieta where empresa_id is null and codigo = d.cod), (select id from public.grupos_poblacion where contrato_id = v_ct and codigo = 'M'), cs.ini, v_m, 'SIMULADA: BD de dietas de practica (reemplazar con la BD real)');
          n_die := n_die + 1;
        end if;
      end loop;
      -- gestantes solo donde hay mujeres
      if cs.m > 0 then
        insert into public.dietas_poblacion (empresa_id, contrato_sede_id, tipo_dieta_id, grupo_poblacion_id, fecha_desde, cantidad, fuente)
        values (v_emp, cs.id, (select id from public.tipos_dieta where empresa_id is null and codigo = 'GESTANTE'), (select id from public.grupos_poblacion where contrato_id = v_ct and codigo = 'M'), cs.ini, greatest(1, round(cs.m * 0.015)::int), 'SIMULADA: BD de dietas de practica (reemplazar con la BD real)');
        n_die := n_die + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('colegios_nuevos', n_pae, 'establecimientos_nuevos', n_usp, 'cupos_pae', n_cup, 'filas_dietas', n_die);
end $$;
revoke all on function public.simular_poblacion(double precision) from public, anon;

select public.simular_poblacion();

-- ---------------------------------------------------------------------
-- 3. Vista plana para exportar y revisar la poblacion vigente
-- ---------------------------------------------------------------------
create or replace view public.v_poblacion_vigente as
select e.nombre_corto as empresa, c.numero as contrato, c.modalidad, se.nombre as sede, se.ciudad, se.subtipo,
       g.codigo as grupo, g.nombre as grupo_nombre, tc.codigo as tiempo, v.codigo as variante, cu.fecha_desde, cu.cantidad, cu.fuente, cs.id as contrato_sede_id, c.empresa_id
  from public.cupos cu
  join public.contrato_sedes cs on cs.id = cu.contrato_sede_id
  join public.sedes se on se.id = cs.sede_id
  join public.contratos c on c.id = cs.contrato_id
  join public.empresas e on e.id = c.empresa_id
  join public.grupos_poblacion g on g.id = cu.grupo_poblacion_id
  left join public.tiempos_comida tc on tc.id = cu.tiempo_comida_id
  left join public.variantes_racion v on v.id = cu.variante_id
 where cu.fecha_hasta is null;
alter view public.v_poblacion_vigente set (security_invoker = true);

create or replace view public.v_dietas_vigentes as
select e.nombre_corto as empresa, c.numero as contrato, se.nombre as sede, td.codigo as dieta, td.nombre_oficial as dieta_nombre, g.codigo as grupo,
       dp.fecha_desde, dp.cantidad, dp.fuente, cs.id as contrato_sede_id, c.empresa_id
  from public.dietas_poblacion dp
  join public.contrato_sedes cs on cs.id = dp.contrato_sede_id
  join public.sedes se on se.id = cs.sede_id
  join public.contratos c on c.id = cs.contrato_id
  join public.empresas e on e.id = c.empresa_id
  join public.tipos_dieta td on td.id = dp.tipo_dieta_id
  left join public.grupos_poblacion g on g.id = dp.grupo_poblacion_id
 where dp.fecha_hasta is null;
alter view public.v_dietas_vigentes set (security_invoker = true);
grant select on public.v_poblacion_vigente, public.v_dietas_vigentes to authenticated;
