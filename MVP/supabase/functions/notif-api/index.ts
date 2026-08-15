// notif-api — mensajería saliente: WhatsApp (Twilio) + push (APNs).
// Cada mensaje queda registrado en whatsapp_messages con su estado.
//
// POST {action:"send_whatsapp", telefono, tipo, texto? | contexto?}
//   - Si viene `texto`, se envía tal cual (0 tokens).
//   - Si viene `contexto`, Claude redacta el mensaje → pasa por el
//     portero de tokens (whatsapp_message ~300).
//   - WhatsApp requiere plan basic (solo usuario principal) o pro
//     (toda la familia). Plan free: bloqueado con invitación a upgrade.
// POST {action:"register_device", device_token} — registra APNs.
// POST {action:"send_push", title, body} — push de prueba al usuario.

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, userFromRequest } from "../_shared/supabase.ts";
import { chargeCost, consumeTokens, refundTokens } from "../_shared/tokens.ts";
import { analyzeText } from "../_shared/anthropic.ts";
import { sendWhatsApp } from "../_shared/twilio.ts";
import { sendPush } from "../_shared/apns.ts";

interface NotifBody {
  action: "send_whatsapp" | "register_device" | "send_push";
  telefono?: string;
  tipo?: "expiry_alert" | "reminder" | "ai_suggestion";
  texto?: string;
  contexto?: string;
  device_token?: string;
  title?: string;
  body?: string;
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return error("method_not_allowed", "Usa POST", 405);

  const user = await userFromRequest(req);
  if (!user) return error("unauthorized", "Sesión inválida o expirada", 401);

  let body: NotifBody;
  try {
    body = await req.json();
  } catch {
    return error("bad_request", "Body JSON inválido");
  }

  const admin = adminClient();

  switch (body.action) {
    case "register_device": {
      if (!body.device_token) {
        return error("bad_request", "device_token es obligatorio");
      }
      const { error: err } = await admin.from("device_tokens").upsert(
        { user_id: user.id, device_token: body.device_token },
        { onConflict: "user_id,device_token" },
      );
      if (err) return error("db_error", err.message, 500);
      return json({ ok: true });
    }

    case "send_push": {
      const { data: devices } = await admin
        .from("device_tokens")
        .select("device_token")
        .eq("user_id", user.id);
      if (!devices?.length) {
        return error("no_devices", "No hay dispositivos registrados", 404);
      }
      const results = await Promise.all(
        devices.map((d) =>
          sendPush(d.device_token, body.title ?? "Botikin", body.body ?? "")
        ),
      );
      return json({ enviados: results.filter((r) => r.ok).length });
    }

    case "send_whatsapp": {
      if (!body.telefono || !body.tipo) {
        return error("bad_request", "telefono y tipo son obligatorios");
      }

      // WhatsApp es una función de pago: plan free no la tiene.
      const { data: sub } = await admin
        .from("subscriptions")
        .select("plan, estado")
        .eq("user_id", user.id)
        .single();
      if (!sub || sub.plan === "free") {
        return error(
          "plan_required",
          "Los mensajes WhatsApp están disponibles desde el plan Básico. Mejora tu plan para activarlos.",
          402,
          { upgrade: true },
        );
      }
      // Plan basic: solo al teléfono del usuario principal
      if (sub.plan === "basic") {
        const { data: profile } = await admin
          .from("users")
          .select("telefono")
          .eq("id", user.id)
          .single();
        if (!profile?.telefono || profile.telefono !== body.telefono) {
          return error(
            "plan_limit",
            "Con el plan Básico solo puedes enviar WhatsApp a tu propio número. El plan Pro incluye a toda la familia.",
            402,
            { upgrade: true },
          );
        }
      }

      let texto = body.texto?.trim() ?? "";
      let tokensRestantes: number | null = null;
      let tokensConsumidos = 0;

      // Redacción con Claude (cobra tokens) si no vino texto listo
      if (!texto) {
        if (!body.contexto) {
          return error("bad_request", "Envía texto o contexto");
        }
        const cost = chargeCost("whatsapp_message");
        const gate = await consumeTokens(admin, user.id, "whatsapp_message", cost);
        if (gate instanceof Response) return gate;
        tokensRestantes = gate.tokensRestantes;
        tokensConsumidos = cost;

        try {
          const result = await analyzeText(
            "Redactas recordatorios de salud por WhatsApp en español de Chile. Naturales, cálidos y breves (máximo 2 frases), jamás robóticos. Respondes SOLO con el texto del mensaje.",
            `Redacta un mensaje de WhatsApp para: ${body.contexto}`,
            512,
          );
          texto = result.text.trim();
        } catch (e) {
          await refundTokens(admin, user.id, "whatsapp_message", cost);
          console.error("notif-api claude error:", e);
          return error("ai_failed", "No se pudo redactar el mensaje; no se descontaron tokens.", 502);
        }
      }

      const send = await sendWhatsApp(body.telefono, texto);

      const { data: row, error: insErr } = await admin
        .from("whatsapp_messages")
        .insert({
          user_id: user.id,
          telefono: body.telefono,
          texto,
          tipo: body.tipo,
          estado_entrega: send.status === "sent" ? "sent" : "failed",
          twilio_sid: send.sid,
        })
        .select()
        .single();
      if (insErr) return error("db_error", insErr.message, 500);

      if (send.status === "failed") {
        return json({
          mensaje: row,
          enviado: false,
          motivo: send.errorMessage,
          tokens_consumidos: tokensConsumidos,
          tokens_restantes: tokensRestantes,
        }, 502);
      }
      return json({
        mensaje: row,
        enviado: true,
        tokens_consumidos: tokensConsumidos,
        tokens_restantes: tokensRestantes,
      });
    }

    default:
      return error("bad_request", "action desconocida");
  }
});
