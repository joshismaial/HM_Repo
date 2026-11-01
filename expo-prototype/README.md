# My Hostel – Expo Go prototype

All screens of the My Hostel app, with sample data, to try on your phone in **Expo Go**.
No database, SMS or payments yet. Closing the app resets everything.

The real app is still Flutter (`../app`). This folder is only for testing the screens and flow.

## Run it

1. Install **Node.js LTS** from https://nodejs.org (one time).
2. Install **Expo Go** on your phone from the Play Store / App Store.
3. Double-click **start_expo.bat**. The first time it installs Expo (a few minutes) and saves the log to `setup_result.txt`.
4. A QR code appears in the window. Scan it:
   - Android: open Expo Go → "Scan QR code".
   - iPhone: open the Camera app and point it at the QR.

Your phone and computer must be on the same Wi-Fi. If the phone can't connect, run **start_tunnel.bat** instead (it may ask to install a helper once – type `y`).

If Expo Go says the project needs a newer or older SDK, update Expo Go from the store, or tell Claude the exact message.

## How to test

- The app opens on **Login** (owner). Mobile and password are already filled in. Tap **Log in**.
- **Owner / Staff** switch on Login: staff see fewer menu items.
- **Open as student** (bottom of Login) = scanning the hostel QR.
- OTP everywhere: **123456**. Any other number shows the wrong-OTP error.
- Duplicate UTR test: **428913775201**.
- **Error & test screens** (bottom of Login): payment failed, bed taken, no internet, extend stay, find my booking.
- **Nest Co-living** in My hostels shows the new-hostel setup checklist.
- Student status page: **Prototype: back to start** at the bottom returns to Login. On Android the back button also works.

Screens update each other: a student's payment shows in the owner's Requests tab, approving it adds a tenant, a reported issue appears in Complaints.

## Files

```
App.js                       screen list + app start
src/state.js                 sample data and actions (replace with Supabase later)
src/nav.js                   simple screen-to-screen navigation
src/overlay.js               bottom sheets, confirm boxes, toasts
src/ui.js                    colours, fonts, buttons, cards, fields
src/screens/student.js       verify → hostel details → rooms → your details → payment → submitted, errors, privacy
src/screens/studentShell.js  status page tabs: My stay, Pay rent, Issues, Call owner
src/screens/owner.js         login, sign up, forgot password, my hostels, register hostel, setup checklist
src/screens/ownerShell.js    Home, Requests, Tenants, Rent, More tabs
src/screens/ownerMore.js     tenant details, record payment, rooms, add room, complaints, notices,
                             hostel settings, staff, invite, notifications, reports, app settings, delete account
```
