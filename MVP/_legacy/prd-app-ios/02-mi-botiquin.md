# PRD — Mi Botiquín

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** inventario de remedios, semáforo de vencimiento, filtros y
análisis con IA — NO toca las alertas que salen del teléfono (ver
[07](07-alerta-diaria.md)), NO toca lectura de códigos de barra

---

## 1 · RESUMEN

**Hoy:** el inventario del botiquín está en la cabeza de una persona.

**Después:** cada caja es una ficha con fecha, y la app dice en un color si
sirve, si urge o si hay que botarla.

---

## 2 · LA HISTORIA

**ANTES**
Carmen abre el cajón buscando un antiinflamatorio. Encuentra seis cajas,
tres sin fecha visible, dos empezadas. Saca una al azar, le da desconfianza,
y compra otra en la farmacia de la esquina. **La caja que servía estaba ahí,
al fondo.**

**DESPUÉS**
Carmen abre la app y toca *Urgente*. Ve dos fichas en rojo: el Ibuprofeno
venció hace tres días, el Amoxicilina vence en cinco. El resto está en
verde. Bota dos cajas, se lleva una a la cartera y cierra el cajón en menos
de un minuto. **Por primera vez sabe lo que tiene.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — agregar un remedio toma menos de 20 segundos: nombre, dosis,
  unidades y fecha
- **O2** — el estado de vencimiento se ve sin leer: es un color y una frase
  corta
- **O3** — al abrir, un banner dice de una cuántos están vencidos y cuántos
  por vencer
- **O4** — la IA puede resumir el botiquín completo y priorizar qué mirar
  primero

- **NO1** — no calculamos dosis ni interacciones entre medicamentos
- **NO2** — no borramos solos los remedios vencidos: avisamos, decide el
  usuario
- **NO3** — no hay stock automático (las unidades las ajusta la persona)

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                     DESPUÉS

mirar la caja           ficha del remedio ─► fecha de vencimiento
adivinar la fecha                            └─ semáforo (4 estados)
                                                  ├─ vencido       rojo
                                                  ├─ vence pronto  rojo   ≤ 7 días
                                                  ├─ este mes      ámbar  8–30 días
                                                  └─ vigente       verde  > 30 días

(nada)                  lista ─► filtros: todos · vencidos · urgente ·
                                          este mes · vigentes
                              └─ banner de resumen arriba

(nada)                  botón "analizar mi botiquín" ─► portero de tokens
                                                         └─ IA prioriza alertas
```

---

## 5 · LOS DATOS

**remedio**
| campo | qué es |
|---|---|
| nombre | "Ibuprofeno" |
| dosis | texto libre: "400mg" |
| unidades | cuántas quedan, nunca negativo |
| fecha de vencimiento | **el campo que manda** |
| foto | opcional, privada del usuario |
| viene de receta | marca de origen |
| receta de origen | si vino de un escaneo, cuál |

**El semáforo no es un campo.** Se calcula de la fecha contra hoy, cada vez.
No se guarda un estado que puede quedar viejo mientras la app está cerrada.

**El candado:** cada quien ve solo sus remedios.
**La búsqueda que importa:** por usuario, ordenada por fecha de vencimiento
— es la consulta de toda la pantalla y de la alerta diaria.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO se abre Mi Botiquín

  traemos los remedios del usuario ordenados por vencimiento
  para cada uno calculamos el estado contra la fecha de hoy

  ENTONCES pintamos la lista y, si hay algo vencido o por vencer,
           un banner arriba que lo dice en una frase.


CUANDO el usuario pide "analizar mi botiquín"

  ¿tiene al menos un remedio?  → si no, le pedimos agregar primero
                                  (y NO le cobramos)
  ¿pasa el portero?            → si no, paywall

  ENTONCES la IA devuelve alertas priorizadas y un resumen de una frase,
           con los vencidos siempre en prioridad alta.
```

**Promesas:**
- un botiquín vacío nunca cobra tokens
- el estado que se ve siempre corresponde al día de hoy
- ningún remedio desaparece solo
