# PRD — Escanear receta

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** foto de receta → lectura con IA → cruce con el botiquín →
importación — NO toca compra de remedios, NO toca recetas electrónicas ni
integración con farmacias

---

## 1 · RESUMEN

**Hoy:** la receta es un papel que se pierde y una letra que no se entiende.

**Después:** una foto, y en segundos la receta es una lista clara que ya
sabe qué tienes en casa.

---

## 2 · LA HISTORIA

**ANTES**
El doctor le pasa a Carmen un papel con tres líneas escritas a mano. En la
farmacia el vendedor la mira, duda, y le vende lo que cree que dice. Carmen
llega a la casa con un remedio que ya tenía y sin uno que necesitaba.
**La letra del doctor le costó dieciocho mil pesos.**

**DESPUÉS**
Carmen le saca una foto al papel antes de guardarlo. La app le muestra una
tarjeta: **Dr. Pérez · 14 de agosto**, y abajo los tres medicamentos con
dosis y posología en letra clara. Dos vienen marcados *✓ Ya lo tienes*. El
tercero dice *Comprar*. **Va a la farmacia a comprar una sola cosa.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — de la foto a la tarjeta legible en menos de 15 segundos
- **O2** — cada medicamento leído se cruza contra el botiquín y se marca
  *ya lo tienes* o *comprar*
- **O3** — lo que no se puede leer queda vacío; **la IA nunca inventa un
  medicamento**
- **O4** — la receta y su lectura quedan guardadas y se pueden volver a ver
- **O5** — desde la tarjeta se puede agregar un medicamento al botiquín en
  un toque

- **NO1** — no interpretamos el diagnóstico ni sugerimos cambiar el
  tratamiento
- **NO2** — no validamos la receta legalmente ni la enviamos a nadie
- **NO3** — no leemos varias recetas en una sola foto

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                    DESPUÉS

papel ─► cartera       foto (cámara o galería)
      └─ se pierde      └─ sube a almacenamiento privado del usuario
                             └─ se crea la receta (sin lectura todavía)
                                  └─ portero de tokens
                                       └─ IA de visión lee la imagen
                                            └─ se guarda la lectura
                                                 └─ cruce con el botiquín
                                                      └─ tarjeta en pantalla
                                                           └─ "agregar al botiquín"
```

---

## 5 · LOS DATOS

**receta**
| campo | qué es |
|---|---|
| foto | ruta en almacenamiento privado, en la carpeta del usuario |
| lectura | lo que la IA extrajo, guardado como documento |
| creada | para ordenar el historial |

**La forma de la lectura** (el acuerdo con la IA):
```
medico          texto
fecha_receta    fecha, o vacío si no se lee
medicamentos    lista de:
                  nombre       comercial o genérico
                  dosis        "500mg"
                  posologia    "1 comprimido cada 8 horas por 7 días"
                  indicaciones "tomar con comida"
```

**El cruce con el botiquín** no se guarda: se calcula al mostrar, comparando
nombres normalizados (sin tildes, sin mayúsculas, sin dobles espacios) y
aceptando coincidencia parcial en ambos sentidos.

**El candado:** la foto vive en una carpeta con el identificador del usuario
y el almacenamiento es privado. Nadie ve la receta de otro, ni con el enlace.

**El vínculo:** un remedio importado desde una receta recuerda de cuál vino.
Si la receta se borra, el remedio se queda (huérfano, no muerto).

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO el usuario toma una foto de receta

  subimos la foto a su carpeta privada
  creamos la receta vacía

  ¿pasa el portero?  → si no, paywall (y la foto queda guardada igual)

  ENTONCES la IA de visión la lee y devuelve la lista de medicamentos.


CUANDO la lectura vuelve

  ¿se pudo interpretar?   → si no, devolvemos los tokens y lo decimos claro
  guardamos la lectura en la receta

  para cada medicamento leído
    ¿su nombre calza con algo del botiquín?  → sí: "✓ Ya lo tienes"
                                               no: "Comprar"

  ENTONCES mostramos la tarjeta con médico, fecha y medicamentos marcados.
```

**Promesas:**
- si la IA falla, no se cobra
- un campo ilegible queda vacío, nunca adivinado
- la foto es privada del usuario y no sale del producto
- en el simulador, la cámara cae a galería sin romper el flujo
