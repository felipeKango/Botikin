# PRD — Tratamientos y adherencia

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** recordar cada toma según la pauta prescrita, confirmarla y
descontar el stock — NO indica ni ajusta dosis, NO decide cuándo suspender un
tratamiento

---

## 1 · RESUMEN

**Hoy:** si alguien se tomó el remedio o no, es una suposición.

**Después:** es un dato, porque alguien preguntó y alguien respondió.

---

## 2 · LA HISTORIA

**ANTES**
A Rosa, la mamá de Carmen, le recetaron losartán de permanencia. Carmen
supone que se lo toma. Rosa a veces se lo toma. Cuando Carmen le pregunta,
Rosa dice que sí para no preocuparla. En el control, el doctor pregunta cómo
va con el tratamiento y las dos contestan que bien. **Nadie mintió y nadie
sabía.**

**DESPUÉS**
Cada mañana a las 8 llega un mensaje: *"Es hora del losartán de Rosa (1
comprimido)."* Carmen responde *"listo"*. El domingo llega el resumen:
*"Esta semana Rosa tomó 6 de 7 losartán. Le quedan 12 comprimidos, alcanzan
hasta el 12 de septiembre."* Ese número Carmen se lo puede mostrar al doctor.
**La adherencia se confirma, no se supone.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — cada toma de la pauta se recuerda a su hora, en horario de Chile
- **O2** — la toma se **confirma** con una respuesta; sin respuesta no se
  cuenta como tomada
- **O3** — confirmar descuenta stock, y el stock proyecta **hasta cuándo
  alcanza**
- **O4** — un tratamiento con duración **se cierra solo** el día que
  corresponde, y se avisa
- **O5** — la semana se resume en un mensaje que se le puede mostrar al médico
- **O6** — los recordatorios del día se agrupan en **bloques** (mañana, tarde,
  noche), no uno por toma

- **NO1** — no insistimos: si no contesta, queda sin confirmar y se sigue
- **NO2** — no regañamos ni culpabilizamos por una toma perdida
- **NO3** — no sugerimos suspender, retomar ni cambiar nada: eso es del médico
- **NO4** — los tratamientos **SOS no tienen recordatorio** (ver
  [05](05-leer-la-receta.md))
- **NO5** — no avisamos de madrugada: la pauta de cada 8 horas no despierta a
  nadie a las 3 AM

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                     DESPUÉS

suponer                 tratamiento activo (pauta del médico)
  └─ preguntar             └─ genera las tomas del día
       └─ que digan             └─ se agrupan en bloques
          que sí                     ├─ mañana  08:00
                                     ├─ tarde   14:00
                                     └─ noche   21:00
                                          └─ un mensaje por bloque
                                               └─ el usuario responde
                                                    ├─ "listo"    → confirmada
                                                    ├─ "no pude"  → saltada
                                                    └─ (silencio) → sin confirmar
                                                         └─ descuenta stock
                                                              └─ proyecta duración
                                                                   └─ resumen semanal
```

**Por qué bloques y no una toma por mensaje:** además de ser menos molesto,
es lo que hace viable el negocio. El primer mensaje del día sale por plantilla
y **abre la ventana de 24 horas**; todo lo que siga es conversación libre y
sin costo. Un mensaje por toma multiplicaría el costo del canal por tres (ver
[01](01-el-canal.md)).

---

## 5 · LOS DATOS

**tratamiento**
| campo | qué es |
|---|---|
| integrante | de quién es |
| medicamento / producto | qué se toma |
| dosis cantidad + unidad | "1 comprimido", "3,5 mL", "1 inhalación" |
| cada cuántas horas | la frecuencia prescrita |
| tipo de duración | `días` \| `permanencia` \| `sos` |
| fecha de inicio / fecha de término | término solo si es por días |
| receta de origen | de dónde salió la pauta |
| estado | activo \| terminado \| suspendido |

**toma** — un evento de la pauta
| campo | qué es |
|---|---|
| tratamiento | a cuál pertenece |
| momento programado | fecha y hora en Chile |
| estado | `pendiente` \| `confirmada` \| `saltada` \| `sin confirmar` |
| confirmada a las | cuándo respondió |

**Los cuatro estados importan.** `saltada` es "me dijo que no la tomó";
`sin confirmar` es "no sé". Mezclarlos convierte el resumen semanal en una
mentira, y ese resumen se le muestra a un médico.

**El descuento de stock:** solo una toma **confirmada** descuenta unidades del
medicamento. El stock manda el mensaje de *"te alcanza hasta el…"*, y ese
cálculo tiene que ser conservador.

**El candado del reloj:** las horas se calculan y se guardan en zona horaria
de Chile. Un cambio de hora no puede mover la toma de las 8 de la mañana.

**La ventana de silencio:** entre las 22:00 y las 08:00 no sale ningún
recordatorio. Una pauta de cada 8 horas se acomoda a los bloques del día.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO se crea un tratamiento

  generamos sus tomas según la pauta, desde la fecha de inicio
  ¿es SOS?  → no generamos ninguna: no tiene horario

  las repartimos en los bloques del día, respetando el silencio nocturno.


CUANDO llega la hora de un bloque

  juntamos todas las tomas pendientes de ese bloque, de toda la casa
  ¿hay alguna?  → si no, no mandamos nada

  ENTONCES mandamos UN mensaje con lo que toca ahora,
           nombrando a cada persona.


CUANDO el usuario responde

  ¿confirmó?
     → sí     : marcamos confirmada, descontamos stock
                   └─ ¿el stock alcanza para terminar el tratamiento?
                        → si no, se lo decimos ahora, no cuando se acabe
     → no pudo: marcamos saltada, sin comentarios ni consejos
     → algo distinto: seguimos la conversación normal

  ENTONCES respondemos corto y no volvemos a preguntar por esa toma.


CUANDO pasa el bloque sin respuesta

  las tomas quedan SIN CONFIRMAR
  no reenviamos, no insistimos, no lo mencionamos mañana.


CUANDO se cumple la fecha de término de un tratamiento

  lo cerramos y lo avisamos:
     "hoy termina el jarabe de Bruno; los inhaladores siguen"
  ¿quedó medicamento sin usar?  → lo dejamos en el inventario, vigente.


CUANDO termina la semana

  resumimos por persona: cuántas confirmadas de cuántas programadas,
  qué tratamientos siguen y hasta cuándo alcanza el stock.
  Sin juicios, sin porcentajes de reproche.
```

**Promesas:**
- una toma sin confirmar nunca se cuenta como tomada
- nunca insistimos ni reprochamos
- nunca despertamos a nadie
- la dosis del recordatorio es textual la que escribió el médico
- si el stock no alcanza para terminar el tratamiento, se avisa con tiempo
