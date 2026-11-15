# Login rate limiting and an audit log

Decisions made while planning [`Plans/login-limits.md`](../../../Plans/login-limits.md) (tracking issue #135).

## 2026-11-15: the first slice and the visitor's address

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The questions:** what the first phase is, and where the server reads the visitor's address for rate limiting, since it sits behind a Cloudflare Tunnel and otherwise sees the tunnel's address.

**Options considered:**
- First phase: rate limiting alone; rate limiting plus the sign-in events; everything at once.
- Address: Cloudflare's `CF-Connecting-IP` header only when a setting turns it on; always the connection's address; ignore the address and count per email only.

**The decision:** phase 1 is the rate limit plus the sign-in events, with no viewer yet. The address comes from `CF-Connecting-IP` only when `TRUST_PROXY_HEADERS=true`, and from the connection otherwise. The header can be forged by anyone who can reach the server directly (port 8300), so it's ignored unless the setting is on, and the setting is for servers reachable only through Cloudflare.

**What it changes:** phase 1 (the table, the counting, the setting) and the order of the later phases. Left as working assumptions in the plan's open questions, not decided: the numbers (5 failures in 15 minutes), what an event stores, and how long events are kept. Asked which parts should wait, Matthew had no preference, so the split into phases 2 and 3 is the planner's and can be changed.

## 2026-11-15: a deleted user's sign-in log entries

**Decided:** 2026-11-15, by Matthew. **Status:** accepted. Settles part of open question 2.

**The question:** phase 1 (#132) kept a deleted user's sign-in log entries with their email, only unlinked from the user. What should happen to them?

**Options considered:**
- Blank the email: the entries stay (what happened, when, from which address), the email goes.
- Keep them with the email: a complete log for an admin looking into something later, but the address outlives the user.
- Delete their entries: cleanest for privacy, but the log loses those events, failed attempts on their email by someone else included.

**The decision:** blank the email. Deleting a user, by themselves or by an admin, sets `email` to NULL on every `audit_events` row with their user id or their email address (any case), and the foreign key already nulls the user id. Their recent failures stop counting toward the rate limit, which doesn't matter for an account that no longer exists.

**What it changes:** #139 (app 1.46.1): `_delete_user` in `apps/server/app/main.py`, its tests in `test_login_limits.py`, and `PRIVACY.md`. Entries logged for users deleted before 1.46.1 keep their email.

## 2026-11-15: what phase 2 logs, and how it names people

**Decided:** 2026-11-15, by Matthew. **Status:** accepted. Settles the rest of open question 2 for phase 2 (#133).

**The questions:** phase 2 was to log "your own password change", but the app had no way to change your own password (only an admin reset in Admin → Users). How should an event name the user an admin acted on, given that deleting a user blanks their email in the log (#139)? And which backups count?

**Options considered:**
- Own password: skip the event and open an issue for a change-password form; or build the form in phase 2.
- The person acted on: by user number in `detail` ("user #7"); or by email in `detail`, scrubbed when that user is deleted.
- Backups: admin and personal (each user's export and import), scheduled ones included; the same without scheduled ones; admin only.

**The decision:** build the form in phase 2: Settings → Change password, `POST /api/me/password` with the current and new password, browser session only, not for Google-only users (they have no password; an admin can set one). Name the person acted on by number ("user #7", or "own user" when an admin acts on themselves), so a deletion leaves nothing naming them with no extra clean-up; the phase 3 viewer can show the email for users who still exist. Log admin and personal backups, scheduled ones included (with no user).

**What it changes:** #133 (app 1.48.0, web 1.70.0): `record_event` calls and `audit_target` in `apps/server/app/main.py`, the Change password panel in `apps/web/index.html`, `test_audit_events.py`, `PRIVACY.md`, and the plan's phase 2.

## 2026-11-15: how long the audit log keeps entries, and how the viewer names people

**Decided:** 2026-11-15, by Matthew. **Status:** accepted. Settles open question 3 (#134).

**The questions:** how long audit events are kept before the daily clean-up deletes them, and how the Admin panel shows a user an event names by number.

**Options considered:**
- Retention: 180 days; 90 days; 365 days; keep forever unless a setting says otherwise.
- Names: the email next to the number while that user exists; the number only.

**The decision:** 180 days by default, set with `AUDIT_RETENTION_DAYS` and never less than a day. The panel shows "user #7 (bob@example.com)" while user 7 exists and "user #7" once they're deleted; the log keeps only the number, so the #139 rule still holds.

**What it changes:** #134 (app 1.49.0, web 1.71.0): `GET /api/admin/audit` and `prune_audit_events` in `apps/server/app/main.py`, the Audit log panel in `apps/web/index.html`, `.env.example`, `docker-compose.yml`, the README settings table and `PRIVACY.md`.
