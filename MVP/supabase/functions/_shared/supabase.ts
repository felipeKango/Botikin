// Clientes Supabase para Edge Functions.
// - admin: service_role, salta RLS. Solo para lógica de servidor.
// - userFromRequest: valida el JWT del usuario que llama.

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
}

export interface AuthedUser {
  id: string;
  email: string;
}

/// Extrae y valida el usuario del header Authorization: Bearer <jwt>.
/// Devuelve null si el token falta o es inválido.
export async function userFromRequest(req: Request): Promise<AuthedUser | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? "" };
}

/// Verifica que la petición venga con el service_role key
/// (para funciones internas como expiry-scheduler).
export function isServiceRequest(req: Request): boolean {
  const authHeader = req.headers.get("Authorization") ?? "";
  return authHeader === `Bearer ${SERVICE_ROLE_KEY}`;
}
