# PRD — Planes y pago

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** paywall, pago con WebPay y canje de códigos de descuento — NO
toca renovación automática (WebPay Plus no guarda la tarjeta; eso es
OneClick, post-MVP), NO toca facturación ni boletas

---

## 1 · RESUMEN

**Hoy:** no hay forma de pagar; la IA se regala hasta que duele.

**Después:** el usuario se queda sin saldo, ve los planes, paga con su
tarjeta chilena y vuelve a la acción que estaba haciendo — con saldo nuevo.

---

## 2 · LA HISTORIA

**ANTES**
A Carmen se le acaba el saldo justo cuando iba a escanear la receta de su
mamá. La app le muestra *Error 402*. Carmen no sabe qué es 402. Cierra la
app y no vuelve. **Perdimos a la usuaria en el minuto exacto en que quería
pagarnos.**

**DESPUÉS**
A Carmen se le acaba el saldo. La app le muestra tres planes con lo que trae
cada uno en análisis reales, no en números raros. Toca *Básico*, paga con su
Redcompra en la ventana de siempre, y vuelve a la app con **5.000** en el
rayo. Escanea la receta. **Todo el desvío duró noventa segundos.**

Y cuando su amiga le pasa el código que dio una influencer, lo escribe en la
misma pantalla y se lleva un mes sin pagar.

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — el paywall aparece exactamente donde se acabó el saldo, no en un
  menú escondido
- **O2** — cada plan se explica en análisis, no en tokens
- **O3** — del pago autorizado al saldo nuevo: mismo minuto, sin cerrar la
  app
- **O4** — un código de descuento activa el plan **sin pasar por la tarjeta**
- **O5** — todo intento de cobro queda auditado, haya resultado o no

- **NO1** — no guardamos la tarjeta ni cobramos solos el mes siguiente
- **NO2** — no hay prorrateo ni cambio de plan a mitad de ciclo
- **NO3** — no devolvemos dinero desde la app

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                    DESPUÉS

sin saldo ─► error     sin saldo ─► paywall con los tres planes
                                     │
                                     ├─ camino tarjeta
                                     │   elegir plan ─► se crea la orden
                                     │        └─ se abre WebPay
                                     │             └─ el usuario paga
                                     │                  └─ vuelve a la app
                                     │                       └─ confirmamos con Transbank
                                     │                            ├─ autorizada → plan activo
                                     │                            └─ rechazada  → sin cambios
                                     │
                                     └─ camino código
                                         escribir código ─► validar
                                              └─ consumir un uso
                                                   └─ plan activo por N meses
```

**Precios:** gratis $0 · básico $4.990 CLP · pro $9.990 CLP (mensual).

---

## 5 · LOS DATOS

**transacción de pago** — la auditoría
| campo | qué es |
|---|---|
| orden de compra | única, es la llave del cruce con Transbank |
| plan | qué se estaba comprando |
| monto | en pesos |
| estado | `iniciada` → `autorizada` \| `rechazada` \| `reversada` |

**código de descuento**
| campo | qué es |
|---|---|
| código | único, se compara sin distinguir mayúsculas ni espacios |
| meses gratis | cuánto dura el regalo |
| usos máximos / usos actuales | el cupo de la campaña |
| activo | el interruptor de la campaña |
| expira el | fecha tope, opcional |

**El candado del código:** un mismo usuario no puede canjear dos veces el
mismo código. La suscripción recuerda cuál usó.

**El candado de lectura:** la tabla de códigos **no se puede leer desde el
cliente**. La app nunca sabe qué códigos existen; solo pregunta si uno sirve.

**Activar un plan** siempre hace lo mismo, venga de tarjeta o de código:
pone el plan, deja el estado activo, asigna el saldo del plan, **deja el
usado en cero** y corre la renovación N meses hacia adelante.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO el usuario elige un plan pago

  ¿venía con código?
     → sí: validamos el código
              ¿existe, está activo, no expiró, queda cupo, no lo usó ya?
                 → si falla cualquiera, se lo decimos en su idioma
              consumimos un uso
              activamos el plan por los meses del código
              y NO cobramos nada
     → no: creamos la orden de compra
              abrimos el pago
              esperamos que vuelva


CUANDO el usuario vuelve del pago

  confirmamos con el proveedor usando la orden

  ¿autorizada?
     → sí: marcamos la transacción autorizada
           activamos el plan por 1 mes
           el saldo nuevo aparece en pantalla
     → no: marcamos rechazada y no tocamos la suscripción

  ENTONCES lo devolvemos a la acción que quería hacer.
```

**Promesas:**
- una orden de compra se confirma una sola vez
- un pago rechazado no cambia nada del plan
- un código no se puede gastar dos veces, ni por la misma persona ni de más
- el saldo del plan reemplaza al anterior; no se acumula
