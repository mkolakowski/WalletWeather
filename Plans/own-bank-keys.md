# Own bank keys: each person's own Teller and Plaid keys

Tracking issue: #279

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Your own keys, server and web | Server, Web | #276 | Built, not released (server 1.95.0, web 1.106.0, schema 38) |
| 2. Admin sees who has their own keys | Server, Web | #277 | Built, not released (server 1.96.0, web 1.107.0) |
| 3. Your own keys from the iPhone | iOS, Server, Web | #278 | Built, not released (server 1.97.0, web 1.108.0, iOS 0.33.0) |

Planned 2026-11-23 from the question "what would be needed to move the place to store variables for bank sync inside the database, changing the admin to turn on and allow the connections then the users themselves add the connection information to their account". Seven calls were made while planning ([decision](../docs/dev/decisions/bank-sync.md#2026-11-23-each-persons-own-teller-and-plaid-keys)).

**Phase 1 built 2026-11-23** (server 1.95.0, web 1.106.0, schema 38; not released yet). What was built: the `bank_keys` table and `bank_connections.keys_enc`; `teller.py` and `plaid.py` take `Keys` instead of reading `os.environ`, with syncs, balances and disconnecting on the connection's copy and starting, finishing and Teller's setup on the person's own keys (`bank_keys.py`); Teller's certificate and key written to a fresh 0700 folder under `/tmp`, files 0600, removed as soon as `httpx` has loaded them; the one-time copy of `.env`'s keys at startup (`bank_keys.copy_env_keys`, once per provider); `PUT /api/bank/keys/teller`, `PUT /api/bank/keys/plaid` and `POST /api/bank/keys/remove` (browser session, fresh two-factor code, audit `bank_keys_saved` / `bank_keys_removed`); `keys` in `/api/bank`; per-person `providers[].available` and `providers_allowed`; the Settings key cards; Admin → Bank sync's note; sealed backups carrying `bank_keys` and each connection's `keys`; the docs. Set in building, not asked: saving keys needs bank sync switched on and a tick for that provider (removing doesn't, as disconnecting doesn't); Teller's check is a `GET /accounts` with the certificate and no token (401 means the certificate is known), after loading the pair locally; Plaid's check is `/institutions/get`; a same-id replacement also updates the copies of the person's own connections that used the old keys, so a renewed certificate reaches them; a connection with no copy (made before, `.env` unreadable at the upgrade) falls back on its holder's own keys and gets a copy when passed on; the copy is marked done per provider only when it ran or there were no connections, so an unreadable `.env` is tried again at the next start; Admin → Users offers every provider now; a restore in replace mode replaces your keys with the backup's, a merge only fills in missing ones; `tempfile` is on the security guard's forbidden list, so the folder is made with `os.mkdir` and a random name. Tests: an autouse guard in `conftest.py` gives Teller and Plaid a refusing transport, so no test reaches the network (a daily sync over connections left by earlier tests otherwise hung on DNS). Verified: `tests/test_bank_own_keys.py` (new) and the bank suites against the stand-in providers; the full suite: 1229 passed, 4 failed, the four date-dependent bank tests of #272 that fail on main too; Settings → Bank sync and Admin → Bank sync checked headless at 1100 and 390 px with the API stubbed, no page errors, nothing wider than the screen.

**Phase 2 built 2026-11-23** (server 1.96.0, web 1.107.0; not released yet). `GET /api/admin/users` gains `bank_keys`: `{"teller": {"environment": …} | null, "plaid": … | null}` per person, from one query over `bank_keys` (environment only: no id, secret, certificate or key). Admin → Users' Bank sync column shows "own keys, <environment>" after Teller's and Plaid's ticks, and "ticked, no keys yet" when ticked without keys; an admin (always allowed) shows only the "own keys" note, as Teller: / Plaid: lines under "Always". Tests: `tests/test_admin_bank_keys.py` (new: the fields and environment, null for none, no key id or secret or PEM in the body, one `bank_keys` query for many people, non-admin refused). Verified: that file with `test_bank_own_keys.py`, the security guards and the admin-users suites passed; Admin → Users checked headless at 1100 and 390 px with the API stubbed.

**Phase 3 built 2026-11-23** (server 1.97.0, web 1.108.0, iOS 0.33.0; not released yet). As decided (open question 1), a server page in the app's sign-in sheet: `/app-bank-keys` (`app-bank-keys.html` / `.js`, the same tight policy as `/app-connect-bank`, on the security guard's `PUBLIC` list, and a place Google sign-in may return to) signs in, shows a card each for Teller and Plaid (the id, environment, when checked and which connections use them; add, Replace, Remove, with one two-factor code field at the top cleared after each try) and saves through phase 1's `PUT /api/bank/keys/teller|plaid` and `POST /api/bank/keys/remove`; Teller's zip, the two files or their pasted text, as the web card. "Back to the app" sends `walletweather://bank-keys?state=changed|closed` (`off` when bank sync is off or the person isn't ticked and has no keys). `GET /api/bank/status` (token-readable) gains `providers_ticked` and `own_keys` (environment only). The app: `BankStatus.providersTicked` / `ownKeys`, `BankKeys` (rows, offered from server 1.97.0 for a writing token, the answer's words), `AppLink.bankKeys`, `AppModel.editBankKeys`, and a "Your Teller and Plaid keys" section under Connect a bank in More → Bank sync; the demo has Teller keys and Plaid ticked without keys. Set in building, not asked: the card's button reads "Add your bank keys" until one is saved, then "Your bank keys"; someone ticked for Teller or Plaid without keys is told "Add yours below, then connect a bank" (`addKeysFirst`) instead of the Admin → Users line; `app-connect-bank.js`'s "add your keys first" now points to the app's card too. Tests: `tests/test_app_bank_keys.py` (new: the page and its policy, `_safe_next`, `providers_ticked` and `own_keys` with the app's token and no id or secret, unticked and admin, removal, the app's token refused on saving and removing) and `test_not_connected_status` in `test_bank_sync_daily.py` updated for the two fields; `swift test` (`BankSyncTests`, `DemoTests`). Verified: the new file with the security guards and the bank suites, 231 passed; `swift test` 210 passed; the card seen in the simulator (demo, iPhone Duo); the page checked headless at 390 px with the API stubbed (no page errors, nothing wider than the screen, the code asked for before saving).

Sessions: may span — each phase is its own release, and phase 3 waits on open question 1.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Your own keys, server and web | Server, Web | Opus | Haiku: find every `os.environ` read and every call into `teller.py` and `plaid.py`; Sonnet: API tests against stand-in Teller and Plaid, and the headless check of the Settings cards | A schema change holding secrets, every provider call rewired to per-person keys, a one-time copy on upgrade, sealed backups, and a Teller client certificate that has to reach `httpx` from the database on a read-only file system. |
| 2. Admin sees who has their own keys | Server, Web | Sonnet | Sonnet: tests | A mark per service in an existing Admin list, from a table phase 1 makes. |
| 3. Your own keys from the iPhone | iOS, Server | Opus | Sonnet: `swift test` and screenshots through `with-simulator.sh` | Secrets entered on the phone (a file picked from Files for Teller), on a path open question 1 decides. |

## Open questions

1. ~~**How the iPhone enters keys** (blocks phase 3).~~ **Decided 2026-11-23: a server page opened in the app's sign-in sheet**, as Connect a bank does (#258). Was: either a server page opened in the app's sign-in sheet, as Connect a bank does (#258), so keys only ever go in from a signed-in browser with a fresh two-factor code; or a native form in the app's Settings that sends them with the app's API token. The first keeps today's rule that only a browser can do what reads a bank; the second feels more like the rest of the app.
2. ~~**Keep refusing a key change while connections use them?** (phase 1).~~ Decided 2026-11-23: removing your keys, or replacing them with a different application or client id, is refused while connections use them. The same day it was also decided that each connection keeps its own copy of the keys it was made with, so a change would no longer break those connections. Phase 1 is built with the refusal, as decided; this asks whether it's still wanted. **Decided 2026-11-23: keep the refusal.**

## The plan

**Goal:** a person who wants to sync a bank through Teller or Plaid uses their own developer keys, entered in their own Settings and kept encrypted in the database, instead of keys the server's operator puts in `.env`. The admin's part stays as it is: the Admin → Bank sync switch for everyone, and a tick per person and service in Admin → Users (#264). It extends roadmap item 29 and follows `Plans/bank-providers.md` (#259) and `Plans/sync-access.md` (#269).

**Decided 2026-11-23** (asked while planning; [decision page](../docs/dev/decisions/bank-sync.md#2026-11-23-each-persons-own-teller-and-plaid-keys)):

- **Each person brings their own keys**; not keys the admin enters once for everyone; not both.
- **On upgrade, keys in `.env` are copied to the people using them:** everyone with a Teller or Plaid connection gets the server's keys (and Teller's certificate) saved as their own, so nothing stops. After that `.env` isn't read for Teller or Plaid.
- **Each connection keeps an encrypted copy of the keys it was made with,** so a connection passed to another owner when its person is deleted (#266) keeps syncing without the new holder seeing the keys. Your own keys are what your new connections use.
- **Changing keys in use is refused:** removing your keys, or replacing them with a different application or client id, is refused while connections use them, naming those connections. Replacing with the same id (a renewed certificate, a rotated secret) is allowed. See open question 2.
- **Keys go only into sealed backups and moves,** never a plain export, as bank connections do today.
- **The web takes Teller's zip:** one file picker for the `teller.zip` Teller downloads, with two file pickers (`certificate.pem`, `private_key.pem`) and pasting the text as fallbacks.
- **Entering keys on the iPhone and the Admin marks wait** for phases 3 and 2.
- **Done means** API tests in CI against stand-in providers (and `swift test` for the iPhone), then a release. No hands-on check between phases.

**Out of scope:**

- Removing the Teller and Plaid lines from `.env.example` and `docker-compose.yml`: phase 1 keeps them, marked as read once on upgrade, so a server that skips a version still copies them. They can go in a later release.
- Teller or Plaid on a phone without a server (standalone, #239). The earlier reason it was out (the operator's keys can't ship in an app) doesn't hold for a person's own keys in their own Keychain, so it could be a later item, but not in this plan.
- SimpleFIN, which already takes each person's own token.
- Email alerts' `MS_CLIENT_ID`, which stays in `.env`.

**What's there today:**

- `apps/server/app/teller.py`: `app_id()`, `environment()` and `_cert()` read `TELLER_APP_ID`, `TELLER_ENV`, `TELLER_CERT_FILE` and `TELLER_KEY_FILE`; `_client()` hands the certificate files to `httpx`. The compose file mounts `TELLER_CERT_DIR` read-only at `/run/teller`; the container's file system is read-only apart from a `tmpfs` at `/tmp`, and it runs as uid 1000.
- `apps/server/app/plaid.py`: `_keys()` and `environment()` read `PLAID_CLIENT_ID`, `PLAID_SECRET` and `PLAID_ENV`.
- `main.py`: `bank_providers()` says what the instance offers (one answer for everyone), `bank_access()` which providers a person is ticked for; `/api/bank` and `/api/bank/status` carry `providers` and `providers_allowed`.
- `db.py`: `BankConnection.access_url_enc` holds the provider's token, encrypted with `ENCRYPTION_KEY` (`encrypt_str` / `decrypt_str`); `AdminSetting` is the key/value table; `BankAccess` holds the ticks.
- `backup.py`: `include_bank` puts bank connections only into a sealed backup.

### Phase 1: Your own keys, server and web

**What changes:**

- **Schema:** a `bank_keys` table, one row per person and service (`user_id`, `provider`, `environment`, the application or client id, and the secret part encrypted: Plaid's secret, or Teller's certificate and private key), with when it was saved and last checked. `bank_connections` gains the encrypted copy of the keys it was made with.
- **Provider calls take keys:** every call in `teller.py` and `plaid.py` takes the keys to use instead of reading `os.environ`; syncs, balances, connecting, finishing and disconnecting use the connection's copy, and starting a new connection uses the person's own keys. Teller's certificate and key are written to files under `/tmp`, readable only by the app, for as long as one `httpx` client needs them.
- **Upgrade:** when `.env` has Teller or Plaid keys, each person with a connection of that service gets them saved as their own keys, and each such connection gets its copy. Done once; Admin → Bank sync then says the `.env` lines are no longer read.
- **What's offered:** a service is offered to a person when an admin has ticked them (or they're an admin) and they've saved their keys. `providers[].available` and `providers_allowed` become per person, so the iPhone's Connect a bank follows without an app change. Someone ticked without keys is told in Settings to add theirs.
- **Settings → Bank sync:** a card each for "Your Teller keys" (application id, environment, the zip or the two files or pasted text) and "Your Plaid keys" (client id, secret, environment). Saving checks the keys with the service first (Teller: a call with the certificate; Plaid: a call with the id and secret) and says what's wrong if they don't work. Once saved, a card shows the id, the environment and when they were checked, never the secret, with Replace and Remove. Saving, replacing and removing need a signed-in browser and, with two-factor on, a fresh code, as connecting does.
- **Changing keys in use is refused** as decided above, naming the connections.
- **Sealed backups and moves** carry the person's keys and each connection's copy; a plain export carries neither. An older backup without keys restores as before.
- **Audit log:** `bank_keys_saved` and `bank_keys_removed`, with the service and environment, never a key.
- **Docs:** the bank sync guide (your own Teller or Plaid account, step by step), `.env.example` and `docker-compose.yml` comments, `PRIVACY.md`, `docs/privacy.md`, `SECURITY.md`, the changelog (a **Breaking:** entry: keys move from `.env` to each person's Settings).

**What you have to do:** nothing until the release; afterwards your own Teller or Plaid keys are already in your Settings if your server had them in `.env`.

**Done when:** API tests pass in CI: the security guard for every new route, each route's happy and error paths, the copy on upgrade, calls made with the right person's or connection's keys, the refusal while in use, a sealed backup round trip, and no response or log line carrying a secret. Settings checked headless at 1100 and 390 px. Released.

### Phase 2: Admin sees who has their own keys

**What changes:** Admin → Users shows, next to each person's Teller and Plaid ticks, whether they've saved their own keys for that service and in which environment ("own keys, development"), never the keys. A ticked person without keys reads as "ticked, no keys yet".

**What you have to do:** nothing.

**Done when:** API tests pass (the admin list's new fields, a non-admin refused, no key in the response). Admin checked headless. Released.

### Phase 3: Your own keys from the iPhone

**What changes:** the iPhone app's Bank sync card can add, replace and remove your Teller and Plaid keys, Teller's certificate picked from Files (the zip or the two files), on the path open question 1 decides. The card shows which services have keys, as Settings does.

**What you have to do:** settle open question 1 first.

**Done when:** `swift test` passes, the card checked in the simulator (through `with-simulator.sh`), server tests pass for any server change, released.
