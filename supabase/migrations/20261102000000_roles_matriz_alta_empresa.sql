-- =====================================================================
-- Supply ERP · Migracion 002 · Roles de la plataforma, matriz de permisos, alta de empresas,
-- roles construibles y administracion de usuarios.
-- Convencion de letras: V ver · C crear y editar · A aprobar y anular
-- Roles pensados desde el area de compras y la operacion de contratos PAE / USPEC / ICBF.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Plantillas globales de rol
-- ---------------------------------------------------------------------
insert into public.roles (empresa_id, codigo, nombre, descripcion, es_proveedor, sistema) values
  (null, 'admin_empresa',      'Administrador de empresa',        'Configura la empresa, usuarios, buzones e integraciones; ve todo', false, true),
  (null, 'gerencia',           'Gerencia',                        'Ve todo, aprueba contratos, compras grandes y pagos; tableros', false, true),
  (null, 'dir_compras',        'Director de compras',             'Toda la cadena de compras: negociacion, aprobacion de OC, proveedores, precios, seguimiento de pagos', false, true),
  (null, 'jefe_compras',       'Jefe de compras',                 'Compras completas con aprobacion de OC hasta el monto configurado', false, true),
  (null, 'coord_compras',      'Coordinador de compras',          'Crea solicitudes de oferta, negocia y emite OC para aprobacion', false, true),
  (null, 'analista_compras',   'Analista de compras',             'Explosion, requerimientos, seguimiento de OC, master de precios, indicadores', false, true),
  (null, 'aux_compras',        'Auxiliar de compras',             'Registra ofertas, documentos de proveedores y novedades; consulta OC', false, true),
  (null, 'planeacion',         'Planeacion y nutricion',          'Minutas, calendario, cupos, dietas, menus por sede y explosion de materiales', false, true),
  (null, 'almacen_cedi',       'Almacen (CEDI)',                  'Recepcion contra OC, lotes, kardex, traslados a sedes', false, true),
  (null, 'admin_sede',         'Administrador de unidad de servicio', 'Recibido en sede, consumo diario, cuadro de raciones, evidencias; solo su sede', false, true),
  (null, 'almacenista_sede',   'Almacenista de unidad de servicio', 'Recibido, inventario y rotacion en su sede', false, true),
  (null, 'calidad',            'Calidad e interventoria',         'Evidencias, hallazgos, planes de mejora, documentos de proveedores y lotes', false, true),
  (null, 'contabilidad',       'Contabilidad',                    'Radicacion, aceptacion y causacion de facturas; cuentas de cobro', false, true),
  (null, 'financiero',         'Financiero y tesoreria',          'Programacion y aprobacion de pagos, egresos', false, true),
  (null, 'talento_humano',     'Talento humano',                  'Personal del contrato y administrativo, documentos y vencimientos', false, true),
  (null, 'conductor',          'Conductor / logistica',           'Rutas, actas de entrega, evidencias, kilometraje del vehiculo', false, true),
  (null, 'proveedor',          'Proveedor (externo)',             'Solo el portal: sus productos, ofertas, documentos, OC, facturas y pagos', true, true);

-- ---------------------------------------------------------------------
-- 2. Matriz de permisos
-- ---------------------------------------------------------------------
create temporary table tmp_matriz (rol text, modulo text, letras text);
insert into tmp_matriz (rol, modulo, letras) values
  -- Administrador de empresa: configura todo, ve todo
  ('admin_empresa','M0','VCA'),('admin_empresa','M1','VC'),('admin_empresa','M2','V'),('admin_empresa','M3','V'),
  ('admin_empresa','M4','VCA'),('admin_empresa','M5','V'),('admin_empresa','M6','V'),('admin_empresa','M7','V'),
  ('admin_empresa','M8','V'),('admin_empresa','M9','V'),('admin_empresa','M10','V'),('admin_empresa','M11','V'),
  ('admin_empresa','M12','VCA'),('admin_empresa','M13','VCA'),('admin_empresa','M14','VCA'),('admin_empresa','M15','V'),
  -- Gerencia: ve todo; aprueba contratos, compras, facturacion, pagos y talento humano
  ('gerencia','M0','V'),('gerencia','M1','VCA'),('gerencia','M2','VA'),('gerencia','M3','VA'),('gerencia','M4','V'),
  ('gerencia','M5','V'),('gerencia','M6','V'),('gerencia','M7','V'),('gerencia','M8','VA'),('gerencia','M9','VA'),
  ('gerencia','M10','VA'),('gerencia','M11','VA'),('gerencia','M12','V'),('gerencia','M13','V'),('gerencia','M14','V'),('gerencia','M15','V'),
  -- Director de compras
  ('dir_compras','M1','V'),('dir_compras','M2','VC'),('dir_compras','M3','VCA'),('dir_compras','M4','VCA'),
  ('dir_compras','M5','V'),('dir_compras','M6','V'),('dir_compras','M8','V'),('dir_compras','M10','V'),
  ('dir_compras','M12','VC'),('dir_compras','M13','VCA'),('dir_compras','M15','V'),
  -- Jefe de compras
  ('jefe_compras','M1','V'),('jefe_compras','M2','V'),('jefe_compras','M3','VCA'),('jefe_compras','M4','VC'),
  ('jefe_compras','M5','V'),('jefe_compras','M6','V'),('jefe_compras','M8','V'),('jefe_compras','M10','V'),
  ('jefe_compras','M12','V'),('jefe_compras','M13','VC'),('jefe_compras','M15','V'),
  -- Coordinador de compras
  ('coord_compras','M1','V'),('coord_compras','M2','V'),('coord_compras','M3','VC'),('coord_compras','M4','VC'),
  ('coord_compras','M5','V'),('coord_compras','M8','V'),('coord_compras','M10','V'),('coord_compras','M13','VC'),('coord_compras','M15','V'),
  -- Analista de compras
  ('analista_compras','M1','V'),('analista_compras','M2','VC'),('analista_compras','M3','VC'),('analista_compras','M4','V'),
  ('analista_compras','M5','V'),('analista_compras','M10','V'),('analista_compras','M13','VC'),('analista_compras','M15','V'),
  -- Auxiliar de compras
  ('aux_compras','M1','V'),('aux_compras','M3','VC'),('aux_compras','M4','V'),('aux_compras','M5','V'),('aux_compras','M13','VC'),
  -- Planeacion y nutricion
  ('planeacion','M1','V'),('planeacion','M2','VCA'),('planeacion','M3','V'),('planeacion','M5','V'),('planeacion','M7','V'),
  ('planeacion','M8','V'),('planeacion','M13','VC'),('planeacion','M15','V'),
  -- Almacen CEDI
  ('almacen_cedi','M2','V'),('almacen_cedi','M3','V'),('almacen_cedi','M5','VCA'),('almacen_cedi','M6','VC'),
  ('almacen_cedi','M8','VC'),('almacen_cedi','M13','V'),('almacen_cedi','M14','V'),
  -- Administrador de sede
  ('admin_sede','M1','V'),('admin_sede','M2','V'),('admin_sede','M5','VC'),('admin_sede','M6','VC'),('admin_sede','M7','VCA'),
  ('admin_sede','M8','VC'),('admin_sede','M11','VC'),('admin_sede','M13','V'),
  -- Almacenista de sede
  ('almacenista_sede','M5','VC'),('almacenista_sede','M6','VC'),('almacenista_sede','M7','VC'),('almacenista_sede','M13','V'),
  -- Calidad
  ('calidad','M1','V'),('calidad','M3','V'),('calidad','M4','V'),('calidad','M5','V'),('calidad','M6','V'),('calidad','M7','V'),
  ('calidad','M8','VCA'),('calidad','M11','V'),('calidad','M13','VC'),('calidad','M15','V'),
  -- Contabilidad
  ('contabilidad','M1','V'),('contabilidad','M3','V'),('contabilidad','M5','V'),('contabilidad','M9','VCA'),
  ('contabilidad','M10','VC'),('contabilidad','M12','V'),('contabilidad','M13','VC'),('contabilidad','M15','V'),
  -- Financiero y tesoreria
  ('financiero','M1','V'),('financiero','M3','V'),('financiero','M9','V'),('financiero','M10','VCA'),('financiero','M15','V'),
  -- Talento humano
  ('talento_humano','M1','V'),('talento_humano','M11','VCA'),('talento_humano','M13','V'),
  -- Conductor
  ('conductor','M6','VC'),('conductor','M14','VC'),
  -- Proveedor externo: solo su portal (las tablas de M4 limitan a lo suyo)
  ('proveedor','M4','VC');

insert into public.permisos (rol_id, modulo, accion)
select r.id, m.modulo, a.accion
from tmp_matriz m
join public.roles r on r.empresa_id is null and r.codigo = m.rol
cross join lateral (
  select 'ver'::public.accion_permiso as accion where m.letras like '%V%'
  union all select 'crear'   where m.letras like '%C%'
  union all select 'editar'  where m.letras like '%C%'
  union all select 'aprobar' where m.letras like '%A%'
  union all select 'anular'  where m.letras like '%A%'
) a
on conflict do nothing;
drop table tmp_matriz;

-- ---------------------------------------------------------------------
-- 3. Copia de plantillas y alta de empresa
-- ---------------------------------------------------------------------
create or replace function public.clonar_roles_plantilla(p_empresa uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int := 0; t record; v_rol uuid;
begin
  if not (public.es_superadmin() or auth.uid() is null or public.tiene_permiso(p_empresa, 'M0', 'crear')) then
    raise exception 'Sin permiso para crear roles en esta empresa';
  end if;
  for t in select * from public.roles where empresa_id is null and estado = 'activo' loop
    insert into public.roles (empresa_id, codigo, nombre, descripcion, es_proveedor, sistema)
    values (p_empresa, t.codigo, t.nombre, t.descripcion, t.es_proveedor, true)
    on conflict (empresa_id, codigo) do nothing
    returning id into v_rol;
    if v_rol is not null then
      insert into public.permisos (rol_id, modulo, accion) select v_rol, modulo, accion from public.permisos where rol_id = t.id;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

-- Alta de empresa: crea la empresa, su CEDI, sus roles, configuracion base y consecutivos.
create or replace function public.alta_empresa(
  p_razon_social text,
  p_nit          text,
  p_dv           text,
  p_ciudad       text,
  p_nombre_corto text default null,
  p_tipo_empresa text default 'union_temporal',
  p_grupo        text default null,
  p_sede         text default 'CEDI principal',
  p_config       jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_grupo uuid; v_cfg jsonb; k text;
begin
  if not (public.es_superadmin() or auth.uid() is null) then
    raise exception 'Solo el superadministrador puede crear empresas';
  end if;
  if p_grupo is not null then
    select id into v_grupo from public.grupos where nombre = p_grupo;
    if v_grupo is null then insert into public.grupos (nombre) values (p_grupo) returning id into v_grupo; end if;
  end if;

  insert into public.empresas (grupo_id, razon_social, nombre_corto, nit, dv, tipo_empresa, ciudad, creado_por, actualizado_por)
  values (v_grupo, p_razon_social, coalesce(p_nombre_corto, p_razon_social), p_nit, p_dv, p_tipo_empresa, p_ciudad, auth.uid(), auth.uid())
  returning id into v_emp;

  insert into public.sedes (empresa_id, nombre, tipo, ciudad, creado_por) values (v_emp, p_sede, 'cedi', p_ciudad, auth.uid());
  perform public.clonar_roles_plantilla(v_emp);

  -- parametros base del dominio (cada empresa los ajusta en Empresa y parametros)
  v_cfg := jsonb_build_object(
    'moneda',                    jsonb_build_object('v', 'COP',            'd', 'Moneda de trabajo'),
    'decimales',                 jsonb_build_object('v', 2,                'd', 'Decimales en pantalla'),
    'zona_horaria',              jsonb_build_object('v', 'America/Bogota', 'd', 'Zona horaria'),
    'tope_adiciones_pct',        jsonb_build_object('v', 50,               'd', 'Tope legal de adiciones sobre el valor inicial del contrato (%)'),
    'alerta_agotamiento_pct',    jsonb_build_object('v', 80,               'd', 'Avisar cuando el agotamiento presupuestal pase de este %'),
    'dias_aceptar_factura',      jsonb_build_object('v', 3,                'd', 'Dias habiles para aceptar o rechazar la factura electronica del proveedor'),
    'meta_compras_locales_pct',  jsonb_build_object('v', 30,               'd', 'Meta de compras publicas locales (Ley 2046) en % del valor comprado'),
    'ciclo_reparto_defecto',     jsonb_build_object('v', 'semanal',        'd', 'Ciclo de reparto a sedes por defecto: semanal, quincenal, 2+3, 3+4'),
    'dia_inicio_semana_reparto', jsonb_build_object('v', 5,                'd', 'Dia en que arranca la semana de consumo (1 lunes ... 7 domingo). USPEC: 5 = viernes'),
    'presupuesto_en_explosion',  jsonb_build_object('v', 'media_3',        'd', 'Techo de gasto en la explosion: ninguno, ultimo_precio, media_3, moda_3'),
    'montos_aprobacion_oc',      jsonb_build_object('v', '{}'::jsonb,      'd', 'Monto maximo de OC que aprueba cada rol (COP); vacio = sin tope')
  );
  for k in select jsonb_object_keys(p_config) loop
    v_cfg := jsonb_set(v_cfg, array[k], jsonb_build_object('v', p_config->k, 'd', coalesce(v_cfg->k->>'d', k)), true);
  end loop;
  insert into public.config_empresa (empresa_id, clave, valor, descripcion, actualizado_por)
  select v_emp, key, value->'v', value->>'d', auth.uid() from jsonb_each(v_cfg);

  insert into public.consecutivos (empresa_id, tipo_documento, prefijo) values
    (v_emp, 'CT',  'CT'),   -- contrato (codigo interno)
    (v_emp, 'EXP', 'EXP'),  -- explosion de materiales / requerimiento
    (v_emp, 'SO',  'SO'),   -- solicitud de oferta (RFQ)
    (v_emp, 'OC',  'OC'),   -- orden de compra
    (v_emp, 'REC', 'REC'),  -- recepcion / entrada en sistema
    (v_emp, 'TRA', 'TRA'),  -- orden de traslado a sede
    (v_emp, 'ACT', 'ACT'),  -- acta de entrega
    (v_emp, 'CR',  'CR'),   -- cuadro de raciones
    (v_emp, 'HAL', 'HAL'),  -- hallazgo de interventoria
    (v_emp, 'CC',  'CC'),   -- cuenta de cobro a la entidad
    (v_emp, 'RAD', 'RAD'),  -- radicacion de factura de proveedor
    (v_emp, 'CE',  'CE'),   -- comprobante de egreso
    (v_emp, 'NOV', 'NOV');  -- novedad de materia prima
  return v_emp;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Roles construibles (como en A2 PAN / Payana)
--    Nadie da una funcion sensible que no tiene: usuarios, facturacion, contabilidad y pagos,
--    talento humano (datos personales) y tableros financieros.
-- ---------------------------------------------------------------------
create or replace function public.funcion_sensible(p_modulo text) returns boolean language sql immutable as $$
  select p_modulo in ('M0', 'M9', 'M10', 'M11', 'M15');
$$;

create or replace function public.guardar_rol(p_empresa uuid, p_rol uuid, p_nombre text, p_descripcion text, p_permisos jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_rol public.roles; v_id uuid; v_super boolean := coalesce(public.es_superadmin(), false); x jsonb; v_cod text;
begin
  if not (v_super or public.tiene_permiso(p_empresa, 'M0', 'editar')) then
    raise exception 'Sin permiso para administrar roles (Usuarios: editar).';
  end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Escribe el nombre del rol.'; end if;
  if p_permisos is null or jsonb_typeof(p_permisos) <> 'array' or jsonb_array_length(p_permisos) = 0 then
    raise exception 'Escoge al menos una funcion para el rol.';
  end if;
  if exists (select 1 from public.roles where empresa_id = p_empresa and lower(nombre) = lower(trim(p_nombre))
              and estado = 'activo' and id is distinct from p_rol) then
    raise exception 'Ya existe un rol con el nombre "%".', trim(p_nombre);
  end if;
  if not v_super then
    for x in select * from jsonb_array_elements(p_permisos) loop
      if public.funcion_sensible(x ->> 'modulo') and not public.tiene_permiso(p_empresa, x ->> 'modulo', (x ->> 'accion')::public.accion_permiso) then
        raise exception 'No puede dar la funcion % · % porque usted no la tiene.', x ->> 'modulo', x ->> 'accion';
      end if;
    end loop;
  end if;
  if p_rol is null then
    v_cod := 'r_' || substr(md5(random()::text || clock_timestamp()::text), 1, 8);
    insert into public.roles (empresa_id, codigo, nombre, descripcion, es_proveedor, estado, sistema)
    values (p_empresa, v_cod, trim(p_nombre), nullif(trim(p_descripcion), ''), false, 'activo', false)
    returning id into v_id;
  else
    select * into v_rol from public.roles where id = p_rol and empresa_id = p_empresa;
    if v_rol.id is null then raise exception 'Rol no encontrado en esta empresa.'; end if;
    if v_rol.sistema and not v_super then
      raise exception 'Los roles que trae la plataforma solo los cambia el superadministrador. Duplíquelo y cambie la copia.';
    end if;
    update public.roles set nombre = trim(p_nombre), descripcion = nullif(trim(p_descripcion), '') where id = p_rol;
    v_id := p_rol;
    delete from public.permisos where rol_id = v_id;
  end if;
  insert into public.permisos (rol_id, modulo, accion)
  select distinct v_id, e ->> 'modulo', (e ->> 'accion')::public.accion_permiso
    from jsonb_array_elements(p_permisos) e
   where exists (select 1 from public.modulos m where m.codigo = e ->> 'modulo');
  return v_id;
end $$;

create or replace function public.anular_rol(p_rol uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_rol public.roles;
begin
  select * into v_rol from public.roles where id = p_rol;
  if v_rol.id is null then raise exception 'Rol no encontrado.'; end if;
  if not (public.es_superadmin() or public.tiene_permiso(v_rol.empresa_id, 'M0', 'editar')) then
    raise exception 'Sin permiso para administrar roles.';
  end if;
  if v_rol.sistema and not public.es_superadmin() then raise exception 'Los roles de la plataforma solo los anula el superadministrador.'; end if;
  if exists (select 1 from public.membresias where rol_id = p_rol and activo) then
    raise exception 'El rol tiene usuarios activos. Cámbieles el rol primero.';
  end if;
  update public.roles set estado = 'anulado' where id = p_rol;
end $$;

create or replace function public.roles_empresa(p_empresa uuid)
returns table(id uuid, codigo text, nombre text, descripcion text, sistema boolean, usuarios int, permisos jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.codigo, r.nombre, r.descripcion, r.sistema,
         (select count(*)::int from public.membresias m where m.rol_id = r.id and m.activo),
         coalesce((select jsonb_agg(jsonb_build_object('modulo', p.modulo, 'accion', p.accion) order by p.modulo, p.accion)
                     from public.permisos p where p.rol_id = r.id), '[]'::jsonb)
    from public.roles r
   where r.empresa_id = p_empresa and r.estado = 'activo' and not r.es_proveedor
     and (public.es_superadmin() or public.tiene_permiso(p_empresa, 'M0', 'ver'))
   order by r.sistema desc, r.nombre;
$$;

create or replace function public.membresia_sin_escalar() returns trigger language plpgsql security definer set search_path = public as $$
declare v_falta text;
begin
  if auth.uid() is null or public.es_superadmin() then return new; end if;
  if tg_op = 'UPDATE' and new.rol_id is not distinct from old.rol_id then return new; end if;
  select p.modulo || ' · ' || p.accion into v_falta
    from public.permisos p
   where p.rol_id = new.rol_id and public.funcion_sensible(p.modulo) and not public.tiene_permiso(new.empresa_id, p.modulo, p.accion)
   limit 1;
  if v_falta is not null then raise exception 'No puede asignar este rol: da la funcion % y usted no la tiene.', v_falta; end if;
  return new;
end $$;
create trigger membresias_sin_escalar before insert or update of rol_id on public.membresias
  for each row execute function public.membresia_sin_escalar();

-- ---------------------------------------------------------------------
-- 5. Usuarios de la empresa
-- ---------------------------------------------------------------------
create or replace function public.usuarios_empresa(p_empresa uuid)
returns table(membresia_id uuid, usuario_id uuid, correo text, nombre text, rol_codigo text, rol_nombre text, activo boolean,
              ultimo_ingreso timestamptz, confirmado boolean, invitado_en timestamptz, rol_id uuid, sede_id uuid)
language sql stable security definer set search_path = public, auth as $$
  select m.id, m.usuario_id, u.email::text, p.nombre, r.codigo, r.nombre, m.activo, u.last_sign_in_at,
         u.email_confirmed_at is not null, u.invited_at, r.id, m.sede_id
    from public.membresias m
    join auth.users u on u.id = m.usuario_id
    left join public.perfiles p on p.id = m.usuario_id
    join public.roles r on r.id = m.rol_id
   where m.empresa_id = p_empresa
     and (public.es_superadmin() or public.tiene_permiso(p_empresa, 'M0', 'ver'))
   order by coalesce(p.nombre, u.email);
$$;

create or replace function public.asignar_usuario(p_empresa uuid, p_correo text, p_rol_codigo text, p_nombre text default null, p_sede uuid default null)
returns uuid language plpgsql security definer set search_path = public, auth as $$
declare v_user uuid; v_rol uuid; v_mem uuid;
begin
  if not (public.es_superadmin() or public.tiene_permiso(p_empresa, 'M0', 'crear')) then
    raise exception 'Sin permiso para administrar usuarios (M0 crear)';
  end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_correo));
  if v_user is null then
    raise exception 'El correo % no esta invitado todavia. Invitalo primero en Supabase (Authentication > Invite user).', p_correo;
  end if;
  select id into v_rol from public.roles where empresa_id = p_empresa and codigo = p_rol_codigo and estado = 'activo';
  if v_rol is null then raise exception 'Rol % no existe en la empresa', p_rol_codigo; end if;
  if p_rol_codigo = 'admin_empresa' and not public.es_superadmin() then
    raise exception 'Solo el administrador de la plataforma asigna administradores de empresa';
  end if;
  insert into public.membresias (usuario_id, empresa_id, rol_id, sede_id, creado_por)
  values (v_user, p_empresa, v_rol, p_sede, auth.uid())
  on conflict (usuario_id, empresa_id) do update set rol_id = excluded.rol_id, sede_id = excluded.sede_id, activo = true
  returning id into v_mem;
  if p_nombre is not null and length(trim(p_nombre)) > 0 then
    update public.perfiles set nombre = trim(p_nombre) where id = v_user;
  end if;
  return v_mem;
end $$;

create or replace function public.editar_nombre_usuario(p_empresa uuid, p_usuario uuid, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.es_superadmin() or public.tiene_permiso(p_empresa, 'M0', 'editar')) then raise exception 'Sin permiso (Usuarios: editar).'; end if;
  if not exists (select 1 from public.membresias where usuario_id = p_usuario and empresa_id = p_empresa) then
    raise exception 'El usuario no pertenece a esta empresa.';
  end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Escribe el nombre.'; end if;
  update public.perfiles set nombre = trim(p_nombre), actualizado_en = now() where id = p_usuario;
end $$;

revoke execute on function public.clonar_roles_plantilla(uuid), public.alta_empresa(text, text, text, text, text, text, text, text, jsonb),
  public.guardar_rol(uuid, uuid, text, text, jsonb), public.anular_rol(uuid), public.roles_empresa(uuid),
  public.usuarios_empresa(uuid), public.asignar_usuario(uuid, text, text, text, uuid), public.editar_nombre_usuario(uuid, uuid, text) from public, anon;
grant execute on function public.clonar_roles_plantilla(uuid), public.alta_empresa(text, text, text, text, text, text, text, text, jsonb),
  public.guardar_rol(uuid, uuid, text, text, jsonb), public.anular_rol(uuid), public.roles_empresa(uuid),
  public.usuarios_empresa(uuid), public.asignar_usuario(uuid, text, text, text, uuid), public.editar_nombre_usuario(uuid, uuid, text) to authenticated;
