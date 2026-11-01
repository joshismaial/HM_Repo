# My Hostel – setup and run (Phase 1)

Owner app for Android + student web pages, built with Flutter and Supabase.
Read `REQUIREMENTS.md` first – every rule in it applies.

```
supabase/
  migrations/   database tables, functions, security rules, scheduled jobs
  functions/    server (Edge) functions: student-otp, student-api, owner-actions, sms-hook, purge-files
  tests/        database test (runs the whole join → pay → confirm → vacate flow)
app/            Flutter app (owner screens + student screens in one codebase)
```

You need: [Flutter](https://docs.flutter.dev/get-started/install) (stable), [Supabase CLI](https://supabase.com/docs/guides/cli),
a Supabase project and an MSG91 account (for real SMS).

---

## 1. Database (Supabase)

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push            # creates tables, functions, security rules
```

Then in Supabase → **SQL editor**, run once (use your own long random key and keep a copy safe –
without it, saved ID numbers can't be read):

```sql
insert into private.settings (name, value) values ('id_encryption_key', '<a long random secret>');
```

Scheduled jobs: Supabase → **Database → Extensions** → enable `pg_cron`, then run `supabase db push` again
(or re-run the end of `20261011000003_security.sql`). It frees expired bed holds every minute and makes
rent bills every morning (06:00 IST).

## 2. Logins for owners (Supabase Auth)

1. **Authentication → Providers → Phone**: turn on. Turn on "Confirm phone".
2. **Authentication → Hooks → Send SMS hook**: type HTTPS, URL
   `https://<project-ref>.supabase.co/functions/v1/sms-hook`. Copy the secret it shows (`v1,whsec_…`).
   With this hook, Supabase sends owner OTPs through MSG91 (no Twilio needed).
3. Students never use Supabase Auth (see REQUIREMENTS – no student login).

## 3. Server functions

Set the secrets (Supabase → **Edge Functions → Secrets**, or the CLI):

```bash
supabase secrets set \
  SMS_DEV_MODE=true \
  PUBLIC_APP_URL=https://<your student web address> \
  ALLOWED_ORIGIN=https://<your student web address> \
  SEND_SMS_HOOK_SECRET='v1,whsec_...' \
  MSG91_AUTH_KEY=... MSG91_OTP_TEMPLATE_ID=... MSG91_LINK_TEMPLATE_ID=...
```

`SMS_DEV_MODE=true` means no SMS is sent and every OTP is **123456** – use it only while testing.
Set it to `false` before real use.

Deploy:

```bash
supabase functions deploy student-otp  --no-verify-jwt
supabase functions deploy student-api  --no-verify-jwt
supabase functions deploy sms-hook     --no-verify-jwt
supabase functions deploy owner-actions
supabase functions deploy purge-files
```

(`--no-verify-jwt` only for the student and SMS-hook functions: students have no login, and they are
checked with their private token instead.)

Daily clean-up (deletes ID copies/photos 3 months after a tenant leaves, and owner accounts 7 days after
a deletion request): Supabase → **Integrations → Cron** → new job, daily, type "Supabase Edge Function",
function `purge-files`, header `Authorization: Bearer <service role key>`.

## 4. Photo and ID storage (Supabase Storage)

Student ID copies and photos are kept in the private Supabase Storage bucket `student-files`
(created automatically by the server functions the first time a student uploads). Files are never
public; the app only gets 5-minute signed links. Nothing to set up.

## 4b. Testing on this computer (Windows)

- `setup-database.bat` – links this folder to your Supabase project and uploads the database.
- `deploy-functions.bat` – switches on the server functions in test mode (no SMS, every OTP is 123456).
- `run-app.bat` – runs the app in Chrome at http://localhost:5555 (copied outside OneDrive first). For testing,
  the student joining pages also work in Chrome: open your hostel's join link (`http://localhost:5555/j/<CODE>`)
  in a new tab.

## 5. SMS (MSG91, India)

Register two DLT templates and create MSG91 "flows" for them:

- OTP: `Your My Hostel OTP is ##var1##. Valid for 5 minutes. Do not share it.`
- Private link: `Welcome to ##var1##. Your stay, bills and receipts: ##var2## - My Hostel`

Put the flow/template IDs in `MSG91_OTP_TEMPLATE_ID` and `MSG91_LINK_TEMPLATE_ID`.

## 6. Flutter app

```bash
cd app
flutter create . --platforms=android,web --project-name my_hostel   # adds android/ and web/ folders (keeps our files)
flutter pub get
flutter gen-l10n
flutter test
```

Run (owner app on an Android phone/emulator):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key> \
  --dart-define=PUBLIC_APP_URL=https://<your student web address>
```

Run the student pages in Chrome: same command with `-d chrome`, then open `/j/<JOIN CODE>`
(the join code is shown in Hostel settings and in the join QR link).

Build:

```bash
flutter build apk --release   --dart-define=...   # owner app (Play Store needs: flutter build appbundle)
flutter build web --release   --dart-define=...   # student pages → build/web
```

## 7. Hosting the student pages

Upload `app/build/web` to Cloudflare Pages, Vercel or Netlify. Every path must fall back to `index.html`
(single-page app), otherwise QR links like `/j/ABCD2345` show "not found":

- Cloudflare Pages / Netlify: `app/web/_redirects` (included) does this.
- Vercel: `vercel.json` with `{ "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }`.

Use the same address for `PUBLIC_APP_URL` and `ALLOWED_ORIGIN`.

## 8. Before launch – checklist

- [ ] `SMS_DEV_MODE=false`, DLT templates approved.
- [ ] `id_encryption_key` set and backed up.
- [ ] Privacy policy and Terms reviewed by a lawyer; fill [DATE], [X] years, grievance officer, [City]
      (texts are in `app/lib/l10n/app_*.arb`, keys starting with `pp` and `tm`).
- [ ] Support e-mail in `app/lib/screens/owner/more_screen.dart` (`supportEmail`).
- [ ] Owners use a business / merchant UPI ID (personal UPI IDs can get limits for regular rent collection).
- [ ] App icon and Play Store listing; "Delete account" link in the listing.

## 9. Testing the database locally (optional)

The database test needs a local PostgreSQL 15+ with `pgcrypto`:

```bash
createdb hm_test
psql hm_test -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do psql hm_test -v ON_ERROR_STOP=1 -f "$f"; done
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/01_flow_test.sql    # ends with ALL_TESTS_PASSED
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/02_rent_tab_test.sql
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/03_student_app_test.sql
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/04_tenant_rooms_test.sql  # rooms entered by tenants
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/05_hostel_settings_test.sql  # hostel settings
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/06_settings_changes_test.sql  # sharing change, fee date change, notice period, add room
psql hm_test -v ON_ERROR_STOP=1 -f supabase/tests/07_staff_test.sql  # staff page (owner only)
```

## What's in Phase 1

Owner: sign up (one OTP), login, forgot password · register hostels, My hostels · rooms & beds (incl. beds
of tenants not yet on the app) · hostel settings (rent day, notice period, UPI / bank / cash, amenities,
house rules) · Requests (confirm payments with amount received, approve existing tenants, reject) ·
Tenants and tenant details (masked ID + Reveal, ID/photo, payments, Record payment, reset student link,
mark vacated with deposit) · Rent tab (this month, pending, WhatsApp reminder, Record) · Rooms board ·
Home (stats, needs attention, setup checklist, join QR) · Privacy & Terms · Delete account.

Student (web, no login): verify mobile (OTP) → hostel details → rooms (15-minute bed hold) → details
(new joiner / already staying) → payment (UPI link with amount + note, bank, cash, UTR, duplicate UTR
blocked, refund policy) → submitted · private link page: My stay (bill, Pay now, receipts, give notice) and
Pay rent.

Languages: English, Hindi, Telugu. Phase 2 and 3 items are listed in `REQUIREMENTS.md`.
