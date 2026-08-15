# Manuales

| archivo | para quién |
|---|---|
| `Botikin-manual-usuario.pdf` | la familia que usa Botikin |
| `Botikin-manual-admin.pdf` | quien opera el producto |

Se escriben en HTML y se convierten con Chrome. Tras editar el `.html`:

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="Botikin-manual-usuario.pdf" "file://$PWD/manual-usuario.html"
```

## Las imágenes son reales

Ninguna es una ilustración: todas salieron del producto funcionando.

| imagen | de dónde |
|---|---|
| `activar.png` | la página de activación en producción |
| `flow-pago-ok.png` | el comprobante del primer pago real ($3.990, orden 178392655) |
| `panel-arriba.png` · `panel-abajo.png` | el panel con datos reales |
| `caja-real.webp` | la caja de paracetamol que se fotografió para probar la visión |
| `kapso-numero.png` | el número en el panel de Kapso |
| `web-landing.png` · `web-demo.png` | capturas en vivo de botikin.app |
| `conversacion-real.png` | la conversación real, renderizada desde la base |

Las conversaciones que aparecen dibujadas en los manuales sí están recreadas —
las reales traen nombres y datos de una familia de verdad.

## Al actualizar

Revisar que sigan siendo ciertos: el número de WhatsApp (+1 201 801 8270), el
precio ($3.990) y el correo de soporte. Están escritos en varios lugares de
ambos manuales.
