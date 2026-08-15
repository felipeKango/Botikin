-- ============================================================
-- Botikin — Los tratamientos con fecha de término se cierran solos
--
-- El PRD 06 dice: "un tratamiento con duración se cierra solo el día que
-- corresponde". No estaba implementado, y se notó: la receta de Bruno del
-- 15 de mayo dejó dos tratamientos de 5 días que en agosto seguían
-- marcados como activos.
--
-- Un tratamiento vencido que figura activo no es un detalle cosmético:
-- el agente lo ve en su contexto y podría recordar una toma de un
-- tratamiento que terminó hace tres meses.
--
-- Se arregla en dos capas, a propósito:
--   1. Al LEER — contexto_hogar nunca devuelve uno vencido, así el agente
--      queda correcto aunque nadie haya corrido el mantenimiento.
--   2. Al MANTENER — cerrar_tratamientos_vencidos() actualiza el estado
--      para que los informes y el panel también digan la verdad.
-- ============================================================

create or replace function public.cerrar_tratamientos_vencidos()
returns integer language plpgsql security definer set search_path = public as $$
declare v_cerrados integer;
begin
  with cerrados as (
    update tratamientos
       set estado = 'terminado'
     where estado = 'activo'
       and duracion = 'dias'
       and fecha_termino is not null
       and fecha_termino < (now() at time zone 'America/Santiago')::date
    returning 1)
  select count(*) into v_cerrados from cerrados;
  return v_cerrados;
end;
$$;

-- ------------------------------------------------------------
-- contexto_hogar: mismo contrato, pero los tratamientos vencidos
-- ya no llegan al agente, y los que siguen traen cuántos días les
-- quedan — que es lo que el agente necesita para avisar a tiempo.
-- ------------------------------------------------------------
create or replace function public.contexto_hogar(p_hogar uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'hoy', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD'),
    'ahora', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD HH24:MI'),
    'onboarding', (select onboarding from hogares where id = p_hogar),
    'integrantes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'nombre', i.nombre, 'sexo', i.sexo,
        'fecha_nacimiento', i.fecha_nacimiento,
        'edad_anios', case when i.fecha_nacimiento is null then null
                      else extract(year from age(current_date, i.fecha_nacimiento))::int end,
        'edad_meses', case when i.fecha_nacimiento is null then null
                      else extract(month from age(current_date, i.fecha_nacimiento))::int end,
        'es_titular', i.es_titular))
      from integrantes i where i.hogar_id = p_hogar and i.activo), '[]'::jsonb),
    'inventario', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'principio_activo', p.principio_activo,
        'concentracion', p.concentracion,
        'forma', p.forma_farmaceutica,
        'marca', m.marca_comprada,
        'cantidad', m.cantidad, 'unidad', m.unidad,
        'vence', m.fecha_vencimiento,
        'dias_para_vencer', case when m.fecha_vencimiento is null then null
                            else (m.fecha_vencimiento - current_date) end,
        'de_quien', coalesce(i.nombre, 'la casa')))
      from medicamentos m
      left join productos p on p.id = m.producto_id
      left join integrantes i on i.id = m.integrante_id
      where m.hogar_id = p_hogar and m.estado = 'vigente'), '[]'::jsonb),
    'tratamientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'de_quien', i.nombre,
        'principio_activo', p.principio_activo,
        'dosis', t.dosis_cantidad || ' ' || t.dosis_unidad,
        'cada_horas', t.cada_horas,
        'duracion', t.duracion,
        'termina', t.fecha_termino,
        'dias_restantes', case when t.fecha_termino is null then null
                          else (t.fecha_termino - current_date) end))
      from tratamientos t
      join integrantes i on i.id = t.integrante_id
      left join productos p on p.id = t.producto_id
      where t.hogar_id = p_hogar
        and t.estado = 'activo'
        -- Un tratamiento cuya fecha ya pasó no es activo, aunque la
        -- columna todavía no se haya actualizado.
        and (t.fecha_termino is null or t.fecha_termino >= current_date)),
      '[]'::jsonb)
  );
$$;

-- Cerramos los que ya venían arrastrados.
select public.cerrar_tratamientos_vencidos();
