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
