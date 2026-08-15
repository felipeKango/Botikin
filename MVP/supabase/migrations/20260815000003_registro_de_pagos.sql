-- ============================================================
-- Botikin — Registro de operaciones de pago
--
-- Cada cobro de Flow queda acá, haya terminado bien o mal. Es la
-- contabilidad del producto y el respaldo cuando alguien reclama:
-- "pagué y no me llegó nada" se responde con una fila, no con memoria.
--
-- La orden de Flow es única: la misma notificación puede llegar dos
-- veces (Flow reintenta) y no puede generar dos códigos ni cobrar dos
-- veces al mismo hogar.
-- ============================================================

create type estado_pago as enum ('exitoso', 'rechazado', 'pendiente', 'reversado');

create table public.pagos (
  id             uuid primary key default gen_random_uuid(),
  orden_flow     text not null unique,          -- el candado de idempotencia
  monto          integer not null check (monto > 0),
  moneda         text not null default 'CLP',
  estado         estado_pago not null,
  email          text,
  medio_pago     text,                          -- Onepay, WebPay, transferencia…
  tarjeta_final  text check (tarjeta_final is null or length(tarjeta_final) <= 4),
  pagado_el      timestamptz not null,
  activacion_id  uuid references public.activaciones(id) on delete set null,
  hogar_id       uuid references public.hogares(id) on delete set null,
  crudo          jsonb,                         -- la notificación tal cual llegó
  created_at     timestamptz not null default now()
);
create index pagos_email_idx  on public.pagos (lower(email), pagado_el desc);
create index pagos_estado_idx on public.pagos (estado, pagado_el desc);

comment on column public.pagos.tarjeta_final is
  'Solo los últimos 4 dígitos, para que soporte pueda identificar el cobro. '
  'Jamás el número completo ni el CVV: eso vive en la pasarela, no acá.';
comment on column public.pagos.crudo is
  'La notificación cruda de Flow. Si mañana cambian un campo, el histórico '
  'sigue siendo interpretable.';

alter table public.pagos enable row level security;

-- ------------------------------------------------------------
-- registrar_pago: lo que llama el webhook de Flow.
--
-- Un cobro exitoso genera su código de activación en el mismo acto.
-- Si la orden ya existe, devuelve el código que ya se había generado:
-- Flow reintenta, y reintentar no puede duplicar nada.
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- Cuando el código se canjea, el pago queda amarrado al hogar que
-- nació de él. Así se puede ir del cobro a la casa y de vuelta.
-- ------------------------------------------------------------
create or replace function public.enlazar_pago_a_hogar()
returns trigger language plpgsql as $$
begin
  if new.estado = 'usada' and new.hogar_id is not null then
    update pagos set hogar_id = new.hogar_id where activacion_id = new.id;
  end if;
  return new;
end;
$$;

create trigger activaciones_enlazan_pago
  after update on public.activaciones
  for each row execute function public.enlazar_pago_a_hogar();
