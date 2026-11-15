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
