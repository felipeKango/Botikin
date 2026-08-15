// Cliente de la API de Flow.
//
// La firma: todos los parámetros ordenados alfabéticamente, concatenados
// como nombre+valor SIN separadores, HMAC-SHA256 con la secret key, en hex.
// Un orden distinto o un separador de más y Flow responde 401 sin explicar.

import crypto from "node:crypto";

const API = process.env.FLOW_API_URL ?? "https://www.flow.cl/api";
const KEY = process.env.FLOW_API_KEY;
const SEC = process.env.FLOW_SECRET_KEY;

function firmar(params) {
  const p = { ...params, apiKey: KEY };
  const cadena = Object.keys(p).sort().map((k) => k + p[k]).join("");
  return { ...p, s: crypto.createHmac("sha256", SEC).update(cadena).digest("hex") };
}

async function pedir(metodo, recurso, params = {}) {
  const p = firmar(params);
  const opciones = metodo === "GET"
    ? {}
    : { method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams(p) };
  const url = metodo === "GET" ? `${API}/${recurso}?${new URLSearchParams(p)}` : `${API}/${recurso}`;
  const r = await fetch(url, opciones);
  const texto = await r.text();
  let d; try { d = JSON.parse(texto); } catch { d = { crudo: texto }; }
  if (!r.ok) throw new Error(`flow ${recurso} ${r.status}: ${texto.slice(0, 300)}`);
  return d;
}

export const flowGet  = (r, p) => pedir("GET", r, p);
export const flowPost = (r, p) => pedir("POST", r, p);
