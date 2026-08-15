// payments-api — Transbank WebPay Plus (REST v1.2).
// POST {action:"create_transaction", plan, codigo_descuento?} → url + token
// GET/POST /payments-api?webpay_return=1&token_ws=... → commit + activación
//
// Secrets: TBK_COMMERCE_CODE, TBK_API_KEY, TBK_ENVIRONMENT
// (integration | production). En integración usar las credenciales
// públicas de prueba de Transbank (ver README).

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, userFromRequest } from "../_shared/supabase.ts";

const TBK_HOST = (Deno.env.get("TBK_ENVIRONMENT") ?? "integration") === "production"
  ? "https://webpay3g.transbank.cl"
  : "https://webpay3gint.transbank.cl";
const TBK_COMMERCE_CODE = Deno.env.get("TBK_COMMERCE_CODE") ?? "597055555532";
const TBK_API_KEY = Deno.env.get("TBK_API_KEY") ??
  "579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C";
const FUNCTIONS_URL = Deno.env.get("EDGE_FUNCTIONS_URL") ??
  `${Deno.env.get("SUPABASE_URL")}/functions/v1`;
// Deep link de vuelta a la app tras el pago
const APP_RETURN_URL = "botikin://payment-result";

const PLAN_PRICES_CLP: Record<string, number> = {
  basic: 4990,
  pro: 9990,
};

function tbkHeaders(): HeadersInit {
  return {
    "Tbk-Api-Key-Id": TBK_COMMERCE_CODE,
    "Tbk-Api-Key-Secret": TBK_API_KEY,
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  const url = new URL(req.url);

  // ── Retorno de WebPay (webhook de confirmación) ──────────────
  // WebPay redirige el navegador aquí con token_ws (pago normal),
  // o TBK_TOKEN (pago abortado por el usuario).
  if (url.searchParams.has("webpay_return") || url.searchParams.has("token_ws") ||
      url.searchParams.has("TBK_TOKEN")) {
    return await handleWebPayReturn(req, url);
  }

  // ── Crear transacción (requiere sesión) ──────────────────────
  if (req.method !== "POST") return error("method_not_allowed", "Usa POST", 405);

  const user = await userFromRequest(req);
  if (!user) return error("unauthorized", "Sesión inválida o expirada", 401);

  let body: { action?: string; plan?: string; codigo_descuento?: string };
  try {
    body = await req.json();
  } catch {
    return error("bad_request", "Body JSON inválido");
  }

  if (body.action !== "create_transaction") {
    return error("bad_request", "action debe ser create_transaction");
  }
  const plan = body.plan ?? "";
  const amount = PLAN_PRICES_CLP[plan];
  if (!amount) return error("bad_request", "plan debe ser basic | pro");

  const admin = adminClient();

  // Código de descuento: si es válido, activa el plan sin pasar por
  // WebPay (mes gratis de campaña).
  if (body.codigo_descuento) {
    const { data: redeemed, error: rpcErr } = await admin.rpc(
      "redeem_discount_code",
      { p_user_id: user.id, p_codigo: body.codigo_descuento },
    );
    if (rpcErr) {
      return error("invalid_code", codeErrorMessage(rpcErr.message), 422);
    }
    const meses = Array.isArray(redeemed)
      ? redeemed[0]?.meses_gratis ?? 1
      : 1;
    await admin.rpc("activate_plan", {
      p_user_id: user.id,
      p_plan: plan,
      p_meses: meses,
      p_codigo: body.codigo_descuento.toUpperCase(),
    });
    return json({
      estado: "activated_with_code",
      plan,
      meses_gratis: meses,
    });
  }

  // Transacción WebPay normal
  const buyOrder = `BOT-${crypto.randomUUID().slice(0, 18)}`;
  const sessionId = user.id.slice(0, 26);

  const { error: insErr } = await admin.from("payment_transactions").insert({
    user_id: user.id,
    buy_order: buyOrder,
    plan,
    monto_clp: amount,
    estado: "initialized",
  });
  if (insErr) return error("db_error", insErr.message, 500);

  const tbkRes = await fetch(
    `${TBK_HOST}/rswebpaytransaction/api/webpay/v1.2/transactions`,
    {
      method: "POST",
      headers: tbkHeaders(),
      body: JSON.stringify({
        buy_order: buyOrder,
        session_id: sessionId,
        amount,
        return_url: `${FUNCTIONS_URL}/payments-api?webpay_return=1`,
      }),
    },
  );
  if (!tbkRes.ok) {
    return error("tbk_error", `WebPay no respondió: ${await tbkRes.text()}`, 502);
  }
  const tbk = await tbkRes.json();

  await admin.from("payment_transactions")
    .update({ tbk_token: tbk.token })
    .eq("buy_order", buyOrder);

  // La app abre url + "?token_ws=" + token en SFSafariViewController
  return json({ url: tbk.url, token: tbk.token, buy_order: buyOrder });
});

async function handleWebPayReturn(_req: Request, url: URL): Promise<Response> {
  const admin = adminClient();

  // Pago abortado por el usuario
  const abortToken = url.searchParams.get("TBK_TOKEN");
  if (abortToken) {
    await admin.from("payment_transactions")
      .update({ estado: "failed" })
      .eq("tbk_token", abortToken);
    return redirectToApp("aborted");
  }

  const tokenWs = url.searchParams.get("token_ws");
  if (!tokenWs) return redirectToApp("error");

  // Commit de la transacción (confirma el cargo)
  const commitRes = await fetch(
    `${TBK_HOST}/rswebpaytransaction/api/webpay/v1.2/transactions/${tokenWs}`,
    { method: "PUT", headers: tbkHeaders() },
  );
  if (!commitRes.ok) {
    await admin.from("payment_transactions")
      .update({ estado: "failed" })
      .eq("tbk_token", tokenWs);
    return redirectToApp("failed");
  }
  const result = await commitRes.json();

  const { data: tx } = await admin.from("payment_transactions")
    .select("user_id, plan, buy_order")
    .eq("tbk_token", tokenWs)
    .single();
  if (!tx) return redirectToApp("error");

  const authorized = result.response_code === 0 && result.status === "AUTHORIZED";

  await admin.from("payment_transactions")
    .update({ estado: authorized ? "authorized" : "failed" })
    .eq("tbk_token", tokenWs);

  if (!authorized) return redirectToApp("failed");

  // Pago OK → activar suscripción y asignar tokens del plan
  await admin.rpc("activate_plan", {
    p_user_id: tx.user_id,
    p_plan: tx.plan,
    p_meses: 1,
    p_codigo: null,
  });
  await admin.from("subscriptions")
    .update({ transbank_buy_order: tx.buy_order })
    .eq("user_id", tx.user_id);

  return redirectToApp("ok");
}

/// Redirige el navegador de vuelta a la app vía deep link.
function redirectToApp(status: string): Response {
  const target = `${APP_RETURN_URL}?status=${status}`;
  // Página mínima por si el redirect automático no dispara el deep link
  return new Response(
    `<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=${target}"></head>` +
      `<body style="font-family:-apple-system;text-align:center;padding-top:40vh">` +
      `<a href="${target}">Volver a Botikin</a></body></html>`,
    { status: 200, headers: { "Content-Type": "text/html" } },
  );
}

function codeErrorMessage(raw: string): string {
  if (raw.includes("code_not_found")) return "El código no existe";
  if (raw.includes("code_inactive")) return "El código ya no está activo";
  if (raw.includes("code_expired")) return "El código expiró";
  if (raw.includes("code_exhausted")) return "El código agotó sus usos";
  if (raw.includes("code_already_used")) return "Ya usaste este código";
  return "Código inválido";
}
