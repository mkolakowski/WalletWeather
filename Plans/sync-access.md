# Sync access: who may connect, and the sync kept with the account

Tracking issue: #269

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Who may connect, per person and provider | Server, Web | #264 | Not started |
| 2. The account holds its sync | Server, Web | #265 | Not started |
| 3. The connection passes on | Server, Web | #266 | Not started; open question 1 |
| 4. The same on the iPhone | iOS | #267 | Not started; waits for the release of phases 1 to 3 |
| 5. Email alerts on the same model | Server, Web, iOS | #268 | Not started; waits for the release of phases 1 to 3; open question 4 |

Planned 2026-11-21 (about 2:40 AM ET), from your question in the whats-next round: "is there a way to move the syncing out of the admin, by the admin allowing users to setup syncs as permissions and the sync living with the acct vs the user". Phases 1 to 3 go out together in one release; phases 4 and 5 each ship afterwards.

Sessions: may span — phases 1 to 3 end with one release and your try on your own instance (with a second user sharing an account), then the iPhone and email alerts follow.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Who may connect | Opus | Sonnet: API tests for every connect route and the upgrade migration | A permission check on every way in, and a migration that mustn't stop a working sync. |
| 2. The account holds its sync | Opus | Sonnet: API tests for owner, editor, read-only and stranger on each route | It widens who sees bank data (a privacy decision), across many routes and screens. |
| 3. The connection passes on | Opus | Sonnet: API tests for deleting the connecting person | Touches account deletion, where a mistake loses data. |
| 4. The same on the iPhone | Sonnet | none | One card and one button on existing screens, against routes phases 1 and 2 already shape. |
| 5. Email alerts | Opus | Sonnet: API tests | The same model applied to a second feature with its own open question. |

## Open questions

1. **Who gets a connection when its person leaves, if its linked accounts have different other owners?** (blocks phase 3) Assumed: the connection goes, whole, to the other owner of the account it was linked to first (the longest-standing owner if there are several); links to accounts that person doesn't own stay, since phase 2 lets owners and editors run them, and an owner can unlink. The delete-account screen names who it goes to. If no linked account has another owner, the connection is deleted, as today.
2. **What unticking a person does to the connections they already have.** (blocks phase 1's last part) Assumed: unticking a provider stops that person's connections of it from syncing, as the master switch does, and keeps them so ticking again carries on; Settings tells them an admin has paused it. Not deleted.
3. **What an editor is told about whose bank login feeds the account.** (blocks phase 2's wording) Assumed: "Synced from <name>'s SimpleFIN connection" on the account's sync card, with the bank account's name; never the token or anything else about the login.
4. **Does a mailbox pass on when its person leaves?** (blocks phase 5) Assumed: no. A mailbox is someone's own email, so it's disconnected when they leave, unlike a bank login that feeds shared accounts.

Settled 2026-11-21 ([decision](../docs/dev/decisions/bank-sync.md#2026-11-21-who-may-connect-and-the-sync-kept-with-the-account)): an admin ticks each person for each provider; the Admin → Bank sync switch stays as an off-for-everyone kill switch; on upgrade, whoever has a connection gets its provider ticked and admins can always connect; the bank login stays its person's but each account's link, status, log, Unmatched list and Sync now belong to the account; owners and editors see and run them, read-only people only see the lines; only owners link or unlink; bank sync first, email alerts later in this plan.

## The plan

Today one switch in Admin turns bank sync on for everyone who can sign in (decided 2026-11-16, question 3), and a bank connection belongs to the person who made it (`BankConnection.user_id`). Only that person sees an account's sync log, Unmatched list, bank balance and Sync now; people the account is shared with see the lines arrive but nothing about the sync. If the person who connected is deleted, the connection and its links go with them.

**Out of scope:** sharing a bank login itself (another person reconnecting or renaming someone's connection, or linking their accounts to it); per-account provider limits; changing what read-only people see beyond the synced lines they already see.

### Phase 1: Who may connect, per person and provider

**Server:** a table of which providers each person may connect (`user_id`, `provider`; schema bump). Admin → Users gets a tick per provider for each person (Teller and Plaid shown only when their keys are in `.env`), through `PATCH /api/admin/users/{id}` (`current_admin`), recorded in the audit log as `bank_access_changed`. Every way to connect (`/api/bank/connect`, `/connect/start`, `/connect/check`, the Teller enroll route and `/app-connect-bank`) refuses a provider the person isn't ticked for, with a message saying to ask an admin; admins are always allowed. `/api/bank` reports `providers_allowed`. The Admin → Bank sync switch stays: off stops every sync and hides bank sync for everyone, whatever is ticked. Unticking pauses that person's connections of that provider (open question 2).

**Upgrade:** each person with a connection gets its provider ticked, so nothing that works today stops; everyone else starts unticked.

**Web:** the ticks in Admin → Users; Settings → Bank sync shown to a person only when the switch is on and they're ticked for something (or still have a connection to remove), offering only their ticked providers.

**Done when:** API tests cover each connect route ticked, unticked and as an admin, the upgrade migration on a database with connections of each provider, and the audit event; `test_security_guards.py` still passes; the screens checked in a headless browser.

### Phase 2: The account holds its sync

**Server:** a linked account's sync belongs to the account. Everyone with edit or owner on it can read its sync log (`BankSyncRun` read by account, not by person), its Unmatched list, match a line by hand or leave it, see its bank balance and Adjust to bank, and run Sync now for it (`POST /api/bank/sync` with the account, which syncs the connection that feeds it). Forecast's `bank_unmatched` and `bank_unmatched_count` count for editors too. Read-only people see the synced lines and nothing else, as today. Linking and unlinking stay with owners (decision 7 kept); the connection's own controls (reconnect, disconnect, categories) stay with its person.

**Web:** an editor's Settings → Bank sync lists the shared accounts that sync, each with its status, last sync, "Synced from …" (open question 3) and Sync now; the account's sync log, Unmatched panel and bank balance show for them as they do for the owner.

**Done when:** API tests for owner, editor, read-only and someone with no access on every route above (404 for the last two where it's 404 today); the screens checked in a headless browser as an editor.

### Phase 3: The connection passes on

**Server:** deleting a person (themselves or by an admin) passes each of their bank connections that still feeds an account with another owner to that owner (open question 1), with its links, log and category map, instead of deleting it; the delete-account screen and the admin's delete say who it goes to. A connection with no such account is deleted, as today. Recorded in the audit log as `bank_connection_passed`.

**Done when:** API tests for deleting the connecting person with one other owner, with two different other owners, and with none; the sync carries on for the new holder.

**Release:** phases 1 to 3 go out together, then your try on your own instance with a second user who shares an account.

### Phase 4: The same on the iPhone

The bank sync card in Settings shows the shared accounts an editor can sync (status and Sync now), and **Connect a bank** appears only when the person is ticked for Teller or Plaid. Needs the server from phases 1 to 3.

**Done when:** checked on your phone over TestFlight as an editor and as an unticked person.

### Phase 5: Email alerts on the same model

The same for email alerts: an admin ticks who may connect a mailbox (Microsoft 365, and Gmail and IMAP once bank-alert-emails phase 3 lands), with the Admin → Email alerts switch kept as a kill switch and whoever has a mailbox ticked on upgrade; the alert-fed lines' Unmatched list (already shared by phase 2), status and Check now for editors. A mailbox doesn't pass on (open question 4).

**Done when:** API tests as in phases 1 and 2 for the mail routes; the screens checked in a headless browser; the iPhone's email alerts card follows if bank-alert-emails phase 6 has landed.
