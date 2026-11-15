# iOS app: a native app for iPhone and iPhone Duo

Tracking issue: #93

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Connect and Dashboard | #87 | Released in 1.50.0 (2026-11-15; web 1.72.0, schema 19, iOS 0.1.1); simulator screenshots on #87; waiting on your phone check |
| 2. Forecast | #88 | Released in 1.52.0 (2026-11-15; iOS 0.2.0); waiting on your phone check |
| 3. Bills & income and Calendar | #89 | Released in 1.53.0 (2026-11-15; iOS 0.3.0); waiting on your phone check |
| 4. The Duo's big screen | #90 | Open (after phase 3) |
| 5. The other pages and app settings | #91 | Released in 1.54.0 (2026-11-15; iOS 0.4.0); waiting on your phone check |
| 6. TestFlight and the App Store | #92 | Open (waits on legal-risk phase 5, #49) |
| 7. More ways to sign in | #100 | Open (after phase 1; email and password after phone-path phase 3, #43) |
| 8. Kept on the phone | #101 | Open (after phase 5) |
| 9. The web app's themes | #102 | Open (after phase 5) |
| 10. Search everything | #112 | Open (after phases 3 and 5, and #111: one search on the server and in the web app) |

Phase 1 built on 2026-11-15: server 1.50.0 (the "sign in an app" page and its two endpoints, `current_balance` on the Dashboard, schema 19), web 1.72.0 (the "Open in WalletWeather" button) and the iOS app 0.1.0 (Connect, sign-in, the Important notice, the frame and the Dashboard). Verified by the server tests (pytest, all passing), `swift test` in `apps/ios/WalletWeatherKit` against samples recorded from the demo server, and simulator screenshots on the Duo (closed, open on its side, open upright) and an iPhone 17, which found two layout bugs fixed in iOS 0.1.1; released in v1.50.0 the same day. The Cloudflare part waits on your phone (see `docs/dev/decisions/ios-app.md`, "how the Cloudflare sign-in reaches the app").

Phase 2 built on 2026-11-15, before your phone check of phase 1 (your call): server 1.52.0 (`token_access` in `/api/me`, `category_id` on forecast lines, a save may keep a line's category on a shared account) and the iOS app 0.2.0 (Forecast with cards closed, chart, table and editor or summary open, swipe to mark paid, Add transaction, transaction search). How it marks paid, adds and opens search results was settled the same day (`docs/dev/decisions/ios-app.md`, "marking paid, adding a transaction, and search results"). Verified by the server tests (`tests/test_app_forecast.py`), `swift test` on samples recorded from the demo server, the live tests in `LiveServerTests.swift` against a demo server (mark paid at another amount and undo, add and delete), and simulator screenshots on the Duo closed, open on its side and open upright, which found three layout bugs fixed before the commit; released in v1.52.0 the same day.

Phase 3 built on 2026-11-15: server 1.53.0 (`next_date` and `next_dates` on `/api/recurring`; changing a bill may keep its category on a shared account) and the iOS app 0.3.0 (Bills & income, Calendar, Move money from the + menu). Its four choices are in `docs/dev/decisions/ios-app.md` ("the Calendar's accounts, moving money, skipping and ending"). Verified by the server tests (`tests/test_app_bills.py`), `swift test` on samples recorded from the demo server, and the live tests against a demo server (add, skip, find on the Calendar and end a bill; move money). Released in v1.53.0 the same day; no simulator screenshots yet (the Duo simulator hung on install).

Phase 5 built on 2026-11-15: server 1.54.0 (`today=` on Net worth, Budgets and report runs) and the iOS app 0.4.0 (Net worth, Budgets and Reports under More; Appearance with AMOLED black and Sepia; the app lock, asking after a minute away; the app-switcher cover). Verified by the server tests (`tests/test_app_more.py`), `swift test` on samples recorded from the demo server (with three budgets added), and a live test against it. No simulator screenshots: the Duo simulator hangs on install. Released in v1.54.0 the same day.

Written 2026-11-14 from a review of the app at 1.35.0 (web 1.59.0, schema 14). Until now the only notes on a native app were `apps/ios/README.md` and the "ready for native apps later" goal of `Plans/phone-path.md`.

All thirteen open questions were settled on 2026-11-14 (`docs/dev/decisions/ios-app.md`). Questions 1 to 7 made phase 1 bigger and added phases 7 to 9.

Order: phases 1, 2, 3 and 5 in turn; then 4, 7, 8, 9 and 10 in any order; 6 whenever you want it on TestFlight.

Mockups: <https://claude.ai/artifact/4P7y4vUZww5xJGAq1TPKcc> (a private page; drawn from this plan, not screenshots of a build).

Sessions: may span — each phase ends with a build on your phone and your check before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Connect and Dashboard | Opus | Sonnet: record the sample responses, and write the decoding tests and the tests for the new sign-in endpoints | Sets what everything else sits in: sign-in through the sheet and Cloudflare, the API client, and the layout that changes when the Duo opens. |
| 2. Forecast | Opus | Sonnet: tests for the editing calls | The page used most, and the first with editing and two panes. |
| 3. Bills & income and Calendar | Sonnet | none | Follows phase 2's list, editor and two-pane patterns. |
| 4. The Duo's big screen | Opus | none | New system features (the hinge, Split View, a second window) that have to be tried in the simulator before they're designed. |
| 5. The other pages and app settings | Sonnet | Haiku: list the response fields each page reads | Read-only pages on patterns already built. |
| 6. TestFlight and the App Store | Sonnet | none | Packaging and paperwork; most steps are yours. |
| 7. More ways to sign in | Sonnet | none | Two additions on phase 1's sign-in. Switch to Opus if a QR generator has to be chosen and licence-checked. |
| 8. Kept on the phone | Opus | Sonnet: tests that nothing is left behind | A privacy decision: what is stored, how it's protected, and when it's deleted. |
| 9. The web app's themes | Sonnet | none | Ten palettes applied to screens already built. |
| 10. Search everything | Sonnet | none | One screen on patterns already built, over an endpoint that exists by then. |

## Open questions

All thirteen were settled on 2026-11-14: the answers are below and the reasoning is in [`docs/dev/decisions/ios-app.md`](../docs/dev/decisions/ios-app.md). Nothing is open.

1. ~~**How does the app sign in?**~~ All four ways, with the web sign-in sheet first: the sheet, the "Open in WalletWeather" link and paste in phase 1; the QR code and email and password in phase 7.
2. ~~**How does the app get past Cloudflare Access?**~~ The app signs in to Cloudflare itself by default, and takes a service token as the alternative. Both are in phase 1. Carrying the Cloudflare sign-in from the sheet to the app's own requests isn't proven yet, so it's tried first.
3. ~~**Is anything kept on the phone?**~~ Each person chooses, asked once at set-up: Nothing (the default) or Last-known numbers. That's phase 8; until then the app keeps nothing. Offline editing is roadmap item 27.
4. ~~**Plain `http://` on the home network?**~~ Home-network addresses only, with a warning on the Connect screen.
5. ~~**Oldest iOS?**~~ iOS 26 and later; the Duo layouts switch on under iOS 27.1.
6. ~~**How does it look?**~~ The system's light and dark with WalletWeather's colours; the web app's ten themes come later, in phase 9. AMOLED black and Sepia were added the same day as choices in the app's settings (phase 5).
7. ~~**Where do the pages go on the open Duo?**~~ The system's bar down the right edge. The sidebar isn't built.
8. ~~**What does the second pane hold on the open Duo?**~~ Before you tap anything, the page's chart and totals; then what you tap (a line's editor, a day's lines) takes that place. The right half is never empty.
9. ~~**How much can be edited from the phone?**~~ The day-to-day edits are in the app (mark a line as paid with its real amount and date, add, change or delete a transaction, add, change or skip a bill, move money between accounts). Set-up stays on the web (accounts, categories, tags and rules, budgets, sharing, CSV import, building reports, backups, the Admin pages, deleting your account).
10. ~~**Does the app lock?**~~ Touch ID or Face ID is offered once at first sign-in and can be changed in the app's settings. The numbers are always hidden in the app switcher.
11. ~~**How does Apple's reviewer get in?**~~ Sample data built into the app, behind "Try the demo" on the Connect screen. No server is needed, and anyone can try the app before setting one up.
12. ~~**iPad and Mac?**~~ iPhone only for now.
13. ~~**Do the kept numbers go into the phone's backups?**~~ No. They're left out of iCloud and computer backups, so a restored phone starts empty.

## The plan

**Goal:** a native app for iPhone that signs in to your own WalletWeather server and does the everyday jobs well: see where each balance is heading, mark what has really been paid, add a transaction, check the bills and the calendar. On an iPhone Duo it works like any iPhone when closed and uses the big screen when open: two panes instead of one, the full forecast table, and a few things only a screen that size can do.

**Carried over from earlier decisions:**
- The server is reached over HTTPS through a Cloudflare Tunnel with Zero Trust rules (phone-path).
- The app signs in with an API token that is full access or read-only (phone-path, phase 2). Tokens can also be admin level (phone-path, decided 2026-11-15), but the app never asks for one: Admin stays on the web.
- The first sign-in shows the Important notice (legal-risk phase 2): `GET /api/me` returns `notice_required`.
- The apps collect nothing, and the store privacy policy is `docs/privacy.md` (legal-risk phase 5).
- The name is cleared before any store listing (legal-risk phase 5, #49).
- No new copyleft code. This plan goes further: no third-party packages at all.

**Decided 2026-11-14** ([the decision pages](../docs/dev/decisions/ios-app.md)):
- Four ways to sign in, the web sign-in sheet first; then the "Open in WalletWeather" link with paste, a QR code, and email and password.
- Past Cloudflare Access by signing in to Cloudflare in the app, with a service token as the alternative.
- What the phone keeps is each person's choice at set-up: Nothing by default, or Last-known numbers.
- Plain `http://` for home-network addresses only, with a warning.
- iOS 26 and later.
- The system's light and dark; the web app's ten themes later.
- On the open Duo, the system's bar down the right edge.
- On the open Duo, the right half shows the page's summary until you tap something, then what you tapped.
- Day-to-day edits in the app; set-up stays on the web.
- The app lock is offered once at first sign-in.
- Kept numbers are left out of the phone's backups.
- "Try the demo" opens the app on built-in sample data, which is how Apple's reviewer gets in.
- iPhone only for now: no iPad or Mac.
- AMOLED black and Sepia join Light and Dark as choices in the app's settings.
- Search finds everything (transactions, bills and income, accounts, categories and reports), and the web app gains the same search (#111). Its button is the round one beside the pages bar; + moves to the top corner of each page.
- Liquid Glass on the cards as well as the bars, following the phone's glass setting.

**What the review found** (app 1.35.0, web 1.59.0, schema 14):
- **The web app's phone layout already says what a phone needs.** A bar with Dashboard, Forecast, Bills & income, Calendar and More (usability phase 4); Forecast lines as cards that open to edit; Transactions folded into Forecast (1.32.6); Bills & income working like Forecast (1.34.0). The native app keeps that shape, so the two feel like one product.
- **The server does the arithmetic.** `GET /api/accounts/{id}/forecast` returns every line with its forecast and actual amounts and both running balances; `/api/dashboard`, `/api/dashboard/charts`, `/api/calendar`, `/api/networth`, `/api/budgets/progress` and `/api/subscriptions` return numbers ready to show. The app draws; it doesn't forecast.
- **The viewer's date is already a parameter** (`today=`), so "today" on the phone is right whatever time zone the server runs in.
- **About 90 endpoints, all JSON, all behind the session cookie.** No tokens yet (#42), and no login rate limiting, password reset or two-step sign-in (roadmap items 13 to 15). Google sign-in is a browser redirect that a native app can't follow without more server work.
- **Responses have no declared shape.** They are hand-built dictionaries, so `/openapi.json` doesn't describe them, and a change made for the web page could break the app unnoticed. Each endpoint the app reads gets a shape test on the server and a recorded sample that the app's own tests decode.
- **Amounts travel as plain numbers and dates as `YYYY-MM-DD` text.** The app turns amounts into decimals for display and leaves the sums to the server.
- **Each account says what you may do with it** (`level` in `/api/accounts`: owner, edit or read). The app hides editing on a read-only account, and everywhere under a read-only token.
- **Nothing on the server can notify a phone** (roadmap item 6 isn't built), so reminders and widgets are outside this plan.
- **Money data is encrypted on the server, and the privacy policy says nothing about data kept on a phone:** one reason for the "nothing kept on the phone" assumption (open question 3).

**How it's built:**
- SwiftUI, one app for every iPhone on iOS 26 and later. Layout follows the width the system reports (compact or regular), never the device model or which way it's turned, as Apple asks for the Duo.
- `apps/ios/WalletWeather.xcodeproj` for the app, and `apps/ios/WalletWeatherKit`, a local Swift package for everything with no screen: the API client, the models, money and date formatting. The package is tested with `swift test`, with no simulator.
- System frameworks only: SwiftUI, Swift Charts, the Keychain, LocalAuthentication. Nothing to add to the licence list.
- The system's own tab bar, navigation, lists and sheets, so iOS places and adapts them in each way the Duo can be held.
- Liquid Glass throughout: the bar, the sheets and the round buttons use the system's glass, and the app's own cards and panels are glass too. All of it follows the phone's Liquid Glass setting (a slider from clear to tinted in iOS 27) and turns solid under Reduce Transparency or Increase Contrast. Behind the cards, each page carries a soft tint of the look's accent colour fading down from the top, so the glass has something to show.
- The app has its own version number (from 0.1.0), listed in `CHANGELOG.md` beside the app, web and schema versions. It names the oldest server version it works with and checks `GET /api/version` on connecting.
- Changes under `apps/ios` already don't rebuild the container image.

**The iPhone Duo** (from Apple's "Prepare your app for iPhone Duo" tech talk and write-ups of its companion talks; the last three points are from write-ups only and are checked in the simulator in phases 1 and 4):
- A 5.4-inch front screen and a 7.6-inch inner screen of the same shape, iOS 27, Touch ID in the side button, two apps side by side on the inner screen. Xcode 27.1 on this Mac has an iPhone Duo simulator that opens, closes, turns and half-folds.
- Closed, it reports a compact width like any iPhone. Open, it reports a regular width and height however it's turned. The standard split layout collapses to one column when the phone closes and comes back when it opens.
- The system's bars stand down the right edge when the Duo is closed and when it's open on its side, and run along the bottom when it's open and upright. A sidebar on the inner screen is something an app opts in to, and this app doesn't.
- The margins the system keeps clear aren't the same on each side, so nothing is centred by assuming they are.
- The fold is reported as closed, partly open or open, with its angle.
- A second window of the same app can be opened on the inner screen only.

**How the bigger screen is used:**
1. **Two panes that meet at the fold.** The list stays on the left half while what you tapped opens on the right; until you tap, the right half shows the page's chart and totals. Nothing you need to read or tap sits on the fold.
2. **The full forecast table** (forecast and actual side by side, the difference, the balance) where the front screen shows cards.
3. **Accounts beside charts** on the Dashboard, where the front screen stacks them.
4. **A month you can read:** amounts written in each day of the Calendar, with the tapped day's lines beside it.
5. **Two accounts side by side** (phase 4).
6. **WalletWeather beside your bank's app**, for confirming what's cleared (phase 4).
7. **Half open, like a small laptop:** the chart above the fold, the number pad below it (phase 4).
8. **Closing it keeps your place:** a line open in the right pane becomes a sheet on the front screen, with what you'd typed.

**Out of scope:** the Android app; iPad and Mac (iPhone only for now); an Apple Watch app; widgets and bill reminders (they need phase 8's kept numbers first, or a way for the server to reach the phone); offline editing (roadmap item 27); Siri and Shortcuts; signing up for an account inside the app; more than one server at a time; and the set-up that stays on the web (accounts, categories, tags and rules, budgets, sharing, CSV import, building reports, backups, the Admin pages, deleting your account).

### Phase 1: Connect and Dashboard

Depends on phone-path phase 2 (#42, API tokens). The biggest phase: it may take two sessions, sign-in first.

- `apps/ios/WalletWeather.xcodeproj`: a SwiftUI app for iPhone (iOS 26 and later), written by the session and built from the command line. Its version starts at 0.1.0, `CHANGELOG.md` gains an iOS version beside the other three, and the release routine in `CLAUDE.md` gains it too.
- `apps/ios/WalletWeatherKit`: the API client, the models and the formatting, tested with `swift test` against sample responses recorded from the demo server.
- **Tried first, because it's the least certain part:** signing in through the system's sign-in sheet and carrying the Cloudflare sign-in over to the app's own requests. Google refuses to sign in inside an app's own web view, so the sheet has to be the system's, and the system's sheet doesn't share its Cloudflare session with the app. If there's no clean way to hand it over, you're told before anything else is built, and the service token is the way through until there is.
- The Connect screen: the server's address, then **Sign in**, which opens the server's own sign-in page in the system's sheet (Cloudflare first when it's in front, then your email and password or Google) and comes back signed in. Under "Other ways": the "Open in WalletWeather" link beside a new token in the web app's Settings, and pasting a token. Under "Advanced": the two fields for a Cloudflare service token.
- Plain `http://` is accepted for home-network addresses only, with a warning on the Connect screen.
- The token is kept in the Keychain, on this device only and never in iCloud. Signing out removes it. Nothing else is kept on the phone (phase 8 adds the choice).
- The Important notice at first sign-in, as the web app shows it.
- A server check on connecting: a server older than the app needs gets a plain message, not a broken screen.
- The frame every page sits in: the five places of the web app's phone bar, one column when the Duo is closed or on any other iPhone, two panes when it's open. The system's own bar, which iOS stands down the right edge on the Duo. The round button beside the bar is kept for Search (phase 2); a page's own actions, such as +, sit in its top corner.
- Light and dark, following the phone, with WalletWeather's colours.
- Glass: the bar, sheets, round buttons and the cards are Liquid Glass. Checked with the phone's Liquid Glass setting at each end, with Reduce Transparency on and with Increase Contrast on: the numbers on a card must stay easy to read in every case, and the cards turn solid when the phone asks for less transparency.
- Dashboard, read-only: the account cards (balance today, forecast and actual month-end, the month's low and high with their dates), "rest of this month", the charts with the Month / 30 days / 90 days switch, and pinned reports. Open Duo: accounts on the left half, charts on the right.
- No connection, a slow server, an expired token and an expired Cloudflare session each get their own plain message with a retry.
- Server, on top of #42: a "sign in an app" page that asks you to confirm and hands the app a code that works once, and an endpoint that swaps the code for a token named after the phone, so it shows and can be revoked in Settings; the "Open in WalletWeather" link in Settings. Tests for each new endpoint, and shape tests for `/api/version`, `/api/me`, `/api/accounts`, `/api/dashboard` and `/api/dashboard/charts`. The app and web versions bump.
- `apps/ios/README.md` is rewritten for how the app is really built and run.

**You:** in person, once: pick your signing team in Xcode so a build can go on your phone. Then sign in on your phone through Cloudflare, with no service token entered, and look at the Dashboard with the Duo closed and open.

**Done when:** `swift test` and the server tests pass; the phase issue has simulator screenshots of the Connect screen and the Dashboard on the Duo (closed, open on its side, open upright) and on a regular iPhone; on your phone the Sign in button takes you from nothing to your real accounts without typing a token; the phone's token shows in the web app's Settings and revoking it signs the phone out; closing and opening the Duo keeps your place.

### Phase 2: Forecast

Depends on phase 1.

- One account at a time with the web app's account switcher; month by month with previous and next; the summary (balance today, forecast and actual month-end).
- Closed: each line is a card, as in the web app's phone layout (name and amount, the forecast and actual dates, category, both balances, the difference when there is one). Tapping a line opens its editor as a sheet.
- Open: the full table on the left (date, name, category, forecast, actual, difference, balance) under the balance chart, and the tapped line's editor on the right, so the list stays put while you edit. Before a line is tapped, the right half shows the month's summary: income and spending against plan, what's still to come, the low and high, and the lines that differ from plan.
- Editing, on accounts you may edit: mark a line as paid with its real amount and date, undo that, change its notes and category, add a one-off transaction, delete one. A read-only account or token shows no edit controls.
- Search: the round button beside the pages bar opens it, and + sits in the top corner of the page. In this phase it finds transactions, through the search the server already has; phase 10 widens it to everything.
- Server: shape tests for the forecast, transaction and search endpoints the app calls.

**You:** on your phone, mark one bill as paid with a different amount, add a transaction, then delete it. Do the same with the Duo open.

**Done when:** tests pass; the issue has screenshots closed and open; your edits show in the web app straight away; closing the Duo in the middle of an edit keeps it open on the front screen.

### Phase 3: Bills & income and Calendar

Depends on phase 2 (its list, editor and two-pane patterns).

- Bills & income: All accounts and each account; the monthly totals (bills, income, what's left); each line with its amount, how often, and its next date. Add, change, end and skip once, on accounts you may edit. Editing several at once stays on the web.
- Calendar: the month with each day's bills and paychecks, the day's closing balance, and today marked. Closed: a compact month with dots, and the tapped day's lines listed under it. Open: the month on the left with amounts written in each day, and the tapped day's lines on the right.
- Open, before anything is tapped, the right half shows the page's summary: the monthly totals for Bills & income, and today's lines and balances for the Calendar.
- Moving money between two accounts, from the + button.
- Server: shape tests for `/api/recurring`, `/api/subscriptions`, `/api/calendar` and `/api/transfers`.

**You:** add a bill on the phone and find it on the Calendar; skip one occurrence; move money between two accounts.

**Done when:** tests pass; the issue has screenshots closed and open; what you add shows on the web app's Bills & income page and Calendar.

### Phase 4: The Duo's big screen

Depends on phase 3. Each part is tried in the Duo simulator first and kept only if it works well; each can ship on its own.

- **Compare:** two accounts, or one account in two months, side by side, one in each half, scrolling together by date.
- **Beside another app:** WalletWeather in half the inner screen next to your bank's app or a statement, set up for confirming lines quickly: the lines still unconfirmed, each with "Paid as planned" and a box for a different amount.
- **Half open, like a small laptop:** the chart or the list above the fold, and the line being edited with its number pad below it. It uses the fold reading iOS 27.1 offers, which is checked against Apple's documentation before the detail is designed.
- **A second WalletWeather window** on the inner screen (Forecast beside Calendar), if iOS allows it for this kind of app.
- Dropping a bank's CSV file onto the app is noted for later: importing stays on the web in this plan.

**You:** try each on your Duo and say which to keep.

**Done when:** each part kept has screenshots in the issue and works every way the Duo can be held; each part dropped is recorded here with why.

### Phase 5: The other pages and app settings

Depends on phase 2.

- Under More, read-only: Net worth (the total, its chart, each account), Budgets (spent against each budget this month) and Reports (run a saved report; building one stays on the web).
- The app's settings: the server and who's signed in, Sign out, appearance (Match the phone, Light, Dark, AMOLED black or Sepia; the last two are new looks, drawn in the mockups, and aren't among the web app's themes; each look is checked at each end of the phone's Liquid Glass setting), the app lock (Touch ID or Face ID, offered once at first sign-in, or once after updating for people already signed in, and changeable here), "Open the web app" for everything that stays there, the Important notice, and the versions of the app and the server.
- The numbers are hidden when the app shows in the app switcher.
- The Admin pages stay on the web: an admin sees nothing extra in the app.
- Server: shape tests for `/api/networth`, `/api/budgets/progress` and the saved-report endpoints the app calls.

**You:** open each page on your phone and compare its numbers with the web app's.

**Done when:** tests pass; the issue has screenshots closed and open; each page's numbers match the web app's for the same month.

### Phase 6: TestFlight and the App Store

Waits on legal-risk phase 5 (#49, the name).

- The app icon (from `favicon.svg`), the launch screen, the privacy manifest, and the App Privacy answers ("no data collected").
- `docs/privacy.md` read against what the app really does (the token in the Keychain, and what phase 8 keeps if it has shipped) and updated first if it needs it.
- "Try the demo" on the Connect screen: the app opens on sample data built into it, with no server, so Apple's reviewer and anyone curious can get in. The samples are recorded from the demo server and decoded by the same tests as the real responses, so they can't drift from what the server sends.
- iPhone only: iPad and Mac stay switched off.
- A TestFlight build for your own devices first; the public listing only after your check.
- The store's text and screenshots, with the Duo closed and open.
- README: where to get the app, and the oldest server version it works with.

**You:** join the Apple Developer Program if you haven't (a yearly fee); finish #49's name search; create the app's record in App Store Connect; press Submit. If the session is to upload builds, its App Store Connect key goes in a gitignored file.

**Done when:** the TestFlight build runs on your phone against your server; for the store, Apple has approved it.

### Phase 7: More ways to sign in

Depends on phase 1; the email and password part also on phone-path phase 3 (#43). Each part can ship on its own.

- **QR code:** the web app's Settings shows a code beside a new token and the app scans it with the camera, which is handy when Settings is open on a computer. Something has to draw the code: a small generator added to the server (licence-checked, and listed in `THIRD_PARTY_NOTICES.md`) or one written for the page. Chosen when the phase starts.
- **Email and password:** typed into the app and swapped for a token by `POST /api/auth/token` (phone-path phase 3, which needs login rate limiting first). Not offered to accounts that only sign in with Google.
- The Connect screen lists all four ways, the sign-in sheet first.

**You:** sign in each new way once, and revoke each token afterwards.

**Done when:** tests pass; each way signs in on your phone; the camera is asked for only when you choose the QR code.

### Phase 8: Kept on the phone

Depends on phase 5 (the app's settings).

- Set-up asks once what this phone keeps: **Nothing** (the default: the app needs a connection, as before) or **Last-known numbers** (the app opens without a connection to the pages it last loaded, each marked with when it was loaded). The choice can be changed in the app's settings, and people who already have the app stay on Nothing until they change it.
- What's kept can't be read while the phone is locked, is left out of iCloud and computer backups, and is deleted on signing out or on switching back to Nothing.
- Editing still needs a connection.
- `docs/privacy.md` and the App Privacy answers are updated before this ships: the numbers stay on the phone, so nothing is collected, but the policy has to say what's stored.

**You:** choose Last-known numbers, load the Dashboard, switch on airplane mode and open the app again. Then sign out and check that nothing opens.

**Done when:** tests pass; with no connection the app shows the last pages with their age; after signing out or choosing Nothing, the app's storage in the simulator holds no numbers.

### Phase 9: The web app's themes

Depends on phase 5.

- The web app's ten themes in the app, beside Match the phone, Light, Dark, AMOLED black and Sepia.
- Whether the app follows the theme saved on the server or keeps its own choice is asked when the phase starts.

**You:** look at each page in the themes you use, closed and open.

**Done when:** every page has been checked in each theme, closed and open, and its text is readable in each.

### Phase 10: Search everything

Depends on phases 3 and 5 (the pages a result opens) and on #111 (one search on the server and in the web app).

- The search opened by the round button beside the pages bar finds transactions, bills and income, accounts, categories and saved reports, grouped by kind, through the server's new search endpoint.
- Tapping a result opens it where it lives: a transaction or a bill in its editor, an account in Forecast, a category as its transactions, a report run.
- Open Duo: the results stay on the left half and the tapped result opens on the right.
- Nothing about a search is kept on the phone.

**You:** search for a bill, a shop and a category on your phone, with the Duo closed and open.

**Done when:** tests pass; each kind of result opens the right place; the issue has screenshots closed and open.
