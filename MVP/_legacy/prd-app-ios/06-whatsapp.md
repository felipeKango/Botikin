# PRD — Recordatorios por WhatsApp

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** redactar y enviar un recordatorio a un teléfono — NO toca
conversación de vuelta (nadie responde el WhatsApp), NO toca estados de
entrega finos (post-MVP), NO toca la alerta automática diaria (ver
[07](07-alerta-diaria.md))

---

## 1 · RESUMEN

**Hoy:** el recordatorio del remedio es una hija llamando por teléfono todos
los días.

**Después:** el mensaje lo redacta la IA con el tono de la familia y llega
por WhatsApp, que es donde la abuela sí mira.

---

## 2 · LA HISTORIA

**ANTES**
Carmen le pone alarma en su propio teléfono para acordarse de llamar a su
mamá a las 8 y recordarle el Omeprazol. Algunos días se le pasa por una
reunión. Su mamá no toma el remedio y no se lo dice para no preocuparla.
**El tratamiento depende de que Carmen no esté ocupada.**

**DESPUÉS**
Carmen registra el teléfono de su mamá una vez. Elige el Omeprazol y toca
*Enviar recordatorio*. La IA escribe: *"Hola mamá, recuerda tomar el
Omeprazol 20mg en ayunas esta mañana. ¡Buen día!"* — Carmen lo lee, le
gusta, lo manda. A su mamá le llega un WhatsApp que suena a su hija.
**Nadie tuvo que llamar a nadie.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — el mensaje suena humano y chileno, nunca a robot: máximo dos
  frases
- **O2** — el usuario ve el texto antes de que salga
- **O3** — cada envío queda en un historial con lo que se mandó y a quién
- **O4** — redactar cuesta tokens y pasa por el portero como todo lo demás
- **O5** — WhatsApp es beneficio de plan pago: básico manda al titular, pro
  a toda la familia

- **NO1** — no recibimos respuestas ni sostenemos conversación
- **NO2** — no mandamos nada a un número que el usuario no escribió
- **NO3** — no prometemos entrega: hoy sabemos que salió, no que se leyó

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                     DESPUÉS

llamar por teléfono     registrar teléfono en el perfil (formato +56 9 ...)
todos los días            └─ elegir a quién y sobre qué
                               └─ portero de tokens
                                    └─ la IA redacta el texto
                                         └─ el usuario lo LEE
                                              ├─ lo edita o lo rechaza
                                              └─ lo envía
                                                   └─ sale por WhatsApp
                                                        └─ queda en el historial
```

---

## 5 · LOS DATOS

**usuario** — se agrega el teléfono, en formato internacional. Vacío
mientras no lo registre; sin teléfono, la pantalla invita a ponerlo en vez
de fallar.

**mensaje de WhatsApp** — el historial
| campo | qué es |
|---|---|
| teléfono | a quién se mandó |
| texto | exactamente lo que salió |
| tipo | `alerta de vencimiento` \| `recordatorio` \| `sugerencia de IA` |
| estado de entrega | `enviado` \| `entregado` \| `fallido` |
| identificador del proveedor | para rastrear después |

**El interruptor:** el plan decide si el canal existe.
`gratis` → no disponible · `básico` → solo el titular · `pro` → la familia.

**El candado:** el número de destino sale de datos del usuario, nunca del
cuerpo de una petición cualquiera.

**Deuda conocida:** el estado se queda en `enviado`. Los estados reales del
proveedor son post-MVP y ya hay campo donde ponerlos.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO el usuario pide un recordatorio

  ¿su plan incluye WhatsApp?   → si no, paywall
  ¿tiene teléfono registrado?  → si no, lo mandamos al perfil a ponerlo
  ¿pasa el portero?            → si no, paywall

  ENTONCES la IA redacta el texto con el tono de la casa
           y se lo mostramos ANTES de enviarlo.


CUANDO el usuario confirma el envío

  lo mandamos por WhatsApp
  guardamos el mensaje en el historial con su resultado

  ENTONCES le mostramos el mensaje enviado en su historial, con la hora.
```

**Promesas:**
- ningún mensaje sale sin que el usuario lo haya visto
- un número mal formateado se avisa antes de cobrar tokens
- el texto guardado es el texto que salió, sin reescrituras
- máximo dos frases, en español de Chile, siempre cálido
