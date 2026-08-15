-- ============================================================
-- Botikin — Schema inicial
-- Tablas core del negocio. RLS se activa en la migración 0002.
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ------------------------------------------------------------
-- Tipos enumerados
-- ------------------------------------------------------------
create type plan_type as enum ('free', 'basic', 'pro');
create type subscription_status as enum ('active', 'past_due', 'canceled');
create type token_action_type as enum (
  'prescription_analysis',  -- análisis de receta con foto (~800–1.200)
  'cabinet_analysis',       -- análisis de botiquín (~300–500)
  'whatsapp_message',       -- mensaje WhatsApp generado (~200–400)
  'assistant_chat'          -- chat asistente (~100–300 por turno)
);
create type whatsapp_message_type as enum ('expiry_alert', 'reminder', 'ai_suggestion');
create type delivery_status as enum ('sent', 'delivered', 'failed');

-- ------------------------------------------------------------
-- users — perfil público, espejo de auth.users
-- ------------------------------------------------------------
create table public.users (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null unique,
  nombre      text not null default '',
  telefono    text,                -- E.164, ej: +56912345678 (para WhatsApp)
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- subscriptions — LA tabla del negocio
-- tokens_total = -1 significa ilimitado (plan Pro)
-- ------------------------------------------------------------
create table public.subscriptions (
  id                      uuid primary key default uuid_generate_v4(),
  user_id                 uuid not null unique references public.users(id) on delete cascade,
  plan                    plan_type not null default 'free',
  estado                  subscription_status not null default 'active',
  tokens_total            integer not null default 500,
  tokens_usados           integer not null default 0 check (tokens_usados >= 0),
  fecha_renovacion        timestamptz not null default now() + interval '1 month',
  codigo_descuento_usado  text,
  transbank_buy_order     text,   -- última orden de compra WebPay confirmada
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- ------------------------------------------------------------
-- medicines — inventario del botiquín
-- ------------------------------------------------------------
create table public.medicines (
  id                 uuid primary key default uuid_generate_v4(),
  user_id            uuid not null references public.users(id) on delete cascade,
  nombre             text not null,
  dosis              text not null default '',        -- "500mg", "20mg"
  unidades           integer not null default 0 check (unidades >= 0),
  fecha_vencimiento  date not null,
  foto_path          text,                            -- ruta en Storage (bucket medicine-photos)
  viene_de_receta    boolean not null default false,
  prescription_id    uuid,                            -- FK blanda; se llena al importar desde receta
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index medicines_user_expiry_idx on public.medicines (user_id, fecha_vencimiento);

-- ------------------------------------------------------------
-- prescriptions — recetas escaneadas y su análisis de Claude
-- analysis JSON: { medico, fecha_receta, medicamentos: [{nombre, dosis, posologia, indicaciones}] }
-- ------------------------------------------------------------
create table public.prescriptions (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.users(id) on delete cascade,
  foto_path   text not null,        -- ruta en Storage (bucket prescriptions)
  analysis    jsonb,
  created_at  timestamptz not null default now()
);
create index prescriptions_user_idx on public.prescriptions (user_id, created_at desc);

alter table public.medicines
  add constraint medicines_prescription_fk
  foreign key (prescription_id) references public.prescriptions(id) on delete set null;

-- ------------------------------------------------------------
-- token_usage — cada consumo de IA queda registrado
-- ------------------------------------------------------------
create table public.token_usage (
  id                 uuid primary key default uuid_generate_v4(),
  user_id            uuid not null references public.users(id) on delete cascade,
  tipo_accion        token_action_type not null,
  tokens_consumidos  integer not null check (tokens_consumidos > 0),
  created_at         timestamptz not null default now()
);
create index token_usage_user_idx on public.token_usage (user_id, created_at desc);

-- ------------------------------------------------------------
-- discount_codes — campañas e influencers (mes gratis)
-- ------------------------------------------------------------
create table public.discount_codes (
  id             uuid primary key default uuid_generate_v4(),
  codigo         text not null unique,
  meses_gratis   integer not null default 1 check (meses_gratis > 0),
  usos_maximos   integer not null default 100 check (usos_maximos > 0),
  usos_actuales  integer not null default 0 check (usos_actuales >= 0),
  activo         boolean not null default true,
  expira_el      date,
  created_at     timestamptz not null default now()
);

-- ------------------------------------------------------------
-- whatsapp_messages — historial de mensajes enviados
-- ------------------------------------------------------------
create table public.whatsapp_messages (
  id               uuid primary key default uuid_generate_v4(),
  user_id          uuid not null references public.users(id) on delete cascade,
  telefono         text not null,
  texto            text not null,
  tipo             whatsapp_message_type not null,
  estado_entrega   delivery_status not null default 'sent',
  twilio_sid       text,
  created_at       timestamptz not null default now()
);
create index whatsapp_messages_user_idx on public.whatsapp_messages (user_id, created_at desc);

-- ------------------------------------------------------------
-- payment_transactions — auditoría de WebPay
-- ------------------------------------------------------------
create table public.payment_transactions (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid not null references public.users(id) on delete cascade,
  buy_order      text not null unique,
  tbk_token      text,
  plan           plan_type not null,
  monto_clp      integer not null,
  estado         text not null default 'initialized',  -- initialized | authorized | failed | reversed
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ------------------------------------------------------------
-- device_tokens — tokens APNs para push
-- ------------------------------------------------------------
create table public.device_tokens (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references public.users(id) on delete cascade,
  device_token text not null,
  created_at   timestamptz not null default now(),
  unique (user_id, device_token)
);

-- ------------------------------------------------------------
-- Trigger: al registrarse un usuario en auth, crear perfil +
-- suscripción free con 500 tokens.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.users (id, email, nombre)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nombre', ''));

  insert into public.subscriptions (user_id, plan, tokens_total, tokens_usados)
  values (new.id, 'free', 500, 0);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- updated_at automático
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger subscriptions_touch before update on public.subscriptions
  for each row execute function public.touch_updated_at();
create trigger medicines_touch before update on public.medicines
  for each row execute function public.touch_updated_at();
create trigger payment_transactions_touch before update on public.payment_transactions
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- Storage buckets (privados; acceso vía RLS de storage.objects)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('prescriptions', 'prescriptions', false),
  ('medicine-photos', 'medicine-photos', false)
on conflict (id) do nothing;
