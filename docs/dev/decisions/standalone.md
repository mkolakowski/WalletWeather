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
