# Pruebas

## `leer-receta.mjs` — el lector de recetas

Prueba el prompt de extracción contra un documento real:

```bash
set -a && . ../.env && set +a
node leer-receta.mjs /ruta/a/una-receta.pdf
```

**No hay receta de ejemplo en el repo a propósito**: la que usamos en el diseño
tiene nombre, RUN y domicilio de un menor, y está excluida en `.gitignore`.
Usa una tuya, o anonimiza una antes de guardarla acá.

### Resultado de la validación (15-08-2026, `claude-opus-5`)

Receta pediátrica real, 2 páginas, 6 medicamentos. Extracción correcta al 100%:

- Separó principio activo / concentración / forma en los 6 casos.
- Distinguió los tres tipos de duración: 2 `permanencia`, 3 `dias` (5), 1 `sos`.
- **El paracetamol SOS quedó con `cada_horas: null`** aunque el papel dice
  "cada 6 Horas por SOS" — la regla de que un SOS no tiene horario funcionó.
- **Leyó la página 2**: la observación "en la noche, xuzal" de la levocetirizina
  está en la segunda hoja y la asoció al medicamento correcto de la primera.
- No inventó ningún dato: los medicamentos sin observación quedaron sin el campo.

Costo: 5.486 tokens de entrada + 1.134 de salida ≈ **USD 0,055 por receta**.

---

## `leer-envase.mjs` — el lector de cajas

```bash
set -a && . ../.env && set +a
node leer-envase.mjs ../CajaParacetamol.webp
```

### Resultado de la validación (15-08-2026, `claude-opus-5`)

Caja de Paracetamol Andrómaco 500 mg, 16 comprimidos. La imagen es la cara
frontal: **no tiene vencimiento ni lote impresos**, que es justo el caso que
importa probar.

| campo | resultado | por qué importa |
|---|---|---|
| principio activo | `PARACETAMOL` | no confundió el compuesto con el laboratorio |
| concentración | `500 mg` | |
| forma | `comprimido` | **la llave de deduplicación queda completa** |
| cantidad / unidad | `16` / `comprimido` | |
| marca | `null` | genérico sin marca de fantasía — y NO lo reportó como duda |
| laboratorio | `ANDRÓMACO` | separado de la marca, correctamente |
| vencimiento | `null` + duda | **no lo inventó** |
| lote | `null` + duda | |

La pregunta que generó para el vencimiento:

> *"¿Me dices la fecha de vencimiento? Está en una de las solapas del costado
> de la caja, a veces marcada en relieve. Busca algo como 'VENC' o 'EXP' con
> mes y año."*

Con `principio activo + concentración + forma` completos, esta caja colisiona
correctamente con un Panadol 500 mg comprimido: es la promesa central del
producto funcionando.

Costo: 3.088 tokens de entrada + 266 de salida ≈ **USD 0,022 por caja**.
