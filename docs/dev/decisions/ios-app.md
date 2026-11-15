# iOS app: sign-in, Cloudflare, what the phone keeps, and the look

Decisions made while planning [`Plans/ios-app.md`](../../../Plans/ios-app.md) (tracking issue #93). The mockups they refer to are at <https://claude.ai/artifact/4P7y4vUZww5xJGAq1TPKcc> (a private page).

## 2026-11-14: how the app signs in

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the app holds an API token (phone-path phase 2, #42) and never the password. How does the token get onto the phone?

**Options considered:**
- An "Open in WalletWeather" link beside a new token in the web app's Settings, with paste as the fallback: the smallest build, and it covers Google accounts.
- A QR code in Settings that the app scans: handy from a computer screen, but something has to draw the code (a new dependency to licence-check, or code written for the page).
- Email and password typed into the app: waits on phone-path phase 3 and login rate limiting, and can't cover Google-only accounts.
- A web sign-in sheet inside the app that handles local, Google and Cloudflare sign-in at once: the smoothest, and the most server work.

**The decision:** all four, with the web sign-in sheet as the first choice on the Connect screen. The sheet, the link and paste are built in phase 1 (#87); the QR code and email and password in phase 7.

**What it changes:** phase 1 grows (a "sign in an app" page and a code-for-token exchange on the server, on top of #42), and the plan gains phase 7. One thing isn't proven yet and is tried first in phase 1: Google refuses to sign in inside an app's own web view, so the sheet has to be the system's sign-in sheet, and that sheet doesn't share its Cloudflare session with the app's own requests.

## 2026-11-14: getting past Cloudflare Access

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the server sits behind a Cloudflare Tunnel with Zero Trust rules, which turn a request away before WalletWeather sees its token. How does the app get through? (For native apps, this is open question 1 of `Plans/phone-path.md`.)

**Options considered:**
- A Cloudflare service token entered on the Connect screen and sent with every request: Cloudflare still guards everything, and the token is made once in the Zero Trust dashboard.
- An Access rule that lets `/api/*` through: nothing to build, but the API is then reachable from the internet with the WalletWeather token as the only check.
- The app signs in to Cloudflare itself and reuses that session: no service token to manage, but signing in again whenever the Cloudflare session ends, and more to build.

**The decision:** the app signs in to Cloudflare itself by default, and takes a service token as the alternative (under "Advanced" on the Connect screen). The Access rule for `/api/*` isn't used for the app.

**What it changes:** phase 1 (#87). If the Cloudflare session can't be carried from the sign-in sheet to the app's own requests, the service token is the way through until it can, and Matthew is told before the rest of the phase is built. How scripts get past Cloudflare is still open in `Plans/phone-path.md`.

## 2026-11-14: what the phone keeps

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** phone-path decided the installed web app stores no balances or transactions. Does the native app keep anything?

**Options considered:**
- Nothing but the server's address and the token: matches the web app and the privacy policy as written, and rules out widgets and reminders.
- The last pages loaded, so the app opens offline to last-known numbers marked with their age.
- Offline editing that syncs later: large, because the server has no sync.

**The decision:** each person chooses, asked once at set-up, with **Nothing** as the default and **Last-known numbers** as the other level. The choice can be changed in the app's settings. Offline editing isn't in this plan: it's roadmap item 27.

**What it changes:** the plan gains phase 8, and `docs/privacy.md` is updated before that phase ships. Until then the app keeps nothing, as phase 1 builds it.

## 2026-11-14: plain http, the oldest iOS, the look, and the bar on the open Duo

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **Plain `http://` is accepted for home-network addresses only**, with a warning on the Connect screen. The other option was https everywhere, which would shut out a server that's only on the home network without a certificate.
- **iOS 26 and later.** The Duo layouts switch on under iOS 27.1. The other option was iOS 27.1 only: less code, newest phones only.
- **The system's light and dark, with WalletWeather's own colours, and the web app's ten themes later.** Carrying the themes over from the start meant ten palettes to check on every screen while the screens are still changing. The themes are phase 9.
- **On the open Duo the pages are on the system's bar down the right edge.** The other options were a sidebar on the left listing every page (about a quarter of the width, and it pushes the first pane across the fold) and a setting to switch between the two (both layouts to build and test on every page).

**What it changes:** phase 1 (#87) for all four, and the plan gains phase 9 for the themes.
