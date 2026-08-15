-- ============================================================
-- Botikin — Funciones de negocio y scheduler
-- ============================================================

-- ------------------------------------------------------------
-- consume_tokens: descuento atómico de tokens ("el portero").
-- La llama ai-engine con service_role ANTES de responder a Claude.
-- tokens_total = -1 → plan Pro ilimitado (registra uso, no descuenta).
-- Lanza excepción 'insufficient_tokens' si no alcanza el saldo.
-- ------------------------------------------------------------
create or replace function public.consume_tokens(
  p_user_id uuid,
  p_action  token_action_type,
  p_amount  integer
) returns table (tokens_restantes integer, plan plan_type)
language plpgsql
security definer set search_path = public
as $$
declare
  v_sub subscriptions%rowtype;
begin
  if p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  -- Lock de la fila para evitar dobles descuentos concurrentes
  select * into v_sub from subscriptions s
    where s.user_id = p_user_id for update;

  if not found then
    raise exception 'no_subscription';
  end if;

  if v_sub.estado <> 'active' then
    raise exception 'subscription_inactive';
  end if;

  -- Renovación vencida de plan free: resetea el ciclo automáticamente
  if v_sub.fecha_renovacion < now() and v_sub.plan = 'free' then
    update subscriptions set tokens_usados = 0,
      fecha_renovacion = now() + interval '1 month'
      where user_id = p_user_id;
    v_sub.tokens_usados := 0;
  end if;

  if v_sub.tokens_total <> -1
     and v_sub.tokens_usados + p_amount > v_sub.tokens_total then
    raise exception 'insufficient_tokens';
  end if;

  if v_sub.tokens_total <> -1 then
    update subscriptions set tokens_usados = tokens_usados + p_amount
      where user_id = p_user_id;
  end if;

  insert into token_usage (user_id, tipo_accion, tokens_consumidos)
    values (p_user_id, p_action, p_amount);

  return query
    select case when s.tokens_total = -1 then -1
                else s.tokens_total - s.tokens_usados end,
           s.plan
    from subscriptions s where s.user_id = p_user_id;
end;
$$;

-- Solo service_role puede ejecutarla: el cliente nunca descuenta solo.
revoke execute on function public.consume_tokens from public, anon, authenticated;

-- ------------------------------------------------------------
-- redeem_discount_code: valida y consume un uso del código.
-- La llama discount-code-api / payments-api con service_role.
-- ------------------------------------------------------------
create or replace function public.redeem_discount_code(
  p_user_id uuid,
  p_codigo  text
) returns table (meses_gratis integer)
language plpgsql
security definer set search_path = public
as $$
declare
  v_code discount_codes%rowtype;
begin
  select * into v_code from discount_codes d
    where upper(d.codigo) = upper(trim(p_codigo)) for update;

  if not found then
    raise exception 'code_not_found';
  end if;
  if not v_code.activo then
    raise exception 'code_inactive';
  end if;
  if v_code.expira_el is not null and v_code.expira_el < current_date then
    raise exception 'code_expired';
  end if;
  if v_code.usos_actuales >= v_code.usos_maximos then
    raise exception 'code_exhausted';
  end if;
  if exists (select 1 from subscriptions s
             where s.user_id = p_user_id
               and s.codigo_descuento_usado = v_code.codigo) then
    raise exception 'code_already_used';
  end if;

  update discount_codes set usos_actuales = usos_actuales + 1
    where id = v_code.id;

  return query select v_code.meses_gratis;
end;
$$;

revoke execute on function public.redeem_discount_code from public, anon, authenticated;

-- ------------------------------------------------------------
-- activate_plan: aplica un plan a la suscripción (webhook WebPay
-- o canje de código). Resetea el ciclo de tokens.
-- ------------------------------------------------------------
create or replace function public.activate_plan(
  p_user_id uuid,
  p_plan    plan_type,
  p_meses   integer default 1,
  p_codigo  text default null
) returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_tokens integer;
begin
  v_tokens := case p_plan
    when 'free'  then 500
    when 'basic' then 5000
    when 'pro'   then -1
  end;

  update subscriptions set
    plan = p_plan,
    estado = 'active',
    tokens_total = v_tokens,
    tokens_usados = 0,
    fecha_renovacion = now() + (p_meses || ' month')::interval,
    codigo_descuento_usado = coalesce(p_codigo, codigo_descuento_usado)
  where user_id = p_user_id;
end;
$$;

revoke execute on function public.activate_plan from public, anon, authenticated;

-- ------------------------------------------------------------
-- Config privada para el cron (URL del proyecto + service key).
-- Rellenar tras el deploy: ver README.
-- ------------------------------------------------------------
create schema if not exists private;
create table if not exists private.app_config (
  key   text primary key,
  value text not null
);

-- ------------------------------------------------------------
-- Cron diario 08:00 America/Santiago (12:00 UTC): invoca la Edge
-- Function expiry-scheduler, que revisa vencimientos y dispara
-- alertas push + WhatsApp.
-- ------------------------------------------------------------
create or replace function private.invoke_expiry_scheduler()
returns void
language plpgsql
security definer
as $$
declare
  v_url text;
  v_key text;
begin
  select value into v_url from private.app_config where key = 'edge_functions_url';
  select value into v_key from private.app_config where key = 'service_role_key';
  if v_url is null or v_key is null then
    raise notice 'app_config incompleta: no se invoca expiry-scheduler';
    return;
  end if;

  perform net.http_post(
    url     := v_url || '/expiry-scheduler',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := '{}'::jsonb
  );
end;
$$;

select cron.schedule(
  'botikin-expiry-daily',
  '0 12 * * *',
  $$select private.invoke_expiry_scheduler()$$
);
