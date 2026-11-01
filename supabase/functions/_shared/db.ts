// Database access for Edge Functions.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { AppError, toAppError } from "./http.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

// Full-access client: only used on the server, never sent to the app.
export const admin: SupabaseClient = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Client that acts as the logged-in owner (row-level security applies).
export function clientForRequest(req: Request): SupabaseClient {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new AppError("NOT_LOGGED_IN", 401);
  return createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) throw toAppError(error.message);
  return data as T;
}
