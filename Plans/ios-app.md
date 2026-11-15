# iOS app: a native app for iPhone and iPhone Duo

Tracking issue: #93

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Connect and Dashboard | #87 | Open (waits on phone-path phase 2, #42, and open questions 1 to 7) |
| 2. Forecast | #88 | Open (after phase 1; open questions 8 and 9) |
| 3. Bills & income and Calendar | #89 | Open (after phase 2) |
| 4. The Duo's big screen | #90 | Open (after phase 3) |
| 5. The other pages and app settings | #91 | Open (after phase 2; open questions 9 and 10) |
| 6. TestFlight and the App Store | #92 | Open (waits on legal-risk phase 5, #49, and open questions 11 and 12) |

Nothing built yet. Written 2026-11-14 from a review of the app at 1.35.0 (web 1.59.0, schema 14). Until now the only notes on a native app were `apps/ios/README.md` and the "ready for native apps later" goal of `Plans/phone-path.md`.

Mockups: <https://claude.ai/artifact/4P7y4vUZww5xJGAq1TPKcc> (a private page; drawn from this plan, not screenshots of a build).

Sessions: may span — each phase ends with a build on your phone and your check before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Connect and Dashboard | Opus | Sonnet: record the sample responses and write the decoding tests | Sets what everything else sits in: sign-in, the API client, and the layout that changes when the Duo opens. |
| 2. Forecast | Opus | Sonnet: tests for the editing calls | The page used most, and the first with editing and two panes. |
| 3. Bills & income and Calendar | Sonnet | none | Follows phase 2's list, editor and two-pane patterns. |
| 4. The Duo's big screen | Opus | none | New system features (the hinge, Split View, a second window) that have to be tried in the simulator before they're designed. |
| 5. The other pages and app settings | Sonnet | Haiku: list the response fields each page reads | Read-only pages on patterns already built. |
| 6. TestFlight and the App Store | Sonnet | none | Packaging and paperwork; most steps are yours. |

## Open questions

Each has a working assumption, and the mockups are drawn to those assumptions.

1. **How does the app sign in?** (blocks phase 1) It holds an API token (phone-path phase 2, #42), never your password. The choices for getting the token onto the phone: (a) create it in the web app's Settings on the phone and tap "Open in WalletWeather", with paste as the fallback; (b) a QR code shown in Settings and scanned by the app, which needs a QR generator added to the server (a new dependency to licence-check); (c) type your email and password into the app (phone-path phase 3; it needs login rate limiting first and can't cover Google-only accounts); (d) a web sign-in sheet inside the app that handles local, Google and Cloudflare sign-in at once (the most server work). Working assumption: (a) first, and (c) when phone-path phase 3 lands.
2. **How does the app get past Cloudflare Access?** (blocks using phase 1 away from home, not building it) This is phone-path's open question 1. Working assumption: the Connect screen has two optional fields for a Cloudflare service token, kept in the Keychain and sent with every request; an Access rule that lets `/api/*` through would need nothing in the app.
3. **Is anything kept on the phone?** (blocks phase 1) phone-path decided the installed web app stores no balances or transactions. The choices here: (a) the same: only the server's address and the token, in the Keychain, and offline the app says so; (b) also keep the last pages loaded (encrypted by iOS while the phone is locked), so the app opens to the last-known numbers offline, marked with their age; (c) offline editing that syncs later (large, and the server has no sync). Widgets and bill reminders need at least (b). Working assumption: (a).
4. **Plain `http://` on the home network?** (blocks phase 1) iOS refuses plain http unless an app allows it, and the README's quick start runs the server at `http://localhost:8300`. The choices: allow http for local-network addresses only, with a warning on the Connect screen; or https only. Working assumption: local addresses only, with the warning.
5. **Oldest iOS?** (blocks phase 1) iOS 26 and later, with the Duo layouts switching on under iOS 27.1; or iOS 27.1 only (less code, newest phones only). Working assumption: iOS 26 and later.
6. **How does it look?** (blocks phase 1) Follow the phone's light and dark setting with WalletWeather's own colours (blue accent, green for money in, red for money out) on the system's bars, lists and sheets; or carry over the web app's ten themes and the theme choice saved on the server. Working assumption: system light and dark; the mockups show dark.
7. **Where do the pages go on the open Duo?** (blocks phase 1) The system's bar down the right edge, which is what iOS does by default and leaves the most room for two panes; or a sidebar on the left listing every page, with no "More", which takes about a quarter of the width. Working assumption: the right-edge bar. The mockups show both.
8. **What does the second pane hold on the open Duo?** (blocks phases 2 and 3) Working assumption, as drawn: Dashboard, accounts beside charts; Forecast, the full table beside the open line's editor; Bills & income, the list beside the editor; Calendar, the month beside the tapped day's lines.
9. **How much can be edited from the phone?** (blocks phases 2, 3 and 5) Working assumption: the day-to-day edits are in the app (mark a line as paid with its real amount and date, add, change or delete a transaction, add, change or skip a bill, move money between accounts), and set-up stays on the web (accounts, categories, tags and rules, budgets, sharing, CSV import, building reports, backups, the Admin pages, deleting your account).
10. **Does the app lock?** (blocks phase 5) Ask for Touch ID or Face ID when the app opens: off unless switched on, on from the start, or offered once at first sign-in. Working assumption: offered once at first sign-in and changeable in the app's settings. The numbers are always hidden in the app switcher.
11. **How does Apple's reviewer get in?** (blocks phase 6) App Store review needs a working sign-in, and no public demo is planned (`Plans/legal-risk.md`). The choices: sample data built into the app behind "Try the demo" on the Connect screen (no server needed, and anyone can try the app before setting one up); a temporary demo server for each review; or stay on TestFlight for your own devices and skip the public listing. Working assumption: built-in sample data.
12. **iPad and Mac?** (blocks phase 6) The open-Duo layouts are driven by width, so they would carry over to an iPad with little work. Working assumption: iPhone only for now.

## The plan

**Goal:** a native app for iPhone that signs in to your own WalletWeather server and does the everyday jobs well: see where each balance is heading, mark what has really been paid, add a transaction, check the bills and the calendar. On an iPhone Duo it works like any iPhone when closed and uses the big screen when open: two panes instead of one, the full forecast table, and a few things only a screen that size can do.

**Carried over from earlier decisions:**
- The server is reached over HTTPS through a Cloudflare Tunnel with Zero Trust rules (phone-path).
- The app signs in with an API token that is full access or read-only, and a token never reaches the Admin endpoints (phone-path, phase 2 and its open question 2).
- The first sign-in shows the Important notice (legal-risk phase 2): `GET /api/me` returns `notice_required`.
- The apps collect nothing, and the store privacy policy is `docs/privacy.md` (legal-risk phase 5).
- The name is cleared before any store listing (legal-risk phase 5, #49).
- No new copyleft code. This plan goes further: no third-party packages at all.

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
- SwiftUI, one app for every iPhone. Layout follows the width the system reports (compact or regular), never the device model or which way it's turned, as Apple asks for the Duo.
- `apps/ios/WalletWeather.xcodeproj` for the app, and `apps/ios/WalletWeatherKit`, a local Swift package for everything with no screen: the API client, the models, money and date formatting. The package is tested with `swift test`, with no simulator.
- System frameworks only: SwiftUI, Swift Charts, the Keychain, LocalAuthentication. Nothing to add to the licence list.
- The system's own tab bar, navigation, lists and sheets, so iOS places and adapts them in each way the Duo can be held.
- The app has its own version number (from 0.1.0), listed in `CHANGELOG.md` beside the app, web and schema versions. It names the oldest server version it works with and checks `GET /api/version` on connecting.
- Changes under `apps/ios` already don't rebuild the container image.

**The iPhone Duo** (from Apple's "Prepare your app for iPhone Duo" tech talk and write-ups of its companion talks; the last three points are from write-ups only and are checked in the simulator in phases 1 and 4):
- A 5.4-inch front screen and a 7.6-inch inner screen of the same shape, iOS 27, Touch ID in the side button, two apps side by side on the inner screen. Xcode 27.1 on this Mac has an iPhone Duo simulator that opens, closes, turns and half-folds.
- Closed, it reports a compact width like any iPhone. Open, it reports a regular width and height however it's turned. The standard split layout collapses to one column when the phone closes and comes back when it opens.
- The system's bars stand down the right edge when the Duo is closed and when it's open on its side, and run along the bottom when it's open and upright. A sidebar on the inner screen is something an app opts in to (open question 7).
- The margins the system keeps clear aren't the same on each side, so nothing is centred by assuming they are.
- The fold is reported as closed, partly open or open, with its angle.
- A second window of the same app can be opened on the inner screen only.

**How the bigger screen is used:**
1. **Two panes that meet at the fold.** The list stays on the left half while what you tapped opens on the right. Nothing you need to read or tap sits on the fold.
2. **The full forecast table** (forecast and actual side by side, the difference, the balance) where the front screen shows cards.
3. **Accounts beside charts** on the Dashboard, where the front screen stacks them.
4. **A month you can read:** amounts written in each day of the Calendar, with the tapped day's lines beside it.
5. **Two accounts side by side** (phase 4).
6. **WalletWeather beside your bank's app**, for confirming what's cleared (phase 4).
7. **Half open, like a small laptop:** the chart above the fold, the number pad below it (phase 4).
8. **Closing it keeps your place:** a line open in the right pane becomes a sheet on the front screen, with what you'd typed.

**Out of scope:** the Android app; an Apple Watch app; widgets, bill reminders and anything else that needs data kept on the phone or a way for the server to reach it; Siri and Shortcuts; signing up for an account inside the app; more than one server at a time; and everything open question 9 leaves on the web.

### Phase 1: Connect and Dashboard

Depends on phone-path phase 2 (#42, API tokens) and open questions 1 to 7.

- `apps/ios/WalletWeather.xcodeproj`: a SwiftUI app for iPhone, written by the session and built from the command line. Its version starts at 0.1.0, `CHANGELOG.md` gains an iOS version beside the other three, and the release routine in `CLAUDE.md` gains it too.
- `apps/ios/WalletWeatherKit`: the API client, the models and the formatting, tested with `swift test` against sample responses recorded from the demo server.
- The Connect screen: the server's address, then the token (open question 1) and the optional Cloudflare fields (open question 2). The token is kept in the Keychain, on this device only and never in iCloud. Signing out removes it.
- The Important notice at first sign-in, as the web app shows it.
- A server check on connecting: a server older than the app needs gets a plain message, not a broken screen.
- The frame every page sits in: the five places of the web app's phone bar, one column when the Duo is closed or on any other iPhone, two panes when it's open.
- Dashboard, read-only: the account cards (balance today, forecast and actual month-end, the month's low and high with their dates), "rest of this month", the charts with the Month / 30 days / 90 days switch, and pinned reports. Open Duo: accounts on the left half, charts on the right.
- No connection, a slow server, an expired token and an expired Cloudflare session each get their own plain message with a retry.
- Server: shape tests for `/api/version`, `/api/me`, `/api/accounts`, `/api/dashboard` and `/api/dashboard/charts`. No new endpoints beyond #42, unless open question 1 picks the QR code or the sign-in sheet.
- `apps/ios/README.md` is rewritten for how the app is really built and run.

**You:** in person, once: pick your signing team in Xcode so a build can go on your phone. Then connect the app to your server and look at the Dashboard with the Duo closed and open.

**Done when:** `swift test` and the server tests pass; the phase issue has simulator screenshots of the Connect screen and the Dashboard on the Duo (closed, open on its side, open upright) and on a regular iPhone; on your phone the app connects to your server and shows your real accounts; closing and opening the Duo keeps your place.

### Phase 2: Forecast

Depends on phase 1 and open questions 8 and 9.

- One account at a time with the web app's account switcher; month by month with previous and next; the summary (balance today, forecast and actual month-end).
- Closed: each line is a card, as in the web app's phone layout (name and amount, the forecast and actual dates, category, both balances, the difference when there is one). Tapping a line opens its editor as a sheet.
- Open: the full table on the left (date, name, category, forecast, actual, difference, balance) under the balance chart, and the tapped line's editor on the right, so the list stays put while you edit.
- Editing, on accounts you may edit: mark a line as paid with its real amount and date, undo that, change its notes and category, add a one-off transaction, delete one. A read-only account or token shows no edit controls.
- Search across transactions, from the page's search field.
- Server: shape tests for the forecast, transaction and search endpoints the app calls.

**You:** on your phone, mark one bill as paid with a different amount, add a transaction, then delete it. Do the same with the Duo open.

**Done when:** tests pass; the issue has screenshots closed and open; your edits show in the web app straight away; closing the Duo in the middle of an edit keeps it open on the front screen.

### Phase 3: Bills & income and Calendar

Depends on phase 2 (its list, editor and two-pane patterns).

- Bills & income: All accounts and each account; the monthly totals (bills, income, what's left); each line with its amount, how often, and its next date. Add, change, end and skip once, on accounts you may edit. Editing several at once stays on the web.
- Calendar: the month with each day's bills and paychecks, the day's closing balance, and today marked. Closed: a compact month with dots, and the tapped day's lines listed under it. Open: the month on the left with amounts written in each day, and the tapped day's lines on the right.
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

Depends on phase 2 and open questions 9 and 10.

- Under More, read-only: Net worth (the total, its chart, each account), Budgets (spent against each budget this month) and Reports (run a saved report; building one stays on the web).
- The app's settings: the server and who's signed in, Sign out, appearance (open question 6), the app lock (open question 10), "Open the web app" for everything that stays there, the Important notice, and the versions of the app and the server.
- The numbers are hidden when the app shows in the app switcher.
- The Admin pages stay on the web: an admin sees nothing extra in the app.
- Server: shape tests for `/api/networth`, `/api/budgets/progress` and the saved-report endpoints the app calls.

**You:** open each page on your phone and compare its numbers with the web app's.

**Done when:** tests pass; the issue has screenshots closed and open; each page's numbers match the web app's for the same month.

### Phase 6: TestFlight and the App Store

Waits on legal-risk phase 5 (#49, the name) and open questions 11 and 12.

- The app icon (from `favicon.svg`), the launch screen, the privacy manifest, and the App Privacy answers ("no data collected").
- `docs/privacy.md` read against what the app really does (the token in the Keychain, and anything open question 3 added) and updated first if it needs it.
- The way in for Apple's reviewer (open question 11).
- A TestFlight build for your own devices first; the public listing only after your check.
- The store's text and screenshots, with the Duo closed and open.
- README: where to get the app, and the oldest server version it works with.

**You:** join the Apple Developer Program if you haven't (a yearly fee); finish #49's name search; create the app's record in App Store Connect; press Submit. If the session is to upload builds, its App Store Connect key goes in a gitignored file.

**Done when:** the TestFlight build runs on your phone against your server; for the store, Apple has approved it.
