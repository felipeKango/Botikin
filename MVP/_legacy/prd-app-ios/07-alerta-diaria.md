# PRD — Alerta diaria de vencimientos

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** el proceso diario que revisa vencimientos y avisa por push y
WhatsApp — NO toca el semáforo dentro de la app (ver [02](02-mi-botiquin.md)),
NO toca horarios configurables por usuario

---

## 1 · RESUMEN

**Hoy:** los remedios vencen en silencio; nadie abre la app a preguntar.

**Después:** todos los días a las 8 de la mañana, el que tenga algo por
vencer se entera sin hacer nada.

---

## 2 · LA HISTORIA

**ANTES**
Carmen cargó su botiquín completo un domingo de entusiasmo. Después no
volvió a abrir la app en dos meses. En ese tiempo se le vencieron cuatro
cosas, incluida la que su mamá tomaba a diario. **La información estaba
adentro y no sirvió de nada.**

**DESPUÉS**
Un martes a las 8:04 Carmen recibe una notificación: *"Botikin — revisa tu
botiquín: 1 remedio vencido · 2 vencen en menos de 7 días"*. Toca, entra
directo a la lista filtrada, y resuelve las tres cosas antes de salir de la
casa. Su mamá, en paralelo, recibió un WhatsApp con lo suyo.
**La app la buscó a ella.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — corre una vez al día, 08:00 hora de Chile, sin que nadie lo
  gatille
- **O2** — la ventana de aviso es de 7 días hacia adelante, más todo lo ya
  vencido
- **O3** — el push es gratis y le llega a todos, incluido el plan gratis
- **O4** — **la alerta sale igual aunque no queden tokens**: si la IA no se
  puede pagar, sale una plantilla
- **O5** — un usuario sin nada por vencer no recibe nada (no hay ruido)

- **NO1** — no mandamos más de una alerta por usuario por día
- **NO2** — no dejamos elegir el horario en el MVP
- **NO3** — no avisamos por correo

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                   DESPUÉS

(nada pasa solo)      reloj diario 08:00 Chile
                        └─ buscamos TODO lo que vence dentro de 7 días
                             o ya venció
                              └─ agrupamos por usuario
                                   └─ para cada usuario:
                                        ├─ resumen en una frase
                                        │    "1 vencido · 2 vencen en <7 días"
                                        │
                                        ├─ push a todos sus dispositivos  [gratis]
                                        │
                                        └─ ¿plan pago + teléfono?
                                             └─ portero de tokens
                                                  ├─ alcanza → la IA redacta
                                                  └─ no alcanza → plantilla fija
                                                       └─ sale por WhatsApp igual
                                                            └─ queda en el historial
```

---

## 5 · LOS DATOS

**Lo que lee:** remedios de todos los usuarios con vencimiento dentro de la
ventana, agrupados por dueño. Es la misma consulta ordenada por usuario y
fecha que ya sirve a Mi Botiquín.

**dispositivo**
| campo | qué es |
|---|---|
| identificador de envío | dónde llega el push |
| usuario | de quién es el teléfono |

Un usuario puede tener varios dispositivos; el par usuario+dispositivo es
único, así que registrar dos veces no duplica.

**Lo que escribe:** un mensaje en el historial de WhatsApp por cada envío, y
—si cobró— una fila de consumo de tokens.

**El candado:** este proceso solo puede invocarlo el sistema con privilegio
de servicio. Una petición con sesión de usuario se rechaza, aunque sea del
dueño del producto.

**La configuración del reloj** vive en una tabla privada del backend, no en
el código ni en la app.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO son las 08:00 en Chile

  ¿la llamada viene del sistema?  → si no, la rechazamos

  buscamos todo lo que vence dentro de 7 días o ya venció
  ¿hay algo?  → si no, terminamos sin avisar a nadie

  agrupamos por usuario


  PARA CADA usuario con algo por vencer

    armamos el resumen: cuántos vencidos, cuántos por vencer

    le mandamos push a cada dispositivo suyo        ← siempre, gratis

    ¿su plan es pago, está activo y tiene teléfono?
       → no: terminamos con él
       → sí: intentamos cobrar la redacción
                ├─ alcanza  → la IA escribe el aviso
                │              └─ si la IA falla, usamos la plantilla
                └─ no alcanza → usamos la plantilla, sin cobrar

             mandamos el WhatsApp y lo guardamos en el historial


  ENTONCES devolvemos cuántos usuarios avisamos y cuántos remedios revisamos.
```

**Promesas:**
- una alerta de salud **nunca** se pierde por falta de saldo
- quien no tiene nada por vencer no recibe nada
- el push llega a todos los planes, siempre gratis
- si el proceso se cae a la mitad, mañana vuelve a correr completo
