# Standalone: the iPhone app without a server

Tracking issue: #240

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. The answer key and first core numbers | Server (tests), Core | #232 | Done 2026-11-18, no version (tests only) |
| 2. The server runs on the core | Server, Core | #233 | Built in 1.82.0, 2026-11-18; waits for the release and your look |
| 3. The core on the iPhone | iOS, Core | #234 | Built in iOS 0.18.0, 2026-11-18; waits for TestFlight and your try |
| 4. Use without a server | iOS | #235 | Not started |
| 5. Move between a server and the phone | iOS, Server | #236 | Not started |
| 6. Backup to iCloud Drive | iOS | #237 | Not started |
| 9. CSV import from Files (runs after 6, before 7) | iOS, Core | #243 | Not started |
| 7. Live iCloud sync between devices | iOS | #238 | Not started |
| 8. Bank sync on the phone | iOS, Core | #239 | Not started |

Phase 3 built 2026-11-18 in iOS 0.18.0. `Core.swift` runs a copy of the core (`WalletWeatherKit/Sources/WalletWeatherKit/Core/`, refreshed by `Scripts/copy-core.sh`) in JavaScriptCore, one context behind a lock. `CoreTests` runs every answer-key case inside JavaScript, so numbers are compared to the last bit, and fails when the copy differs from `packages/core`. "Try the demo" now works out its Dashboard, charts, Forecast, Calendar and account balances with the core from `Demo/household.json`: the demo household's rows, recorded by `Scripts/record-household.py` from the server's demo seed for 2026-11-15. The household is moved by days to today, so its purchases stay in the past. Six recorded answers left the app. Verified by all 63 answer-key cases exact in JavaScriptCore (and in Node's V8 by hand); by the household reproducing the recorded demo samples on its day (Dashboard, both charts, Forecast, both Calendars, balances); by `swift test` (138 passed); and by an app build. Not tried on a phone yet.

Phase 2 built 2026-11-18 in 1.82.0 (core 0.2.0), not released yet. The server's forecast, Actual bal, a bill's next and in-window dates, Calendar, Dashboard and Dashboard charts now come from the core: `app/forecast.py` reads the rows, `app/jscore.py` runs the core in quickjs-ng (one thread behind a lock, memory and time limits, clean-up every 100 calls), and the Python copies are gone. Budgets, Net worth, Reports, Search and bank matching use it through `build_forecast` and `_occurrences`. The Dashboard and charts were added to the answer key first, written by the old Python (63 cases), and the core matched them exactly before the switch. Speed (an account with 1,458 lines): a month's forecast took 24 ms against 23.5 ms before, 90 days 28 ms against 26 ms. The first version was 3–4× slower: it decrypted every line, the engine cleaned up after every call, and strings compared one character at a time; all three were fixed without changing an answer. Found and fixed: the server read lines and categories in no set order, which can reorder lines on the same date in a busy database; it now reads each kind in id order. Image: +8 MB (quickjs-ng). Verified by the answer key, the full suite (810 passed) and an image build (the core at `/app/packages/core/`, run inside the image). Left for phase 4, where the phone first needs them: Bills & income's list and totals and Search (transfers are saves, not worked-out numbers).

Phase 1 done 2026-11-18, with no version (nothing in the image changed). `packages/core/walletweather-core.js` (core 0.1.0) works out the forecast, the Actual bal as of a day, a bill's next dates and the Calendar. `apps/server/tests/answer_key.py` builds three households (basics, edges, two accounts) and writes 51 cases from today's server code to `packages/core/answer-key/`. `tests/test_core_answer_key.py` runs the core over every case in quickjs-ng and checks that the key still matches the server. The engine was chosen by you (open question 1). Findings that changed the plan: the server keeps amounts unrounded and adds them as floats, with Python 3.12's compensated `sum()` in two places, so the core adds the same doubles in the same order instead of using whole cents. Its answers then match the server's **exactly**, to the last bit. Verified by the 51 cases plus date, rounding and summation checks against Python, a deliberate bug (month ends clamped to the 28th) failing 19 cases, and the full suite (797 passed). Dashboard numbers weren't in phase 1's key; they move to phase 2.

The first version worth telling people about is phase 6: the app on its own, with an iCloud Drive backup and a way to move to a server and back. Phases 7 and 8 follow it.

Planned 2026-11-18 (1:13 AM ET), from your question about running WalletWeather without a server.

Sessions: may span — eight phases across the server, a new shared core and the iOS app, each shipping its own version, with your try on TestFlight between the app phases.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 4. Use without a server | iOS | Opus | Sonnet: tests for the local store and the local answers | A privacy decision (financial data stored on the phone) and a new way into the app. |
| 5. Move between a server and the phone | iOS, Server | Opus | Sonnet: server tests that import a file the phone made | scrypt written in Swift has to match `backup.py` byte for byte; a wrong key loses a backup. |
| 6. Backup to iCloud Drive | iOS | Sonnet | none | Writes the phase 5 file on a timer into the app's iCloud folder. Switch to Opus if the passphrase handling changes. |
| 9. CSV import from Files | iOS, Core | Opus | Sonnet: the importer's answer key cases and tests | The web app's importer (column mapping, dates, amounts, de-duplication, tag rules) moves into the core, and the server switches to it as in phase 2; a wrong de-duplication drops or doubles lines. |
| 7. Live iCloud sync between devices | iOS | Opus | Sonnet: conflict tests | CloudKit, its rules for what the store may hold, and what happens when two devices edit at once. |
| 8. Bank sync on the phone | iOS, Core | Opus | Sonnet: matching tests over the answer key | Moves bank matching into the core and keeps a SimpleFIN token on the phone. |

## Open questions

1. ~~**The server's JavaScript engine.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **quickjs-ng** (MIT, 2.5 MB wheel, 8 MB installed). Set aside: mini-racer (V8, ISC, 74 MB installed), dukpy (ES5 only), a Node service in Compose.
2. ~~**What standalone shows for what it can't do.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **shown, marked "Needs a server".** Sharing, bank-alert emails, email alerts, Net worth, Budgets and Reports stay where they are, greyed, and open a short note on what a server adds, with a link to the setup.
3. ~~**How transactions get in before phase 8.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **CSV import from the Files app**, as its own phase (9, run after phase 6 and before 7; numbered 9 so phases 7 and 8 keep their issues).
4. ~~**The backup passphrase.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **chosen once when backup is turned on and kept in iCloud Keychain**, so a new phone opens the backups by itself, with a plain warning that a lost passphrase can't be recovered.
5. ~~**How often iCloud Drive backups are written, and how many are kept.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **at most once a day, only on days something changed, keeping the last 14.**
6. ~~**When two devices edit the same thing.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **the later edit wins, per record** (CloudKit's own rule), with no note, and a deleted record stays deleted.
7. ~~**Standalone and the App Store listing.**~~ Decided 2026-11-18 ([decision](../docs/dev/decisions/standalone.md)): **the app asks at onboarding**, showing the pros and cons of both: on this iPhone, or connected to your own server. The listing presents the two the same way (its wording is for `ios-app` phase 6, #92).

## The plan

**Goal:** someone who just wants WalletWeather on their iPhone can use it with no server: the data lives on the phone, is backed up to iCloud and can sync between their devices, and can be moved to a server (or back) when they want one.

**Decided 2026-11-18** (asked in the session; [decision page](../docs/dev/decisions/standalone.md)):

- **The iPhone app gets a standalone mode.** No server-in-a-box: the app holds the data itself.
- **The money logic is written once, in JavaScript**, and run by all three: the server (an embedded engine), the iPhone (JavaScriptCore, part of iOS), and later the web app as-is. Compared against a shared Python core embedded in the app (tens of MB, no help for the web) and a Rust core (exact decimals, but a new toolchain on the Mac, in Docker and in Xcode, and a WebAssembly build for the web).
- **Today's server is the answer key.** Before the server switches to the core, the server produces test cases (data in, the API's JSON out) and the core must match them all. Both CI (pytest) and `swift test` run them.
- **iCloud: both.** A sealed backup file in iCloud Drive, in the server's own backup format (`backup.py`: scrypt + AES-256-GCM) so the server's Import takes it, and live sync between the person's devices.
- **Scope:** the first usable version is standalone + backup + moving (phases 4–6), then CSV import (phase 9). Bank sync on the phone and live sync are in this plan, after it. The web app working in the browser, and Net worth, Budgets and Reports in standalone, wait (roadmap items 32 and 33).
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

- **Core first:** Bills & income's list and totals and Search move into the core, with answer-key cases, and the server switches to them as in phase 2 (left from phase 2).
- **iOS:** the first screen asks how to use the app (open question 7), with the pros and cons of each:
  - **On this iPhone:** no server to run, the data stays on your devices and backs up to iCloud; but no web app, no sharing, no bank-alert emails or email alerts, and bank sync only while the app runs.
  - **Your own server:** the web app and the phone, sharing, bank sync on a schedule and alerts; but you run and update a server.
  - "Try the demo" stays, smaller, under both.
- **iOS:** The data lives in a store on the phone (SwiftData, with complete file protection, as kept numbers are today). A local connection answers the app's API calls from the store through the core, as the demo does, so the screens don't change. It covers Dashboard, Forecast, Bills & income, Calendar, moving money, search, and adding, editing and deleting.
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

### Phase 9: CSV import from Files

Runs after phase 6 and before phase 7 (decided 2026-11-18, open question 3).

- **Core:** the web app's CSV importer (`_parse_csv_rows`, the column mapping, dates and amounts, de-duplication against lines already there, the auto-tag rules) moves into the core, with its own answer-key cases, and the server's preview and import endpoints switch to it as in phase 2.
- **iOS:** a standalone phone can pick a bank's CSV export in the Files app, map its columns (remembered per account, as on the web), preview what lands and what's a duplicate, and import.
- **You:** import a CSV export from your bank into a standalone phone.
- **Done when:** the importer's answer key passes on both sides; the same file imported twice adds nothing the second time.

### Phase 7: Live iCloud sync between devices

- **iOS:** the store syncs through the person's private CloudKit database, so an iPhone and an iPad (or two phones) stay in step. When two devices edit the same record, the later edit wins and a deleted record stays deleted (open question 6). The store is reshaped where CloudKit needs it (no unique constraints, every field optional or defaulted), with a migration.
- **You:** create the CloudKit container in the Apple developer website (the one setup step only you can do), then edit on two devices.
- **Done when:** an edit on one device shows on the other; the conflict tests pass; turning sync off leaves the data on the phone.

### Phase 8: Bank sync on the phone

- **Core:** bank matching (which bill a bank line pays, taught names, the Unmatched list) moves into the core, and the server switches to it as in phase 2, checked by its own answer key.
- **iOS:** a standalone phone can be given a SimpleFIN token (kept in the Keychain) and pulls when the app opens and when iOS gives it background time. The Unmatched list and matching by hand come to the app.
- **You:** connect your SimpleFIN account to a standalone phone.
- **Done when:** the matching answer key passes on both sides; lines arrive and match on the phone.
