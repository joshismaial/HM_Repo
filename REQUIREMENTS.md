# My Hostel – Requirements & Decisions

Follow every point in this file while developing the app.
Screen designs: "My Hostel App Screens" canvas (36 screens incl. error & empty states; student screens shown in an iPhone frame, owner screens in an Android frame) – https://claude.ai/artifact/JcknZzzXwZJBAVZ4K5g9Ph

## How we build (decided 19 Oct 2026)
- New changes are made in **expo-prototype only** (tested in Expo Go). Sample screens are still shown and confirmed before building.
- Every prototype change is added to "Waiting for Flutter" below.
- When the owner says **"move to Flutter"**, the whole list is built in the Flutter app (and Supabase where needed) in one go, then the list is cleared.
- Changes up to 22 Oct 2026 are in both (moved to Flutter on 22 Oct 2026).

### Waiting for Flutter
- **Login screen** (24 Oct 2026): see "Login (24 Oct 2026)". No Owner / Staff tabs – the server tells staff apart by mobile number.
- **Create owner account – one screen** (24 Oct 2026): see "Create owner account (24 Oct 2026)". Sign-up and the first hostel are saved together; no separate Register hostel step after sign-up.
- **Register hostel – short form** (24 Oct 2026): see "Register hostel (24 Oct 2026)". Flutter needs `hostels.latitude` / `hostels.longitude` (numeric, nullable), phone location permission (`geolocator` + `geocoding` packages; no map, no Google key), address made of optional house/street + area + city + optional pincode, and the floors / photos / contact / "Save & add another hostel" parts removed from this screen.

- **App logo** (24 Oct 2026): see "App logo (24 Oct 2026)". Flutter needs the launcher icon (adaptive icon, coral background), splash image, and the logo on Login and My hostels.
- **New joiner confirmation** (25 Oct 2026): see "New joiner confirmation (25 Oct 2026)". Owner request card with details + payment and one Confirm booking button; Reject needs a reason; student booking status page with Call owner; bed kept (hidden from Rooms) while waiting; 2-hour reminder to the owner (server job).
- **Free UPI payments with checks** (25 Oct 2026): see "Payments – free UPI with checks". Flutter needs: UPI intent with our transaction reference and reading the UPI app's reply (UTR, status), share target for receipt images, system photo picker, on-device text reading (e.g. ML Kit), the 12 checks on the server, all payments in Home › Confirm payments (Confirm / Received / Not received), receipt storage 7 days server / 90 days owner phone, removal of the Pay online option.

### Moved to Flutter (22 Oct 2026)
All 19 items that were waiting are now built in Flutter + Supabase: hostel photo, new student Home (name band, 4-state fee card, ad space, Notice, Wi-Fi and Leaving? tiles), student tabs Home · Fees · Report issue · Settings, ads table (admin only), Fees pay options (Pay online sheet, Done – I have paid, Pay by cash with Today / Tomorrow / Already paid), student Settings, default owner message + owner Notice to students, cash plans + Cash received / Not received, extra charge per day, owner Rent tab tidy, late fee card in Hostel settings, student photo thumbnails (made on the phone), owner ↔ student gap fixes (messages until OK, numbers on tabs, house rules list, Instant online pay switch, vacate notice on the next fee date + Cancel), Trust blue look, new owner Home, "Name – Type" hostel names, tidy-up, part payments.
- Database: migration `20261022000001_waiting_for_flutter.sql` (+ test `08_waiting_for_flutter_test.sql`). Edge Functions `student-api` and `owner-actions` updated.
- Not live yet in Flutter: **Instant online pay** (Razorpay) – the option shows when the owner turns it on, but tapping it says "coming soon" until a Razorpay account is connected (Phase 2). **Delete my data** still sends an email request. Ads are added by the app admin directly in the database (admin page not built).
- Fee card "paid" state shows when nothing is due and the next fee is more than 7 days away; otherwise the blue "Next fee · N days left" state.

## Login (24 Oct 2026)
- Language button top right · centred **app logo** (96 px, rounded) – the logo already says My Hostel, so no separate title – then "Owner and staff login".
- **Mobile number** box with a phone icon and +91 · **Password** box with a lock icon and eye (both 50 px, no labels above).
- **Forgot password?** (right) · **Log in** · thin "or" line · **Create owner account** (outline button).
- At the bottom: small "Student? Scan your hostel's QR code" line and **Privacy policy · Terms of use**. Expo only: "Prototype: open as a student".
- **No Owner / Staff tabs.** One login for both: if the mobile number belongs to a staff member the owner added (More → Staff), the staff view opens with only their duties; otherwise the owner view. Staff first log in with an OTP and set their own password (staff login part 2).

## App logo (24 Oct 2026)
- Coral gradient square (`#FB7154` → `#DC3C46`), white **house outline** with **My** inside and **Hostel** below, in **Lora** bold (serif, free for commercial use). No roof line, no police/government symbols, no badges or "Free/#1" text.
- Used as: phone app icon (Android adaptive icon, logo kept inside the circle-safe area), splash screen (white logo on coral), Play Store icon (512×512 PNG), Login (96 px) and My hostels header (44 px, left of "Hi … / My hostels").
- App name on Play can be "My Hostel"; the logo is the part that makes it different from other "My Hostel" apps.

## Create owner account (24 Oct 2026)
One screen creates the owner account **and** the first hostel ("You and your hostel, on one screen"):
- Fits one screen (24 Oct 2026): slim boxes (42 px high, 14 px text, 8 px apart), cards with 12 px padding, small subtitle and terms line.
- **YOU** card: Your name · Mobile number (+91) with **Send OTP** → **6-digit OTP** with **Verify** ("Resend in 30s" / Resend OTP) → after Verify the OTP box goes and the mobile shows a green **Verified** · **Password** (at least 6) · **Confirm password** (eye icon on both; "Passwords do not match" under Confirm).
- **YOUR HOSTEL** card: Hostel name · Type (Men's / Women's / Co-living) · Full address (house, street, area) · City · Pincode (6 digits).
- No location, floors, photos, contact number or language on this screen (language stays on the login screen's button).
- One button **Create account** → saves both and opens the new hostel. "Already have an account? Log in" and the Terms / Privacy line at the bottom.
- Adding more hostels later uses Register hostel (below).
- Rule (24 Oct 2026): new changes go to the Expo prototype only; ask the owner before changing Flutter.

## Register hostel (24 Oct 2026)
Owners won't spend time on setup; students type their own rooms (see "Rooms entered by tenants"). The screen asks only:
- **Hostel name** and **Type** (Men's / Women's / Co-living chips).
- **Location** card: "Are you at the hostel now?" with two buttons:
  - **Yes, use my location** → the phone's location saves the exact point (latitude / longitude, never shown to the owner) and fills area, city and pincode. Shows a green "Exact location saved · Madhapur, Hyderabad 500081" line with **Change**, then **House / street (optional)**.
  - **No, type address** → Area, City, Pincode (optional) and House / street (optional), plus a small "At the hostel now? Use my location" link.
  - If location is refused or fails, the owner types the address. No map (decided 24 Oct 2026: keep it simple).
- One button **Create hostel**. Removed from this screen: Floors, Add hostel photos (added from the My hostels card), Hostel contact number (= owner's login number, changeable in Hostel settings), "Save & add another hostel" (My hostels already has Add hostel).
- Later: the saved point gives students a **Directions** button on the hostel page.

## Build phases (follow this order)
Build Phase 1 completely before starting Phase 2. Do not add Phase 2/3 features to Phase 1 code unless asked.

### Phase 1 – launch with real hostels (Android owner app + student web pages)
- Platforms: ONE Android app (Flutter) for owners and students. Students install it from the hostel QR (every student install counts as a Play Store download). The web page only shows "Get the app" (no joining in the browser). No iPhone app yet.
- Owner: sign up (one OTP) and login (mobile + password), forgot password (OTP); register hostel (multiple hostels); My hostels; add rooms & beds (mark beds already occupied by tenants not yet on the app); hostel settings: rent day (same as joining date / fixed day), notice period, payment options (UPI with amount + note filled in, bank, cash), amenities, house rules.
- Student joining flow: verify mobile (OTP) → hostel details → available rooms (15-minute bed hold) → your details incl. new joiner / already staying here (past joining date) → payment (monthly stay; UPI / bank / cash; UTR; duplicate UTR blocked; refund policy agreement) → submitted.
- Owner: Requests (confirm payments with amount received, approve existing tenants, reject), Tenants list + tenant details (masked ID with Reveal, view ID/photo, payments, Record payment, reset student link, mark vacated & deposit), Rent tab (this month, pending list, WhatsApp reminder, Record payment), Rooms (occupancy board), Home (stats, needs attention, join QR / link).
- Student after joining: My stay (bill, Pay now, receipts, give notice) and Pay rent.
- Rooms entered by tenants (Phase 1 only, see "Rooms entered by tenants" below): students type floor, room, sharing, price and deposit in Your details; the owner checks them in More → Rooms from tenants and Hostel settings → Price by sharing.
- Privacy policy, Terms, Delete account (store requirement), error & empty states.
- Languages: English, Hindi, Telugu.

### Phase 2 – after 1–2 months with real hostels
- Online payment gateway (auto-confirm; needs each owner's KYC with the gateway).
- Complaints (Report an issue + owner Complaints), extra charges (electricity, laundry), day-wise stays and Extend stay.
- Reports with charts, staff logins (moved to Phase 1 – see "Staff"), notifications screen (bell), app settings (notification switches, app lock, theme), push notifications.

### Phase 3
- iPhone app for students, remaining languages (Tamil, Marathi, Kannada, Bengali), police verification form.
- Room change, rent increase notice, expenses, owner web dashboard, Plan & billing (how the app earns).

## Where data is stored (confirmed 19 Oct 2026)
- Hostel photos: Supabase Storage, private bucket `hostel-photos` (see "Hostel short name & photo").
- Photo store (Supabase Storage, private bucket `student-files`; decided 20 Oct 2026: Phase 1 uses Supabase only, no Cloudflare R2): student photo and ID proof only. Opened with short-lived links; ID copies deleted 3 months after the student leaves.
- Later, if the app grows (many hostels), files may move to Cloudflare R2 (free downloads, cheaper per GB). On that day either (a) copy all old files to R2 once with a copy job, then switch, or (b) remember per file which store it is in. Decide then.
- Details database (Supabase): student details (name, parent name, mobiles, reference, addresses, joining date, room, bed, rent, payments) and hostel details. Only the file key of each photo is saved next to the student.

## Tech stack
- App: Flutter (Android + iOS)
- Database, owner/staff login, backend logic: Supabase (PostgreSQL, Auth, Edge Functions)
- ID proofs and student photos: Supabase Storage private bucket `student-files`, signed URLs only (Phase 1; R2 only if the app grows – see "Where data is stored")
- Notifications: Firebase Cloud Messaging (free push notifications)
- Online payments (optional per hostel): a payment gateway with UPI/cards and webhooks for auto-confirmation
- Owner web dashboard (optional): Next.js on Vercel
- Code hosting: GitHub
- Start on free tiers

## Languages
- English, Hindi, Telugu, Tamil, Marathi, Kannada, Bengali.
- Students choose it at the top of the verify-mobile screen; owners on the login screen, at sign-up or in Hostel settings; changeable any time.
- All app text must come from translation files (no hard-coded strings).

## One app, two modes
- A single Flutter app (one Play Store / App Store listing, one codebase). No "I'm a student / I'm an owner" choice screen.
- Student screens open ONLY from a hostel's QR code or join link (Android App Link into the app; if the app isn't installed, a "Get the app" web page), or from a student's saved access key / private link.
- Opening the app normally (no link) shows the Owner login screen, with a note: "Student? Scan your hostel's QR code or open the link your hostel sent you."
- Owner/staff mode: login with mobile number + password.
- Student mode: no login (see "Student access").

## Student app: QR → install → join (decided)
- Goal: every student installs the app from Google Play, so installs count as store downloads. No "continue in browser" option.
- QR / join link (same link as before, e.g. myhostel.app/j/CODE?bed=…&k=…):
  - App installed → Android opens the app straight on that hostel / bed (App Links; assetlinks.json on the web host).
  - Not installed → **Get the app** web page: hostel name and area, the held bed (room, bed, sharing, rent, deposit — no "to pay now"), a big **Get the My Hostel app** button (Google Play), the 3 steps (Install · It opens on this bed · Verify, add details & pay) and "the 15-minute timer starts when you open the app".
  - The Play Store link carries the join code and bed (install referrer), so after installing the app opens directly on that bed (first launch only).
- Bed hold: the owner's QR hold lasts 60 minutes (time to install); the student's 15 minutes start when the app first opens on the bed.
- Google Play only in Phase 1 (no iPhone app).
- Two ways to book a bed — both use the same Play Store link:
  1. **Owner / staff books**: taps Book on a free bed and shows its QR → the bed is already chosen, so **no room selection** (4 steps).
  2. **Student scans the office QR** (hostel QR) → picks the room and bed in the app (5 steps).
- Get the app page: "Welcome! You've been invited by <owner> to join", hostel card (name, area; the held bed if owner-booked), **Get it on Google Play**.
- App screens: **Welcome** (hostel name + owner, held bed and 15-minute timer if owner-booked) with the **Student registration** button below it, and "Already joined? Find my booking" → **Verify mobile** (one OTP) → **Student Details Entry** (folder design: "Full name * : …" rows; **Save & Submit** enabled only when every * field is filled) → **Student Profile** (check details, View Aadhaar card, Edit) → [scan path only: **Room Selection** — floor and sharing filters, room grid (free / selected / full), bed chips, fee details for that sharing (set by the owner), agree to terms, **Confirm and proceed to payment** (holds the bed 15 minutes)] → **Choose payment** (options the owner turned on) → **Booking submitted** (room, date of joining, next fee date, amount; "owner will confirm") → **Go to Home**.
- **The owner must verify every booking** (payment and details) before the stay starts.
- Scan path: details and photos stay on the phone until the bed is held, then they are uploaded and submitted.
- Student home tabs (20 Oct 2026): **Home** (name band, fee card, ad space, Wi-Fi, leaving/vacate notice, owner notices) · **Fees** (bill, pay, receipts) · **Report issue** (send an issue + my issues with status; replaced the "My room" tab) · **Settings** (see "Student Settings"). No Call / WhatsApp owner buttons in the student app. Student details are locked after submitting (owner edits them).
- **Wi-Fi** (owner → Hostel settings → Wi-Fi for students): add / edit / delete networks for the whole hostel or one floor (up to 50). Students see the whole-hostel networks and their own floor's, with copy buttons, only while staying (active or on notice).
- Not now (decided): room change requests and student self-edit of details.
- Student details fields: profile photo with pen (optional); full name*, mobile (verified), Aadhaar number* ("No Aadhaar? Use another ID" → passport / driving licence), address*; parent name*, parent mobile*; reference name and mobile (optional); college / company name*, address (optional); ID card photo upload* (on the form, not the keyboard); house rules + "I accept"; DPDP consent.
- The amount to pay is shown only on the payment step.

## Colours – "Trust blue" (decided 22 Oct 2026, replaces Sky blue)
- Why: white text on Sky blue `#0A80D0` is about 4.2:1 contrast (below the 4.5:1 needed for small text); Trust blue is about 6.1:1, so button labels, tabs and amounts stay readable outdoors and on low-cost phones.
- One colour set for the whole app, owner and student (and the admin panel).
- Main blue `#1560BD` everywhere (headers, buttons, selected tabs, date box, links, arrows) · light blue tint `#E8F0FA` (chips, highlights, active-tab pill) · dark blue text on tint `#0C447C` · page `#F2F5F9` · cards white · text on blue `#D6ECFC`.
- Blue header bands are **solid** Trust blue – **no gradient** (`assets/sky-plain.jpg` no longer used). Flutter: plain `#1560BD`, no LinearGradient.
- Cards: thin border `#DCE3EC` (1 px) + very light shadow `0 1px 2px rgba(15,23,42,0.06)`, so card edges stay visible on dim, low-cost screens. Fee card: same, plus its 6 px coloured stripe on the left (blue / red / amber / green by state).
- Tappable rows and tiles show a blue **›** arrow on the right (menu rows, owner Home tiles, Rent card, setup checklist); static count tiles (Beds Filled / On hold / Free) have no arrow.
- Bottom tab bar (both apps): **lifted floating** rounded white bar – radius 26, 12 px from the sides, 1 px `#DCE3EC` border, light shadow `0 2px 6px rgba(15,23,42,0.08)`, 14 px above the phone's gesture area; the selected tab has a pale blue pill behind its icon, red count badges stay. It sits in the page flow (not on top), so no card hides behind it.
- Text `#14213D`, grey text `#5C6782`, lines `#DCE3EC`. Money / paid: green `#15803D`. Alerts / late: red `#DC2626`. Due: orange `#B45309`.
- Look only: layouts, text and behaviour did not change.

## Owner Home (decided 22 Oct 2026, replaces the earlier Home layout)
- **Header (blue):** ‹ My hostels and Switch (both go back to My hostels) · hostel name as **"Name – Type"** (one line if it fits; otherwise 2 lines, and very long names shrink a little rather than use a 3rd line) · area below with a pin icon. **No** photo/short-name box, **no** "Women's" chip and **no** "Open for joins" label on Home. The hostel photo is still added or changed from the My hostels card.
- **Payments card** (updated 22 Oct 2026, no bars): title "Payments" with an **eye button at the top-right** that hides or shows amounts. Two halves side by side – **Month · October** and **Today · <date>** – each shows: amount received (big, green), "of <total>" (small grey), and **"<amount> left" in red on its own line** ("All paid" in green when nothing is left). Amounts shrink to fit and never wrap. Bottom row: "<names> not paid today" + **Remind**. Hidden: amounts show "₹ ••••". The choice is remembered while the app is open.
- **Fits one screen, no scrolling:** the Needs your action rows share the free space – closer together on small phones, spread out on tall phones. On small screens the drag handle is hidden and spacing is a little tighter. Measured: fits without scrolling on every phone 760 or more tall; only older phones shorter than that scroll a little (nothing is cut off).
- **Needs your action** list (one card, each row: icon · title · count · ›): Confirm payments → Requests · Approve joins → Requests · Complaints · Leaving notices · **Available beds** ("In N rooms · M total") → Rooms filtered to available. Counts are shown once (no extra red badges on Home).
- **Invite students** card (updated 22 Oct 2026, "light blue card"): pale blue background `#E8F0FA` with blue border `#B9CDEB`, white QR box with Download under it, title **"Invite students"** (16, extra-bold, dark blue) and **"Scan this QR to join"** (14, semi-bold, dark blue), **Share link** and **Poster** side by side as white pills. Same card size as before.
- Removed from Home: the separate Beds card (Filled / On hold / Free), the separate Rent and Today's pending cards, and the 4 tiles (replaced by the Payments card and the Needs your action list).

## Hostel name display (decided 22 Oct 2026)
- Everywhere a hostel name is shown (owner Home, Rooms header, My hostels cards, invite page, staff home, student pages, payment screen) it reads **"Name – Type"**, e.g. "Sai Residency Ladies PG" → **"Sai Residency – Women's"**, "Sunrise Boys PG" → "Sunrise – Men's", "Nest Co-living" → "Nest – Co-living".
- Words that only say who the hostel is for are dropped from the display: Ladies, Girls, Women('s), Gents, Boys, Men('s), Co-living / Co Living, PG. The type comes from the owner's choice (Men's / Women's / Co-living) and never splits across lines. The name the owner typed is saved unchanged (Hostel settings still shows and edits it).
- The short name in photo boxes uses the cleaned name (e.g. "SR" for Sai Residency). Separate type chips next to the name are removed where the name already shows the type.

## Text, weight and corners – "Tidy-up" (decided 22 Oct 2026)
- **One font everywhere:** Plus Jakarta Sans, including what people type into input boxes (Flutter: set the font on the whole theme, incl. `TextField` style; Expo: `appFont()` in `src/ui.js`).
- **6 text sizes only:** 24 page title · 20 big amounts and headings · 16 card titles and typed text · 14 normal text and buttons · 12.5 grey lines under a title · 11 badges, tab names and small labels. **Nothing smaller than 11.**
- **3 weights:** 400 regular (grey lines, normal text) · 600 semi-bold (labels, names, buttons, selected tab) · 800 extra-bold only for page titles, big numbers and money amounts.
- **4 corner sizes:** 8 small chips and tags · 12 buttons, inputs, icon boxes, small tiles · 16 cards, tiles, sheets · fully round for pills, avatars, badges and round buttons. (The floating tab bar keeps its 26 pill shape.)
- **Login splash** ("Welcome, …" after login): solid Trust blue background, white check circle and white text.
- Look only: layouts, text wording and behaviour did not change.

## Admin panel – for the app owner (you) only (decided 21 Oct 2026)
- A separate private **web app** (e.g. admin.<your domain>, hosted on Netlify), same Supabase database, login only for accounts with the **admin** role. Hostel owners and students never see it.
- Until it is built: manage ads and look at hostels directly in the Supabase dashboard.
- Pages (samples shown 21 Oct 2026; uses the Trust blue look from 22 Oct 2026 – solid blue top bar, left menu):
  1. **Dashboard** – hostels (active this week), beds and % filled, students (+ this week), earnings this month (ads + platform fee when on); new students per week chart; "Needs your attention" (platform fee off, data-deletion requests, support messages, ads ending); costs this month (SMS, photo storage on R2, database size, downloads, with free limits).
  2. **Ads** – list with shop + offer, area, dates, views, clicks, Live switch; filters All / Live / Stopped; New ad form: shop name, offer, button Call / Open link, phone or link, show in All hostels / area, start, end, preview of the student Home card, Save ad. Only the admin adds ads.
  3. **Hostel owners** – counts (hostels, active this week, new this month, blocked); table: hostel + area, owner + masked phone, beds, students, online payments this month, status, View / Block (Unblock); filters All / Active / New / Blocked. **The app is free for hostel owners – no owner subscription (decided 21 Oct 2026).**
  4. **Platform fee** (future, OFF at launch) – a small fee the **student** pays with rent; the owner always gets the full rent. Settings: on/off, fixed ₹ per payment or % of amount, amount, name students see ("Platform fee"), charged on (instant online pay only – UPI-to-owner and cash go straight to the owner, so a fee can't be collected there), apply to all hostels or picked hostels, Save. Shows "What the student sees" (Rent ₹6,500 + Platform fee ₹10 = Pay ₹6,510; owner receives ₹6,500), a preview of what it would have earned last month, and online rent payments by hostel.
  - Later pages: Support (owner messages, data-deletion requests), App notices (message to all owners), Costs (detail), Settings (admin users).
- Database to add: `admins` (or an admin flag on profiles), `ads` (+ `ad_events` for views / clicks), `platform_fee_settings` (on, type, amount, name, hostels), a `platform_fee` column on payments, `support_messages`.
- **Ways to earn** (plan): **no subscription for owners – the app stays free for them**. 1) Local ads on student Home (now). 2) **Platform fee paid by students** on instant online rent payments (future; shown clearly before paying and on the receipt; needs a payment gateway that can split the money, e.g. Razorpay Route, and proper business registration). Later ideas: paid extras (SMS packs, police-verification PDFs, QR posters), featured hostels on a student "find a hostel" page, partner services. Check registration / GST with a CA and payment-collection rules (RBI) before charging any fee.

## Public website & Find a hostel – future, Phase 2–3 (decided 21 Oct 2026)
- **One public website** (Next.js, e.g. myhostel.in; Netlify / Vercel) does both jobs:
  - **Google search (SEO):** one page per hostel (`/hyderabad/madhapur/sunrise-boys-pg`) and per area (`/hyderabad/madhapur`): photo, area, rent from, beds free today, rent by sharing with free beds, amenities, notice period. Button **"Book a bed – open in My Hostel app"** (Android App Link with the hostel's join code → opens the app on that hostel, or Play Store first).
  - **Find a hostel on the web:** search by area / office with filters (men's / women's / co-living, budget, sharing, must-haves, distance, monthly / day-wise).
- **Student app "Find a hostel"** (Flutter): same data and filters; list → hostel page (♡ save, Visit, Book a bed) → normal joining flow. If the student already stays in a hostel: "Leave <old> on <date> → Join <new>" with the deposit rule; one tap sends the vacate notice and books the new bed (or "only book, notice later"). Report issue stays in the tab bar; Find goes on Home or Settings.
- Both read the **same Supabase data** (public hostel info only – never student data); prices and free beds update automatically.
- **Owner opt-in:** "Show my hostel on the website / in search" switch. Pitched to owners as **"Fill my empty beds"** – we bring new students.
- **Who sees Find in the app:** new users (not in a hostel) and students who have already given vacate notice – not students in the middle of a stay (protects owner trust).
- **When:** Phase 2 = "Fill my empty beds" (owners list free beds for new students); Phase 3 = full Find a hostel + featured listings (income). Start once there are ~30–50 hostels in one area. The admin panel stays private (can share the Next.js project under a protected section).
- Needs: own domain (~₹500–1,000/year), Google Search Console, assetlinks.json on the website for App Links.

## Navigation
Student (no login):
- Joining flow (no tab bar): Verify mobile → Hostel details → Available rooms → Your details → Stay & payment → Payment submitted. Each step has a back button and a "Step x of 4" progress bar.
- After joining, bottom tab bar with 4 tabs: Home · Fees · Report issue · Settings (see "Student home tabs").
- My stay shows the bill breakdown and a "Pay ₹X now" button that opens the Pay rent tab (no separate payment form on My stay).

Owner / staff (login):
- Before a hostel is chosen (no tab bar): Login → Sign up → Register hostel → My hostels.
- Inside a hostel, bottom tab bar with 5 tabs: Home · Requests (badge with count) · Tenants · Rent · More (badge for complaints / notices).
- Owner home header has a bell icon with unread count → Notifications screen (Today / Yesterday list, unread dot, "Mark all read"; each item opens the related screen).
- More menu: owner profile (no Switch hostel — switch from Home / Rooms "Switch" or back to My hostels); Manage: Complaints, Leaving notices; Hostel: Hostel settings (incl. Rooms: Add room, Rooms & beds), Staff logins, Invite students; Settings: App settings; Privacy & legal: Privacy policy, Terms of use, Download my data; Account: Help & support, Log out, Delete account.
- Sub-screens keep the tab bar with their parent tab highlighted and a back button (Tenant details → Tenants; Rooms, Complaints, Hostel settings, Staff → More). Forms (Add room, Register hostel) have only a back button.
- Owner home header has "My hostels · switch" to change hostel.

### Back button (standing rule – every screen, now and in future)
- The top-left back arrow and the phone's back button / gesture must both go to the previous screen, on every screen.
- Order: close an open sheet/dialog → pop a pushed screen → go to the screen's parent → leave the app only from a start screen (Login, My hostels, student OTP page).
- Tabs (Requests, Rooms, Rent, More) show a back arrow and go back to Home first; Home goes back to My hostels.
- After a payment is submitted, back goes to the student status page, never back to the payment form.
- Flutter: every route is listed in `app/lib/core/back_nav.dart` (`backTarget`), and screens use `AppBackButton` / `goBack`. Expo prototype: `<Screen>` / `<TabPage onBack>` and `useBackHandler` in `src/nav.js`.
- Any new screen must be added to these before it is done.

## App settings (owner)
- Notifications on/off: new join requests, payments, complaints, daily summary (9 PM).
- Messages to students: push (free), SMS, WhatsApp on/off.
- Security: app lock (fingerprint / Face ID), change password, logged-in devices with "Log out others".
- Theme: Light / Dark / System. Language. App version, Rate the app.

## Privacy, terms & account deletion
- Privacy policy and Terms of use screens (tabs), reachable from More, from the student Verify screen ("By continuing you agree to…") and from the student status page.
- Privacy policy covers: what we collect, why, who can see it, how we protect it, how long we keep it, DPDP rights, grievance officer contact. The text is a draft template; a lawyer must review it before launch, and placeholders ([DATE], [X] years, grievance officer details) must be filled.
- Delete account (required by Apple App Store and Google Play for apps with account creation): More → Delete account → explains what is deleted (all hostels, rooms, tenants, ID proofs, staff, complaints), students told by SMS 30 days before losing access, payment records kept as legally required; "Download all data (Excel)" first; optional reason; type DELETE + OTP to confirm; account removed after 7 days, logging in within 7 days cancels.
- Students: "Request my data deletion" link on the status page.
- Google/Apple login is NOT needed: the app uses only its own mobile + password login (allowed by both stores). If Google login is ever added, iOS also needs an equivalent privacy-friendly option such as Sign in with Apple.

## Login
- Only hostel owners and their staff log in (mobile number + password).
- Owner sign-up: name, mobile, one OTP to verify the number, password, language. "Forgot password" also uses one OTP.
- Students never log in: no signup, passwords, profile pages or settings.
- Do NOT use Supabase Auth for students, not even anonymous sign-in (it counts as a monthly active user).

- After a successful login (or sign-up), a lavender **Welcome** screen shows for about 1.5 seconds — purple tick, "Logged in", "Welcome, [first name]", spinner, "Opening My hostels" — then opens My hostels by itself (tap to skip). Opening the app while already logged in goes straight to My hostels.

## Staff logins (limited access)
- Owner invites staff by name + mobile (SMS invite; staff set their own password).
- Owner picks permissions per staff member: view tenants & rooms, approve join requests, confirm payments, handle complaints, send rent reminders, view ID proofs.
- Owner-only (never for staff): change rent/rooms/charges, payment options, reports, staff management.
- Enforce permissions in the backend (database row-level rules), not only in the app UI.

## Multiple hostels per owner
- One owner login can manage more than one hostel.
- After login: first-time owners go to "Register hostel"; returning owners see "My hostels".
- Register hostel fields: hostel name, hostel type (Men's / Women's / Co-living), address, city, pincode, hostel contact number (shown to students), number of floors, photos (optional).
- Buttons at the end: "Save hostel" and "Save & add another hostel"; "My hostels" also has an "Add another hostel" button.
- "My hostels" lists each hostel with its type, beds filled and alerts (payments to confirm, rent pending, or "finish setup" for a new hostel).
- Tapping a hostel opens that hostel's Owner home. Owner home shows "My hostels · switch" to go back.
- Each hostel has its own rooms, sharing, rent, payment options, settings, tenants, staff, join link / QR and reports.

## Hostel short name & photo (short name 19 Oct 2026; photo back in Phase 1 on 20 Oct 2026)
- The owner can add a **hostel photo** (My hostels card and Hostel Home header). Small button on the photo box: 📷 camera = add (no photo yet), ✏️ pen = change. It opens a sheet: **Take a photo**, **Choose from gallery**, **Remove photo (show EWH)** (only when there is a photo), Cancel. The photo also shows to students on the hostel page.
- Photos are compressed to ~200 KB and saved in a private Supabase Storage bucket `hostel-photos` (separate from student files); only the file key is saved on the hostel; shown with short-lived links.
- Until a photo is added (or after it is removed), a box shows the hostel's **short name**: first letter of each word, at most 3 letters – if the name has more than 3 words, the first word + the last two. Examples: Elite Deluxe Women's Hostel → **EWH**, Sai Residency Ladies PG → **SLP**, Sunrise Boys PG → **SBP**, Nest Co-living → **NC**.
- Made automatically from the hostel name (owners can't type it). My hostels: light-blue box with blue letters; Hostel Home: white box on the blue header.

## Rooms
- Rooms tab shows only FREE beds: one card per free bed named room number + bed letter (e.g. 201 A, 201 B), grouped by floor, filtered by sharing (All / 1 / 2 / 3 / 4, each chip shows its free-bed count). Full rooms and beds on hold are hidden. Header shows the real hostel name and area, and whole-hostel numbers — occupied beds, available beds and occupied % — which never change with the sharing filter. Tapping a bed card books that bed (no separate bed selection).
- Bed cards are as small as possible (4 per row): room + bed letter, sharing · short rent, and a Book button inside the card.
- Book → "Share with student" screen: the bed is held 15 minutes (timer shown) and the screen shows room, bed, rent, deposit, total and a QR code for that bed, with WhatsApp link / Copy link / Cancel booking and "Hold again" when the hold ends.
- Student scans the QR → 3 steps: (1) verify mobile with OTP (the held bed, rent, deposit and timer are shown), (2) Your details + accept hostel terms & house rules + DPDP consent, (3) pay → "Waiting for owner approval". Every new joiner waits for the owner's approval in Requests; on approval the tenant is added to the Tenants list, the bed becomes filled (free-bed list updates) and the student's home page shows their details (name, mobile, room · bed, joined, rent, next due, deposit, parent, company / institute, address).
- Student details: Full name*, Mobile* (verified by OTP), Parent mobile*, Reference number (optional), Aadhaar / ID number*, Aadhaar / ID photo*, Profile photo (optional), Home address*, Company / institute name*, Company / institute address (optional).
- More → Hostel settings starts with **Rooms & beds**: Total beds · Occupied · Available · Floors, then the Add room button, then all rooms by floor with their sharing type (the list scrolls inside its own box; tap a room to change rent / deposit or delete it). Below it: Rent day as two large options (Same as joining date / Fixed day for everyone with a small number box 1–28). Hostel details and Accepting students are not on this screen.
- Add room: floor and room number side by side, sharing 1–6, fees side by side (monthly rent / deposit, per-day rent / day-wise deposit), features (AC, Geyser, Attached bathroom, Balcony, Cupboard, Study table, TV, Wi-Fi) and Save room. After saving the owner goes back to Hostel settings; counts and list update, the new room is marked New and a "Room saved · N beds added" message shows.
- Home Beds card (Filled / On hold / Free) shows plain numbers; the tiles are not tappable.
- Add room: room number, floor, sharing (1–6 beds), monthly rent per bed, deposit for monthly stay, per-day rent, deposit for day-wise stay, features (AC, attached bathroom, etc.), separate electricity meter on/off.
- Button: "Save room" (goes back to Hostel settings; tap Add room again for the next room).

## Hostel settings (simple page, decided 17–18 Oct 2026)
One page, big boxes, pens to edit (owners may not read well: few words, icons, big boxes):
- **Owner only.** Hostel settings (and everything in it) can be changed only by the hostel owner – not by staff logins (when they come) and never by students. The database checks this (private.assert_owner / row-level security).
- **One setting open at a time.** Every setting below the Rooms & beds counts (Hostel details, Change room details, Add room, Sharing + price, Advance / deposit, Rent date, Notice period, Wi-Fi, Allow day-wise stay, Extra charges, Payment options, Amenities, House rules, Account) is one closed line with a down arrow. Tapping a line opens it (arrow up, blue border), closes any other, and is placed on screen whole: when the keyboard is up, the setting sits just above it with a small gap (about one finger); without the keyboard the page moves only if the setting doesn't fit; a setting too tall to fit above the keyboard shows from its title at the top (scroll for Save).
- **Save in every setting.** Each open setting has a **Save** button on the right (with "+ Add …" on the left where there is one). Nothing in a setting (pens, ✕, switches, dates, chips, text) is stored until Save. After Save, only that setting turns grey with a white box in the middle: green tick, "Your changes are saved" and a short line (e.g. "Rent date · 10th"); it goes away by itself after 1½ seconds. If the owner opens another setting with unsaved changes, a sheet asks "Save changes?" – Save / Don't save (Don't save puts the setting back as it was).
- Rooms & beds block: Total beds · Occupied · Available · Floors, then **Change room details** as a line with a down arrow like the other settings (no switch): when opened, the search box and two boxes show straight away – [Room no. 🔒] [Sharing ✎]. The owner types a room number, changes only the sharing, then Save room. After saving, the same grey cover and "Your changes are saved · Room 204 · 3 sharing to 4 sharing" show for 1½ seconds; the box is then back to empty (it stays open; the rooms block updates without a loading circle). The room number can't be changed here and there is no rent box: the rent comes from the saved Sharing + price for the new sharing (if that sharing has no price, the owner is asked to add it first). Beds follow the sharing; can't go below the people staying. **When the sharing changes and students stay in the room**, a sheet first says e.g. "3 students stay in this room. Their fee becomes ₹5,500 (was ₹6,500) from their next fee date. They all get a message." – Yes, change / Cancel. Those students then pay the new sharing's price from their next fee date (fee bills already made for later dates take the new fee too) and get a message. A price change in Sharing + price alone (no room change) is only for new students.
- **Hostel details**: [Hostel name ✎] [Address ✎] [City ✎] [Pincode ✎] [Mobile number ✎] + "Open for new students" switch, Save.
- **Add room**: "Floor" with a box beside it (✎, type 0 = Ground, 1, 2, 3 … 50), "Room number" with a box beside it (type e.g. 305; ground floor = G + number), Sharing (1–5, +), Save. No price box: the rent comes from **Sharing + price** for that sharing (if it has no price, the owner is asked to add it there first). Deposit and per-day price come from the hostel's settings. Function add_room_simple.
- **Sharing + price** (was called "Sharing + price"): one line per sharing – [N sharing ✎] [₹ price ✎] [✕]. "+ Add sharing" opens one sheet asking the sharing (1–12) and its price, with an **Add** button that puts the line in the list (a sharing can't be there twice). When there are no lines, one empty line [Sharing ✎] [₹ Price ✎] [✕] shows; tapping either box opens the same sheet. "+ Add sharing" is always shown but greyed until there is at least one line. Saving copies the price to every room of that sharing; students already staying keep their rent.
- **Advance / deposit**: switch + [₹ amount ✎] (off = no deposit for new students).
- **Rent date**: Joining date / Fixed date. With Fixed date, the owner taps a date (1–28); the grid then closes and only the green line "Your fixed fee date is 10th of every month" stays, with a **✎ Change** button that opens the grid again. **Changing the fee date while students stay**: Save first shows "Fee date: 5th → 10th" with what happens; on "Yes, change" every staying student moves to the new date (function change_rent_day). The days between the old and the new date are added **once** to the next fee: monthly fee ÷ days in that month × days (e.g. ₹5,500 ÷ 30 × 5 = ₹917, so the fee on 10 Nov is ₹6,417); if the new date is earlier, the days already paid are taken off once the same way. After that, the normal fee every month on the new date. Fee bills made early (not paid) are made again on the new date. Every student gets a message.
- **Notice period**: 15 days / 30 days / 45 days or "Or type days" ✎ (1–90, e.g. 7, 14, 21 for week-wise hostels), Save. All students who haven't given notice get a message and their screens show the new period; students who already gave notice keep their leaving date (function set_notice_days).
- **Wi-Fi**: one line per floor – [Floor ✎] [password ✎] [✕]. "+ Add Wi-Fi" opens one sheet asking the floor and the password (Add only when both are given; a floor can't be there twice). Empty list → one empty line [Floor ✎] [Password ✎] [✕] that opens the sheet; "+ Add Wi-Fi" greyed until there is a line. Students see only their floor's password.
- **Allow day-wise stay**: switch + [₹ per day ✎].
- **Extra charges**: Electricity bill (₹ per unit) and Laundry (₹ per month) with amount ✎ + switch (no help text under the heading); "+ Add another charge" (name, amount, every month / one time).
- **Payment options** (only the ones switched on show to students): UPI (+ UPI ID ✎), Google Pay, PhonePe, Paytm (need UPI on; same UPI ID; students get a "Pay with …" button), Bank transfer (+ details ✎), Cash (+ message students see, e.g. "Pay cash in the office, 9 AM – 1 PM"). Pay online (Razorpay) shown greyed "Phase 2".
- Amenities, House rules, then **Account → Change password** (its own sheet). There is no "Save settings" button at the bottom of the page.
- **Messages to students** (student home, newest first, last 30 days, up to 5; text in the student's language): "Your room becomes 4 sharing – Room 204 · from 5 Nov your fee is ₹5,500 a month (was ₹6,500)", "Fee date changed to 10th – Next fee on 10 Nov: ₹5,500 + ₹917 for 5 extra days (once) = ₹6,417", "Notice period is now 30 days – Tell the owner 30 days before you leave". Table student_messages, sent in student_me_extra.messages (migration 20261018000001, test 06_settings_changes_test.sql).
- Database: hostels.sharing_prices, deposit_on, deposit_amount, day_wise_on, per_day_rent, extra_charges, accept_gpay/phonepe/paytm; function save_hostel_prices (migration 20261017000002, test 05_hostel_settings_test.sql). Extra charges are stored now; adding them to monthly bills comes with Phase 2 billing.

## Staff (decided 18 Oct 2026 – moved into Phase 1)
More → **Staff** (owner only). Simple page like Hostel settings:
- Every staff member is one line – initials, name, job · mobile – with a down arrow; only one open at a time (unsaved changes ask "Save changes?").
- Opened: **Duties in the app** (switches): Collect rent · record cash, Approve new students, Rooms & beds (book, free a bed), Complaints · reply & close, Leaving notices · check-out, Send rent reminders, See reports & money totals, See ID proofs, Daily jobs checklist. Below them the duties the owner typed himself (switch + ✕) and **"+ Add any duty you wish"** (type a duty in your own words, e.g. "Buy vegetables"). Then **Daily jobs (checklist)** ✎ (e.g. "Lock gate 10:30 PM · Check water tank"), **Remove staff** (asks first) and **Save** (grey "Your changes are saved" cover, 1½ s).
- **"+ Add staff member"** at the bottom: name, mobile number, job (Manager / warden, Cleaning, Security, Cook, Other + which job) → "Add & send SMS invite" (the SMS opens on the owner's phone). The job switches on its usual duties: Manager – rent, approve, rooms, complaints, leaving, checklist; Cleaning – complaints, checklist; Security – leaving, checklist; Cook / Other – checklist. The owner changes them after adding. A mobile number can be added once per hostel.
- **How staff get access** (part 2, next): staff log in on their own phone with their own mobile number (OTP, then a password) – never the owner's login. The app shows only the screens for their duties (home: rent to collect, students to approve, complaints, free beds, today's jobs with tick boxes) and the database checks the duties on every action, so a changed app can't do more. Changing a duty or Remove staff works at once. Every action is saved with the staff member's name. Always owner only: Hostel settings, payment details, staff, deleting the hostel.
- Database (part 1): table staff (job, duties, custom_duties, checklist, user_id for part 2); functions staff_list, save_staff, remove_staff, staff_job_duties; owner only (migration 20261018000002, test 07_staff_test.sql).

## Rooms entered by tenants (Phase 1 only – remove or switch off in Phase 2/3)
Why: at the start owners won't spend time entering every floor, room, sharing and price. Every student who scans the hostel QR types their own room while joining; the owner only checks it.
- Per-hostel switch "Tenants enter room details" (on by default; Hostel settings → Price by sharing). Turn it off once all rooms are set.
- Student "Your details" (2 scroll screens, order): New joiner / Already staying here options (no "Joining" heading) + Joined on → **Your room**: Room no., Floor (a "Ground" chip + a "Floor" button that opens a pop-up over a dimmed screen: Floor 1–9 in a 3×3 grid and a full-width "+ Tap to add next floor" bar that adds Floor 10, 11 … up to 50; new floors show in green; tapping a floor picks it and closes the pop-up; the student types the full room number, e.g. 204), Sharing (chips 1–5 then "+"; each "+" adds and selects the next number: 6, 7, … up to 12), Monthly price, Deposit (empty if none) → About you (name, verified mobile, parent name + mobile, reference name + number) → ID proof (number, last 4 shown) with ID copy and Your photo side by side → Address (home address, college / office name, college / office address) → house rules, DPDP consent. College / office is only in the Address part (not on the first screen).
- If the typed room number is a room the owner already set, its floor, sharing, price and deposit are filled in and locked.
- No room selection step when the room is typed: Profile → existing tenants "Send to owner for approval", new joiners go to payment (step x of 4).
- Server: the typed room is created **unconfirmed** if it doesn't exist and a bed in it is held for the student (so uploads, payment and approval work as usual). Each tenant keeps the fee and deposit they typed. Unconfirmed rooms are not offered to other students in room selection.
- Owner: More → **Rooms from tenants** – table grouped by floor: Room, Sharing, Price, Filled, status Confirmed / OK / Fix. "Fix" = tenants typed different sharing / price / floor for the same room. Tapping a room opens it inline (what each tenant entered + correct floor, sharing, price, deposit → Save). The owner corrects it himself; the student is NOT told and there is no separate "check room" screen. "Confirm all correct rooms" confirms every OK room. Confirmed rooms become normal rooms in Rooms & beds (extra empty beds removed / missing beds added).
- Owner: Hostel settings → **Price by sharing** – table Sharing, Rooms, Price / bed, Deposit (rooms still to fix show "N prices"); tap a row to set one price and deposit for every tenant-entered room of that sharing; switches "Use these prices for new joiners" (tenant-entered rooms offered in room selection) and "Tenants enter room details".
- Ground floor rooms are **G + a number** (G1, G2, G3 …). Ground is off by default; when the student picks Ground the room field shows a fixed "G" and takes digits only; typing a G first picks Ground automatically; rooms on floors 1–9 can't start with G (error shown, Continue stays off). The server checks the same rule (BAD_GROUND_ROOM, migration 20261017000001).
- The owner's fix panel uses the same floor and sharing pickers. Rooms can have up to 12 beds (migration 20261016000002).
- Database: `hostels.tenant_room_entry`, `hostels.use_tenant_prices`, `rooms.confirmed`, `rooms.from_tenants`, table `tenant_room_entries` (migration 20261016000001, test `supabase/tests/04_tenant_rooms_test.sql`).

## Removed
- Live chat / message section
- Payment screenshots as the only proof (25 Oct 2026: a receipt is required again, but it is checked by the app and the owner's bank is final – see "Payments – free UPI with checks")

## New joiner confirmation (25 Oct 2026)
- After a new student sends all details and the full payment, he **must wait for the owner to confirm**. Every new joiner (UPI, bank, cash or online) needs the owner's OK.
- While waiting, the bed is **kept for him**: nobody else can book it (it is not shown as free in Rooms).
- **Student – "Your booking" page** (after paying, and on Home until the owner decides): amber "Waiting for owner" card with Room · Bed "kept for you"; status steps Details sent ✓ → Payment sent ✓ (amount, method, UTR) → Owner confirming → Bed booked; a **Call owner** button ("Want it confirmed faster?"); amount paid and "If not confirmed, the owner returns your money."
- **Owner – Requests**: one card per new joiner showing **details** (photo and Aadhaar – open with a private link – mobile, parent mobile, reference, college/office, home address) and **payment** (rent + deposit, method, UTR, note, duplicate-UTR warning, "Check your bank app for ₹… first") on one screen, with **Confirm booking** (green, big) and a small **Reject** at the bottom. No separate details / payment checks.
- **Confirm booking** → bed becomes Filled (booked), tenant added, student Home opens with a "Bed booked!" message.
- **Reject** → owner must pick a reason (Wrong details, Aadhaar not clear, Payment not received, Bed not available, Other) → bed becomes free for others again → student sees "Booking not confirmed", the reason, "Your money will be returned by the owner", Call owner and Pick another bed. (Refund amount rule: see point 2, being decided.)
- If the owner has not answered in **2 hours**, he gets a reminder; the bed stays kept because the student has already paid.

## Student flow (no login)
1. Scan the hostel's QR code or open its link → Verify mobile screen opens directly (step 1 of 4): only the hostel name, language choice, mobile number + one OTP, "Verify & continue", and "Find my booking". No hostel details, rooms or prices before verification.
2. After successful verification → Hostel details screen: photos, name, type, address, prices (monthly / day-wise), sharing, available beds, amenities, owner contact, rent day, notice period, extra charges, house rules. Below the details: "View available rooms" button.
3. Available rooms (step 2 of 4): pick sharing and room/bed. "Hold this bed & enter my details" holds the bed for 15 minutes (released automatically if not paid).
4. Your details (step 3 of 4): full name, mobile (already verified), parents number, reference number, ID proof (Aadhaar, passport or driving licence), ID copy, student photo, address, office/college address, DPDP consent. Shows the held bed and time left.
5. Stay & payment (step 4 of 4): choose Monthly / Day-wise, see the amount, accept the refund policy, then pay.
6. Receive confirmation, rent day and receipt by SMS / WhatsApp / push.

## Existing tenants (moving to the app) & joining date
- No manual "add tenant" form. Existing tenants join the same way (scan QR → verify → choose their current room/bed → details).
- "Your details" has a Joining section: "New joiner" (joining date = today, read-only) or "Already staying here" (enter a past joining date).
- Existing tenants skip payment: the button becomes "Send to owner for approval". The request shows on the owner's Requests screen as "Existing tenant · joined [date] · Room/Bed" for the owner to check and approve. Their next rent is due on the next rent day; past payments are recorded by the owner with "Record payment".
- Beds of tenants not yet on the app: the owner marks them occupied when adding rooms; existing tenants can still pick their own bed.
- Tenant details and exports show the joining date.

## Record payment (cash and other offline payments)
- "+ Record payment" on Tenant details, and in the Rent tab by tapping a tenant → Record payment.
- Form: which bill, amount received, method (Cash / UPI / Bank transfer / Cheque), date of payment, optional note, "Send receipt to student" switch, Save.
- Less than the bill is saved as a part-payment; the rest stays pending.

## Rent tab
- Top bar: back, Reports icon (opens Reports), settings icon (opens Hostel settings). No download button here — downloads are in Reports.
- Compact **Month box** (light blue, tap "October ▾" to pick one of the last 12 months): "₹13,000 of ₹48,500 · 27%"; tiles **Collected** (n paid) · **Still to pay** (due today + later this month) · **Late now** (incl. late fees).
- Compact **Today box** (same look): "Today · 13 Oct", "n tenants due"; tiles Collected today · Still to pay today · Late now; **Auto-remind** switch (3 days before & on rent day) at the bottom. Saved per hostel; a daily job sends the SMS.
- **Late fee** row (above the filters): on/off switch + "✎ ₹50/day" edit button. The owner decides the amount per day (any amount, quick picks ₹20 / ₹30 / ₹50 / ₹100). Off = no late fee anywhere.
  - Fee = days late × amount per day, for each unpaid rent bill, until the payment date.
  - Late tenants show "Room 202 · ₹8,000 + ₹850 fee" and the total (₹8,850).
  - Record payment shows Rent due, "Late fee · 17 days × ₹50", **Total payable**, and a **Waive late fee** switch. On saving, the fee becomes a separate "Late fee" bill (not when waived) and counting restarts from the payment date.
  - Student payments confirmed by the owner also get the late fee up to the payment date.
  - Students see "Late fee (N days × ₹50)" and Total payable on Your bill; Pay now includes it.
- Filters: All / Late / Due / Upcoming / Paid. **All** shows only due today, late and paid — future rent appears only under **Upcoming**.
- The whole page scrolls (boxes, late fee row, filters and list); only the Send reminder button stays fixed at the bottom.
- Tap an unpaid tenant: Record payment / Send WhatsApp reminder / Open tenant details. Tap a paid tenant: tenant details.
- **Send reminder to all · n unpaid** is fixed at the bottom (confirm first): SMS to tenants whose rent is due today or late (amount incl. late fee); anyone reminded in the last 12 hours is skipped.
- Extra charges (electricity, laundry) are Phase 2 and are not shown on the Rent tab.

## Reports (More → Reports)
- One screen: choose **Rent report** or **Students list** (two cards at the top), then **Month-wise / Year-wise** and the month or year (‹ October 2026 ›).
- **Rent report** (format chosen 19 Oct 2026 – "Excel table"): Collected / Expected / Pending boxes; when nothing is pending a green line "✓ All rent collected for August 2026"; then one table – Room · Name · Rent · Due (date) · Status (Paid / Due) – with a **Total** row (total rent and "All paid" or "₹… due"). Year-wise also shows a month-by-month table (tap a month to open it).
- **Students list** (format chosen 19 Oct 2026): Staying now / Joined / Left counts, filter All / Staying / Joined / Left, then one card per student – initials, **Name · Room**, 📞 mobile · Joined date · Deposit, and an **ID ✓** (uploaded) / **ID ?** (not uploaded) badge; leaving / left students also show that.
- **Download report**: downloads the report and period shown on screen. The sheet offers only **PDF** ("To print or keep") and **Excel** ("To edit or for accountant") – no WhatsApp / share option. One tap saves the file on the phone and opens it (open_filex); the message has an "Open" button.
- Rent PDF / Excel follow the screen: hostel name, period · number of students, the three totals, the green "All rent collected" line when nothing is pending, then # · Room · Name · Mobile · Rent · Due date · Paid on · Mode (UPI / Cash / Bank) · Status, and a Total row (Excel also has Paid amount and Pending columns). Students PDF / Excel: # · Name · Room · Mobile · Joined · Deposit · ID proof (Uploaded / Not uploaded) · Status (Excel also Company / institute). Aadhaar numbers are never included in reports.

## Extend a day-wise stay
- 1 day before check-out and on the check-out morning, the student gets a push/SMS: "Your stay ends tomorrow… ₹[per-day] per day. Tap to extend and pay."
- Extend screen: current stay dates and how long the bed is free; option "Add more days" (− / + days, new check-out date, days × per-day rent = total; deposit already paid) or "Switch to monthly" (per-day rent up to the rent day + deposit top-up, then monthly rent).
- If the bed isn't free for all chosen days, show the latest possible date. Pay to confirm; "No thanks, I'm checking out".

## Error & empty states (must be built)
- Wrong OTP: red boxes, "Wrong OTP… X tries left", Resend OTP; after 3 wrong tries wait 10 minutes.
- Payment failed: no money taken / refund in 5–7 working days if deducted; bed hold time left; Try again / Pay another way.
- Bed taken while paying: not charged, similar free beds suggested, details kept, See all rooms.
- No internet: offline bar, typed data saved on the phone, Try again.
- New hostel (empty): setup checklist (Hostel details ✓ → Add rooms → Payment options → Rent day & rules → Invite students) with progress; "No tenants yet" message.
- Every list screen (Requests, Tenants, Complaints, Notifications, Reports) needs a friendly empty message with the next action.

## Later (not now)
- Room change / bed transfer, rent increase notice, expenses tracking.

## Stay types (Monthly / Day-wise)
- Owner can turn day-wise stays on/off in Hostel settings.
- Toggle on the payment screen: Monthly / Day-wise.
- Monthly: show rent for the first period + security deposit (monthly) = total; show the rent day.
- Day-wise: show check-in and check-out dates, number of days × per-day rent = rent, + security deposit (day-wise) = total.
- Security deposit is shown for both stay types (separate amounts set by owner per room).
- Both stay types go to the payment options.

## Rent day (owner setting)
- Owner chooses: "Same as joining date" or "Fixed day" (e.g. 5th of every month).
- Fixed day + mid-month joining: first bill is charged per day up to the rent day (monthly rent ÷ 30 × days), then full months.
- Students are told their rent day when they join, and get reminders 3 days before and on the rent day.

## Refund & notice policy
- Owner sets the notice period (e.g. 7 / 15 / 30 days) in Hostel settings.
- Before payment, show: "No refund of the security deposit or that month's rent if you leave without informing at least [N] days before." Student must tick "I agree".
- Students give notice from the status page ("Give notice · choose leaving date"); owner sees it on Owner home.
- On vacating, owner settles the deposit: forfeited if notice was short, otherwise refund minus deductions (damage, unpaid bills).

## Extra charges
- Owner switches in Hostel settings: separate electricity bill (room meter, split per bed), laundry (fixed per month), and other custom charges.
- Each month the owner enters electricity bills per room; charges appear as separate lines on the student's bill and receipt.

## Payments – free UPI with checks (decided 25 Oct 2026, replaces "Payment verification (no screenshots)")
- **Free and instant:** students pay by **UPI straight to the owner's UPI ID** (money reaches the owner's bank at once, no gateway, no charges). No "Pay online" (gateway) option in the student app for now; Cashfree / Razorpay stay a possible later option only. Amount is the exact fee (no extra paise).
- **Pay screen:** total + "Paid straight to the owner · no extra charges", then big buttons **Google Pay · PhonePe · Paytm · Any UPI app** (only apps the owner turned on + Any UPI app). Tapping opens the app with amount and a payment note filled in. Small links: "Paying from another phone? Show QR", "Pay cash at the office", "Bank transfer" (if the owner turned it on).
- **After the UPI app:** the UTR is **filled in from the UPI app's reply** when the app sends it; otherwise the student types / pastes the 12-digit UTR.
- **Receipt is required** to finish a UPI / bank payment: in the UPI app tap **Share › My Hostel** (the app is a share target), or **pick the screenshot** (system photo picker, newest first, no gallery permission). Parent paid from another phone → send the receipt on WhatsApp, then pick it. The phone reads the text in the receipt (on the phone).
- **12 checks** – 7 on the payment: UPI app said "Success"; reply matches this payment (our code in the UPI request); UTR filled by the UPI app; UTR never used before (any hostel); amount ≤ due (part payments allowed); time in the UPI app looks normal (not back within ~8 s, not hours later); no earlier "Not received" for this tenant. 5 on the receipt: says "Successful"; paid to the owner's UPI ID; same UTR and amount; time after tapping Pay; image never used before. (Dropped: "UTR date = today" – not reliable across banks.)
- **Every student payment waits for the owner** (decided 25 Oct 2026, option B): nothing counts as paid until the owner confirms. All of them – UPI rent (checks passed or failed), cash the student says he paid, joining payments – appear only in **Home › Confirm payments** (Requests › Payments); the Rent tab only shows a link "N payments to confirm · Home › Confirm payments".
- **Checks all passed:** green tag "12 of 12 checks · check your bank", receipt, UTR last 4 digits big, **Not received** and **Confirm** (one tap). **Any check failed** (or UTR typed by hand): amber "Checks failed · check your bank" with the failed checks, **Not received** and **Received** (amount actually received, part-payment rules).
- Student sees **"Payment sent · waiting for owner"** (Fees: "Waiting for owner to confirm · UTR …"). On Confirm / Received → receipt + "Owner confirmed your payment". On Not received → UTR blocked, the tenant is told to check / pay again, and later payments from him show "Had Not received before".
- **New joiners** always wait for the owner's **Confirm booking** (see "New joiner confirmation"); their request shows the receipt and check results.
- **Receipt image storage:** compressed (~50–80 KB); kept on the server for at most **7 days** (the confirm window), copied into the **owner's phone** (app storage, not gallery) when his app opens, deleted there after **90 days**. Only the check results, UTR and an image fingerprint (to block reused images) stay on the server.
- **Cash:** unchanged – owner taps "Cash received" (no receipt).
- Owner tip: a free **business UPI ID** (PhonePe Business, Paytm for Business, Google Pay for Business) works more smoothly than a personal UPI ID when payments are opened from another app.
- **Test before Flutter:** small Android test build, pay ₹1 from Google Pay, PhonePe, Paytm and BHIM to an owner's business UPI ID; note whether each app opens with the amount, completes, and sends back "Success" + UTR.
- Expo prototype: opening the UPI app, its reply and reading the receipt are simulated with buttons.

## Safety & data rules
- One phone OTP per student at joining (and only again for "Find my booking" or a new phone).
- Two students must not get the same bed: lock the bed in the database when it's held (one transaction).
- Short-lived signed upload links, only for verified bookings.
- Rate-limit form submissions and OTP requests per phone number.
- Aadhaar rules: ask for a masked Aadhaar copy; store any Aadhaar number encrypted and show only the last 4 digits; owner must tap "Reveal" (logged) to see more; never show the full number to students or staff without permission.
- Allow other ID proofs (passport, driving licence) for students without Aadhaar.
- ID copies and photos are deleted automatically 3 months after the tenant leaves.
- ID proofs visible only to that hostel's owner (and staff with the "view ID proofs" permission).
- DPDP Act consent checkbox on the student form.
- Compress photos in the app before upload (about 200–300 KB each).

## Student access (private link and app, no login)
- After joining, the student gets one private link by SMS / WhatsApp. It stays the same for the whole stay.
- Existing tenants ("Already staying here") get the same private link by SMS when they send their details for approval.
- The link is a long random token that can't be guessed.
- Students can bookmark it or "Add to home screen" so it opens like an app.
- Every monthly rent reminder includes the same link.
- Student app: on first open, enter mobile number + one OTP (once only). The app saves a secure access key on the phone and opens straight to the status page after that.
- The saved key / link token is checked by our own Supabase Edge Function, not Supabase Auth.
- New phone or app reinstalled: mobile number + one OTP again brings back the same booking.
- Lost link: "Find my booking" asks for the mobile number, sends one OTP, then resends the link.
- Owner can tap "Reset student link / app access": a new link/key is issued and the old one stops working.
- After the student vacates: the page stays read-only for receipts for about 3 months, then the link stops working.

## Student Home (decided 20 Oct 2026)
- Top: blue name band – student photo (from joining; initials if none), **full name**, hostel name, chips "204 · Bed B" and "3 sharing".
- **Fee card** – compact, about half height (approved 20 Oct 2026). Look: white card with a 2px border in the state colour, solid date box in that colour (white month/day), breakdown in a light tinted strip along the bottom. Colours: blue before the fee date, red late, amber late fee off, green paid. Layout: one row = date box on the left (month + day of the fee date) | label, big total, one short line | **Pay** button on the right; below a thin line with the full breakdown "Rent ₹6,500 + elec ₹420 + laundry ₹300 + late fee ₹200" (each part only when there is one). Four states:
  1. Before the fee date: blue date box, "Next fee · due 05 Nov", total, "16 days left · then +₹50/day" (the "+₹50/day" part only when late fee is on; "Pay today" on the day), green Pay.
  2. Late, **late fee ON**: red date box, "Overdue · due 05 Nov", total incl. late fee, "4 days late · ₹50/day", red Pay; breakdown ends with "+ late fee ₹200".
  3. Late, **late fee OFF**: amber date box, "Fee due · 05 Nov", total, "Please pay now", green Pay – no delay count, no late fee.
  4. **Paid**: green tick box, "<month> fee paid ✓", amount, "Paid <date> · <method>", **Receipt** button; line "Next fee on <date> · paid on time ★".
- Late fee and extra charges (electricity, laundry, others) show only when the owner has turned them on / added them.
- Then:
  - **Ad space**: a sponsored card from a shop near the hostel ("SPONSORED · near you", ✕ to hide, shop, offer, Call button). When there is no ad, an empty dashed "Ad space" box. Ads only on student screens – never on owner screens, payment or ID screens. **Ads are added only by the app admin (you)** from an admin page – hostel owners cannot add ads. Each ad: shop name, offer text, icon/photo, button (Call / Open), area or hostels to show in, start/end date.
  - **Wi-Fi** in 2 lines inside one box: "Wi-Fi · <name>" / "Password: <password>" + **Copy** (the student's floor Wi-Fi first, else the whole-hostel one).
  - **Leaving the hostel?** card: one line "Give notice by <date> → deposit back" (date = 15 days – the hostel's notice period – before the student's next fee date). After that date the line turns red: "Notice date <date> passed → no refund". Red-outline **Give vacate notice**. No date picker: the student always leaves on the next fee date.
  - Tap before the notice date → notice sent at once, card becomes "**Vacate notice given** · Leaving on <fee date> · ₹<deposit> deposit back when you leave" + **Cancel notice (I'm staying)** (asks "Cancel your notice?" first). The owner is told each time.
  - Tap after the notice date → warning "Leave on <fee date>? Notice date has passed … no refund (deposit and rent)" with red **Give notice – no refund** / Cancel; the given card then shows "Short notice – no refund".
  - **From your owner** notices (only when the owner posted any).
- Fee receipts are **not** on Home – they are in the Fees tab. Report issue is its own bottom tab. Call / WhatsApp owner removed.
- Everything fits on one phone screen.
- Prototype: student Settings → "Prototype: Home demo" switches the fee state, late fee on/off and No ad / Sample ad.

## Student private status page
- Reuses the "4th screen - Student profile" design as a read-only page.
- Shows: name, photo, hostel, room, sharing, bed, booking progress.
- Current bill: rent + electricity + laundry/other charges = total, due date, paid/pending.
- Pay rent: payment options and UTR entry.
- Downloadable receipts (all past receipts kept).
- Report an issue (see Complaints) and list of my issues with status.
- Leaving the hostel: notice rule and "Give notice" button.
- My details (no edit; ID shows last 4 digits only).

## Complaints (Report an issue)
- Student: category (Water, Electricity, Wi-Fi, Cleaning, Food, Furniture, Plumbing, Security, Other), description, optional photo; sees status of each issue.
- Owner/staff: Complaints screen with Open / In progress / Resolved filters; "Start work" / "Reply" / "Mark resolved"; student sees each status change.
- Open complaints count shown on Owner home.

## Police verification
- Tenant details has "Download police verification form (PDF)" filled with the tenant's details.

## Owner features (login)
- Hostel settings (per hostel): name/type/address, rooms, photos & rules, rent day, day-wise stays, notice period, extra charges, payment options, staff, language
- Tenant list with all details; search and filters; Excel export
- Approve or reject join requests
- Confirm payments (amount received, duplicate UTR warnings, online auto-confirm)
- Room occupancy board (filled / vacant / held beds) and Add room
- Monthly rent tracking with extra charges, reminders (one tap or automatic)
- Complaints
- Vacate tenant, notice tracking and deposit settlement
- Reports: monthly collections, occupancy rate, Excel export

## What students still get
- Join form, room selection, Monthly/Day-wise choice, payment options
- Confirmation and receipt (SMS / WhatsApp / push)
- Private status link or student app to check booking any time
- Monthly rent reminders with the payment link
- Report an issue and give notice

## Cost target
- About 1 lakh owner logins (included in Supabase Pro); staff logins count as users too.
- About $1,450/month for 10 million students' records; about $2,870/month with one OTP per student.
- Student app access checks via Edge Functions (about $2 per million); push notifications are free.
- Online payment gateway fee is per payment and only for hostels that turn it on.

## More features
- The owner will add more features later; add them to this file when they are decided.
