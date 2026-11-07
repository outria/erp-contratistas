-- Ración360 · Migracion 031 · Requerimientos de Planeacion (necesidad de compra de materia prima)
--
-- Planeacion envia a Compras la "NECESIDAD DE COMPRA DE MATERIA PRIMA" (archivo Excel con codigo C0xx por programa:
-- C050 Cenit, C028 Nutrifood, C071 Alianza, C0105 Malambo, C0148 Grupo 15, C0180 Carceles y URIs...). Cada uno trae
-- bodega, fecha de envio, ciclo de menu, modalidad, cobertura, y por renglon: fecha de entrega, dia a consumir,
-- descripcion, cantidad, unidad, categoria, precio de matriz, descuento de inventario y cantidad a comprar.
-- Aqui queda como documento: se importa el archivo tal cual, se versiona (actualizacion, adicional, cancelada),
-- se cruza con el catalogo de productos de la empresa (y crea los que falten, marcados para revision) y Compras le
-- cambia el estado (recibido -> en compra -> cubierto). El descuento de inventario es el sobrante que se descuenta.
set client_min_messages = warning;

create table if not exists public.requerimientos_planeacion (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  contrato_id uuid not null references public.contratos(id),
  codigo text not null check (codigo ~ '^[A-Za-z0-9._-]{1,30}$'),
  version int not null default 1 check (version between 1 and 99),
  tipo text not null default 'planificada' check (tipo in ('planificada', 'actualizacion', 'adicional', 'cancelada')),
  categorias text[] not null default '{}',
  consumo_desde date,
  consumo_hasta date check (consumo_hasta is null or consumo_desde is null or consumo_hasta >= consumo_desde),
  fecha_envio date,
  fecha_entrega date,
  bodega text,
  ciclo text,
  modalidad text,
  cobertura int check (cobertura is null or cobertura >= 0),
  analista text,
  observaciones text,
  archivo text,
  estado text not null default 'recibido' check (estado in ('recibido', 'en_compra', 'cubierto', 'cancelado')),
  origen text not null default 'importado' check (origen in ('importado', 'manual', 'correo')),
  costo_total numeric(16,2),
  creado_por uuid default auth.uid(), creado_en timestamptz not null default now(),
  actualizado_por uuid, actualizado_en timestamptz not null default now(),
  unique (empresa_id, contrato_id, codigo, version)
);
create index if not exists rp_empresa_idx on public.requerimientos_planeacion (empresa_id, estado);
create index if not exists rp_contrato_idx on public.requerimientos_planeacion (contrato_id, consumo_desde);

create table if not exists public.requerimiento_lineas (
  id uuid primary key default gen_random_uuid(),
  requerimiento_id uuid not null references public.requerimientos_planeacion(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id),
  producto_id uuid references public.productos(id),
  descripcion text not null,
  categoria text,
  unidad text,
  fecha_entrega date,
  dia_consumo text,
  cantidad numeric(16,3) not null check (cantidad >= 0),
  descuento_inventario numeric(16,3) not null default 0 check (descuento_inventario >= 0),
  cantidad_comprar numeric(16,3) check (cantidad_comprar is null or cantidad_comprar >= 0),
  precio_ref numeric(14,2) check (precio_ref is null or precio_ref >= 0),
  costo numeric(16,2),
  orden int not null default 0
);
create index if not exists rl_req_idx on public.requerimiento_lineas (requerimiento_id, orden);
create index if not exists rl_producto_idx on public.requerimiento_lineas (producto_id) where producto_id is not null;
create index if not exists rl_empresa_idx on public.requerimiento_lineas (empresa_id);

-- coherencia de empresa
create or replace function public.rp_validar() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.contratos where id = new.contrato_id and empresa_id = new.empresa_id) then
    raise exception 'El contrato no pertenece a la empresa.';
  end if;
  new.actualizado_en := now();
  return new;
end $$;
drop trigger if exists rp_validar on public.requerimientos_planeacion;
create trigger rp_validar before insert or update on public.requerimientos_planeacion for each row execute function public.rp_validar();

create or replace function public.rl_validar() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.requerimientos_planeacion where id = new.requerimiento_id and empresa_id = new.empresa_id) then
    raise exception 'El requerimiento no pertenece a la empresa.';
  end if;
  if new.producto_id is not null and not exists (select 1 from public.productos where id = new.producto_id and empresa_id = new.empresa_id) then
    raise exception 'El producto no pertenece a la empresa.';
  end if;
  return new;
end $$;
drop trigger if exists rl_validar on public.requerimiento_lineas;
create trigger rl_validar before insert or update on public.requerimiento_lineas for each row execute function public.rl_validar();

drop trigger if exists rp_bitacora on public.requerimientos_planeacion;
create trigger rp_bitacora after insert or update or delete on public.requerimientos_planeacion for each row execute function public.registrar_bitacora();

alter table public.requerimientos_planeacion enable row level security;
alter table public.requerimiento_lineas enable row level security;
drop policy if exists rp_ver on public.requerimientos_planeacion;
create policy rp_ver on public.requerimientos_planeacion for select to authenticated
  using (public.es_superadmin() or empresa_id in (select public.mis_empresas_internas()));
drop policy if exists rl_ver on public.requerimiento_lineas;
create policy rl_ver on public.requerimiento_lineas for select to authenticated
  using (public.es_superadmin() or empresa_id in (select public.mis_empresas_internas()));
-- escrituras solo por funciones (importar, cambiar estado)
revoke all on public.requerimientos_planeacion, public.requerimiento_lineas from public, anon;
grant select on public.requerimientos_planeacion, public.requerimiento_lineas to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant all on public.requerimientos_planeacion, public.requerimiento_lineas to service_role;
  end if;
end $$;

-- categoria del archivo -> categoria del catalogo
create or replace function public.rp_categoria(p text) returns text language sql immutable as $$
  select case
    when p is null then 'otros'
    when lower(translate(p, 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou')) like 'protein%' then 'proteinas'
    when lower(p) like 'fruver%' then 'fruver'
    when lower(translate(p, 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou')) like 'lacteo%' then 'lacteos'
    when lower(translate(p, 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou')) like 'panader%' then 'panaderia'
    when lower(p) like 'abarrote%' then 'abarrotes'
    when lower(p) like 'bebida%' then 'bebidas'
    when lower(p) like 'aseo%' then 'aseo'
    when lower(p) like 'desechable%' then 'desechables'
    else 'otros' end;
$$;

-- Importa un requerimiento: p = {empresa_id, contrato_id, codigo, tipo?, categorias?, consumo_desde?, consumo_hasta?,
--   fecha_envio?, fecha_entrega?, bodega?, ciclo?, modalidad?, cobertura?, analista?, observaciones?, archivo?, costo_total?,
--   crear_productos? (bool, por defecto true), lineas: [{descripcion, categoria, unidad, fecha_entrega, dia_consumo,
--   cantidad, descuento_inventario, cantidad_comprar, precio_ref, costo}]}
-- Si el codigo ya existe para el contrato, queda como nueva version (la anterior pasa a cancelado si la nueva es
-- 'actualizacion' o 'cancelada').
create or replace function public.importar_requerimiento(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_ct uuid := (p->>'contrato_id')::uuid;
        v_cod text := upper(trim(p->>'codigo')); v_tipo text := coalesce(p->>'tipo', 'planificada');
        v_ver int; v_id uuid; l jsonb; i int := 0; v_prod uuid; v_cat text; v_uni text; v_nuevos int := 0; v_cruzados int := 0;
        v_crear boolean := coalesce((p->>'crear_productos')::boolean, true); v_n int;
begin
  if v_emp is null or v_ct is null or coalesce(v_cod, '') = '' then raise exception 'Faltan empresa, contrato o codigo.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M2', 'crear') or public.tiene_permiso(v_emp, 'M3', 'crear')) then
    raise exception 'Sin permiso (Planeacion o Compras: crear).';
  end if;
  if not exists (select 1 from public.contratos where id = v_ct and empresa_id = v_emp) then raise exception 'El contrato no pertenece a la empresa.'; end if;
  if jsonb_typeof(p->'lineas') is distinct from 'array' then raise exception 'Faltan los renglones.'; end if;
  if jsonb_array_length(p->'lineas') > 2000 then raise exception 'Demasiados renglones (maximo 2000).'; end if;

  select coalesce(max(version), 0) + 1 into v_ver from public.requerimientos_planeacion where empresa_id = v_emp and contrato_id = v_ct and codigo = v_cod;
  if v_ver > 99 then raise exception 'El requerimiento % ya tiene demasiadas versiones.', v_cod; end if;
  if v_ver > 1 and v_tipo in ('actualizacion', 'cancelada') then
    update public.requerimientos_planeacion set estado = 'cancelado', actualizado_por = auth.uid()
     where empresa_id = v_emp and contrato_id = v_ct and codigo = v_cod and estado in ('recibido', 'en_compra');
  end if;

  insert into public.requerimientos_planeacion (empresa_id, contrato_id, codigo, version, tipo, categorias, consumo_desde, consumo_hasta,
    fecha_envio, fecha_entrega, bodega, ciclo, modalidad, cobertura, analista, observaciones, archivo, costo_total, origen, estado)
  values (v_emp, v_ct, v_cod, v_ver, v_tipo,
    coalesce(array(select jsonb_array_elements_text(p->'categorias')), '{}'),
    (p->>'consumo_desde')::date, (p->>'consumo_hasta')::date, (p->>'fecha_envio')::date, (p->>'fecha_entrega')::date,
    left(p->>'bodega', 120), left(p->>'ciclo', 200), left(p->>'modalidad', 40), (p->>'cobertura')::int, left(p->>'analista', 120),
    left(p->>'observaciones', 4000), left(p->>'archivo', 300), (p->>'costo_total')::numeric, coalesce(p->>'origen', 'importado'),
    case when v_tipo = 'cancelada' then 'cancelado' else 'recibido' end)
  returning id into v_id;

  for l in select * from jsonb_array_elements(p->'lineas') loop
    i := i + 1;
    if coalesce(trim(l->>'descripcion'), '') = '' then continue; end if;
    v_cat := public.rp_categoria(l->>'categoria');
    -- cruce con el catalogo por nombre normalizado
    select id into v_prod from public.productos
     where empresa_id = v_emp and public.normalizar_nombre_producto(nombre) = public.normalizar_nombre_producto(l->>'descripcion')
     order by (estado = 'activo') desc limit 1;
    if v_prod is not null then v_cruzados := v_cruzados + 1;
    elsif v_crear then
      v_uni := upper(coalesce(l->>'unidad', ''));
      select coalesce(max(substring(codigo from 4)::int), 0) + 1 into v_n from public.productos where empresa_id = v_emp and codigo ~ '^RQ-[0-9]{1,9}$';
      insert into public.productos (empresa_id, codigo, nombre, categoria, unidad_base, unidad_compra, factor_compra, pendiente_revision, perecedero)
      values (v_emp, 'RQ-' || lpad(v_n::text, 5, '0'), left(trim(l->>'descripcion'), 160), v_cat,
              case when v_uni like 'KILO%' or v_uni = 'KG' then 'g' when v_uni like 'LITRO%' or v_uni = 'L' then 'ml' else 'und' end,
              case when v_uni like 'KILO%' or v_uni = 'KG' then 'kg' when v_uni like 'LITRO%' or v_uni = 'L' then 'l' else 'und' end,
              case when v_uni like 'KILO%' or v_uni = 'KG' or v_uni like 'LITRO%' or v_uni = 'L' then 1000 else 1 end,
              true, v_cat in ('proteinas', 'fruver', 'lacteos', 'panaderia'))
      on conflict (empresa_id, codigo) do nothing
      returning id into v_prod;
      if v_prod is not null then v_nuevos := v_nuevos + 1; end if;
    end if;
    insert into public.requerimiento_lineas (requerimiento_id, empresa_id, producto_id, descripcion, categoria, unidad, fecha_entrega, dia_consumo,
      cantidad, descuento_inventario, cantidad_comprar, precio_ref, costo, orden)
    values (v_id, v_emp, v_prod, left(trim(l->>'descripcion'), 200), v_cat, left(l->>'unidad', 30), (l->>'fecha_entrega')::date, left(l->>'dia_consumo', 60),
      greatest(coalesce((l->>'cantidad')::numeric, 0), 0), greatest(coalesce((l->>'descuento_inventario')::numeric, 0), 0),
      case when l ? 'cantidad_comprar' and l->>'cantidad_comprar' is not null then greatest((l->>'cantidad_comprar')::numeric, 0) end,
      nullif((l->>'precio_ref')::numeric, 0), (l->>'costo')::numeric, i);
    v_prod := null;
  end loop;

  update public.requerimientos_planeacion r
     set costo_total = coalesce(r.costo_total, (select sum(costo) from public.requerimiento_lineas where requerimiento_id = v_id))
   where r.id = v_id;
  return jsonb_build_object('id', v_id, 'version', v_ver, 'lineas', i, 'productos_cruzados', v_cruzados, 'productos_nuevos', v_nuevos);
end $$;

create or replace function public.estado_req_planeacion(p_id uuid, p_estado text)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from public.requerimientos_planeacion where id = p_id;
  if v_emp is null then raise exception 'Requerimiento no encontrado.'; end if;
  if p_estado not in ('recibido', 'en_compra', 'cubierto', 'cancelado') then raise exception 'Estado no valido.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M3', 'crear')
          or (p_estado = 'cancelado' and public.tiene_permiso(v_emp, 'M2', 'crear'))) then
    raise exception 'Sin permiso.';
  end if;
  update public.requerimientos_planeacion set estado = p_estado, actualizado_por = auth.uid() where id = p_id;
end $$;

revoke all on function public.importar_requerimiento(jsonb), public.estado_req_planeacion(uuid, text), public.rp_categoria(text) from public, anon;
grant execute on function public.importar_requerimiento(jsonb), public.estado_req_planeacion(uuid, text), public.rp_categoria(text) to authenticated;
