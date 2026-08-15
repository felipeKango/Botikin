# PRD — El portero de tokens

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** la regla que gobierna TODA acción de IA del producto — NO toca
el cobro de dinero (ver [05](05-planes-y-pago.md)), NO toca qué hace cada
acción de IA por dentro

> Este es el PRD más importante del producto. Los demás lo asumen existiendo.

---

## 1 · RESUMEN

**Hoy:** cada llamada a la IA es plata que se va sin que nadie la cuente.

**Después:** ninguna acción de IA ocurre sin haberse cobrado primero, y el
usuario siempre supo cuánto costaba.

---

## 2 · LA HISTORIA

**ANTES**
Carmen escanea catorce recetas viejas de una sentada, un domingo. La cuenta
del proveedor de IA sube. Carmen no pagó nada, no sabía que estaba gastando
algo, y nosotros no sabemos cuánto nos costó ella hasta que llega la
factura. **El producto no tiene freno.**

**DESPUÉS**
Carmen ve un rayo con **500** desde el primer día. Cada acción dice lo que
cuesta antes de tocarla: *receta ~1.000*. Al segundo escaneo el rayo llega a
cero y la app no le muestra un error rojo: le muestra los planes, con el
número exacto de análisis que trae cada uno. **Carmen entiende el trato, y
nosotros entendemos nuestro costo.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — se descuenta ANTES de llamar a la IA, nunca después
- **O2** — el descuento es atómico: dos toques simultáneos no gastan el
  mismo saldo dos veces
- **O3** — si la IA falla, se devuelve lo cobrado
- **O4** — el cliente no puede descontarse ni regalarse saldo: solo el
  backend escribe
- **O5** — quedarse sin saldo no es un error, es la puerta al paywall
- **O6** — el plan pro no descuenta, **pero igual registra el consumo**

- **NO1** — no cobramos por acciones que no llegan a la IA (botiquín vacío,
  campo faltante)
- **NO2** — no cobramos el costo real variable: el precio por acción es fijo
  y predecible
- **NO3** — no bloqueamos las alertas de vencimiento por falta de saldo
  (ver [07](07-alerta-diaria.md))

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                      DESPUÉS

acción ─► IA ─► resultado    acción ─► ¿sesión válida?       → no: fuera
        (sin control)                └─ ¿suscripción activa? → no: paywall
                                          └─ ¿alcanza el saldo?  → no: paywall
                                               └─ DESCUENTA + registra
                                                    └─ llama a la IA
                                                         ├─ ok    → resultado + saldo nuevo
                                                         └─ falla → devuelve el saldo
```

**Precios fijos por acción** (los mismos que muestra la app):

| acción | costo |
|---|---|
| analizar receta | 1.000 |
| analizar botiquín | 400 |
| redactar WhatsApp | 300 |
| chat asistente | 200 |

**Lo que trae cada plan:**

| plan | saldo mensual | equivale a |
|---|---|---|
| gratis | 500 | ~5 análisis de botiquín |
| básico | 5.000 | ~5 recetas + extras |
| pro | ilimitado | sin tope |

---

## 5 · LOS DATOS

**suscripción** — la tabla del negocio
| campo | qué es |
|---|---|
| plan | el interruptor: `gratis` \| `básico` \| `pro` |
| estado | `activa` \| `morosa` \| `cancelada` |
| saldo total | cuánto trae el ciclo — **ilimitado se marca con −1** |
| saldo usado | cuánto lleva gastado este ciclo |
| renovación | cuándo empieza el ciclo siguiente |

**consumo de tokens** — una fila por cobro
| campo | qué es |
|---|---|
| tipo de acción | receta \| botiquín \| whatsapp \| chat |
| cantidad | lo cobrado |
| cuándo | para el gráfico de Mis Tokens |

**El candado de concurrencia:** al cobrar se toma la fila de la suscripción
en exclusiva hasta terminar. Dos peticiones a la vez se ordenan; ninguna
lee un saldo viejo.

**El candado de escritura:** saldo y plan solo se escriben desde el backend
con privilegio de servicio. La sesión del usuario **no tiene permiso** para
ejecutar el cobro ni para editar la suscripción.

**La renovación perezosa:** si el ciclo del plan gratis venció, el primer
cobro del mes lo resetea antes de decidir. No hay un proceso nocturno que
mantenga los saldos al día.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO se pide cobrar N tokens por una acción

  ¿N es mayor que cero?              → si no, error de programación
  tomamos la suscripción en exclusiva
  ¿existe?                           → si no, la cuenta está rota
  ¿está activa?                      → si no, paywall

  ¿venció el ciclo y el plan es gratis?
      → sí: dejamos el usado en cero y corremos la renovación un mes

  ¿el plan es ilimitado?
      → sí: NO descontamos, pero registramos el consumo
      → no: ¿usado + N cabe en el total?
               → no: paywall, y la IA nunca se llama
               → sí: sumamos N al usado

  ENTONCES registramos el consumo y devolvemos el saldo restante
           (ilimitado se devuelve como −1).


CUANDO la IA falla después de haber cobrado

  devolvemos N al saldo (nunca bajo cero)
  borramos el registro de consumo

  ENTONCES le decimos al usuario que no se le descontó nada.
```

**Promesas:**
- el precio se muestra antes de gastarse
- nunca se llama a la IA sin haber cobrado
- nunca se cobra sin haber llamado a la IA (o se devuelve)
- sin saldo → **402 + invitación a mejorar el plan**, jamás un error técnico
- el usuario nunca puede escribir su propio saldo
