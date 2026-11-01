// Rent reminder SMS.
// Owner (JWT on):  POST { action: "remind_all", hostel_id }  -> { sent, failed }
//   Reminds every tenant whose rent is due today or late (amount includes any late fee),
//   skipping anyone reminded in the last 12 hours.
// Daily job:       POST { action: "auto" } with header x-cron-secret = CRON_SECRET -> { sent, failed }
//   For hostels with Auto-remind on: rent due in 3 days or today. Schedule once a day (e.g. 09:00 IST).
// Deploy with --no-verify-jwt (the owner's login is checked below, the job uses CRON_SECRET).
import { AppError, corsHeaders, errorResponse, json, readJson, str } from "../_shared/http.ts";
import { admin, clientForRequest } from "../_shared/db.ts";
import { sendRentReminder } from "../_shared/sms.ts";

const APP_URL = (Deno.env.get("PUBLIC_APP_URL") ?? "").replace(/\/$/, "");
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

type Target = { tenant_id: string; phone: string; due: number; due_date: string; hostel_id?: string; hostel_name?: string };

function dueText(iso: string): string {
  const d = new Date(`${iso}T00:00:00+05:30`);
  return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", timeZone: "Asia/Kolkata" });
}

async function sendAll(targets: Target[], hostelOf: (t: Target) => { id: string; name: string }, kind: "manual" | "auto") {
  let sent = 0;
  let failed = 0;
  const log: { hostel_id: string; tenant_id: string; kind: string }[] = [];
  for (const t of targets) {
    const h = hostelOf(t);
    try {
      await sendRentReminder(t.phone, h.name, t.due, dueText(t.due_date), `${APP_URL}/`);
      log.push({ hostel_id: h.id, tenant_id: t.tenant_id, kind });
      sent++;
    } catch (e) {
      console.error("reminder failed", t.tenant_id, (e as Error).message);
      failed++;
    }
  }
  if (log.length) await admin.from("rent_reminders").insert(log);
  return { sent, failed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const body = await readJson(req);

    if (body.action === "auto") {
      if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) throw new AppError("NOT_ALLOWED", 403);
      const { data, error } = await admin.rpc("auto_reminder_targets");
      if (error) throw new AppError("SERVER_ERROR", 500);
      const rows = (data ?? []) as Target[];
      return json(await sendAll(rows, (t) => ({ id: t.hostel_id!, name: t.hostel_name ?? "My Hostel" }), "auto"));
    }

    if (body.action === "remind_all") {
      const owner = clientForRequest(req);
      const { data: auth } = await owner.auth.getUser();
      if (!auth?.user) throw new AppError("NOT_LOGGED_IN", 401);
      const hostelId = str(body.hostel_id, 40);
      if (!hostelId) throw new AppError("BAD_REQUEST");
      // Row-level security: only finds the hostel if the owner owns it.
      const { data: hostel } = await owner.from("hostels").select("id, name").eq("id", hostelId).maybeSingle();
      if (!hostel) throw new AppError("NOT_ALLOWED", 403);
      const { data, error } = await owner.rpc("rent_reminder_targets", { p_hostel: hostelId });
      if (error) throw new AppError("SERVER_ERROR", 500);
      const rows = (data ?? []) as Target[];
      const res = await sendAll(rows, () => ({ id: hostel.id, name: hostel.name }), "manual");
      return json(res);
    }

    throw new AppError("BAD_ACTION");
  } catch (err) {
    return errorResponse(err);
  }
});
