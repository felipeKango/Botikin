# Correo

Trabajo previo (códigos `ABCD-EFGH`, emisor Resend, plantilla) que **todavía
no está conectado al agente**. Ver el conflicto de diseño abajo antes de
enchufarlo.

| archivo | qué es |
|---|---|
| `botikin-access-codes.sql` | tabla `access_codes` + emisión + canje |
| `botikin-send-welcome.ts` | Edge Function que emite y manda por Resend |
| `botikin-welcome-email.html` | la plantilla (variables `{{CODIGO}}`, `{{EMAIL}}`…) |
| `botikin-welcome-email-preview.html` | previsualización |
| `botikin-logo-320.png` | logo para el correo |

## Remitente

`Botikin <soporte@botikin.app>` — corregido desde `hola@botikin.cl`, que era
un dominio no registrado (sin A, sin NS, sin MX).

## DNS en GoDaddy para verificar el dominio en Resend

Resend pone sus registros en el subdominio `send.`, así que **el correo actual
de `botikin.app` en GoDaddy no se toca**: su MX y su SPF de raíz siguen igual.

| tipo | nombre | valor |
|---|---|---|
| MX | `send` | `feedback-smtp.<región>.amazonses.com` · prioridad 10 |
| TXT | `send` | `v=spf1 include:amazonses.com ~all` |
| TXT | `resend._domainkey` | `p=…` (único por cuenta) |

Los valores exactos los da Resend al agregar el dominio. **Al pegarlos en
GoDaddy, omite el dominio en el nombre**: `send`, no `send.botikin.app` —
GoDaddy lo completa solo, y ponerlo entero crea `send.botikin.app.botikin.app`.

## El conflicto que falta resolver

Este sistema fue diseñado para un producto con **sesión web**:

- `redeem_access_code()` exige `auth.uid()` — un usuario logueado
- el correo enlaza a `/activar?code=…`, una página que no existe
- el código se valida contra el **correo**

El producto es WhatsApp: no hay sesión, no hay clave, y lo que hay que
demostrar es **el teléfono**, no el correo. Por eso existe en paralelo
`activaciones` + `canjear_activacion()`, que sí crea el hogar con el número
desde el que llegó el mensaje.

**Dos tablas de códigos son dos verdades sobre lo mismo.** Hay que unificar:
la recomendación es quedarse con `access_codes` (mejor generador —
`gen_random_bytes` sin sesgo de módulo— y emisión idempotente por correo) y
reemplazar solo el canje por el que crea el hogar desde WhatsApp.
