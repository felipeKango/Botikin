-- ============================================================
-- Botikin — De la receta a las tomas
--
-- La receta se leía y se creaban los tratamientos, pero faltaban las dos
-- piezas que la vuelven útil:
--
--   1. El CRUCE con el botiquín — saber qué de lo recetado ya está en casa
--      y qué hay que ir a comprar. Sin eso el usuario sale de la consulta
--      igual de perdido que antes.
--   2. Las TOMAS — sin ellas no hay nada que recordar. Un tratamiento sin
--      tomas es una anotación, no un acompañamiento.
-- ============================================================

-- ------------------------------------------------------------
-- cruzar_con_botiquin: ¿esto que me recetaron ya lo tengo?
--
-- Cruza por principio activo + concentración + forma, la misma llave con
-- que se detectan los duplicados. Devuelve lo que hay vigente en esa casa.
-- ------------------------------------------------------------
create or replace function public.cruzar_con_botiquin(
  p_hogar            uuid,
  p_principio_activo text,
  p_concentracion    text,
  p_forma            text
) returns table (
  medicamento_id uuid,
  marca          text,
  cantidad       numeric,
  unidad         text,
  vence          date,
  de_quien       text
) language sql stable security definer set search_path = public as $$
  select m.id, m.marca_comprada, m.cantidad, m.unidad, m.fecha_vencimiento,
         coalesce(i.nombre, 'la casa')
    from medicamentos m
    join productos p on p.id = m.producto_id
    left join integrantes i on i.id = m.integrante_id
   where m.hogar_id = p_hogar
     and m.estado = 'vigente'
     and lower(trim(p.principio_activo))   = lower(trim(p_principio_activo))
     and lower(trim(p.concentracion))      = lower(trim(p_concentracion))
     and lower(trim(p.forma_farmaceutica)) = lower(trim(p_forma))
   order by m.fecha_vencimiento nulls last;
$$;

-- ------------------------------------------------------------
-- generar_tomas: convierte una pauta en eventos concretos.
--
-- Los horarios NO se reparten matemáticamente. Una pauta de "cada 8 horas"
-- repartida exacta cae a las 00:00, y despertar a alguien de madrugada para
-- un jarabe para la tos es peor medicina que darlo un poco antes.
-- Se reparte dentro de las horas de vigilia, respetando el silencio
-- nocturno del PRD 06 (22:00 a 08:00).
--
-- La dosis y el intervalo que el agente REPITE son siempre los del médico;
-- esto solo decide a qué hora suena el recordatorio.
-- ------------------------------------------------------------
create or replace function public.generar_tomas(
  p_tratamiento uuid,
  p_dias_horizonte integer default 14
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  t         tratamientos%rowtype;
  v_horas   int[];
  v_hasta   date;
  v_dia     date;
  v_hora    int;
  v_momento timestamptz;
  v_creadas int := 0;
  v_hoy     date := (now() at time zone 'America/Santiago')::date;
begin
  select * into t from tratamientos where id = p_tratamiento;
  if not found then raise exception 'tratamiento no existe'; end if;

  -- Un SOS no tiene horario: se toma si hace falta. Generarle tomas sería
  -- inventar una pauta que el médico no escribió.
  if t.duracion = 'sos' or t.cada_horas is null then return 0; end if;

  v_horas := case
    when t.cada_horas >= 24 then array[8]
    when t.cada_horas >= 12 then array[8, 20]
    when t.cada_horas >= 8  then array[8, 15, 22]
    when t.cada_horas >= 6  then array[8, 13, 18, 22]
    else array[8, 12, 16, 20, 22]
  end;

  v_hasta := least(
    coalesce(t.fecha_termino, v_hoy + p_dias_horizonte),
    v_hoy + p_dias_horizonte);

  v_dia := greatest(t.fecha_inicio, v_hoy);

  while v_dia <= v_hasta loop
    foreach v_hora in array v_horas loop
      v_momento := (v_dia + make_time(v_hora, 0, 0)) at time zone 'America/Santiago';
      if v_momento > now() then
        insert into tomas (tratamiento_id, hogar_id, momento_programado)
        select p_tratamiento, t.hogar_id, v_momento
        where not exists (
          select 1 from tomas
           where tratamiento_id = p_tratamiento and momento_programado = v_momento);
        v_creadas := v_creadas + 1;
      end if;
    end loop;
    v_dia := v_dia + 1;
  end loop;

  return v_creadas;
end;
$$;

-- ------------------------------------------------------------
-- Al crear un tratamiento, sus tomas nacen con él.
-- ------------------------------------------------------------
create or replace function public.tratamiento_genera_tomas()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform generar_tomas(new.id);
  return new;
end;
$$;

drop trigger if exists tratamientos_generan_tomas on public.tratamientos;
create trigger tratamientos_generan_tomas
  after insert on public.tratamientos
  for each row execute function public.tratamiento_genera_tomas();

-- ------------------------------------------------------------
-- Las tomas de un bloque del día, agrupadas y listas para un solo
-- mensaje. Es lo que va a leer el proceso que manda los recordatorios.
-- ------------------------------------------------------------
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
         p.principio_activo || ' ' || p.concentracion,
         t.dosis_cantidad || ' ' || t.dosis_unidad,
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

-- ------------------------------------------------------------
-- Confirmar una toma descuenta del stock. Una toma sin confirmar no
-- descuenta nada: no sabemos si se tomó, y suponer que sí haría que el
-- "te alcanza hasta el X" fuera una mentira.
-- ------------------------------------------------------------
create or replace function public.confirmar_toma(
  p_toma uuid,
  p_estado estado_toma default 'confirmada'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  tm tomas%rowtype;
  t  tratamientos%rowtype;
  v_restante numeric;
begin
  select * into tm from tomas where id = p_toma for update;
  if not found then return jsonb_build_object('error', 'toma no existe'); end if;

  update tomas set estado = p_estado,
                   confirmada_at = case when p_estado = 'confirmada' then now() end
   where id = p_toma;

  if p_estado <> 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', p_estado);
  end if;

  select * into t from tratamientos where id = tm.tratamiento_id;

  update medicamentos
     set cantidad = greatest(0, cantidad - t.dosis_cantidad)
   where id = t.medicamento_id
  returning cantidad into v_restante;

  return jsonb_build_object('ok', true, 'estado', 'confirmada', 'restante', v_restante);
end;
$$;
