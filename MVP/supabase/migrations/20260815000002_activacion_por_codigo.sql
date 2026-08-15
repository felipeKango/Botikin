-- ============================================================
-- Botikin — Activación por código
--
-- El problema que resuelve: el teléfono escrito en un formulario NO es
-- prueba de nada. La persona se equivoca, pone el fijo de la casa, o el
-- de su pareja. Y un hogar creado sobre un número equivocado es un hogar
-- al que su dueño nunca va a poder entrar.
--
-- El código cierra eso: llega al correo de quien pagó, y solo se puede
-- canjear escribiéndolo POR WHATSAPP. El teléfono queda demostrado por
-- el acto de escribir, no declarado en un campo.
-- ============================================================

create type estado_activacion as enum ('pendiente', 'usada', 'expirada');

create table public.activaciones (
  id                   uuid primary key default gen_random_uuid(),
  codigo               text not null unique,
  email                text not null,
  flow_subscription_id text,
  flow_customer_id     text,
  invitacion_id        uuid references public.invitaciones(id) on delete set null,
  estado               estado_activacion not null default 'pendiente',
  expira_el            timestamptz not null default now() + interval '30 days',
  hogar_id             uuid references public.hogares(id) on delete set null,
  usada_el             timestamptz,
  created_at           timestamptz not null default now()
);
create index activaciones_pendientes_idx
  on public.activaciones (codigo) where estado = 'pendiente';

alter table public.activaciones enable row level security;

-- ------------------------------------------------------------
-- Intentos fallidos por teléfono: sin esto, seis caracteres son
-- adivinables a fuerza bruta desde WhatsApp.
-- ------------------------------------------------------------
create table public.intentos_activacion (
  telefono   text primary key,
  fallidos   integer not null default 0,
  ultimo     timestamptz not null default now()
);
alter table public.intentos_activacion enable row level security;

-- ------------------------------------------------------------
-- generar_codigo: 6 caracteres de un alfabeto sin ambigüedades.
-- Se dictan por teléfono y se escriben a mano: fuera 0/O, 1/I/L, 5/S.
-- ------------------------------------------------------------
create or replace function public.generar_codigo()
returns text language plpgsql volatile as $$
declare
  v_alfabeto constant text := '234789ABCDEFGHJKMNPQRTUVWXYZ';
  v_codigo text;
begin
  loop
    v_codigo := '';
    for _ in 1..6 loop
      v_codigo := v_codigo || substr(v_alfabeto, 1 + floor(random() * length(v_alfabeto))::int, 1);
    end loop;
    exit when not exists (select 1 from activaciones where codigo = v_codigo);
  end loop;
  return v_codigo;
end;
$$;

-- ------------------------------------------------------------
-- crear_activacion: la llama el webhook de Flow cuando el cobro
-- se confirma. Devuelve el código que hay que mandar por correo.
-- ------------------------------------------------------------
create or replace function public.crear_activacion(
  p_email                text,
  p_flow_subscription_id text default null,
  p_flow_customer_id     text default null,
  p_invitacion           uuid default null
) returns text
language plpgsql security definer set search_path = public as $$
declare v_codigo text;
begin
  v_codigo := generar_codigo();
  insert into activaciones (codigo, email, flow_subscription_id, flow_customer_id, invitacion_id)
  values (v_codigo, lower(trim(p_email)), p_flow_subscription_id, p_flow_customer_id, p_invitacion);
  return v_codigo;
end;
$$;

-- ------------------------------------------------------------
-- canjear_activacion: el momento en que un número se convierte en
-- un hogar. Atómico: o queda todo, o no queda nada.
--
-- Devuelve (hogar_id, resultado). resultado ∈
--   ok | no_existe | ya_usada | expirada | bloqueado | ya_tiene_hogar
-- ------------------------------------------------------------
create or replace function public.canjear_activacion(
  p_codigo   text,
  p_telefono text
) returns table (hogar uuid, resultado text)
language plpgsql security definer set search_path = public as $$
declare
  v_act   activaciones%rowtype;
  v_hogar uuid;
  v_fallidos integer;
begin
  -- El candado anti fuerza bruta: 5 intentos por hora y por teléfono.
  select fallidos into v_fallidos from intentos_activacion
    where telefono = p_telefono and ultimo > now() - interval '1 hour';
  if coalesce(v_fallidos, 0) >= 5 then
    return query select null::uuid, 'bloqueado';
    return;
  end if;

  -- Un teléfono que ya es hogar no canjea nada.
  select id into v_hogar from hogares where telefono = p_telefono;
  if found then
    return query select v_hogar, 'ya_tiene_hogar';
    return;
  end if;

  select * into v_act from activaciones
    where codigo = upper(regexp_replace(p_codigo, '[^A-Za-z0-9]', '', 'g'))
    for update;

  if not found then
    insert into intentos_activacion (telefono, fallidos, ultimo)
      values (p_telefono, 1, now())
      on conflict (telefono) do update
        set fallidos = case when intentos_activacion.ultimo > now() - interval '1 hour'
                            then intentos_activacion.fallidos + 1 else 1 end,
            ultimo = now();
    return query select null::uuid, 'no_existe';
    return;
  end if;

  if v_act.estado = 'usada' then
    return query select null::uuid, 'ya_usada'; return;
  end if;
  if v_act.expira_el < now() then
    update activaciones set estado = 'expirada' where id = v_act.id;
    return query select null::uuid, 'expirada'; return;
  end if;

  -- Nace el hogar, con el teléfono DEMOSTRADO por este mensaje.
  insert into hogares (telefono, invitacion_id, onboarding)
    values (p_telefono, v_act.invitacion_id, 'nuevo')
    returning id into v_hogar;

  insert into suscripciones (hogar_id, estado, flow_customer_id, flow_subscription_id,
                             proximo_cobro, ultimo_cobro_ok)
    values (v_hogar, 'activa', v_act.flow_customer_id, v_act.flow_subscription_id,
            (current_date + interval '1 month')::date, current_date);

  insert into conversaciones (hogar_id, ultimo_mensaje_usuario)
    values (v_hogar, now());

  update activaciones set estado = 'usada', hogar_id = v_hogar, usada_el = now()
    where id = v_act.id;

  if v_act.invitacion_id is not null then
    update invitaciones set usos_actuales = usos_actuales + 1 where id = v_act.invitacion_id;
  end if;

  delete from intentos_activacion where telefono = p_telefono;

  return query select v_hogar, 'ok';
end;
$$;
