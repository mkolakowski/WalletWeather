# WalletWeather core

The money logic shared by the server, the iPhone app and (later) the web app,
written once in JavaScript ([`Plans/standalone.md`](../../Plans/standalone.md),
tracking issue #240).

| Path | What it is |
| --- | --- |
| `walletweather-core.js` | The core: one classic script, no dependencies and no build step, defining `WalletWeatherCore`. Hosts call `WalletWeatherCore.run(name, json)` with a JSON string in and a JSON string out. |
| `answer-key/` | Cases written by today's server code: the rows the core is given and the JSON the server answered. The core must match every one exactly. |

What it works out: `forecast` (an account's Forecast page),
`actualBalanceAsOf` (the Actual bal column on a day), `upcomingDates` (a
bill's next dates), `occurrences` (a bill's dates in a window), `calendar`
(the Calendar page), `dashboard` (the Dashboard's cards) and
`dashboardCharts` (its charts), and since core 0.3.0 `recurringList` (Bills &
income and its totals), `searchTransactions` (transaction search) and `search`
(the search box's grouped results), and since core 0.4.0 `csvPreview` and
`csvCommit` (CSV import's preview, and the bills and lines an import makes;
Python's csv reader, strptime and float() are copied, and
`apps/server/tests/test_csv_import.py` checks them against Python itself),
and since core 0.5.0 bank matching: `bankMatch` (which bill each new bank
line pays, taught names and each bill's days and percent included),
`bankUnmatched` (the Unmatched list), `bankCandidates` (the match pop-in's
candidates and choices), `bankNear` (the Unmatched lines that could pay a
planned line) and `bankCatchUp` (the lines a newly taught name pays; the
server keeps these amounts as exact decimals, so they go in as decimal
strings). Since core 0.5.1 a line's source counts a line joined to its
bank row (#210) as the bank's, and bankMatch takes an optional `name` (an
email alert's merchant). The server's bank sync, email alerts and Unmatched
routes run the matching from the core since 1.94.1, and so does the iPhone
app without a server (#239).
Each function's input is described above
it in the source.

**Who runs it.** The server, since 1.82.0 (Bills & income and search since
1.83.0): `apps/server/app/forecast.py`
reads the rows and `apps/server/app/jscore.py` runs the core in quickjs-ng.
The iPhone app from phase 3 of the plan, in JavaScriptCore.

**Checking it.** The server's tests run the core in quickjs-ng over every
case, and check that the cases still match what the server answers:

```sh
docker compose -f docker-compose.test.yml run --rm tests tests/test_core_answer_key.py
docker compose -f docker-compose.test.yml down
```

**When the server's answers change on purpose**, rewrite the key and commit
it with the change (`apps/server/tests/answer_key.py` says how).
