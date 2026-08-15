# PRD — Registrar un medicamento

**Estado:** Borrador · **Dueño:** F. Rubilar · **Creado:** 15-08-2026
**Padre:** [Botikin](00-botikin.md)
**Alcance:** las tres formas de meter una caja al inventario —foto,
descripción o código— y la deduplicación por principio activo — NO toca
recetas ([05](05-leer-la-receta.md)), NO toca vencimientos
([07](07-vencimientos.md))

> **Acá vive la decisión que define el producto:** duplicado no es el mismo
> nombre, es el mismo principio activo.

---

## 1 · RESUMEN

**Hoy:** el inventario del botiquín no existe porque construirlo es un
trabajo que nadie va a hacer.

**Después:** se construye solo, una foto a la vez, en el momento de la
compra.

---

## 2 · LA HISTORIA

**ANTES**
Carmen va a la farmacia con dolor de cabeza y compra Kitadol. En su casa, en
el cajón de la cocina, hay una caja de Panadol con 16 comprimidos vigentes.
Son el mismo paracetamol de 500 mg. Carmen no está siendo desordenada: está
siendo humana. Nadie recuerda el inventario de su casa parado en la fila de
la caja. **Pagó dos veces por la misma molécula.**

**DESPUÉS**
Carmen le escribe al Doctor Botikin desde la farmacia: *"voy a la farmacia,
¿compro Kitadol para el stock?"* Le responde: *"No compres: ya tienes Panadol
500 mg (16 comprimidos, vence 11/2026). Es el mismo paracetamol en la misma
dosis. Lo que sí se te está acabando es el ibuprofeno: quedan 4."*
**Le pidió una marca y recibió un principio activo.**

---

## 3 · OBJETIVOS / NO-OBJETIVOS

- **O1** — tres caminos de entrada: **foto de la caja o boleta**, **descripción
  escrita**, o **código del envase**
- **O2** — el duplicado se detecta por **principio activo + concentración +
  forma farmacéutica**, resuelto contra el registro sanitario del ISP
- **O3** — nombre, concentración, formato y vencimiento salen **del envase**,
  no de una estimación del modelo
- **O4** — si un dato no se leyó con confianza, **se pregunta**; nunca se
  inventa
- **O5** — registrar toma un mensaje: la foto sola basta para empezar
- **O6** — el medicamento queda asociado a una persona de la casa

- **NO1** — no marcamos como duplicado dos formas farmacéuticas distintas:
  paracetamol 500 mg comprimido **no es** jarabe pediátrico de 100 mg/mL
- **NO2** — no adivinamos equivalencias entre marcas: las resuelve el ISP
- **NO3** — no pedimos una auditoría inicial del botiquín completo
- **NO4** — no recomendamos comprar ni dónde comprar

---

## 4 · CÓMO FUNCIONA HOY → CÓMO VA A FUNCIONAR

```
HOY                    DESPUÉS

formulario de 6        TRES ENTRADAS, UNA SALIDA
campos que nadie
llena                    📷 foto de caja o boleta
                            └─ visión: marca, principio activo,
                               concentración, forma, cantidad, vencimiento
                         ✍️ "compré losartán de 50, 30 comprimidos"
                            └─ texto: se resuelve contra el ISP
                         🔢 código del envase
                            └─ búsqueda directa en el registro

                                    ↓ todo converge

                         resolver_producto (ISP)
                            └─ ¿ya hay algo con este principio activo,
                               esta concentración y esta forma?
                                 ├─ sí → AVISA EL DUPLICADO
                                 │        y suma al stock
                                 └─ no → producto nuevo en la casa
                                      └─ ¿de quién es?
                                           └─ guardado + confirmación
                                                "vence 03/2027, te aviso
                                                 un mes antes"
```

---

## 5 · LOS DATOS

**producto** — el catálogo, compartido entre todas las casas
| campo | qué es |
|---|---|
| principio activo | "paracetamol" |
| concentración | "500 mg" |
| forma farmacéutica | comprimido \| jarabe \| aerosol \| solución oral… |
| nombres comerciales | Panadol, Kitadol, Tapsin… |
| registro sanitario | el identificador del ISP |

**medicamento** — la caja concreta que está en esa casa
| campo | qué es |
|---|---|
| hogar / integrante | de quién es |
| producto | qué contiene |
| marca comprada | lo que dice la caja |
| cantidad | cuántas unidades quedan |
| unidad | comprimido \| mL \| dosis \| sobre |
| fecha de vencimiento | **del envase, no estimada** |
| lote | si se pudo leer |
| foto | la imagen original, privada |
| origen | foto \| descripción \| código \| receta |
| estado | vigente \| agotado \| descartado |

**La llave de deduplicación:**
```
principio activo + concentración + forma farmacéutica
```
Los tres. Sacar cualquiera de los tres produce un error peligroso: sin la
forma, el jarabe del niño se confunde con el comprimido del adulto.

**El diccionario:** el registro sanitario del ISP. Cuando un producto no está
o no se puede resolver, **queda marcado como "sin resolver"** y no participa
de la deduplicación. Es preferible no detectar un duplicado que inventar uno.

**El candado:** las fotos viven en almacenamiento privado, en la carpeta del
hogar.

---

## 6 · PSEUDO-CÓDIGO — EL ACUERDO

```
CUANDO llega una foto de caja o boleta

  la guardamos y la leemos con visión
  extraemos: marca, principio activo, concentración, forma,
             cantidad y fecha de vencimiento

  para cada dato que salió dudoso o vacío
     → LO PREGUNTAMOS, uno a la vez, diciendo dónde mirarlo
       "la fecha salió cortada, ¿me la dictas? está en la solapa"

  ENTONCES resolvemos el producto contra el ISP.


CUANDO el usuario lo describe con palabras o da el código

  mismo camino, sin el paso de visión.


CUANDO ya tenemos el producto resuelto

  ¿la casa ya tiene algo con el mismo principio activo,
   la misma concentración Y la misma forma?

     → sí: LO DECIMOS ANTES QUE NADA
              "ojo: ya tenías 12 comprimidos vigentes del mismo losartán"
           y calculamos hasta cuándo alcanza el total,
           si hay un tratamiento activo que lo consuma

     → no: queda como producto nuevo de la casa

  ¿sabemos de quién es?
     → si no, preguntamos — y si es de varios, queda de la casa

  ENTONCES confirmamos en una frase lo que quedó guardado,
           incluyendo cuándo vamos a avisar del vencimiento.
```

**Promesas:**
- ningún dato del envase se estima: se lee o se pregunta
- el duplicado se avisa antes de que el usuario compre, no después
- dos formas farmacéuticas distintas nunca son el mismo ítem
- una foto basta para empezar; el resto lo conversamos
- si el ISP no resuelve el producto, lo decimos en vez de adivinar
