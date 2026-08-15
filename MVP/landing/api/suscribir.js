// Paso 1: crea una orden de pago propia para esta persona.
//
// Acá está la diferencia con el link estático que murió al primer uso:
// cada llamada genera una orden NUEVA con su propio token. Nadie puede
// consumir la de otro.
//
// Por qué payment/create y no subscription/create: la cuenta todavía no
// tiene contrato de cargo automático con Flow (error 7001), así que no se
// puede inscribir la tarjeta ni cobrar solo. Se cobra el mes por adelantado
// y se recobra cuando corresponda. Al habilitar el cargo automático esto
// pasa a customer/register + subscription/create y la renovación es sola.

import { flowPost } from "./_flow.js";

const SB   = process.env.SUPABASE_URL;
const SKEY = process.env.SUPABASE_SERVICE_KEY;
const MONTO = Number(process.env.BOTIKIN_PRECIO ?? 3990);

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "usa POST" });

  const { email, nombre } = req.body ?? {};
  const correo = String(email ?? "").trim().toLowerCase();
  if (!correo.includes("@") || correo.length < 6) {
    return res.status(400).json({ error: "Necesito un correo válido." });
  }

  // Si ya tiene un código vivo, no le cobramos de nuevo: se lo recordamos.
  try {
    const r = await fetch(
      `${SB}/rest/v1/access_codes?select=code,status&email=eq.${encodeURIComponent(correo)}` +
      `&status=in.(issued,sent)&expires_at=gt.${new Date().toISOString()}&limit=1`,
      { headers: { apikey: SKEY, Authorization: `Bearer ${SKEY}` } });
    const vivos = await r.json();
    if (Array.isArray(vivos) && vivos.length) {
      return res.status(200).json({ yaTiene: true, codigo: vivos[0].code });
    }
  } catch { /* si la consulta falla, seguimos al pago igual */ }

  const base = `https://${req.headers.host}`;
  const orden = `botikin-${Date.now()}`;

  try {
    const pago = await flowPost("payment/create", {
      commerceOrder: orden,
      subject: "Botikin — 1 mes",
      currency: "CLP",
      amount: MONTO,
      email: correo,
      urlConfirmation: `${base}/api/flow-webhook`,   // servidor a servidor
      urlReturn: `${base}/api/flow-retorno`,          // a donde vuelve la persona
      optional: JSON.stringify({ nombre: (nombre ?? "").trim() }),
    });

    res.status(200).json({ url: `${pago.url}?token=${pago.token}` });
  } catch (e) {
    console.error("suscribir:", e);
    res.status(500).json({
      error: "No pudimos abrir el pago. Inténtalo de nuevo en un momento.",
      detalle: String(e).slice(0, 200),
    });
  }
}
