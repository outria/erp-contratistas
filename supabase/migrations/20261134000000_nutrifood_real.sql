-- Ración360 · Migracion 034 · UT Nutrifood pasa de practica a empresa real
-- Con el clausulado 202604177 y el RUT ya tenemos los datos reales (NIT 902.116.853-7). La empresa de practica
-- "UT Nutrifood (practica)" ya tiene el contrato, el requerimiento C028 y sus productos; se convierte en la empresa
-- real y la ficha provisional "UNION TEMPORAL NUTRIFOOD" (NIT POR-DEFINIR, sin contratos, usuarios ni datos) se anula (nada se borra).
set client_min_messages = warning;

do $$
declare v_prac uuid; v_prov uuid; v_grupo uuid; v_n int;
begin
  select id into v_prac from public.empresas where nit = '900000103' and razon_social ilike '%nutrifood%';
  select id, grupo_id into v_prov, v_grupo from public.empresas where nit = 'POR-DEFINIR-NUTRIFOOD';
  if v_prac is null then
    raise notice 'No hay empresa de practica de Nutrifood (ya se convirtio).';
    return;
  end if;

  if v_prov is not null then
    -- la ficha provisional no debe tener nada operativo
    select (select count(*) from public.contratos where empresa_id = v_prov) + (select count(*) from public.membresias where empresa_id = v_prov)
         + (select count(*) from public.productos where empresa_id = v_prov) + (select count(*) from public.terceros where empresa_id = v_prov)
         + (select count(*) from public.ordenes_compra where empresa_id = v_prov) into v_n;
    if v_n > 0 then raise exception 'La ficha provisional de Nutrifood tiene datos (%); revisar a mano antes de convertir.', v_n; end if;
    update public.empresas set estado = 'anulada', nit = 'RETIRADO-NUTRIFOOD', nombre_corto = 'UT Nutrifood (provisional retirada)'
     where id = v_prov;
  end if;

  update public.empresas
     set nit = '902116853', dv = '7', razon_social = 'UNION TEMPORAL NUTRIFOOD', nombre_corto = 'UT Nutrifood', es_practica = false,
         grupo_id = coalesce(v_grupo, grupo_id)
   where id = v_prac;

  update public.contratos
     set notas = regexp_replace(coalesce(notas, ''), '^PRACTICA con datos reales\. ', 'Contrato real (convertido de practica el 6-nov-2026). ')
   where empresa_id = v_prac;
end $$;
