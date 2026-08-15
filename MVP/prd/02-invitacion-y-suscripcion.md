# PRD — Invitación y suscripción

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** el link de recomendación, el pago mensual con tarjeta vía Flow,
el código de activación por correo y el estado de la cuenta — NO hay plan
gratis, NO hay prueba sin pago, NO hay compra dentro del chat

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
- **O6** — la cuenta queda amarrada al número de WhatsApp **demostrado**, no
  al que alguien escribió en un formulario

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
       └─ crear cuenta            └─ ingresas CORREO + tarjeta
            └─ plan gratis             └─ (URL propia de Flow por persona)
            └─ plan gratis             └─ Flow cobra el primer mes
                 └─ paywall                 └─ te llega un código al correo
                      └─ abandono                 └─ se lo escribes al agente
                                                       └─ nace tu hogar
                                                            └─ empieza a conocer la casa

                           CADA MES
                             Flow cobra solo
                               ├─ ok     → sigue todo igual
                               └─ falla  → 3 reintentos en 7 días
                                    └─ el agente avisa por WhatsApp
                                         └─ si no se arregla: cuenta en pausa
```

**El plan (único):** **$3.990 CLP/mes**, todo incluido, por invitación.

### El link de pago tiene que ser reutilizable

Un *link de pago* de Flow (`flow.cl/uri/…`) apunta a **una transacción**, no a
un producto. Redirige siempre al mismo token, así que **lo cobra una persona y
después muere**: el segundo que entra ve *"Ya existe un pago para la
transacción N° …"*.

Sirve para cobrarle a alguien puntual, no para vender una suscripción.

Lo que este producto necesita es **Flow Suscripciones**, que además resuelve
el cobro mensual — un pago único tampoco se renueva solo. La integración es
por API, en cuatro pasos:

```
plans/create        una vez: el plan de $3.990/mes
customer/create     por cada persona que se suscribe
customer/register   inscribe su tarjeta (Flow le muestra el formulario)
subscription/create la amarra al plan y empieza a cobrar todos los meses
```

Cada suscriptor recibe su propia URL de registro de tarjeta, así que nunca
hay un link compartido que se pueda consumir.

### Por qué el código, y no el teléfono en el formulario

El diseño anterior creaba el hogar con el número que la persona escribía al
pagar. Ese supuesto se rompió en la primera prueba real: el teléfono que
teníamos anotado no era el WhatsApp desde el que efectivamente se escribe.
Un hogar montado sobre un número equivocado es un hogar al que su dueño no
puede entrar, y no hay forma de que el agente se dé cuenta.

**El código invierte la prueba.** Llega al correo de quien pagó y solo sirve
escribiéndolo *por WhatsApp*. El número deja de ser un dato declarado y pasa
a ser un hecho: quedó demostrado por el acto de escribir desde él.

De paso, el formulario de pago se simplifica — ya no pide teléfono, solo
correo y tarjeta.

**Seis caracteres, alfabeto sin ambigüedades.** Se dictan por teléfono y se
escriben a mano, así que fuera `0`/`O`, `1`/`I`/`L` y `5`/`S`. Se acepta en
minúscula, con espacios o con guiones: `bpk-tqx` es `BPKTQX`.

**El candado:** cinco intentos fallidos por hora y por teléfono. Sin eso, seis
caracteres son adivinables a fuerza bruta desde WhatsApp.

**En pausa** significa: el agente responde, pero solo para decir que la cuenta
está suspendida y cómo reactivarla. **Los datos no se borran y los avisos
proactivos se detienen.**

---

## 5 · LOS DATOS

**activación** — el puente entre el pago y el WhatsApp
| campo | qué es |
|---|---|
| código | 6 caracteres, único, del alfabeto sin ambigüedades |
| correo | a quién se le mandó |
| identificadores de Flow | el cobro que lo originó |
| estado | `pendiente` \| `usada` \| `expirada` |
| expira | 30 días |
| hogar | se llena al canjearse |

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


CUANDO envía correo y tarjeta

  le pedimos el cobro a Flow

  ENTONCES esperamos la confirmación de la pasarela — nunca activamos
           por lo que diga el navegador del usuario.


CUANDO la pasarela confirma un cobro

  ¿la firma del aviso es válida?   → si no, lo botamos
  ¿ya procesamos ese cobro?        → si sí, no hacemos nada

  ¿el cobro salió bien?
     → sí: generamos un código de activación
           y se lo mandamos al correo con que pagó
     → no: sumamos un intento fallido
              ├─ 1 y 2: el agente avisa y Flow reintenta
              └─ 3    : cuenta en pausa, se detienen los avisos


CUANDO un número desconocido le escribe al agente

  ¿el mensaje es un código de 6 caracteres del alfabeto?
     → no: lo saludamos y le damos el link de pago. Nada más:
           sin cuenta no hay conversación.
     → sí: intentamos canjearlo

  el canje es atómico y NO pasa por el modelo — toca dinero:
     ¿lleva 5 fallos en la última hora?  → esperamos una hora
     ¿este número ya es un hogar?        → no necesita código
     ¿el código existe?                  → si no, sumamos un fallo
     ¿ya se usó? ¿venció?                → se lo explicamos y qué hacer

  ENTONCES nace el hogar con ESTE teléfono, la suscripción queda activa,
           se consume el uso de la invitación, y el agente saluda y
           pregunta quiénes viven en la casa.


CUANDO el usuario pide cancelar

  cortamos la renovación en la pasarela
  la cuenta sigue activa hasta la fecha ya pagada

  ENTONCES le confirmamos hasta cuándo tiene servicio, sin retenerlo
           con preguntas.
```

**Promesas:**
- nadie entra sin invitación y sin pagar
- una cuenta = un número de WhatsApp **demostrado**
- un código se canjea una sola vez, desde un solo teléfono
- cada rechazo dice por qué y qué hacer, nunca "código inválido" a secas
- el mismo cobro nunca se procesa dos veces
- cancelar toma un mensaje, no una llamada
- si la cuenta se pausa, los datos de la familia se quedan donde están
