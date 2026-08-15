# Legado — Botikin app iOS (abril–agosto 2026)

Esto es la versión anterior del producto, **archivada el 15-08-2026** cuando
Botikin dejó de ser una app iOS y pasó a ser un agente de WhatsApp.

## Qué hay aquí

| carpeta | qué es |
|---|---|
| `ios/` | app SwiftUI completa (34 archivos Swift) + BotikinKit con sus tests |
| `prd-app-ios/` | los 8 PRDs de la versión app (padre + 7 hijos) |
| `README-app-ios.md` | setup completo del MVP anterior |
| `verify.sh` | script de verificación del MVP anterior |

## Por qué se archivó y no se borró

No hay git en esta carpeta: borrar sería irreversible. Además hay piezas que
siguen siendo válidas y conviene tener a mano:

- **La lógica de vencimientos** (`BotikinKit/ExpiryCalculator`) y sus tests:
  el cálculo de días y estados sirve igual en el agente, solo cambia la
  ventana de aviso (7 días en la app → 30 días en el agente).
- **El análisis de recetas con visión** (`supabase/functions/ai-engine`): el
  prompt y el formato de extracción son el punto de partida del nuevo lector
  de recetas.
- **Las políticas de aislamiento por usuario** del schema anterior.

## Qué NO sobrevive al pivote

- **El sistema de tokens y los tres planes.** Ahora hay un solo plan pago por
  invitación; el costo variable ya no es el modelo de IA sino el mensaje de
  WhatsApp.
- **Toda la capa de UI.** No hay pantallas: la interfaz es la conversación.
- **APNs y push.** Los avisos salen por WhatsApp.
- **Transbank WebPay.** El cobro recurrente ahora es Flow.cl.

## El schema de Supabase

`supabase/` **quedó en su lugar**, fuera de esta carpeta, porque el producto
nuevo lo sigue usando — pero necesita migración: el modelo pasa de
*un usuario = un botiquín* a *un hogar = varias personas con edades*, y
aparecen tratamientos, tomas y adherencia. Ver los PRD nuevos en `../prd/`.
