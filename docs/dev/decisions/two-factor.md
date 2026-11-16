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

**Decided:** 2026-11-15, while building; not asked. **Status:** a working choice, open to change (open question 2 in the plan).

**The question:** the password limit counts failures per email and address. Should wrong codes be counted the same way?

**The choice:** per user, from any address, with the same numbers. A code has a million values and three are right at any moment, so a per-address count would hand someone who already has the password five more tries from every address they can use. The cost is that someone who knows the password can keep the code step blocked for the real owner; that person already has half of what they need, and the block shows in the audit log.
