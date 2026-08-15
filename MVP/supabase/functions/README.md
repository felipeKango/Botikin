# El agente

```
WhatsApp → Kapso → webhook firmado → whatsapp/index.ts
                                          │
                                          ├── contexto_hogar()  ← hoy, casa, inventario
                                          ├── Claude (opus-5) + soul.md
                                          │      └── herramientas → Supabase
                                          └── respuesta → Kapso → WhatsApp
```

| archivo | qué hace |
|---|---|
| `whatsapp/index.ts` | la puerta: firma HMAC, identidad por teléfono, medios, envío |
| `_shared/agente.ts` | el bucle: herramientas + Claude |
| `_shared/alma.ts` | **generado** desde `soul.md` — no editar |

`soul.md` es la fuente de verdad del carácter. Tras cambiarlo:

```bash
node herramientas/generar-alma.mjs && supabase functions deploy whatsapp --no-verify-jwt
```

## Estado (15-08-2026)

Desplegado y verificado de punta a punta: firma HMAC (rechaza inválidas con
401), identidad por teléfono, contexto inyectado, Claude respondiendo en
carácter, mensajes guardados. **Un mensaje simulado recorre todo el camino en
5,8 segundos.**

## La ventana de 24 horas, comprobada

El primer intento de responder murió con:

```
422 · Cannot send non-template messages outside the 24-hour window.
```

Un mensaje simulado engaña a nuestra base pero no a Meta: si el usuario no
escribió de verdad, no hay ventana abierta y solo se aceptan plantillas.
Es la restricción central del PRD 01 confirmándose en la primera prueba real.

**Para probar:** escríbele al +1 201 801 8270 desde el teléfono registrado.
Ese mensaje abre la ventana y todo lo que siga en 24 h es texto libre y gratis.

## Pendiente

- Plantillas de utilidad aprobadas por Meta (sin ellas el agente no puede
  hablar primero: ni recordatorios, ni vencimientos, ni bienvenida)
- Catálogo del ISP: hoy `resolverProducto` crea productos con `resuelto=false`,
  así que la deduplicación automática de la base no los toma. El agente sí
  avisa de los duplicados que encuentra por coincidencia exacta.
- Las tomas y el cron diario de vencimientos (PRD 06 y 07)

## El comando `Botikin`

Escribir **"Botikin"** a secas devuelve el botiquín completo. Es una consulta
con salida fija, así que **no pasa por el modelo**: contesta al instante y no
cuesta tokens. Acepta mayúsculas, minúsculas y tildes.

Vacío:

```
No tienes nada registrado todavía.

Mándame una foto de cualquier caja que tengas a mano y la guardo —
con eso me basta para empezar.
```

Con contenido: agrupado por persona, **lo urgente primero**, y la fecha de
corte al pie para que se entienda contra qué día está calculado.

```
Tienes los siguientes medicamentos:

*Bruno*
• ⚠️ Paracetamol 100 mg/mL — 60 mL · vence en 21 días

*Rosa*
• Losartán 50 mg — 30 comprimidos · vence 03/2027

*De la casa*
• ⚠️ Paracetamol 500 mg — 16 comprimidos · venció 07/2026
• Paracetamol 500 mg — 8 comprimidos · sin fecha de vencimiento

⚠️ 2 necesitan atención. Lo vencido va a punto limpio de farmacia,
nunca al WC ni a la basura.

_Al 15 de agosto_
```

Detalles que importan y no son obvios:

- **Por principio activo, no por marca.** La lista dice "Paracetamol 500 mg",
  no "Kitadol": es el mismo criterio con que se detectan los duplicados, y así
  las dos cajas de paracetamol de arriba se ven como lo que son.
- **Ventana de 30 días**, la del PRD 07 — no los 7 de la app anterior.
- **Sin fecha no es lo mismo que vigente.** Un medicamento sin vencimiento se
  muestra tal cual, sin ⚠️ pero sin fingir que está bien.
- **Las unidades se pluralizan como corresponde:** "60 mL", no "60 mLs".
- El agente igual tiene el inventario en su contexto, así que preguntar
  "¿qué tengo?" en medio de una conversación también funciona — con sus
  palabras, no con este formato.
