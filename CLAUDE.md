# My Hostel app

Before writing or changing any code, read `REQUIREMENTS.md` in this folder and follow every point in it
(tech stack, owner-only login, no student login, no chat, no payment screenshots, student flow, safety rules,
owner features and cost target).

Build in the phase order given in `REQUIREMENTS.md` ("Build phases"). Phase 1 is being built now; do not add
Phase 2 or Phase 3 features unless asked.

Build status: Phase 1 code is written (database tested with `supabase/tests`; Flutter app and Edge Functions
still need their first compile/run on a developer machine – see `README.md`). 22 Oct 2026: all "Waiting for Flutter"
items moved to Flutter (migration `20261022000001_waiting_for_flutter.sql`, test 08); run `check_app.bat` after each move.

Project layout:
- `supabase/` – database migrations, security rules, server (Edge) functions
- `app/` – Flutter app (owner app for Android + student web pages)
- `README.md` – setup and run steps

If a request conflicts with `REQUIREMENTS.md`, point out the conflict and ask before going ahead.
When a new feature or decision is agreed, add it to `REQUIREMENTS.md`.

## Expo Go prototype – keep it in step (standing rule)
`expo-prototype/` is a clickable copy of the app for testing on a phone in **Expo Go** (React Native, sample data,
no database). The real app stays Flutter in `app/`.

Every change to the app – a new screen, feature, field, rule, wording or flow change – must ALSO be made in
`expo-prototype/` in the same piece of work, so the user can test it in Expo Go:
- sample data and actions: `expo-prototype/src/state.js`
- new screens: add to the right file in `expo-prototype/src/screens/` and register the name in `SCREENS` in `expo-prototype/App.js`
- use only packages Expo Go already includes; no native modules that need a custom build
- when done, tell the user what to tap in Expo Go to see the change

## Back button – must work on every screen (standing rule)
The top-left back arrow AND the phone's back button / gesture must go to the previous screen on every screen,
current and future (tabs → Home first; leave the app only from a start screen). See "Back button" in `REQUIREMENTS.md`.
- Flutter: add every new route to `backTarget` in `app/lib/core/back_nav.dart`; use `AppBackButton` / `goBack(context)`
  for back arrows (never a bare `context.go` back). All routes sit inside `BackScope` in `router.dart`.
- Expo prototype: use `<Screen>` (has the arrow) or `<TabPage onBack>`; register custom back with `useBackHandler` (`src/nav.js`).

