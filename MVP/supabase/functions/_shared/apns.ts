// Push notifications vía APNs con autenticación por token (ES256).
// Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (contenido .p8),
// APNS_BUNDLE_ID, APNS_ENVIRONMENT ("sandbox" | "production").

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY_PEM = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "app.botikin.ios";
const HOST = (Deno.env.get("APNS_ENVIRONMENT") ?? "sandbox") === "production"
  ? "https://api.push.apple.com"
  : "https://api.sandbox.push.apple.com";

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function makeJWT(): Promise<string> {
  const header = { alg: "ES256", kid: KEY_ID };
  const payload = { iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const enc = new TextEncoder();
  const unsigned = `${base64url(enc.encode(JSON.stringify(header)))}.${
    base64url(enc.encode(JSON.stringify(payload)))
  }`;
  const key = await importPrivateKey(PRIVATE_KEY_PEM);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    enc.encode(unsigned),
  );
  return `${unsigned}.${base64url(new Uint8Array(sig))}`;
}

export async function sendPush(
  deviceToken: string,
  title: string,
  body: string,
): Promise<{ ok: boolean; error?: string }> {
  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY_PEM) {
    return { ok: false, error: "apns_not_configured" };
  }

  const jwt = await makeJWT();
  const res = await fetch(`${HOST}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: "default" },
    }),
  });

  if (!res.ok) {
    return { ok: false, error: `${res.status}: ${await res.text()}` };
  }
  return { ok: true };
}
