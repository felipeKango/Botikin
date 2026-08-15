-- =====================================================================
-- Botikin · Códigos de acceso ABCD-EFGH
-- Ejecutar completo en Supabase → SQL Editor
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tabla acumuladora
-- ---------------------------------------------------------------------
create table if not exists public.access_codes (
  id             uuid primary key default gen_random_uuid(),
  code           text not null,                                   -- formato visible: ABCD-EFGH
  code_key       text generated always as (upper(replace(code, '-', ''))) stored,
  email          text,
  full_name      text,
  status         text not null default 'issued'
                   check (status in ('issued','sent','redeemed','revoked')),
  source         text default 'waitlist',                         -- waitlist | referido | feria | manual
  issued_at      timestamptz not null default now(),
  sent_at        timestamptz,
  expires_at     timestamptz not null default (now() + interval '30 days'),
  redeemed_at    timestamptz,
  redeemed_by    uuid references auth.users(id) on delete set null,
  attempts       integer not null default 0,
  metadata       jsonb not null default '{}'::jsonb,
  constraint access_codes_format_chk check (code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$')
);

create unique index if not exists access_codes_key_uidx    on public.access_codes (code_key);
create index        if not exists access_codes_email_idx   on public.access_codes (lower(email));
create index        if not exists access_codes_status_idx  on public.access_codes (status, expires_at desc);

comment on table public.access_codes is 'Códigos de acceso anticipado a Botikin. Un registro por invitación emitida.';

-- ---------------------------------------------------------------------
-- 2. Generador ABCD-EFGH
--    Alfabeto de 32 símbolos sin I, O, 0, 1 (evita errores al dictarlo).
--    256 / 32 = 8 exacto → sin sesgo de módulo. Espacio: 32^8 ≈ 1,1 billones.
-- ---------------------------------------------------------------------
create or replace function public.generate_access_code()
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes    bytea := gen_random_bytes(8);
  raw      text  := '';
  i        int;
begin
  for i in 0..7 loop
    raw := raw || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return substr(raw, 1, 4) || '-' || substr(raw, 5, 4);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Emitir código (server-side: service_role / Edge Function)
--    Idempotente: si el correo ya tiene un código vigente, lo devuelve.
-- ---------------------------------------------------------------------
create or replace function public.issue_access_code(
  p_email      text,
  p_full_name  text default null,
  p_source     text default 'waitlist',
  p_valid_days int  default 30
)
returns public.access_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.access_codes;
  v_try int := 0;
begin
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'email inválido: %', p_email using errcode = '22023';
  end if;

  select * into v_row
    from access_codes
   where lower(email) = lower(p_email)
     and status in ('issued','sent')
     and expires_at > now()
   order by issued_at desc
   limit 1;

  if found then
    return v_row;                       -- reenvío del mismo código, no genera uno nuevo
  end if;

  loop
    v_try := v_try + 1;
    begin
      insert into access_codes (code, email, full_name, source, expires_at)
      values (
        generate_access_code(),
        lower(trim(p_email)),
        nullif(trim(coalesce(p_full_name,'')), ''),
        p_source,
        now() + make_interval(days => p_valid_days)
      )
      returning * into v_row;
      return v_row;
    exception when unique_violation then
      if v_try >= 10 then raise; end if; -- colisión: reintenta
    end;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Marcar como enviado (después del envío del correo)
-- ---------------------------------------------------------------------
create or replace function public.mark_access_code_sent(p_code text)
returns public.access_codes
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.access_codes;
begin
  update access_codes
     set status  = case when status = 'issued' then 'sent' else status end,
         sent_at = now()
   where code_key = upper(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g'))
  returning * into v_row;
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Canjear código (lo llama la app con el usuario ya autenticado)
--    Devuelve jsonb: { ok, error, code, expires_at }
-- ---------------------------------------------------------------------
create or replace function public.redeem_access_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_key   text;
  v_row   public.access_codes;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'sin_sesion');
  end if;

  select email into v_email from auth.users where id = v_uid;

  v_key := upper(regexp_replace(coalesce(p_code,''), '[^a-zA-Z0-9]', '', 'g'));
  if length(v_key) <> 8 then
    return jsonb_build_object('ok', false, 'error', 'formato_invalido');
  end if;

  select * into v_row from access_codes where code_key = v_key for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  update access_codes set attempts = attempts + 1 where id = v_row.id;

  if v_row.status = 'revoked' then
    return jsonb_build_object('ok', false, 'error', 'revocado');
  end if;

  if v_row.status = 'redeemed' then
    return case
      when v_row.redeemed_by = v_uid
        then jsonb_build_object('ok', true, 'code', v_row.code, 'already', true)
      else jsonb_build_object('ok', false, 'error', 'ya_usado')
    end;
  end if;

  if v_row.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'vencido');
  end if;

  -- El código queda amarrado al correo al que se emitió
  if v_row.email is not null and lower(v_row.email) is distinct from lower(v_email) then
    return jsonb_build_object('ok', false, 'error', 'correo_no_coincide');
  end if;

  update access_codes
     set status = 'redeemed', redeemed_at = now(), redeemed_by = v_uid
   where id = v_row.id;

  return jsonb_build_object('ok', true, 'code', v_row.code, 'redeemed_at', now());
end;
$$;

-- ---------------------------------------------------------------------
-- 6. RLS: nadie lee la tabla salvo su propio código canjeado.
--    La emisión vive solo en el servidor (service_role ignora RLS).
-- ---------------------------------------------------------------------
alter table public.access_codes enable row level security;

drop policy if exists "usuario ve su propio código" on public.access_codes;
create policy "usuario ve su propio código"
  on public.access_codes for select
  to authenticated
  using (redeemed_by = auth.uid());

revoke execute on function public.issue_access_code(text, text, text, int)  from anon, authenticated;
revoke execute on function public.mark_access_code_sent(text)               from anon, authenticated;
revoke execute on function public.generate_access_code()                    from anon, authenticated;
grant  execute on function public.redeem_access_code(text)                  to   authenticated;

-- ---------------------------------------------------------------------
-- 7. Vista de control (para el dashboard interno)
-- ---------------------------------------------------------------------
create or replace view public.access_codes_stats as
select
  count(*)                                                              as emitidos,
  count(*) filter (where status = 'sent')                               as enviados,
  count(*) filter (where status = 'redeemed')                           as canjeados,
  count(*) filter (where status in ('issued','sent') and expires_at <= now()) as vencidos,
  count(*) filter (where status = 'revoked')                            as revocados,
  round(100.0 * count(*) filter (where status = 'redeemed')
        / nullif(count(*) filter (where status in ('sent','redeemed')), 0), 1) as tasa_activacion_pct
from public.access_codes;

-- ---------------------------------------------------------------------
-- 8. Prueba rápida
-- ---------------------------------------------------------------------
-- select public.generate_access_code();                       -- ej: K7QP-M3XZ
-- select * from public.issue_access_code('felipe@botikin.cl', 'Felipe', 'manual');
-- select * from public.access_codes_stats;
