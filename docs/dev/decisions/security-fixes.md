# Security fixes

Decisions made while building [`Plans/security-fixes.md`](../../../Plans/security-fixes.md) (tracking issue #190), the plan that closes the 2026-11-16 security review's findings.

## 2026-11-16: the two findings rated high are fixed before anything is published

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The question:** the repository is public and `SECURITY.md` asks for weaknesses to be reported privately. The plan, its issues and its tests describe each weakness. Where do they go before the fixes are out?

**Options considered:** fix the two highs in a release first, then publish the rest; publish the plan at once; keep everything private until every fix is released.

**The decision:** the two highs (and four small findings beside them) were fixed and released as 1.62.0 with only a private draft advisory holding the details. The plan, the phase issues and the remaining findings' tests were published after that release.

**What it changes:** a later review that finds something rated high follows the same order: private advisory, fix, release, then the public write-up.

## 2026-11-16: who may register

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The question:** registering with a password proves nothing about who owns the address, so anyone could register an address listed in `ADMIN_EMAILS` before its owner and become an administrator.

**Options considered:** a registration code set in `.env`; administrators' addresses can't be self-registered once the instance has a user; both.

**The decision:** both. `REGISTRATION_CODE` is optional; an `ADMIN_EMAILS` address registers only while the instance has no users, and after that an administrator adds it (Admin → User management, `POST /api/admin/users`).

**Settled while building:** there's nowhere to type a code on the way back from Google, so with a code set, Google sign-in makes new users only for addresses on `ALLOWED_EMAILS`. An administrator adding a user needs no code and works with registration off, but keeps to `ALLOWED_EMAILS`.

## 2026-11-16: what a password change ends

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**Options considered:** the user's other browser sessions; those and every API token of theirs.

**The decision:** other browser sessions only. The iPhone app and scripts keep their tokens through a password change. An administrator's password reset ends the user's sessions and their tokens, since a reset is for an account that may be in the wrong hands.

**Settled while building:** the same number that ends sessions (`users.session_epoch`) is raised when the user switches two-factor on or off, and by a new "Sign out my other browsers" button. The browser that made the change stays signed in. Sessions from before the update carry no number and keep working.

## 2026-11-16: sharing an account

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The question:** the Permissions panel lists every user's email and name to anyone with an account, and a share takes effect without the other person's agreement.

**Options considered:** type the exact email and the other person accepts first; type the exact email with no acceptance; keep the list.

**The decision:** no user list. The sharer types the exact address, and the account appears for the other person only after they accept an invitation shown in the web app.

## 2026-11-16: editors sharing onward, and a password meeting Google sign-in

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The decision:** only an owner changes who has access to an account; an editor no longer can. When Google sign-in links to a user for the first time and that user already has a password, the password is removed and the user's sessions and tokens end: someone else may have registered the address first and still know the password. The Google owner can have an administrator set a new one.

## 2026-11-16: one release for phases 2 to 6

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The decision:** phases 2, 4, 5, 3 and 6 are built as 1.63.0 to 1.67.0 and held for one release at the end, rather than released one by one. Two of them can stop an instance that updates without a look at its `.env` (a short `SESSION_SECRET`; a reverse proxy that rewrites `Host` with `APP_BASE_URL` unset), and one read of the release notes is better than five.

## 2026-11-16: images and Actions stay pinned by tag

**Decided:** 2026-11-16, while building phase 5. **Status:** accepted; Matthew can overrule it.

**The decision:** the review suggested pinning base images and GitHub Actions by digest. They stay pinned by tag. Nothing in this project runs on a schedule to move a digest forward, so a pinned `python:3.12-slim` would stop picking up its own security patches at each release build, which is a worse problem than the one the pin removes. bcrypt also stays at 4.2.0: 5.x refuses passwords over 72 bytes, and the app accepts 128 characters.
