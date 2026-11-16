# Bank sync: transactions pulled from the bank (SimpleFIN)

Tracking issue: #198

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Encrypted backups | Server, Web | #193 | Not started; its questions are settled |
| 2. Connect a bank and Sync now | Server, Web | #194 | Not started |
| 3. Daily sync and its status | Server, Web | #195 | Not started |
| 4. Bills matched automatically | Server, Web | #196 | Not started; its question is settled |
| 5. Status and Sync now in the iOS app | iOS | #197 | Not started |

Planned 2026-11-16. Open questions 1 to 8 settled the same day; question 9 holds what followed from them. Added the same day at your ask: a sync log for the account's owner (phase 3) and a list of unmatched synced lines with matching by hand (phase 4).

Sessions: may span — each phase ends with a release and your try on your own instance before the next starts, and phase 2 needs your own SimpleFIN subscription.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Encrypted backups | Server, Web | Opus | Sonnet: write the endpoint tests once the file format is settled | A new file format that has to restore years from now, and the key handling has to be right the first time. |
| 2. Connect a bank and Sync now | Server, Web | Opus | Sonnet: tests against a stand-in SimpleFIN; Haiku: find every place a transaction is created or exported | The server's first call out to another service, a new stored secret, a schema version and the guard against a pasted token pointing somewhere else. |
| 3. Daily sync and its status | Server, Web | Sonnet | none | Follows the backup scheduler's pattern in `main.py`; the calls and the tables exist by then. |
| 4. Bills matched automatically | Server, Web | Opus | Sonnet: tests for the matching cases; Sonnet: the Unmatched list's screen once its endpoints exist | Changes what the forecast shows as paid; a wrong match moves real numbers, so the rules, matching by hand and the undo need care. |
| 5. Status and Sync now in the iOS app | iOS | Sonnet | none | One row and one button on an existing screen and two fields in the bill editor, against endpoints that exist. |

## Open questions

1. ~~**What unlocks an encrypted backup?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): a passphrase, typed when exporting and again when importing. Scheduled backups use `BACKUP_PASSPHRASE` from `.env`.
2. ~~**Do plain backups stay?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): no, backups are encrypted only. What that means for the readable copy and the schedule is question 9.
3. ~~**Who may connect a bank?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): nobody until an admin switches bank sync on in Admin (off by default); then any user can connect their own bank.
4. ~~**How far back does the first sync reach?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): to a start date you pick for each account when matching it, defaulting to today.
5. ~~**Pending bank transactions.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): sync waits until the bank posts them.
6. ~~**How close is a match?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): settable per bill (days either side and how far the amount may differ), starting at 5 days and 10%. Always the same account and direction; the nearest date wins and a tie is left unmatched.
7. ~~**Shared accounts.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): only an account's owner can link it to a bank account.
8. ~~**A fresh code for connecting?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-sync.md)): yes, with two-factor on, connecting and disconnecting each ask for a fresh code, in a browser session only.
9. **The readable copy, old backups and the schedule, now that backups are encrypted only.** Blocks nothing; phase 1 is built on these assumptions unless you say otherwise. Assumed: (a) each user keeps a readable "Download my data" JSON, as `PRIVACY.md` promises; it isn't offered as a backup and never holds the bank connection. (b) Plain backup files made before this version still import. (c) The scheduled backup and the admin's full-system backup won't run without `BACKUP_PASSPHRASE` in `.env`, and Admin says so instead of quietly writing a plain file.
10. **How long the sync log is kept, and what a line in it shows.** Blocks nothing; phase 3 is built on this unless you say otherwise. Assumed: kept as long as the audit log (`AUDIT_RETENTION_DAYS`, 180 days by default); each sync shows when it ran, whether by schedule or Sync now, and how many lines came in, were skipped as already there, matched a bill or were left unmatched, with the lines themselves a tap away.

## The plan

**Goal:** transactions arrive from the bank by themselves instead of by CSV upload, are tagged by the auto-tag rules, and mark the planned bills they pay. It is roadmap item 29.

**Decided 2026-11-16** (asked while planning, #198; [decision page](../docs/dev/decisions/bank-sync.md)):

- **SimpleFIN Bridge, not Plaid.** You pay SimpleFIN yourself (about $15 a year), paste one token into WalletWeather, and the server asks SimpleFIN for transactions. No approval from a provider, no script loaded from another site, no public address needed. The connection can read transactions and balances and can't move money.
- **Encrypted backups come first** (roadmap item 12), as phase 1, so the bank token is never in a backup file anyone could read.
- **The first bank release is Connect and Sync now.** The daily schedule, the matching and the iOS part each get their own phase.
- **Bank rows match planned bills automatically:** a bank row close in date and amount to a planned bill marks that bill paid at the real amount; anything unmatched lands as a new paid line; a wrong match can be undone.
- **The iOS app gets status and a Sync now button.** Connecting a bank stays in the web app.
- **Done means** API tests in CI, then a release and your try on your own instance, phase by phase, as the two-factor plan did.

**Out of scope:** Plaid; bank-supplied categories (SimpleFIN gives none; the auto-tag rules do that work); connecting a bank from the iOS app; the sync log and the Unmatched list in the iOS app (web only for now); comparing the bank's balance with yours; investments and loans; moving money; more than one SimpleFIN connection per user.

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

- Every backup is encrypted with a passphrase: a user's own, the admin's full-system one and the scheduled ones. Export asks for the passphrase (twice, with a warning that it can't be recovered); the scheduled and full-system backups use `BACKUP_PASSPHRASE` from `.env` (added to `.env.example`) and don't run without it (open question 9).
- Import asks for the passphrase; a wrong one is refused with a plain message and nothing is changed. Plain backup files from earlier versions still import (open question 9).
- The readable copy `PRIVACY.md` promises stays as "Download my data", not offered as a backup (open question 9).
- Documents: the README's security notes and `SECURITY.md` "Known limits" change "backups are not encrypted", `PRIVACY.md` on how to treat backup files, `ROADMAP.md` item 12, the changelog.
- Tests: an encrypted export imports back the same; a wrong passphrase is refused; a damaged file is refused; a plain backup from an earlier version still imports; the scheduled backup is encrypted, and refuses to run without `BACKUP_PASSPHRASE`.

**You:** add `BACKUP_PASSPHRASE` to your `.env`, then on your instance make an encrypted backup, import it into a throwaway user or instance, and try a wrong passphrase.

**Done when:** the tests pass in CI, the version is released, and you've restored from an encrypted backup.

### Phase 2: Connect a bank and Sync now

**Apps:** Server and Web. No iOS work.

- **Schema:** a table for a user's bank connection (the access address, encrypted with `ENCRYPTION_KEY`; when it was made; the last sync and its result), a table linking a bank account to one of the user's accounts with its start date, and on `transactions` the bank's id for the row (kept so it can be looked up without decrypting every row).
- **Connect, in Settings:** paste the token; the server claims it and shows the bank accounts it found; you match each to one of your accounts (or leave it out) and pick a start date, defaulting to today; nothing before it comes in. Only an account you own can be linked. Browser session only; demo users can't; with two-factor on, connecting asks for a fresh code.
- **The token can only point at SimpleFIN:** the pasted token names the address the server will call, so the server checks it against an allowed list (`SIMPLEFIN_HOSTS` in `.env.example`, defaulting to SimpleFIN Bridge) before calling anything, and never follows it elsewhere.
- **Sync now:** a button that asks SimpleFIN for transactions since the last sync (or the start date), lands the new ones as paid lines through the CSV import's path, skips any already there (by the bank's id, and by date, amount and description for rows that came in by CSV or by hand), runs the auto-tag rules, and says how many came in.
- **Disconnect:** asks for a fresh code with two-factor on, then removes the stored access address and the links; lines already brought in stay. Deleting a user removes their connection. The screen says how to revoke the token at SimpleFIN too.
- **Admin:** the switch that allows bank sync on the instance, off by default, and the users list shows who has a bank connected.
- **Audit log:** bank connected, disconnected, sync run (how many lines), sync failed.
- **Backups:** the connection goes into backups, which are all encrypted by then (phase 1), and never into "Download my data".
- **Documents:** `PRIVACY.md` "What leaves the server" and `docs/privacy.md` (the server calls SimpleFIN; what SimpleFIN and the bank see; what's stored), `SECURITY.md` "Known limits" (who can read the access address), the README's security notes and set-up, `.env.example`, `ROADMAP.md` item 29, the changelog.
- **Security checks:** each new route gets its sign-in dependency (and `current_admin` for the admin switch) in `test_security_guards.py`.
- **Tests,** against a stand-in SimpleFIN (no real network): connect and list accounts; a token pointing at another host is refused; sync lands rows once and a second sync adds nothing; a row already imported by CSV isn't doubled; the tag rules run; disconnect removes the secret; a token or a demo user can't connect; with the admin switch off everything is refused; SimpleFIN being down or the token revoked gives a plain error and changes nothing.

**You:** subscribe to SimpleFIN Bridge and link your bank there (in person: your bank's own sign-in), paste the token into your instance, match an account, press Sync now and compare what arrived with your bank's list.

**Done when:** the tests pass in CI, the version is released, and a Sync now on your instance has brought in your real transactions without doubling any.

### Phase 3: Daily sync and its status

**Apps:** Server and Web. No iOS work.

- A background check, like the backup scheduler's, that syncs each connected user about once a day, well inside SimpleFIN's limit, and never at the same moment as a Sync now.
- Settings shows when the last sync ran, how many lines it brought in and, when it failed, why and what to do (a revoked token asks you to connect again). The Dashboard shows a small warning when sync has been failing for more than a day.
- **A sync log, for the account's owner:** on each linked account, a list of its syncs, newest first: when, by schedule or Sync now, how many lines came in, how many were skipped as already there, and any error in plain words; opening one shows the lines it brought in. Only the account's owner sees it, not the people it's shared with (open question 10 for how long it's kept).
- Sync now refuses, with the time to wait, when pressing it again would go over SimpleFIN's limit.
- Posted transactions only; pending ones wait until the bank posts them.
- A status endpoint an API token may read, and Sync now allowed to a token with write access, ready for phase 5.
- Tests: the scheduler syncs a due user and skips one synced recently; a failure is recorded and doesn't stop other users' syncs; the limit is kept; the status endpoint's shape; the sync log's shape, and that someone the account is shared with can't read it; a read-only token can't Sync now.

**You:** leave it running for a few days, check the lines arrive each day by themselves, and read the sync log against what arrived.

**Done when:** the tests pass in CI, the version is released, and your instance has synced by itself on three days running.

### Phase 4: Bills matched automatically

**Apps:** Server and Web. The iOS app shows the result with no change of its own (its Forecast already reads paid lines from the server); its bill editor gets the two match settings in phase 5.

- When a synced row lands in an account, the server looks for a planned bill or income line that isn't paid yet and is close in date and amount: within that bill's own days and amount settings, the same account and direction, the nearest date winning and a tie left unmatched. A match marks that line paid with the bank's date and amount, as marking it paid by hand does, instead of adding a second line.
- **Per bill:** each bill and income line has two match settings, days either side and how far the amount may differ, starting at 5 days and 10%, in the web client's bill editor and on `/api/recurring`. A schema version adds them.
- A matched line says it was matched by bank sync, and can be un-matched: the bill goes back to planned and the bank row becomes its own paid line, and that pair isn't matched again.
- Unmatched rows land as new paid lines, as in phase 2, and are kept on an **Unmatched** list for the account: every synced line that didn't match a bill, with a count on the account so you know there's something to look at.
- **Match by hand:** from an unmatched line, pick one of the account's planned lines that isn't paid yet (bills, income and one-off planned lines, nearest in date first, whatever the bill's settings say). That line is marked paid with the bank's date and amount and the separate line goes away. "Leave as its own line" takes it off the list. A match made by hand can be un-matched like any other.
- The sync log (phase 3) gains how many lines matched and how many didn't.
- The forecast's response says which lines were matched, so the web client can show it.
- Tests: an exact match; a late bill at a slightly different amount; two candidates (left unmatched); a bill's own settings are used, and their limits checked; an already-paid bill is never matched twice; un-match and no re-match; a transfer leg isn't matched to a bill; the Unmatched list's shape; a match by hand, to a line outside the bill's settings too; a line already paid can't be picked; "leave as its own line"; another user's line can't be matched; the forecast response's new field.

**You:** watch a month of real bills on your instance: which matched, which didn't, and whether any match was wrong; match one from the Unmatched list by hand.

**Done when:** the tests pass in CI, the version is released, and you've seen your real bills marked paid by a sync, with one un-matched by hand.

### Phase 5: Status and Sync now in the iOS app

**Apps:** iOS. No server or web work expected (the endpoints come from phase 3; if one turns out to be missing a field, that's a small server change in the same phase, named in its issue when it lands).

- A "Bank sync" row under More: connected or not, the last sync time and how many lines, and any error in plain words.
- A Sync now button, with the same wait message as the web app when the limit is reached. Hidden for a read-only token.
- The bill editor gets the two match settings from phase 4 (days and amount).
- When no bank is connected, the row says connecting is done in the web app.
- Demo mode shows a sample status.
- Tests: `swift test` in `apps/ios/WalletWeatherKit` on samples recorded from the server (connected, never connected, failing, limit reached); a simulator look through the shared simulator lock.

**You:** install the build on your phone, open More, and press Sync now.

**Done when:** `swift test` passes, the simulator screenshots look right, the iOS version is released with the server's, and Sync now has worked from your phone.
