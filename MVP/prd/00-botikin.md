# PRD — Botikin (producto)

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Alcance:** un agente de WhatsApp llamado **Doctor Botikin** que administra
el botiquín de una casa — NO hay app, NO hay pantallas, NO hay plan gratis

> **Pivote.** Este documento reemplaza al PRD de la app iOS, archivado en
> `../_legacy/prd-app-ios/`. El producto ya no se descarga: se conversa.

---

## 1 · RESUMEN

**Hoy:** el botiquín de tu casa es una bodega sin inventario.

**Después:** es una conversación de WhatsApp con alguien que sí lleva la
cuenta.

---

## 2 · LA HISTORIA

**ANTES**
Carmen tiene remedios en tres lugares: el cajón del baño, la cocina y su
cartera. No sabe cuáles están vencidos. Compró Kitadol el mes pasado sin
acordarse del Panadol que ya tenía —el mismo paracetamol, otra marca—. A su
mamá le recetaron losartán "de permanencia" y hace dos semanas que no sabe si
se lo está tomando. Bajó una app para ordenar todo esto; la abrió dos veces.
**El problema no era la falta de una app. Era que nadie llevaba la cuenta.**

**DESPUÉS**
Carmen le manda una foto de la caja a un contacto de WhatsApp. Le responden:
*"Registré Losartán 50 mg × 30. Vence 03/2027: te aviso un mes antes."* Y
después: *"Ojo: ya tenías 12 comprimidos vigentes del mismo losartán. Con
esta caja te alcanza hasta el 12 de septiembre — no compres más."*

Al otro día, a las 8, le llega: *"Es hora del losartán de tu mamá."* Carmen
responde *"listo"* y sigue con su día. **El inventario se construyó solo,
dentro del chat que ya tenía abierto.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — registrar un medicamento toma una foto y cero formularios
- **O2** — el duplicado se detecta por **principio activo + concentración +
  forma farmacéutica**, nunca por marca
- **O3** — el aviso de vencimiento llega **30 días antes**, con qué hacer
- **O4** — la adherencia se **confirma**, no se supone
- **O5** — el agente sabe siempre qué día es hoy y quién es cada integrante
  de la casa, con su edad exacta
- **O6** — el agente **solo habla de lo que está en la base de datos**; lo
  demás lo deriva a un centro de salud (ver [`../soul.md`](../soul.md))

- **NO1** — no hay app, no hay web para el usuario final, no hay menús
- **NO2** — no hay plan gratis: se entra por invitación y se paga
- **NO3** — no damos asesoría médica, no indicamos ni ajustamos dosis
- **NO4** — no vendemos remedios ni derivamos a farmacias con convenio
- **NO5** — no perseguimos al usuario: si no contesta, no insistimos

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                              DESPUÉS

descargar una app                recibir un link de invitación
   └─ crear cuenta                  └─ pagar la suscripción
        └─ llenar formularios            └─ se abre el chat de WhatsApp
             └─ abrirla 2 veces               └─ el agente pregunta por la casa
                  └─ abandonarla                   └─ y ya está adentro

registrar un remedio             mandar una foto de la caja
  = 6 campos en un formulario      = un mensaje

saber si algo venció             el agente avisa 30 días antes
  = acordarse de mirar             = llega solo

saber si se lo tomó              el agente pregunta y el usuario confirma
  = suponer                        = un dato
```

---

## 5 · LOS DATOS

| entidad | para qué existe |
|---|---|
| **hogar** | la cuenta: un número de WhatsApp que paga y manda |
| **integrante** | cada persona de la casa: nombre, sexo, fecha de nacimiento |
| **medicamento** | una caja concreta: cuánto queda y hasta cuándo sirve |
| **producto** | el principio activo + concentración + forma, según el ISP |
| **receta** | el documento que subió el usuario y lo que se leyó de él |
| **tratamiento** | la pauta prescrita: cuánto, cada cuánto, desde cuándo, hasta cuándo |
| **toma** | cada evento de la pauta, y si se confirmó |
| **suscripción** | el estado del pago |
| **invitación** | el link de recomendación que abre la puerta |
| **conversación** | el hilo, y cuándo fue el último mensaje del usuario |

**La distinción que sostiene el producto:** *medicamento* es la caja que está
en tu casa; *producto* es lo que esa caja contiene según el registro
sanitario. Dos cajas de marcas distintas apuntan al mismo producto — y por eso
el agente sabe que ya lo tienes.

**El dato vivo:** **hoy**. La fecha en zona horaria de Chile entra en cada
turno de la conversación y en cada proceso programado. Sin ella no se calcula
un vencimiento, ni una edad, ni si un tratamiento de 5 días ya terminó.

**El candado:** un hogar solo ve lo suyo. Un número que no es el titular no
recibe información.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO llega cualquier mensaje al número de Botikin

  ¿el número pertenece a un hogar?     → si no, es una invitación por cobrar
  ¿la suscripción está al día?         → si no, lo mandamos a pagar
  ¿la casa ya está descrita?           → si no, seguimos conociéndola

  cargamos: hoy, la casa, el inventario, los tratamientos abiertos

  ENTONCES el agente responde SOLO con eso — y lo que no está ahí,
           lo deriva al médico.
```

**Promesas del producto:**
- ningún dato se inventa: si no se leyó, se pregunta
- el aviso de vencimiento llega antes de que sirva de nada, no después
- la dosis siempre es la que escribió un médico
- una urgencia corta todo y deriva de inmediato
- lo que la familia pida borrar, se borra

---

## PRDs HIJOS

| # | PRD | qué resuelve |
|---|---|---|
| 01 | [El canal](01-el-canal.md) | Kapso, la ventana de 24 h y el reloj — **la regla dura** |
| 02 | [Invitación y suscripción](02-invitacion-y-suscripcion.md) | link de recomendación + pago con Flow |
| 03 | [Conocer la casa](03-conocer-la-casa.md) | la conversación inicial: nombres, sexo, nacimiento |
| 04 | [Registrar un medicamento](04-registrar-medicamento.md) | foto, descripción o código → inventario sin duplicados |
| 05 | [Leer la receta](05-leer-la-receta.md) | el documento del médico → tratamientos |
| 06 | [Tratamientos y adherencia](06-tratamientos-y-adherencia.md) | recordar cada toma y confirmarla |
| 07 | [Vencimientos](07-vencimientos.md) | avisar 30 días antes y desechar bien |

**Orden de construcción:** 01 → 02 → 03 → 04 → 07 → 05 → 06.
El canal va primero: define qué mensajes son posibles y cuáles cuestan plata.
La adherencia va última porque es la que más depende de todo lo anterior.

**El alma del agente vive aparte:** [`../soul.md`](../soul.md). Ningún PRD
redefine su carácter ni sus límites; todos lo asumen.
