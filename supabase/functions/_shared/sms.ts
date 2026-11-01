// SMS through MSG91 (DLT-approved templates are required in India).
// Set SMS_DEV_MODE=true while testing: nothing is sent, the OTP is always 123456 and messages are logged.

const DEV = Deno.env.get("SMS_DEV_MODE") === "true";
const AUTH_KEY = Deno.env.get("MSG91_AUTH_KEY") ?? "";

export const isDevMode = DEV;

async function sendFlow(templateId: string, phone: string, vars: Record<string, string>): Promise<void> {
  const mobile = phone.replace(/^\+/, ""); // 91XXXXXXXXXX
  if (DEV) {
    console.log(`[SMS_DEV_MODE] to ${mobile} template ${templateId}`, vars);
    return;
  }
  if (!AUTH_KEY || !templateId) throw new Error("SMS_NOT_CONFIGURED");
  const res = await fetch("https://control.msg91.com/api/v5/flow", {
    method: "POST",
    headers: { authkey: AUTH_KEY, "Content-Type": "application/json", accept: "application/json" },
    body: JSON.stringify({ template_id: templateId, short_url: "0", recipients: [{ mobiles: mobile, ...vars }] }),
  });
  if (!res.ok) {
    console.error("MSG91 error", res.status, await res.text());
    throw new Error("SMS_FAILED");
  }
}

// Template example: "##var1## is your My Hostel OTP. Valid for 5 minutes. Do not share it."
export function sendOtp(phone: string, code: string): Promise<void> {
  return sendFlow(Deno.env.get("MSG91_OTP_TEMPLATE_ID") ?? "", phone, { var1: code });
}

// Template example: "##var1##: your booking is received. Check status and pay rent here: ##var2##"
export function sendStudentLink(phone: string, hostelName: string, link: string): Promise<void> {
  return sendFlow(Deno.env.get("MSG91_LINK_TEMPLATE_ID") ?? "", phone, {
    var1: hostelName.slice(0, 30),
    var2: link,
  });
}

// Template example: "##var1##: rent of Rs.##var2## is due on ##var3##. Pay in your My Hostel app or link: ##var4##"
export function sendRentReminder(phone: string, hostelName: string, amount: number, dueDate: string, link: string): Promise<void> {
  return sendFlow(Deno.env.get("MSG91_REMINDER_TEMPLATE_ID") ?? "", phone, {
    var1: hostelName.slice(0, 30),
    var2: String(amount),
    var3: dueDate,
    var4: link,
  });
}

export function devOtp(): string | null {
  return DEV ? "123456" : null;
}
