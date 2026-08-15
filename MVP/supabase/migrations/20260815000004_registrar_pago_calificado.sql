-- Corrige una ambigüedad: el parámetro de salida `codigo` chocaba con
-- la columna `activaciones.codigo` dentro del INSERT.

create or replace function public.registrar_pago(
  p_orden      text,
  p_monto      integer,
  p_estado     estado_pago,
  p_email      text default null,
  p_medio      text default null,
  p_tarjeta    text default null,
  p_pagado_el  timestamptz default now(),
  p_crudo      jsonb default null
) returns table (codigo text, ya_existia boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_pago   pagos%rowtype;
  v_codigo text;
begin
  -- ¿Ya vimos esta orden? Devolvemos lo mismo de antes.
  select * into v_pago from pagos where orden_flow = p_orden;
  if found then
    select a.codigo into v_codigo from activaciones a where a.id = v_pago.activacion_id;
    return query select v_codigo, true;
    return;
  end if;

  if p_estado = 'exitoso' then
    if p_email is null or trim(p_email) = '' then
      raise exception 'un pago exitoso necesita correo: es a donde va el código';
    end if;
    v_codigo := crear_activacion(p_email);
  end if;

  insert into pagos (orden_flow, monto, estado, email, medio_pago, tarjeta_final,
                     pagado_el, activacion_id, crudo)
  values (p_orden, p_monto, p_estado, lower(nullif(trim(p_email), '')), p_medio,
          right(regexp_replace(coalesce(p_tarjeta, ''), '\D', '', 'g'), 4),
          p_pagado_el,
          (select a.id from activaciones a where a.codigo = v_codigo),
          p_crudo);

  return query select v_codigo, false;
end;
$$;

