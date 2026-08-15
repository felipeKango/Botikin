-- ============================================================
-- Botikin — Row Level Security
-- TODAS las tablas con RLS. Cada usuario solo ve sus filas.
-- Las Edge Functions con service_role saltan RLS (by design).
-- ============================================================

alter table public.users               enable row level security;
alter table public.subscriptions       enable row level security;
alter table public.medicines           enable row level security;
alter table public.prescriptions      enable row level security;
alter table public.token_usage         enable row level security;
alter table public.discount_codes      enable row level security;
alter table public.whatsapp_messages   enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.device_tokens        enable row level security;

-- users: leer y editar solo el propio perfil
create policy "users_select_own" on public.users
  for select using (auth.uid() = id);
create policy "users_update_own" on public.users
  for update using (auth.uid() = id);

-- subscriptions: solo lectura para el dueño.
-- Escrituras SOLO desde Edge Functions (service_role): el cliente
-- jamás modifica su plan ni sus tokens directamente.
create policy "subscriptions_select_own" on public.subscriptions
  for select using (auth.uid() = user_id);

-- medicines: CRUD completo del dueño
create policy "medicines_select_own" on public.medicines
  for select using (auth.uid() = user_id);
create policy "medicines_insert_own" on public.medicines
  for insert with check (auth.uid() = user_id);
create policy "medicines_update_own" on public.medicines
  for update using (auth.uid() = user_id);
create policy "medicines_delete_own" on public.medicines
  for delete using (auth.uid() = user_id);

-- prescriptions: el dueño lee y borra; la inserción del análisis
-- la hace ai-engine (service_role), pero permitimos insert propio
-- para subir la foto antes del análisis.
create policy "prescriptions_select_own" on public.prescriptions
  for select using (auth.uid() = user_id);
create policy "prescriptions_insert_own" on public.prescriptions
  for insert with check (auth.uid() = user_id);
create policy "prescriptions_delete_own" on public.prescriptions
  for delete using (auth.uid() = user_id);

-- token_usage: solo lectura propia; inserta ai-engine (service_role)
create policy "token_usage_select_own" on public.token_usage
  for select using (auth.uid() = user_id);

-- discount_codes: NADIE lee desde el cliente. La validación pasa
-- por discount-code-api (service_role). Sin políticas = sin acceso.

-- whatsapp_messages: solo lectura propia; inserta notif-api
create policy "whatsapp_select_own" on public.whatsapp_messages
  for select using (auth.uid() = user_id);

-- payment_transactions: solo lectura propia; escribe payments-api
create policy "payments_select_own" on public.payment_transactions
  for select using (auth.uid() = user_id);

-- device_tokens: el dueño registra y borra sus dispositivos
create policy "device_tokens_all_own" on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ------------------------------------------------------------
-- Storage: cada usuario solo accede a su carpeta {user_id}/...
-- ------------------------------------------------------------
create policy "prescriptions_storage_rw" on storage.objects
  for all
  using (
    bucket_id = 'prescriptions'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'prescriptions'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "medicine_photos_storage_rw" on storage.objects
  for all
  using (
    bucket_id = 'medicine-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'medicine-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
