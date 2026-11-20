# Standalone: the iPhone app without a server

Decisions made while planning [`Plans/standalone.md`](../../../Plans/standalone.md) (tracking issue #240).

## 2026-11-18: standalone lives in the iPhone app

**Decided:** 2026-11-18, by Matthew. **Status:** accepted, planned.

**The question:** could someone use WalletWeather without running a server, back it up to iCloud, and move to a server one day?

**The decision:** the iPhone app gets a standalone mode that keeps the data on the phone. A lighter server image or a Mac app with the server hidden inside were set aside (still a server), and so was a browser-only web app for now (browser storage can be wiped; it waits as roadmap item 32).

## 2026-11-18: the money logic is one JavaScript core

**Decided:** 2026-11-18, by Matthew. **Status:** accepted, planned (phases 1–3).

**The question:** standalone needs the server's money logic (repeating bills, forecast balances, Calendar, Dashboard) on the phone. How do the two stay the same?

**The options weighed:**

- **A Swift copy checked by shared test cases:** fully native, but every feature written twice.
- **A shared Python core embedded in the app** (Python 3.13+ runs on iOS): reuses the server's code, but adds tens of MB to the app and does nothing for the web.
- **A Rust core** (PyO3 for the server, a C interface for Swift; UniFFI is MPL-2.0 and refused by `test_licences.py`): exact decimals, but a new toolchain on the Mac, in Docker and in Xcode, and a WebAssembly build that ends the web app's "no build step".
- **A JavaScript core:** JavaScriptCore is part of iOS (no size, no package), it runs as-is in the web app, and the project already writes JavaScript. The server needs an engine embedded in Python.

**The decision:** a JavaScript core in `packages/core/` (pure functions, rows in, the API's JSON out, whole cents and plain dates), run by the server, the iPhone and later the web. Before the server switches to it, today's server produces an answer key of test cases that the core must match, run by pytest and `swift test`. Which engine the server embeds is open question 1, settled in phase 1.

## 2026-11-18: iCloud both ways, and the scope

**Decided:** 2026-11-18, by Matthew. **Status:** accepted, planned (phases 5–7).

**The decision:**

- **iCloud: both.** A sealed backup file in iCloud Drive in the server's own backup format (`backup.py`: scrypt + AES-256-GCM), so the server's Import takes it, and live sync between the person's devices through their private CloudKit database.
- **The first usable version** is standalone + backup + moving between a server and the phone (phases 4–6). Live sync (phase 7) and bank sync on the phone (phase 8) follow in the same plan.
- **Waiting:** the web app working in the browser (roadmap item 32), and Net worth, Budgets and Reports in standalone (roadmap item 33).
- **Checked by** the answer key in CI and `swift test`, plus Matthew's try of each app phase on TestFlight.

## 2026-11-18: the server embeds quickjs-ng

**Decided:** 2026-11-18, by Matthew. **Status:** accepted; in the tests from phase 1 (#232), in the image from phase 2. Answers open question 1.

**The question:** which JavaScript engine the server embeds to run the shared core.

**The options weighed** (checked on PyPI on 2026-11-18):

- **quickjs-ng 0.18.0.2:** MIT (the wrapper and the quickjs-ng engine), a 2.5 MB wheel and 8 MB installed, abi3 wheels for Linux x86_64 and aarch64 and macOS arm64, released the day before. Its Python wrapper has one maintainer, and its metadata names no licence, so it is on `test_licences.py`'s reviewed list.
- **mini-racer 0.14.1** (V8): ISC, actively maintained, but a 22 MB wheel and 74 MB installed.
- **dukpy 0.6.0:** MIT, but it runs ES5 only, which would force old syntax on the core for the iPhone and the web.
- **A Node service in Compose:** no Python package, but a second container to keep patched and a network call for every calculation.
- The original `quickjs` binding was last released in 2023 and is archived.

**The decision:** quickjs-ng. If its wrapper is abandoned, the core moves to another engine unchanged, since it is plain JavaScript.

## 2026-11-18: the core adds floats as the server does, not whole cents

**Decided:** 2026-11-18, while building phase 1 (#232). **Status:** accepted. Replaces the plan's first assumption ("money as whole cents").

**What was found:** the server accepts amounts as unrounded floats (`Money` in `main.py`), stores them as the Decimal of that float, and adds balances as Python floats, with Python 3.12's compensated `sum()` in two places (the Δ Bal planned balance and `actual_balance_as_of`). Whole cents would change the numbers for any amount with more than two decimals, and plain addition put one balance a half cent the other way after rounding.

**The decision:** the core adds the same doubles in the same order and copies `sum()`'s compensation and `round()`'s half-to-even rounding. Its answers then match the server's exactly, and the answer key compares with no tolerance.

## 2026-11-18: what standalone shows, the passphrase, backups and conflicts

**Decided:** 2026-11-18, by Matthew (`/resolve-open-questions`). **Status:** accepted, planned. Answers open questions 2, 4, 5 and 6.

- **What standalone can't do is shown, marked "Needs a server"** (phase 4, #235). Sharing, bank-alert emails, email alerts, Net worth, Budgets and Reports stay where they are, greyed, and open a short note on what a server adds, with a link to the setup. Chosen over hiding them behind one Settings line (cheaper) so people see what a server would add.
- **The backup passphrase is kept in iCloud Keychain** (phase 5, #236). It's chosen once, when backup or export is first used, and synced so a new phone opens the backups by itself, with a plain warning that a lost passphrase can't be recovered. Typing it every time was set aside because automatic backups couldn't run.
- **iCloud Drive backups: at most once a day, only on days something changed, keeping the last 14** (phase 6, #237).
- **Sync conflicts: the later edit wins, per record** (phase 7, #238), as CloudKit does by itself, with no note; a deleted record stays deleted. A rare edit made on two devices before they sync can be lost.

## 2026-11-18: CSV import on the phone, and asking at onboarding

**Decided:** 2026-11-18, by Matthew (`/resolve-open-questions`). **Status:** accepted, planned. Answers open questions 3 and 7.

- **CSV import from the Files app** gets standalone transactions in before bank sync on the phone (phase 8). It's a new phase, numbered 9 so phases 7 and 8 keep their issues, run after phase 6 and before 7. The web app's importer moves into the core so both import the same way.
- **The app asks at onboarding** whether to use it on this iPhone or with your own server, showing the pros and cons of both (phase 4). Asked as "how should the App Store listing present standalone?", Matthew answered with this instead of picking one to lead with. So the listing presents the two the same way, and its wording is left to `ios-app` phase 6 (#92).

## 2026-11-18: leaving standalone, and adding accounts on the phone

**Decided:** 2026-11-18, by Matthew, asked while building phase 4 (#235). **Status:** accepted, built in iOS 0.19.0.

- **Settings → On this iPhone offers Back to the first screen and Delete everything on this iPhone.** Back keeps the household on the phone, and choosing On this iPhone again opens it; Delete asks first, then erases the store. Chosen over a single Delete (nothing to come back to) and over no way out until phase 5.
- **Accounts are added from an empty Dashboard ("Add your first account") and from Settings → On this iPhone → Add an account,** with the web app's fields: a name, a starting balance (a leading minus for money owed) and the date it starts. Chosen over a set-up step before the Dashboard and over a "New account" item in the + menu.

**Set in building, not asked:** the household is included in the phone's own iCloud or computer backup (it's the only copy until phase 6), unlike kept numbers, which stay out; rows get random ids below 2^52 rather than counts, so phase 7's sync can't have two devices pick the same id; the Important notice is asked once, as after signing up on the web; the server's default categories are made with a new household; Try the demo moved from the sign-in screen to the first screen.

## 2026-11-18: importing onto a phone, and transfers in backups

**Decided:** 2026-11-18, by Matthew, asked while building phase 5 (#236). **Status:** accepted, built in 1.84.0 and iOS 0.20.0.

- **Importing a server backup onto a phone that already has a household replaces it, after asking.** The confirmation names the accounts that will replace the phone's, as the server's "replace" import does. An empty phone just imports. Chosen over importing only into an empty phone, and over offering replace or add alongside.
- **Backups record transfers (backup version 5).** Each transfer is listed with its two accounts' places in the file, its date, amount, name and notes, and its two lines point at it, so a restore or a move keeps them linked. Before, the server's own backups turned a transfer into two plain lines. It's an optional addition, so older backups still import; a version 5 file needs a server on 1.84.0 or later. Chosen over keeping plain lines.

**Set in building, not asked:** the passphrase is chosen the first time Export for a server is used, typed twice, and shown in Settings → Backup passphrase after Face ID, Touch ID or the passcode (so it can be typed on the server); the import tries the passphrase in iCloud Keychain first and asks only when it doesn't open the file; tags, tag rules and bank and email-alert links are left behind on the way onto the phone, which has none of them; the files that make the trip are committed in the iOS app's test samples and checked from both sides.

## 2026-11-20: when the iCloud Drive backup starts, and where restore is

**Decided:** 2026-11-20, by Matthew, asked while building phase 6 (#237). **Status:** accepted, built in iOS 0.21.0.

- **The backup is on from the first account.** Adding the first account on the phone turns it on: at once when a backup passphrase is already chosen, otherwise a sheet asks for one ("Not now" leaves it off, and Settings → On this iPhone → Backup turns it on later). Chosen over off until turned on, and over off with a reminder, so a household that only lives on the phone is never left without a copy because nobody found the switch.
- **Restore is on the first screen and in Settings.** "Restore from an iCloud backup" on the first screen is the new-phone path; "Restore from a backup…" in the Backup card does the same on a phone that already has a household, after asking. Both list the backups newest first.

**Set in building, not asked:** a restore turns the backup back on, and saves a typed passphrase to iCloud Keychain so the next backup uses it; the household stamps every change in its own store, so "only when something changed" survives the app closing; the backup is checked when the app opens and when it goes to the background, since iOS gives an app no timer.

## 2026-11-20: where CSV import lives on the iPhone

**Decided:** 2026-11-20, by Matthew, asked while building phase 9 (#243). **Status:** accepted, built in iOS 0.23.0.

- **In Settings and in Forecast's + menu.** Settings asks which account (the first one you can change, to start); Forecast's menu imports into the account on screen. Chosen over Settings only and Forecast only.
- **With a server too.** A phone signed in to a server gets the same screen, for accounts it may change; the server does the import with its same code. Chosen over keeping it to the phone with no server.
- **The columns are remembered per account.** The columns, the signs and "first row is column names" are kept on the phone for each account and used again when the next file has the same headings; otherwise they're worked out from the names. Chosen over working them out every time, as the web app does.

**Set in building, not asked:** the sheet shows the summary first and folds the columns away, opening them by itself when the date or amount column wasn't found; a byte order mark at the start of a file is dropped, as a browser drops it for the web app; a file that isn't UTF-8 is read as Latin-1.

## 2026-11-20: syncing with iCloud

**Decided:** 2026-11-20, by Matthew, asked while building phase 7 (#238). **Status:** accepted, built in iOS 0.24.0.

- **On by default.** The household on this iPhone syncs through the person's private CloudKit database when the phone is signed in to iCloud; "Sync with iCloud" in Settings → On this iPhone turns it off, per device, keeping every number on that phone. Chosen over off until turned on.
- **In the background too.** CloudKit's silent pushes bring another device's changes while the app is closed. That needs the household's file readable after the phone's first unlock, so while sync is on its protection is "complete until first user authentication" instead of "complete" (a privacy decision; the privacy policy and Settings say so). Chosen over syncing only while the app is open, which kept complete protection.
- **A second device's numbers merge.** A device that had its own household adds it to the shared one (CloudKit has one private database per Apple ID); the default categories each device started with are joined by name. Chosen over asking first whether to merge or replace.

**Set in building, not asked:** the copy kept when devices made the same thing apart is the one with the lowest id, so every device keeps the same one; a category kept takes a colour from its twin if it had none; joined settings take the latest change and backup stamps, and "agreed" or "on" if any copy says so; **Delete everything on this iPhone** deletes the phone's copy only, and now says a synced copy stays in iCloud (whether it should also clear iCloud is open).
