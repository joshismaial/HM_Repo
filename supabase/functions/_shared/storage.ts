// Private file storage for student ID copies and photos (decided 20 Oct 2026: Phase 1 uses Supabase Storage only).
// Files are never public: the app only gets short-lived signed links to upload or view them.
// Bucket "student-files" (private) is created automatically the first time it is needed.
// Files: hostels/<hostel id>/tenants/<tenant id>/id-<uuid>.jpg and photo-<uuid>.jpg
import { admin } from "./db.ts";

const BUCKET = "student-files";
export const MAX_IMAGE_BYTES = 2 * 1024 * 1024; // the app compresses photos to ~200–300 KB

let bucketReady = false;
async function bucket() {
  if (!bucketReady) {
    // private bucket, only images up to 2 MB; "already exists" is fine
    await admin.storage.createBucket(BUCKET, {
      public: false,
      fileSizeLimit: MAX_IMAGE_BYTES,
      allowedMimeTypes: ["image/jpeg", "image/png", "image/webp"],
    });
    bucketReady = true;
  }
  return admin.storage.from(BUCKET);
}

/** Signed link the app uses to upload one file (PUT). */
export async function uploadUrl(key: string, _contentType: string): Promise<string> {
  const { data, error } = await (await bucket()).createSignedUploadUrl(key);
  if (error || !data) throw new Error("UPLOAD_URL_FAILED");
  return data.signedUrl;
}

/** Signed link to view one file for a short time (default 5 minutes). */
export async function viewUrl(key: string, seconds = 300): Promise<string> {
  const { data, error } = await (await bucket()).createSignedUrl(key, seconds);
  if (error || !data) throw new Error("VIEW_URL_FAILED");
  return data.signedUrl;
}

/** Checks an uploaded file exists, is an image and is not too big. */
export async function checkImage(key: string): Promise<boolean> {
  try {
    const slash = key.lastIndexOf("/");
    const name = key.slice(slash + 1);
    const { data } = await (await bucket()).list(key.slice(0, slash), { search: name });
    const f = (data ?? []).find((x) => x.name === name);
    // deno-lint-ignore no-explicit-any
    const meta = (f?.metadata ?? {}) as any;
    const size = Number(meta.size ?? 0);
    return size > 0 && size <= MAX_IMAGE_BYTES && String(meta.mimetype ?? "image/").startsWith("image/");
  } catch {
    return false;
  }
}

export async function deleteKeys(keys: string[]): Promise<void> {
  for (let i = 0; i < keys.length; i += 1000) {
    const chunk = keys.slice(i, i + 1000);
    if (chunk.length) await (await bucket()).remove(chunk);
  }
}

async function listAll(prefix: string): Promise<string[]> {
  const dir = prefix.replace(/\/$/, "");
  const out: string[] = [];
  const { data } = await (await bucket()).list(dir, { limit: 1000 });
  for (const item of data ?? []) {
    const path = `${dir}/${item.name}`;
    if (item.id) out.push(path); // a file
    else out.push(...await listAll(path)); // a folder
  }
  return out;
}

/** Deletes every file under a folder, e.g. "hostels/<id>/". Returns how many were deleted. */
export async function deletePrefix(prefix: string): Promise<number> {
  const keys = await listAll(prefix);
  await deleteKeys(keys);
  return keys.length;
}
