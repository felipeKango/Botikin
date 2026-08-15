-- ============================================================
-- Botikin — Unificación de códigos de acceso
--
-- Había dos tablas de códigos: `activaciones` (canje por WhatsApp) y
-- `access_codes` (canje por web con sesión). Dos verdades sobre lo mismo.
--
-- Se queda `access_codes` — mejor generador (gen_random_bytes sin sesgo
-- de módulo, no random()) y emisión idempotente por correo — pero con el
-- canje reescrito: en el producto WhatsApp no hay sesión que consultar,
-- y lo que hay que demostrar es el TELÉFONO, no el correo.
-- ============================================================

create extension if not exists pgcrypto;

create table public.access_codes (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,                                   -- visible: ABCD-EFGH
  code_key    text generated always as (upper(replace(code, '-', ''))) stored,
  email       text,
  full_name   text,
  status      text not null default 'issued'
                check (status in ('issued','sent','redeemed','revoked')),
  source      text default 'pago',                             -- pago | referido | feria | manual
  issued_at   timestamptz not null default now(),
  sent_at     timestamptz,
  expires_at  timestamptz not null default (now() + interval '30 days'),
  redeemed_at timestamptz,
  hogar_id    uuid references public.hogares(id) on delete set null,
  attempts    integer not null default 0,
  metadata    jsonb not null default '{}'::jsonb,
  constraint access_codes_format_chk check (code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$')
);
create unique index access_codes_key_uidx   on public.access_codes (code_key);
create index        access_codes_email_idx  on public.access_codes (lower(email));
create index        access_codes_status_idx on public.access_codes (status, expires_at desc);

comment on column public.access_codes.hogar_id is
  'El hogar que nació de este código. Reemplaza al redeemed_by original: '
  'en WhatsApp no hay auth.users, hay un teléfono demostrado.';

alter table public.access_codes enable row level security;

-- ------------------------------------------------------------
-- Generador ABCD-EFGH. Alfabeto de 32 sin I, O, 0, 1 — se dicta
-- por teléfono. 256/32 = 8 exacto, así que no hay sesgo de módulo.
-- ------------------------------------------------------------
create or replace function public.generate_access_code()
returns text language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  -- pgcrypto vive en el esquema `extensions` en Supabase: hay que
  -- calificarlo o no se encuentra bajo search_path = public.
  bytes    bytea := extensions.gen_random_bytes(8);
  raw      text  := '';
  i        int;
begin
  for i in 0..7 loop
    raw := raw || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return substr(raw, 1, 4) || '-' || substr(raw, 5, 4);
end;
$$;

-- ------------------------------------------------------------
-- issue_access_code — idempotente por correo: si ya hay uno
-- vigente para ese correo, se devuelve ese. Reenviar el correo
-- no puede generar un código nuevo.
-- ------------------------------------------------------------
create or replace function public.issue_access_code(
  p_email      text,
  p_full_name  text default null,
  p_source     text default 'pago',
  p_valid_days int  default 30
) returns public.access_codes
language plpgsql security definer set search_path = public as $$
declare
  v_row public.access_codes;
  v_try int := 0;
begin
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'email inválido: %', p_email using errcode = '22023';
  end if;

  select * into v_row from access_codes
   where lower(email) = lower(p_email)
     and status in ('issued','sent')
     and expires_at > now()
   order by issued_at desc limit 1;
  if found then return v_row; end if;

  loop
    v_try := v_try + 1;
    begin
      insert into access_codes (code, email, full_name, source, expires_at)
      values (generate_access_code(), lower(trim(p_email)),
              nullif(trim(coalesce(p_full_name,'')), ''), p_source,
              now() + make_interval(days => p_valid_days))
      returning * into v_row;
      return v_row;
    exception when unique_violation then
      if v_try >= 10 then raise; end if;
    end;
  end loop;
end;
$$;

create or replace function public.mark_access_code_sent(p_code text)
returns public.access_codes
language plpgsql security definer set search_path = public as $$
declare v_row public.access_codes;
begin
  update access_codes
     set status = case when status = 'issued' then 'sent' else status end,
         sent_at = now()
   where code_key = upper(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g'))
  returning * into v_row;
  return v_row;
end;
$$;

-- ------------------------------------------------------------
-- canjear_codigo — EL CAMBIO DE FONDO.
--
-- El original exigía auth.uid() y comparaba contra el correo. Acá no
-- hay sesión: el canje llega por WhatsApp y lo que queda demostrado es
-- el teléfono desde el que se escribió. De ese acto nace el hogar.
--
-- Devuelve (hogar, resultado). resultado ∈
--   ok | no_existe | ya_usada | expirada | revocada | bloqueado | ya_tiene_hogar
-- ------------------------------------------------------------
create or replace function public.canjear_codigo(
  p_codigo   text,
  p_telefono text
) returns table (hogar uuid, resultado text)
language plpgsql security definer set search_path = public as $$
declare
  v_row      access_codes%rowtype;
  v_hogar    uuid;
  v_fallidos integer;
  v_key      text;
begin
  select fallidos into v_fallidos from intentos_activacion
    where telefono = p_telefono and ultimo > now() - interval '1 hour';
  if coalesce(v_fallidos, 0) >= 5 then
    return query select null::uuid, 'bloqueado'; return;
  end if;

  select id into v_hogar from hogares where telefono = p_telefono;
  if found then
    return query select v_hogar, 'ya_tiene_hogar'; return;
  end if;

  v_key := upper(regexp_replace(coalesce(p_codigo,''), '[^a-zA-Z0-9]', '', 'g'));
  select * into v_row from access_codes where code_key = v_key for update;

  if not found then
    insert into intentos_activacion (telefono, fallidos, ultimo)
      values (p_telefono, 1, now())
      on conflict (telefono) do update
        set fallidos = case when intentos_activacion.ultimo > now() - interval '1 hour'
                            then intentos_activacion.fallidos + 1 else 1 end,
            ultimo = now();
    return query select null::uuid, 'no_existe'; return;
  end if;

  update access_codes set attempts = attempts + 1 where id = v_row.id;

  if v_row.status = 'revoked'   then return query select null::uuid, 'revocada'; return; end if;
  if v_row.status = 'redeemed'  then return query select null::uuid, 'ya_usada'; return; end if;
  if v_row.expires_at <= now()  then return query select null::uuid, 'expirada'; return; end if;

  -- Nace el hogar, con el teléfono demostrado por este mensaje.
  insert into hogares (telefono, onboarding) values (p_telefono, 'nuevo')
    returning id into v_hogar;

  insert into suscripciones (hogar_id, estado, proximo_cobro, ultimo_cobro_ok)
    values (v_hogar, 'activa', (current_date + interval '1 month')::date, current_date);

  insert into conversaciones (hogar_id, ultimo_mensaje_usuario) values (v_hogar, now());

  update access_codes
     set status = 'redeemed', redeemed_at = now(), hogar_id = v_hogar
   where id = v_row.id;

  delete from intentos_activacion where telefono = p_telefono;
  return query select v_hogar, 'ok';
end;
$$;

-- ------------------------------------------------------------
-- El registro de pagos ahora apunta a access_codes.
-- ------------------------------------------------------------
alter table public.pagos drop constraint if exists pagos_activacion_id_fkey;
alter table public.pagos rename column activacion_id to codigo_id;
-- Los pagos existentes apuntaban a la tabla vieja: se desvinculan y más
-- abajo se les reemite el código en el formato nuevo.
update public.pagos set codigo_id = null;
alter table public.pagos add constraint pagos_codigo_fkey
  foreign key (codigo_id) references public.access_codes(id) on delete set null;

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
  v_pago pagos%rowtype;
  v_cod  access_codes%rowtype;
begin
  select * into v_pago from pagos where orden_flow = p_orden;
  if found then
    select * into v_cod from access_codes a where a.id = v_pago.codigo_id;
    return query select v_cod.code, true; return;
  end if;

  if p_estado = 'exitoso' then
    if p_email is null or trim(p_email) = '' then
      raise exception 'un pago exitoso necesita correo: es a donde va el código';
    end if;
    v_cod := issue_access_code(p_email, null, 'pago');
  end if;

  insert into pagos (orden_flow, monto, estado, email, medio_pago, tarjeta_final,
                     pagado_el, codigo_id, crudo)
  values (p_orden, p_monto, p_estado, lower(nullif(trim(p_email), '')), p_medio,
          right(regexp_replace(coalesce(p_tarjeta, ''), '\D', '', 'g'), 4),
          p_pagado_el, v_cod.id, p_crudo);

  return query select v_cod.code, false;
end;
$$;

-- El trigger que amarra el pago al hogar, ahora sobre access_codes.
drop trigger if exists activaciones_enlazan_pago on public.activaciones;
create or replace function public.enlazar_pago_a_hogar()
returns trigger language plpgsql as $$
begin
  if new.status = 'redeemed' and new.hogar_id is not null then
    update pagos set hogar_id = new.hogar_id where codigo_id = new.id;
  end if;
  return new;
end;
$$;
create trigger access_codes_enlazan_pago
  after update on public.access_codes
  for each row execute function public.enlazar_pago_a_hogar();

-- ------------------------------------------------------------
-- Fuera la tabla vieja. Los códigos pendientes de 6 caracteres no
-- caben en el formato nuevo, así que se reemiten desde su pago.
-- ------------------------------------------------------------
drop function if exists public.canjear_activacion(text, text);
drop function if exists public.crear_activacion(text, text, text, uuid);
drop table if exists public.activaciones cascade;
drop type if exists estado_activacion;

-- ------------------------------------------------------------
-- Reemisión: cada pago exitoso que quedó sin código recibe uno
-- nuevo en el formato ABCD-EFGH.
-- ------------------------------------------------------------
do $$
declare r record; v access_codes%rowtype;
begin
  for r in select * from pagos where estado = 'exitoso' and codigo_id is null and email is not null loop
    v := issue_access_code(r.email, null, 'pago');
    update pagos set codigo_id = v.id where id = r.id;
    raise notice 'pago % → código %', r.orden_flow, v.code;
  end loop;
end $$;
