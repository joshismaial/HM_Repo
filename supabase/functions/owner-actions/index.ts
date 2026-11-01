// Owner actions that need server secrets. Requires the owner's login (keep JWT verification on).
// POST { action: "file_url",     tenant_id, kind: "id" | "photo" }      -> { url }   (5-minute link)
// POST { action: "student_link", tenant_id, reset?: boolean, sms?: boolean } -> { url }
// POST { action: "hostel_photo_upload", hostel_id, content_type }      -> { key, url }   (signed upload link)
// POST { action: "hostel_photo_url",    hostel_id }                     -> { url | null } (1-hour link)
// POST { action: "thumb_urls",          hostel_id }                     -> { urls: { tenant_id: url } } (lists)
import { AppError, corsHeaders, errorResponse, json, readJson, str } from "../_shared/http.ts";
import { admin, clientForRequest } from "../_shared/db.ts";
import { randomToken, sha256Hex } from "../_shared/crypto.ts";
import { checkImage, uploadUrl, viewUrl } from "../_shared/storage.ts";
import { sendStudentLink } from "../_shared/sms.ts";

const APP_URL = (Deno.env.get("PUBLIC_APP_URL") ?? "").replace(/\/$/, "");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const owner = clientForRequest(req);
    const { data: auth } = await owner.auth.getUser();
    if (!auth?.user) throw new AppError("NOT_LOGGED_IN", 401);
    const body = await readJson(req);

    // ---- hostel-level actions (row-level security: only finds the owner's own hostel) ----
    if (["hostel_photo_upload", "hostel_photo_url", "hostel_photo_saved", "thumb_urls"].includes(String(body.action))) {
      const hostelId = str(body.hostel_id, 40);
      if (!hostelId) throw new AppError("BAD_REQUEST");
      const { data: hostel } = await owner.from("hostels").select("id, photo_key").eq("id", hostelId).maybeSingle();
      if (!hostel) throw new AppError("NOT_ALLOWED", 403);
      const folder = `hostels/${hostel.id}/photo/`;

      if (body.action === "hostel_photo_upload") {
        const contentType = String(body.content_type ?? "image/jpeg");
        if (!/^image\/(jpeg|png|webp)$/.test(contentType)) throw new AppError("BAD_FILE_TYPE");
        const key = `${folder}${crypto.randomUUID()}.${contentType.split("/")[1].replace("jpeg", "jpg")}`;
        return json({ key, url: await uploadUrl(key, contentType) });
      }
      if (body.action === "hostel_photo_saved") {
        // the app uploaded the photo: check it and save the key (or remove the photo when key is null)
        const key = body.key == null ? null : str(body.key, 200);
        if (key && (!key.startsWith(folder) || !(await checkImage(key)))) throw new AppError("FILE_TOO_BIG_OR_MISSING");
        const { error } = await admin.from("hostels").update({ photo_key: key }).eq("id", hostel.id);
        if (error) throw new AppError("SERVER_ERROR", 500);
        return json({ url: key ? await viewUrl(key, 3600) : null });
      }
      if (body.action === "hostel_photo_url") {
        const key = hostel.photo_key as string | null;
        return json({ url: key && key.startsWith(folder) ? await viewUrl(key, 3600) : null });
      }
      // thumbnails for the Rent / Tenants / Requests lists (1-hour links; the app caches what it showed)
      const { data: rows } = await owner.from("tenants")
        .select("id, photo_thumb_key").eq("hostel_id", hostel.id).not("photo_thumb_key", "is", null)
        .in("status", ["active", "notice", "pending_approval", "awaiting_payment"]);
      const urls: Record<string, string> = {};
      for (const t of rows ?? []) {
        const k = t.photo_thumb_key as string;
        if (k.startsWith(`hostels/${hostel.id}/tenants/${t.id}/thumb-`)) urls[t.id] = await viewUrl(k, 3600);
      }
      return json({ urls });
    }

    const tenantId = str(body.tenant_id, 40);
    if (!tenantId) throw new AppError("BAD_REQUEST");

    // Row-level security: this only finds the tenant if it belongs to the owner's hostel.
    const { data: tenant } = await owner.from("tenants")
      .select("id, hostel_id, phone, status, id_file_key, photo_key, hostels(name)")
      .eq("id", tenantId).maybeSingle();
    if (!tenant) throw new AppError("NOT_ALLOWED", 403);

    if (body.action === "file_url") {
      const key = body.kind === "photo" ? tenant.photo_key : tenant.id_file_key;
      if (!key) throw new AppError("NO_FILE", 404);
      return json({ url: await viewUrl(key, 300) });
    }

    if (body.action === "student_link") {
      if (["vacated", "rejected", "expired"].includes(tenant.status)) throw new AppError("NOT_ACTIVE");
      if (body.reset === true) {
        await admin.from("student_sessions").update({ revoked_at: new Date().toISOString() })
          .eq("tenant_id", tenant.id).is("revoked_at", null);
      }
      const token = randomToken();
      const { error } = await admin.from("student_sessions").insert({
        hostel_id: tenant.hostel_id,
        phone: tenant.phone,
        tenant_id: tenant.id,
        token_hash: await sha256Hex(token),
      });
      if (error) throw new AppError("SERVER_ERROR", 500);
      const url = `${APP_URL}/s/${token}`;
      if (body.sms === true) {
        // deno-lint-ignore no-explicit-any
        const hostelName = (tenant as any).hostels?.name ?? "My Hostel";
        await sendStudentLink(tenant.phone, hostelName, url);
      }
      return json({ url });
    }

    throw new AppError("BAD_ACTION");
  } catch (err) {
    return errorResponse(err);
  }
});
