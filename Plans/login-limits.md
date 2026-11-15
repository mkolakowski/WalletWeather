# Login rate limiting and an audit log

Tracking issue: #135

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Rate limiting and sign-in events | #132 | Built in 1.44.0 (schema 18), not yet released |
| 2. More audit events | #133 | Open (after phase 1) |
| 3. Admin viewer and pruning | #134 | Open (after phase 2) |

Phase 1 built 2026-11-15 in app 1.44.0 / schema 18 (no web change: the sign-in card already shows the server's message), not yet released. Verified by 16 new tests (114 in all pass). Not yet tried on a running instance.

Sessions: may span — each phase ends with a release and your check on your own instance before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Rate limiting and sign-in events | Opus | Sonnet: write the tests once the design is in | Changes the sign-in path (a security control), adds a table, and has to get the client's address right behind a proxy. |
| 2. More audit events | Sonnet | none | One `record_event` call at each place that matters, following phase 1's pattern. |
| 3. Admin viewer and pruning | Sonnet | none | One list endpoint, one Admin panel and one daily delete; follows the Admin page's existing panels. |

## Open questions

1. **How many wrong passwords, and for how long?** (blocks phase 1's numbers, not its build) Working assumption: 5 failed sign-ins for the same email from the same address within 15 minutes block further tries for that pair until the 15 minutes since the last failure have passed; a correct password before that clears the count. Both numbers are settings in `.env` (`LOGIN_MAX_FAILURES`, `LOGIN_WINDOW_MINUTES`) with those defaults.
2. **What does an event store?** (blocks phase 1) Working assumption: when it happened, what it was, the email involved (typed text, cut to 320 characters), the user if there is one, the address the request came from when known, and a short detail. Never a password, never the browser's user-agent string. It is personal data, so it's added to `PRIVACY.md` in phase 1. As built, deleting a user keeps their entries with the email but unlinks the user; the alternative is to blank the email or delete the entries when the user goes, which would also wipe their recent failures from the rate limit.
3. **How long are events kept?** (blocks phase 3) Working assumption: 180 days, a setting (`AUDIT_RETENTION_DAYS`), and never less than a day so the rate limit's window is always there.
4. **Should Google sign-in and registration be limited too?** (blocks nothing) Left out on purpose: Google handles its own password guessing, and `ALLOWED_EMAILS` and `ALLOW_REGISTRATION` already control who can sign up. Revisit if registration is ever left open on a public address.

## The plan

**Goal:** guessing a password gets slow and visible: failed sign-ins are limited per email and address, and what happens on the server is written down where an admin can read it. It also unblocks `POST /api/auth/token` (phone-path phase 3, #43) and the iOS app's email and password sign-in (`Plans/ios-app.md`, phase 7).

**Decided 2026-11-15** ([decision](../docs/dev/decisions/login-limits.md)):
- Phase 1 is the rate limit and the sign-in events together, with no viewer yet.
- The visitor's address comes from Cloudflare's `CF-Connecting-IP` header only when `TRUST_PROXY_HEADERS=true` is set; otherwise it's the connection's own address.
- The later events, the viewer and pruning are separate phases, in that order (you had no preference on the split).

**Out of scope:** limits on Google sign-in and registration (open question 4), limits on API tokens (a token is 256 random bits and can't be guessed), two-step sign-in and password reset (roadmap items 13 and 14), sending alerts by email or push.

### Phase 1: Rate limiting and sign-in events

Roadmap item 15, first part.

- A new `audit_events` table (the next schema number): when, event, user (kept as NULL if the user is deleted), email, address, detail. One row per event; phase 1 writes `login`, `login_failed` and `login_blocked`, for both password and Google sign-in (`detail` says which).
- `POST /api/auth/login` counts the recent `login_failed` rows for the same email and address, so there is no second table. Past the limit it answers `429` with a `Retry-After` header and a sentence the sign-in card shows ("Too many failed sign-ins. Try again in 12 minutes."), without checking the password: a correct one is refused too until the block ends. Emails with no account are counted like real ones, so the answer never says whether an email exists.
- The address: with `TRUST_PROXY_HEADERS=true` the server uses `CF-Connecting-IP` when it's there and the connection's address otherwise; off, always the connection's address. The setting is listed in `.env.example` and `docker-compose.yml`, with a note that it should only be on when the server is reachable only through Cloudflare.
- Settings in `.env.example`: `LOGIN_MAX_FAILURES` (5) and `LOGIN_WINDOW_MINUTES` (15) (open question 1).
- The sign-in card shows the `429` message, not "Invalid email or password".
- `PRIVACY.md` says what the log holds and for how long it's kept (open questions 2 and 3); the README's Security Notes and `SECURITY.md`'s "Known limits" drop "no login rate limiting".
- Tests: the happy path (a wrong password then the right one signs in and clears the count); the sixth failure gets `429` with `Retry-After`; a correct password during a block is refused; a different email or a different address isn't blocked; an unknown email is blocked the same way; the window running out unblocks (by moving the rows' times back); `CF-Connecting-IP` is used only when the setting is on and ignored when it's off; each event row has the right fields and no password.

**You:** on your instance, type a wrong password until you're blocked, read the message, then sign in once it's over.

**Done when:** tests pass; on your instance the sixth wrong password shows the retry message; a correct sign-in afterwards works; `/api/version` shows the new schema.

### Phase 2: More audit events

Roadmap item 15, second part. Depends on phase 1.

- A small `record_event(db, event, user=None, email=None, detail=None)` helper, so each call is one line.
- Events for: your own password change and an admin resetting someone's; an admin disabling, enabling or deleting a user; an admin changing a permission, the instance title or the backup settings; a backup made, downloaded or restored; deleting your own account; an API token made or revoked (by its owner or an admin).
- Each event names who did it and, where there is one, who it was done to (`detail`), never any amounts, account names or other financial data.
- Tests: one per event type that checks the row is written with the right user and detail, and that a refused action (a 403, a wrong password) writes nothing.

**Done when:** tests pass; each action above leaves a row, checked in the database after trying it.

### Phase 3: Admin viewer and pruning

Roadmap item 15, third part. Depends on phase 2.

- `GET /api/admin/audit`: newest first, filters for event and email, paged with a cursor. Readable by an admin's session or an admin token.
- Admin page: an "Audit log" panel with the filters and a "Load more" button. Every typed value (emails especially) is shown as text, never as HTML.
- Pruning: events older than `AUDIT_RETENTION_DAYS` (180, open question 3) are deleted once a day by the existing background thread, never anything newer than a day.
- Tests for the endpoint (shape, filters, paging, 403 for a non-admin and for a read-only or full token) and for pruning (old rows go, recent ones stay).

**You:** open Admin → Audit log after a few sign-ins and read it.

**Done when:** tests pass; the Admin panel lists the events you caused; an event older than the retention is gone after pruning.
