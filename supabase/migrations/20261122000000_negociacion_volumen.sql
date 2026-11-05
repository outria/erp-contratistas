-- Supply ERP · Migracion 022 · Negociacion por volumen (Compras): proyeccion consolidada de varios contratos
-- (de una o varias empresas del grupo) y calculadora de cobertura: con X kilos o contenedores, que programas cubro y hasta que fecha.
set client_min_messages = warning;

-- 1. Las empresas de practica forman su propio grupo para poder consolidar entre ellas
do $$
declare v_g uuid;
begin
  select id into v_g from public.grupos where nombre = 'Grupo de practica';
  if v_g is null then insert into public.grupos (nombre) values ('Grupo de practica') returning id into v_g; end if;
  update public.empresas set grupo_id = v_g where nit in ('900000001', '900000002', '900000003') and grupo_id is null;
  -- catalogo maestro del grupo de practica (los productos son copias del mismo catalogo: casan exactos y quedan aprobados)
  perform public.sugerir_catalogo_maestro(v_g);
end $$;

-- 2. Correcciones: es_admin_sql() en vez de auth.uid() is null (regla del protocolo) y grupo obligatorio
create or replace function public.puede_ver_consolidada(p_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.es_superadmin() or public.es_admin_sql() or not exists (
    select 1 from public.proyecciones_consolidadas pc cross join unnest(pc.contratos) ct(id) join public.contratos c on c.id = ct.id
     where pc.id = p_id and not (public.tiene_permiso(c.empresa_id, 'M2', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver')));
$$;

create or replace function public.crear_proyeccion_consolidada(p_contratos uuid[], p_desde date, p_hasta date, p_nombre text default null,
                                                               p_incluye_dietas boolean default true, p_incluye_propuestos boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_grupo uuid; v_n int; c record; v_id uuid; v_ex uuid;
begin
  if coalesce(array_length(p_contratos, 1), 0) = 0 then raise exception 'Seleccione al menos un contrato.'; end if;
  if p_hasta < p_desde then raise exception 'El periodo esta al reves.'; end if;
  if p_hasta - p_desde > 366 then raise exception 'Maximo un ano por proyeccion.'; end if;
  select count(distinct e.grupo_id), min(e.grupo_id::text)::uuid into v_n, v_grupo
    from public.contratos ct join public.empresas e on e.id = ct.empresa_id where ct.id = any (p_contratos);
  if v_grupo is null then raise exception 'La empresa no pertenece a un grupo empresarial; pidale al administrador que la asigne.'; end if;
  if v_n > 1 then raise exception 'Todos los contratos deben ser de empresas del mismo grupo.'; end if;
  for c in select ct.id, ct.numero, ct.empresa_id from public.contratos ct where ct.id = any (p_contratos) loop
    if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver')) then
      raise exception 'Sin permiso para proyectar el contrato % (Planeacion o Compras: ver).', c.numero;
    end if;
  end loop;
  insert into public.proyecciones_consolidadas (grupo_id, nombre, fecha_desde, fecha_hasta, contratos, incluye_dietas, incluye_propuestos, creado_por)
  values (v_grupo, p_nombre, p_desde, p_hasta, p_contratos, p_incluye_dietas, p_incluye_propuestos, auth.uid()) returning id into v_id;
  for c in select ct.id from public.contratos ct where ct.id = any (p_contratos) loop
    v_ex := public.crear_explosion(c.id, p_desde, p_hasta, null, p_incluye_dietas, 'ninguno', coalesce(p_nombre, 'Consolidada'), 'proyeccion', p_incluye_propuestos);
    update public.explosiones set proyeccion_consolidada_id = v_id where id = v_ex;
  end loop;
  return v_id;
end $$;

-- 3. Contratos del grupo que el usuario puede proyectar (para armar la seleccion por empresa)
create or replace function public.contratos_grupo(p_empresa uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_grupo uuid;
begin
  select grupo_id into v_grupo from public.empresas where id = p_empresa;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', ct.id, 'numero', ct.numero, 'modalidad', ct.modalidad, 'estado', ct.estado, 'empresa_id', e.id, 'empresa', e.nombre_corto,
                   'sedes', (select count(*) from public.contrato_sedes cs where cs.contrato_id = ct.id and cs.estado = 'activa'),
                   'cupos', (select coalesce(sum(cu.cantidad), 0) from public.cupos cu join public.contrato_sedes cs on cs.id = cu.contrato_sede_id where cs.contrato_id = ct.id and cu.fecha_hasta is null)) order by e.nombre_corto, ct.numero), '[]')
            from public.contratos ct join public.empresas e on e.id = ct.empresa_id
           where (e.grupo_id = v_grupo or e.id = p_empresa) and ct.estado in ('vigente', 'borrador', 'suspendido')
             and (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(e.id, 'M2', 'ver') or public.tiene_permiso(e.id, 'M3', 'ver')));
end $$;
revoke all on function public.contratos_grupo(uuid) from public, anon;

-- 4. Lista y detalle para la pantalla
create or replace function public.consolidadas_lista(p_empresa uuid, p_limite int default 40)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_grupo uuid;
begin
  select grupo_id into v_grupo from public.empresas where id = p_empresa;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', pc.id, 'nombre', pc.nombre, 'desde', pc.fecha_desde, 'hasta', pc.fecha_hasta, 'dias', pc.fecha_hasta - pc.fecha_desde + 1,
                   'estado', pc.estado, 'n_contratos', coalesce(array_length(pc.contratos, 1), 0), 'calculada_en', pc.calculada_en, 'creado_en', pc.creado_en,
                   'empresas', (select string_agg(distinct e.nombre_corto, ', ') from unnest(pc.contratos) x(id) join public.contratos ct on ct.id = x.id join public.empresas e on e.id = ct.empresa_id),
                   'calculadas', (select count(*) from public.explosiones ex where ex.proyeccion_consolidada_id = pc.id and ex.estado = 'calculada'),
                   'raciones', (select coalesce(sum(ex.raciones), 0) from public.explosiones ex where ex.proyeccion_consolidada_id = pc.id)) order by pc.creado_en desc), '[]')
            from (select * from public.proyecciones_consolidadas p where p.grupo_id = v_grupo and p.estado <> 'anulada' and public.puede_ver_consolidada(p.id) order by p.creado_en desc limit p_limite) pc);
end $$;
revoke all on function public.consolidadas_lista(uuid, int) from public, anon;

create or replace function public.consolidada_detalle(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public set jit = off as $$
declare pc public.proyecciones_consolidadas;
begin
  select * into pc from public.proyecciones_consolidadas where id = p_id;
  if pc.id is null then raise exception 'Proyeccion no encontrada'; end if;
  if not public.puede_ver_consolidada(p_id) then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'proyeccion', jsonb_build_object('id', pc.id, 'nombre', pc.nombre, 'desde', pc.fecha_desde, 'hasta', pc.fecha_hasta, 'dias', pc.fecha_hasta - pc.fecha_desde + 1, 'estado', pc.estado,
                    'incluye_dietas', pc.incluye_dietas, 'incluye_propuestos', pc.incluye_propuestos, 'calculada_en', pc.calculada_en),
    'explosiones', (select coalesce(jsonb_agg(jsonb_build_object('id', ex.id, 'contrato_id', ex.contrato_id, 'contrato', ct.numero, 'empresa', e.nombre_corto, 'modalidad', ct.modalidad, 'estado', ex.estado, 'raciones', ex.raciones,
                       'n_sedes', (select count(*) from public.contrato_sedes cs where cs.contrato_id = ct.id and cs.estado = 'activa'),
                       'dias_cubiertos', (select count(*) from generate_series(ex.fecha_desde, ex.fecha_hasta, interval '1 day') g where ex.cubierto @> g::date)) order by e.nombre_corto, ct.numero), '[]')
                      from public.explosiones ex join public.contratos ct on ct.id = ex.contrato_id join public.empresas e on e.id = ct.empresa_id where ex.proyeccion_consolidada_id = p_id),
    'productos', case when pc.estado = 'calculada' then (select coalesce(jsonb_agg(to_jsonb(r) order by r.cantidad_base desc), '[]') from public.resumen_proyeccion_consolidada(p_id) r) else '[]'::jsonb end
  );
end $$;
revoke all on function public.consolidada_detalle(uuid) from public, anon;

create or replace function public.anular_consolidada(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.puede_ver_consolidada(p_id) then raise exception 'Sin permiso'; end if;
  update public.proyecciones_consolidadas set estado = 'anulada' where id = p_id;
  update public.explosiones set estado = 'anulada' where proyeccion_consolidada_id = p_id and estado not in ('aprobada', 'enviada_compras');
end $$;
revoke all on function public.anular_consolidada(uuid) from public, anon;

-- 5. Calculadora de cobertura: con una cantidad de un producto (maestro o producto), hasta que fecha alcanza para los contratos
--    elegidos (todos los de la consolidada o un subconjunto), repartiendo dia a dia como lo consume cada programa.
--    Devuelve tambien el reparto por contrato (cuanto le toca a cada uno) y el consumo diario.
create or replace function public.cobertura_volumen(p_id uuid, p_maestro uuid, p_cantidad numeric, p_contratos uuid[] default null, p_max_dias int default 730)
returns jsonb language plpgsql security definer set search_path = public set jit = off as $$
declare pc public.proyecciones_consolidadas; acum numeric := 0; n int := 0; d record; prom numeric; extra int := 0; v_dias int; v_hasta date; v_unidad text; v_factor numeric; v_nombre text;
        v_prods uuid[]; v_ctos uuid[];
begin
  select * into pc from public.proyecciones_consolidadas where id = p_id;
  if pc.id is null or not public.puede_ver_consolidada(p_id) then raise exception 'Proyeccion no encontrada'; end if;
  if pc.estado <> 'calculada' then raise exception 'Calcule primero la proyeccion consolidada.'; end if;
  if coalesce(p_cantidad, 0) <= 0 then raise exception 'Indique la cantidad a negociar.'; end if;
  v_dias := pc.fecha_hasta - pc.fecha_desde + 1;
  v_ctos := coalesce(p_contratos, pc.contratos);
  select array_agg(id) into v_prods from public.productos where maestro_id = p_maestro or id = p_maestro;
  select coalesce(pm.nombre, pr.nombre), coalesce(pm.unidad_compra, pr.unidad_compra), coalesce(pm.factor_compra, pr.factor_compra, 1)
    into v_nombre, v_unidad, v_factor
    from (select 1) uno left join public.productos_maestros pm on pm.id = p_maestro left join public.productos pr on pr.id = p_maestro;
  -- consumo diario del conjunto elegido (en unidad base)
  create temp table if not exists tmp_cob (fecha date, contrato_id uuid, c numeric) on commit drop;
  truncate tmp_cob;
  insert into tmp_cob
  select dd.fecha, ex.contrato_id, sum(dd.cantidad_bruta)
    from public.explosiones ex join public.explosion_detalle dd on dd.explosion_id = ex.id
   where ex.proyeccion_consolidada_id = p_id and ex.contrato_id = any (v_ctos) and dd.producto_id = any (v_prods)
   group by 1, 2;
  for d in select g::date as f, coalesce((select sum(t.c) from tmp_cob t where t.fecha = g::date), 0) as c from generate_series(pc.fecha_desde, pc.fecha_hasta, interval '1 day') g order by g loop
    exit when acum + d.c > p_cantidad * v_factor;
    acum := acum + d.c; n := n + 1;
  end loop;
  select coalesce(sum(c), 0) / v_dias into prom from tmp_cob;
  if n >= v_dias and prom > 0 then
    extra := greatest(0, least(p_max_dias - n, floor((p_cantidad * v_factor - acum) / prom)::int));
    acum := acum + extra * prom; n := n + extra;
  end if;
  v_hasta := case when n > 0 then pc.fecha_desde + n - 1 end;
  return jsonb_build_object(
    'producto', v_nombre, 'unidad', v_unidad, 'cantidad', p_cantidad,
    'hasta', v_hasta, 'dias', n, 'extrapolado', extra > 0, 'dias_proyectados', v_dias,
    'consumo_diario', round(prom / v_factor, 3), 'consumo_cubierto', round(acum / v_factor, 3), 'sobrante', round(p_cantidad - acum / v_factor, 3),
    'sin_consumo', prom = 0,
    'por_contrato', (select coalesce(jsonb_agg(jsonb_build_object('contrato_id', x.contrato_id, 'contrato', ct.numero, 'empresa', e.nombre_corto, 'modalidad', ct.modalidad,
                        'promedio_dia', round(x.c / v_dias / v_factor, 3), 'le_toca', round(x.c / nullif((select sum(c) from tmp_cob), 0) * least(p_cantidad, acum / v_factor), 2),
                        'participacion', round(100 * x.c / nullif((select sum(c) from tmp_cob), 0), 1)) order by x.c desc), '[]')
                       from (select contrato_id, sum(c) c from tmp_cob group by 1) x join public.contratos ct on ct.id = x.contrato_id join public.empresas e on e.id = ct.empresa_id),
    'por_mes', (select coalesce(jsonb_agg(jsonb_build_object('mes', x.m, 'cantidad', round(x.c / v_factor, 2)) order by x.m), '[]')
                  from (select to_char(fecha, 'YYYY-MM') m, sum(c) c from tmp_cob group by 1) x)
  );
end $$;
revoke all on function public.cobertura_volumen(uuid, uuid, numeric, uuid[], int) from public, anon;
