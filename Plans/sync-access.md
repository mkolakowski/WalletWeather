# Sync access: who may connect, and the sync kept with the account

Tracking issue: #269

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Who may connect, per person and provider | Server, Web | #264 | Released in 1.92.0, 2026-11-22 |
| 2. The account holds its sync | Server, Web | #265 | Released in 1.92.0, 2026-11-22 |
| 3. The connection passes on | Server, Web | #266 | Released in 1.92.0, 2026-11-22 |
| 4. The same on the iPhone | iOS, Server | #267 | Built 2026-11-22 in iOS 0.31.0 and server 1.92.1; server released in v1.97.0 (2026-11-23); on TestFlight in build 400 (iOS 0.33.0); waiting on your check |
| 5. Email alerts on the same model | Server, Web | #268 | Built 2026-11-22 in 1.93.0 (web 1.104.0, schema 36), released in v1.97.0 (2026-11-23); your check: tick and untick someone in Admin → Users, and an editor of a shared account presses Check now |

Phase 1 built 2026-11-21 in 1.90.0 (web 1.101.0, schema 35), not released. The ticks are set with `PUT /api/admin/users/{id}/bank-access` (a browser session, like the Bank sync switch) rather than the `PATCH` the plan first named, so an admin API token can't widen who reaches a bank. API tests in `apps/server/tests/test_bank_access.py` (14: each connect route ticked, unticked and as an admin, a tick taken away mid-connection, the switch, the admin route and its audit event, pausing and carrying on, one provider paused beside another, and the once-only upgrade); the bank tests' `register` now ticks its users. Admin → Users and Settings → Bank sync (paused card, only ticked providers offered, hidden tab) checked in headless Chromium against a stubbed API.

Phase 5 built 2026-11-22 (about 9:00 PM ET) in 1.93.0 (web 1.104.0, schema 36), not released. An admin ticks who may connect a mailbox in Admin → Users' new Email alerts column (`PUT /api/admin/users/{id}/mail-access`, a browser session, audit `mail_access_changed`); on upgrade whoever has a mailbox is ticked once; unticking pauses the mailbox (kept, not checked, Check now 403). `/api/mail` and `/api/mail/status` gain `providers_allowed` and `shared` (accounts the caller owns or edits that another person's sender or card feeds: whose mailbox, last check, paused, unmatched count; never senders, folder or address), and `POST /api/mail/check` takes `account_id` (runs as the mailbox's person, counting only that account's lines). A mailbox doesn't pass on: it goes with its person. Verified by 39 API tests in `apps/server/tests/test_mail_access.py` with the mail, security and licence tests (260 passed), the whole suite (1182 passed; 4 bank tests fail on `main` too, date-dependent, filed separately), and headless Chromium with the API stubbed at 1100 and 390 px (the Admin column and its PUT, the shared cards, the paused note; no page errors). No iPhone change: bank-alert-emails phase 6 (#211), the app's email alerts card, hasn't landed.

Phase 4 built 2026-11-22 in iOS 0.31.0 and server 1.92.1 (no schema change), not released. The gap the phase named is closed: `GET /api/bank/status` now carries `providers_allowed` (an API token couldn't see who is ticked before; the app reads it, and a server without the field keeps today's behaviour). The Settings card lists `shared` accounts with their status and a Sync now each (`POST /api/bank/sync {account_id}`), and Connect a bank shows only for someone ticked for Teller or Plaid. API tests in `apps/server/tests/test_bank_access.py` (2 new); Swift tests in `BankSyncTests` and `DemoTests` (wording for every state, the Connect rule, the account sync request and a paused holder's refusal), `swift test` 195 passed and the app builds for the simulator. Not yet done: the check on your phone over TestFlight, as an editor and as an unticked person.

Phase 3 built 2026-11-22 (about 12:00 AM ET) in 1.92.0 (web 1.103.0, no schema change), not released. Deleting a person (themselves or by an admin) passes each connection that still feeds an account staying with another owner to the first-linked such account's longest-standing other owner, with its links; the new holder is ticked for its provider ([decided 2026-11-21](../docs/dev/decisions/bank-sync.md#2026-11-21-a-passed-on-connection-ticks-its-new-holder)) and gets a copy of the category map in their same-named categories; sync logs on accounts that stay are kept; `bank_connection_passed` in the audit log (both people by number, under the admin who deleted, or no one for a self-delete). A disabled or demo owner, or one with the same bank account on a connection of their own, is skipped for the next. A code review before the release also closed: Sync now for a shared account reports that account's own numbers only; a locked match's start date can't be changed either; connecting a bank ticks its person (so an admin's connection doesn't pause if they're demoted); the two new events are in Admin → Audit's filter; a shared card's Sync now is off while its person needs to reconnect or can't sign in. The deletion checks (and the new `GET /api/admin/users/{id}/deletion-check`) list `bank_connections_passed` and `bank_connections_deleted`, shown on Settings → Delete account and in Admin's delete. Found along the way and closed in the same phase: Save matches could unmatch an account the person doesn't own, so such a match is now `locked` (text in Settings, 403 from `PUT /api/bank/links`), and an owner's shared card has Stop syncing (`DELETE /api/accounts/{id}/bank-link`, `bank_link_removed`). API tests in `apps/server/tests/test_bank_connection_passes.py` (35: one other owner, two owners, two accounts with different owners, none, self and admin delete, the tick, the category map, the kept log, the events, the checks, locked matches, Stop syncing by level); `test_delete_me.py`'s whole-JSON check gained the two new lists. Delete screens, locked rows and Stop syncing checked in headless Chromium against a stubbed API.

Phase 2 built 2026-11-21 in 1.91.0 (web 1.102.0, no schema change), not released. Owners and editors reach an account's sync log (read by account), Unmatched list, bank balance and Adjust to bank, and `POST /api/bank/sync` takes `account_id` (runs as the connection's person, so their pause, limit and lock apply; the audit event is recorded under whoever pressed it). `/api/bank` and `/api/bank/status` carry `shared` (the bank account's name only in `/api/bank`); the account's last sync there comes from its own sync log, never the connection's summary, so nothing about the person's other accounts shows. Email-alert lines on the Unmatched list reach editors too, since the list is the account's. API tests in `apps/server/tests/test_bank_shared_sync.py` (45: owner, editor, read-only and stranger on every route, Sync now by account including paused, disabled and over-limit holders, the audit event, `shared` in both statuses); six older tests that pinned owner-only updated to the new rule. Settings → Bank sync as an editor checked in headless Chromium against a stubbed API (cards, paused note, Sync now by account, sync log, Unmatched).

Planned 2026-11-21 (about 2:40 AM ET), from your question in the whats-next round: "is there a way to move the syncing out of the admin, by the admin allowing users to setup syncs as permissions and the sync living with the acct vs the user". Phases 1 to 3 go out together in one release; phases 4 and 5 each ship afterwards.

Sessions: may span — phases 1 to 3 end with one release and your try on your own instance (with a second user sharing an account), then the iPhone and email alerts follow.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Who may connect | Opus | Sonnet: API tests for every connect route and the upgrade migration | A permission check on every way in, and a migration that mustn't stop a working sync. |
| 2. The account holds its sync | Opus | Sonnet: API tests for owner, editor, read-only and stranger on each route | It widens who sees bank data (a privacy decision), across many routes and screens. |
| 3. The connection passes on | Opus | Sonnet: API tests for deleting the connecting person | Touches account deletion, where a mistake loses data. |
| 4. The same on the iPhone | Sonnet | none | One card and one button on existing screens, against routes phases 1 and 2 already shape. |
| 5. Email alerts | Opus | Sonnet: API tests | The same model applied to a second feature, where a mailbox doesn't pass on. |

## Open questions

None. Questions 1 to 4 were settled 2026-11-21, as assumed ([decision](../docs/dev/decisions/bank-sync.md#2026-11-21-sync-access-open-questions-1-to-4)):

1. ~~**Who gets a connection when its person leaves, if its linked accounts have different other owners?**~~ The other owner of the account it was linked to first (the longest-standing owner if there are several) gets the whole connection; links to accounts that person doesn't own stay, and their owners can unlink. The delete screens name who it goes to. With no other owner, it's deleted as today.
2. ~~**What unticking a person does to the connections they already have.**~~ Paused, kept: unticking a provider stops that person's connections of it from syncing, ticking again carries on, and Settings says an admin has paused it.
3. ~~**What an editor is told about whose bank login feeds the account.**~~ "Synced from <name>'s <provider> connection · <bank account name>"; never the token or anything else about the login.
4. ~~**Does a mailbox pass on when its person leaves?**~~ No: it's disconnected with them; lines already in stay.

Settled 2026-11-21 ([decision](../docs/dev/decisions/bank-sync.md#2026-11-21-who-may-connect-and-the-sync-kept-with-the-account)): an admin ticks each person for each provider; the Admin → Bank sync switch stays as an off-for-everyone kill switch; on upgrade, whoever has a connection gets its provider ticked and admins can always connect; the bank login stays its person's but each account's link, status, log, Unmatched list and Sync now belong to the account; owners and editors see and run them, read-only people only see the lines; only owners link or unlink; bank sync first, email alerts later in this plan.

## The plan

Today one switch in Admin turns bank sync on for everyone who can sign in (decided 2026-11-16, question 3), and a bank connection belongs to the person who made it (`BankConnection.user_id`). Only that person sees an account's sync log, Unmatched list, bank balance and Sync now; people the account is shared with see the lines arrive but nothing about the sync. If the person who connected is deleted, the connection and its links go with them.

**Out of scope:** sharing a bank login itself (another person reconnecting or renaming someone's connection, or linking their accounts to it); per-account provider limits; changing what read-only people see beyond the synced lines they already see.

### Phase 1: Who may connect, per person and provider

**Server:** a table of which providers each person may connect (`user_id`, `provider`; schema bump). Admin → Users gets a tick per provider for each person (Teller and Plaid shown only when their keys are in `.env`), through `PUT /api/admin/users/{id}/bank-access` (`current_session_admin`), recorded in the audit log as `bank_access_changed`. Every way to connect (`/api/bank/connect`, `/connect/start`, `/connect/check`, the Teller enroll route and `/app-connect-bank`) refuses a provider the person isn't ticked for, with a message saying to ask an admin; admins are always allowed. `/api/bank` reports `providers_allowed`. The Admin → Bank sync switch stays: off stops every sync and hides bank sync for everyone, whatever is ticked. Unticking pauses that person's connections of that provider.

**Upgrade:** each person with a connection gets its provider ticked, so nothing that works today stops; everyone else starts unticked.

**Web:** the ticks in Admin → Users; Settings → Bank sync shown to a person only when the switch is on and they're ticked for something (or still have a connection to remove), offering only their ticked providers.

**Done when:** API tests cover each connect route ticked, unticked and as an admin, the upgrade migration on a database with connections of each provider, and the audit event; `test_security_guards.py` still passes; the screens checked in a headless browser.

### Phase 2: The account holds its sync

**Server:** a linked account's sync belongs to the account. Everyone with edit or owner on it can read its sync log (`BankSyncRun` read by account, not by person), its Unmatched list, match a line by hand or leave it, see its bank balance and Adjust to bank, and run Sync now for it (`POST /api/bank/sync` with the account, which syncs the connection that feeds it). Forecast's `bank_unmatched` and `bank_unmatched_count` count for editors too. Read-only people see the synced lines and nothing else, as today. Linking and unlinking stay with owners (decision 7 kept); the connection's own controls (reconnect, disconnect, categories) stay with its person.

**Web:** an editor's Settings → Bank sync lists the shared accounts that sync, each with its status, last sync, "Synced from <name>'s <provider> connection · <bank account>" and Sync now; the account's sync log, Unmatched panel and bank balance show for them as they do for the owner.

**Done when:** API tests for owner, editor, read-only and someone with no access on every route above (404 for the last two where it's 404 today); the screens checked in a headless browser as an editor.

### Phase 3: The connection passes on

**Server:** deleting a person (themselves or by an admin) passes each of their bank connections that still feeds an account with another owner to that owner, with its links, log and category map, instead of deleting it; the delete-account screen and the admin's delete say who it goes to. A connection with no such account is deleted, as today. Recorded in the audit log as `bank_connection_passed`.

**Done when:** API tests for deleting the connecting person with one other owner, with two different other owners, and with none; the sync carries on for the new holder.

**Release:** phases 1 to 3 go out together, then your try on your own instance with a second user who shares an account.

### Phase 4: The same on the iPhone

The bank sync card in Settings shows the shared accounts an editor can sync (status and Sync now), and **Connect a bank** appears only when the person is ticked for Teller or Plaid. Needs the server from phases 1 to 3.

**Done when:** checked on your phone over TestFlight as an editor and as an unticked person.

### Phase 5: Email alerts on the same model

The same for email alerts: an admin ticks who may connect a mailbox (Microsoft 365, and Gmail and IMAP once bank-alert-emails phase 3 lands), with the Admin → Email alerts switch kept as a kill switch and whoever has a mailbox ticked on upgrade; the alert-fed lines' Unmatched list (already shared by phase 2), status and Check now for editors. A mailbox doesn't pass on.

**Done when:** API tests as in phases 1 and 2 for the mail routes; the screens checked in a headless browser; the iPhone's email alerts card follows if bank-alert-emails phase 6 has landed.
