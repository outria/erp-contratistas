-- =====================================================================
-- Supply ERP · Migracion 005 · El administrador de la base (editor SQL, sin sesion: auth.uid() nulo)
-- puede pedir consecutivos y crear contratos, igual que alta_empresa. Hallazgo al correr el seed
-- en Supabase el 30-oct-2026 (el seed se revirtio completo por "Sin permiso para crear contratos").
-- =====================================================================
create or replace function public.siguiente_consecutivo(p_empresa uuid, p_tipo text)
returns text language plpgsql security definer set search_path = public as $$
declare v_pref text; v_num bigint;
begin
  if not (auth.uid() is null or public.es_miembro(p_empresa) or public.es_superadmin()) then
    raise exception 'Sin acceso a la empresa';
  end if;
  update public.consecutivos set siguiente = siguiente + 1
   where empresa_id = p_empresa and tipo_documento = p_tipo
  returning prefijo, siguiente - 1 into v_pref, v_num;
  if v_num is null then raise exception 'No existe consecutivo % para la empresa', p_tipo; end if;
  return v_pref || '-' || lpad(v_num::text, 6, '0');
end;
$$;

create or replace function public.crear_contrato(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := (p->>'empresa_id')::uuid; v_id uuid; v_cod text;
begin
  if not (auth.uid() is null or public.es_superadmin() or public.tiene_permiso(v_emp, 'M1', 'crear')) then
    raise exception 'Sin permiso para crear contratos (Contratos: crear).';
  end if;
  v_cod := public.siguiente_consecutivo(v_emp, 'CT');
  insert into public.contratos (empresa_id, codigo, numero, entidad_id, modalidad, objeto, obligaciones, proceso_secop, interventoria,
    supervisor_entidad, valor_inicial, incluye_iva, fecha_suscripcion, fecha_inicio, fecha_fin_inicial, dias_atencion, tiempos_comida,
    n_menus_ciclo, ciclo_reparto, dias_subsanacion, poliza_cumplimiento, estado, notas)
  values (v_emp, v_cod, p->>'numero', (p->>'entidad_id')::uuid, p->>'modalidad', p->>'objeto', p->>'obligaciones', p->>'proceso_secop', p->>'interventoria',
    p->>'supervisor_entidad', (p->>'valor_inicial')::numeric, coalesce((p->>'incluye_iva')::boolean, false), (p->>'fecha_suscripcion')::date,
    (p->>'fecha_inicio')::date, (p->>'fecha_fin_inicial')::date, coalesce(p->>'dias_atencion', 'habiles'), coalesce((p->>'tiempos_comida')::int, 1),
    (p->>'n_menus_ciclo')::int, coalesce(p->>'ciclo_reparto', 'semanal'), coalesce((p->>'dias_subsanacion')::int, 3), p->>'poliza_cumplimiento',
    coalesce(p->>'estado', 'borrador'), p->>'notas')
  returning id into v_id;
  return v_id;
end $$;
