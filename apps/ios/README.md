# WalletWeather for iOS

A native SwiftUI app for iPhone (iOS 26 and later) that signs in to your own
WalletWeather server, or, since iOS 0.19.0, keeps your numbers on the iPhone
with no server at all ("On this iPhone" below). It's being built in phases from
[`Plans/ios-app.md`](../../Plans/ios-app.md) (tracking issue #93). Phase 1
(#87) gives it the Connect screen, sign-in and a read-only Dashboard; phase 2
(#88) adds Forecast, with marking lines paid, adding and deleting
transactions, and transaction search; phase 3 (#89) adds Bills & income, the
Calendar and moving money between accounts; phase 5 (#91) adds Net worth,
Budgets and Reports under More, the looks (Match the phone, Light, Dark,
AMOLED black, Sepia), the app lock and the app-switcher cover; phase 7
(#100) adds email and password and QR-code sign-in; phase 10 (#112) makes
Search find everything through the server's `/api/search` (server 1.56.0;
an older server searches transactions only). It works with a server on
1.54.0 or later. It's on TestFlight for internal testers (from iOS 0.17.1) but
not on the App Store yet (phase 6, #92); otherwise it's built from source and
put on a phone from Xcode. **Try the
demo** on the Connect screen opens it on sample numbers with no server; since
iOS 0.18.0 its Dashboard, charts, Forecast, Calendar and balances are worked
out on the phone by the shared JavaScript core (phase 3 of
[`Plans/standalone.md`](../../Plans/standalone.md), #234).
Bank sync (phase 5 of `Plans/bank-sync.md`, #197) shows its status and Sync
now under Settings, each connection on its own (SimpleFIN, Teller or Plaid,
phase 4 of `Plans/bank-providers.md`, #257), and a bill's bank match settings
in its editor; the sync log stays in the web app. The Unmatched list opens in
the app with a server too (duo-more phase 3, #306), and connecting a bank is
in the app from 0.30.0 (see Bank sync below).

Changes in this folder don't trigger the container build.

## What's here

| Path | What it is |
| --- | --- |
| `project.yml` | The project, as an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Change this, then run `xcodegen generate`. |
| `WalletWeather.xcodeproj` | Generated from `project.yml`, and committed so Xcode opens it without XcodeGen. |
| `WalletWeather/` | The app: screens, the sign-in sheet, the Keychain. |
| `WalletWeatherKit/` | A local Swift package with everything that has no screen: the API client, the models, and money and date formatting. |
| `WalletWeatherKit/Tests/WalletWeatherKitTests/Samples/` | Responses recorded from the demo server, which the tests decode. |
| `WalletWeatherKit/Sources/WalletWeatherKit/Demo/` | The samples "Try the demo" answers from (copies of the test samples), and `household.json`, the demo household's rows the core works the demo's numbers out from (`Scripts/record-household.py` records it). |
| `WalletWeatherKit/Sources/WalletWeatherKit/LocalStore.swift`, `LocalServer.swift` | On this iPhone: the household's SwiftData store, and the local connection that answers the app's requests from it through the core. `LocalTests` checks them. |
| `WalletWeatherKit/Sources/WalletWeatherKit/Core/` | A copy of the shared JavaScript core (`packages/core`), run in JavaScriptCore by `Core.swift`. `Scripts/copy-core.sh` refreshes it; `CoreTests` fails when it's out of date and runs the core over the whole answer key. |
| `WalletWeather/PrivacyInfo.xcprivacy` | The privacy manifest: no tracking, no data collected, and why the app reads its settings and file dates. |
| `Config/Base.xcconfig` | Shared build settings. It reads `Config/Signing.local.xcconfig` if it's there. |

The app uses system frameworks only (SwiftUI, Swift Charts, the Keychain,
AuthenticationServices, CryptoKit, JavaScriptCore) and no third-party packages, so there's
nothing to add to `THIRD_PARTY_NOTICES.md`. XcodeGen is a build tool on the
Mac, not part of the app.

## Building and testing

From `apps/ios`:

```sh
# The package's tests: no simulator needed.
(cd WalletWeatherKit && swift test)

# After changing project.yml (XcodeGen: `brew install xcodegen`):
xcodegen generate

# Build for a simulator:
xcodebuild -project WalletWeather.xcodeproj -scheme WalletWeather \
  -destination 'platform=iOS Simulator,name=iPhone Duo' build
```

**Putting it on your phone.** Signing needs your Apple developer team. Put it
in `Config/Signing.local.xcconfig`, which is gitignored:

```
DEVELOPMENT_TEAM = <your team ID>
```

Then build for the phone from Xcode, or from the command line with
`-destination 'platform=iOS,name=<your phone>' -allowProvisioningUpdates`.
The bundle ID is `net.iptater.walletweather`. Don't change it: the phone's
sign-in is kept in the Keychain under it.

**Uploading to TestFlight.** `Scripts/testflight.sh` archives a Release
build and uploads it with an App Store Connect API key, making the
distribution certificate and profile itself if they're missing. It needs:

- the app's record in App Store Connect, for bundle ID
  `net.iptater.walletweather`;
- an API key with the App Manager role (App Store Connect, Users and Access,
  Integrations). The `.p8` file goes in
  `~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8`, outside the repo;
- `Config/AppStoreConnect.local.env` (gitignored), with the key's ID and the
  issuer ID:

  ```
  ASC_KEY_ID=<key ID>
  ASC_ISSUER_ID=<issuer ID>
  ```

The build number is the number of commits on `HEAD`, so commit before
uploading again. Builds are for internal testers only until the name is
cleared (#49); `TESTFLIGHT_INTERNAL_ONLY=false` lifts that.

**Screenshots without signing in by hand.** In Debug builds only, the app
opens signed in when it's launched with a server and a token:

```sh
SIMCTL_CHILD_WW_DEBUG_SERVER=http://localhost:8300 \
SIMCTL_CHILD_WW_DEBUG_TOKEN=ww_... \
xcrun simctl launch booted net.iptater.walletweather
```

Three more Debug-only settings put it where a screenshot needs it, with no
taps: `SIMCTL_CHILD_WW_DEBUG_PLACE=forecast` (or `search`, `dashboard`, …)
opens that page, `SIMCTL_CHILD_WW_DEBUG_OPEN_LINE=Rent` opens that Forecast
line (or that bill, on Bills & income) in the editor,
`SIMCTL_CHILD_WW_DEBUG_SEARCH=gro` fills in search (with
`SIMCTL_CHILD_WW_DEBUG_SEARCH_OPEN=transaction`, `bill`, `category`,
`report` or `account` opening its first result of that kind), and on the Calendar
`SIMCTL_CHILD_WW_DEBUG_ACCOUNT=Checking` picks an account and
`SIMCTL_CHILD_WW_DEBUG_DAY=2026-11-11` a day. With
`SIMCTL_CHILD_WW_DEBUG_PLACE=calendar` and that day, `WW_DEBUG_OPEN_LINE=Rent`
also opens that line of the day in the line editor (#305), and
`SIMCTL_CHILD_WW_DEBUG_DASH_ACCOUNT=Checking` chooses that account on the
Dashboard's right half, on the open Duo.
`SIMCTL_CHILD_WW_DEBUG_SETTINGS=<page>` opens Settings on one of its pages
(#294): `connections` (the list the card at the top opens, #300),
`connection` (the page of the connection in front), `bank`, `appearance`,
`privacy`, `display` (Dates & display), `backup`, `move`,
`help` or `keep` (Keep on this iPhone, under the connection's page);
`WW_DEBUG_TAGS=1` opens Tags and `WW_DEBUG_BANK` Bank sync;
`WW_DEBUG_UNMATCHED=1` opens Bank sync and, once its lines are counted, the
Unmatched list of the first account with lines waiting (in the demo, the Credit
Card; on the household on this iPhone, as `WW_DEBUG_BANK=unmatched`). On a regular
width (the open Duo, #295) Settings is a sidebar with the chosen page beside
it, and these choose that page there; the open page is kept per window
(`settings.page`), so closing or opening the Duo keeps it.
The Dashboard's bank card (#321) shows in the demo as "N bank lines to match";
`SIMCTL_CHILD_WW_DEBUG_BANK_CARD=reconnect` also makes the demo's first bank need
reconnecting, so the card shows both lines.
`SIMCTL_CHILD_WW_DEBUG_DATES=iso` (or `short`) forces how dates are written
(Settings → Dates & display → Date format, #296), whatever is chosen there or
saved in the web app; `WW_DEBUG_LOOK=<look>` picks the look the same way.
`SIMCTL_CHILD_WW_DEBUG_CUSTOM_THEMES=sample` puts two sample custom themes
(#297) in memory, never in iCloud or the preferences: "Paper" (light, with its
money in faint on the card, so the editor's readability warning shows) and
"Deep sea" (dark). `WW_DEBUG_LOOK=custom-light` or `custom-dark` then shows
the app in one of them, and with `WW_DEBUG_SETTINGS=appearance`,
`SIMCTL_CHILD_WW_DEBUG_THEME_EDITOR=custom-light` (or `custom-dark`, a
theme's name, or `new` for a copy of the look in use) opens the theme editor
over Settings → Appearance. Debug only.
`SIMCTL_CHILD_WW_DEBUG_SCROLL=bottom` opens a Settings page, or the theme
editor, scrolled to its end.
`SIMCTL_CHILD_WW_DEBUG_UNDO=Rent` shows the Forecast's Undo bar for that line
once the page has loaded (#315); it saves nothing and stays until dismissed.
`SIMCTL_CHILD_WW_DEBUG_FAIL_SAVE=offline` opens every editor and sheet (the
line and bill editors, Add transaction, Move money, Skip a date, End, New
account) already showing the problem banner at its top, as if a save had just
failed, and makes every save fail the same way (#311): `offline` (or `1`) and
`slow` offer Try again, `signin` offers Sign in again, `cloudflare` Sign in to
Cloudflare, and `server` (a refusal with the server's reason) and `demo` (the
demo's "doesn't save changes") offer no button. With
`WW_DEBUG_OPEN_LINE` it puts the line editor in that state with no taps.
`SIMCTL_CHILD_WW_DEBUG_CONNECTIONS=sample` fills Settings → Connections for
pictures (#300): two sample servers, "Home" (home.example.com) and "Mum &
Dad" (ww.parents.example), plus the household on this iPhone when the
simulator has one, which is then in front; with none, the app opens in the
demo, so nothing is contacted. They're kept in memory and a throwaway
settings suite only, never in the Keychain, and are gone at the next launch.
Switching to a sample server tries to reach it, and fails. "Mum & Dad" has
had its sign-in end (#302), so the warning symbol and "Sign in again" show on
its row in Connections and in the chip's menu, and on the chip itself while
it's in front; the chip shows whenever there are two or more connections.
`SIMCTL_CHILD_WW_DEBUG_LOCKED_DEMO=1` starts as if the lock had just sent the
app to the demo (#301), whether or not the lock is on: whatever is saved (or
the sample connections, with `WW_DEBUG_CONNECTIONS=sample`) stays behind the
demo, so the chip, its menu's contents and what Connections hides while
locked can be pictured without Face ID. Choosing a real connection then asks
as on a phone; a simulator with no passcode set says no, and the demo stays.
A script can't open a menu, so
`SIMCTL_CHILD_WW_DEBUG_CHIP_MENU=1` shows the chip's choices as a sheet over
the Dashboard instead.
The keyboard and pointer (#307) can't be driven from a script either, so
`SIMCTL_CHILD_WW_DEBUG_SHORTCUTS=1` shows the shortcut table (the Kit's
`KeyShortcuts`: keys, title and where each works) as a sheet over the open
page, and `SIMCTL_CHILD_WW_DEBUG_CONTEXT=1` shows the long-press menu of
Forecast's first line (the Kit's `RowAction`s, as that person may use them)
as a sheet over Forecast. Both are Debug only.
`SIMCTL_CHILD_WW_DEBUG_CHANGE_TRANSFER=1` opens a transfer line (Forecast's
first one this month) in the line editor with Change transfer already open
over it (#324): the Move money form filled in. The demo has no transfers, so
use it with `SIMCTL_CHILD_WW_DEBUG_LOCAL=sample`, whose household has one.
Debug only.
Drag and drop (#308) can't be driven from a script either:
`SIMCTL_CHILD_WW_DEBUG_DROP=csv` shows Forecast's (and the Dashboard's) drop
highlight as if a bank's CSV were held over the page, and
`SIMCTL_CHILD_WW_DEBUG_DROP=day` shows a Calendar day highlighted as if a line
were held over it (the day after today, or the 15th when today isn't in the
month shown; a `YYYY-MM-DD` in the month instead picks that day). Each shows
only where the drop would be taken: an account that can change, and not
while the lock has the demo in front. Debug only.
On this Mac the simulators are shared with other projects' sessions, so run
simulator commands through mkplus's `Scripts/with-simulator.sh`.

**Against a real server.** `LiveServerTests.swift` holds tests that run only
when given a demo server and a throwaway token: `WW_LIVE_TOKEN` (signing out
ends it) and `WW_LIVE_EDIT_TOKEN` (marks a line paid and undoes it, adds and
deletes a one-off, on the demo's data). `WW_LIVE_EMAIL` and
`WW_LIVE_PASSWORD` sign in with an email and password and end the token
straight away.

## How it signs in

1. **Sign in** on the Connect screen opens the server's `/app-sign-in` page
   in the system's sign-in sheet (`ASWebAuthenticationSession`). The sheet
   shares Safari's sign-ins, so Cloudflare Access, Google, passkeys and
   password managers all work there (Google refuses to sign in inside an
   app's own web view).
2. You sign in there if you aren't already, and tap **Allow**. The server
   makes a one-time code and sends the sheet to `walletweather://signed-in`.
3. The app swaps the code for its own API token at
   `POST /api/app-sign-in/token`, proving with a PKCE verifier that it's the
   app that opened the sheet. The token lasts 90 days and shows in the web
   app's **Settings → API tokens**, where revoking it signs the phone out.
4. **Cloudflare:** the sheet keeps its Cloudflare sign-in to itself. Cloudflare
   passes your Access token to the server on every request
   (`Cf-Access-Jwt-Assertion`), so the server hands it back to the app in the
   same `walletweather://` answer. The app then sends it as
   `cf-access-token`. When it runs out (24 hours unless the Access application
   says otherwise), the app says so and **Sign in to Cloudflare** opens
   `/app-sign-in/cloudflare` in the sheet, which hands back a fresh one.
   Cloudflare's "binding cookie" setting, if switched on for the
   application, would stop this. A Cloudflare service token under
   **Advanced** stands in for it.

The other ways in, under **Other ways to sign in** (#100):

- **Email and password**, swapped for a token at `POST /api/auth/token`
  (full access, 90 days, named after the phone), under the server's sign-in
  rate limit. Behind Cloudflare the sheet signs in to Cloudflare first. An
  account that signs in only with Google has no password, so it gets the
  wrong-password message, which points to Sign in.
- **Scan a QR code:** the web app's Settings → API tokens draws a new
  token's `walletweather://connect?server=…&token=…` link as a QR code
  (Show QR code, off an iPhone; the encoder is written for the page). The
  app scans it with VisionKit's `DataScannerViewController`, asking for the
  camera only then, and the phone's Camera app can open it too.
- The **Open in WalletWeather** button beside a new token in the web app's
  Settings (on an iPhone), which opens the same link.
- **Pasting a token.**

A link, scanned or opened, always asks "Connect to …?" before it's used.
It adds its server beside the ones already signed in to and switches to it,
or, for a server already in the list, signs in to it again with the new
token (#300).

**Several servers at once** (#300). Settings → the card at the top opens
**Connections**: every saved connection (each server signed in to, and the
household on this iPhone), with a tick on the one in front. Tapping another
switches to it without signing out of anything: its keep choice, its kept
numbers and its web theme come with it, and every page loads again.
**Add a server** opens this same sign-in screen, with all its ways, as a
sheet. Signing in to a server and person already in the list renews that
connection's token instead of adding a second; another person on the same
server is a connection of its own. Which person a connection is comes from
`/api/me` (its email, kept with the connection); a sign-in whose person
can't be told is added rather than replacing someone else's
(`SavedConnection.signInTarget`). A connection whose token has ended still
switches, and its pages offer **Sign in again**, which opens the sign-in
sheet for that server only. Each connection has its own page (the ⓘ
button on its row): its name, which you can change, its address and who's signed
in, Cloudflare, Open the web app, and **Sign out of** it; Keep on this
iPhone shows there for the one in front.

Debug builds take launch settings for checking the Connect screen in the
simulator: `WW_DEBUG_ADDRESS` (opens on Connect with that address),
`WW_DEBUG_OTHER_WAYS`, `WW_DEBUG_SCAN`, and `WW_DEBUG_EMAIL` with
`WW_DEBUG_PASSWORD` (signs in with them).

Plain `http://` is accepted only for home-network addresses (`localhost`, a
name with no dots, `.local`, private IP addresses), with a warning, because
that's what iOS lets an app reach over plain HTTP.

## What's kept on the phone

On this iPhone, the household itself: see "On this iPhone" below. With a
server, only its sign-in: a sign-in per server (the server's address, the
token, the Cloudflare sign-in, what the phone keeps for it and its web
theme), each in its own Keychain item (`ConnectionStore`, account
`connection.<id>`), on this device only (never in iCloud, never moved by a
backup), readable only while the phone is unlocked. The preferences
(`UserDefaults`) hold only which one is in front (`connections.active`).
Several sign-ins are kept at once, one item each, and signing out of one
deletes only its item, its keep choice and its kept numbers; the others stay
signed in. The app's own settings (the look,
whether the lock is on and whether it was offered, the tab bar and Getting
started) are in its preferences, and stay after signing out. Themes the
person makes (Settings → Appearance → My themes, #297) are kept in the iPhone's
iCloud key-value store (`NSUbiquitousKeyValueStore`, key `themes.custom`), so
they reach their other iPhones signed in to the same Apple ID, and mirrored in
the preferences under the same key, so with iCloud off they stay on this
iPhone: each theme's name and six colours only, never a number or anything
else. A theme changed on another iPhone arrives through the store's
external-change notification; the look saved while one is chosen is
`custom:<uuid>`, and if that theme is deleted the app falls back to Match this
iPhone. Balances and
transactions are kept only when the person chooses Last-known numbers
(phase 8, `KeptResponses`), in a folder per server
(`Application Support/Kept/<id>/`); signing out of that server deletes them.
The single sign-in kept before #299 (account `connection`) is carried over
once, and removed only after its copy reads back.

Signing out of a server (its page, from Connections) ends that server's
token first (`DELETE /api/tokens/current`, sent with that connection's own
sign-in, so it works for one that isn't in front: a token may revoke itself,
and nothing else). If the server can't be reached, the app still signs out
and says the token stays listed in Settings → API tokens until it's revoked
there. If it was in front, the one used most recently comes in front; with
none left, the app goes back to the sign-in screen.

## Changing a line

The app changes lines the way the web app's editor does: a projected date of
a repeating bill or paycheck is saved as a new transaction
(`POST /api/accounts/{id}/transactions`), a line that's already saved is sent
whole again (`PATCH /api/transactions/{id}`, which replaces every field, so
the app sends the line's name, dates, amounts, category and notes each time
and leaves its tags alone), a saved line is deleted with `DELETE`, and a
projected date is skipped with `POST /api/recurring/{id}/skip`. Undoing
"paid" keeps the line as a transaction at its planned amount, so its notes
and category stay. Marking a line paid from the Forecast's list (a swipe, or
To confirm) shows an Undo bar along the bottom for about five seconds (fifteen
with VoiceOver on): Undo finds the line again after the reload (a projected
date is a transaction by then) and saves it with Paid off, the same
`PATCH` the editor's switch sends (#315). A success haptic goes with marking a
line paid and with a save that goes through in the line editor, the bill
editor, Add transaction and Move money; the phone's System Haptics setting
turns them off. Transfers are read-only in the app for now; new ones are made with Move
money (`POST /api/transfers`). Bills are changed the same way as lines: a
`PATCH /api/recurring/{id}` sends the whole item again, and ending one sets
its end date.

For a line you added (saved, not a transfer, not from a repeating bill), the
editor's first section makes the name, planned date and planned amount fields,
and the same `PATCH` sends the edited ones (a name is required, up to 500
characters; the planned amount is typed without a sign and the line keeps its
own). Changing the plan never marks the line paid, and a paid line keeps the
actual amount and date set for it. A projected date, a bill's saved date and a
transfer show those three as text, and a date that comes from a bill is changed
in its bill. The phone's own household answers the same way.

Editing shows only on an account you own or may edit (`level` in
`/api/accounts`), and nowhere under a read-only token (`token_access` in
`/api/me`).

## The responses it reads

The server's responses have no declared shape, so each endpoint the app reads
has a shape test on the server (`apps/server/tests/test_app_shapes.py`) and a
recorded sample that `swift test` decodes. When a shape test changes,
re-record the samples from a demo server (`DEMO_MODE=true`) and run
`swift test`.

The app checks `GET /api/version` when it connects. A server older than
`AppInfo.minimumServerVersion` (in `WalletWeatherKit`) gets a plain message.

## Bank sync

Settings → Bank sync (a row in Your household, its state in a few words
beside it, `BankStatus.settingsValue`) opens a page with the **Bank sync**
card (`BankSyncCard` in `MoreView.swift`, with
the words in `BankSync.swift` in `WalletWeatherKit`, which tests check state
by state). It reads `GET /api/bank/status` (server 1.70.0; an older server
gets "Bank sync shows here from server 1.70.0"). From server 1.86.0 the
status lists each bank connection (`connections`: SimpleFIN, Teller or Plaid,
each with its bank's name, its own last sync and its own 20-a-day limit), and
the card shows one block for each with its own **Sync now**, which posts
`POST /api/bank/sync` with that `connection_id`; a server from 1.70.0 to
1.85.0 sends no list, and the card shows its one connection as before with a
Sync now that syncs it. A read-only token can't sync, so the button is
hidden for one. Over a connection's limit its block shows the wait message
(naming its provider) and disables its button. A bill's editor shows the two match settings
(`match_days`, `match_percent`, server 1.73.0) only when the server sends
them, and a save from a server without them leaves them out of the request,
which leaves them as they are. In the demo the status is a sample made from
the time now, with two connections (one through SimpleFIN, one through
Teller), and Sync now says the demo saves nothing.

**Connect a bank** (iOS 0.30.0, server 1.89.0, phase 5 of
`Plans/bank-providers.md`, #258; decided 2026-11-21) opens the server's
`/app-connect-bank` page in the sign-in sheet (`AppModel.connectBank`, the
same `SignInSheet` as signing in). The page runs Teller or Plaid under the
browser's sign-in and two-factor code, as Settings does in the web app, and
answers `walletweather://bank-connected?connection=<id>` (or
`?state=exited|expired|cancelled|failed|off`), which `AppLink` reads; the
card then reads the status again and names the new connection
(`BankConnect.outcome`). The app's token never connects a bank. The button
shows when bank sync is on, the server is 1.89.0 or later and the token can
write; in the demo it says the demo saves nothing. Matching the new
connection's accounts stays in the web app.

**Unmatched lines with a server** (duo-more phase 3, #306): a connection's block
and each shared account with lines waiting show a row, "3 lines to match",
that opens `UnmatchedListView(accounts:)` for those accounts, the same list the
household on this iPhone has, now on the server's
`GET /api/accounts/{id}/bank-unmatched` and `.../{line}/candidates`
(`BankUnmatched`, `BankCandidates`; `test_app_shapes.py` pins the fields the app
reads). The status carries a count only for shared accounts, so the person's own
accounts are asked one by one (`APIClient.unmatchedCounts(for:)`). **Match…**
shows each bill or planned line the bank's line could pay (**Pay this**,
**Always match "name"**, which teaches the bill the name, and **Leave as its own
line**); `POST .../match` and `.../leave` are what the web app's pop-in sends.
On a regular width (the open Duo) the list is one pane and the tapped line's
choices the other (`FoldLayout`); closed, the list is pushed and the choices are a sheet. In the
wide Settings window the detail pane is forced to a compact width, so there the
row presents the list as a full-screen cover over the whole window with its
regular width back and a Done button (`unmatchedList` in `PhoneBankViews.swift`;
the pane says it is wide through the `settingsIsWide` environment value), as
Compare does from Forecast; Done returns to Bank sync. `WW_DEBUG_UNMATCHED=1`
lands in the same place on each. A
read-only token sees the list and the choices with Pay this and Leave off, and a
line saying so. Settings' Bank sync row says "3 to match" while lines wait
(after a bank that needs reconnecting or failed, which still come first;
`BankStatus.settingsValue(unmatched:)`). The demo has two sample lines on the
Credit Card (`Demo/unmatched.json`), one close to the Phone bill; Match and
Leave say the demo saves nothing. There is no setting for it: matching from the
phone is what the web app already offers, so no one is left with a behaviour
they'd want the other way.

**On an iPhone without a server** (iOS 0.32.0, phase 8 of
`Plans/standalone.md`, #239; design calls settled 2026-11-22) the card is
`PhoneBankCard` (`PhoneBankViews.swift`) instead, and SimpleFIN runs on the
phone (`PhoneBank.swift` in `WalletWeatherKit`), never Teller or Plaid, whose
keys must stay on a server. **Connect SimpleFIN** takes the pasted setup
token and claims it as `simplefin.py` does (https on SimpleFIN's own hosts
only, no redirects); the access address goes in the Keychain only
(`KeychainBankSecret`: this device only, never iCloud Keychain, readable
after the first unlock for background time), never in the household's
store, its backups or iCloud sync. What the phone knows about the
connection (the bank accounts, which phone account each fills and from
when, the calls of the last 24 hours, the last sync) is this phone's, in
its settings. Each bank account has a picker (Leave out, or one of the
phone's accounts) and a "Bring in from" date (up to 90 days back, today to
start), as in the web app. A sync by itself comes at most every 23½ hours
(the server's `BANK_SYNC_EVERY`, counted from the last sync of any kind,
failed or not), when the app becomes active or in a background app refresh
(`BGAppRefreshTask` `net.iptater.walletweather.banksync`, only while the
household can be read); **Sync now** is under the server's 20-calls-a-day
limit with its wait message. Lines land in the household as the server's
`_bank_sync_locked` lands them (`LocalBank.swift`): skipped by their bank
ref (the server's SHA-256, so the same line never lands twice here, on
another device or after a move to a server), a line typed by hand or from a
CSV with the same date, amount and name claimed, a bill paid through the
core's `bankMatch`, the rest as their own lines with the short name.
**Unmatched (N)** opens `UnmatchedListView`, answered by `LocalServer` in the
server's shapes (`/api/accounts/{id}/bank-unmatched`, `.../candidates`,
`.../match`, `.../leave`) through the core, with **Match…** (cards like the
web app's pop-in, Pay this, and "Always match …") and
**Leave**. Forecast rows on the list wear the Unmatched pill. Debug builds:
`WW_DEBUG_BANK=1` swaps in a stand-in SimpleFIN (`DebugBridge`), and
`connected` or `unmatched` (with `WW_DEBUG_LOCAL=sample`) connects, matches
and syncs it, `unmatched` opening the list.

**Shared accounts and who may connect** (iOS 0.31.0, server 1.92.0 for
`shared` and 1.92.1 for `providers_allowed`, phase 4 of
`Plans/sync-access.md`, #267): the card also lists the accounts the person
owns or edits that sync from someone else's connection
(`BankStatus.shared`, `SharedBankAccount`), each saying "Synced from <name>'s
<provider> connection", how its own last sync went, a paused, needs-reconnect
or can't-sign-in note naming that person, how many lines wait to be matched
(a row that opens them, see below), and a **Sync now** of its own (`POST /api/bank/sync` with
`account_id`, `APIClient.syncBankNow(account:)`) that is off while the account
is paused, needs a reconnect, its person can't sign in or the day's limit is
reached. Someone with only shared accounts skips "No bank connected". **Connect
a bank** shows only when `providers_allowed` has Teller or Plaid (a server
before 1.92.1 doesn't say, so it's offered as before), and an unticked person's
"No bank connected" says an admin chooses who may. The demo has one shared
account, a Credit Card synced from Sam's Plaid connection.

## On this iPhone

The first screen asks how to use the app (phase 4 of
[`Plans/standalone.md`](../../Plans/standalone.md), #235; decided
2026-11-18): **On this iPhone** or **Your own server**, each with what it
gives and what it costs (`Standalone.swift`), and **Try the demo**, smaller,
under both. Your own server goes on to the sign-in screen.

On this iPhone keeps the household in a SwiftData store
(`LocalStore.swift`) in `Application Support/Household`, with complete file
protection (unreadable while the phone is locked). It's the only copy, so
unlike kept numbers it's in the phone's iCloud or computer backup, and phase 6
adds a sealed backup to iCloud Drive (below). **Sync with iCloud** (phase 7,
#238; on unless turned off in Settings → iCloud & backup, a choice kept per
device) mirrors the store to the private CloudKit database of the container
`iCloud.net.iptater.walletweather`, also in the background through silent
pushes (`UIBackgroundModes: remote-notification`, `aps-environment`), so
while it's on the files are protected until the first unlock instead.
CloudKit keeps a record's later edit and a deleted record deleted;
`LocalSync.swift`'s `reconcile` joins what two devices made apart (the
default categories by name, settings, a skipped date) the same way on every
device, when the store opens and when another device's changes land
(`NSPersistentStoreRemoteChange`). With sync on, **Delete everywhere** (#249)
empties the household through the store (`emptyHousehold`), waits for
CloudKit's export, then deletes the files (`LocalStore.eraseEverywhere`).
`SyncTests` checks it.

**The CloudKit schema** (#270): TestFlight and App Store builds sync to the
container's Production environment, whose record types (`CD_LocalAccount`
and the other nine, one per model) must be deployed from Development in
CloudKit Console first, and again after any model change. Debug builds write
the whole Development schema, every field included, with
`SIMCTL_CHILD_WW_DEBUG_CLOUDKIT_SCHEMA=1` (Apple's `initializeCloudKitSchema()`
on a scratch store, `CloudKitSchema` in `LocalStore.swift`); the device must be
signed in to iCloud, and the result is written to `debug-cloudkit-schema.txt`
in the app's Documents. Using the app alone isn't enough: SwiftData's sync
makes a field only once a record has a value for it.

The household's `Connection` points at
`https://this-iphone.walletweather.invalid`, and `APIClient` answers it on
the phone (`LocalServer.swift`): the pages make the same requests as with a
server and get the server's shapes back.

- **Worked out by the core:** Dashboard, its charts, Forecast, the Calendar,
  balances, Bills & income and its totals, and both searches, from the rows
  as the server hands them over (`apps/server/app/forecast.py`).
- **Saved as the server saves:** new accounts (`POST /api/accounts`, from an
  empty Dashboard or Settings → Add an account), lines, bills, skipped dates
  and Move money, with the server's checks. A new household starts with the
  server's default categories. Rows get random ids below 2^52, not counts,
  so two devices can't pick the same one once phase 7 syncs them.
- **Needs a server** (open question 2): Net worth, Budgets and Reports
  stay where they are, greyed and marked, and open a note on what a
  server adds; their requests answer 404. Bank sync works on the phone since
  iOS 0.32.0 (below). A transfer can be deleted (both
  its lines) but not changed, skipped dates are brought back from a bill's
  editor (#246), and tags are kept (on lines, bills and in rules, moved and
  synced; `LocalTags.swift`, #250) and since phone-tags phase 2 (#251)
  made and chosen on the phone (`TagViews.swift`), as with a server, and auto-tag
  rules applied on the phone as the server applies them (#252).
- **No network:** the local session's only handlers are the household's and
  one that refuses everything else (`RefuseProtocol`); `LocalTests` drives
  every page and checks nothing was refused.
- **Settings** (#294): Your household has Add an account, iCloud & backup
  and Move to a server; About has the Important notice (asked once, as
  after signing up); the connection card at the top opens Back to the
  first screen (the numbers stay; On this iPhone opens them again) and
  Delete everything on this iPhone.

**Moving to or from a server** (phase 5, #236): Settings → Move to a
server. **Export for a server** writes the server's own
sealed backup (`BackupFile.swift`: scrypt, then AES-256-GCM, the header bound
as Python's `json.dumps` writes it; `Scrypt.swift`, since CryptoKit has none),
in backup version 5 (`LocalBackup.swift`, as `export_user`), and saves it
with the system's Save to Files; the server's Settings → Restore takes it.
**Import a server backup** opens one the server made and replaces the
household after asking (decided 2026-11-18), as the server's "replace"
import does, with its checks. Tags, tag rules and bank and email-alert links
aren't kept on the phone. The backup passphrase is chosen the first time and
kept in iCloud Keychain (`BackupPassphrase` in `Keychain.swift`, synced);
Settings → iCloud & backup → Backup passphrase shows it after Face ID, Touch ID or the
passcode. The files that make the trip are committed in
`Tests/WalletWeatherKitTests/Samples/moves/` and checked from both sides:
`BackupTests` and `ScryptTests` here, `apps/server/tests/test_backup_moves.py`
on the server (phone → server → phone gives the same Forecasts).

**Backup to iCloud Drive** (phase 6, #237): `CloudBackup.swift` writes that
same sealed file to the app's iCloud Drive container
(`iCloud.net.iptater.walletweather`, `Documents/Backups/walletweather-YYYY-MM-DD.json`,
shown in Files through `NSUbiquitousContainers`; the entitlements come from
`project.yml`). It runs from `CloudBackupModel` when the app opens or goes to
the background: on, something changed since the last backup (the household
stamps every change in its store, `LocalServer.markChanged`), and none made
today yet; the newest 14 are kept. It turns on with the first account
(`AppModel.accountAdded`) and Settings → iCloud & backup switches it.
**Restore** (`BackupViews.swift`) is on the first screen and on that page:
it lists the folder, asks iCloud for a file not yet downloaded, opens it with
the iCloud Keychain passphrase (or one typed) and replaces the household.
`CloudBackupTests` runs it all in a temporary folder; the real iCloud round
trip is checked on a phone.

**Import a CSV** (phase 9, #243): `CSVImportViews.swift` picks a file in
Files and shows one sheet (account, signs, a summary, the columns folded
away, the rows); `CSVImport.swift` holds its models and the two calls,
`/api/accounts/{id}/import/preview` and `/commit`. A server answers them
itself; on the phone `LocalServer` hands the file, the account's lines and
bills and the categories to the core's `csvPreview` and `csvCommit` (the
server's same code) and makes the bills and lines the plan lists. It's in
Settings and Forecast's + menu, with or without a server; the columns and
signs are kept per account in the app's settings. Debug builds open it on a
file in the app's Documents folder with `WW_DEBUG_CSV=<file>`. `WW_DEBUG_TAGS=1` opens Settings → Tags (#252). `LocalTests`
covers the import and its checks, `CoreTests` the core's answers.

Debug builds open it from the command line with `WW_DEBUG_LOCAL=1`, or
`empty` / `sample` for a fresh household with the notice agreed to (and a
few bills and lines with `sample`), and the first screen with
`WW_DEBUG_WELCOME=1`. `WW_DEBUG_IMPORT=<file>` (with `WW_DEBUG_PASSPHRASE`)
imports a backup from the app's Documents folder onto a fresh household,
through the same code as Import a server backup, and `WW_DEBUG_EXPORT=<file>`
then writes the household back there as Export for a server does; what
happened goes to `debug-import.txt` beside them. Copy files in and out with
`xcrun simctl get_app_container <device> net.iptater.walletweather data`.

## Try the demo

**Try the demo** on the first screen (#92) opens the app on sample numbers,
with no server, for Apple's reviewer and anyone curious. The demo's
`Connection` points at `https://demo.walletweather.invalid` (an address that
can't exist), and `APIClient` answers it from
`WalletWeatherKit/Sources/WalletWeatherKit/Demo/` instead of the network
(`Demo.swift`). Decided 2026-11-16:

- **Read-only.** Editors open as usual; saving says "The demo doesn't save
  changes" (`APIError.demoReadOnly`). Running a saved report still works.
- **A bar on every page,** "Demo · sample numbers", with **Leave** back to
  the Connect screen; Settings' connection card opens the same as **Leave
  the demo** (#294).
- **No set-up:** no Important notice, no "What should this iPhone keep?", no
  lock offer, no Getting started card, nothing kept and nothing in the
  Keychain.
- **Dates follow the calendar.** The samples were recorded in November 2026;
  every date moves by whole months to the month asked for, so each month
  looks like the recorded one. Forecast and the Calendar on the accounts the
  samples weren't recorded on are built from the Calendar's lines.
- **Sample tags and a rule** (#293): Holiday, Work and Kids, two auto-tag
  rules, and a few lines and one bill carrying them (`Demo/tags.json`), so
  Settings → Tags, the editors' Tags row, the chips on lines and opening a
  tag from Search all work. Creating, changing or deleting a tag or rule is
  refused like any other save.

`DemoTests` sends every page's request to the demo and decodes the answers
with the real models, including one test that asks for every page Settings
links to, so a page added there without a demo answer fails the tests. When the test samples are re-recorded, copy the same
files into `Demo/` and run `swift test`.

## Before listing in the App Store

- The store asks for a privacy policy URL. It is
  <https://mkolakowski.github.io/WalletWeather/privacy> (the source is
  `docs/privacy.md`). Read it against what the app really does before
  submitting, and update it first if the app stores or sends anything it
  doesn't mention.
- The privacy manifest, `WalletWeather/PrivacyInfo.xcprivacy`, says the same
  as the policy: no tracking, no data collected.
- The App Privacy questions (the "nutrition label"): the honest answer today
  is that no data is collected, because the app talks only to the user's own
  server. Last-known numbers (phase 8) stay on the phone and are never sent
  anywhere, so they don't change that answer, but the policy says what's
  kept. Adding analytics, crash reporting or ads would change that answer
  and the policy.
- The name "WalletWeather" should be cleared first (`Plans/legal-risk.md`,
  phase 5).
