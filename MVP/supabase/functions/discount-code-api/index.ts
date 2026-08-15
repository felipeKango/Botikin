// discount-code-api — validación de códigos de descuento.
// El cliente NUNCA lee la tabla discount_codes (sin políticas RLS);
// solo puede preguntar aquí si un código es válido.
// POST {action:"validate", codigo} → válido/ inválido con motivo.
// El canje real (consumir un uso) lo hace payments-api al suscribirse.

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, userFromRequest } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return error("method_not_allowed", "Usa POST", 405);

  const user = await userFromRequest(req);
  if (!user) return error("unauthorized", "Sesión inválida o expirada", 401);

  let body: { action?: string; codigo?: string };
  try {
    body = await req.json();
  } catch {
    return error("bad_request", "Body JSON inválido");
  }

  if (body.action !== "validate" || !body.codigo?.trim()) {
    return error("bad_request", "action=validate y codigo son obligatorios");
  }

  const admin = adminClient();
  const codigo = body.codigo.trim().toUpperCase();

  const { data: code } = await admin
    .from("discount_codes")
    .select("codigo, meses_gratis, usos_maximos, usos_actuales, activo, expira_el")
    .ilike("codigo", codigo)
    .maybeSingle();

  if (!code) {
    return json({ valido: false, motivo: "El código no existe" });
  }
  if (!code.activo) {
    return json({ valido: false, motivo: "El código ya no está activo" });
  }
  if (code.expira_el && new Date(code.expira_el) < new Date(new Date().toDateString())) {
    return json({ valido: false, motivo: "El código expiró" });
  }
  if (code.usos_actuales >= code.usos_maximos) {
    return json({ valido: false, motivo: "El código agotó sus usos" });
  }

  const { data: sub } = await admin
    .from("subscriptions")
    .select("codigo_descuento_usado")
    .eq("user_id", user.id)
    .single();
  if (sub?.codigo_descuento_usado === code.codigo) {
    return json({ valido: false, motivo: "Ya usaste este código" });
  }

  return json({
    valido: true,
    codigo: code.codigo,
    meses_gratis: code.meses_gratis,
  });
});
