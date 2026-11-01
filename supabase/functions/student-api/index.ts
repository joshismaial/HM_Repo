// Everything a student does after verifying their mobile. Deploy with --no-verify-jwt.
// The student's private token comes in the "x-student-token" header (never in the body or logs).
import { AppError, corsHeaders, errorResponse, json, normalizePhone, readJson, str } from "../_shared/http.ts";
import { admin, rpc } from "../_shared/db.ts";
import { sha256Hex } from "../_shared/crypto.ts";
import { checkImage, uploadUrl, viewUrl } from "../_shared/storage.ts";
import { sendStudentLink } from "../_shared/sms.ts";

type Session = { session_id: string; hostel_id: string; phone: string; tenant_id: string | null };

const APP_URL = (Deno.env.get("PUBLIC_APP_URL") ?? "").replace(/\/$/, "");

function isoDate(v: unknown): string | null {
  const s = str(v, 10);
  if (!s) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) throw new AppError("BAD_DATE");
  return s;
}

function method(v: unknown): "upi" | "bank" | "cash" {
  const m = String(v ?? "");
  if (m !== "upi" && m !== "bank" && m !== "cash") throw new AppError("BAD_METHOD");
  return m;
}

// Hostel photo as a 1-hour link (the key itself never goes to the app). Only keys inside the hostel's
// own photo folder are signed, so a wrong key can never expose another file.
async function hostelPhotoUrl(sid: string, hostelId: string): Promise<string | null> {
  try {
    const key = await rpc<string | null>("student_hostel_photo_key", { p_session: sid });
    if (!key || !key.startsWith(`hostels/${hostelId}/photo/`)) return null;
    return await viewUrl(key, 3600);
  } catch {
    return null;
  }
}

// Private link by SMS (never fails the request).
async function smsLink(session: Session, token: string) {
  try {
    const { data: h } = await admin.from("hostels").select("name").eq("id", session.hostel_id).single();
    if (APP_URL) await sendStudentLink(session.phone, h?.name ?? "My Hostel", `${APP_URL}/s/${token}`);
  } catch (e) {
    console.error("link SMS failed", (e as Error).message);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const token = req.headers.get("x-student-token") ?? "";
    if (token.length < 30) throw new AppError("SESSION_INVALID", 401);
    const session = await rpc<Session>("student_session_by_hash", { p_token_hash: await sha256Hex(token) });
    const sid = session.session_id;
    const body = await readJson(req);

    switch (body.action) {
      case "hostel": {
        const h = await rpc<Record<string, unknown>>("student_hostel", { p_session: sid });
        return json({ ...h, photo_url: await hostelPhotoUrl(sid, session.hostel_id) });
      }

      case "rooms":
        return json(await rpc("student_rooms", { p_session: sid }));

      case "hold":
        return json(await rpc("student_hold_bed", { p_session: sid, p_bed: str(body.bed_id, 40) }));

      case "hold_booked":
        // the bed the owner held and shared as a QR code (link has bed + one-time code)
        return json(await rpc("student_hold_booked_bed", {
          p_session: sid, p_bed: str(body.bed_id, 40), p_code: str(body.code, 40),
        }));

      // Phase 1: the student types their own room (floor, room no, sharing, price, deposit)
      case "room_lookup":
        return json(await rpc("student_room_lookup", { p_session: sid, p_room_no: str(body.room_no, 20) }));

      case "claim_room": {
        const int = (v: unknown) => {
          const n = Number(v ?? 0);
          if (!Number.isInteger(n) || n < 0) throw new AppError("BAD_AMOUNT");
          return n;
        };
        return json(await rpc("student_claim_typed_room", {
          p_session: sid,
          p_room_no: str(body.room_no, 20),
          p_floor: int(body.floor),
          p_sharing: int(body.sharing),
          p_rent: int(body.rent_month),
          p_deposit: int(body.deposit),
          p_existing: body.is_existing === true,
        }));
      }

      case "quote":
        return json(await rpc("student_quote", { p_session: sid }));

      case "upload_url": {
        // signed link to upload a compressed photo straight to private storage
        const fresh = await rpc<Session>("student_session_by_hash", { p_token_hash: await sha256Hex(token) });
        if (!fresh.tenant_id) throw new AppError("NO_BED_HELD");
        const kind = body.kind === "photo" ? "photo" : body.kind === "thumb" ? "thumb" : "id";
        const contentType = String(body.content_type ?? "image/jpeg");
        if (!/^image\/(jpeg|png|webp)$/.test(contentType)) throw new AppError("BAD_FILE_TYPE");
        const ext = contentType.split("/")[1].replace("jpeg", "jpg");
        const key = `hostels/${fresh.hostel_id}/tenants/${fresh.tenant_id}/${kind}-${crypto.randomUUID()}.${ext}`;
        return json({ key, url: await uploadUrl(key, contentType), content_type: contentType });
      }

      case "details": {
        const fresh = await rpc<Session>("student_session_by_hash", { p_token_hash: await sha256Hex(token) });
        if (!fresh.tenant_id) throw new AppError("NO_BED_HELD");
        const prefix = `hostels/${fresh.hostel_id}/tenants/${fresh.tenant_id}/`;
        const idKey = str(body.id_file_key, 200);
        const photoKey = str(body.photo_key, 200);
        // ID photo required; profile photo optional
        if (!idKey?.startsWith(prefix) || (photoKey && !photoKey.startsWith(prefix))) throw new AppError("FILES_REQUIRED");
        if (!(await checkImage(idKey)) || (photoKey && !(await checkImage(photoKey)))) throw new AppError("FILE_TOO_BIG_OR_MISSING");

        const parent = str(body.parent_phone, 20);
        if (!parent) throw new AppError("PARENT_PHONE_REQUIRED");
        if (!str(body.parent_name, 120)) throw new AppError("PARENT_NAME_REQUIRED");
        const reference = str(body.reference_phone, 20);
        const idType = String(body.id_type ?? "");
        if (!["aadhaar", "passport", "driving_licence"].includes(idType)) throw new AppError("BAD_ID_NUMBER");

        const result = await rpc<Record<string, unknown>>("student_submit_details", {
          p_session: sid,
          p_full_name: str(body.full_name, 120),
          p_parent_phone: parent ? normalizePhone(parent) : null,
          p_reference_phone: reference ? normalizePhone(reference) : null,
          p_id_type: idType,
          p_id_number: str(body.id_number, 30),
          p_id_file_key: idKey,
          p_photo_key: photoKey ?? null,
          p_home_address: str(body.home_address, 300),
          p_office_address: str(body.office_address, 300),
          p_is_existing: body.is_existing === true,
          p_joining_date: isoDate(body.joining_date),
          p_consent: body.consent === true,
          p_org_name: str(body.org_name, 160),
        });
        await rpc("student_set_names", {
          p_session: sid,
          p_parent_name: str(body.parent_name, 120),
          p_reference_name: str(body.reference_name, 120),
        });
        // existing tenants skip payment: send their private link now
        if (result.status === "pending_approval") await smsLink(session, token);
        return json(result);
      }

      case "pay": {
        const result = await rpc<Record<string, unknown>>("student_submit_payment", {
          p_session: sid,
          p_method: method(body.method),
          p_utr: str(body.utr, 40),
          p_paid_on: isoDate(body.paid_on),
        });
        // send the private link by SMS so the student can come back any time
        await smsLink(session, token);
        return json(result);
      }

      case "me": {
        const me = await rpc<Record<string, unknown>>("student_me", { p_session: sid });
        const extra = await rpc<Record<string, unknown>>("student_me_extra", { p_session: sid });
        me.tenant = { ...(me.tenant as Record<string, unknown>), ...extra };
        me.hostel = { ...(me.hostel as Record<string, unknown>), photo_url: await hostelPhotoUrl(sid, session.hostel_id) };
        // the student's own photo for the Home name band (small thumbnail first, full photo if none)
        try {
          const tid = (me.tenant as Record<string, unknown>).id as string | undefined;
          if (tid) {
            const { data: tp } = await admin.from("tenants").select("photo_thumb_key, photo_key").eq("id", tid).single();
            const key = (tp?.photo_thumb_key ?? tp?.photo_key) as string | null;
            if (key && key.startsWith(`hostels/${session.hostel_id}/tenants/${tid}/`)) {
              (me.tenant as Record<string, unknown>).photo_url = await viewUrl(key, 3600);
            }
          }
        } catch { /* initials instead */ }
        return json(me);
      }

      // small photo for the owner's lists, made on the phone (~100×100)
      case "set_thumb": {
        const fresh = await rpc<Session>("student_session_by_hash", { p_token_hash: await sha256Hex(token) });
        if (!fresh.tenant_id) throw new AppError("NO_BED_HELD");
        const key = str(body.key, 200);
        if (!key?.startsWith(`hostels/${fresh.hostel_id}/tenants/${fresh.tenant_id}/thumb-`)) throw new AppError("FILES_REQUIRED");
        if (!(await checkImage(key))) throw new AppError("FILE_TOO_BIG_OR_MISSING");
        return json(await rpc("student_set_thumb", { p_session: sid, p_key: key }) ?? {});
      }

      // Pay by cash → "When will you pay?" today / tomorrow / paid → the owner is told
      case "cash_plan": {
        const amount = Number(body.amount);
        if (!Number.isInteger(amount)) throw new AppError("BAD_AMOUNT");
        const plan = String(body.plan ?? "");
        if (!["today", "tomorrow", "paid"].includes(plan)) throw new AppError("BAD_PLAN");
        return json(await rpc("student_cash_plan", { p_session: sid, p_plan: plan, p_amount: amount }));
      }

      case "cancel_cash_plan":
        await rpc("student_cancel_cash_plan", { p_session: sid });
        return json({ ok: true });

      // message in Fees / Home stays until the student taps OK
      case "ack_message":
        await rpc("student_ack_message", { p_session: sid, p_message: str(body.id, 40) });
        return json({ ok: true });

      case "report_issue":
        return json({ id: await rpc("student_report_issue", {
          p_session: sid, p_category: str(body.category, 20), p_body: str(body.body, 500),
        }) });

      case "read_issue":
        await rpc("student_read_issue", { p_session: sid, p_issue: str(body.id, 40) });
        return json({ ok: true });

      case "cancel_notice":
        await rpc("student_cancel_notice", { p_session: sid });
        return json({ ok: true });

      case "ad_event":
        await rpc("student_ad_event", { p_session: sid, p_ad: str(body.id, 40), p_click: body.click === true });
        return json({ ok: true });

      case "pay_bill": {
        const amount = Number(body.amount);
        if (!Number.isInteger(amount)) throw new AppError("BAD_AMOUNT");
        return json(await rpc("student_pay_bill", {
          p_session: sid,
          p_method: method(body.method),
          p_utr: str(body.utr, 40),
          p_amount: amount,
          p_paid_on: isoDate(body.paid_on),
        }));
      }

      case "give_notice":
        return json(await rpc("student_give_notice", { p_session: sid, p_leaving_date: isoDate(body.leaving_date) }));

      default:
        throw new AppError("BAD_ACTION");
    }
  } catch (err) {
    return errorResponse(err);
  }
});
