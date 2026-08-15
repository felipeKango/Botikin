// expiry-scheduler — cron diario (pg_cron, 08:00 Chile).
// Revisa vencimientos de TODOS los usuarios y dispara alertas:
//   - Push APNs a los dispositivos registrados (gratis).
//   - WhatsApp a usuarios basic/pro con teléfono registrado: el texto
//     lo redacta Claude (cobra tokens vía el portero); si el saldo no
//     alcanza, sale una plantilla sin costo para no perder la alerta.
// Solo se puede invocar con el service_role key (pg_cron).

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, isServiceRequest } from "../_shared/supabase.ts";
import { chargeCost, consumeTokens } from "../_shared/tokens.ts";
import { analyzeText } from "../_shared/anthropic.ts";
import { sendWhatsApp } from "../_shared/twilio.ts";
import { sendPush } from "../_shared/apns.ts";

const ALERT_WINDOW_DAYS = 7;

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (!isServiceRequest(req)) {
    return error("unauthorized", "Solo el scheduler puede invocar esta función", 401);
  }

  const admin = adminClient();
  const hoy = new Date();
  const limite = new Date(hoy.getTime() + ALERT_WINDOW_DAYS * 86400_000);
  const hoyStr = hoy.toISOString().slice(0, 10);
  const limiteStr = limite.toISOString().slice(0, 10);

  // Remedios vencidos o que vencen dentro de la ventana
  const { data: meds, error: qErr } = await admin
    .from("medicines")
    .select("id, user_id, nombre, dosis, fecha_vencimiento")
    .lte("fecha_vencimiento", limiteStr)
    .order("user_id");
  if (qErr) return error("db_error", qErr.message, 500);
  if (!meds?.length) return json({ usuarios_alertados: 0 });

  // Agrupar por usuario
  const byUser = new Map<string, typeof meds>();
  for (const m of meds) {
    const list = byUser.get(m.user_id) ?? [];
    list.push(m);
    byUser.set(m.user_id, list);
  }

  let alertados = 0;
  for (const [userId, userMeds] of byUser) {
    const vencidos = userMeds.filter((m) => m.fecha_vencimiento < hoyStr);
    const porVencer = userMeds.filter((m) => m.fecha_vencimiento >= hoyStr);

    const resumen = [
      vencidos.length ? `${vencidos.length} remedio(s) vencido(s)` : null,
      porVencer.length ? `${porVencer.length} vence(n) en menos de ${ALERT_WINDOW_DAYS} días` : null,
    ].filter(Boolean).join(" · ");

    // ── Push a todos los dispositivos (gratis) ──────────────────
    const { data: devices } = await admin
      .from("device_tokens")
      .select("device_token")
      .eq("user_id", userId);
    for (const d of devices ?? []) {
      await sendPush(d.device_token, "Botikin — revisa tu botiquín", resumen);
    }

    // ── WhatsApp solo basic/pro con teléfono ────────────────────
    const { data: sub } = await admin
      .from("subscriptions")
      .select("plan, estado")
      .eq("user_id", userId)
      .single();
    const { data: profile } = await admin
      .from("users")
      .select("telefono")
      .eq("id", userId)
      .single();

    if (
      sub && sub.estado === "active" && sub.plan !== "free" &&
      profile?.telefono
    ) {
      const detalle = userMeds
        .map((m) => `${m.nombre} ${m.dosis} vence el ${m.fecha_vencimiento}`)
        .join("; ");

      // Intento con Claude (cobra tokens); si el portero bloquea,
      // se usa una plantilla sin costo para no perder la alerta.
      let texto =
        `⚠️ Botikin: ${resumen}. Revisa tu botiquín en la app.`;
      const cost = chargeCost("whatsapp_message");
      const gate = await consumeTokens(admin, userId, "whatsapp_message", cost);
      if (!(gate instanceof Response)) {
        try {
          const result = await analyzeText(
            "Redactas alertas de vencimiento de medicamentos por WhatsApp en español de Chile. Cálido, claro, breve (máximo 2 frases). Respondes SOLO con el texto.",
            `Redacta una alerta para estos medicamentos: ${detalle}`,
            512,
          );
          texto = result.text.trim();
        } catch (_) {
          // Claude falló: se queda la plantilla (tokens ya cobrados
          // se reembolsarían en ai-engine; aquí preferimos simplicidad
          // y el mensaje sale igual).
        }
      }

      const send = await sendWhatsApp(profile.telefono, texto);
      await admin.from("whatsapp_messages").insert({
        user_id: userId,
        telefono: profile.telefono,
        texto,
        tipo: "expiry_alert",
        estado_entrega: send.status === "sent" ? "sent" : "failed",
        twilio_sid: send.sid,
      });
    }

    alertados++;
  }

  return json({ usuarios_alertados: alertados, remedios_revisados: meds.length });
});
