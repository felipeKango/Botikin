// admin-dashboard-api — métricas para el dashboard admin (post-MVP).
// El dashboard Next.js queda fuera del alcance del MVP iOS; aquí solo
// se dejan los endpoints listos. Acceso restringido a los correos de
// ADMIN_EMAILS (secret, separados por coma).

import { error, handleOptions, json } from "../_shared/http.ts";
import { adminClient, userFromRequest } from "../_shared/supabase.ts";

const ADMIN_EMAILS = (Deno.env.get("ADMIN_EMAILS") ?? "")
  .split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;

  const user = await userFromRequest(req);
  if (!user || !ADMIN_EMAILS.includes(user.email.toLowerCase())) {
    return error("forbidden", "Solo administradores", 403);
  }

  const admin = adminClient();
  const url = new URL(req.url);
  const metric = url.searchParams.get("metric") ?? "overview";

  switch (metric) {
    case "overview": {
      const [users, subs, usage, messages] = await Promise.all([
        admin.from("users").select("id", { count: "exact", head: true }),
        admin.from("subscriptions").select("plan"),
        admin.from("token_usage").select("tokens_consumidos"),
        admin.from("whatsapp_messages").select("id", { count: "exact", head: true }),
      ]);

      const planCounts: Record<string, number> = { free: 0, basic: 0, pro: 0 };
      for (const s of subs.data ?? []) planCounts[s.plan] = (planCounts[s.plan] ?? 0) + 1;

      const mrrCLP = planCounts.basic * 4990 + planCounts.pro * 9990;
      const totalTokens = (usage.data ?? [])
        .reduce((acc, u) => acc + u.tokens_consumidos, 0);

      return json({
        usuarios_totales: users.count ?? 0,
        por_plan: planCounts,
        mrr_clp: mrrCLP,
        tokens_consumidos_totales: totalTokens,
        whatsapp_enviados: messages.count ?? 0,
      });
    }

    case "token_usage": {
      const { data } = await admin
        .from("token_usage")
        .select("tipo_accion, tokens_consumidos, created_at")
        .order("created_at", { ascending: false })
        .limit(500);
      return json({ registros: data ?? [] });
    }

    case "discount_codes": {
      const { data } = await admin
        .from("discount_codes")
        .select("codigo, meses_gratis, usos_maximos, usos_actuales, activo, expira_el");
      return json({ codigos: data ?? [] });
    }

    default:
      return error("bad_request", "metric debe ser overview | token_usage | discount_codes");
  }
});
