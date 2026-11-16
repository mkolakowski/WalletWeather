# Two-factor sign-in (authenticator app codes)

Tracking issue: #170

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Set up, sign in with a code, recovery | #165 | Open |
| 2. A code in the iOS app's sign-in | #166 | Open, after phase 1 |
| 3. Remember this browser | #167 | Open, after phase 1 |
| 4. Admin: require it for everyone | #168 | Open, after phase 1 |
| 5. A code for sensitive actions | #169 | Open, after phase 1 |

Nothing built yet. Planned 2026-11-15.

Sessions: may span — each phase ends with a release and your try on your own instance with a real authenticator app before the next starts.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Set up, sign in with a code, recovery | Opus | Sonnet: write the endpoint tests once the design is in | Changes the sign-in path, adds a schema version and stores a new secret. |
| 2. A code in the iOS app's sign-in | Sonnet | none | One optional field on an existing endpoint and one field on an existing screen. |
| 3. Remember this browser | Opus | Sonnet: tests | A way to skip a security check, so what it trusts and how it's revoked has to be right. |
| 4. Admin: require it for everyone | Sonnet | none | One admin setting and a gate like the first-login notice's. |
| 5. A code for sensitive actions | Opus | Sonnet: tests | Touches several endpoints that delete or grant access. |

## Open questions

1. **A QR code needs a library, or does it?** (blocks phase 1's set-up screen only) The codes themselves need no library: they're a few lines of Python's standard `hmac`, checked against the standard's published test values, so `pyotp` (the roadmap's suggestion) isn't needed. Drawing a QR code does need one. Working assumption: add `segno` (BSD licence, pure Python, no dependencies of its own) to draw the QR on the server, so nothing loads from another site. The alternative is no QR: the set-up screen shows the key to type and a link that opens the authenticator app on a phone.
2. **How many wrong codes?** (blocks phase 1's numbers, not its build) Working assumption: wrong codes count toward the same limit as wrong passwords (`LOGIN_MAX_FAILURES` in `LOGIN_WINDOW_MINUTES`, 5 in 15 by default), per email and address.
3. **How long is a browser remembered?** (blocks phase 3) Working assumption: 30 days, and switching two-factor off, changing the password or an admin's switch-off forgets every remembered browser.
4. **Who does "require it" cover?** (blocks phase 4) Working assumption: users with a password. Google-only users aren't asked (decided below: Google sign-ins skip the code).
5. **Which actions ask again?** (blocks phase 5) Working assumption: changing the password, deleting your own account, making an admin token, and switching two-factor off.

## The plan

**Goal:** a stolen password alone no longer opens an instance. A user can switch on a second step: a 6-digit code from an authenticator app (any app that follows the usual standard, TOTP), asked after the password. It is roadmap item 14, and one of the two things to do before bank sync (item 29, #163).

**Decided 2026-11-15** (asked while planning):

- **Password sign-ins only.** The code is asked after an email and password. Google sign-in skips it: Google runs its own two-step check.
- **Lost phone: recovery codes and an admin.** Ten one-time recovery codes are shown at set-up, and an admin can switch a user's two-factor off.
- **The first release is the core only.** Requiring it for everyone, remembering a browser, a code field in the iOS app and codes for sensitive actions each wait for their own phase.
- **Done means** API tests in CI, then a release and your try on your own instance, phase by phase.

**Out of scope:** codes by text message or email (the app sends neither), passkeys and security keys, a second step on Google sign-in, self-serve password reset (roadmap item 13), encrypted backups (item 12).

**What's there today:** `POST /api/auth/login` and `POST /api/auth/token` both go through `_password_sign_in` in `apps/server/app/main.py`, which holds the rate limit and writes the sign-in log. Backups carry no password hashes, so they will carry no two-factor keys either.

### Phase 1: Set up, sign in with a code, recovery

- **Schema 20:** on `users`, the key (encrypted with `ENCRYPTION_KEY`, like amounts), when two-factor was switched on, and the last code step used (so a code can't be used twice). A new table of recovery codes, stored as hashes, each usable once.
- **Set-up, in Settings:** start (the server makes a key and returns it with the QR code, open question 1), then confirm with a code from the app, which switches it on and shows the ten recovery codes once. Switching it off, or making new recovery codes, needs the password and a current code. Browser session only, like changing the password. Demo users can't switch it on.
- **Sign-in:** for a user with two-factor on, a right password doesn't sign in. `POST /api/auth/login` answers that a code is needed and the sign-in card shows a code field; a second endpoint takes the code (or a recovery code) and only then sets the session. The half-way state lasts five minutes. Codes are accepted one step either side of now, for clocks that are a little off.
- **Wrong codes** are logged and counted toward the sign-in limit (open question 2).
- **The app's password sign-in** (`POST /api/auth/token`) refuses a user with two-factor on, with a message to use "Sign in with browser", which already goes through the web sign-in. Phase 2 lifts this.
- **Admin:** the users list shows who has it on, and an admin can switch a user's off. An admin setting a user's password doesn't switch it off.
- **Audit log:** switched on, switched off (by the user or an admin), recovery code used, recovery codes remade, wrong code.
- **`GET /api/me`** says whether it's on and how many recovery codes are left.
- **Documents:** `PRIVACY.md` and `docs/privacy.md` (the key and the recovery codes are stored), `SECURITY.md` "Known limits" and the README's security notes drop "no two-factor sign-in", `ROADMAP.md` item 14, the changelog.
- **Tests:** set-up and confirm; sign-in with a right code; a wrong code, a reused code and an expired half-way state are refused; a recovery code works once; wrong codes reach the limit; switching off needs the password and a code; an admin's switch-off; `/api/auth/token` refuses; Google sign-in is unaffected; a token can't reach the set-up endpoints.

**You:** on your instance, switch it on with your authenticator app, sign out and back in with a code, sign in once with a recovery code, and have the admin switch-off tried on a second user.

**Done when:** the tests pass in CI, the version is released, and you've signed in with a code on your instance.

### Phase 2: A code in the iOS app's sign-in

- `POST /api/auth/token` takes an optional code. With two-factor on and no code, it answers that one is needed; with a right code it makes the token as now.
- The iOS app's email and password sign-in shows a code field when the server asks for one.
- Tests for the endpoint (code needed, right, wrong, recovery code) and for the app's handling of the new answer.

**You:** sign the iPhone app in with email, password and a code.

**Done when:** tests pass, the server and the iOS version are released, and the app has signed in with a code.

### Phase 3: Remember this browser

- A tick box on the code step: "Don't ask on this browser for 30 days" (open question 3). The browser gets its own cookie tied to the user; the server keeps a hashed record so it can be forgotten.
- Settings lists remembered browsers and can forget them. Switching two-factor off, a password change and an admin's switch-off forget them all.
- Tests: a remembered browser skips the code; an expired or forgotten one doesn't; one user's cookie doesn't work for another.

**You:** tick the box, sign out and in again without a code, then forget the browser and get asked again.

**Done when:** tests pass, released, and you've tried both on your instance.

### Phase 4: Admin: require it for everyone

- An admin setting: every user with a password must set two-factor up (open question 4). Until they have, the app shows only the set-up screen after sign-in, the way the first-login notice does.
- The admin can't switch the requirement on before setting up their own.
- Tests: the gate holds every other endpoint back; Google-only users aren't gated; switching the setting off lifts it.

**You:** switch it on, sign in as a second user and be walked through set-up.

**Done when:** tests pass, released, and the gate has been seen on your instance.

### Phase 5: A code for sensitive actions

- The actions in open question 5 ask for a current code (or a recovery code) when the user has two-factor on.
- Tests: each action is refused without a code and goes through with one; users without two-factor are unaffected.

**You:** change your password on your instance and be asked for a code.

**Done when:** tests pass, released, and you've been asked on your instance.
