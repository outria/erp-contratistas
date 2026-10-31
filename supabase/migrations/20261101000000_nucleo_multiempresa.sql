-- =====================================================================
-- Supply ERP (contratistas de alimentacion del Estado) · Migracion 001 · Nucleo multiempresa (M0)
-- Heredado del nucleo probado de A2 PAN ERP y adaptado a este dominio.
-- Empresas (operadores, UT, consorcios), sedes (CEDI, bodegas, oficinas, unidades de servicio),
-- perfiles, roles, permisos por modulo, membresias, configuracion, buzones, integraciones,
-- consecutivos y bitacora.
-- Regla de oro: toda fila operativa tiene empresa_id y la base (RLS) solo deja verla
-- a usuarios con membresia activa en esa empresa. Nada se borra: se anula con estado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Catalogo de modulos de la plataforma (coincide con el Plan Maestro)
-- ---------------------------------------------------------------------
create table public.modulos (
  codigo      text primary key,
  nombre      text not null,
  orden       int  not null
);

insert into public.modulos (codigo, nombre, orden) values
  ('M0',  'Seguridad, empresas y administracion', 0),
  ('M1',  'Contratos y anexos', 1),
  ('M2',  'Planeacion y explosion de materiales', 2),
  ('M3',  'Compras y aprovisionamiento', 3),
  ('M4',  'Portal de proveedores (e-procurement)', 4),
  ('M5',  'Inventario y bodegas (WMS)', 5),
  ('M6',  'Distribucion y entregas a sedes', 6),
  ('M7',  'Operacion en unidad de servicio', 7),
  ('M8',  'Calidad e interventoria', 8),
  ('M9',  'Facturacion a la entidad', 9),
  ('M10', 'Contabilidad y pagos a proveedores', 10),
  ('M11', 'Talento humano del contrato', 11),
  ('M12', 'IA y automatizaciones', 12),
  ('M13', 'Maestros: productos, terceros y fichas tecnicas', 13),
  ('M14', 'Vehiculos y flota', 14),
  ('M15', 'Tableros e indicadores', 15);

create type public.accion_permiso as enum ('ver', 'crear', 'editar', 'aprobar', 'anular');

-- ---------------------------------------------------------------------
-- 2. Organizacion
-- ---------------------------------------------------------------------
create table public.grupos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  creado_en   timestamptz not null default now()
);

-- Una empresa = un operador, union temporal o consorcio con sus propios contratos y datos.
create table public.empresas (
  id              uuid primary key default gen_random_uuid(),
  grupo_id        uuid references public.grupos(id),
  razon_social    text not null,
  nombre_corto    text,                         -- como lo llama el equipo: "UT Diestra", "Nutrifood"
  nit             text not null,
  dv              text,
  tipo_empresa    text not null default 'union_temporal'
                  check (tipo_empresa in ('sociedad', 'union_temporal', 'consorcio', 'persona_natural', 'otro')),
  ciudad          text,
  direccion       text,
  telefono        text,
  correo          text,
  logo_url        text,
  color_primario  text default '#1F2A44',
  color_acento    text default '#D98E04',
  estado          text not null default 'activa' check (estado in ('activa', 'suspendida', 'anulada')),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (nit)
);

-- Sedes de la empresa: CEDI/bodega principal, bodegas, oficinas y unidades de servicio
-- (ERON, colegio, CDI...). Las unidades de servicio se amarran al contrato en M1 (contrato_sedes).
create table public.sedes (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete restrict,
  nombre          text not null,
  tipo            text not null default 'cedi'
                  check (tipo in ('cedi', 'bodega', 'oficina', 'unidad_servicio', 'planta')),
  subtipo         text,                         -- eron, colegio, cdi, casino, estacion...
  departamento    text,
  ciudad          text,
  direccion       text,
  telefono        text,
  responsable     text,
  estado          text not null default 'activa' check (estado in ('activa', 'anulada')),
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now()
);
create index sedes_empresa_idx on public.sedes (empresa_id, tipo);

create table public.perfiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  nombre          text,
  documento       text,
  telefono        text,
  tipo            text not null default 'interno' check (tipo in ('interno', 'proveedor', 'entidad')),
  es_superadmin   boolean not null default false,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Roles, permisos y membresias
-- ---------------------------------------------------------------------
create table public.roles (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid references public.empresas(id),  -- null = plantilla global
  codigo          text not null,
  nombre          text not null,
  descripcion     text,
  es_proveedor    boolean not null default false,
  sistema         boolean not null default false,      -- lo trae la plataforma; solo superadmin lo cambia
  estado          text not null default 'activo' check (estado in ('activo', 'anulado')),
  creado_en       timestamptz not null default now(),
  unique nulls not distinct (empresa_id, codigo)
);

create table public.permisos (
  rol_id          uuid not null references public.roles(id) on delete cascade,
  modulo          text not null references public.modulos(codigo),
  accion          public.accion_permiso not null,
  primary key (rol_id, modulo, accion)
);

create table public.membresias (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references auth.users(id) on delete cascade,
  empresa_id      uuid not null references public.empresas(id),
  rol_id          uuid not null references public.roles(id),
  sede_id         uuid references public.sedes(id),    -- usuario amarrado a una sede (admin de ERON, almacenista)
  activo          boolean not null default true,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  unique (usuario_id, empresa_id)
);

-- ---------------------------------------------------------------------
-- 4. Configuracion por empresa, buzones, integraciones, consecutivos
-- ---------------------------------------------------------------------
create table public.config_empresa (
  empresa_id      uuid not null references public.empresas(id),
  clave           text not null,
  valor           jsonb not null,
  descripcion     text,
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  primary key (empresa_id, clave)
);

create table public.buzones_correo (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  tipo            text not null check (tipo in ('oc_entidad', 'facturas_proveedores', 'documentos_proveedores', 'general')),
  direccion       text not null,
  proveedor_correo text not null check (proveedor_correo in ('gmail', 'microsoft365', 'imap')),
  credencial_ref  text,                         -- id del secreto en Supabase Vault (nunca la credencial)
  parametros      jsonb not null default '{}'::jsonb,
  activo          boolean not null default true,
  ultima_lectura  timestamptz,
  creado_por      uuid references auth.users(id),
  creado_en       timestamptz not null default now(),
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (empresa_id, tipo, direccion)
);

create table public.integraciones (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  tipo            text not null check (tipo in ('siigo', 'cigo', 'zeus', 'ciesa', 'dian', 'pasarela_pagos', 'whatsapp', 'secop', 'sipsa', 'otro')),
  credencial_ref  text,
  parametros      jsonb not null default '{}'::jsonb,
  activo          boolean not null default true,
  actualizado_por uuid references auth.users(id),
  actualizado_en  timestamptz not null default now(),
  unique (empresa_id, tipo)
);

create table public.consecutivos (
  empresa_id      uuid not null references public.empresas(id),
  tipo_documento  text not null,
  prefijo         text not null,
  siguiente       bigint not null default 1,
  primary key (empresa_id, tipo_documento)
);

-- ---------------------------------------------------------------------
-- 5. Bitacora de auditoria
-- ---------------------------------------------------------------------
create table public.bitacora (
  id              bigint generated always as identity primary key,
  empresa_id      uuid,
  usuario_id      uuid,
  tabla           text not null,
  registro_id     text,
  accion          text not null,
  antes           jsonb,
  despues         jsonb,
  fecha           timestamptz not null default now()
);
create index bitacora_empresa_fecha_idx on public.bitacora (empresa_id, fecha desc);

-- ---------------------------------------------------------------------
-- 6. Funciones de seguridad
-- ---------------------------------------------------------------------
create or replace function public.es_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select es_superadmin from public.perfiles where id = auth.uid()), false);
$$;

create or replace function public.es_miembro(p_empresa uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membresias m where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo);
$$;

create or replace function public.tiene_permiso(p_empresa uuid, p_modulo text, p_accion public.accion_permiso)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membresias m join public.permisos p on p.rol_id = m.rol_id
    where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo
      and p.modulo = p_modulo and p.accion = p_accion
  );
$$;

-- permisos del usuario en la empresa (el superadmin tiene todos)
create or replace function public.mis_permisos(p_empresa uuid)
returns table (modulo text, accion text) language sql stable security definer set search_path = public as $$
  select m.codigo::text, a::text from public.modulos m cross join unnest(enum_range(null::public.accion_permiso)) a
   where public.es_superadmin()
  union
  select p.modulo::text, p.accion::text from public.membresias mb join public.permisos p on p.rol_id = mb.rol_id
   where mb.usuario_id = auth.uid() and mb.empresa_id = p_empresa and mb.activo
$$;

create or replace function public.mi_rol(p_empresa uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.codigo from public.membresias m join public.roles r on r.id = m.rol_id
      where m.usuario_id = auth.uid() and m.empresa_id = p_empresa and m.activo),
    case when public.es_superadmin() then 'superadmin' end);
$$;

create or replace function public.siguiente_consecutivo(p_empresa uuid, p_tipo text)
returns text language plpgsql security definer set search_path = public as $$
declare v_pref text; v_num bigint;
begin
  if not public.es_miembro(p_empresa) and not public.es_superadmin() then
    raise exception 'Sin acceso a la empresa';
  end if;
  update public.consecutivos set siguiente = siguiente + 1
   where empresa_id = p_empresa and tipo_documento = p_tipo
  returning prefijo, siguiente - 1 into v_pref, v_num;
  if v_num is null then raise exception 'No existe consecutivo % para la empresa', p_tipo; end if;
  return v_pref || '-' || lpad(v_num::text, 6, '0');
end;
$$;

-- parametros de la empresa como filas (clave, valor, descripcion)
create or replace function public.parametros_empresa(p_empresa uuid)
returns table (clave text, valor jsonb, descripcion text) language sql stable security definer set search_path = public as $$
  select c.clave, c.valor, c.descripcion from public.config_empresa c
   where c.empresa_id = p_empresa and (public.es_superadmin() or public.es_miembro(p_empresa))
   order by c.clave;
$$;

-- ---------------------------------------------------------------------
-- 7. Triggers
-- ---------------------------------------------------------------------
-- perfil automatico; el dueño de la plataforma entra como superadministrador
create or replace function public.crear_perfil_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre, es_superadmin)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', new.email), lower(new.email) = 'outria@gmail.com');
  return new;
end;
$$;
create trigger al_crear_usuario after insert on auth.users for each row execute function public.crear_perfil_usuario();

create or replace function public.marcar_actualizacion()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  if to_jsonb(new) ? 'actualizado_por' then new.actualizado_por := coalesce(auth.uid(), new.actualizado_por); end if;
  return new;
end;
$$;

create or replace function public.registrar_bitacora()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_id text; v_fila jsonb;
begin
  v_fila := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_emp := (v_fila->>'empresa_id')::uuid;
  v_id  := coalesce(v_fila->>'id', v_fila->>'clave');
  if tg_table_name = 'permisos' then
    select empresa_id into v_emp from public.roles where id = (v_fila->>'rol_id')::uuid;
    v_id := (v_fila->>'rol_id') || ':' || (v_fila->>'modulo') || ':' || (v_fila->>'accion');
  end if;
  insert into public.bitacora (empresa_id, usuario_id, tabla, registro_id, accion, antes, despues)
  values (v_emp, auth.uid(), tg_table_name, v_id, tg_op,
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['empresas','sedes','buzones_correo','integraciones','config_empresa'] loop
    execute format('create trigger %I_actualizacion before update on public.%I for each row execute function public.marcar_actualizacion()', t, t);
  end loop;
  foreach t in array array['empresas','sedes','membresias','roles','permisos','buzones_correo','integraciones','config_empresa','consecutivos'] loop
    execute format('create trigger %I_bitacora after insert or update or delete on public.%I for each row execute function public.registrar_bitacora()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 8. Seguridad por fila (RLS)
-- ---------------------------------------------------------------------
alter table public.modulos        enable row level security;
alter table public.grupos         enable row level security;
alter table public.empresas       enable row level security;
alter table public.sedes          enable row level security;
alter table public.perfiles       enable row level security;
alter table public.roles          enable row level security;
alter table public.permisos       enable row level security;
alter table public.membresias     enable row level security;
alter table public.config_empresa enable row level security;
alter table public.buzones_correo enable row level security;
alter table public.integraciones  enable row level security;
alter table public.consecutivos   enable row level security;
alter table public.bitacora       enable row level security;

create policy modulos_ver on public.modulos for select to authenticated using (true);
create policy grupos_super on public.grupos for all to authenticated using (public.es_superadmin()) with check (public.es_superadmin());

create policy empresas_ver on public.empresas for select to authenticated using (public.es_superadmin() or public.es_miembro(id));
create policy empresas_crear on public.empresas for insert to authenticated with check (public.es_superadmin());
create policy empresas_editar on public.empresas for update to authenticated
  using (public.es_superadmin() or public.tiene_permiso(id, 'M0', 'editar'))
  with check (public.es_superadmin() or public.tiene_permiso(id, 'M0', 'editar'));

do $$
declare t text;
begin
  foreach t in array array['sedes','config_empresa','buzones_correo','integraciones','consecutivos'] loop
    execute format('create policy %I_ver on public.%I for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id))', t, t);
    execute format('create policy %I_crear on public.%I for insert to authenticated with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M0'', ''crear''))', t, t);
    execute format('create policy %I_editar on public.%I for update to authenticated using (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M0'', ''editar'')) with check (public.es_superadmin() or public.tiene_permiso(empresa_id, ''M0'', ''editar''))', t, t);
  end loop;
end $$;

-- llaves de integraciones y buzones: solo quien administra la empresa
drop policy integraciones_ver on public.integraciones;
create policy integraciones_ver on public.integraciones for select to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M0', 'editar'));

create policy perfiles_ver on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_superadmin()
    or exists (select 1 from public.membresias m1 join public.membresias m2 on m1.empresa_id = m2.empresa_id
               where m1.usuario_id = auth.uid() and m1.activo and m2.usuario_id = perfiles.id));
create policy perfiles_editar on public.perfiles for update to authenticated
  using (id = auth.uid() or public.es_superadmin())
  with check ((id = auth.uid() and es_superadmin = public.es_superadmin()) or public.es_superadmin());

-- roles y permisos: se leen por membresia; se escriben solo por superadmin (los demas pasan por guardar_rol, mig. 002)
create policy roles_ver on public.roles for select to authenticated
  using (empresa_id is null or public.es_superadmin() or public.es_miembro(empresa_id));
create policy roles_crear on public.roles for insert to authenticated with check (public.es_superadmin());
create policy roles_editar on public.roles for update to authenticated using (public.es_superadmin()) with check (public.es_superadmin());
create policy permisos_ver on public.permisos for select to authenticated
  using (exists (select 1 from public.roles r where r.id = rol_id and (r.empresa_id is null or public.es_superadmin() or public.es_miembro(r.empresa_id))));
create policy permisos_admin on public.permisos for all to authenticated using (public.es_superadmin()) with check (public.es_superadmin());

create policy membresias_ver on public.membresias for select to authenticated
  using (usuario_id = auth.uid() or public.es_superadmin() or public.tiene_permiso(empresa_id, 'M0', 'ver'));
create policy membresias_crear on public.membresias for insert to authenticated
  with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M0', 'crear'));
create policy membresias_editar on public.membresias for update to authenticated
  using (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M0', 'editar'))
  with check (public.es_superadmin() or public.tiene_permiso(empresa_id, 'M0', 'editar'));

create policy bitacora_ver on public.bitacora for select to authenticated
  using (public.es_superadmin() or (empresa_id is not null and public.tiene_permiso(empresa_id, 'M0', 'ver')));

grant usage on schema public to authenticated;
grant select on public.modulos to authenticated;
grant select, insert, update on public.grupos, public.empresas, public.sedes, public.perfiles, public.roles,
  public.membresias, public.config_empresa, public.buzones_correo, public.integraciones, public.consecutivos to authenticated;
grant select, insert, update, delete on public.permisos to authenticated;
grant select on public.bitacora to authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.es_superadmin(), public.es_miembro(uuid), public.tiene_permiso(uuid, text, public.accion_permiso),
  public.mis_permisos(uuid), public.mi_rol(uuid), public.siguiente_consecutivo(uuid, text), public.parametros_empresa(uuid) to authenticated;
