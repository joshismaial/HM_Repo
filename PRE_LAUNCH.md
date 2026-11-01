# My Hostel – pre-launch tracking

Last updated: 2 Nov 2026. Keep this file up to date: tick a box when an item is done, and add the date.

---

## 1. Must change before launch

Status: `[ ]` open · `[x]` done

### Code changes
- [ ] **1. Make the leaving date strict (server side).**
  `student_give_notice` (migration `20261022000001_waiting_for_flutter.sql`) still accepts a leaving date from the phone, so a changed app could send an earlier date.
  Fix: ignore the date from the phone and always use the next fee date (`private.next_fee_date`).
- [ ] **2. Decide: keep "Delete my data" as an email request, or automate it.**
  `REQUIREMENTS.md` says it sends an email request for now (not a gap). The Expo prototype already shows the owner alert flow (`requestDataDelete` in `state.js`); the database has no function for it.
  Decide before launch whether email is enough.

### Checks and tests (nothing has run for real yet)
- [ ] **3. Refund message for the owner.**
  The app only records the deposit refund amount; the owner pays it outside the app. Make the owner's "Mark vacated" screen say so clearly.
- [ ] **4. First real run on the developer machine.**
  - Build the Flutter app and run `check_app.bat`.
  - Run the tests in `supabase/tests`.
  - Test with a real phone and real SMS: give notice, cancel notice, owner marks vacated.
  - Run and test the Edge Functions (never run yet).
- [ ] **5. Confirm the file-deletion job runs.**
  Photos, ID copies and ID numbers are deleted 3 months after the student is marked vacated (`files_to_purge` / `mark_files_purged`). Make sure the scheduled job that calls them is actually set up, and test it with a short date.

### Before the Play Store launch
- [ ] **6. SMS (OTP) template.**
  Ask the SMS provider for a DLT template that works with Android auto-read (the SMS must end with the app's 11-character code). Do not ask for the `READ_SMS` permission; Google Play rejects most apps that use it.

### Police portal (separate repo `PM_Repo`) – before police use it
Database scripts are run and the portal works locally (tested 2 Nov 2026 with officer `HYD-SI-2043`).
- [ ] **7. Fix officer `HYD-SI-2041`.**
  Its mobile (ending 077) is an owner account that owns a hostel. Logging in as 2041 would replace that owner's app password.
  Change its number or delete it: `update public.police_officers set phone = '+91XXXXXXXXXX' where officer_id = 'HYD-SI-2041';`
- [ ] **8. Real SMS.**
  Turn off `SMS_DEV_MODE` and add the MSG91 keys + DLT templates in Supabase (same as item 6). Until then, OTPs only appear in the `sms-hook` logs.
- [ ] **9. Put the portal online (Vercel).**
  Deploy `PM_Repo` with the three keys from `.env.local`, so police use a web address instead of the developer's computer.
- [ ] **10. Real station names for each officer.**
  `update public.police_officers set station = '…' where officer_id = '…';`
- [ ] **11. Police approval and legal check.**
  Written approval from the police department, and a lawyer's check of police access to student data (privacy policy / DPDP), before any officer uses it.

---

## 2. My tests – failed, and suggestions

### 2a. Tests that failed
Add one row per failure. Move the row to "Fixed" when done.

| # | Date | Screen / feature | What I did | What happened | What I expected | Status |
|---|------|------------------|------------|---------------|-----------------|--------|
| 1 | 28 Oct 2026 | Database test `01_flow_test.sql` | Ran the test on a scratch database | Stops at "rent partly paid" (and, after that is patched, at `BAD_AMOUNT` in `record_payment`) | The whole test passes | Open |

Note on #1: not a database bug. The test joins a student "today", so the first rent bill is pro-rated by the day of the month; near the 5th-of-month rent day (e.g. 28 Oct) 8000 pays the deposit and the whole first rent, so the test's "partly paid" expectation fails. It passed on 12 Oct. Fix: make the test's amounts independent of the date. The same scratch run gives the same result with and without the 28 Oct migration.

### 2b. Suggestions and ideas
Add one row per idea.

| # | Date | Suggestion | Why | Priority (High / Medium / Low) | Status |
|---|------|------------|-----|--------------------------------|--------|
| 1 | 27 Oct 2026 | Add true OTP auto-read in Flutter (Android SMS Retriever). The keyboard suggestion is already in the Expo prototype. | Fewer typing mistakes and fewer locked screens. Depends on item 6 above. | Medium | Open |

### 2c. Fixed
| # | Date fixed | What was fixed |
|---|------------|----------------|
|   |            |                |
