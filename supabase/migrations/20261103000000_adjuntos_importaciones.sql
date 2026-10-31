-- =====================================================================
-- Supply ERP · Migracion 003 · Gestion documental (adjuntos) e importaciones masivas
-- Cualquier registro de la plataforma puede llevar sus soportes (PDF, fotos, escaneados):
-- anexos del contrato, OC, facturas, remisiones firmadas, actas, SOAT, fichas tecnicas...
-- Los archivos van al bucket privado "adjuntos" por empresa; la tabla lleva el indice.
-- =====================================================================

create table public.adjuntos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  entidad         text not null,          -- contrato, oc, factura, recepcion, acta, hallazgo, proveedor, vehiculo...
  entidad_id      uuid not null,
  categoria       text,                   -- anexo_nutricional, anexo_calidad, anexo_talento_humano, poliza, ficha_tecnica, certificado...
  nombre          text not null,
  ruta            text not null,          -- empresa/entidad/id/archivo dentro del bucket
  tipo_mime       text,
  tamano          bigint,
  descripcion     text,
  version         int not null default 1,
  vigente_desde   date,
  vigente_hasta   date,                   -- para documentos que vencen (polizas, BPM, SOAT, carnets)
  subido_por      uuid references auth.users(id) default auth.uid(),
  subido_nombre   text,
  subido_en       timestamptz not null default now(),
  anulado         boolean not null default false
);
create index adjuntos_entidad_idx on public.adjuntos (empresa_id, entidad, entidad_id);
create index adjuntos_vencen_idx on public.adjuntos (empresa_id, vigente_hasta) where vigente_hasta is not null and not anulado;

create or replace function public.adjunto_nombre_usuario() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.subido_nombre is null then
    select nombre into new.subido_nombre from public.perfiles where id = coalesce(new.subido_por, auth.uid());
  end if;
  return new;
end $$;
create trigger adjuntos_nombre before insert on public.adjuntos for each row execute function public.adjunto_nombre_usuario();

alter table public.adjuntos enable row level security;
create policy adjuntos_ver on public.adjuntos for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id));
create policy adjuntos_crear on public.adjuntos for insert to authenticated with check (public.es_superadmin() or public.es_miembro(empresa_id));
-- quitar un adjunto: quien lo subio, o quien administra la empresa; se marca anulado, no se borra
create policy adjuntos_editar on public.adjuntos for update to authenticated
  using (public.es_superadmin() or subido_por = auth.uid() or public.tiene_permiso(empresa_id, 'M0', 'editar'))
  with check (public.es_superadmin() or subido_por = auth.uid() or public.tiene_permiso(empresa_id, 'M0', 'editar'));
create policy adjuntos_borrar on public.adjuntos for delete to authenticated
  using (public.es_superadmin() or subido_por = auth.uid() or public.tiene_permiso(empresa_id, 'M0', 'editar'));
grant select, insert, update, delete on public.adjuntos to authenticated;
create trigger adjuntos_bitacora after insert or update or delete on public.adjuntos for each row execute function public.registrar_bitacora();

-- bucket privado; la ruta arranca con el id de la empresa y RLS de storage exige membresia en esa empresa
insert into storage.buckets (id, name, public, file_size_limit)
values ('adjuntos', 'adjuntos', false, 15728640)
on conflict (id) do nothing;

create policy adjuntos_storage_ver on storage.objects for select to authenticated
  using (bucket_id = 'adjuntos' and (public.es_superadmin() or public.es_miembro(((storage.foldername(name))[1])::uuid)));
create policy adjuntos_storage_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'adjuntos' and (public.es_superadmin() or public.es_miembro(((storage.foldername(name))[1])::uuid)));
create policy adjuntos_storage_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'adjuntos' and (public.es_superadmin() or owner = auth.uid() or public.tiene_permiso(((storage.foldername(name))[1])::uuid, 'M0', 'editar')));

-- ---------------------------------------------------------------------
-- Importaciones masivas: cada carga de plantilla (productos, proveedores, precios, cupos...)
-- deja rastro de que se cargo, cuantas filas y que errores hubo. Las plantillas se generan
-- desde la pantalla de cada maestro; aqui solo queda el registro.
-- ---------------------------------------------------------------------
create table public.importaciones (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  tipo            text not null,          -- productos, proveedores, precios, cupos, minuta, personal...
  archivo         text,
  filas_leidas    int not null default 0,
  filas_cargadas  int not null default 0,
  errores         jsonb not null default '[]'::jsonb,
  estado          text not null default 'procesada' check (estado in ('procesada', 'con_errores', 'anulada')),
  creado_por      uuid references auth.users(id) default auth.uid(),
  creado_en       timestamptz not null default now()
);
alter table public.importaciones enable row level security;
create policy importaciones_ver on public.importaciones for select to authenticated using (public.es_superadmin() or public.es_miembro(empresa_id));
create policy importaciones_crear on public.importaciones for insert to authenticated with check (public.es_superadmin() or public.es_miembro(empresa_id));
grant select, insert on public.importaciones to authenticated;
