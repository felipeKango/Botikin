// El "portero" de la IA: middleware de tokens.
// Toda acción de IA pasa por aquí ANTES de llamar a Claude.
// Sin tokens → bloquea con 402 e invita a hacer upgrade.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { error } from "./http.ts";

export type TokenAction =
  | "prescription_analysis"
  | "cabinet_analysis"
  | "whatsapp_message"
  | "assistant_chat";

// Rangos estimados por acción (se muestran también en la app).
export const TOKEN_COST: Record<TokenAction, { min: number; max: number }> = {
  prescription_analysis: { min: 800, max: 1200 },
  cabinet_analysis: { min: 300, max: 500 },
  whatsapp_message: { min: 200, max: 400 },
  assistant_chat: { min: 100, max: 300 },
};

// Costo fijo que se cobra por acción (dentro del rango, predecible
// para el usuario: es el que muestra la pantalla Mis Tokens).
export const CHARGE_COST: Record<TokenAction, number> = {
  prescription_analysis: 1000,
  cabinet_analysis: 400,
  whatsapp_message: 300,
  assistant_chat: 200,
};

export interface GateResult {
  ok: true;
  tokensRestantes: number; // -1 = ilimitado
  plan: string;
}

/// Verifica saldo y descuenta atómicamente vía RPC consume_tokens.
/// Devuelve GateResult o una Response de error lista para retornar.
export async function consumeTokens(
  admin: SupabaseClient,
  userId: string,
  action: TokenAction,
  amount: number,
): Promise<GateResult | Response> {
  const { data, error: rpcError } = await admin.rpc("consume_tokens", {
    p_user_id: userId,
    p_action: action,
    p_amount: amount,
  });

  if (rpcError) {
    if (rpcError.message.includes("insufficient_tokens")) {
      return error(
        "insufficient_tokens",
        "No te quedan tokens suficientes para esta acción. Mejora tu plan para seguir usando la IA de Botikin.",
        402,
        { upgrade: true, action, tokens_requeridos: amount },
      );
    }
    if (rpcError.message.includes("subscription_inactive")) {
      return error(
        "subscription_inactive",
        "Tu suscripción no está activa. Renueva tu plan para continuar.",
        402,
        { upgrade: true },
      );
    }
    return error("token_gate_failed", rpcError.message, 500);
  }

  const row = Array.isArray(data) ? data[0] : data;
  return {
    ok: true,
    tokensRestantes: row?.tokens_restantes ?? 0,
    plan: row?.plan ?? "free",
  };
}

/// Costo que se cobra antes de llamar a Claude.
export function chargeCost(action: TokenAction): number {
  return CHARGE_COST[action];
}

/// Reembolsa un consumo si la llamada a Claude falló después de
/// haber descontado los tokens.
export async function refundTokens(
  admin: SupabaseClient,
  userId: string,
  action: TokenAction,
  amount: number,
): Promise<void> {
  const { data: sub } = await admin
    .from("subscriptions")
    .select("tokens_usados, tokens_total")
    .eq("user_id", userId)
    .single();
  if (sub && sub.tokens_total !== -1) {
    await admin
      .from("subscriptions")
      .update({ tokens_usados: Math.max(0, sub.tokens_usados - amount) })
      .eq("user_id", userId);
  }
  const { data: last } = await admin
    .from("token_usage")
    .select("id")
    .eq("user_id", userId)
    .eq("tipo_accion", action)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (last) {
    await admin.from("token_usage").delete().eq("id", last.id);
  }
}
