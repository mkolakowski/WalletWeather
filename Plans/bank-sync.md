# Bank sync: transactions pulled from the bank (SimpleFIN)

Tracking issue: #198

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Encrypted backups | Server, Web | #193 | Not started; waits on open question 1 |
| 2. Connect a bank and Sync now | Server, Web | #194 | Not started |
| 3. Daily sync and its status | Server, Web | #195 | Not started |
| 4. Bills matched automatically | Server, Web | #196 | Not started; waits on open question 6 |
| 5. Status and Sync now in the iOS app | iOS | #197 | Not started |

Planned 2026-11-16.

Sessions: may span — each phase ends with a release and your try on your own instance before the next starts, and phase 2 needs your own SimpleFIN subscription.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Encrypted backups | Server, Web | Opus | Sonnet: write the endpoint tests once the file format is settled | A new file format that has to restore years from now, and the key handling has to be right the first time. |
| 2. Connect a bank and Sync now | Server, Web | Opus | Sonnet: tests against a stand-in SimpleFIN; Haiku: find every place a transaction is created or exported | The server's first call out to another service, a new stored secret, a schema version and the guard against a pasted token pointing somewhere else. |
| 3. Daily sync and its status | Server, Web | Sonnet | none | Follows the backup scheduler's pattern in `main.py`; the calls and the tables exist by then. |
| 4. Bills matched automatically | Server, Web | Opus | Sonnet: tests for the matching cases | Changes what the forecast shows as paid; a wrong match moves real numbers, so the rules and the undo need care. |
| 5. Status and Sync now in the iOS app | iOS | Sonnet | none | One row and one button on an existing screen, against endpoints that exist. |

## Open questions

1. **What unlocks an encrypted backup?** Blocks phase 1. A passphrase you type when exporting (it restores on any server, but a scheduled backup has nobody to type one, so it would need a passphrase kept in `.env`), or the server's own `ENCRYPTION_KEY` (nothing to type, but the backup only restores where that key is, so losing `.env` loses the backups too).
2. **Do plain backups stay?** Blocks phase 1. Keep the unencrypted export as a choice (a readable copy of your data, which `PRIVACY.md` promises each user), with the bank connection only ever in the encrypted kind. Assumed: yes, both stay, and the plain one never holds the token.
3. **Who may connect a bank?** Blocks phase 2. Every user, or only once an admin switches bank sync on for the instance. Assumed: an admin switch in Admin, off by default, because `PRIVACY.md` says nothing leaves the server unless the operator chooses.
4. **How far back does the first sync reach?** Blocks phase 2. SimpleFIN can give roughly the last 90 days. Rows older than what you've already entered change an account's balance unless its starting balance is adjusted. Assumed: you pick a start date per account when matching it, defaulting to today, and nothing before it is brought in.
5. **Pending bank transactions.** Blocks phase 3. Wait until the bank posts them, or show them as not-yet-paid lines. Assumed: only posted transactions are brought in.
6. **How close is a match?** Blocks phase 4. How many days and how much difference in amount still counts as the same bill. Assumed until settled: the same account, within 5 days either side of the planned date, and the amount within 10% (exact for the same sign only); the nearest date wins, and two candidates the same distance apart are left unmatched.
7. **Shared accounts.** Blocks phase 2. Assumed: only an account's owner can link it to a bank account; people it's shared with see the synced lines like any others.
8. **A fresh code for connecting?** Blocks phase 2. Assumed: with two-factor on, connecting a bank asks for a fresh code, as making an API token does (`docs/dev/decisions/two-factor.md`), and it's a browser-session action only, never an API token's.

## The plan

**Goal:** transactions arrive from the bank by themselves instead of by CSV upload, are tagged by the auto-tag rules, and mark the planned bills they pay. It is roadmap item 29.

**Decided 2026-11-16** (asked while planning, #198; [decision page](../docs/dev/decisions/bank-sync.md)):

- **SimpleFIN Bridge, not Plaid.** You pay SimpleFIN yourself (about $15 a year), paste one token into WalletWeather, and the server asks SimpleFIN for transactions. No approval from a provider, no script loaded from another site, no public address needed. The connection can read transactions and balances and can't move money.
- **Encrypted backups come first** (roadmap item 12), as phase 1, so the bank token is never in a backup file anyone could read.
- **The first bank release is Connect and Sync now.** The daily schedule, the matching and the iOS part each get their own phase.
- **Bank rows match planned bills automatically:** a bank row close in date and amount to a planned bill marks that bill paid at the real amount; anything unmatched lands as a new paid line; a wrong match can be undone.
- **The iOS app gets status and a Sync now button.** Connecting a bank stays in the web app.
- **Done means** API tests in CI, then a release and your try on your own instance, phase by phase, as the two-factor plan did.

**Out of scope:** Plaid; bank-supplied categories (SimpleFIN gives none; the auto-tag rules do that work); connecting a bank from the iOS app; comparing the bank's balance with yours; investments and loans; moving money; more than one SimpleFIN connection per user.

**What's there today:**

- CSV import (`csv_import_commit` in `apps/server/app/main.py`) lands each row as a paid `Transaction`, skips duplicates by date, amount and description, and runs `_apply_tag_rules`. Bank sync reuses that landing path.
- `Transaction` has no column for a bank's own transaction id, so de-duplication by id needs a schema version.
- Stored secrets are encrypted with `ENCRYPTION_KEY` (`encrypt_str` in `apps/server/app/db.py`), as two-factor keys are.
- Background work runs as daemon threads started in `main.py` (`_backup_scheduler_loop`, checked every 30 minutes).
- `httpx` is already a pinned dependency, so no new library is needed for the calls out.
- Backups (`apps/server/app/backup.py`) are plain JSON and carry no password hashes or two-factor keys.
- `PRIVACY.md` "What leaves the server" says nothing does, apart from Google sign-in.
- The iOS app's More tab (`apps/ios/WalletWeather/Views/MoreView.swift`) is where a status row would go.

**How SimpleFIN works** (to be checked against its published protocol at the start of phase 2): the token you paste is used once to claim a private access address, which the server keeps. Asking that address for accounts returns each bank account with its balance and its transactions in a date range, each with the bank's id, date, amount and description. SimpleFIN limits how often it may be asked (about 24 times a day) and refreshes from the banks about once a day.

### Phase 1: Encrypted backups

**Apps:** Server and Web. No iOS work.

- An encrypted kind of backup, for a user's own export, the admin's full-system export and the scheduled backups, unlocked as open question 1 settles.
- Import recognises an encrypted file and asks for what unlocks it; a wrong passphrase or key is refused with a plain message and nothing is changed.
- Plain backups stay as they are (open question 2).
- Documents: the README's security notes and `SECURITY.md` "Known limits" change "backups are not encrypted", `PRIVACY.md` on how to treat backup files, `ROADMAP.md` item 12, the changelog.
- Tests: an encrypted export imports back the same; a wrong passphrase is refused; a damaged file is refused; a plain backup still imports; the scheduled backup writes the encrypted kind when set to.

**You:** on your instance, make an encrypted backup, import it into a throwaway user or instance, and try a wrong passphrase.

**Done when:** the tests pass in CI, the version is released, and you've restored from an encrypted backup.

### Phase 2: Connect a bank and Sync now

**Apps:** Server and Web. No iOS work.

- **Schema:** a table for a user's bank connection (the access address, encrypted with `ENCRYPTION_KEY`; when it was made; the last sync and its result), a table linking a bank account to one of the user's accounts with its start date, and on `transactions` the bank's id for the row (kept so it can be looked up without decrypting every row).
- **Connect, in Settings:** paste the token; the server claims it and shows the bank accounts it found; you match each to one of your accounts (or leave it out) and pick a start date (open question 4). Browser session only; demo users can't; a fresh code with two-factor on (open question 8).
- **The token can only point at SimpleFIN:** the pasted token names the address the server will call, so the server checks it against an allowed list (`SIMPLEFIN_HOSTS` in `.env.example`, defaulting to SimpleFIN Bridge) before calling anything, and never follows it elsewhere.
- **Sync now:** a button that asks SimpleFIN for transactions since the last sync (or the start date), lands the new ones as paid lines through the CSV import's path, skips any already there (by the bank's id, and by date, amount and description for rows that came in by CSV or by hand), runs the auto-tag rules, and says how many came in.
- **Disconnect:** removes the stored access address and the links; lines already brought in stay. Deleting a user removes their connection. The screen says how to revoke the token at SimpleFIN too.
- **Admin:** the switch that allows bank sync on the instance (open question 3), and the users list shows who has a bank connected.
- **Audit log:** bank connected, disconnected, sync run (how many lines), sync failed.
- **Backups:** the connection goes into encrypted backups only (phase 1).
- **Documents:** `PRIVACY.md` "What leaves the server" and `docs/privacy.md` (the server calls SimpleFIN; what SimpleFIN and the bank see; what's stored), `SECURITY.md` "Known limits" (who can read the access address), the README's security notes and set-up, `.env.example`, `ROADMAP.md` item 29, the changelog.
- **Security checks:** each new route gets its sign-in dependency (and `current_admin` for the admin switch) in `test_security_guards.py`.
- **Tests,** against a stand-in SimpleFIN (no real network): connect and list accounts; a token pointing at another host is refused; sync lands rows once and a second sync adds nothing; a row already imported by CSV isn't doubled; the tag rules run; disconnect removes the secret; a token or a demo user can't connect; with the admin switch off everything is refused; SimpleFIN being down or the token revoked gives a plain error and changes nothing.

**You:** subscribe to SimpleFIN Bridge and link your bank there (in person: your bank's own sign-in), paste the token into your instance, match an account, press Sync now and compare what arrived with your bank's list.

**Done when:** the tests pass in CI, the version is released, and a Sync now on your instance has brought in your real transactions without doubling any.

### Phase 3: Daily sync and its status

**Apps:** Server and Web. No iOS work.

- A background check, like the backup scheduler's, that syncs each connected user about once a day, well inside SimpleFIN's limit, and never at the same moment as a Sync now.
- Settings shows when the last sync ran, how many lines it brought in and, when it failed, why and what to do (a revoked token asks you to connect again). The Dashboard shows a small warning when sync has been failing for more than a day.
- Sync now refuses, with the time to wait, when pressing it again would go over SimpleFIN's limit.
- Posted transactions only (open question 5).
- A status endpoint an API token may read, and Sync now allowed to a token with write access, ready for phase 5.
- Tests: the scheduler syncs a due user and skips one synced recently; a failure is recorded and doesn't stop other users' syncs; the limit is kept; the status endpoint's shape; a read-only token can't Sync now.

**You:** leave it running for a few days and check the lines arrive each day by themselves.

**Done when:** the tests pass in CI, the version is released, and your instance has synced by itself on three days running.

### Phase 4: Bills matched automatically

**Apps:** Server and Web. The iOS app shows the result with no change of its own (its Forecast already reads paid lines from the server).

- When a synced row lands in an account, the server looks for a planned bill or income line that isn't paid yet and is close in date and amount (open question 6). A match marks that line paid with the bank's date and amount, as marking it paid by hand does, instead of adding a second line.
- A matched line says it was matched by bank sync, and can be un-matched: the bill goes back to planned and the bank row becomes its own paid line, and that pair isn't matched again.
- Unmatched rows land as new paid lines, as in phase 2.
- The forecast's response says which lines were matched, so the web client can show it.
- Tests: an exact match; a late bill at a slightly different amount; two candidates (left unmatched); an already-paid bill is never matched twice; un-match and no re-match; a transfer leg isn't matched to a bill; the forecast response's new field.

**You:** watch a month of real bills on your instance: which matched, which didn't, and whether any match was wrong.

**Done when:** the tests pass in CI, the version is released, and you've seen your real bills marked paid by a sync, with one un-matched by hand.

### Phase 5: Status and Sync now in the iOS app

**Apps:** iOS. No server or web work expected (the endpoints come from phase 3; if one turns out to be missing a field, that's a small server change in the same phase, named in its issue when it lands).

- A "Bank sync" row under More: connected or not, the last sync time and how many lines, and any error in plain words.
- A Sync now button, with the same wait message as the web app when the limit is reached. Hidden for a read-only token.
- When no bank is connected, the row says connecting is done in the web app.
- Demo mode shows a sample status.
- Tests: `swift test` in `apps/ios/WalletWeatherKit` on samples recorded from the server (connected, never connected, failing, limit reached); a simulator look through the shared simulator lock.

**You:** install the build on your phone, open More, and press Sync now.

**Done when:** `swift test` passes, the simulator screenshots look right, the iOS version is released with the server's, and Sync now has worked from your phone.
