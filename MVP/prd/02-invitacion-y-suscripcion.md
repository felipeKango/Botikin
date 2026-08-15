# PRD — Invitación y suscripción

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** el link de recomendación, el pago mensual con tarjeta vía Flow y
el estado de la cuenta — NO hay plan gratis, NO hay prueba sin pago, NO hay
compra dentro del chat

---

## 1 · RESUMEN

**Hoy:** cualquiera baja la app, nadie la usa, y el que la usaría no la
encuentra.

**Después:** se entra solo por el link que te pasó alguien que ya lo usa, y
se entra pagando.

---

## 2 · LA HISTORIA

**ANTES**
Botikin era gratis para probar. Miles de cuentas creadas, cientos de
botiquines vacíos, y el costo de cada mensaje de WhatsApp corriendo por
cuenta nuestra para gente que nunca iba a pagar. La conversión era un
misterio y el canal, un gasto. **Regalamos justo la parte que cuesta plata.**

**DESPUÉS**
La amiga de Carmen le manda un link: *"esto me salvó con los remedios de mi
mamá"*. Carmen entra, ve una página de una pantalla, pone su tarjeta y su
número. Al segundo le llega el primer WhatsApp: *"Hola Carmen, soy el Doctor
Botikin. Vamos a armar el botiquín de tu casa —¿quiénes viven contigo?"*
**Pagó antes de escribir la primera palabra, y por eso escribe.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — se entra únicamente por un link de invitación válido
- **O2** — del link al primer mensaje del agente: menos de dos minutos
- **O3** — el cobro es mensual, con tarjeta, y se renueva solo
- **O4** — quien invita sabe cuántos entraron por su link
- **O5** — si el cobro falla, el agente lo dice por WhatsApp y da el link
  para arreglarlo, sin cortar de golpe
- **O6** — la cuenta queda amarrada al número de WhatsApp que se registró

- **NO1** — no hay plan gratis ni versión de prueba
- **NO2** — no hay descarga, no hay contraseña, no hay app
- **NO3** — no se cobra dentro de la conversación: el pago vive en el link
- **NO4** — no guardamos datos de la tarjeta: los guarda la pasarela

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                        DESPUÉS

buscar en la App Store     alguien te pasa su link
  └─ descargar               └─ página de una pantalla
       └─ crear cuenta            └─ ingresas número + tarjeta
            └─ plan gratis             └─ Flow cobra el primer mes
                 └─ paywall                 └─ suscripción activa
                      └─ abandono                └─ el agente escribe primero
                                                      └─ empieza a conocer la casa

                           CADA MES
                             Flow cobra solo
                               ├─ ok     → sigue todo igual
                               └─ falla  → 3 reintentos en 7 días
                                    └─ el agente avisa por WhatsApp
                                         └─ si no se arregla: cuenta en pausa
```

**El plan (único):** **$3.990 CLP/mes**, todo incluido, por invitación.

**En pausa** significa: el agente responde, pero solo para decir que la cuenta
está suspendida y cómo reactivarla. **Los datos no se borran y los avisos
proactivos se detienen.**

---

## 5 · LOS DATOS

**invitación**
| campo | qué es |
|---|---|
| código | el trozo único que va en el link |
| quién invita | el hogar que la generó (o el equipo, para campañas) |
| usos máximos / usos actuales | el cupo |
| activa | el interruptor |
| expira | fecha tope, opcional |

**hogar** — la cuenta
| campo | qué es |
|---|---|
| teléfono | **la identidad**, en formato internacional, único |
| nombre del titular | para saludarlo |
| invitación de origen | por dónde entró |
| creado | cuándo |

**suscripción**
| campo | qué es |
|---|---|
| estado | `activa` \| `morosa` \| `en pausa` \| `cancelada` |
| identificador en la pasarela | la llave del cruce con Flow |
| próximo cobro | fecha |
| último cobro correcto | fecha |
| intentos fallidos | 0 a 3 |

**El candado del teléfono:** un número pertenece a un solo hogar. Si un
número ya registrado intenta suscribirse de nuevo, no se crea una cuenta
nueva: se reactiva la que existe.

**El candado del cobro:** el estado de la suscripción **solo lo escribe el
backend**, y solo desde el webhook firmado de la pasarela. Nunca desde la
conversación.

**Lo que no guardamos:** número de tarjeta, CVV, ni nada equivalente. Solo el
identificador que nos devuelve Flow.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO alguien abre un link de invitación

  ¿el código existe, está activo, no expiró y le queda cupo?
     → si falla cualquiera, mostramos una página que lo explica
        y ofrece dejar el correo para la lista de espera

  ENTONCES mostramos la página de suscripción con el precio del plan.


CUANDO envía número y tarjeta

  ¿el número ya tiene hogar?
     → sí y está activo : le decimos que su cuenta ya existe
     → sí y está en pausa: reactivamos esa, no creamos otra
     → no                : creamos el hogar

  le pedimos el cobro a Flow

  ENTONCES esperamos la confirmación de la pasarela — nunca activamos
           por lo que diga el navegador del usuario.


CUANDO la pasarela confirma un cobro

  ¿la firma del aviso es válida?   → si no, lo botamos
  ¿ya procesamos ese cobro?        → si sí, no hacemos nada

  ¿el cobro salió bien?
     → sí: suscripción activa, consumimos un uso de la invitación,
           corremos el próximo cobro un mes, y
           EL AGENTE ESCRIBE PRIMERO para empezar a conocer la casa
     → no: sumamos un intento fallido
              ├─ 1 y 2: el agente avisa y Flow reintenta
              └─ 3    : cuenta en pausa, se detienen los avisos


CUANDO el usuario pide cancelar

  cortamos la renovación en la pasarela
  la cuenta sigue activa hasta la fecha ya pagada

  ENTONCES le confirmamos hasta cuándo tiene servicio, sin retenerlo
           con preguntas.
```

**Promesas:**
- nadie entra sin invitación y sin pagar
- una cuenta = un número de WhatsApp
- el mismo cobro nunca se procesa dos veces
- cancelar toma un mensaje, no una llamada
- si la cuenta se pausa, los datos de la familia se quedan donde están
