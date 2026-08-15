// Prueba del envío, protegida con la clave del panel.
//   curl -X POST .../api/probar-correo -H "x-panel-clave: …" -d '{"para":"…"}'

import { enviarCodigo } from "./_correo.js";

export default async function handler(req, res) {
  if (req.headers["x-panel-clave"] !== process.env.PANEL_CLAVE) {
    return res.status(401).json({ error: "clave incorrecta" });
  }
  const para = req.body?.para ?? process.env.SMTP_USER ?? "soporte@botikin.app";
  const r = await enviarCodigo({
    email: para, nombre: "Prueba", codigo: "TEST-0000",
    expira: new Date(Date.now() + 30 * 864e5).toISOString(),
  });
  res.status(r.enviado ? 200 : 500).json(r);
}
