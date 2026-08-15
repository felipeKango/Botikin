# PRD — Conocer la casa

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** la conversación inicial en la que el agente aprende quiénes viven
en la casa — nombres, sexo y fecha de nacimiento — NO toca el inventario, NO
pide diagnósticos ni antecedentes médicos

---

## 1 · RESUMEN

**Hoy:** un formulario de registro pide correo y contraseña, y no sabe para
quién es cada remedio.

**Después:** el agente conversa cinco minutos, aprende quiénes viven en la
casa y sus edades exactas, y desde ahí todo lo que diga tiene apellido.

---

## 2 · LA HISTORIA

**ANTES**
Carmen registra un jarabe. La app lo guarda como "un jarabe de Carmen".
Después registra los comprimidos de su mamá y el inhalador de Bruno, su hijo
de 4 años. Todo cae en el mismo saco. Cuando llega la alerta dice *"tienes un
medicamento por vencer"* — pero Carmen no sabe si es el de ella, el de su
mamá o el del niño. **Un botiquín familiar sin personas adentro no sirve de
nada.**

**DESPUÉS**
Lo primero que hace el Doctor Botikin es preguntar quiénes viven ahí. Carmen
escribe *"yo, mi mamá Rosa y mi hijo Bruno"*. Él pregunta por cada uno, de a
uno, y anota la fecha de nacimiento. Cuando Carmen dice que Bruno nació el 23
de noviembre de 2021, el agente ya sabe que hoy tiene 4 años, 8 meses y 23
días — y que su tratamiento va a venir en mililitros, no en comprimidos.
**Después de eso, cada mensaje dice el nombre de la persona correcta.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — al terminar, la casa tiene al menos un integrante con nombre, sexo
  y fecha de nacimiento
- **O2** — la conversación es una pregunta a la vez, no un formulario
- **O3** — la edad **se calcula de la fecha de nacimiento contra hoy**, nunca
  se guarda como número
- **O4** — se puede interrumpir y retomar sin perder lo ya contado
- **O5** — agregar o corregir un integrante después es igual de fácil que al
  principio
- **O6** — el titular queda marcado como tal

- **NO1** — no preguntamos enfermedades, alergias ni antecedentes: no somos
  una ficha clínica
- **NO2** — no pedimos RUT ni dirección
- **NO3** — no exigimos terminar de una: si Carmen quiere registrar un remedio
  antes, se le deja
- **NO4** — no inferimos el sexo del nombre: se pregunta

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                       DESPUÉS

registro con correo       el agente saluda y explica en dos frases
  └─ contraseña             └─ "¿quiénes viven contigo?"
       └─ perfil vacío           └─ por cada persona mencionada:
                                      ├─ ¿cómo se llama?
                                      ├─ ¿es hombre o mujer?
                                      └─ ¿cuándo nació?
                                           └─ confirma la edad en voz alta
                                                "Bruno, 4 años. ¿Correcto?"
                                                     └─ siguiente persona
                                                          └─ cierra:
                                                             "listo, ahora
                                                              mándame una foto
                                                              de cualquier caja"
```

**El cierre importa tanto como el inicio:** la conversación no termina en
"gracias", termina **pidiendo la primera foto**. El onboarding no está
completo hasta que hay un medicamento adentro.

---

## 5 · LOS DATOS

**integrante**
| campo | qué es |
|---|---|
| hogar | a qué casa pertenece |
| nombre | como lo llaman en la casa, no el nombre legal |
| sexo | `femenino` \| `masculino` \| `otro` \| `no dice` |
| fecha de nacimiento | **el campo del que sale todo lo demás** |
| es el titular | quién paga y manda |
| activo | para dar de baja sin borrar el historial |

**Lo que NO es un campo:** la edad. Se calcula contra **hoy**, siempre. Un
niño de 4 años cumple 5 sin que nadie edite nada, y el agente se entera solo.

**Para qué sirve cada dato, exactamente:**

| dato | uso real |
|---|---|
| nombre | que el mensaje diga "el jarabe de Bruno" |
| fecha de nacimiento | distinguir presentación pediátrica de adulta, y ordenar por quién |
| sexo | dirigirse bien a la persona, y contexto de la receta |

El sexo y la edad **no se usan para calcular dosis**. Esa línea está en
[`../soul.md`](../soul.md) y no se cruza acá.

**El candado:** los integrantes pertenecen a un hogar y no se comparten entre
cuentas. Rosa puede estar en la casa de Carmen sin tener cuenta propia.

**El estado de la conversación:** el hogar recuerda en qué parte del
onboarding va, para poder retomar. Se guarda como un paso, no como un
formulario a medio llenar.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO la suscripción se activa

  el agente escribe primero: se presenta en dos frases
  y pregunta quiénes viven en la casa.


CUANDO el usuario nombra a las personas

  para cada una, de a una y en orden:

    ¿cómo se llama?          → lo anotamos como lo dijo
    ¿es hombre o mujer?      → si no quiere decir, queda "no dice"
    ¿cuándo nació?           → aceptamos "23 de noviembre de 2021",
                               "23/11/21" o "tiene 4 años"
                                  └─ si dio la edad y no la fecha,
                                     PEDIMOS LA FECHA: la edad sola
                                     se pudre en tres meses

    calculamos la edad contra hoy y LA DECIMOS EN VOZ ALTA
       "Bruno, 4 años. ¿Correcto?"
          → si corrige, corregimos

  ENTONCES guardamos al integrante y seguimos con el siguiente.


CUANDO ya hay al menos una persona

  cerramos pidiendo la primera foto de una caja.


CUANDO en cualquier momento después aparece alguien nuevo
  ("es para mi suegra que se vino a vivir con nosotros")

  hacemos las mismas tres preguntas, sin ceremonia, y seguimos
  con lo que estábamos haciendo.
```

**Promesas:**
- una pregunta a la vez, siempre
- la edad se confirma en voz alta antes de guardarla
- nunca guardamos una edad: guardamos una fecha
- si el usuario quiere saltarse esto y registrar un remedio, se le deja —
  pero el remedio queda sin dueño hasta que sepamos de quién es
