# Standalone: the iPhone app without a server

Tracking issue: #240

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. The answer key and first core numbers | Server (tests), Core | #232 | Done 2026-11-18, no version (tests only) |
| 2. The server runs on the core | Server, Core | #233 | Not started |
| 3. The core on the iPhone | iOS, Core | #234 | Not started |
| 4. Use without a server | iOS | #235 | Not started |
| 5. Move between a server and the phone | iOS, Server | #236 | Not started |
| 6. Backup to iCloud Drive | iOS | #237 | Not started |
| 7. Live iCloud sync between devices | iOS | #238 | Not started |
| 8. Bank sync on the phone | iOS, Core | #239 | Not started |

Phase 1 done 2026-11-18, with no version (nothing in the image changed). `packages/core/walletweather-core.js` (core 0.1.0) works out the forecast, the Actual bal as of a day, a bill's next dates and the Calendar. `apps/server/tests/answer_key.py` builds three households (basics, edges, two accounts) and writes 51 cases from today's server code to `packages/core/answer-key/`. `tests/test_core_answer_key.py` runs the core over every case in quickjs-ng and checks that the key still matches the server. The engine was chosen by you (open question 1). Findings that changed the plan: the server keeps amounts unrounded and adds them as floats, with Python 3.12's compensated `sum()` in two places, so the core adds the same doubles in the same order instead of using whole cents. Its answers then match the server's **exactly**, to the last bit. Verified by the 51 cases plus date, rounding and summation checks against Python, a deliberate bug (month ends clamped to the 28th) failing 19 cases, and the full suite (797 passed). Dashboard numbers weren't in phase 1's key; they move to phase 2.

The first version worth telling people about is phase 6: the app on its own, with an iCloud Drive backup and a way to move to a server and back. Phases 7 and 8 follow it.

Planned 2026-11-18 (1:13 AM ET), from your question about running WalletWeather without a server.

Sessions: may span — eight phases across the server, a new shared core and the iOS app, each shipping its own version, with your try on TestFlight between the app phases.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 2. The server runs on the core | Server, Core | Opus | Sonnet: runs the full suite and reports; Haiku: pulls failures out of long test output | Swaps the engine under the numbers every page shows; a mismatch moves real balances. |
| 3. The core on the iPhone | iOS, Core | Opus | Sonnet: `swift test` over the answer key | JavaScriptCore in WalletWeatherKit, and the demo moving from recorded months to computed ones. |
| 4. Use without a server | iOS | Opus | Sonnet: tests for the local store and the local answers | A privacy decision (financial data stored on the phone) and a new way into the app. |
| 5. Move between a server and the phone | iOS, Server | Opus | Sonnet: server tests that import a file the phone made | scrypt written in Swift has to match `backup.py` byte for byte; a wrong key loses a backup. |
| 6. Backup to iCloud Drive | iOS | Sonnet | none | Writes the phase 5 file on a timer into the app's iCloud folder. Switch to Opus if the passphrase handling changes. |
| 7. Live iCloud sync between devices | iOS | Opus | Sonnet: conflict tests | CloudKit, its rules for what the store may hold, and what happens when two devices edit at once. |
| 8. Bank sync on the phone | iOS, Core | Opus | Sonnet: matching tests over the answer key | Moves bank matching into the core and keeps a SimpleFIN token on the phone. |

## Open questions

1. ~~**The server's JavaScript engine.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **quickjs-ng** (MIT, 2.5 MB wheel, 8 MB installed). Set aside: mini-racer (V8, ISC, 74 MB installed), dukpy (ES5 only), a Node service in Compose.
2. ~~**What standalone shows for what it can't do.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **shown, marked "Needs a server".** Sharing, bank-alert emails, email alerts, Net worth, Budgets and Reports stay where they are, greyed, and open a short note on what a server adds, with a link to the setup.
3. **How transactions get in before phase 8.** Blocks nothing. Assumed: typing them, and importing a server backup (phase 5). CSV import on the phone is a later idea.
4. ~~**The backup passphrase.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **chosen once when backup is turned on and kept in iCloud Keychain**, so a new phone opens the backups by itself, with a plain warning that a lost passphrase can't be recovered.
5. ~~**How often iCloud Drive backups are written, and how many are kept.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **at most once a day, only on days something changed, keeping the last 14.**
6. ~~**When two devices edit the same thing.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **the later edit wins, per record** (CloudKit's own rule), with no note, and a deleted record stays deleted.
7. **Standalone and the App Store listing.** Blocks nothing. The app becomes useful without a server, which changes what `ios-app` phase 6 (#92) says to Apple's reviewer and in the listing.

## The plan

**Goal:** someone who just wants WalletWeather on their iPhone can use it with no server: the data lives on the phone, is backed up to iCloud and can sync between their devices, and can be moved to a server (or back) when they want one.

**Decided 2026-11-18** (asked in the session; [decision page](../docs/dev/decisions/standalone.md)):

- **The iPhone app gets a standalone mode.** No server-in-a-box: the app holds the data itself.
- **The money logic is written once, in JavaScript**, and run by all three: the server (an embedded engine), the iPhone (JavaScriptCore, part of iOS), and later the web app as-is. Compared against a shared Python core embedded in the app (tens of MB, no help for the web) and a Rust core (exact decimals, but a new toolchain on the Mac, in Docker and in Xcode, and a WebAssembly build for the web).
- **Today's server is the answer key.** Before the server switches to the core, the server produces test cases (data in, the API's JSON out) and the core must match them all. Both CI (pytest) and `swift test` run them.
- **iCloud: both.** A sealed backup file in iCloud Drive, in the server's own backup format (`backup.py`: scrypt + AES-256-GCM) so the server's Import takes it, and live sync between the person's devices.
- **Scope:** the first usable version is standalone + backup + moving (phases 4–6). Bank sync on the phone and live sync are in this plan, after it. The web app working in the browser, and Net worth, Budgets and Reports in standalone, wait (roadmap items 32 and 33).
- **Checked by** the answer key in CI and `swift test`, plus your try of each app phase on TestFlight.

**How the core is shaped:**

- `packages/core/`: plain JavaScript, no build step, no dependencies. It's copied into the server image (the build already runs from the repo root) and into the iOS app's bundle.
- Pure functions: the rows go in (accounts, transactions, bills and their skips, tags), and the same JSON the API sends today comes out, so the server and the phone answer in one shape and the app's decoding doesn't change.
- Money is a JavaScript number, the same double as the server's Python float, added up in the same order (with Python's compensated `sum()` where the server uses it), so the answers match exactly. The server keeps amounts unrounded, so whole cents (the first assumption) would have changed numbers people see (found in phase 1). Dates are plain "YYYY-MM-DD", never JavaScript `Date`, so no time zone moves a day.
- One classic script defining `WalletWeatherCore`, not ES modules, because JavaScriptCore and the server's engine evaluate scripts. `run(name, json)` is the one entry point.

**Out of scope:** the web app running without a server; sharing between people in standalone; bank-alert emails and email alerts in standalone; Net worth, Budgets and Reports in standalone; offline editing for people who use a server (roadmap item 27, which needs sync with the server rather than iCloud).

### Phase 1: The answer key and first core numbers

- **Server (tests only):** a generator that runs today's forecast, Calendar, bills' upcoming dates and Dashboard numbers over a set of fixture households (monthly, weekly and every-two-weeks bills, the only rhythms the server has; skips, paid lines, transfers, month ends, leap days, accounts that start mid-month) and writes each case as JSON: the rows in, the response out. The cases are committed.
- **Core:** `packages/core/` with the forecast (`_occurrences`, `upcoming_dates`, `build_forecast`'s maths and the running balance) and the Calendar month.
- **The engine:** the candidates in open question 1 compared, and the chosen one added to the test requirements only (not the image yet), passing `test_licences.py` and listed in `THIRD_PARTY_NOTICES.md`.
- A pytest that runs the core over every case through the engine.
- **No version bump:** nothing in the image changes.
- **Done when:** the core matches every forecast and Calendar case; the engine's findings are on the issue for open question 1; the suite passes in CI.

### Phase 2: The server runs on the core

- **Core:** the rest of what Dashboard, Forecast, Bills & income, Calendar, transfers and search work out.
- **Server:** the engine moves into the image; `forecast.py` and the route handlers load rows and call the core instead of working the numbers out themselves. The Python versions are deleted once the answer key passes, so there's one copy; the committed cases stay as the key, and new features add their own.
- A speed check: the forecast route before and after, on the demo household.
- `APP_VERSION` (minor), the changelog ("works the numbers out a new way; nothing should look different").
- **You:** look over your own Dashboard and Forecast after the release.
- **Done when:** the full suite and the answer key pass; the forecast route's time before and after, and the image size change, are on the issue (more than 20% slower comes back to you).

### Phase 3: The core on the iPhone

- **iOS:** WalletWeatherKit runs `packages/core/` in JavaScriptCore (a system framework, so nothing to add to `THIRD_PARTY_NOTICES.md`). `swift test` runs the same answer key.
- **The demo** works its numbers out through the core from sample rows, instead of moving recorded months, so it follows the calendar for real.
- `MARKETING_VERSION`, `AppInfo.version`, the changelog.
- **You:** try the demo from TestFlight: Forecast and Calendar for this month and next.
- **Done when:** `swift test` passes the answer key; the demo's pages look as before.

### Phase 4: Use without a server

- **iOS:** the Connect screen offers "Use without a server" next to connecting and the demo. The data lives in a store on the phone (SwiftData, with complete file protection, as kept numbers are today). A local connection answers the app's API calls from the store through the core, as the demo does, so the screens don't change. It covers Dashboard, Forecast, Bills & income, Calendar, moving money, search, and adding, editing and deleting.
- What standalone can't do (sharing, bank-alert emails, email alerts, Net worth, Budgets, Reports) stays in place, greyed and marked "Needs a server", and opens a short note on what a server adds with a link to the setup (open question 2). No sign-in, but the app lock still works.
- `docs/privacy.md` and the iOS README updated.
- **You:** set up a standalone household from scratch on TestFlight and use it for a few days.
- **Done when:** a household can be set up and edited with no server; the store's tests pass; nothing is sent over the network in standalone (checked by a test with a session that fails every request).

### Phase 5: Move between a server and the phone

- **iOS:** "Export for a server" writes a sealed backup in `backup.py`'s format (version, scrypt, AES-256-GCM; scrypt written in Swift, since CryptoKit has none). "Import a server backup" fills a standalone phone from a file the server made.
- **Server:** a test that imports a file the phone made, committed as a fixture, so a change on either side that breaks the move fails CI.
- The passphrase is chosen once, when backup or export is first used, and kept in iCloud Keychain, with a plain warning that it can't be recovered (open question 4).
- **You:** export from the phone, import it on your instance, and the other way round.
- **Done when:** a round trip (phone → server → phone) gives the same Forecast; the key-derivation tests match Python's for the same passphrase and salt.

### Phase 6: Backup to iCloud Drive

- **iOS:** with backup on, the phase 5 file is written to the app's iCloud Drive folder, at most once a day and only on days something changed, keeping the last 14 (open question 5). Restore from a backup on a new phone, and the backups can be seen in the Files app.
- The release that ships this is the first standalone version worth announcing (README, changelog).
- **You:** turn backup on, delete the app, put it back and restore.
- **Done when:** a restore on a fresh install gives the same Forecast; old backups are pruned to the number kept.

### Phase 7: Live iCloud sync between devices

- **iOS:** the store syncs through the person's private CloudKit database, so an iPhone and an iPad (or two phones) stay in step. When two devices edit the same record, the later edit wins and a deleted record stays deleted (open question 6). The store is reshaped where CloudKit needs it (no unique constraints, every field optional or defaulted), with a migration.
- **You:** create the CloudKit container in the Apple developer website (the one setup step only you can do), then edit on two devices.
- **Done when:** an edit on one device shows on the other; the conflict tests pass; turning sync off leaves the data on the phone.

### Phase 8: Bank sync on the phone

- **Core:** bank matching (which bill a bank line pays, taught names, the Unmatched list) moves into the core, and the server switches to it as in phase 2, checked by its own answer key.
- **iOS:** a standalone phone can be given a SimpleFIN token (kept in the Keychain) and pulls when the app opens and when iOS gives it background time. The Unmatched list and matching by hand come to the app.
- **You:** connect your SimpleFIN account to a standalone phone.
- **Done when:** the matching answer key passes on both sides; lines arrive and match on the phone.
