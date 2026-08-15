// Envío del código de acceso.
//
// Dos caminos, y se elige solo por las variables que existan:
//   · RESEND_API_KEY  → Resend (mejor entregabilidad y registro de rebotes)
//   · SMTP_PASSWORD   → SMTP directo por el buzón de GoDaddy
//
// Hoy corre por SMTP. Cambiar a Resend después es agregar una variable y
// borrar otra — el resto del código no se entera.
//
// Nunca lanza: el correo importa, pero no tanto como para dejar a alguien
// sin su código justo después de haberle cobrado.

import { PLANTILLA } from "./_plantilla-correo.js";

const DE   = process.env.CORREO_REMITENTE ?? "Botikin <soporte@botikin.app>";
const LOGO = process.env.BOTIKIN_LOGO_URL ?? "https://botikin.app/img/avatar.png";
const WA   = process.env.BOTIKIN_WHATSAPP ?? "12018018270";

const fecha = (iso) => new Intl.DateTimeFormat("es-CL", {
  day: "numeric", month: "long", year: "numeric", timeZone: "America/Santiago",
}).format(new Date(iso));

const render = (tpl, vars) => tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? "");

async function porResend(para, asunto, html) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
               "content-type": "application/json" },
    body: JSON.stringify({ from: DE, to: [para], subject: asunto, html }),
  });
  if (!r.ok) throw new Error(`resend ${r.status}: ${(await r.text()).slice(0, 160)}`);
  return "resend";
}

async function porSmtp(para, asunto, html) {
  // Import dinámico: si algún día solo se usa Resend, nodemailer ni se carga.
  const { default: nodemailer } = await import("nodemailer");
  const puerto = Number(process.env.SMTP_PORT ?? 465);
  const t = nodemailer.createTransport({
    host: process.env.SMTP_HOST ?? "smtpout.secureserver.net",
    port: puerto,
    secure: puerto === 465,                 // 465 = SSL directo; 587 = STARTTLS
    auth: {
      user: process.env.SMTP_USER ?? "soporte@botikin.app",
      pass: process.env.SMTP_PASSWORD,
    },
    // El buzón de GoDaddy es lento en abrir: sin esto la función se corta antes.
    connectionTimeout: 12000,
    greetingTimeout: 8000,
    socketTimeout: 15000,
  });
  await t.sendMail({ from: DE, to: para, subject: asunto, html });
  return "smtp";
}

/** Devuelve { enviado, via, motivo }. */
export async function enviarCodigo({ email, nombre, codigo, expira }) {
  const html = render(PLANTILLA, {
    NOMBRE: (nombre ?? "").trim().split(" ")[0] || "hola",
    CODIGO: codigo,
    EMAIL: email,
    FECHA_EXPIRACION: fecha(expira),
    // Acá el código no se canjea en una web: se le escribe al agente.
    URL_ACTIVACION: `https://wa.me/${WA}?text=${encodeURIComponent(codigo)}`,
    LOGO_URL: LOGO,
    URL_BAJA: "mailto:soporte@botikin.app?subject=Baja",
  });
  const asunto = `Tu código de acceso a Botikin: ${codigo}`;

  try {
    if (process.env.RESEND_API_KEY) {
      return { enviado: true, via: await porResend(email, asunto, html) };
    }
    if (process.env.SMTP_PASSWORD) {
      return { enviado: true, via: await porSmtp(email, asunto, html) };
    }
    return { enviado: false, motivo: "sin RESEND_API_KEY ni SMTP_PASSWORD" };
  } catch (e) {
    return { enviado: false, motivo: String(e).slice(0, 200) };
  }
}
