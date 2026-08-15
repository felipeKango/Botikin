// whatsapp — la puerta del agente.
//
// Kapso recibe el WhatsApp y nos lo manda acá. Nosotros identificamos el hogar,
// corremos el agente y devolvemos la respuesta por el mismo número.
//
// Kapso queda como puro transporte: el cerebro vive en _shared/agente.ts y el
// carácter en soul.md. Si mañana cambia el proveedor de WhatsApp, se reescribe
// este archivo y nada más.

import { admin, responder } from "../_shared/agente.ts";

const KAPSO = "https://api.kapso.ai";

/** Firma HMAC-SHA256 del cuerpo crudo, comparada en tiempo constante. */
async function firmaValida(crudo: string, firma: string | null, secreto: string) {
  if (!firma) return false;
  const clave = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secreto),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", clave, new TextEncoder().encode(crudo));
  const esperada = [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  if (esperada.length !== firma.length) return false;
  let diff = 0;
  for (let i = 0; i < esperada.length; i++) diff |= esperada.charCodeAt(i) ^ firma.charCodeAt(i);
  return diff === 0;
}

/** Baja un archivo de Kapso y lo deja en base64 para mandárselo a Claude. */
async function bajarMedio(url: string) {
  const r = await fetch(url, { headers: { "X-API-Key": Deno.env.get("KAPSO_API_KEY")! } });
  if (!r.ok) throw new Error(`medio ${r.status}`);
  const tipo = r.headers.get("content-type")?.split(";")[0] ?? "image/jpeg";
  const bytes = new Uint8Array(await r.arrayBuffer());
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return { tipo, base64: btoa(bin) };
}

async function enviar(telefono: string, texto: string) {
  const r = await fetch(
    `${KAPSO}/meta/whatsapp/v24.0/${Deno.env.get("KAPSO_PHONE_NUMBER_ID")}/messages`,
    {
      method: "POST",
      headers: {
        "X-API-Key": Deno.env.get("KAPSO_API_KEY")!,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: telefono,
        type: "text",
        text: { body: texto },
      }),
    },
  );
  if (!r.ok) console.error("envío falló:", r.status, await r.text());
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  const crudo = await req.text();
  const secreto = Deno.env.get("KAPSO_WEBHOOK_SECRET");
  if (secreto && !await firmaValida(crudo, req.headers.get("x-webhook-signature"), secreto)) {
    return new Response("firma inválida", { status: 401 });
  }

  let cuerpo: Record<string, never>;
  try {
    cuerpo = JSON.parse(crudo);
  } catch {
    return new Response("json inválido", { status: 400 });
  }

  const m = cuerpo.message;
  // Solo mensajes entrantes: los nuestros vuelven por el mismo webhook.
  if (!m || m.kapso?.direction !== "inbound") return new Response("ignorado", { status: 200 });

  const telefono = "+" + String(m.from).replace(/\D/g, "");
  const db = admin();

  try {
    // Idempotencia: WhatsApp reintenta, y no queremos responder dos veces.
    const { data: visto } = await db.from("mensajes").select("id").eq("wamid", m.id).maybeSingle();
    if (visto) return new Response("duplicado", { status: 200 });

    // El teléfono ES la identidad. Sin hogar no hay conversación.
    const { data: hogar } = await db.from("hogares").select("id").eq("telefono", telefono).maybeSingle();
    if (!hogar) {
      await enviar(
        telefono,
        "Hola. Botikin funciona por invitación: necesitas el link de alguien que " +
        "ya lo use. Si tienes uno, ábrelo y nos vemos por acá.",
      );
      return new Response("sin hogar", { status: 200 });
    }

    // Marcamos el reloj de la ventana de 24 h ANTES de responder.
    await db.from("conversaciones").upsert(
      { hogar_id: hogar.id, ultimo_mensaje_usuario: new Date().toISOString() },
      { onConflict: "hogar_id" },
    );

    // Armamos la entrada: texto, foto, o ambos.
    const entrada: Record<string, unknown>[] = [];
    if (m.kapso?.has_media && m.kapso?.media_url) {
      const { tipo, base64 } = await bajarMedio(m.kapso.media_url);
      entrada.push(
        tipo === "application/pdf"
          ? { type: "document", source: { type: "base64", media_type: tipo, data: base64 } }
          : { type: "image", source: { type: "base64", media_type: tipo, data: base64 } },
      );
    }
    const texto = m.text?.body ?? m.image?.caption ?? m.document?.caption ?? "";
    entrada.push({ type: "text", text: texto || "(el usuario mandó un archivo sin texto)" });

    await db.from("mensajes").insert({
      hogar_id: hogar.id, direccion: "entrante",
      tipo: m.type, texto, wamid: m.id,
    });

    // Los últimos turnos, para que la conversación tenga memoria corta.
    const { data: previos } = await db.from("mensajes")
      .select("direccion, texto").eq("hogar_id", hogar.id)
      .not("texto", "is", null).neq("wamid", m.id)
      .order("created_at", { ascending: false }).limit(10);
    const historial = (previos ?? []).reverse().map((p) => ({
      role: p.direccion === "entrante" ? "user" : "assistant",
      content: p.texto,
    }));

    const respuesta = await responder(db, hogar.id, entrada, historial);

    await enviar(telefono, respuesta);
    await db.from("mensajes").insert({
      hogar_id: hogar.id, direccion: "saliente", tipo: "texto", texto: respuesta,
    });

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("agente:", e);
    // Nunca dejamos al usuario en silencio.
    await enviar(telefono, "Se me cayó algo acá. Dame un minuto y escríbeme de nuevo.");
    return new Response("error manejado", { status: 200 });
  }
});
