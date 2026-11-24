# Legal risk: the disclaimer, the notice, account deletion and the policy URL

Decisions made while planning [`Plans/legal-risk.md`](../../../Plans/legal-risk.md) (tracking issue #50), after the legal review of 2026-11-14.

## 2026-11-14: scope of the plan

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

- **The plan covers everything the review found.** The options were documents only, documents plus the in-app and CI work, or everything including self-serve account deletion and contribution terms. Everything was chosen.
- ~~**The `LICENSE` copyright line stays "WalletWeather Contributors".**~~ *Superseded 2026-11-18: the line now names Matthew Kolakowski (see below).* The options were naming Matthew Kolakowski, naming him and the contributors, or leaving it. It was left as is: common in open source, and accepted as slightly vague about who holds the copyright.
- **Distribution:** self-hosted, with iOS and Android apps in app stores expected later. No public demo instance is planned, so no hosted terms of service are needed.

## 2026-11-14: the disclaimer's wording

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** the app forecasts balances and said nowhere that forecasts are estimates and not advice. What should the disclaimer say, and where?

**Options considered:**
- README only: people using an instance someone else runs would never see it.
- README and a quiet line in the app: easy to miss.
- README and a notice each user acknowledges once: chosen. It costs a stored flag (a schema change) and one interruption per user.
- Wording, plain and short (three sentences): quicker to read, but it leaves out who is responsible for decisions.
- Wording, fuller and more formal: chosen.

**The decision:** this text, in the README's Disclaimer section and in the first-login notice, under the heading "Important notice" with the button "I understand and agree":

> WalletWeather is a planning tool. Its forecasts are estimates calculated from data you enter and may be inaccurate or incomplete.
>
> WalletWeather does not provide financial, tax, legal or investment advice. You are solely responsible for decisions you make using it.
>
> The software is provided "as is", without warranty of any kind, and its authors accept no liability for losses arising from its use. See the MIT licence.

**What it changes:** `README.md` (phase 1, #45) and the first-login notice (phase 2, #46). A change to the wording changes both.

## 2026-11-14: existing users see the notice once

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** when an instance is upgraded to the version with the notice, do people already using it see it?

**Options considered:**
- New users only, with existing users marked as acknowledged by the upgrade: no interruption, but they never see the disclaimer in the app.
- Everyone once: chosen.

**The decision:** every user acknowledges the notice once at their next sign-in. The demo user never sees it.

**What it changes:** phase 2 (#46): the migration leaves the acknowledgement empty for existing users.

## 2026-11-14: deleting your own user is refused while you own shared accounts

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** when someone deletes their own user, what happens to accounts they own that other people have edit or read access to?

**Options considered:**
- Delete the accounts and everyone's access with them, after a warning: simpler, but other people lose what they could see.
- Hand ownership to the person with the highest access: nobody is blocked, but someone becomes an owner without being asked, and it's the most to build.
- Refuse until the owner sorts it out: chosen.

**The decision:** deletion stops and lists the shared accounts in the way. The owner hands each to someone else or removes the sharing first, then deletes. Nobody loses data by surprise.

**What it changes:** phase 4 (#48): `DELETE /api/me` returns a conflict naming the accounts, and the Settings section shows them.

## 2026-11-14: the store privacy policy is served by GitHub Pages from this repo

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** app stores need a public URL for a privacy policy. Where does it live?

**Options considered:**
- Decide when the apps are close to listing: nothing to set up now, but the question stays open.
- A page on a domain of Matthew's: looks most official, needs hosting.
- GitHub Pages from this repo: chosen. Free, versioned with the code.

**The decision:** the policy is a page in this repo, served by GitHub Pages (expected at `https://mkolakowski.github.io/WalletWeather/`). Pages is switched on in the repo's settings, a step for Matthew.

**What it changes:** phase 5 (#49): the policy is written as a Pages page, not only a draft.

## 2026-11-14: an admin deleting a user follows the same rule

**Decided:** 2026-11-14, by Matthew. **Status:** accepted.

**The question:** building self-deletion showed that an admin deleting a user from the Admin panel silently deleted every account that user had created, shared and co-owned ones included (#57). Accounts with another owner are now always kept. What should happen when the user is the only owner of an account other people can see?

**Options considered:**
- Warn the admin with the list, then let them go ahead: quick for cleaning up after someone who has left, but other people lose those accounts.
- Hand each account to the person with the highest access: nothing blocks, but someone becomes an owner without being asked.
- Refuse, as self-deletion does: chosen.

**The decision:** `DELETE /api/admin/users/{uid}` is refused with a conflict that names the accounts. The admin makes someone else an owner of each, or removes the other people's access, under the Admin panel's All permissions, then deletes the user. One rule for both ways of deleting a user.

**What it changes:** app 1.24.1 and web 1.48.1: the admin endpoint and the Admin panel's delete button (#57).

## 2026-11-18: the copyright line names Matthew Kolakowski

**Decided:** 2026-11-18, by Matthew. **Status:** accepted. Replaces the copyright-line part of "scope of the plan" above.

**The question:** Matthew asked whether the licence lets him sell copies of the app. MIT does, and as the copyright holder he isn't bound by it anyway, but the line "WalletWeather Contributors" didn't say who holds the copyright.

**Options considered:**
- "Matthew Kolakowski": chosen. Nearly every commit is his, and it's the clearest basis for selling the app or offering it under other terms later.
- "Matthew Kolakowski and WalletWeather Contributors": covers future pull requests from others, but they keep their own copyright under `CONTRIBUTING.md` either way.
- Keep "WalletWeather Contributors", as decided on 2026-11-14.

**The decision:** `LICENSE` reads `Copyright (c) 2026 Matthew Kolakowski`. The terms stay MIT.

**What it changes:** `LICENSE` only; no app version (#242).

## 2026-11-24: TestFlight opens to external testers before the name check

**Decided:** 2026-11-24, by Matthew (#335). **Status:** accepted.

Builds go to external TestFlight testers from iOS 0.65.0, before the name check in #49 (the USPTO and store search, and the employment-agreement check) is done. Matthew accepted the risk for a small external beta; #49 stays open and still gates any store listing. `apps/ios/Scripts/testflight.sh` now uploads builds external testers can be given by default (`TESTFLIGHT_INTERNAL_ONLY=true` keeps one internal), since a build uploaded as internal-only can never go to them.

**The public link stays out of this repo** for now: not in the README, issues, commits or changelog, until Matthew says otherwise. Waiting for #49, and preparing without switching on, were the other options.

