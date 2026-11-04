-- Supply ERP · Migracion 020 · Pantalla de explosion de materiales: resumen, detalle por producto y lista de explosiones
set client_min_messages = warning;

-- lectura: M2 ver o M3 ver (compras consume la explosion)
create or replace function public.puede_ver_explosion(p_explosion uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.explosiones e where e.id = p_explosion
                  and (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'ver') or public.tiene_permiso(e.empresa_id, 'M3', 'ver')));
$$;
revoke all on function public.puede_ver_explosion(uuid) from public, anon;

-- ---------------------------------------------------------------------
-- Resumen de una explosion para la pantalla: cabecera, productos (compra), categorias, raciones por sede y por dia
-- ---------------------------------------------------------------------
create or replace function public.explosion_resumen(p_explosion uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare e public.explosiones; r jsonb;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if not public.puede_ver_explosion(p_explosion) then raise exception 'Sin permiso'; end if;
  select jsonb_build_object(
    'explosion', jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'tipo', e.tipo, 'estado', e.estado, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta,
                   'incluye_dietas', e.incluye_dietas, 'incluye_propuestos', e.incluye_propuestos, 'raciones', e.raciones, 'calculada_en', e.calculada_en,
                   'aprobada_en', e.aprobada_en, 'notas', e.notas, 'contrato_id', e.contrato_id,
                   'sedes', (select coalesce(jsonb_agg(jsonb_build_object('id', cs.id, 'nombre', s.nombre) order by s.nombre), '[]')
                               from public.contrato_sedes cs join public.sedes s on s.id = cs.sede_id
                              where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes))),
                   'dias_cubiertos', (select count(*) from generate_series(e.fecha_desde, e.fecha_hasta, interval '1 day') g where e.cubierto @> g::date),
                   'dias', e.fecha_hasta - e.fecha_desde + 1),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('producto_id', v.producto_id, 'codigo', v.codigo, 'nombre', v.nombre, 'categoria', v.categoria,
                    'unidad_base', v.unidad_base, 'unidad_compra', v.unidad_compra, 'factor_compra', v.factor_compra,
                    'cantidad_base', round(v.cantidad_base, 1), 'cantidad_compra', v.cantidad_compra, 'de_linea', round(coalesce(v.de_linea, 0), 1), 'de_dietas', round(coalesce(v.de_dietas, 0), 1),
                    'dias', v.dias, 'promedio_dia', v.promedio_dia, 'perecedero', p.perecedero, 'nivel_riesgo', p.nivel_riesgo) order by v.categoria, v.nombre), '[]')
                    from public.v_explosion_productos v join public.productos p on p.id = v.producto_id where v.explosion_id = p_explosion),
    'categorias', (select coalesce(jsonb_agg(jsonb_build_object('categoria', x.categoria, 'productos', x.n, 'kg', x.kg) order by x.kg desc), '[]')
                     from (select p.categoria, count(distinct d.producto_id) n,
                                  round(sum(case when p.unidad_base in ('g','ml') then d.cantidad_bruta / 1000 else d.cantidad_bruta end), 1) kg
                             from public.explosion_detalle d join public.productos p on p.id = d.producto_id where d.explosion_id = p_explosion group by p.categoria) x),
    'por_sede', (select coalesce(jsonb_agg(jsonb_build_object('sede_id', x.contrato_sede_id, 'sede', s.nombre, 'raciones', x.rac, 'dias', x.dias, 'promedio', round(x.rac::numeric / nullif(x.dias, 0))) order by x.rac desc), '[]')
                   from (select r.contrato_sede_id, sum(r.raciones) rac, count(*) filter (where r.raciones > 0) dias from public.explosion_raciones r where r.explosion_id = p_explosion group by 1) x
                   join public.contrato_sedes cs on cs.id = x.contrato_sede_id join public.sedes s on s.id = cs.sede_id),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('fecha', x.fecha, 'raciones', x.rac, 'sedes', x.n) order by x.fecha), '[]')
                  from (select r.fecha, sum(r.raciones) rac, count(*) filter (where r.raciones > 0) n from public.explosion_raciones r where r.explosion_id = p_explosion group by 1) x),
    'por_tiempo', (select coalesce(jsonb_agg(jsonb_build_object('tiempo', t.codigo, 'nombre', t.nombre, 'raciones', x.rac) order by t.orden), '[]')
                     from (select d.tiempo_comida_id, sum(d.raciones) rac from (select tiempo_comida_id, contrato_sede_id, fecha, grupo_poblacion_id, tipo_dieta_id, max(raciones) raciones
                                                                                   from public.explosion_detalle where explosion_id = p_explosion group by 1,2,3,4,5) d group by 1) x
                     join public.tiempos_comida t on t.id = x.tiempo_comida_id),
    'sin_receta', (select count(*) from (select distinct d.contrato_sede_id, d.fecha from public.explosion_raciones d where d.explosion_id = p_explosion and d.raciones > 0
                     and not exists (select 1 from public.explosion_detalle x where x.explosion_id = p_explosion and x.contrato_sede_id = d.contrato_sede_id and x.fecha = d.fecha)) z)
  ) into r;
  return r;
end $$;
revoke all on function public.explosion_resumen(uuid) from public, anon;

-- ---------------------------------------------------------------------
-- Detalle de un producto dentro de la explosion: por sede, por dia y por preparacion
-- ---------------------------------------------------------------------
create or replace function public.explosion_producto(p_explosion uuid, p_producto uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
begin
  if not public.puede_ver_explosion(p_explosion) then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'por_sede', (select coalesce(jsonb_agg(jsonb_build_object('sede', s.nombre, 'cantidad', round(x.c, 1), 'raciones', x.r, 'dias', x.d) order by x.c desc), '[]')
                   from (select d.contrato_sede_id, sum(d.cantidad_bruta) c, sum(d.raciones) r, count(distinct d.fecha) d from public.explosion_detalle d
                          where d.explosion_id = p_explosion and d.producto_id = p_producto group by 1) x
                   join public.contrato_sedes cs on cs.id = x.contrato_sede_id join public.sedes s on s.id = cs.sede_id),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('fecha', x.fecha, 'cantidad', round(x.c, 1), 'sedes', x.n) order by x.fecha), '[]')
                  from (select d.fecha, sum(d.cantidad_bruta) c, count(distinct d.contrato_sede_id) n from public.explosion_detalle d
                         where d.explosion_id = p_explosion and d.producto_id = p_producto group by 1) x),
    'por_preparacion', (select coalesce(jsonb_agg(jsonb_build_object('preparacion', pr.nombre, 'componente', c.codigo, 'tiempo', t.codigo, 'cantidad', round(x.c, 1), 'raciones', x.r,
                                                                    'crudo_racion', round(x.cr, 2), 'ajustes', x.aj, 'dieta', x.dieta) order by x.c desc), '[]')
                          from (select d.preparacion_id, d.componente_id, d.tiempo_comida_id, (d.tipo_dieta_id is not null) dieta, sum(d.cantidad_bruta) c, sum(d.raciones) r,
                                       sum(d.cantidad_bruta) / nullif(sum(d.raciones), 0) cr, string_agg(distinct d.ajuste_aplicado, ' · ') aj
                                  from public.explosion_detalle d where d.explosion_id = p_explosion and d.producto_id = p_producto group by 1, 2, 3, 4) x
                          left join public.preparaciones pr on pr.id = x.preparacion_id
                          left join public.componentes c on c.id = x.componente_id
                          left join public.tiempos_comida t on t.id = x.tiempo_comida_id)
  );
end $$;
revoke all on function public.explosion_producto(uuid, uuid) from public, anon;

-- ---------------------------------------------------------------------
-- Lista de explosiones del contrato (para la pantalla) con cobertura y creador
-- ---------------------------------------------------------------------
create or replace function public.explosiones_contrato(p_contrato uuid, p_limite int default 60)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'ver') or public.tiene_permiso(v_emp, 'M3', 'ver')) then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'codigo', e.codigo, 'nombre', e.nombre, 'tipo', e.tipo, 'estado', e.estado, 'desde', e.fecha_desde, 'hasta', e.fecha_hasta,
                   'dias', e.fecha_hasta - e.fecha_desde + 1, 'raciones', e.raciones, 'calculada_en', e.calculada_en, 'creado_en', e.creado_en, 'incluye_dietas', e.incluye_dietas,
                   'n_sedes', coalesce(array_length(e.sedes, 1), (select count(*) from public.contrato_sedes cs where cs.contrato_id = e.contrato_id and cs.estado = 'activa')),
                   'productos', (select count(distinct d.producto_id) from public.explosion_detalle d where d.explosion_id = e.id),
                   'creado_por', (select coalesce(u.raw_user_meta_data->>'nombre', u.email) from auth.users u where u.id = e.creado_por)) order by e.creado_en desc), '[]')
            from (select * from public.explosiones x where x.contrato_id = p_contrato and x.estado <> 'anulada' order by x.creado_en desc limit p_limite) e);
end $$;
revoke all on function public.explosiones_contrato(uuid, int) from public, anon;

-- anular una explosion (no se borra: queda para la trazabilidad)
create or replace function public.anular_explosion(p_explosion uuid) returns void language plpgsql security definer set search_path = public as $$
declare e public.explosiones;
begin
  select * into e from public.explosiones where id = p_explosion;
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then raise exception 'Sin permiso (Planeacion: crear).'; end if;
  if e.estado = 'enviada_compras' then raise exception 'Ya fue enviada a compras; anule desde compras.'; end if;
  update public.explosiones set estado = 'anulada' where id = p_explosion;
end $$;
revoke all on function public.anular_explosion(uuid) from public, anon;

-- el calculo por tramos ya existe; el planificador debe saber que explosion_detalle crece mucho
create index if not exists explosion_detalle_prod_idx on public.explosion_detalle (explosion_id, producto_id);

-- ---------------------------------------------------------------------
-- Correccion: raciones del tramo en PAE (sumaba solo el maximo por tiempo)
-- ---------------------------------------------------------------------
create or replace function public.calcular_explosion(p_explosion uuid, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_sedes uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(filas integer, raciones integer, productos integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 set search_path = public set jit = off as $function$
declare e public.explosiones; v_filas int := 0; v_rac int := 0; n int; v_hay_sust boolean; d1 date; d2 date; v_total boolean;
begin
  select * into e from public.explosiones where id = p_explosion for update;   -- M1: un calculo a la vez por explosion
  if e.id is null then raise exception 'Explosion no encontrada'; end if;
  if e.tipo = 'requerimiento' then
    if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'crear')) then
      raise exception 'Sin permiso para calcular requerimientos (Planeacion: crear).';
    end if;
    if e.estado in ('aprobada','enviada_compras') then raise exception 'El requerimiento ya esta aprobado; cree uno nuevo.'; end if;
  elsif not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.empresa_id, 'M2', 'ver') or public.tiene_permiso(e.empresa_id, 'M3', 'ver')) then
    raise exception 'Sin permiso para proyectar (Planeacion o Compras: ver).';
  end if;
  v_hay_sust := exists (select 1 from public.intercambios_menu x where x.contrato_id = e.contrato_id and x.tipo_cambio = 'ingrediente'
                          and x.vigente_desde <= e.fecha_hasta and (x.vigente_hasta is null or x.vigente_hasta >= e.fecha_desde)
                          and public.intercambio_aplica(x.estado, x.clase, e.incluye_propuestos));
  d1 := greatest(coalesce(p_desde, e.fecha_desde), e.fecha_desde); d2 := least(coalesce(p_hasta, e.fecha_hasta), e.fecha_hasta);
  v_total := p_desde is null and p_hasta is null and p_sedes is null;
  if v_total then
    delete from public.explosion_detalle where explosion_id = p_explosion;
    delete from public.explosion_raciones where explosion_id = p_explosion;
  else
    delete from public.explosion_detalle where explosion_id = p_explosion and fecha between d1 and d2 and (p_sedes is null or contrato_sede_id = any (p_sedes));
    delete from public.explosion_raciones where explosion_id = p_explosion and fecha between d1 and d2 and (p_sedes is null or contrato_sede_id = any (p_sedes));
  end if;

  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;
  create temp table tmp_exp_dias as
  select cs.id as sede_id, g::date as fecha, dc.dia
    from public.contrato_sedes cs
    cross join generate_series(d1, d2, interval '1 day') g
    cross join lateral public.dia_ciclo(cs.id, g::date) dc
   where cs.contrato_id = e.contrato_id and cs.estado = 'activa' and (e.sedes is null or cs.id = any (e.sedes))
     and (p_sedes is null or cs.id = any (p_sedes));
  create temp table tmp_exp_menu as
  select d.sede_id, d.fecha, m.*
    from tmp_exp_dias d cross join lateral public.menu_del_dia(d.sede_id, d.fecha, e.incluye_propuestos) m
   where m.preparacion_id is not null;
  create index on tmp_exp_menu (sede_id, fecha);
  create temp table tmp_exp_pob as
  select d.sede_id, d.fecha, p.*
    from tmp_exp_dias d cross join lateral public.poblacion_dia(d.sede_id, d.fecha) p;
  create index on tmp_exp_pob (sede_id, fecha);
  analyze tmp_exp_menu; analyze tmp_exp_pob;

  -- ---- linea
  insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
  select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, m.preparacion_id,
         coalesce(si.producto_id, ing.producto_id), p.grupo_poblacion_id, null, p.linea,
         cr.crudo * coalesce(si.factor, 1), p.linea * cr.crudo * coalesce(si.factor, 1),
         nullif(concat_ws(' · ', cr.nota, case when si.producto_id is not null then 'intercambio de ingrediente' end), '')
    from tmp_exp_menu m
    join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id)
                      and (p.tiempo_comida_id is null or p.tiempo_comida_id = m.tiempo_comida_id) and p.linea > 0
    join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                   where pi.preparacion_id = m.preparacion_id and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                   order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
    cross join lateral public.crudo_ingrediente(e.contrato_id, m.sede_id, m.fecha, m.preparacion_id, ing.producto_id, p.grupo_poblacion_id, m.componente_id, ing.peso_bruto) cr
    left join lateral (select * from public.sustitucion_ingrediente(m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos) where v_hay_sust) si on true;
  get diagnostics n = row_count; v_filas := v_filas + n;

  -- ---- dietas: reglas con prioridad contrato > empresa > catalogo (una regla inactiva del contrato anula la del catalogo);
  --      la poblacion en dieta se prorratea si supera la del grupo
  if e.incluye_dietas then
    insert into public.explosion_detalle (empresa_id, explosion_id, contrato_sede_id, fecha, dia_ciclo, tiempo_comida_id, componente_id, preparacion_id, producto_id, grupo_poblacion_id, tipo_dieta_id, raciones, crudo_por_racion, cantidad_bruta, ajuste_aplicado)
    select e.empresa_id, p_explosion, m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, vp.prep,
           coalesce(rs.sust, si.producto_id, ing.producto_id), p.grupo_poblacion_id, dd.tipo_dieta_id, dd.cant,
           x.crudo_final, dd.cant * x.crudo_final, x.nota
      from tmp_exp_menu m
      join tmp_exp_pob p on p.sede_id = m.sede_id and p.fecha = m.fecha and (p.variante_id is null or p.variante_id = m.variante_id)
                        and p.tiempo_comida_id is null and p.en_dieta > 0
      join lateral (select z.tipo_dieta_id,
                           case when sum(z.c) over () > p.en_dieta then floor(z.c * p.en_dieta::numeric / sum(z.c) over ())::int else z.c end as cant
                      from (select dp.tipo_dieta_id, sum(dp.cantidad)::int as c from public.dietas_poblacion dp
                             where dp.contrato_sede_id = m.sede_id and dp.grupo_poblacion_id = p.grupo_poblacion_id
                               and dp.fecha_desde <= m.fecha and (dp.fecha_hasta is null or dp.fecha_hasta >= m.fecha)
                             group by dp.tipo_dieta_id) z) dd on dd.cant > 0
      left join lateral (select q.* from public.dieta_equivalencias q where q.contrato_id = e.contrato_id and q.tipo_dieta_id = dd.tipo_dieta_id
                           and (q.contrato_sede_id = m.sede_id or q.contrato_sede_id is null) order by q.contrato_sede_id nulls last limit 1) eq on true
      cross join lateral (select coalesce(eq.equivale_a_id, dd.tipo_dieta_id) as dieta) de
      left join lateral (select ds.preparacion_id from public.dieta_estandar ds
                          where ds.contrato_id = e.contrato_id and (ds.contrato_sede_id = m.sede_id or ds.contrato_sede_id is null)
                            and (ds.tipo_dieta_id = dd.tipo_dieta_id or ds.tipo_dieta_id is null) and (ds.tiempo_comida_id = m.tiempo_comida_id or ds.tiempo_comida_id is null)
                            and ds.componente_codigo = m.componente_codigo and ds.vigente_desde <= m.fecha and (ds.vigente_hasta is null or ds.vigente_hasta >= m.fecha)
                          order by ds.contrato_sede_id nulls last, ds.tipo_dieta_id nulls last, ds.tiempo_comida_id nulls last, ds.vigente_desde desc limit 1) ds on true
      cross join lateral (select coalesce(ds.preparacion_id, case when m.componente_codigo = 'PROTEICO' then eq.preparacion_proteico_id end, m.preparacion_id) as prep) vp
      cross join lateral (
        select bool_or(r.activa and r.tipo_regla = 'excluir_componente') as excl,
               max(r.valor) filter (where r.activa and r.tipo_regla = 'factor_porcion') as factor,
               max(r.valor) filter (where r.activa and r.tipo_regla = 'porcion_fija') as fija
          from (select distinct on (rd.tipo_regla) rd.*
                  from public.reglas_dieta rd
                 where rd.tipo_dieta_id = de.dieta and rd.componente_codigo = m.componente_codigo
                   and rd.tipo_regla in ('excluir_componente','factor_porcion','porcion_fija')
                   and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and (rd.empresa_id is null or rd.empresa_id = e.empresa_id)))
                 order by rd.tipo_regla, (rd.contrato_id is null), (rd.empresa_id is null)) r) rg
      join lateral (select distinct on (pi.producto_id) pi.* from public.preparacion_ingredientes pi
                     where pi.preparacion_id = vp.prep and (pi.grupo_poblacion_id = p.grupo_poblacion_id or pi.grupo_poblacion_id is null)
                     order by pi.producto_id, pi.grupo_poblacion_id nulls last) ing on true
      left join public.productos prod on prod.id = ing.producto_id
      left join lateral (
        select bool_or(r.activa and r.tipo_regla in ('excluir_producto','excluir_categoria')) as excl,
               max(r.producto_sustituto_id::text) filter (where r.activa and r.tipo_regla = 'sustituir_producto')::uuid as sust
          from (select distinct on (rd.tipo_regla) rd.*
                  from public.reglas_dieta rd
                 where rd.tipo_dieta_id = de.dieta
                   and ((rd.tipo_regla in ('excluir_producto','sustituir_producto') and rd.producto_id = ing.producto_id)
                     or (rd.tipo_regla = 'excluir_categoria' and rd.categoria_producto = prod.categoria))
                   and (rd.contrato_id = e.contrato_id or (rd.contrato_id is null and (rd.empresa_id is null or rd.empresa_id = e.empresa_id)))
                 order by rd.tipo_regla, (rd.contrato_id is null), (rd.empresa_id is null)) r) rs on true
      cross join lateral public.crudo_ingrediente(e.contrato_id, m.sede_id, m.fecha, vp.prep, ing.producto_id, p.grupo_poblacion_id, m.componente_id, ing.peso_bruto) cr
      left join lateral (select * from public.sustitucion_ingrediente(m.sede_id, m.fecha, m.dia, m.tiempo_comida_id, m.componente_id, ing.producto_id, e.incluye_propuestos) where v_hay_sust and rs.sust is null) si on true
      cross join lateral (
        select (case when ing.es_principal and rg.fija is not null then rg.fija / coalesce(prod.rendimiento, 1)
                     when ing.es_principal and coalesce(rg.factor, 1) <> 1 then cr.crudo * rg.factor
                     else cr.crudo end) * coalesce(si.factor, 1) as crudo_final,
               nullif(concat_ws(' · ',
                 case when ing.es_principal and rg.fija is not null then 'dieta: porcion fija ' || rg.fija
                      when ing.es_principal and coalesce(rg.factor, 1) <> 1 then 'dieta: factor ' || rg.factor
                      else cr.nota end,
                 case when rs.sust is not null then 'dieta: sustituido' end,
                 case when vp.prep <> m.preparacion_id then 'dieta: preparacion unificada' end,
                 case when si.producto_id is not null then 'intercambio de ingrediente' end), '') as nota) x
     where not coalesce(rg.excl, false) and not coalesce(rs.excl, false);
    get diagnostics n = row_count; v_filas := v_filas + n;
  end if;

  -- raciones del tramo (personas-dia con servicio) y cobertura
  insert into public.explosion_raciones (explosion_id, contrato_sede_id, fecha, raciones)
  -- cada fila de poblacion_dia es una poblacion distinta (grupo x variante x tiempo): se suman todas (antes tomaba el maximo por tiempo y subcontaba PAE)
  select p_explosion, p.sede_id, p.fecha, coalesce(sum(p.total), 0)
    from tmp_exp_pob p group by p.sede_id, p.fecha;
  select coalesce(sum(r.raciones), 0) into v_rac from public.explosion_raciones r where r.explosion_id = p_explosion;
  drop table if exists tmp_exp_dias; drop table if exists tmp_exp_menu; drop table if exists tmp_exp_pob;

  update public.explosiones
     set cubierto = case when v_total then datemultirange(daterange(e.fecha_desde, e.fecha_hasta, '[]'))
                         when p_sedes is null then cubierto + datemultirange(daterange(d1, d2, '[]'))
                         else cubierto end,          -- un tramo por sedes no cambia la cobertura por fechas
         raciones = v_rac, calculada_en = now()
   where id = p_explosion;
  update public.explosiones
     set estado = case when cubierto @> daterange(fecha_desde, fecha_hasta, '[]') then 'calculada' else 'parcial' end
   where id = p_explosion and estado in ('borrador','parcial','calculada');
  return query select v_filas, v_rac, (select count(distinct producto_id)::int from public.explosion_detalle where explosion_id = p_explosion);
end $function$


