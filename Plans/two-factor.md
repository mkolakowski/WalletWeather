# Two-factor sign-in (authenticator app codes)

Tracking issue: #170

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Set up, sign in with a code, recovery | #165 | Released in 1.57.0 (web 1.75.0, schema 20) |
| 2. A code in the iOS app's sign-in | #166 | Released in 1.59.0 (iOS 0.11.0) |
| 3. Remember this browser | #167 | Built as 1.58.0 (web 1.76.0, schema 21), released in 1.59.0 |
| 4. Admin: require it for everyone | #168 | Open, after phase 1 |
| 5. A code for sensitive actions | #169 | Open, after phase 1 |

Planned 2026-11-15.

Phase 1 built 2026-11-15 as app 1.57.0 (web 1.75.0, schema 20). Verified by 21 new tests in `test_two_factor.py` (263 in all pass), the codes against the standard's published values among them. The screens were driven in a headless browser against a throwaway server (set-up, the QR code decoded back to its link, the code step, a recovery code, the app sign-in page, new recovery codes, the admin switch-off: 19 checks pass). Released 2026-11-15 in v1.57.0 (release issue #172). Not yet tried on your instance with a real authenticator app.

Phase 3 built 2026-11-15 as app 1.58.0 (web 1.76.0, schema 21), after phase 1's release in v1.57.0 but before your try of it (your call). A `remembered_browsers` table keeps each browser's cookie as a SHA-256, with a short name worked out from the browser ("Safari on iPhone", never the user-agent string) so Settings can tell them apart; an admin's password reset forgets them too, alongside the three the decision names. Verified by 17 new tests in `test_remembered_browsers.py` (280 in all pass) and a headless browser run against a throwaway server at phone and desktop widths (tick box, signed in with the password alone, the Settings list with "This browser", Forget, asked again: 22 checks pass). Released 2026-11-15 in v1.59.0 (release issue #173). Not yet tried on your instance.

Phase 2 built 2026-11-15 as app 1.59.0 and iOS 0.11.0 (web and schema unchanged), also before your try of phase 1 (your call). `POST /api/auth/token` takes an optional `code`; without one, or with a wrong one, it answers 403 with `two_factor_required`, which the app turns into a Code field on the Connect screen. Verified by 7 new server tests (286 in all pass), 4 new tests in the app's library (98 pass) and a simulator build. The app was not run in a simulator or on the phone, so the Code field hasn't been seen on screen. Released 2026-11-15 in v1.59.0 (release issue #173); the app itself still has to be installed on the phone.

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

1. ~~**A QR code needs a library, or does it?**~~ Decided 2026-11-15 ([decision](../docs/dev/decisions/two-factor.md)): a QR code, yes; a library, no. The web client already had its own QR encoder (written for the API token's QR code, #100), so the set-up screen draws the code with that and `segno` was never added. The codes themselves are Python's standard `hmac`, so `pyotp` wasn't needed either.
2. ~~**How many wrong codes?**~~ Decided 2026-11-15 ([decision](../docs/dev/decisions/two-factor.md)): per user from any address, with the password limit's numbers (5 in 15 minutes by default), as built in phase 1.
3. ~~**How long is a browser remembered?**~~ Decided 2026-11-15 ([decision](../docs/dev/decisions/two-factor.md)): 30 days; switching two-factor off, changing the password or an admin's switch-off forgets every remembered browser.
4. ~~**Who does "require it" cover?**~~ Decided 2026-11-15 ([decision](../docs/dev/decisions/two-factor.md)): users with a password. Google-only users aren't asked.
5. ~~**Which actions ask again?**~~ Decided 2026-11-15 ([decision](../docs/dev/decisions/two-factor.md)): changing the password, deleting your own account, making an API token (admin and app tokens) and switching two-factor off.

## The plan

**Goal:** a stolen password alone no longer opens an instance. A user can switch on a second step: a 6-digit code from an authenticator app (any app that follows the usual standard, TOTP), asked after the password. It is roadmap item 14, and one of the two things to do before bank sync (item 29, #163).

**Decided 2026-11-15** (asked while planning; [decision page](../docs/dev/decisions/two-factor.md)):

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
