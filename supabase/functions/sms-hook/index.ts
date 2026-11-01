// Supabase Auth "Send SMS" hook: sends owner sign-up / password-reset OTPs through MSG91.
// Supabase dashboard → Authentication → Hooks → Send SMS → HTTPS → this function's URL.
// Deploy with --no-verify-jwt (the request is checked with the hook secret instead).
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { sendOtp } from "../_shared/sms.ts";

const secret = (Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "").replace("v1,whsec_", "");

Deno.serve(async (req) => {
  const raw = await req.text();
  try {
    const wh = new Webhook(secret);
    const payload = wh.verify(raw, Object.fromEntries(req.headers)) as {
      user: { phone: string };
      sms: { otp: string };
    };
    const phone = payload.user.phone.startsWith("+") ? payload.user.phone : `+${payload.user.phone}`;
    await sendOtp(phone, payload.sms.otp);
    return new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("sms-hook failed", (err as Error).message);
    return new Response(
      JSON.stringify({ error: { http_code: 500, message: "Could not send SMS. Please try again." } }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
