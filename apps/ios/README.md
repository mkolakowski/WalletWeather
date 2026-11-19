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
now under Settings, and a bill's bank match settings in its editor; the sync
log, the Unmatched list and connecting a bank stay in the web app.

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
`SIMCTL_CHILD_WW_DEBUG_DAY=2026-11-11` a day.
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

Debug builds take launch settings for checking the Connect screen in the
simulator: `WW_DEBUG_ADDRESS` (opens on Connect with that address),
`WW_DEBUG_OTHER_WAYS`, `WW_DEBUG_SCAN`, and `WW_DEBUG_EMAIL` with
`WW_DEBUG_PASSWORD` (signs in with them).

Plain `http://` is accepted only for home-network addresses (`localhost`, a
name with no dots, `.local`, private IP addresses), with a warning, because
that's what iOS lets an app reach over plain HTTP.

## What's kept on the phone

On this iPhone, the household itself: see "On this iPhone" below. With a
server, only the sign-in: the server's address, the token and the Cloudflare sign-in,
in the Keychain, on this device only (never in iCloud, never moved by a
backup). Signing out deletes them. The app's own settings (the look, whether
the lock is on and whether it was offered, the tab bar, Getting started and
what the phone keeps) are in its preferences (`UserDefaults`), and stay after
signing out. Balances and transactions are kept only when the person chooses
Last-known numbers (phase 8, `KeptResponses`); signing out deletes them.

Signing out ends the token on the server first (`DELETE /api/tokens/current`:
a token may revoke itself, and nothing else). If the server can't be reached,
the app still signs out and says the token stays listed in Settings → API
tokens until it's revoked there.

## Changing a line

The app changes lines the way the web app's editor does: a projected date of
a repeating bill or paycheck is saved as a new transaction
(`POST /api/accounts/{id}/transactions`), a line that's already saved is sent
whole again (`PATCH /api/transactions/{id}`, which replaces every field, so
the app sends the line's name, dates, amounts, category and notes each time
and leaves its tags alone), a saved line is deleted with `DELETE`, and a
projected date is skipped with `POST /api/recurring/{id}/skip`. Undoing
"paid" keeps the line as a transaction at its planned amount, so its notes
and category stay. Transfers are read-only in the app for now; new ones are made with Move
money (`POST /api/transfers`). Bills are changed the same way as lines: a
`PATCH /api/recurring/{id}` sends the whole item again, and ending one sets
its end date.

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

Settings has a **Bank sync** card (`BankSyncCard` in `MoreView.swift`, with
the words in `BankSync.swift` in `WalletWeatherKit`, which tests check state
by state). It reads `GET /api/bank/status` (server 1.70.0; an older server
gets "Bank sync shows here from server 1.70.0") and **Sync now** posts to
`POST /api/bank/sync`, which a read-only token can't, so the button is hidden
for one. Over the 20-a-day limit the card shows the web app's wait message
and disables the button. A bill's editor shows the two match settings
(`match_days`, `match_percent`, server 1.73.0) only when the server sends
them, and a save from a server without them leaves them out of the request,
which leaves them as they are. In the demo the status is a sample made from
the time now, and Sync now says the demo saves nothing.

## On this iPhone

The first screen asks how to use the app (phase 4 of
[`Plans/standalone.md`](../../Plans/standalone.md), #235; decided
2026-11-18): **On this iPhone** or **Your own server**, each with what it
gives and what it costs (`Standalone.swift`), and **Try the demo**, smaller,
under both. Your own server goes on to the sign-in screen.

On this iPhone keeps the household in a SwiftData store
(`LocalStore.swift`) in `Application Support/Household`, with complete file
protection (unreadable while the phone is locked). It's the only copy, so
unlike kept numbers it's in the phone's iCloud or computer backup; CloudKit
is off until phase 7. Its `Connection` points at
`https://this-iphone.walletweather.invalid`, and `APIClient` answers it on
the phone (`LocalServer.swift`): the pages make the same requests as with a
server and get the server's shapes back.

- **Worked out by the core:** Dashboard, its charts, Forecast, the Calendar,
  balances, Bills & income and its totals, and both searches, from the rows
  as the server hands them over (`apps/server/app/forecast.py`).
- **Saved as the server saves:** new accounts (`POST /api/accounts`, from an
  empty Dashboard or Settings → On this iPhone), lines, bills, skipped dates
  and Move money, with the server's checks. A new household starts with the
  server's default categories. Rows get random ids below 2^52, not counts,
  so two devices can't pick the same one once phase 7 syncs them.
- **Needs a server** (open question 2): Net worth, Budgets, Reports and bank
  sync stay where they are, greyed and marked, and open a note on what a
  server adds; their requests answer 404. Transfers can't be changed or
  deleted yet, and skipped dates can't be restored (both are in the web app
  only), and tags can't be made.
- **No network:** the local session's only handlers are the household's and
  one that refuses everything else (`RefuseProtocol`); `LocalTests` drives
  every page and checks nothing was refused.
- **Settings → On this iPhone:** Add an account, the Important notice (asked
  once, as after signing up), Back to the first screen (the numbers stay;
  On this iPhone opens them again) and Delete everything on this iPhone.

**Moving to or from a server** (phase 5, #236): Settings → On this iPhone →
Move to or from a server. **Export for a server** writes the server's own
sealed backup (`BackupFile.swift`: scrypt, then AES-256-GCM, the header bound
as Python's `json.dumps` writes it; `Scrypt.swift`, since CryptoKit has none),
in backup version 5 (`LocalBackup.swift`, as `export_user`), and saves it
with the system's Save to Files; the server's Settings → Restore takes it.
**Import a server backup** opens one the server made and replaces the
household after asking (decided 2026-11-18), as the server's "replace"
import does, with its checks. Tags, tag rules and bank and email-alert links
aren't kept on the phone. The backup passphrase is chosen the first time and
kept in iCloud Keychain (`BackupPassphrase` in `Keychain.swift`, synced);
Settings → Backup passphrase shows it after Face ID, Touch ID or the
passcode. The files that make the trip are committed in
`Tests/WalletWeatherKitTests/Samples/moves/` and checked from both sides:
`BackupTests` and `ScryptTests` here, `apps/server/tests/test_backup_moves.py`
on the server (phone → server → phone gives the same Forecasts).

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
  the Connect screen.
- **No set-up:** no Important notice, no "What should this phone keep?", no
  lock offer, no Getting started card, nothing kept and nothing in the
  Keychain.
- **Dates follow the calendar.** The samples were recorded in November 2026;
  every date moves by whole months to the month asked for, so each month
  looks like the recorded one. Forecast and the Calendar on the accounts the
  samples weren't recorded on are built from the Calendar's lines.

`DemoTests` sends every page's request to the demo and decodes the answers
with the real models. When the test samples are re-recorded, copy the same
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
