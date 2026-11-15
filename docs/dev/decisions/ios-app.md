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

## 2026-11-14: the second pane, editing, the app lock, and backups

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **On the open Duo, the right half shows the page's chart and totals until something is tapped, then what was tapped takes that place.** The other options were the right half holding only what's tapped, with a prompt when nothing is (an empty half most of the time), and charts always on the right with editing in a sheet (the sheet would cover the fold).
- **Day-to-day edits are in the app, and set-up stays on the web.** In the app: mark a line as paid with its real amount and date, add, change or delete a transaction, add, change or skip a bill, move money between accounts. On the web: accounts, categories, tags and rules, budgets, sharing, CSV import, building reports, backups, the Admin pages, deleting your account. The other options were a read-only app first (it couldn't confirm a payment) and bringing set-up into the app in a later phase.
- **The app lock is offered once at first sign-in** ("Lock WalletWeather with Touch ID?") and can be changed in the app's settings. The other options were off unless switched on, and on from the start. The numbers are hidden in the app switcher either way.
- **Kept numbers are left out of iCloud and computer backups.** A restored or new phone starts empty and loads them again. Including them would have put copies of the numbers in iCloud or on a computer.

**What it changes:** phases 2 and 3 (#88, #89) for the second pane and editing, phase 5 (#91) for the app lock, and phase 8 (#101) for backups.

## 2026-11-14: Apple's reviewer, and iPad and Mac

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **Apple's reviewer gets in through sample data built into the app**, behind "Try the demo" on the Connect screen. No server is needed, and anyone can try the app before setting one up. The other options were a demo server put on the internet for each review (a public instance each time, which the README warns against) and staying on TestFlight with no public listing.
- **iPhone only for now.** The open-Duo layouts follow the screen's width and would mostly carry over to an iPad, and iPad was picked first, then changed to iPhone only in the same conversation. iPad and Mac can be a later plan.

**What it changes:** phase 6 (#92). With these, none of the plan's thirteen questions is open.

## 2026-11-14: AMOLED black and Sepia

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** Matthew asked for an AMOLED black look and a sepia look in the mockups. Neither is among the web app's ten themes, and the decision so far was the system's light and dark, with the themes in phase 9. Where do the two new looks go?

**Options considered:**
- From the first version: every screen built in phases 1 to 3 would be checked in four palettes while it's still changing.
- With the app's settings, in phase 5: that phase builds the Appearance choice, and the pages are stable by then.
- With the ten themes, in phase 9: light and dark only until then.
- Mockups only, decided later.

**The decision:** phase 5's Appearance choice offers Match the phone, Light, Dark, AMOLED black and Sepia. In the mockups the light and sepia cards carry an outline and a soft shadow on a darker page background, after the first drawing left them hard to tell from the background.

**What it changes:** phase 5 (#91). Phases 1 to 3 still build light and dark only. The web app doesn't gain the two looks.

## 2026-11-14: search, and where its button goes

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** Matthew asked for a search button in the app. What does search find, and where does the button sit? Today the server searches transactions only, and the web app has that as a panel under Forecast.

**Options considered:**
- Transactions only: exactly what the web app does today; bills and lines that haven't happened aren't found.
- Transactions and bills: the server's existing search plus bills and paychecks matched by name in the app. No server change.
- Everything, in the web app too: one search across transactions, bills, accounts, categories and reports. It needs a new search endpoint, and the web app gains a search box to match.
- The button beside the pages bar with + moved to the top corner of each page; two round buttons beside the bar; or a magnifier at the top of each page.

**The decision:** everything, in the web app too. The app's search button is the round one beside the pages bar, the spot iOS gives search, and + moves to the top corner of each page.

**What it changes:** a new piece of server and web work (#111, roadmap item 28); phase 2 (#88) puts the button in place with transaction search; a new phase 10 widens it to everything once #111 has shipped.
