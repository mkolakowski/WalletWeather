# WalletWeather core

The money logic shared by the server, the iPhone app and (later) the web app,
written once in JavaScript ([`Plans/standalone.md`](../../Plans/standalone.md),
tracking issue #240).

| Path | What it is |
| --- | --- |
| `walletweather-core.js` | The core: one classic script, no dependencies and no build step, defining `WalletWeatherCore`. Hosts call `WalletWeatherCore.run(name, json)` with a JSON string in and a JSON string out. |
| `answer-key/` | Cases written by today's server code: the rows the core is given and the JSON the server answered. The core must match every one exactly. |

What it works out so far: `forecast` (an account's Forecast page),
`actualBalanceAsOf` (the Actual bal column on a day), `upcomingDates` (a
bill's next dates) and `calendar` (the Calendar page). Each function's input
is described above it in the source.

**Checking it.** The server's tests run the core in quickjs-ng over every
case, and check that the cases still match what the server answers:

```sh
docker compose -f docker-compose.test.yml run --rm tests tests/test_core_answer_key.py
docker compose -f docker-compose.test.yml down
```

**When the server's answers change on purpose**, rewrite the key and commit
it with the change (`apps/server/tests/answer_key.py` says how).
