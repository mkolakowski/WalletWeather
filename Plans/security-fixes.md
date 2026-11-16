# Close the security review's findings

Tracking issue: #190

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. One user reaching another, and who may register | #183 | Released in 1.62.0 (web 1.79.0, schema 22) |
| 2. Limits on what's accepted | #185 | Built as 1.63.0, not released |
| 3. Sessions that can be ended | #186 | Built as 1.66.0 (web 1.81.0, schema 23), not released |
| 4. The browser's side | #187 | Built as 1.64.0 (web 1.80.0), not released |
| 5. Dependencies and the image | #188 | Built as 1.65.0, not released |
| 6. Sharing and sign-in limits | #189 | Not started |

Planned 2026-11-16, from the security review of the server (#178).

Phase 1 built and released 2026-11-16 as app 1.62.0 (web 1.79.0, schema 22), before this plan was published: its two findings were rated high, and `SECURITY.md` keeps those private until fixed. Verified by `apps/server/tests/test_security_fixes.py` (the tests that failed before each fix; 443 pass in all) and a headless browser run of sign-up, Add a user and colours against a throwaway server (12 checks pass).

Phase 2 built 2026-11-16 as app 1.63.0 (web and schema unchanged). Verified by its tests moving from `test_security_findings.py` to `test_security_fixes.py` with their markers off, and 11 more on the limits themselves (480 pass in all).

Phase 4 built 2026-11-16 as app 1.64.0 (web 1.80.0). Verified by its tests with their markers off and 24 more (507 pass in all), and a headless browser run: the web app signs in and saves as before with no script errors, a write from another site's page plants nothing, and the app sign-in page refuses to be framed. The browser run found that Chrome keeps a `no-store` request open until its body is read, so the web app now lets go of the answers it doesn't read.

Phase 5 built 2026-11-16 as app 1.65.0. Verified by the whole suite on the new libraries (507 pass, the licence check among them), `/cve-scan`'s script end to end (0 advisories in 35 packages, down from 38 in 4), and the real image run under the hardened Compose file in a throwaway project: it starts, registers a user, saves and writes a backup with a read-only file system and no capabilities. Left out on purpose: pinning images and Actions by digest. Nothing here runs on a schedule to move a pin forward, so a pinned base image would stop picking up its own security patches at each release build, which is worse than the risk it removes.

Phase 3 built 2026-11-16 as app 1.66.0 (web 1.81.0, schema 23), on your choice the same day ([decision](../docs/dev/decisions/security-fixes.md)). Verified by its two tests with their markers off and six more (515 pass in all): the browser that changes the password stays in, tokens survive a change and end with an admin's reset, and a session from before the update still works. The new button hasn't been clicked in a browser yet.

Phases 2 to 6 wait for one release (your choice, same page).

Sessions: may span — six releases, and four answers of yours between them.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 2. Limits on what's accepted | Sonnet | none | Field limits and checks following one pattern; the tests exist. |
| 3. Sessions that can be ended | Opus | none | Changes what a session is, on every request. |
| 4. The browser's side | Sonnet | none | Two small middlewares; the risk is breaking the apps, which a browser run covers. |
| 5. Dependencies and the image | Sonnet | none | Version bumps checked by the suite and `/cve-scan`. |
| 6. Sharing and sign-in limits | Opus | none | Changes how sharing works, with design answers to build on. |

## Open questions

1. ~~**What does a password change end?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/security-fixes.md)): the user's other browser sessions; an admin's reset ends their API tokens too.
2. ~~**Who can you share an account with?**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/security-fixes.md)): type the exact email, and the other person accepts before the account appears for them.
3. ~~**May an editor share an account onward?**~~ Decided 2026-11-16 (same page): owners only.
4. ~~**Google sign-in meeting an existing password.**~~ Decided 2026-11-16 (same page): the password is removed and that user's sessions and tokens end.

## The plan

**Goal:** close what the 2026-11-16 security review of `apps/server` found, most serious first, each fix guarded by a test that failed before it.

**How it's tested:** the review wrote one test per finding as the behaviour the fix should give. Open ones are in `apps/server/tests/test_security_findings.py`, marked `xfail(strict=True)`: they fail today and the run stays green. When a phase lands, its tests start passing, strict mode turns that into a failure, and the markers come off in the same commit (the tests move to `test_security_fixes.py`). `test_security_guards.py` pins what already held.

**The findings**, by the review's ids:

| Id | Finding | Rated | Phase |
| --- | --- | --- | --- |
| WW-SEC-01 | ~~A category or tag colour could be any text and was written into the page unescaped~~ | High | 1, fixed |
| WW-SEC-02 | ~~An `ADMIN_EMAILS` address could be registered by whoever typed it first~~ | High | 1, fixed |
| WW-SEC-14 | ~~The hold on users who must set up two-factor trusted the `Host` header~~ | Medium | 1, fixed |
| WW-SEC-04 | ~~A line could name a recurring item on someone else's account~~ | Medium | 1, fixed |
| WW-SEC-05 | ~~Marking a bill paid accepted any category id~~ | Low | 1, fixed |
| WW-SEC-10 | ~~The demo's reserved domain could be registered~~ | Low | 1, fixed |
| WW-SEC-13 | ~~Google sign-in didn't require a verified address~~ (linking to an existing password: open question 4) | Low | 1, fixed; rest in 6 |
| WW-SEC-09 | ~~No upper limits: long names are a 500 or are stored, request bodies and the forecast window can be any size~~ | Medium | 2, built |
| WW-SEC-11 | ~~NaN and Infinity amounts, and unknown frequencies, are stored and break the pages that show them~~ | Low | 2, built |
| WW-SEC-12 | ~~The server starts with an empty or placeholder `SESSION_SECRET`~~ | Low | 2, built |
| WW-SEC-03 | ~~A session can't be ended from elsewhere; a password change leaves other browsers signed in~~ | Medium | 3, built |
| WW-SEC-07 | ~~Writes from another site's page are stopped only by the cookie's `SameSite=Lax`~~ | Medium | 4, built |
| WW-SEC-08 | ~~No security headers; the API's documentation pages are public~~ | Low | 4, built |
| WW-SEC-15 | ~~starlette, authlib, cryptography and python-multipart carry known advisories~~ | Medium | 5, built |
| WW-SEC-19 | ~~Images and Actions pinned by tag; Compose runs the web service with default privileges~~ | Low | 5, built (Compose hardened; digest pins left out, see Status) |
| WW-SEC-06 | Any user can list every user's email and name, and share an account to anyone | Medium | 6 |
| WW-SEC-16 | The sign-in limit is per email and address only; registration has none | Low | 6 |
| WW-SEC-17 | The Cloudflare token hand-back to the app isn't tied to the app that asked | Low | 6 |
| WW-SEC-18 | An editor can share an owner's account onward | Low | 6 |

**Out of scope:** encrypted backups and self-serve password reset (roadmap items; `SECURITY.md` lists them as known limits), HTTPS-only cookies (the app is served over plain HTTP on home networks), a content security policy (the web app is one file of inline script, so a useful one needs that split first).

**What held up in the review** is pinned by `test_security_guards.py`: every route needs a sign-in unless on a short public list, Admin routes need an admin, token and password routes refuse API tokens, one user gets 404 on another's objects, SQL is never built from strings, and passwords, tokens and codes are stored as hashes.
