# PRD — Leer la receta

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** el documento del médico → tratamientos con su pauta — NO toca los
recordatorios ([06](06-tratamientos-y-adherencia.md)), NO interpreta el
diagnóstico, NO valida la receta legalmente

---

## 1 · RESUMEN

**Hoy:** la receta es un PDF en el correo o un papel en la cartera, y su
contenido vive en la memoria de quien fue a la consulta.

**Después:** se manda por WhatsApp y se convierte en los tratamientos activos
de cada persona de la casa.

---

## 2 · LA HISTORIA

**ANTES**
A Bruno, de 4 años, le recetan seis cosas en una consulta: dos inhaladores de
permanencia, paracetamol SOS, un jarabe para la tos por 5 días, un
antihistamínico y otro jarabe por 5 días. Carmen sale de la consulta con un
PDF de dos páginas y buenas intenciones. Al tercer día ya no se acuerda cuál
era cada 8 horas y cuál cada 12, cuál terminaba el viernes y cuál seguía. Le
da los dos jarabes revueltos y suspende el inhalador cuando Bruno mejora.
**La receta era clarísima; el problema fue el día 3.**

**DESPUÉS**
Carmen reenvía el PDF al Doctor Botikin. Él responde: *"Receta del 15 de
mayo, Dra. Fernández, para Bruno. Son 6 tratamientos: 2 de permanencia y 4
que terminan el 20 de mayo. Te voy a recordar las tomas de cada uno.
¿Empezamos hoy?"* El viernes 20, sin que nadie le pregunte: *"Hoy termina el
jarabe para la tos de Bruno. Los dos inhaladores siguen."*
**La receta dejó de ser un papel y pasó a ser un calendario.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — se acepta **foto y PDF**, de una o varias páginas
- **O2** — cada medicamento sale con su **pauta completa**: dosis, cantidad,
  frecuencia, duración y fecha de inicio
- **O3** — se distingue **"por 5 días" (termina)** de **"permanencia"
  (crónico)** y de **"SOS" (a demanda)** — son tres cosas distintas
- **O4** — la receta se asocia a la **persona correcta** de la casa
- **O5** — se cruza contra el inventario: qué ya tiene y qué falta comprar
- **O6** — lo que no se lee con confianza se pregunta; **la pauta nunca se
  completa por el modelo**

- **NO1** — no interpretamos el diagnóstico ni las observaciones clínicas
- **NO2** — no ajustamos ni convertimos dosis (ni de mg a mL, ni por peso)
- **NO3** — no validamos la receta ni la enviamos a farmacias
- **NO4** — no guardamos el RUT ni la dirección que traiga el documento

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                     DESPUÉS

PDF en el correo        el usuario reenvía el documento
  └─ se olvida            └─ se guarda privado
                               └─ visión sobre TODAS las páginas
                                    └─ se extrae por medicamento:
                                       principio activo · concentración · forma
                                       marca recomendada
                                       dosis + frecuencia + duración
                                       fecha de inicio · observaciones
                                            └─ ¿para quién es?
                                               (nombre del paciente vs. la casa)
                                                 └─ cruce con el inventario
                                                    ✓ lo tienes / ✗ falta
                                                      └─ se crean los tratamientos
                                                           └─ empiezan los
                                                              recordatorios → PRD 06
```

### La anatomía real de una receta chilena

Del ejemplo de referencia (`../../Receta Tipo.pdf`), lo que hay que leer:

| bloque | contenido |
|---|---|
| encabezado | médico, especialidad, centro, fecha de atención |
| paciente | nombre, **edad** — sirve para confirmar de quién es |
| por medicamento | **principio activo + concentración + forma** en el título |
| | *Recomendado:* la marca y presentación sugerida |
| | *Aplicación:* dosis, cada cuántas horas, **por cuánto tiempo** |
| | *Inicio del Tratamiento:* la fecha |
| | *Observaciones:* texto libre del médico |
| pie | código de verificación, fecha de emisión, **paginación** |

**Tres trampas conocidas, que hay que resolver a propósito:**

1. **La receta sigue en la página 2.** Las observaciones de un medicamento
   pueden quedar cortadas y continuar en la hoja siguiente. Leer solo la
   primera página pierde datos.
2. **"por Permanencia" no es una duración.** Significa crónico: no termina.
   Tratarlo como un número de días apaga un tratamiento que no debía apagarse.
3. **"SOS" no tiene horario.** Es a demanda. Ponerle recordatorios de toma
   sería inventar una pauta que el médico no escribió.

---

## 5 · LOS DATOS

**receta**
| campo | qué es |
|---|---|
| hogar / integrante | de quién es |
| archivo | ruta privada al documento original |
| médico | nombre y especialidad |
| centro | dónde se emitió |
| fecha de atención | cuándo |
| lectura | lo que se extrajo, tal cual |
| estado | leída \| con dudas pendientes \| confirmada |

**La forma de la lectura** (el acuerdo con el modelo):
```
paciente        nombre y edad que trae el documento
medico          nombre
fecha_atencion  fecha
medicamentos    lista de:
                  principio_activo    "fluticasona propionato"
                  concentracion       "125 mcg/dosis"
                  forma               "aerosol para inhalación"
                  marca_recomendada   "Flixotide LF 125 mcg x 120 dosis"
                  dosis_cantidad      1          ← número
                  dosis_unidad        "inhalación"
                  cada_horas          12
                  duracion_tipo       dias | permanencia | sos
                  duracion_dias       5          ← solo si duracion_tipo = dias
                  fecha_inicio        fecha
                  observaciones       texto tal cual, sin interpretar
```

**Lo que NO se guarda** aunque venga en el documento: RUT, dirección,
teléfono y correo del paciente. Se leen para poder identificar a la persona y
se descartan. La receta guarda datos de salud de un menor: cuanto menos PII
haya alrededor, mejor.

**El candado de identidad:** el nombre del paciente en la receta se compara
con los integrantes de la casa. Si no calza con ninguno, **se pregunta** —
nunca se asigna al titular por descarte.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO llega una foto o PDF de receta

  la guardamos privada
  la leemos COMPLETA, todas las páginas

  ENTONCES sacamos la lista de medicamentos con su pauta.


CUANDO tenemos la lectura

  ¿el nombre del paciente calza con alguien de la casa?
     → sí  : se lo asignamos
     → no  : preguntamos de quién es
              (y si es alguien nuevo, lo damos de alta → PRD 03)

  para cada medicamento
     ¿quedó completa la pauta (dosis, frecuencia y duración)?
        → no: PREGUNTAMOS lo que falta, citando lo que sí leímos
              "dice 3,5 mL cada 8 horas, pero no leí por cuántos días"
        → sí: seguimos

     ¿es de permanencia?  → no tiene fecha de término
     ¿es SOS?             → SIN recordatorios de horario
     ¿tiene duración?     → calculamos la fecha de término desde el inicio

     ¿la casa ya tiene ese principio activo, concentración y forma?
        → sí: "esto ya lo tienes"
        → no: "esto hay que comprarlo"

  ENTONCES resumimos en un mensaje: cuántos tratamientos,
           cuáles terminan y cuándo, y qué falta comprar.
           Y preguntamos si empezamos con los recordatorios.
```

**Promesas:**
- se leen todas las páginas, siempre
- una pauta incompleta se pregunta, nunca se completa sola
- permanencia, días y SOS son tres cosas distintas y se tratan distinto
- la dosis que guardamos es la que escribió el médico, textual
- el RUT y la dirección del documento no se guardan
