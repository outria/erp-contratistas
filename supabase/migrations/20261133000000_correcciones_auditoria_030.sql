-- Ración360 · Migracion 033 · Correcciones de la auditoria de compras locales (AUDITORIA_2026-11-06_compras_locales_030.md)
-- A1 tablero lento (agregados unicos + indice)      A2 division por cero con meta 0      A3 doble conteo con soportes
-- A4 contratos terminados con facturado estimado     A5 escalada con es_practica          M1 tablero y soportes sin permiso
-- M2 Ley 2046 sin tipo y certificado vencido         M3 importacion validada en el servidor  M6 validaciones de parametros
-- B1 creado_por/origen del cliente                   B3 una sola definicion de practica   B7 grants a service_role
set client_min_messages = warning;

-- ---------- A5 / B3: es_practica solo lo cambia el administrador de la plataforma; una sola definicion ----------
update public.empresas set es_practica = true
 where es_practica = false and (nit ~ '^90000000\d$' or (nit ~ '^9000001\d\d$' and razon_social ilike '%practica%'));

create or replace function public.empresas_proteger_practica() returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT' and new.es_practica) or (tg_op = 'UPDATE' and new.es_practica is distinct from old.es_practica) then
    if not (public.es_admin_sql() or public.es_superadmin()) then
      raise exception 'Solo el administrador de la plataforma marca o desmarca una empresa de practica.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists empresas_proteger_practica on public.empresas;
create trigger empresas_proteger_practica before insert or update on public.empresas for each row execute function public.empresas_proteger_practica();

create or replace function public.es_empresa_demo(p_empresa uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.es_practica from public.empresas e where e.id = p_empresa
                    and (public.es_admin_sql() or public.es_superadmin() or e.id in (select public.mis_empresas_internas()))), false);
$$;

-- ---------- A2 / M6: metas validas ----------
update public.contratos set meta_compras_locales_pct = 30 where meta_compras_locales_pct < 30;
update public.contratos set meta_compras_locales_extra_pct = 100 - meta_compras_locales_pct where meta_compras_locales_pct + meta_compras_locales_extra_pct > 100;
alter table public.contratos drop constraint if exists contratos_meta_cl_rango;
alter table public.contratos add constraint contratos_meta_cl_rango
  check (meta_compras_locales_pct >= 30 and meta_compras_locales_pct + meta_compras_locales_extra_pct <= 100);

create or replace function public.guardar_parametros_cl(p_contrato uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; c public.contratos; v_meta numeric; v_extra numeric; v_base text; v_rubro numeric; v_racion numeric;
begin
  select * into c from public.contratos where id = p_contrato;
  if c.id is null then raise exception 'Contrato no encontrado.'; end if;
  v_emp := c.empresa_id;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M1', 'editar') or public.tiene_permiso(v_emp, 'M1', 'crear')) then
    raise exception 'Sin permiso (Contratos: editar).';
  end if;
  begin
    v_meta := coalesce(nullif(p->>'meta_compras_locales_pct', '')::numeric, c.meta_compras_locales_pct);
    v_extra := coalesce(nullif(p->>'meta_compras_locales_extra_pct', '')::numeric, c.meta_compras_locales_extra_pct);
    v_rubro := case when p ? 'rubro_alimentos_pct' then nullif(p->>'rubro_alimentos_pct', '')::numeric else c.rubro_alimentos_pct end;
    v_racion := case when p ? 'valor_racion_ref' then nullif(p->>'valor_racion_ref', '')::numeric else c.valor_racion_ref end;
  exception when others then raise exception 'Revise los numeros: deben ser valores numericos.';
  end;
  v_base := coalesce(p->>'base_compras_locales', c.base_compras_locales);
  if v_meta < 30 then raise exception 'La meta legal no puede ser menor al 30 %% (Ley 2046).'; end if;
  if v_extra < 0 or v_meta + v_extra > 100 then raise exception 'Meta mas adicional debe estar entre 30 %% y 100 %%.'; end if;
  if v_base not in ('rubro_alimentos', 'facturado_total') then raise exception 'Base no valida.'; end if;
  if v_rubro is not null and (v_rubro <= 0 or v_rubro > 100) then raise exception 'El rubro de alimentos debe estar entre 0 y 100 %%.'; end if;
  if v_racion is not null and v_racion <= 0 then raise exception 'El valor de la racion debe ser mayor que cero.'; end if;
  update public.contratos k
     set meta_compras_locales_pct = v_meta, meta_compras_locales_extra_pct = v_extra, base_compras_locales = v_base,
         rubro_alimentos_pct = v_rubro, valor_racion_ref = v_racion,
         zona_compras_locales = case when p ? 'zona_compras_locales' then array(select jsonb_array_elements_text(p->'zona_compras_locales')) else k.zona_compras_locales end,
         fuente_parametros_cl = case when p ? 'fuente_parametros_cl' then nullif(trim(p->>'fuente_parametros_cl'), '') else k.fuente_parametros_cl end,
         actualizado_por = auth.uid(), actualizado_en = now()
   where k.id = p_contrato;
end $$;

-- ---------- M2: Ley 2046 exige tipo de productor ----------
update public.terceros set tipo_productor_local = 'otro' where ley2046 and tipo_productor_local is null;
alter table public.terceros drop constraint if exists terceros_ley2046_tipo;
alter table public.terceros add constraint terceros_ley2046_tipo check (not ley2046 or tipo_productor_local is not null);

-- ---------- A3 / B1: soportes ----------
-- Regla: un soporte amarrado a una OC es solo documentacion (la OC cuenta por si sola); una OC tiene a lo sumo un soporte
-- y debe ser del mismo contrato; los soportes sueltos no se repiten (mismo proveedor, factura, alimento y valor en el mes).
delete from public.compras_locales_soportes s using public.compras_locales_soportes d
 where s.oc_id is not null and s.oc_id = d.oc_id and s.id > d.id;
create unique index if not exists cls_oc_unico on public.compras_locales_soportes (oc_id) where oc_id is not null;
create unique index if not exists cls_sin_repetir on public.compras_locales_soportes
  (contrato_id, periodo, md5(lower(trim(proveedor_nombre)) || '|' || coalesce(lower(trim(factura)), '') || '|' || coalesce(lower(trim(alimento)), '') || '|' || valor::text))
  where oc_id is null;

create or replace function public.cls_validar() returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.contratos where id = new.contrato_id and empresa_id = new.empresa_id) then
    raise exception 'El contrato no pertenece a la empresa.';
  end if;
  if new.tercero_id is not null and not exists (select 1 from public.terceros where id = new.tercero_id and empresa_id = new.empresa_id) then
    raise exception 'El proveedor no pertenece a la empresa.';
  end if;
  if new.oc_id is not null and not exists (select 1 from public.ordenes_compra where id = new.oc_id and empresa_id = new.empresa_id and contrato_id = new.contrato_id) then
    raise exception 'La OC no pertenece a ese contrato.';
  end if;
  if coalesce(trim(new.proveedor_nombre), '') = '' then raise exception 'Falta el proveedor.'; end if;
  if new.fecha_compra is not null and date_trunc('month', new.fecha_compra)::date <> new.periodo then
    raise exception 'La fecha de compra % no corresponde al mes del reporte.', new.fecha_compra;
  end if;
  if tg_op = 'INSERT' and not public.es_admin_sql() then
    new.creado_por := auth.uid();
    if new.origen = 'oc' and new.oc_id is null then new.origen := 'manual'; end if;
  end if;
  if tg_op = 'UPDATE' then new.creado_por := old.creado_por; new.creado_en := old.creado_en; end if;
  new.actualizado_por := auth.uid();
  new.actualizado_en := now();
  return new;
end $$;

-- M1: leer y escribir soportes exige Compras o Contratos
drop policy if exists cls_ver on public.compras_locales_soportes;
create policy cls_ver on public.compras_locales_soportes for select to authenticated
  using (public.es_superadmin() or (empresa_id in (select public.mis_empresas_internas())
         and (public.tiene_permiso(empresa_id, 'M3', 'ver') or public.tiene_permiso(empresa_id, 'M1', 'ver'))));

-- M3: importacion validada en el servidor (descarta repetidos y renglones que ya son OC de la plataforma)
create or replace function public.importar_soportes_cl(p_contrato uuid, p_periodo date, p_filas jsonb, p_archivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid; f jsonb; v_ins int := 0; v_rep int := 0; v_oc int := 0; v_mal int := 0; v_val numeric; v_fecha date; v_n int;
begin
  select empresa_id into v_emp from public.contratos where id = p_contrato;
  if v_emp is null then raise exception 'Contrato no encontrado.'; end if;
  if not (public.es_admin_sql() or public.es_superadmin() or public.tiene_permiso(v_emp, 'M3', 'crear')) then raise exception 'Sin permiso (Compras: crear).'; end if;
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then raise exception 'Periodo no valido.'; end if;
  if jsonb_typeof(p_filas) is distinct from 'array' or jsonb_array_length(p_filas) > 5000 then raise exception 'Archivo vacio o demasiado grande (maximo 5000 renglones).'; end if;
  for f in select * from jsonb_array_elements(p_filas) loop
    begin
      v_val := (f->>'valor')::numeric;
      v_fecha := nullif(f->>'fecha_compra', '')::date;
    exception when others then v_mal := v_mal + 1; continue;
    end;
    if v_val is null or v_val <= 0 or coalesce(trim(f->>'proveedor_nombre'), '') = '' or (v_fecha is not null and date_trunc('month', v_fecha)::date <> p_periodo) then
      v_mal := v_mal + 1; continue;
    end if;
    if exists (select 1 from public.ordenes_compra o where o.contrato_id = p_contrato and o.codigo = trim(f->>'factura')) then v_oc := v_oc + 1; continue; end if;
    insert into public.compras_locales_soportes (empresa_id, contrato_id, periodo, proveedor_nombre, tipo_proveedor, factura, fecha_compra, tipo_producto,
      alimento, especie_variedad, cantidad, unidad, valor, ley2046, lugar_productor, origen, notas)
    values (v_emp, p_contrato, p_periodo, left(trim(f->>'proveedor_nombre'), 200), left(f->>'tipo_proveedor', 100), left(f->>'factura', 100), v_fecha,
      left(f->>'tipo_producto', 60), left(f->>'alimento', 200), left(f->>'especie_variedad', 100),
      case when (f->>'cantidad') ~ '^-?[0-9]+(\.[0-9]+)?$' and (f->>'cantidad')::numeric >= 0 then (f->>'cantidad')::numeric end,
      left(f->>'unidad', 30), round(v_val, 2), coalesce((f->>'ley2046')::boolean, false), left(f->>'lugar_productor', 200), 'importado', left(p_archivo, 300))
    on conflict do nothing;
    get diagnostics v_n = row_count;
    if v_n = 1 then v_ins := v_ins + 1; else v_rep := v_rep + 1; end if;
  end loop;
  return jsonb_build_object('cargados', v_ins, 'repetidos', v_rep, 'ya_eran_oc', v_oc, 'descartados', v_mal);
end $$;

-- ---------- A1 / A4 / A2 / M1 / M2: tablero reescrito ----------
create index if not exists oc_contrato_fecha_idx on public.ordenes_compra (contrato_id, fecha_emision);

create or replace function public.compras_locales_tablero(p_empresa uuid default null, p_meses int default 3, p_hasta date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_hasta date := date_trunc('month', coalesce(p_hasta, (now() at time zone 'America/Bogota')::date))::date;
        v_meses int := least(greatest(coalesce(p_meses, 3), 1), 12);
        v_desde date; v_out jsonb; v_admin boolean := public.es_admin_sql() or public.es_superadmin();
begin
  v_desde := (v_hasta - make_interval(months => v_meses - 1))::date;
  if p_empresa is not null and not (v_admin or (p_empresa in (select public.mis_empresas_internas())
       and (public.tiene_permiso(p_empresa, 'M3', 'ver') or public.tiene_permiso(p_empresa, 'M1', 'ver')))) then
    raise exception 'Sin acceso a esa empresa.';
  end if;
  with ct as materialized (
    select c.id, c.numero, c.codigo, c.empresa_id, e.nombre_corto as empresa_nombre, e.es_practica, c.modalidad,
           c.meta_compras_locales_pct + c.meta_compras_locales_extra_pct as meta_pct, c.meta_compras_locales_extra_pct as extra_pct,
           c.base_compras_locales, c.rubro_alimentos_pct,
           date_trunc('month', c.fecha_inicio)::date as mes_ini,
           date_trunc('month', coalesce(v.fecha_fin_vigente, c.fecha_fin_inicial))::date as mes_fin
      from public.contratos c
      join public.empresas e on e.id = c.empresa_id
      left join public.v_contratos_resumen v on v.id = c.id
     where c.estado in ('vigente', 'suspendido', 'liquidacion')
       and (p_empresa is null or c.empresa_id = p_empresa)
       and (v_admin or (c.empresa_id in (select public.mis_empresas_internas())
            and (public.tiene_permiso(c.empresa_id, 'M3', 'ver') or public.tiene_permiso(c.empresa_id, 'M1', 'ver'))))
  ), base as materialized (
    select ct.*, m.periodo
      from ct cross join lateral (select (v_hasta - make_interval(months => g))::date as periodo from generate_series(0, v_meses - 1) g) m
     where m.periodo between ct.mes_ini and ct.mes_fin
  ), oc as materialized (
    select o.contrato_id, date_trunc('month', o.fecha_emision)::date as periodo, sum(o.total) as total,
           sum(o.total) filter (where t.ley2046 and (t.ley2046_certificado_vence is null or t.ley2046_certificado_vence >= o.fecha_emision)) as local
      from public.ordenes_compra o join public.terceros t on t.id = o.tercero_id
     where o.contrato_id in (select id from ct) and o.estado not in ('borrador', 'anulada')
       and o.fecha_emision >= v_desde and o.fecha_emision < (v_hasta + interval '1 month')
     group by 1, 2
  ), sop as materialized (
    select s.contrato_id, s.periodo, sum(s.valor) as total, sum(s.valor) filter (where s.ley2046) as local
      from public.compras_locales_soportes s
     where s.contrato_id in (select id from ct) and s.oc_id is null and s.periodo between v_desde and v_hasta
     group by 1, 2
  ), calc as (
    select b.*,
           ej.valor_facturado as facturado_real,
           prom.valor as facturado_prom,
           coalesce(oc.local, 0) + coalesce(sop.local, 0) as local,
           coalesce(oc.total, 0) + coalesce(sop.total, 0) as total
      from base b
      left join public.contrato_ejecucion ej on ej.contrato_id = b.id and ej.periodo = b.periodo
      left join lateral (select round(avg(x.valor_facturado), 2) as valor
                           from (select e2.valor_facturado from public.contrato_ejecucion e2
                                  where e2.contrato_id = b.id and e2.periodo < b.periodo and e2.valor_facturado > 0
                                  order by e2.periodo desc limit 3) x) prom on ej.valor_facturado is null
      left join oc on oc.contrato_id = b.id and oc.periodo = b.periodo
      left join sop on sop.contrato_id = b.id and sop.periodo = b.periodo
  ), fin as (
    select c.*, coalesce(c.facturado_real, c.facturado_prom) as facturado,
           (c.facturado_real is null and c.facturado_prom is not null) as facturado_estimado,
           case when c.base_compras_locales = 'facturado_total' then coalesce(c.facturado_real, c.facturado_prom)
                when c.rubro_alimentos_pct is not null then round(coalesce(c.facturado_real, c.facturado_prom) * c.rubro_alimentos_pct / 100, 2) end as base_valor
      from calc c
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'contrato_id', id, 'numero', numero, 'codigo', codigo, 'empresa_id', empresa_id, 'empresa', empresa_nombre,
           'practica', es_practica, 'modalidad', modalidad, 'periodo', periodo, 'en_curso', periodo = date_trunc('month', (now() at time zone 'America/Bogota')::date)::date,
           'facturado', facturado, 'facturado_estimado', facturado_estimado,
           'base_tipo', base_compras_locales, 'rubro_pct', rubro_alimentos_pct, 'base', base_valor,
           'meta_pct', meta_pct, 'extra_pct', extra_pct,
           'requerido', round(base_valor * meta_pct / 100, 2),
           'comprado_local', local, 'comprado_total', total,
           'pct_local_de_compras', case when total > 0 then round(local / total * 100, 1) end,
           'cumplimiento_pct', case when base_valor > 0 and meta_pct > 0 then round(local / (base_valor * meta_pct / 100) * 100, 1) end,
           'pct_sobre_base', case when base_valor > 0 then round(local / base_valor * 100, 2) end,
           'faltante', case when base_valor is not null then greatest(round(base_valor * meta_pct / 100 - local, 2), 0) end,
           'alerta', case when base_compras_locales = 'rubro_alimentos' and rubro_alimentos_pct is null then 'Falta el % del rubro de alimentos del contrato'
                          when facturado is null then 'Falta el facturado del mes (Contratos > Ejecucion)' end
         ) order by empresa_nombre, numero, periodo desc), '[]'::jsonb)
    into v_out from fin;
  return v_out;
end $$;

-- ---------- grants (B7) ----------
revoke all on function public.importar_soportes_cl(uuid, date, jsonb, text), public.empresas_proteger_practica() from public, anon;
grant execute on function public.importar_soportes_cl(uuid, date, jsonb, text) to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.compras_locales_tablero(uuid, int, date), public.guardar_parametros_cl(uuid, jsonb), public.guardar_ley2046_tercero(uuid, boolean, text, date, text),
      public.importar_soportes_cl(uuid, date, jsonb, text), public.es_empresa_demo(uuid), public.crear_contrato_practica(jsonb),
      public.importar_requerimiento(jsonb), public.estado_req_planeacion(uuid, text) to service_role;
  end if;
end $$;
