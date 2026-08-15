// =====================================================================
// Botikin · supabase/functions/send-welcome/index.ts
//
// Estructura de carpeta:
//   supabase/functions/send-welcome/index.ts        ← este archivo
//   supabase/functions/send-welcome/welcome.html    ← botikin-welcome-email.html
//
// Secrets:
//   supabase secrets set RESEND_API_KEY=re_xxx
//   supabase secrets set BOTIKIN_APP_URL=https://app.botikin.cl
//   supabase secrets set BOTIKIN_LOGO_URL=https://<proj>.supabase.co/storage/v1/object/public/brand/botikin-logo-320.png
//
// Deploy:  supabase functions deploy send-welcome
// Uso:     POST { "email": "...", "nombre": "...", "source": "waitlist" }
// =====================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TEMPLATE = await Deno.readTextFile(new URL("./welcome.html", import.meta.url));

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // service_role: única forma de emitir códigos
);

const APP_URL  = Deno.env.get("BOTIKIN_APP_URL")  ?? "https://app.botikin.cl";
const LOGO_URL = Deno.env.get("BOTIKIN_LOGO_URL")!;

const fmtFecha = (iso: string) =>
  new Intl.DateTimeFormat("es-CL", {
    day: "numeric", month: "long", year: "numeric", timeZone: "America/Santiago",
  }).format(new Date(iso));

const render = (tpl: string, vars: Record<string, string>) =>
  tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? "");

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const { email, nombre, source = "waitlist" } = await req.json();
    if (!email) return Response.json({ ok: false, error: "email requerido" }, { status: 400 });

    // 1. Emitir (o recuperar) el código en la tabla access_codes
    const { data: row, error } = await supabase
      .rpc("issue_access_code", { p_email: email, p_full_name: nombre ?? null, p_source: source })
      .single();
    if (error) throw error;

    // 2. Armar el correo
    const html = render(TEMPLATE, {
      NOMBRE:             (nombre ?? "").trim().split(" ")[0] || "hola",
      CODIGO:             row.code,
      EMAIL:              row.email,
      FECHA_EXPIRACION:   fmtFecha(row.expires_at),
      URL_ACTIVACION:     `${APP_URL}/activar?code=${encodeURIComponent(row.code)}`,
      LOGO_URL,
      URL_BAJA:           `${APP_URL}/baja?e=${encodeURIComponent(row.email)}`,
    });

    // 3. Enviar
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Botikin <hola@botikin.cl>",
        to: [row.email],
        subject: `Tu código de acceso a Botikin: ${row.code}`,
        html,
      }),
    });
    if (!res.ok) throw new Error(`Resend ${res.status}: ${await res.text()}`);

    // 4. Marcar como enviado
    await supabase.rpc("mark_access_code_sent", { p_code: row.code });

    return Response.json({ ok: true, code: row.code, expires_at: row.expires_at });
  } catch (e) {
    console.error(e);
    return Response.json({ ok: false, error: String(e) }, { status: 500 });
  }
});
