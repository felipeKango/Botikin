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
