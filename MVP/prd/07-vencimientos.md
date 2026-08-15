# PRD — Vencimientos

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** el proceso diario que revisa fechas y avisa 30 días antes, con
qué hacer — NO toca los recordatorios de toma
([06](06-tratamientos-y-adherencia.md)), NO recomienda comprar reemplazo

---

## 1 · RESUMEN

**Hoy:** los remedios se vencen en silencio y se descubren cuando ya no
sirven.

**Después:** el aviso llega 30 días antes, cuando todavía se puede hacer algo
con esa caja.

---

## 2 · LA HISTORIA

**ANTES**
Carmen abre el cajón buscando algo para la fiebre de Bruno un domingo a las
11 de la noche. Encuentra el jarabe. Lo mira contra la luz de la cocina y ve
que venció hace dos meses. No hay farmacia de turno cerca. **El aviso que
necesitaba era en junio, no esa noche.**

**DESPUÉS**
El 3 de junio le llega: *"El jarabe de Bruno (paracetamol 100 mg/mL) vence el
3 de julio. Todavía le quedan 60 mL —si lo van a usar, es ahora."* Y el 4 de
julio: *"Venció el jarabe de Bruno. Ese hay que llevarlo a un punto limpio de
farmacia, no al WC ni a la basura."* **Un mes de aviso es la diferencia entre
usarlo y botarlo.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — el aviso sale **30 días antes** del vencimiento
- **O2** — cada aviso trae **qué hacer**: usarlo, priorizarlo en un
  tratamiento activo, o desecharlo bien
- **O3** — el desecho se explica siempre: **punto limpio de farmacia, nunca
  al WC ni a la basura**
- **O4** — un solo mensaje al día por casa, aunque venzan cinco cosas
- **O5** — el usuario puede decir "lo boté" y sale del inventario
- **O6** — si el medicamento está en un tratamiento activo, el aviso lo dice
  y avisa que hay que reponer

- **NO1** — no botamos nada del inventario por nuestra cuenta: avisamos, la
  persona decide
- **NO2** — no recomendamos marca ni farmacia para reemplazarlo
- **NO3** — no repetimos el aviso todos los días: se avisa a los 30 días,
  el día del vencimiento, y basta
- **NO4** — no decimos nunca que un vencido "se puede usar igual"

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                    DESPUÉS

mirar la caja          reloj diario, 09:00 Chile
cuando ya es tarde       └─ revisamos TODO el inventario contra hoy
                              └─ tres momentos, tres mensajes distintos
                                   ├─ faltan 30 días → "úsalo o priorízalo"
                                   ├─ venció hoy     → "cómo desecharlo"
                                   └─ resto de días  → silencio
                                        └─ un solo mensaje por casa
                                             └─ el usuario puede responder
                                                  "lo boté" → sale del inventario
```

**El semáforo interno** (no se muestra, se usa para decidir):

| estado | cuándo |
|---|---|
| vencido | la fecha ya pasó |
| por vencer | faltan 30 días o menos |
| vigente | falta más de un mes |

Este cálculo es el mismo del MVP anterior y su lógica está probada en
`../_legacy/ios/BotikinKit/` — cambia la ventana (era 7 días, ahora 30) y el
canal de salida.

---

## 5 · LOS DATOS

**Lo que lee:** los medicamentos vigentes de todas las casas activas, con su
fecha de vencimiento, agrupados por hogar.

**Lo que escribe en el medicamento**
| campo | qué es |
|---|---|
| avisado a 30 días | fecha en que se mandó, para no repetir |
| avisado al vencer | fecha en que se mandó |
| estado | vigente \| agotado \| **descartado** |
| descartado el | cuándo salió del inventario |

**El candado de repetición:** un medicamento se avisa **una vez** en cada
momento. Los campos de arriba son el candado; sin ellos, el mismo jarabe
vencido molesta todos los días hasta que el usuario bloquea el número.

**El cruce que da valor:** antes de avisar, se mira si ese medicamento está en
un tratamiento activo. No es lo mismo *"vence un jarabe que no usas"* que
*"vence el jarabe que Bruno se está tomando ahora"* — el segundo necesita
reposición y el mensaje tiene que decirlo.

**Este proceso no puede invocarse desde la conversación:** corre solo, con
privilegio de sistema.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO son las 09:00 en Chile

  para cada casa con suscripción activa

    buscamos sus medicamentos vigentes
    calculamos los días que faltan contra HOY

    juntamos:
      los que vencen en 30 días exactos y no han sido avisados
      los que vencieron hoy y no han sido avisados

    ¿hay algo?  → si no, no le escribimos: el silencio también es un servicio

    para cada uno, miramos si está en un tratamiento activo

    ENTONCES armamos UN mensaje con:
       qué vence, de quién es, cuándo
       qué hacer:
         ├─ si está en tratamiento activo → "hay que reponerlo antes del X"
         ├─ si le queda contenido y no vence aún → "si lo van a usar, es ahora"
         └─ si ya venció → "llévalo a un punto limpio de farmacia,
                            nunca al WC ni a la basura"

    y marcamos cada uno como avisado.


CUANDO el usuario responde que lo botó

  lo marcamos descartado con la fecha
  no lo borramos: queda en el historial

  ENTONCES lo confirmamos en una línea y no se menciona nunca más.
```

**Promesas:**
- 30 días de aviso, siempre, no 7
- un mensaje al día por casa como máximo
- cada aviso trae qué hacer, no solo la mala noticia
- nunca decimos que un vencido sirve igual
- nada sale del inventario sin que la persona lo diga
