// Envío de WhatsApp vía Twilio. Credenciales solo en secrets.

const ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID") ?? "";
const AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN") ?? "";
// Número WhatsApp de Twilio, ej: "whatsapp:+14155238886" (sandbox)
const FROM_NUMBER = Deno.env.get("TWILIO_WHATSAPP_FROM") ?? "";

export interface WhatsAppSendResult {
  sid: string | null;
  status: "sent" | "failed";
  errorMessage?: string;
}

export async function sendWhatsApp(
  toPhone: string, // E.164, ej: +56912345678
  body: string,
): Promise<WhatsAppSendResult> {
  if (!ACCOUNT_SID || !AUTH_TOKEN || !FROM_NUMBER) {
    return { sid: null, status: "failed", errorMessage: "twilio_not_configured" };
  }

  const url =
    `https://api.twilio.com/2010-04-01/Accounts/${ACCOUNT_SID}/Messages.json`;
  const params = new URLSearchParams({
    From: FROM_NUMBER,
    To: `whatsapp:${toPhone}`,
    Body: body,
  });

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(`${ACCOUNT_SID}:${AUTH_TOKEN}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    return { sid: null, status: "failed", errorMessage: text };
  }
  const data = await res.json();
  return { sid: data.sid ?? null, status: "sent" };
}
