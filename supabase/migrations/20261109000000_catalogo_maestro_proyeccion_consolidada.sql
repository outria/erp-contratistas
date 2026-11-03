-- =====================================================================
-- Supply ERP · Migracion 009 · Parte 4B-2 (02-nov-2026)
-- 1. Catalogo maestro por grupo empresarial: cada producto de cada empresa (UT Diestra, UT Nutrifood...) apunta a un
--    producto maestro del grupo (Fombisol / Alimentar Capital). El mapeo se sugiere por parecido de nombre y se aprueba.
--    Es lo que permite sumar "pechuga" de una UT con "pechuga" de la otra para comprar en un CEDI compartido o importar.
-- 2. Proyeccion consolidada: varios contratos (de una o varias empresas del grupo) en un mismo periodo, sumados por
--    producto maestro, con el detalle por empresa. Solo entran contratos donde el usuario tiene Planeacion o Compras: ver.
-- 3. Calculo inverso consolidado: con X kg de un maestro (un contenedor), hasta que fecha alcanza para todos los contratos.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Catalogo maestro
-- ---------------------------------------------------------------------
create table public.productos_maestros (
  id              uuid primary key default gen_random_uuid(),
  grupo_id        uuid not null references public.grupos(id),
  codigo          text not null,
  nombre          text not null,
  nombre_norm     text not null,                    -- para buscar parecidos
  categoria       text not null default 'abarrotes',
  unidad_base     text not null default 'g' check (unidad_base in ('g','ml','und')),
  unidad_compra   text not null default 'kg',
  factor_compra   numeric(14,4) not null default 1000,
  subfamilia      text,                              -- Res, Pollo, Huevo, Papa...
  importable      boolean not null default false,    -- candidato a compra por contenedor
  estado          text not null default 'activo' check (estado in ('activo','inactivo')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (grupo_id, codigo)
);
create index productos_maestros_trgm on public.productos_maestros using gin (nombre_norm extensions.gin_trgm_ops);

alter table public.productos add column maestro_id uuid references public.productos_maestros(id);
alter table public.productos add column maestro_estado text check (maestro_estado in ('sugerido','aprobado','rechazado'));
alter table public.productos add column maestro_similitud numeric(5,3);
create index productos_maestro_idx on public.productos (maestro_id);

-- nombre normalizado: minusculas, sin tildes, sin palabras de estado (crudo, fresco...) ni signos
create or replace function public.normalizar_nombre_producto(p text) returns text language sql immutable as $$
  select trim(regexp_replace(regexp_replace(
           lower(translate(coalesce(p, ''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')),
           '\m(crudo|cruda|crudos|crudas|fresco|fresca|entero|entera|natural|x|por|de|la|el|con|sin)\M', ' ', 'g'),
           '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.mantener_nombre_norm() returns trigger language plpgsql as $$
begin new.nombre_norm := public.normalizar_nombre_producto(new.nombre); return new; end $$;
create trigger productos_maestros_norm before insert or update of nombre on public.productos_maestros for each row execute function public.mantener_nombre_norm();
create trigger productos_maestros_actualizacion before update on public.productos_maestros for each row execute function public.marcar_actualizacion();
create trigger productos_maestros_bitacora after insert or update or delete on public.productos_maestros for each row execute function public.registrar_bitacora();

-- el usuario tiene ese permiso en alguna empresa del grupo
create or replace function public.tiene_permiso_grupo(p_grupo uuid, p_modulo text, p_accion public.accion_permiso)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.empresas e where e.grupo_id = p_grupo and public.tiene_permiso(e.id, p_modulo, p_accion));
$$;
create or replace function public.es_miembro_grupo(p_grupo uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.empresas e where e.grupo_id = p_grupo and public.es_miembro(e.id));
$$;
grant execute on function public.tiene_permiso_grupo(uuid, text, public.accion_permiso), public.es_miembro_grupo(uuid) to authenticated;

alter table public.productos_maestros enable row level security;
create policy productos_maestros_ver on public.productos_maestros for select to authenticated using (public.es_superadmin() or public.es_miembro_grupo(grupo_id));
create policy productos_maestros_crear on public.productos_maestros for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso_grupo(grupo_id, 'M13', 'crear'));
create policy productos_maestros_editar on public.productos_maestros for update to authenticated
  using (public.es_superadmin() or public.tiene_permiso_grupo(grupo_id, 'M13', 'editar')) with check (public.es_superadmin() or public.tiene_permiso_grupo(grupo_id, 'M13', 'editar'));
grant select, insert, update on public.productos_maestros to authenticated;

-- Sugiere el maestro de cada producto del grupo que no tenga uno aprobado.
-- Igual nombre normalizado y unidad -> aprobado de una; parecido >= umbral -> sugerido; sin parecido -> crea el maestro desde el producto.
create or replace function public.sugerir_catalogo_maestro(p_grupo uuid, p_umbral numeric default 0.55)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare p record; m record; n_ap int := 0; n_sug int := 0; n_nuevo int := 0; v_cod text; v_id uuid;
begin
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso_grupo(p_grupo, 'M13', 'crear')) then
    raise exception 'Sin permiso (Maestros: crear en alguna empresa del grupo).';
  end if;
  for p in select pr.*, public.normalizar_nombre_producto(pr.nombre) as norm, e.nombre_corto
             from public.productos pr join public.empresas e on e.id = pr.empresa_id
            where e.grupo_id = p_grupo and pr.estado = 'activo'
              and (pr.maestro_id is null or pr.maestro_estado = 'sugerido')
            order by e.creado_en, pr.codigo loop
    select pm.id, pm.nombre_norm, extensions.similarity(pm.nombre_norm, p.norm) as sim into m
      from public.productos_maestros pm
     where pm.grupo_id = p_grupo and pm.estado = 'activo' and pm.unidad_base = p.unidad_base
       and (pm.nombre_norm operator(extensions.%) p.norm or pm.nombre_norm = p.norm)
       -- dos productos distintos de la misma empresa no se funden solos (arveja seca vs arveja verde, res vs cerdo)
       and not exists (select 1 from public.productos o where o.maestro_id = pm.id and o.empresa_id = p.empresa_id and o.id <> p.id)
     order by (pm.nombre_norm = p.norm) desc, extensions.similarity(pm.nombre_norm, p.norm) desc
     limit 1;
    if m.id is not null and m.nombre_norm = p.norm then
      update public.productos set maestro_id = m.id, maestro_estado = 'aprobado', maestro_similitud = 1 where id = p.id;
      n_ap := n_ap + 1;
    elsif m.id is not null and m.sim >= p_umbral then
      update public.productos set maestro_id = m.id, maestro_estado = 'sugerido', maestro_similitud = round(m.sim::numeric, 3) where id = p.id;
      n_sug := n_sug + 1;
    elsif p.maestro_id is null then
      v_cod := upper(regexp_replace(p.norm, '\s+', '_', 'g'));
      if exists (select 1 from public.productos_maestros where grupo_id = p_grupo and codigo = v_cod) then v_cod := v_cod || '_' || substr(gen_random_uuid()::text, 1, 4); end if;
      insert into public.productos_maestros (grupo_id, codigo, nombre, nombre_norm, categoria, unidad_base, unidad_compra, factor_compra, subfamilia)
      values (p_grupo, v_cod, p.nombre, p.norm, p.categoria, p.unidad_base, p.unidad_compra, p.factor_compra, trim(split_part(p.nombre, ',', 1)))
      returning id into v_id;
      update public.productos set maestro_id = v_id, maestro_estado = 'aprobado', maestro_similitud = 1 where id = p.id;
      n_nuevo := n_nuevo + 1;
    end if;
  end loop;
  return jsonb_build_object('aprobados_por_nombre_igual', n_ap, 'sugeridos_para_revisar', n_sug, 'maestros_nuevos', n_nuevo);
end $$;

-- Aprobar, cambiar o rechazar el maestro de un producto (rechazar crea un maestro propio para ese producto)
create or replace function public.decidir_mapeo_maestro(p_producto uuid, p_decision text, p_maestro uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare pr public.productos; v_grupo uuid; v_id uuid;
begin
  select * into pr from public.productos where id = p_producto;
  if pr.id is null then raise exception 'Producto no encontrado'; end if;
  select grupo_id into v_grupo from public.empresas where id = pr.empresa_id;
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso_grupo(v_grupo, 'M13', 'aprobar')) then raise exception 'Sin permiso (Maestros: aprobar).'; end if;
  if p_decision = 'aprobar' then
    update public.productos set maestro_id = coalesce(p_maestro, maestro_id), maestro_estado = 'aprobado' where id = p_producto;
  elsif p_decision = 'rechazar' then
    insert into public.productos_maestros (grupo_id, codigo, nombre, nombre_norm, categoria, unidad_base, unidad_compra, factor_compra, subfamilia)
    values (v_grupo, upper(regexp_replace(public.normalizar_nombre_producto(pr.nombre), '\s+', '_', 'g')) || '_' || substr(gen_random_uuid()::text, 1, 4),
            pr.nombre, public.normalizar_nombre_producto(pr.nombre), pr.categoria, pr.unidad_base, pr.unidad_compra, pr.factor_compra, trim(split_part(pr.nombre, ',', 1)))
    returning id into v_id;
    update public.productos set maestro_id = v_id, maestro_estado = 'aprobado', maestro_similitud = null where id = p_producto;
  else raise exception 'Decision no valida (aprobar, rechazar)'; end if;
end $$;

-- los productos nuevos (incluido el chorizo creado en caliente) reciben sugerencia de maestro al crearse
create or replace function public.sugerir_maestro_producto_nuevo() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_grupo uuid; m record; v_norm text;
begin
  if new.maestro_id is not null then return new; end if;
  select grupo_id into v_grupo from public.empresas where id = new.empresa_id;
  if v_grupo is null then return new; end if;
  v_norm := public.normalizar_nombre_producto(new.nombre);
  select pm.id, extensions.similarity(pm.nombre_norm, v_norm) as sim, pm.nombre_norm into m
    from public.productos_maestros pm where pm.grupo_id = v_grupo and pm.estado = 'activo' and pm.unidad_base = new.unidad_base
     and not exists (select 1 from public.productos o where o.maestro_id = pm.id and o.empresa_id = new.empresa_id)
   order by (pm.nombre_norm = v_norm) desc, extensions.similarity(pm.nombre_norm, v_norm) desc limit 1;
  if m.id is not null and m.nombre_norm = v_norm then new.maestro_id := m.id; new.maestro_estado := 'aprobado'; new.maestro_similitud := 1;
  elsif m.id is not null and m.sim >= 0.55 then new.maestro_id := m.id; new.maestro_estado := 'sugerido'; new.maestro_similitud := round(m.sim::numeric, 3);
  end if;
  return new;
end $$;
create trigger productos_sugerir_maestro before insert on public.productos for each row execute function public.sugerir_maestro_producto_nuevo();

create or replace view public.v_mapeo_maestro with (security_invoker = on) as
select pr.id as producto_id, pr.empresa_id, e.nombre_corto as empresa, pr.codigo, pr.nombre, pr.unidad_base, pr.categoria,
       pr.maestro_id, pm.codigo as maestro_codigo, pm.nombre as maestro_nombre, pr.maestro_estado, pr.maestro_similitud, e.grupo_id
  from public.productos pr join public.empresas e on e.id = pr.empresa_id
  left join public.productos_maestros pm on pm.id = pr.maestro_id;
grant select on public.v_mapeo_maestro to authenticated;

-- ---------------------------------------------------------------------
-- 2. Proyeccion consolidada
-- ---------------------------------------------------------------------
create table public.proyecciones_consolidadas (
  id                 uuid primary key default gen_random_uuid(),
  grupo_id           uuid not null references public.grupos(id),
  nombre             text,
  fecha_desde        date not null,
  fecha_hasta        date not null,
  contratos          uuid[] not null,
  incluye_dietas     boolean not null default true,
  incluye_propuestos boolean not null default false,
  estado             text not null default 'borrador' check (estado in ('borrador','calculada','anulada')),
  calculada_en       timestamptz,
  creado_por         uuid references auth.users(id) default auth.uid(),
  creado_en          timestamptz not null default now(),
  check (fecha_hasta >= fecha_desde)
);
alter table public.explosiones add column proyeccion_consolidada_id uuid references public.proyecciones_consolidadas(id) on delete cascade;
create index explosiones_consolidada_idx on public.explosiones (proyeccion_consolidada_id);

-- puede ver la consolidada si puede proyectar en todos sus contratos
create or replace function public.puede_ver_consolidada(p_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.es_superadmin() or auth.uid() is null or not exists (
    select 1 from public.proyecciones_consolidadas pc cross join unnest(pc.contratos) ct(id) join public.contratos c on c.id = ct.id
     where pc.id = p_id and not (public.tiene_permiso(c.empresa_id, 'M2', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver')));
$$;
alter table public.proyecciones_consolidadas enable row level security;
create policy proyecciones_consolidadas_ver on public.proyecciones_consolidadas for select to authenticated using (public.puede_ver_consolidada(id));
grant select on public.proyecciones_consolidadas to authenticated;

-- crea la consolidada y una explosion (proyeccion) por contrato; la pantalla calcula cada una por tramos
create or replace function public.crear_proyeccion_consolidada(p_contratos uuid[], p_desde date, p_hasta date, p_nombre text default null,
                                                               p_incluye_dietas boolean default true, p_incluye_propuestos boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_grupo uuid; v_n int; c record; v_id uuid; v_ex uuid;
begin
  if coalesce(array_length(p_contratos, 1), 0) = 0 then raise exception 'Seleccione al menos un contrato.'; end if;
  select count(distinct coalesce(e.grupo_id, e.id)), min(e.grupo_id::text)::uuid into v_n, v_grupo
    from public.contratos ct join public.empresas e on e.id = ct.empresa_id where ct.id = any (p_contratos);
  if v_n > 1 or v_grupo is null then raise exception 'Todos los contratos deben ser de empresas del mismo grupo.'; end if;
  for c in select ct.id, ct.numero, ct.empresa_id from public.contratos ct where ct.id = any (p_contratos) loop
    if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(c.empresa_id, 'M2', 'ver') or public.tiene_permiso(c.empresa_id, 'M3', 'ver')) then
      raise exception 'Sin permiso para proyectar el contrato % (Planeacion o Compras: ver).', c.numero;
    end if;
  end loop;
  insert into public.proyecciones_consolidadas (grupo_id, nombre, fecha_desde, fecha_hasta, contratos, incluye_dietas, incluye_propuestos)
  values (v_grupo, p_nombre, p_desde, p_hasta, p_contratos, p_incluye_dietas, p_incluye_propuestos) returning id into v_id;
  for c in select ct.id from public.contratos ct where ct.id = any (p_contratos) loop
    v_ex := public.crear_explosion(c.id, p_desde, p_hasta, null, p_incluye_dietas, 'ninguno', coalesce(p_nombre, 'Consolidada'), 'proyeccion', p_incluye_propuestos);
    update public.explosiones set proyeccion_consolidada_id = v_id where id = v_ex;
  end loop;
  return v_id;
end $$;

-- calcula todo de una vez (para periodos cortos); en periodos largos la pantalla llama calcular_explosion por tramos y luego cerrar
create or replace function public.calcular_proyeccion_consolidada(p_id uuid, p_desde date default null, p_hasta date default null)
returns table (contratos int, filas int) language plpgsql security definer set search_path = public as $$
declare x record; r record; v_c int := 0; v_f int := 0;
begin
  if not public.puede_ver_consolidada(p_id) then raise exception 'Sin permiso'; end if;
  for x in select id from public.explosiones where proyeccion_consolidada_id = p_id loop
    select * into r from public.calcular_explosion(x.id, p_desde, p_hasta);
    v_c := v_c + 1; v_f := v_f + coalesce(r.filas, 0);
  end loop;
  update public.proyecciones_consolidadas set estado = 'calculada', calculada_en = now() where id = p_id;
  return query select v_c, v_f;
end $$;

-- resumen por maestro con el aporte de cada empresa y contrato (lo que ve compras)
create or replace function public.resumen_proyeccion_consolidada(p_id uuid)
returns table (maestro_id uuid, maestro_codigo text, maestro_nombre text, categoria text, unidad_base text, unidad_compra text,
               cantidad_base numeric, cantidad_compra numeric, promedio_dia_base numeric, sin_maestro boolean, mapeo_pendiente boolean, por_empresa jsonb)
language sql stable security definer set search_path = public as $$
  with pc as (select * from public.proyecciones_consolidadas where id = p_id and public.puede_ver_consolidada(p_id)),
  -- una sola pasada sobre el detalle: total por producto y contrato
  porprod as (
    select d.producto_id, ex.empresa_id, ex.contrato_id, sum(d.cantidad_bruta) as cant
      from pc join public.explosiones ex on ex.proyeccion_consolidada_id = pc.id
      join public.explosion_detalle d on d.explosion_id = ex.id
     group by 1, 2, 3),
  emp as (
    select coalesce(pr.maestro_id, pr.id) as clave, pr.maestro_id, bool_or(pr.maestro_estado = 'sugerido') as pend, x.empresa_id, x.contrato_id, sum(x.cant) as cant
      from porprod x join public.productos pr on pr.id = x.producto_id
     group by 1, 2, 4, 5)
  select emp.maestro_id,
         coalesce(pm.codigo, pr.codigo), coalesce(pm.nombre, pr.nombre), coalesce(pm.categoria, pr.categoria),
         coalesce(pm.unidad_base, pr.unidad_base), coalesce(pm.unidad_compra, pr.unidad_compra),
         round(sum(emp.cant), 3),
         round(sum(emp.cant) / nullif(coalesce(pm.factor_compra, pr.factor_compra), 0), 3),
         round(sum(emp.cant) / greatest((select fecha_hasta - fecha_desde + 1 from pc), 1), 3),
         emp.maestro_id is null,
         bool_or(emp.pend),
         jsonb_agg(jsonb_build_object('empresa', e.nombre_corto, 'contrato', ct.numero, 'cantidad', round(emp.cant, 3)) order by emp.cant desc)
    from emp
    join public.empresas e on e.id = emp.empresa_id
    join public.contratos ct on ct.id = emp.contrato_id
    left join public.productos_maestros pm on pm.id = emp.maestro_id
    left join public.productos pr on pr.id = emp.clave and emp.maestro_id is null
   group by emp.clave, emp.maestro_id, pm.id, pr.id
   order by sum(emp.cant) desc;
$$;

-- ---------------------------------------------------------------------
-- 3. Calculo inverso consolidado: con p_cantidad (unidad base) de un maestro, hasta que fecha alcanza para toda la consolidada.
--    Usa el consumo diario ya calculado; si sobra al final del periodo, extrapola con el promedio diario (hasta p_max_dias).
-- ---------------------------------------------------------------------
create or replace function public.calculo_inverso_consolidado(p_id uuid, p_maestro uuid, p_cantidad numeric, p_max_dias int default 730)
returns table (fecha_hasta date, dias int, consumo_diario_promedio numeric, consumo_total numeric, extrapolado boolean, por_empresa jsonb)
language plpgsql stable security definer set search_path = public as $$
declare pc public.proyecciones_consolidadas; acum numeric := 0; n int := 0; dia record; prom numeric; extra int := 0; v_dias int;
begin
  select * into pc from public.proyecciones_consolidadas where id = p_id;
  if pc.id is null or not public.puede_ver_consolidada(p_id) then raise exception 'Proyeccion no encontrada'; end if;
  if pc.estado <> 'calculada' then raise exception 'Calcule primero la proyeccion consolidada.'; end if;
  v_dias := pc.fecha_hasta - pc.fecha_desde + 1;
  for dia in select g::date as f, coalesce(sum(d.cantidad_bruta), 0) as c
               from generate_series(pc.fecha_desde, pc.fecha_hasta, interval '1 day') g
               left join public.explosiones ex on ex.proyeccion_consolidada_id = p_id
               left join public.explosion_detalle d on d.explosion_id = ex.id and d.fecha = g::date
                    and d.producto_id in (select id from public.productos where maestro_id = p_maestro or id = p_maestro)
              group by g order by g loop
    exit when acum + dia.c > p_cantidad;
    acum := acum + dia.c; n := n + 1;
  end loop;
  select coalesce(sum(d.cantidad_bruta), 0) / v_dias into prom
    from public.explosiones ex join public.explosion_detalle d on d.explosion_id = ex.id
   where ex.proyeccion_consolidada_id = p_id and d.producto_id in (select id from public.productos where maestro_id = p_maestro or id = p_maestro);
  if n >= v_dias and prom > 0 then
    extra := greatest(0, least(p_max_dias - n, floor((p_cantidad - acum) / prom)::int));
    acum := acum + extra * prom; n := n + extra;
  end if;
  return query
  select (pc.fecha_desde + n - 1)::date, n, case when n > 0 then round(acum / n, 3) end, round(acum, 3), extra > 0,
         (select jsonb_agg(jsonb_build_object('empresa', e.nombre_corto, 'contrato', ct.numero, 'promedio_dia', round(s.c / v_dias, 3)) order by s.c desc)
            from (select ex.empresa_id, ex.contrato_id, sum(d.cantidad_bruta) as c
                    from public.explosiones ex join public.explosion_detalle d on d.explosion_id = ex.id
                   where ex.proyeccion_consolidada_id = p_id and d.producto_id in (select id from public.productos where maestro_id = p_maestro or id = p_maestro)
                   group by 1, 2) s
            join public.empresas e on e.id = s.empresa_id join public.contratos ct on ct.id = s.contrato_id);
end $$;

revoke execute on function public.sugerir_catalogo_maestro(uuid, numeric), public.decidir_mapeo_maestro(uuid, text, uuid), public.puede_ver_consolidada(uuid),
  public.crear_proyeccion_consolidada(uuid[], date, date, text, boolean, boolean), public.calcular_proyeccion_consolidada(uuid, date, date),
  public.resumen_proyeccion_consolidada(uuid), public.calculo_inverso_consolidado(uuid, uuid, numeric, int) from public, anon;
grant execute on function public.sugerir_catalogo_maestro(uuid, numeric), public.decidir_mapeo_maestro(uuid, text, uuid), public.puede_ver_consolidada(uuid),
  public.crear_proyeccion_consolidada(uuid[], date, date, text, boolean, boolean), public.calcular_proyeccion_consolidada(uuid, date, date),
  public.resumen_proyeccion_consolidada(uuid), public.calculo_inverso_consolidado(uuid, uuid, numeric, int) to authenticated;

-- siembra del catalogo maestro para los grupos existentes
do $$ declare g record; begin
  for g in select id from public.grupos loop perform public.sugerir_catalogo_maestro(g.id); end loop;
end $$;
