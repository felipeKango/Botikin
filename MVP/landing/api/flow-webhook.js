// Flow nos avisa acá cuando un pago se concreta. Servidor a servidor:
// es la única fuente de verdad, nunca lo que diga el navegador.
//
// Registra el pago (idempotente por orden) y emite el código.

import { flowPost } from "./_flow.js";

const SB   = process.env.SUPABASE_URL;
const SKEY = process.env.SUPABASE_SERVICE_KEY;

async function rpc(fn, args) {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SKEY, Authorization: `Bearer ${SKEY}`, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`${fn}: ${await r.text()}`);
  return r.json();
}

export default async function handler(req, res) {
  const token = req.body?.token ?? req.query?.token;
  if (!token) return res.status(400).send("falta token");

  try {
    // Le preguntamos a Flow por el estado real de esa orden.
    const p = await flowPost("payment/getStatus", { token });

    const estado = { 1: "pendiente", 2: "exitoso", 3: "rechazado", 4: "reversado" }[p.status]
                   ?? "pendiente";

    await rpc("registrar_pago", {
      p_orden:     String(p.commerceOrder ?? p.flowOrder),
      p_monto:     Math.round(Number(p.amount ?? 0)),
      p_estado:    estado,
      p_email:     p.payer ?? null,
      p_medio:     p.paymentData?.media ?? null,
      p_tarjeta:   p.paymentData?.cardNumber ?? null,
      p_pagado_el: p.paymentData?.date ?? new Date().toISOString(),
      p_crudo:     p,
    });

    // Flow espera 200 seco; cualquier otra cosa lo hace reintentar.
    res.status(200).send("ok");
  } catch (e) {
    console.error("flow-webhook:", e);
    res.status(500).send("error");
  }
}
