// Shared HTTP helpers for all Edge Functions.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-student-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class AppError extends Error {
  constructor(public code: string, public status = 400, public extra: Record<string, unknown> = {}) {
    super(code);
  }
}

// Error codes raised by the database functions -> HTTP status
const STATUS_BY_CODE: Record<string, number> = {
  SESSION_INVALID: 401,
  NOT_ALLOWED: 403,
  HOSTEL_NOT_FOUND: 404,
  BED_NOT_FOUND: 404,
  NO_BOOKING: 404,
  BED_TAKEN: 409,
  HOLD_EXPIRED: 409,
  ALREADY_JOINED: 409,
  DUPLICATE_UTR: 409,
  TOO_MANY_PENDING: 429,
  OTP_LOCKED: 429,
  OTP_RATE_LIMIT: 429,
};

// Turn a database error message into a short code the app understands.
export function toAppError(message: string | undefined): AppError {
  const code = (message ?? "").trim().split(/\s/)[0];
  if (/^[A-Z_]{4,40}$/.test(code)) {
    return new AppError(code, STATUS_BY_CODE[code] ?? 400);
  }
  console.error("Unexpected error:", message);
  return new AppError("SERVER_ERROR", 500);
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function errorResponse(err: unknown): Response {
  const e = err instanceof AppError ? err : toAppError((err as Error)?.message);
  return json({ error: e.code, ...e.extra }, e.status);
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    return body && typeof body === "object" ? body as Record<string, unknown> : {};
  } catch {
    throw new AppError("BAD_REQUEST");
  }
}

// Indian mobile numbers: accept 10 digits, 91XXXXXXXXXX or +91XXXXXXXXXX; return +91XXXXXXXXXX.
export function normalizePhone(input: unknown): string {
  const digits = String(input ?? "").replace(/\D/g, "");
  const ten = digits.length === 12 && digits.startsWith("91") ? digits.slice(2) : digits;
  if (!/^[6-9]\d{9}$/.test(ten)) throw new AppError("BAD_PHONE");
  return `+91${ten}`;
}

export function str(v: unknown, max = 300): string | null {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  if (s.length === 0) return null;
  if (s.length > max) throw new AppError("TOO_LONG");
  return s;
}
