# My Hostel – test script (before launch)

How to use: run the app (VS Code → F5, phone/emulator for the owner, Chrome `http://localhost:5555/j/<JOINCODE>` for the student).
Tick each box. If a step does not give the result shown, write what you saw next to it and tell Claude.

Test mode (SMS_DEV_MODE=true): no SMS is sent.
- **Student OTP is always 123456.**
- **Owner OTP is random.** Ask Claude "read my owner OTP" and it reads it from the sms-hook log (or Dashboard → Edge Functions → sms-hook → Logs).

Use test numbers only (e.g. 9000000001 owner, 9000000002 student, 9000000003 second student).

## A. Owner account
- [ ] A1. Open the app. **Result:** Owner login screen, Create account button, language button.
- [ ] A2. Create account: name, owner mobile, a strong password, tick the terms, Send OTP. **Result:** OTP screen opens.
- [ ] A3. Enter a wrong OTP. **Result:** error, no login.
- [ ] A4. Enter the right OTP (from Claude). **Result:** you are signed in; first time goes to Register hostel.
- [ ] A5. Log out, then log in with mobile + password. **Result:** signed in, no OTP asked.
- [ ] A6. Log in with a wrong password. **Result:** "wrong login" message.
- [ ] A7. Forgot password → mobile → OTP → new password. **Result:** you can log in with the new password.

## B. Register hostel (short form)
- [ ] B1. Open Register hostel. **Result:** name, type chips, Location card "Are you at the hostel now?", one Create hostel button.
- [ ] B2. Tap Create hostel with nothing filled. **Result:** asks for the name / location, nothing saved.
- [ ] B3. Choose "No, type address": area, city, no pincode. Create hostel. **Result:** hostel is created, opens Home.
- [ ] B4. Create a second hostel with "Yes, use my location" (phone/emulator; allow location). **Result:** area/city/pincode filled, "Exact location saved", hostel created. (In Chrome the address lookup does not work: type it.)
- [ ] B5. Type a wrong pincode (5 digits). **Result:** pincode error.
- [ ] B6. My hostels shows both hostels.
- [ ] B7. Tap × on a hostel. **Result:** sheet "Remove …?" with 4 bullets; if tenants live there, an amber warning with the count.
- [ ] B8. Remove it. **Result:** hostel leaves My hostels; "Removed hostels (1)" link appears under the list. No error.
- [ ] B9. Open Removed hostels. **Result:** card with name, area, "Removed <date> · N tenants", Restore hostel.
- [ ] B10. Restore hostel → Restore hostel. **Result:** back on My hostels with the hostel shown; the Removed link is gone.
- [ ] B11. Remove your ONLY hostel. **Result:** Register hostel opens and shows "Restore a removed hostel (1)"; tapping it restores and returns to My hostels.
- [ ] B12. More → Hostel: the first row reads "Tenants/Students List", and "Removed hostels (n)" sits below Reports, only when at least one hostel is removed.

## C. Rooms and share link
- [ ] C1. Add a room (floor, sharing, rent, deposit). **Result:** room and its beds appear.
- [ ] C2. Open Invite / Share. **Result:** hostel join link and QR code. Copy the join code.

## D. Student joins (Chrome)
- [ ] D1. Open `http://localhost:5555/j/<JOINCODE>`. **Result:** hostel name, mobile field, Send OTP.
- [ ] D2. Tap Find my booking, enter student mobile, Send OTP. **Result:** "Enter the OTP" with six boxes.
- [ ] D3. Enter a wrong OTP three times. **Result:** tries left shown, then "Too many tries" with a 10-minute countdown.
- [ ] D4. (Wait 10 minutes or use another number.) Enter 123456. **Result:** verified, goes on to Your details.
- [ ] D5. Fill details (name, ID, photo, parent, consent). **Result:** moves to room selection.
- [ ] D6. Choose a bed. **Result:** the bed is held (15-minute timer visible).
- [ ] D7. Pay (cash or bank + UTR). **Result:** status "waiting for the owner".
- [ ] D8. Try paying a second joiner with the same UTR. **Result:** refused: UTR already used.

## E. Owner confirms or rejects
- [ ] E1. Owner app → Requests. **Result:** the joiner's card with details, amount, method, UTR; Reject and Confirm booking.
- [ ] E2. Reject → pick "Wrong details" → Reject. **Result:** student is told, the bed is free again, card disappears.
- [ ] E3. Student joins again (new bed hold + payment). Owner taps Confirm booking. **Result:** student becomes a tenant (Tenants list), bills created, bed shown as taken.
- [ ] E4. Wait 2 hours with a pending joiner (or ask Claude to check the job). **Result:** owner gets a "New joiner waiting" notification once.

## F. Rent and payments
- [ ] F1. Owner → Rent. **Result:** this month's bill for the tenant.
- [ ] F2. Record a cash payment. **Result:** bill becomes paid; student sees it.
- [ ] F3. Student pays rent with a UTR. **Result:** owner sees it in Requests; Received confirms it.
- [ ] F4. Owner taps Not received on a payment. **Result:** student gets the message.

## G. Other owner features
- [ ] G1. Complaints: student sends one, owner replies.
- [ ] G2. Notices: owner posts a notice, student sees it.
- [ ] G3. Staff: add, edit, remove one staff member.
- [ ] G4. Leaving: student gives notice, owner marks vacated with a deduction.
- [ ] G5. Language: switch English / Hindi / Telugu on every screen you visited. **Result:** no English left over, no cut-off text.

## H. Safety (ask Claude to check)
- [ ] H1. Owner B cannot see owner A's hostel or tenants (log in with a second account).
- [ ] H2. Security advisors show no new warnings.
- [ ] H3. The SQL tests in supabase/tests all pass.
- [ ] H4. Function logs show no errors after this run.

## I. Before the real launch
- [ ] I1. DLT registration approved; MSG91 template set.
- [ ] I2. SMS_DEV_MODE turned OFF; a real SMS OTP arrived on your own phone (owner and student).
- [ ] I3. Leaked-password protection turned on.
- [ ] I4. Phone provider + Send SMS hook checked in the dashboard.
- [ ] I5. Everything in PRE_LAUNCH.md done.
- [ ] I6. Full join + payment tested on a real phone (not the emulator).

## J. Student-first onboarding (Expo Go prototype only, 1 Nov 2026)
Start: Login screen → "Prototype: student-first flow".
- [ ] J1. Step 1 Student registers: enter hostel name, owner number twice. **Result:** Continue stays off until both match; a green "Matches" tag and the big number appear; the amber wrong-number warning is visible.
- [ ] J2. Type different numbers. **Result:** "The two numbers do not match."
- [ ] J3. Student OTP (123456), then name, room, sharing, rent. **Result:** no Aadhaar, college, parent or photo asked.
- [ ] J4. Dates screen: tick "same as joining date". **Result:** fee day shows the joining day. Untick: a 1–28 day grid appears.
- [ ] J5. Save. **Result:** status "Waiting for your owner", 90 days left, Edit my details, Change owner number, Invite my owner on WhatsApp. No Delete button.
- [ ] J6. Edit my details. **Result:** values prefilled; saving returns to the status.
- [ ] J7. Hub → Add 10 students three times (31 students). **Result:** backend SMS log shows ONE message when the count first reaches 25 ("25 students from your hostel are using My Hostel…"); none for 26–31. Add 25 more: one for 50.
- [ ] J8. Hub step 4: owner waiting list. **Result:** "N students are waiting for you", masked names, hostel name to confirm. Yes → every waiting student gets the message (SMS log).
- [ ] J9. Student status now shows "owner has joined"; open step 3 (message) → link → Complete your details (photo, Aadhaar number + copy, parent, reference, consent). Send to owner.
- [ ] J10. Owner list: Ready / Waiting counts; Waiting rows cannot be opened; "Send reminder" logs an SMS to waiting students.
- [ ] J11. Open a Ready student: details, masked Aadhaar, Reveal (logged), room/rent/dates editable. Verify and add as tenant. **Result:** student shows Added and appears in the Tenants list.
- [ ] J12. Send back for correction. **Result:** student goes back to Waiting and an SMS is logged.
- [ ] J13. Hub step 0 (First open). **Result:** "I am a..." Student / Hostel owner; Student goes to Join your hostel, Owner goes to owner sign-up with photo.
- [ ] J14. Step 4: owner sign-up has an Add your photo circle. On the waiting list, without a photo the Yes button is off and a photo box is shown.
- [ ] J15. After the owner confirms, the student's link first shows "Is this your owner?" with the photo and name. **Yes** goes to Complete your details. **No** shows "Nothing has been shared", and Change owner number or Send report.
- [ ] J16. Hub step 6 / owner "My account": "x of 3 students confirmed you". With 3 Yes it shows Verified (10 hostels, 500 reminders a day); before that, 2 hostels and 50 reminders.
- [ ] J17. Hub "2 students say No": the owner list shows the paused warning and Verify and add as tenant is off.

## Not built yet in Flutter (do not test yet)
- Student "Your booking" page (rejection reason on the student side).
- UPI payment with the 12 checks and receipt upload.
- Receipt purge job.
- One-screen owner sign-up, app logo.
