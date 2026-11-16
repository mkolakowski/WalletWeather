# Two-factor sign-in

Decisions made while planning and building [`Plans/two-factor.md`](../../../Plans/two-factor.md) (tracking issue #170).

## 2026-11-15: what it covers, how to get back in, and the first slice

**Decided:** 2026-11-15, by Matthew. **Status:** accepted.

**The questions:** which sign-ins ask for the code, how someone gets back in without their phone (the app sends no email and has no password reset), what waits for a later phase, and what "done" means for a phase.

**Options considered:**
- Which sign-ins: password sign-ins only; every sign-in, Google included.
- Lost phone: recovery codes and an admin switch-off; recovery codes only; an admin only.
- What could wait: an admin "require it for everyone" setting; "remember this browser"; a code field in the iOS app's sign-in; a code before sensitive actions.
- Done means: tests plus Matthew's try after each release; tests plus one try at the end; tests only.

**The decision:** the code is asked after an email and password only, since Google runs its own two-step check. Ten one-time recovery codes are shown at set-up, and an admin can switch a user's two-factor off (logged). All four extras wait, each as its own phase. Each phase is done when its tests pass, it's released, and Matthew has tried it on his instance.

**What it changes:** phase 1 is set-up, the code step, recovery codes and the admin switch-off. Until phase 2, the iOS app's email and password sign-in refuses a user with two-factor on and points them to the browser sign-in.

## 2026-11-15: a QR code, drawn without a new library

**Decided:** 2026-11-15, by Matthew (a QR code, yes), then settled while building. **Status:** accepted.

**The question:** the set-up screen needs a QR code for the authenticator app to scan. The plan assumed that meant adding a library (`segno`), and Matthew chose "with a QR code".

**What happened:** the web client already had a QR encoder, written for the API token's QR code (#100, [ios-app decisions](ios-app.md)). The set-up screen uses it, so no library was added. The codes themselves are written from the standard (RFC 6238) with Python's own `hmac` and checked against the standard's published values, so the roadmap's `pyotp` wasn't added either.

**What it changes:** no new dependency, nothing to add to `THIRD_PARTY_NOTICES.md`, and the key never leaves the page as an image request.

## 2026-11-15: wrong codes are counted per user

**Decided:** 2026-11-15, while building, then confirmed by Matthew the same day (see below). **Status:** accepted.

**The question:** the password limit counts failures per email and address. Should wrong codes be counted the same way?

**The choice:** per user, from any address, with the same numbers. A code has a million values and three are right at any moment, so a per-address count would hand someone who already has the password five more tries from every address they can use. The cost is that someone who knows the password can keep the code step blocked for the real owner; that person already has half of what they need, and the block shows in the audit log.

## 2026-11-15: wrong codes, remembered browsers, who's required, and what asks again

**Decided:** 2026-11-15, by Matthew (open questions 2 to 5, asked together). **Status:** accepted.

**The questions:** how wrong codes are counted (phase 1, already built), how long "Don't ask on this browser" lasts (phase 3), who an admin's "require it for everyone" covers (phase 4), and which actions ask for a fresh code from someone already signed in (phase 5).

**Options considered:**
- Wrong codes: per user from any address (as built); per email and address, like wrong passwords. Per address would give someone who has the password five more tries from every address they can use.
- Remembered for: 7, 30 or 90 days. Seven means more typing; 90 leaves a stolen laptop trusted for a season.
- Required for: users with a password; everyone, Google-only users too. Google sign-in skips the code (decided above), so a Google-only user's set-up would never be used.
- Asks again: changing the password, deleting your own account, making an API token, switching two-factor off (any combination).

**The decision:**
- Wrong codes stay counted per user from any address, with the password limit's numbers (5 in 15 minutes by default). The working choice above stands.
- A remembered browser lasts 30 days. Switching two-factor off, changing the password or an admin's switch-off forgets every remembered browser.
- "Require it for everyone" covers users with a password. Google-only users aren't asked.
- All four actions ask for a current code (or a recovery code): changing the password, deleting your own account, making an API token (admin and app tokens alike, since a token skips the code afterwards), and switching two-factor off.

**What it changes:** nothing already built. Phases 3 and 4 are built on these answers, which were their working assumptions. Phase 5 grows a little: the plan named only admin tokens, and app tokens (the iOS app's sign-in) now ask for a code too.


## 2026-11-15: remembered browsers are named from the browser

**Decided:** 2026-11-15, while building phase 3 (#167), then confirmed by Matthew. **Status:** accepted.

**The question:** Settings lists remembered browsers so they can be forgotten one by one, which needs some way to tell them apart.

**Options considered:** a short name worked out from the browser's user-agent ("Safari on iPhone"), storing only that name; no name, each listed by the date it was remembered.

**The decision:** the short name. The user-agent string itself is never stored, as with the sign-in log (decided for login-limits). `PRIVACY.md` lists the name with the rest of what a remembered browser keeps.
