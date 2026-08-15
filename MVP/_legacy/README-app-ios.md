# Botikin — MVP iOS

La primera app chilena que usa IA para gestionar el botiquín familiar, leer
recetas médicas y enviar recordatorios por WhatsApp. Producto de
[Kango](https://getkango.com) (Health-Tech, Santiago de Chile).

## Arquitectura

```
┌─────────────┐   JWT    ┌──────────────────────────────┐
│  App iOS    │ ───────► │  Supabase Edge Functions     │
│  SwiftUI    │          │  auth-api · ai-engine        │──► Anthropic Claude
│  MVVM       │          │  payments-api · notif-api    │──► Transbank WebPay
│  BotikinKit │          │  discount-code-api           │──► Twilio WhatsApp
└─────────────┘          │  expiry-scheduler (cron)     │──► APNs
       │                 └──────────────┬───────────────┘
       │  PostgREST + Storage (RLS)     │ service_role
       └────────────► PostgreSQL ◄──────┘
```

- **App iOS**: Swift 6 + SwiftUI + MVVM + async/await, iOS 17+. Sin SDKs de
  terceros: URLSession directo contra Supabase.
- **BotikinKit**: Swift Package con la lógica de negocio pura (portero de
  tokens, códigos de descuento, estados de vencimiento) y sus tests.
- **Backend**: Supabase (Auth, PostgreSQL con RLS, Storage, Edge Functions).
- **IA**: Claude vía Edge Functions — `claude-opus-4-6` (texto) y
  `claude-sonnet-4-6` (visión). **La API key jamás vive en la app.**
- **Regla de oro (el "portero")**: toda acción de IA verifica y descuenta
  tokens ANTES de llamar a Claude (RPC atómico `consume_tokens`). Sin saldo
  → HTTP 402 + invitación a mejorar el plan.

## Estructura del repo

```
assets/                  logo + capturas de referencia de diseño
supabase/
  migrations/            schema, RLS y funciones de negocio (SQL)
  functions/             Edge Functions (Deno/TypeScript)
  seed.sql               códigos de descuento demo
ios/
  project.yml            definición XcodeGen
  Botikin/               app SwiftUI (8 módulos)
  BotikinKit/            lógica de negocio + tests unitarios
```

## Setup

### 1. Supabase

```bash
brew install supabase/tap/supabase
supabase login

# Crea el proyecto en https://supabase.com/dashboard y vincúlalo:
supabase link --project-ref TU_PROJECT_REF

# Aplica schema + RLS + funciones de negocio:
supabase db push

# (Opcional, solo dev) datos demo:
supabase db execute --file supabase/seed.sql
```

> Local: `supabase start` levanta todo con Docker y aplica las migraciones.

### 2. Secrets de las Edge Functions

```bash
supabase secrets set \
  ANTHROPIC_API_KEY=sk-ant-... \
  TWILIO_ACCOUNT_SID=AC... \
  TWILIO_AUTH_TOKEN=... \
  TWILIO_WHATSAPP_FROM=whatsapp:+14155238886 \
  TBK_ENVIRONMENT=integration \
  TBK_COMMERCE_CODE=597055555532 \
  TBK_API_KEY=579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C \
  APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=app.botikin.ios \
  APNS_ENVIRONMENT=sandbox \
  ADMIN_EMAILS=felipe@getkango.com
# APNS_PRIVATE_KEY: contenido del .p8 (usa un archivo .env para el multilinea)
```

- **Transbank**: los valores de arriba son las credenciales públicas de
  integración de WebPay Plus. Tarjeta de prueba VISA `4051 8856 0044 6623`,
  CVV `123`, cualquier fecha; RUT `11.111.111-1`, clave `123`.
- **Twilio**: en desarrollo usa el sandbox de WhatsApp (el número de arriba)
  y une tu teléfono con el código que te da la consola de Twilio.

### 3. Deploy de las funciones

```bash
supabase functions deploy auth-api ai-engine payments-api notif-api \
  discount-code-api admin-dashboard-api expiry-scheduler
```

### 4. Cron diario de vencimientos

El cron (pg_cron, 12:00 UTC = 08:00 Chile) llama a `expiry-scheduler`. Tras
el deploy, registra la URL y el service key en la tabla de config privada:

```sql
insert into private.app_config (key, value) values
  ('edge_functions_url', 'https://TU_PROJECT_REF.supabase.co/functions/v1'),
  ('service_role_key', 'TU_SERVICE_ROLE_KEY')
on conflict (key) do update set value = excluded.value;
```

### 5. App iOS

```bash
brew install xcodegen
cd ios
cp Botikin/Resources/Secrets.example.plist Botikin/Resources/Secrets.plist
# Edita Secrets.plist: SUPABASE_URL + SUPABASE_ANON_KEY (Dashboard → Settings → API)
xcodegen generate
open Botikin.xcodeproj
```

Selecciona un simulador iPhone y ⌘R. La app corre completa en simulador
(la cámara cae a galería automáticamente).

### 6. Tests unitarios

Cubren el descuento de tokens, la validación de códigos de descuento y el
cálculo de estados de vencimiento (vencido / vence en Xd / vigente):

```bash
# Con Xcode instalado:
cd ios/BotikinKit && swift test
# o ⌘U en Xcode con el scheme Botikin.
```

> Nota: `swift test` requiere Xcode (XCTest no viene con los Command Line
> Tools solos).

## Flujo demo del MVP

1. **Registro** → crea perfil + suscripción Gratis con 500 tokens
   (trigger `handle_new_user`).
2. **Agregar remedios** en Mi Botiquín (CRUD, filtros, banner de vencidos).
3. **Escanear receta** (tab Receta): foto → Storage → Claude Vision → tarjeta
   con médico, fecha y medicamentos, cruzados contra tu botiquín
   (✓ ya lo tienes / Comprar).
4. **Ver el descuento de tokens** en el pill "⚡" y en Mis Tokens.
5. **Quedarse sin tokens** → la acción se bloquea con 402 y la app abre la
   pantalla de planes (el paywall).
6. **Suscribirse con WebPay** (modo integración) o canjear un código de
   descuento (`KANGO2026` en el seed) → tokens del plan asignados.
7. **WhatsApp de prueba**: registra tu teléfono en Mi cuenta (perfil) y envía
   un recordatorio; Claude redacta el texto y Twilio lo entrega.

## Seguridad

- **RLS en todas las tablas**: cada usuario solo ve sus filas
  (`auth.uid() = user_id`). `discount_codes` no tiene políticas de lectura:
  el cliente solo puede validar vía `discount-code-api`.
- **Storage privado** con carpetas por usuario (`{user_id}/...`).
- **subscriptions y token_usage solo se escriben desde el backend**
  (service_role); el cliente no puede regalarse tokens.
- **Ninguna API key** de Anthropic/Twilio/Transbank/APNs en el binario:
  todas viven en secrets de Edge Functions. La app solo conoce la URL del
  proyecto y el anon key público.

## Planes

| Plan | Precio | Tokens/mes | WhatsApp |
|------|--------|-----------|----------|
| Gratis | $0 | 500 (~5 análisis) | — |
| Básico | $4.990 CLP | 5.000 (~50 análisis) | Usuario principal |
| Pro | $9.990 CLP | Ilimitados | Toda la familia |

Costo por acción (mostrado siempre en la app): receta ~1.000 · botiquín
~400 · WhatsApp ~300 · chat ~200 tokens.

## Post-MVP (no incluido a propósito)

- Dashboard admin Next.js (los endpoints ya existen en
  `admin-dashboard-api`).
- Estados de entrega de Twilio vía webhook (hoy queda en "Enviado").
- Renovación automática de suscripciones de pago (WebPay Plus no guarda la
  tarjeta; requiere OneClick).
