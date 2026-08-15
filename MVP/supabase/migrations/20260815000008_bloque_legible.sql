-- ============================================================
-- Botikin — Que el recordatorio se lea como lo diría una persona
--
-- La primera prueba de tomas_del_bloque devolvió dos cosas que nadie
-- escribiría en un mensaje:
--
--   "1.00 inhalación de null"   ← numeric(10,2) crudo, y un producto sin resolver
--
-- El "1.00" viene del tipo de la columna y el "null" de un tratamiento cuyo
-- principio activo todavía no está en el diccionario. Ninguno de los dos es
-- razón para mandar un mensaje roto: la dosis se muestra sin ceros de
-- relleno, y si no sabemos el nombre del remedio decimos lo que sí sabemos.
-- ============================================================

create or replace function public.tomas_del_bloque(
  p_hogar uuid,
  p_desde timestamptz default now(),
  p_hasta timestamptz default now() + interval '3 hours'
) returns table (
  toma_id  uuid,
  de_quien text,
  que      text,
  dosis    text,
  momento  timestamptz
) language sql stable security definer set search_path = public as $$
  select tm.id,
         i.nombre,
         coalesce(p.principio_activo || ' ' || p.concentracion, 'su tratamiento'),
         -- trim_scale quita los ceros de relleno: 1.00 → 1, 3.80 → 3.8
         trim_scale(t.dosis_cantidad)::text || ' ' || t.dosis_unidad,
         tm.momento_programado
    from tomas tm
    join tratamientos t on t.id = tm.tratamiento_id
    join integrantes i  on i.id = t.integrante_id
    left join productos p on p.id = t.producto_id
   where tm.hogar_id = p_hogar
     and tm.estado = 'pendiente'
     and t.estado = 'activo'
     and tm.momento_programado between p_desde and p_hasta
   order by tm.momento_programado, i.nombre;
$$;
