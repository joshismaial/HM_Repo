// Student mobile verification (no login). Deploy with --no-verify-jwt.
// POST { action: "peek",   join_code, bed?, k?, start? } -> { hostel_name, is_open, city, owner_name, booking? }
//      start = true when the app opens on the bed: the 15-minute hold timer starts (once)
//      (bed + k come from the owner's "Share with student" QR: the held bed, rent and deposit)
// POST { action: "send",   join_code, phone }          -> { sent: true }
// POST { action: "verify", join_code, phone, code }    -> { token, tenant_status }
import { AppError, corsHeaders, errorResponse, json, normalizePhone, readJson } from "../_shared/http.ts";
import { admin, rpc } from "../_shared/db.ts";
import { randomOtp, randomToken, sha256Hex, timingSafeEqual } from "../_shared/crypto.ts";
import { devOtp, sendOtp } from "../_shared/sms.ts";

const OTP_TTL_MIN = 5;
const MAX_TRIES = 3;
const LOCK_MIN = 10;

async function findHostel(joinCode: unknown) {
  const code = String(joinCode ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{6,12}$/.test(code)) throw new AppError("HOSTEL_NOT_FOUND", 404);
  const { data, error } = await admin.from("hostels")
    .select("id, name, is_open, city, address, profiles(full_name)").eq("join_code", code).maybeSingle();
  if (error) throw new AppError("SERVER_ERROR", 500);
  if (!data) throw new AppError("HOSTEL_NOT_FOUND", 404);
  // deno-lint-ignore no-explicit-any
  const owner = (data as any).profiles?.full_name ?? null;
  return { id: data.id, name: data.name, is_open: data.is_open, city: data.city, address: data.address, owner_name: owner, code };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const body = await readJson(req);
    const hostel = await findHostel(body.join_code);
    const purpose = `join:${hostel.id}`;

    if (body.action === "peek") {
      let booking = null;
      const bed = String(body.bed ?? "");
      const k = String(body.k ?? "");
      if (/^[0-9a-f-]{36}$/i.test(bed) && /^[0-9a-f]{12,40}$/i.test(k)) {
        booking = await rpc("booking_peek", { p_join_code: hostel.code, p_bed: bed, p_code: k, p_start: body.start === true });
      }
      return json({ hostel_name: hostel.name, is_open: hostel.is_open, city: hostel.city, owner_name: hostel.owner_name, booking });
    }

    const phone = normalizePhone(body.phone);

    if (body.action === "send") {
      const since10 = new Date(Date.now() - LOCK_MIN * 60_000).toISOString();
      const since24h = new Date(Date.now() - 24 * 3600_000).toISOString();
      const { data: recent } = await admin.from("otp_codes")
        .select("created_at, attempts").eq("phone", phone).gte("created_at", since24h)
        .order("created_at", { ascending: false });
      const last10 = (recent ?? []).filter((r) => r.created_at >= since10);
      if (last10.some((r) => r.attempts >= MAX_TRIES)) throw new AppError("OTP_LOCKED", 429);
      if (last10.length >= 3 || (recent ?? []).length >= 10) throw new AppError("OTP_RATE_LIMIT", 429);

      const code = devOtp() ?? randomOtp();
      const { error } = await admin.from("otp_codes").insert({
        phone,
        purpose,
        code_hash: await sha256Hex(`${phone}:${purpose}:${code}`),
        expires_at: new Date(Date.now() + OTP_TTL_MIN * 60_000).toISOString(),
      });
      if (error) throw new AppError("SERVER_ERROR", 500);
      await sendOtp(phone, code);
      return json({ sent: true, expires_in: OTP_TTL_MIN * 60 });
    }

    if (body.action === "verify") {
      const code = String(body.code ?? "").replace(/\D/g, "");
      if (code.length !== 6) throw new AppError("OTP_WRONG", 400, { tries_left: MAX_TRIES });

      const { data: otp } = await admin.from("otp_codes")
        .select("*").eq("phone", phone).eq("purpose", purpose).is("consumed_at", null)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (!otp || new Date(otp.expires_at) < new Date()) throw new AppError("OTP_EXPIRED");
      if (otp.attempts >= MAX_TRIES) throw new AppError("OTP_LOCKED", 429);

      const ok = timingSafeEqual(otp.code_hash, await sha256Hex(`${phone}:${purpose}:${code}`));
      if (!ok) {
        const attempts = otp.attempts + 1;
        await admin.from("otp_codes").update({ attempts }).eq("id", otp.id);
        if (attempts >= MAX_TRIES) throw new AppError("OTP_LOCKED", 429);
        throw new AppError("OTP_WRONG", 400, { tries_left: MAX_TRIES - attempts });
      }
      await admin.from("otp_codes").update({ consumed_at: new Date().toISOString() }).eq("id", otp.id);

      const token = randomToken();
      const session = await rpc<{ tenant_status: string | null }>("student_start_session", {
        p_join_code: hostel.code,
        p_phone: phone,
        p_token_hash: await sha256Hex(token),
      });
      return json({ token, tenant_status: session.tenant_status });
    }

    throw new AppError("BAD_ACTION");
  } catch (err) {
    return errorResponse(err);
  }
});
