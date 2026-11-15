# Phone path: API tokens

Decisions made while planning [`Plans/phone-path.md`](../../../Plans/phone-path.md) (tracking issue #44).

## 2026-11-15: tokens and the Admin endpoints

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The question:** API tokens (phase 2, #42) are full access or read-only. Can a full-access token reach the Admin panel's endpoints (`/api/admin/*`: users, permissions, backups, restore)? The working assumption was no: the Admin endpoints would need a signed-in browser.

**Options considered:**
- No, browser only: a leaked phone token can't delete users or restore a backup, and the iOS app keeps Admin on the web anyway. Scripts couldn't run backups.
- Yes, for admins: an admin's full-access token reaches the Admin endpoints too, so scripts could run backups, but a leaked admin token could restore or delete everything.
- A third access level: tokens are read-only, full or admin, chosen when made.

**The decision:** a third access level. A token is `read`, `full` or `admin`. Only an admin token reaches `/api/admin/*`; read-only and full tokens get 403 there. Only a user in `ADMIN_EMAILS` can create an admin token, and it loses its admin reach the moment its owner stops being an admin. Elsewhere an admin token works like full access.

**What it changes:** phase 2 (#42): the `access` column takes three values, the Settings form offers the admin level only to admins, and the tests cover each level on the Admin endpoints. Left as a working assumption, not decided: no token of any level can create or revoke tokens. The iOS app (`Plans/ios-app.md`) never asks for an admin token.

## 2026-11-15: password sign-in for apps

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The question:** `POST /api/auth/token` (phase 3, #43) swaps an email and password for a token. Which access levels can it hand out, and when does the token expire if the app doesn't say?

**Options considered:**
- Access: read or full only; any level, as in Settings; full only.
- Expiry when not given: 90 days, as Settings pre-selects; never, as `POST /api/tokens` does; refuse the request unless it says.

**The decision:** read or full only: admin is refused (403) even for an admin, so a stolen password can't mint an admin token, and admin tokens stay a Settings-only thing. The token expires in 90 days unless the request asks for 30, 365 or `null` (never).

**What it changes:** phase 3's last part. It shares the login rate limit and sign-in log with the web sign-in (`Plans/login-limits.md`, #132). The iOS app's email and password sign-in (`Plans/ios-app.md`, phase 7) uses it.
