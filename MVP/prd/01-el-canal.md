# PRD — El canal

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** cómo entran y salen los mensajes, la ventana de 24 horas, las
plantillas y el reloj — NO toca qué dice el agente (eso es
[`../soul.md`](../soul.md)), NO toca el cobro al usuario

> Este es el PRD más importante del stack. Los demás asumen sus reglas.
> En la versión app, la regla dura era el portero de tokens. Acá es **la
> ventana de 24 horas**: define qué mensajes son posibles y cuáles cuestan.

---

## 1 · RESUMEN

**Hoy:** un producto que quiere avisarte algo tiene que rogarte que abras una
app.

**Después:** el aviso llega al chat que ya tienes abierto — pero solo si
respetamos las reglas de WhatsApp, que no son negociables ni por nosotros ni
por el usuario.

---

## 2 · LA HISTORIA

**ANTES**
Construimos el agente perfecto. El día del lanzamiento intentamos mandar el
primer recordatorio de la mañana y WhatsApp lo rechaza: hace 26 horas que
Carmen no escribe, y fuera de la ventana de servicio solo se puede enviar una
plantilla aprobada. No teníamos ninguna aprobada. **El producto entero era
proactivo y el canal solo nos dejaba responder.**

**DESPUÉS**
Cada aviso que Botikin necesita mandar sin que le hablen primero —el
recordatorio de la toma, el vencimiento a 30 días, el cobro que falló— tiene
su plantilla de utilidad aprobada de antemano. Cuando Carmen responde
*"listo"*, se abre una ventana de 24 horas y todo lo que sigue es
conversación libre y gratis. **El agente sabe en qué modo está antes de
abrir la boca.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — el agente siempre sabe si está dentro o fuera de la ventana de 24 h
- **O2** — todo mensaje proactivo tiene su plantilla de utilidad aprobada
  antes de que exista la funcionalidad que la usa
- **O3** — el agente sabe qué día y hora es en Chile, en cada turno
- **O4** — una foto que llega por WhatsApp queda guardada y disponible para
  la IA en segundos
- **O5** — si el agente se cae, el usuario recibe una respuesta humana, no
  silencio
- **O6** — en desarrollo todo corre en modo simulado, sin gastar mensajes
  reales

- **NO1** — no mandamos plantillas de marketing: solo utilidad y servicio
- **NO2** — no abrimos la ventana artificialmente con mensajes de relleno
- **NO3** — no mandamos más de un mensaje proactivo por bloque de la rutina
  diaria (ver [07](07-vencimientos.md))
- **NO4** — no usamos el canal para nada que no haya pedido el usuario

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                      DESPUÉS

app ─► push ─► usuario   ENTRADA
(y el push se ignora)      usuario escribe ─► Kapso recibe
                                └─ dispara el workflow con el mensaje
                                     └─ identificamos el hogar por el número
                                          └─ cargamos hoy + casa + inventario
                                               └─ el agente responde

                         SALIDA PROACTIVA
                           un proceso decide que hay algo que decir
                             └─ ¿el usuario escribió hace menos de 24 h?
                                  ├─ sí  → mensaje libre        [gratis]
                                  └─ no  → plantilla aprobada   [cuesta]
                                       └─ si contesta, se abre la ventana
                                            └─ el resto es conversación libre
```

### Las piezas de Kapso que usamos

| pieza | para qué |
|---|---|
| **Workflow** | el orquestador de la conversación |
| **Agent Node** | el turno del agente, con sus herramientas |
| **Webhook Node** | llamar a nuestro backend (Supabase) |
| **Function Node** | lógica determinista que no debe quedar en manos del modelo |
| **Wait for Response** | esperar al usuario sin perder el hilo |
| **Handoff Node** | pasarle la conversación a una persona |
| **Templates** | los mensajes proactivos, categoría *utilidad* |
| **Triggers** | por mensaje entrante, por evento y por API |
| **Project Events** | el registro de lo que pasó, para depurar |
| **Sandbox** | desarrollo sin número productivo |

### Las herramientas que el agente puede llamar

Nombradas acá, detalladas en su PRD:

```
buscar_en_inventario        ¿qué tiene esta casa?
registrar_medicamento       guardar una caja nueva          → PRD 04
leer_envase                 visión sobre la foto de caja    → PRD 04
leer_receta                 visión sobre el documento       → PRD 05
resolver_producto           marca → principio activo (ISP)  → PRD 04
crear_tratamiento           pauta prescrita                 → PRD 05/06
registrar_toma              confirmar o saltar una toma     → PRD 06
registrar_integrante        agregar persona a la casa       → PRD 03
descartar_medicamento       sacar del inventario            → PRD 07
```

El agente **no escribe en la base de datos por su cuenta**: solo a través de
estas herramientas, que validan antes de guardar.

---

## 5 · LOS DATOS

**conversación**
| campo | qué es |
|---|---|
| hogar | de quién es el hilo |
| último mensaje del usuario | **el reloj de la ventana de 24 h** |
| estado | activa \| en manos de una persona \| cerrada |

**mensaje** — el registro de todo lo que entra y sale
| campo | qué es |
|---|---|
| dirección | entrante \| saliente |
| tipo | texto \| imagen \| documento \| plantilla \| interactivo |
| plantilla usada | si salió fuera de la ventana |
| archivo | ruta al medio guardado, si venía con foto |
| estado de entrega | enviado \| entregado \| leído \| fallido |

**El interruptor global:** `MODO_SIMULADO`. En verdadero, nada sale a
WhatsApp ni al modelo: las respuestas vienen de ejemplos guardados. Es el
modo por defecto hasta tener credenciales productivas.

**El reloj:** un solo lugar del sistema calcula "ahora" en zona horaria de
Chile y lo inyecta en cada turno y en cada proceso programado. Nadie más
llama al reloj del sistema por su cuenta. Chile cambia de hora dos veces al
año y la aritmética de fechas tiene que aguantarlo.

**El candado:** el número de WhatsApp identifica al hogar. Un número
desconocido nunca recibe información de nadie.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO llega un mensaje entrante

  identificamos el hogar por el número
  guardamos el mensaje y, si trae foto, el archivo
  MARCAMOS EL RELOJ: la ventana de 24 h parte de nuevo

  ENTONCES corre el workflow con: hoy, la casa, el inventario y el hilo.


CUANDO el sistema quiere hablar sin que le hablen

  ¿el último mensaje del usuario fue hace menos de 24 h?
     → sí: mandamos texto libre, sin costo
     → no: ¿existe plantilla aprobada para esto?
              → sí: la mandamos con sus variables
              → no: NO improvisamos — se registra y se avisa al equipo

  ENTONCES esperamos la respuesta, que abre la ventana para el resto.


CUANDO el agente falla o se demora demasiado

  no dejamos al usuario en silencio
  respondemos que hubo un problema y que lo vemos
  pasamos la conversación a una persona

  ENTONCES queda un evento registrado para revisarlo.
```

**Promesas:**
- ningún mensaje proactivo sale sin plantilla aprobada
- ninguna respuesta se calcula sin saber qué día es hoy
- el usuario nunca queda sin respuesta
- en desarrollo, jamás se gasta un mensaje real

---

## 7 · LA ECONOMÍA DEL CANAL — LO QUE HAY QUE VIGILAR

Este producto es proactivo por diseño, y **cada mensaje proactivo fuera de la
ventana se paga a Meta por unidad**. Es el costo variable real: ya no es el
modelo de IA, es WhatsApp.

La aritmética que define el margen del plan de **$3.990 CLP/mes**:

| escenario | plantillas/mes | riesgo |
|---|---|---|
| casa con vencimientos nomás | ~4 | irrelevante |
| un crónico, una toma diaria | ~30 | manejable |
| tres personas, tres tomas al día | ~270 | **come el plan entero** |

**La mitigación es de diseño, no de negociación:** el primer mensaje del día
sale por plantilla y abre la ventana; **todo lo que siga en las próximas 24 h
va como texto libre y no cuesta nada**. Por eso la rutina diaria se agrupa en
bloques (mañana, tarde, noche) y no se manda un mensaje por toma.

**Pendiente de verificar antes de fijar el precio final:** la tarifa de
plantilla de utilidad para Chile en el rate card vigente de Meta. El número de
arriba está sin resolver a propósito — no lo inventamos.
