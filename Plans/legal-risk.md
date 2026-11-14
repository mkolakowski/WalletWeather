# Legal risk: close what the legal review found

Tracking issue: #50

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Notices and policies | #45 | Built 2026-11-14, open until your OK |
| 2. First-login notice | #46 | Built 2026-11-14 (app 1.23.0, web 1.47.0, schema 14), released in v1.24.1, open until your OK |
| 3. Licence check and demo names | #47 | Built 2026-11-14 (app 1.23.1, web 1.47.1), released in v1.24.1, open until your OK |
| 4. Delete my own account | #48 | Built 2026-11-14 (app 1.24.0, web 1.48.0), released in v1.24.1, open until your OK |
| 5. Name and store readiness | #49 | Policy page published 2026-11-14; open, waits on your two checks |

Phase 1: documents only, no version. On `main` 2026-11-14; verified by GitHub's community profile showing the security policy and contributing guide, and by a dependency list taken from a clean `python:3.12-slim` install. Private vulnerability reporting was switched on 2026-11-14.

Phase 2: app 1.23.0, web 1.47.0, schema 14, on `main` 2026-11-14, released in v1.24.1 the same day. Verified by 20 passing tests (6 new), a phone-sized browser run against a throwaway copy (notice after sign-up and after a reload, app only after agreeing, no notice afterwards, the Settings card), and the upgrade path (column dropped, restart re-adds it empty, the user is asked again). The web app is gated; the API itself is not.

Phase 3: app 1.23.1, web 1.47.1, on `main` 2026-11-14, released in v1.24.1 the same day. Verified by 23 passing tests (3 new), by the licence test failing when a GPL package (`Unidecode`) was installed for one run, and by a search finding no brand name left in the code. Built as a test with no new dependency, in place of the planned `pip-licenses` step.

Phase 4: app 1.24.0, web 1.48.0, on `main` 2026-11-14, released in v1.24.1 the same day. Verified by 33 passing tests (10 new) and a phone-sized browser run against a throwaway copy (blocked while a shared account is owned, the form once the sharing is removed, a wrong password refused, then deleted, signed out and unable to sign in, with the user's rows gone from the database). Not tested: a Google-only user's typed-email confirmation. Found along the way: an admin deleting a user still removes shared accounts (#57).

Phase 5: the policy page (`docs/privacy.md`, with `docs/index.md` and `docs/_config.yml`) and the app README sections are on `main` 2026-11-14; documents only, no version. Waiting on you:

| Your step | Result | Date |
| --- | --- | --- |
| Switch on GitHub Pages (branch `main`, folder `/docs`) | Done by the session on request. The policy opens at <https://mkolakowski.github.io/WalletWeather/privacy>; `docs/dev` is not published. | 2026-11-14 |
| USPTO and app-store search for the name | not done | |
| Employment-agreement check | not done | |

Sessions: may span — phase 5 waits on checks only you can do, and phases 2 and 4 each end with a release.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Notices and policies | Sonnet | none | Documents only, from findings already written down. |
| 2. First-login notice | Opus | Sonnet: write the endpoint tests once the design is in | A schema change, a new endpoint and a gate every signed-in user passes through. |
| 3. Licence check and demo names | Sonnet | none | One CI step and a list of renamed sample merchants. |
| 4. Delete my own account | Opus | Sonnet: write the endpoint tests once the design is in | Deletes data for good, and shared accounts make the rules subtle. |
| 5. Name and store readiness | Sonnet | none | Mostly your checks; the session drafts one policy page. |

## Open questions

None open. Resolved 2026-11-14, all recorded in [`docs/dev/decisions/legal-risk.md`](../docs/dev/decisions/legal-risk.md):

1. ~~**What does the first-login notice say?**~~ The fuller, formal wording, quoted on the decision page, in the README and the notice alike.
2. ~~**Do people already using an instance see the notice after upgrading?**~~ Yes, everyone once, the demo user excepted.
3. ~~**What happens to an account someone shares when they delete themselves?**~~ Deletion is refused until the owner hands over each shared account or removes the sharing.
4. ~~**Where does the privacy policy for the store apps live?**~~ A page in this repo, served by GitHub Pages.

## The plan

**Goal:** every risk the legal review of 2026-11-14 found is closed, written down as accepted, or waiting on a named check of yours.

**Decided 2026-11-14:**
- The plan covers everything the review found, account deletion and contribution terms included.
- The `LICENSE` copyright line stays "WalletWeather Contributors".
- The disclaimer goes in the README and in a notice each user acknowledges once.
- WalletWeather stays self-hosted, with iOS and Android apps in app stores expected later. No public demo is planned.

**Out of scope:** the native apps themselves, a hosted public instance and its terms of service, rewriting git history to change commit email addresses, and the security features already on the roadmap (items 12 to 15: encrypted backups, password reset, two-factor sign-in, login rate limiting). Phase 1 states those gaps honestly; it doesn't build them.

**The review's findings and where each one goes:**

| # | Finding | Level | Closed by |
| --- | --- | --- | --- |
| 1 | No "not financial advice" or accuracy disclaimer | Medium | Phases 1 and 2 |
| 2 | The published image redistributes third-party code (LGPL `psycopg`, a Debian base with GPL parts) with no notices file and no licence check | Medium | Phases 1 and 3 |
| 3 | No security policy, while the README advertises "Encryption at rest" without its limits | Medium | Phase 1 |
| 4 | No privacy note for people who run an instance for others; users can't delete their own account | Low to medium | Phases 1, 4 and 5 |
| 5 | The copyright line names "WalletWeather Contributors" | Low | Accepted as is (decided above) |
| 6 | The name isn't cleared as a trademark | Low | Phase 5 |
| 7 | AI-assisted code may have thin copyright protection; an employment agreement could claim side projects | Low | Phase 5 (your check) |
| 8 | Real brand names in demo data and CSV samples | Low | Phase 3 |
| 9 | No contribution terms | Low | Phase 1 |

### Phase 1: Notices and policies

Documents only: no code, no version bump.

- `README.md`: a "Disclaimer" section saying forecasts are estimates from what the user entered, that the app gives no financial, tax or investment advice, and that it comes with no warranty (pointing at `LICENSE`). The wording was decided on 2026-11-14 and is quoted in [`docs/dev/decisions/legal-risk.md`](../docs/dev/decisions/legal-risk.md).
- `README.md`, Security Notes: say what "Encryption at rest" does and doesn't cover. The key sits in `.env` beside the database, backups are unencrypted, session cookies aren't HTTPS-only, and there's no login rate limit or two-factor sign-in yet, with a pointer to the roadmap items.
- `SECURITY.md`: how to report a hole privately (GitHub's private vulnerability reporting, which you switch on in the repo's settings), which versions get fixes, and what to expect.
- `PRIVACY.md`: what the app stores (emails, names, password hashes, financial entries), that it sends nothing to the project or to third parties (Google only when the operator turns on Google sign-in), and that whoever runs an instance for other people is responsible for their data, with what that means in practice (export, deletion by an admin, backups).
- `THIRD_PARTY_NOTICES.md`: each dependency shipped in the image with its licence, calling out `psycopg` (LGPL-3.0, unmodified, with the libpq and OpenSSL it bundles) and the Debian base image.
- `CONTRIBUTING.md`: contributions are accepted under the MIT licence, with a line asking contributors to say when a change was AI-assisted.
- `CLAUDE.md`: the README's file tree and this file's notes stay in step with the new documents.

**You:** switch on private vulnerability reporting in the repo's Security settings.

**Done when:** the six documents are on `main`, GitHub's community profile shows a security policy and contributing guide, and the README carries the decided disclaimer text.

### Phase 2: First-login notice

Depends on phase 1 (the README carries the same text). The wording, and that existing users see it once, are decided ([`docs/dev/decisions/legal-risk.md`](../docs/dev/decisions/legal-risk.md)).

- A new column on `users` for when the notice was acknowledged (the next schema number at the time), with a migration that leaves it empty for existing users.
- `GET /api/me` reports whether the notice is still owed; a new `POST /api/me/acknowledge-notice` records it.
- Web client: after sign-in, a user who hasn't acknowledged sees the notice ("Important notice", with the button "I understand and agree"), and nothing else until they press it. The demo user never sees it. The same text is reachable later from Settings.
- Tests: the happy path, an unauthenticated call, and a second acknowledgement being harmless.
- App and web versions bump (minor), schema bumps, CHANGELOG entry.

**You:** after the release is deployed, sign in and check that the notice appears once and not again.

**Done when:** tests pass; a new user and an existing user each see the notice once; the demo user doesn't.

### Phase 3: Licence check and demo names

- A test (`apps/server/tests/test_licences.py`), run by the Tests workflow and the local test command alike, reads the licence every installed package declares and fails on a copyleft licence, or no licence, that isn't on a short reviewed list (`psycopg`, and `certifi`, which is MPL-2.0 and comes in with `httpx`; phase 1 found it). As built it needs no new dependency: the plan first named `pip-licenses`, and Python's own package metadata turned out to be enough.
- `CLAUDE.md`'s licensing rule names that check, and names `certifi` beside `psycopg` as a copyleft dependency already in use.
- Demo data (`apps/server/app/demo.py`), the CSV sample the server generates and the import placeholder in the web client use generic merchant names ("Streaming service", "Coffee shop", "Grocery store") in place of real brands.
- App and web versions bump (patch), CHANGELOG entry. The demo fingerprint changes, so a running demo reseeds once.

**Done when:** the Tests workflow passes with the new test, and the test fails when a GPL package is installed; no real brand name is left in demo data or samples.

### Phase 4: Delete my own account

Shared accounts are decided ([`docs/dev/decisions/legal-risk.md`](../docs/dev/decisions/legal-risk.md)).

- `DELETE /api/me`, asking for the current password (or a typed confirmation for a Google-only user), deletes the user and everything only they own, then ends the session.
- A user who is the only owner of accounts that other people can see is refused with a conflict that names those accounts. They make someone else an owner on the Permissions panel (that is the hand-over: the account then stays with that owner) or remove the sharing, then delete.
- `GET /api/me/deletion-check` says what would be deleted, what stays and with whom, and what stands in the way, so Settings can show it before asking.
- Transfers the user made between accounts that both stay are kept, and pass to the account's owner.
- Settings page: a "Delete my account" section that says what will be removed, offers the export first, and asks for the confirmation.
- Tests: the happy path, a wrong password, and the refusal while a shared account is owned.
- `PRIVACY.md` is updated to say users can delete themselves. App and web versions bump (minor), CHANGELOG entry.

**You:** on a throwaway user, export, delete the account and confirm the sign-in no longer works.

**Done when:** tests pass; a deleted user's rows are gone from every table; the shared-account rule behaves as decided.

### Phase 5: Name and store readiness

Waits on your checks; nothing here blocks phases 1 to 4.

- **You:** search the USPTO trademark database for WALLETWEATHER and close variants in classes 9, 36 and 42, and search the App Store and Google Play for the name. The review's web search found no such mark; the nearest were WALLETWEALTH, WALLETNEWS and WALLETFITNESS.
- **You:** check any employment agreement for a clause that claims side projects or work done on your own time.
- The session records both results in this file, and if the name is taken, opens an issue for a rename before any store listing.
- A privacy policy for the store apps is written from `PRIVACY.md` as a page in this repo served by GitHub Pages: what the apps collect (the answer should be nothing beyond what the user's own server stores).
- **You:** switch on GitHub Pages in the repo's settings, so the policy has its public URL.
- The iOS and Android READMEs gain a line each on what the stores will ask for (a privacy policy URL, the data-collection answers).

**Done when:** both checks are recorded here with their dates, and the policy page opens at its GitHub Pages URL.
