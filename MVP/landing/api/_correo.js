// Envío del código por correo.
//
// Si no hay RESEND_API_KEY, no falla: registra que no se pudo enviar y
// sigue. El código igual se le muestra en pantalla, así que la persona
// nunca queda bloqueada por un problema de correo.

import { PLANTILLA } from "./_plantilla-correo.js";

const RESEND = "https://api.resend.com/emails";
const DE     = process.env.CORREO_REMITENTE ?? "Botikin <soporte@botikin.app>";
const LOGO   = process.env.BOTIKIN_LOGO_URL ?? "https://botikin.app/img/avatar.png";
const WA     = process.env.BOTIKIN_WHATSAPP ?? "12018018270";

const fecha = (iso) => new Intl.DateTimeFormat("es-CL", {
  day: "numeric", month: "long", year: "numeric", timeZone: "America/Santiago",
}).format(new Date(iso));

const render = (tpl, vars) => tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? "");

/** Devuelve { enviado, motivo }. Nunca lanza: el correo es importante, pero
 *  no tanto como para dejar a alguien sin su código. */
export async function enviarCodigo({ email, nombre, codigo, expira }) {
  const clave = process.env.RESEND_API_KEY;
  if (!clave) return { enviado: false, motivo: "sin RESEND_API_KEY" };

  const html = render(PLANTILLA, {
    NOMBRE: (nombre ?? "").trim().split(" ")[0] || "hola",
    CODIGO: codigo,
    EMAIL: email,
    FECHA_EXPIRACION: fecha(expira),
    // En este producto el código no se canjea en una web: se le escribe
    // al agente. El enlace abre WhatsApp con el código ya puesto.
    URL_ACTIVACION: `https://wa.me/${WA}?text=${encodeURIComponent(codigo)}`,
    LOGO_URL: LOGO,
    URL_BAJA: "mailto:soporte@botikin.app?subject=Baja",
  });

  try {
    const r = await fetch(RESEND, {
      method: "POST",
      headers: { Authorization: `Bearer ${clave}`, "content-type": "application/json" },
      body: JSON.stringify({
        from: DE,
        to: [email],
        subject: `Tu código de acceso a Botikin: ${codigo}`,
        html,
      }),
    });
    if (!r.ok) return { enviado: false, motivo: `resend ${r.status}: ${(await r.text()).slice(0,160)}` };
    return { enviado: true };
  } catch (e) {
    return { enviado: false, motivo: String(e).slice(0, 160) };
  }
}
