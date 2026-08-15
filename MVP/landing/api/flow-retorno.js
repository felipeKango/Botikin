// Paso 2: Flow devuelve a la persona acá después de pagar.
//
// Confirmamos el estado con Flow —nunca con lo que diga el navegador— y le
// mostramos su código. El registro del pago ya lo hizo el webhook, que es
// servidor a servidor; acá solo leemos el resultado.

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

const pagina = (titulo, cuerpo) => `<!DOCTYPE html><html lang="es-CL"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${titulo} · Botikin</title><link rel="icon" href="/img/avatar.png"><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:"Poppins",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
background:#4A0E12;color:#FBF3E7;min-height:100vh;display:flex;align-items:center;
justify-content:center;padding:24px;line-height:1.6}
.caja{background:#FBF3E7;color:#2B1114;border-radius:24px;padding:clamp(28px,5vw,44px);
max-width:520px;text-align:center}
img{width:64px;height:64px;border-radius:16px;margin:0 auto 18px}
h1{font-size:1.6rem;letter-spacing:-.02em;font-weight:800;line-height:1.15;margin-bottom:12px}
p{color:#6B5A54;font-size:.98rem}
.codigo{background:#2B1114;color:#FBF3E7;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
font-size:2rem;letter-spacing:.12em;padding:18px;border-radius:14px;margin:22px 0 10px;font-weight:700}
.btn{display:inline-block;background:#C1121F;color:#fff;padding:14px 28px;border-radius:999px;
font-weight:700;text-decoration:none;margin-top:20px}
.pasos{text-align:left;margin:22px 0 0;padding-left:20px;color:#6B5A54;font-size:.92rem}
.pasos li{margin-bottom:8px}
</style></head><body><div class="caja"><img src="/img/avatar.png" alt="">${cuerpo}</div></body></html>`;

export default async function handler(req, res) {
  res.setHeader("content-type", "text/html; charset=utf-8");
  const token = req.query.token ?? req.body?.token;

  if (!token) {
    return res.status(400).send(pagina("Falta algo", `
      <h1>No pudimos confirmar el pago</h1>
      <p>Volvió sin la información de Flow. Si te cobraron, escríbenos a
      soporte@botikin.app y lo resolvemos.</p>`));
  }

  try {
    // La verdad la tiene Flow, no el navegador del usuario.
    const p = await flowPost("payment/getStatus", { token });

    if (p.status !== 2) {
      return res.status(200).send(pagina("Sin completar", `
        <h1>El pago no se completó</h1>
        <p>Puede que se haya cancelado o rechazado. No te cobramos nada.
        Puedes intentarlo de nuevo cuando quieras.</p>
        <a class="btn" href="/activar">Intentar otra vez</a>`));
    }

    // El webhook ya lo registró; esto es por si llega antes que él.
    await rpc("registrar_pago", {
      p_orden:     String(p.commerceOrder ?? p.flowOrder),
      p_monto:     Math.round(Number(p.amount ?? 0)),
      p_estado:    "exitoso",
      p_email:     p.payer ?? null,
      p_medio:     p.paymentData?.media ?? null,
      p_tarjeta:   p.paymentData?.cardNumber ?? null,
      p_pagado_el: p.paymentData?.date ?? new Date().toISOString(),
      p_crudo:     p,
    });

    const codigo = await rpc("issue_access_code", { p_email: p.payer, p_source: "flow" });

    return res.status(200).send(pagina("Listo", `
      <h1>Tu cuenta está activa</h1>
      <p>Este es tu código de acceso. También te llega por correo.</p>
      <div class="codigo">${codigo.code}</div>
      <ol class="pasos">
        <li>Abre WhatsApp y escríbele a <b>+1 201 801 8270</b></li>
        <li>Mándale este código tal cual</li>
        <li>Doctor Botikin te pregunta quiénes viven en tu casa y empiezan</li>
      </ol>
      <a class="btn" href="https://wa.me/12018018270?text=${encodeURIComponent(codigo.code)}">
        Abrir WhatsApp con el código</a>`));
  } catch (e) {
    console.error("flow-retorno:", e);
    return res.status(500).send(pagina("Error", `
      <h1>Algo se cayó de nuestro lado</h1>
      <p>Si te cobraron, tu pago está a salvo. Escríbenos a
      <b>soporte@botikin.app</b> y te mandamos el código a mano.</p>`));
  }
}
