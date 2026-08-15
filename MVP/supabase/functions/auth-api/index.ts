// auth-api — login / registro / refresh.
// Entrega el JWT que la app usa en cada petición.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { error, handleOptions, json } from "../_shared/http.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

interface AuthBody {
  action: "signup" | "login" | "refresh";
  email?: string;
  password?: string;
  nombre?: string;
  refresh_token?: string;
}

Deno.serve(async (req) => {
  const options = handleOptions(req);
  if (options) return options;
  if (req.method !== "POST") return error("method_not_allowed", "Usa POST", 405);

  let body: AuthBody;
  try {
    body = await req.json();
  } catch {
    return error("bad_request", "Body JSON inválido");
  }

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false },
  });

  switch (body.action) {
    case "signup": {
      if (!body.email || !body.password) {
        return error("bad_request", "email y password son obligatorios");
      }
      const { data, error: err } = await client.auth.signUp({
        email: body.email,
        password: body.password,
        options: { data: { nombre: body.nombre ?? "" } },
      });
      if (err) return error("signup_failed", err.message, 422);
      return json({ session: data.session, user: data.user });
    }
    case "login": {
      if (!body.email || !body.password) {
        return error("bad_request", "email y password son obligatorios");
      }
      const { data, error: err } = await client.auth.signInWithPassword({
        email: body.email,
        password: body.password,
      });
      if (err) return error("invalid_credentials", "Correo o contraseña incorrectos", 401);
      return json({ session: data.session, user: data.user });
    }
    case "refresh": {
      if (!body.refresh_token) {
        return error("bad_request", "refresh_token es obligatorio");
      }
      const { data, error: err } = await client.auth.refreshSession({
        refresh_token: body.refresh_token,
      });
      if (err) return error("refresh_failed", err.message, 401);
      return json({ session: data.session, user: data.user });
    }
    default:
      return error("bad_request", "action debe ser signup | login | refresh");
  }
});
