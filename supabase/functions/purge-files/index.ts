// Daily clean-up (run with the service role key, e.g. from pg_cron + pg_net, see README):
// 1. deletes ID copies and photos 3 months after a tenant leaves;
// 2. deletes owner accounts 7 days after "Delete account" (unless they logged in again and cancelled).
import { corsHeaders, errorResponse, json } from "../_shared/http.ts";
import { admin, rpc } from "../_shared/db.ts";
import { deleteKeys, deletePrefix } from "../_shared/storage.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) {
      return json({ error: "NOT_ALLOWED" }, 403);
    }

    // 1. old tenant files
    const files = await rpc<{ tenant_id: string; id_file_key: string | null; photo_key: string | null }[]>(
      "files_to_purge",
    );
    const keys = files.flatMap((f) => [f.id_file_key, f.photo_key]).filter((k): k is string => !!k);
    await deleteKeys(keys);
    if (files.length) await rpc("mark_files_purged", { p_tenants: files.map((f) => f.tenant_id) });

    // 2. deleted accounts
    const users = await rpc<{ user_id: string }[]>("accounts_to_delete");
    let deletedAccounts = 0;
    for (const u of users) {
      const { data: hostels } = await admin.from("hostels").select("id").eq("owner_id", u.user_id);
      for (const h of hostels ?? []) await deletePrefix(`hostels/${h.id}/`);
      const { error } = await admin.auth.admin.deleteUser(u.user_id); // cascades to all their data
      if (!error) deletedAccounts++;
    }

    return json({ files_deleted: keys.length, accounts_deleted: deletedAccounts });
  } catch (err) {
    return errorResponse(err);
  }
});
