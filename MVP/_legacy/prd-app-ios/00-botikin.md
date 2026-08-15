# PRD — Botikin (producto)

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Alcance:** app iOS + backend del MVP — NO toca dashboard admin web, NO toca
renovación automática de tarjeta, NO toca Android

---

## 1 · RESUMEN

**Hoy:** el botiquín de la casa es una caja de zapatos. Nadie sabe qué hay,
qué venció, ni qué recetó el doctor hace tres semanas.

**Después:** el botiquín vive en el teléfono, la receta se lee con una foto,
y a la abuela le llega un WhatsApp que le recuerda su remedio.

---

## 2 · LA HISTORIA

**ANTES**
A Carmen le recetaron tres remedios para su mamá. Guardó la receta en la
cartera, compró dos y el tercero se le olvidó. Un mes después abre el cajón
del baño y encuentra cuatro cajas del mismo antibiótico —dos vencidas— y
ninguna del remedio que sí necesitaba. **Nadie le avisó nada.** Vuelve a la
farmacia a comprar lo que ya tenía y a botar lo que ya no sirve.

**DESPUÉS**
Carmen le saca una foto a la receta en la puerta de la consulta. En diez
segundos la app le muestra los tres remedios, con dosis y posología, y le
marca cuál **ya lo tienes** y cuál **hay que comprar**. Esa noche agrega las
cajas del cajón. El martes siguiente le llega una alerta: *dos remedios
vencen esta semana*. Y a su mamá le llega un WhatsApp a las 8 de la mañana
recordándole el Omeprazol. **Carmen deja de ser la única memoria de la casa.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — una foto de receta se convierte en una lista legible de
  medicamentos en menos de 15 segundos
- **O2** — el usuario siempre sabe qué venció y qué está por vencer, sin
  abrir la app
- **O3** — la IA nunca se ejecuta sin saldo: cada acción se cobra ANTES de
  llamar a Claude
- **O4** — el usuario puede pagar y quedar activo en el mismo minuto
- **O5** — ninguna llave de proveedor vive dentro de la app

- **NO1** — no damos diagnósticos ni reemplazamos al médico
- **NO2** — no vendemos ni intermediamos la compra de remedios
- **NO3** — no compartimos el botiquín entre cuentas (una cuenta = un hogar)
- **NO4** — no guardamos la tarjeta ni renovamos solos (MVP)

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                          DESPUÉS

receta de papel  ─► cartera   receta de papel ─► foto ─► lectura por IA
                                                  └─ cruce con el botiquín
                                                       └─ "ya lo tienes" / "comprar"

caja de remedios ─► cajón     caja de remedios ─► ficha con fecha
                                                  └─ semáforo de vencimiento
                                                       └─ alerta diaria
                                                            ├─ push al dueño
                                                            └─ WhatsApp a la familia

pagar la IA      ─► (nada)    cada acción de IA ─► portero de tokens
                                                  ├─ hay saldo → Claude
                                                  └─ no hay    → paywall
```

---

## 5 · LOS DATOS

| entidad | para qué existe |
|---|---|
| **usuario** | quién es, y su teléfono para WhatsApp |
| **suscripción** | el plan, el saldo de tokens y cuándo se renueva |
| **remedio** | una caja del botiquín, con su fecha de vencimiento |
| **receta** | la foto + lo que la IA leyó de ella |
| **consumo de tokens** | una fila por cada acción de IA cobrada |
| **código de descuento** | campañas e influencers |
| **mensaje WhatsApp** | qué se mandó, a quién y si llegó |
| **transacción de pago** | auditoría de cada intento de cobro |
| **dispositivo** | dónde mandar el push |

**El candado transversal:** el saldo y el plan **solo los escribe el
backend**. El cliente puede leerlos; jamás tocarlos. Un usuario que edite la
app no puede regalarse tokens.

**El interruptor por usuario:** `plan` — `gratis` | `básico` | `pro`.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO el usuario pide cualquier cosa a la IA

  ¿tiene sesión válida?           → si no, no hacemos nada
  ¿su suscripción está activa?    → si no, mostramos el paywall
  ¿le alcanza el saldo?           → si no, mostramos el paywall

  ENTONCES le descontamos primero, llamamos a la IA después,
           y si la IA falla le devolvemos lo descontado.
```

**Promesas del producto:**
- el costo de cada acción se muestra antes de gastarlo
- quedarse sin saldo nunca es un error: es una invitación a mejorar el plan
- una alerta de vencimiento sale igual aunque no queden tokens
- las fotos de recetas son privadas por usuario, sin excepción

---

## PRDs HIJOS

Este documento no implementa nada por sí solo. Cada pieza cuenta su propia
historia:

| # | PRD | qué resuelve |
|---|---|---|
| 01 | [Cuenta y sesión](01-cuenta-y-sesion.md) | entrar, y nacer con saldo |
| 02 | [Mi Botiquín](02-mi-botiquin.md) | el inventario y su semáforo |
| 03 | [Escanear receta](03-escanear-receta.md) | la foto que se vuelve lista |
| 04 | [El portero de tokens](04-portero-de-tokens.md) | la regla dura del negocio |
| 05 | [Planes y pago](05-planes-y-pago.md) | WebPay y códigos de descuento |
| 06 | [Recordatorios por WhatsApp](06-whatsapp.md) | el mensaje a la familia |
| 07 | [Alerta diaria de vencimientos](07-alerta-diaria.md) | el aviso sin abrir la app |

**Orden de construcción:** 01 → 04 → 02 → 03 → 05 → 06 → 07.
El portero (04) va segundo a propósito: todo lo demás lo asume existiendo.
