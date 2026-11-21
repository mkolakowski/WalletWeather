# Bank sync

Decisions made while planning and building [`Plans/bank-sync.md`](../../../Plans/bank-sync.md) (tracking issue #198).

## 2026-11-16: the provider, backups first, the first slice, matching and the iOS part

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions:** which service brings the transactions in, what a backup does with the bank token while backups aren't encrypted, how big the first release is, how a bank row meets the forecast, and what the iOS app does.

**Options considered:**
- Provider: SimpleFIN Bridge; Plaid with each instance's own keys (both looked at in #163).
- Backups: leave the connection out of backups; encrypted backups first (roadmap item 12); put the token in today's plain backups.
- First slice: connect and Sync now; connect plus a daily sync; everything in one release.
- Forecast: match planned bills automatically; a review list first; land as paid with no matching; decide later.
- iOS: status and Sync now; connecting from the phone too; nothing for now.

**The decision:** SimpleFIN Bridge. Encrypted backups are built first, as the plan's phase 1, and the bank connection only ever goes into the encrypted kind. The first bank release is connect and Sync now; the daily schedule follows. A bank row close in date and amount to a planned bill marks it paid at the real amount, anything else lands as a new paid line, and a wrong match can be undone. The iOS app shows the sync's status and has a Sync now button; connecting stays in the web app.

**Why:** SimpleFIN needs no provider approval, no script from another site and no public address, which Plaid does. The token reads bank transactions, so it shouldn't sit in a file anyone can read. A small first release tries the real bank early.

**What it changes:** roadmap item 12 becomes phase 1 of this plan, and item 29 is built on SimpleFIN only. Plaid is out of scope. The plan's open questions were settled the same day, below.

## 2026-11-16: the plan's eight open questions

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

1. **What unlocks an encrypted backup:** a passphrase typed at export and import; not the server's `ENCRYPTION_KEY`; not a choice of either at each export. Scheduled backups take theirs from `BACKUP_PASSPHRASE` in `.env`.
2. **Whether plain backups stay:** no, backups are encrypted only; not both kinds side by side.
3. **Who may connect a bank:** nobody until an admin switches it on in Admin, off by default; not a `.env` setting; not every user always.
4. **How far back the first sync reaches:** a start date picked per account, defaulting to today; not all 90 days with a preview; not today only.
5. **Pending bank transactions:** wait until posted; not shown as unpaid lines.
6. **How close a match is:** settable per bill, starting at 5 days and 10%; not one fixed rule of 5 days and 10%; not 3 days and the exact amount.
7. **Shared accounts:** only the owner links an account to a bank; not anyone with edit access.
8. **A fresh code:** with two-factor on, connecting and disconnecting each ask for one; not connecting only; not none.

**Why:** a passphrase restores on any server, where the server's key would lose the backups with the `.env`. The admin switch keeps `PRIVACY.md`'s "nothing leaves the server unless the operator chooses". A start date keeps a balance from moving by surprise. Posted-only means a line never changes after it arrives.

**What it changes:** phase 1 drops the plain backup as a choice, which raised the plan's question 9 (the readable "Download my data" copy, old plain files still importing, and the schedule needing `BACKUP_PASSPHRASE`), built on stated assumptions. Phase 4 gains two settings on every bill and a schema version, and phase 5 adds them to the iOS bill editor.

## 2026-11-16: a sync log and matching by hand

**Decided:** 2026-11-16, by Matthew (asked for while the plan was being written). **Status:** accepted.

**The decision:** the account's owner can read a log of each sync (phase 3), and synced lines that matched no bill are kept on an Unmatched list, from which one can be matched by hand to a planned line that isn't paid yet (phase 4).

**What it changes:** phases 3 and 4 are bigger. Both are web only; the iOS app doesn't get them in this plan. How long the log is kept is the plan's open question 10.

## 2026-11-16: what "encrypted only" means for the readable copy, old files and the schedule

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **The readable copy `PRIVACY.md` promises:** a plain "Download my data" JSON stays, labelled as a copy to read and not as a backup, never holding the bank connection; not the same with an admin switch to remove it; not removed.
- **Plain backup files from earlier versions:** still import, with a note that the file wasn't encrypted; not silently; not refused.
- **Scheduled and full-system backups without `BACKUP_PASSPHRASE`:** they don't run and Admin says so; not a passphrase typed by the admin for the full-system one; not a fall back to plain files.

**What it changes:** updating to the phase 1 release stops an instance's scheduled backups until `BACKUP_PASSPHRASE` is added to `.env`, so the changelog entry is marked **Breaking**. `PRIVACY.md`'s promise of a readable copy stays as written.

## 2026-11-16: where bank sync lives, how far back, and a guard on Sync now

**Decided:** 2026-11-16, by Matthew, at the start of phase 2 (#194). **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **Where in Settings:** a "Bank sync" tab of its own, shown only when an admin has switched bank sync on (or the user still has a connection to remove); not under Accounts; not under Your account.
- **How far back a start date may go:** up to 90 days, so the first sync is one request to SimpleFIN; not up to a year (several requests); not today only. Older history still comes in by CSV.
- **A limit in phase 2:** yes, Sync now stops after 20 calls in 24 hours and says when it can run again; not left for phase 3.

**Why:** a tab of its own leaves room for the sync log and the Unmatched list (phases 3 and 4). SimpleFIN Bridge allows 90 days per request and expects about 24 requests a day, and disables a token that asks much more often, so the guard protects a user's connection from the first release.

**What it changes:** phase 3 builds its "wait N minutes" on the same count.

## 2026-11-20: Teller and Plaid next to SimpleFIN

**Decided:** 2026-11-20, by Matthew, while planning [`Plans/bank-providers.md`](../../../Plans/bank-providers.md) (#259). **Status:** accepted. Replaces 2026-11-16's "Plaid is not planned".

**Why it came back:** SimpleFIN Bridge runs on MX, and Matthew's banks wouldn't connect through it. Teller and Plaid reach banks through their own connections.

**The questions and what was chosen** (the first option listed is the one chosen):

- **Providers:** Teller and Plaid, both next to SimpleFIN; not one of them; not Lunch Flow (resells MX and Finicity); not an enterprise aggregator (MX, Yodlee, Akoya, Finicity direct: contracts with minimums).
- **Where connecting happens:** on the provider's page, not inside the web app: Plaid through Hosted Link in a new tab with the server checking back (no webhook, no public address), Teller on one small separate page that alone may load `cdn.teller.io`; not both scripts in the Bank sync tab; not the iPhone app only.
- **Order:** both providers in one phase; not Teller first; not Plaid first.
- **What waits:** connecting from the iPhone; the providers' categories, the bank's balance and the iPhone list of connections are planned as phases.

**Why:** Hosted Link and a separate page answer two of 2026-11-16's objections to Plaid (a script on the app's pages, a public return address). The third, Plaid's approval, is put off by its Trial plan (10 bank logins free), and Teller needs none for up to 100.

**What it changes:** a user can have many bank connections; `PRIVACY.md` gains Teller and Plaid and names the one page that loads Teller's script. Teller's certificate and Plaid's secret must stay on a server, so a standalone phone (#239) stays SimpleFIN-only.

## 2026-11-20: providers' categories, and the bank's balance

**Decided:** 2026-11-20, by Matthew, settling open questions 3 and 4 of [`Plans/bank-providers.md`](../../../Plans/bank-providers.md) (#259). **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **How Teller's and Plaid's categories become yours** (phase 2, #255): a mapping table in Settings → Bank sync, one row per provider category seen so far, a dropdown of your categories pre-filled where the names match, blank for uncategorized; not asking "always put X in Y?" the first time you categorize a line; not making new categories from theirs; not a read-only label with no mapping.
- **Where the bank's balance shows** (phase 3, #256): on the Accounts screen under each linked account's balance; not only in Settings → Bank sync; not both.
- **What a gap does:** shown in amber with an "Adjust to bank" button that adds one correction line for the difference and can be undone; not marked only; not the two numbers with no highlight.

**Why:** a table is set once and is small to build, and pre-filling by name does most of it. The Accounts screen is seen every day, and a one-tap correction line is how a gap usually gets fixed anyway.

**What it changes:** a line that pays a planned bill keeps the bill's category; the comparison counts only lines up to today, against the bank's posted balance.

## 2026-11-20: one switch for all providers, one link per account

**Decided:** 2026-11-20, by Matthew, settling open questions 1 and 2 of [`Plans/bank-providers.md`](../../../Plans/bank-providers.md) (#259). **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **How an admin controls the providers:** the existing Admin → Bank sync switch covers all three, and Teller or Plaid is offered only once its keys are in `.env`; not a switch per provider; not one switch with a list of allowed providers.
- **The same bank account through two connections:** each of your accounts links to one bank account across all connections, and a second link is refused with a message naming the connection that has it; not both feeding one account with duplicates skipped; not moving the link to the new connection.

**Why:** keys in `.env` already decide whether email alerts can be offered, so nothing new is needed in Admin. One link per account means no line can come in twice, and skipping by date and amount could drop a real repeat charge.

## 2026-11-21: when Teller's balance is asked for

**Decided:** 2026-11-21, by Claude while building phase 3 ([#256](https://github.com/mkolakowski/WalletWeather/issues/256)), which left "decide when to ask" open because Teller bills the balance call in production. **Status:** accepted unless Matthew says otherwise.

**What was chosen:** Teller's balance is asked for at a linked account's first sync (and when it's made from a bank account), when a sync brings in a line it hasn't seen, and when the kept balance is a week old; not on every sync; not only on a schedule.

**Why:** a posted balance only moves when a line posts, so a sync with nothing new can't have changed it and a billed call would buy nothing, while asking whenever a new line lands keeps the balance and the lines in step (a balance read before a line lands would show a false gap). The week is a backstop for a bank that reverses or edits a line without a new one. SimpleFIN and Plaid send the balance with every sync at no extra cost, so they keep it every time, and a provider that sends none clears the old one rather than leave a balance that no longer matches the lines.

**What it changes:** at most about one billed Teller call per account per day, and none on quiet days or repeated Sync now. The bank's balance on the Accounts screen carries the time it was read.

## 2026-11-21: connecting a bank from the iPhone

**Decided:** 2026-11-21, by Matthew, starting phase 5 of [`Plans/bank-providers.md`](../../../Plans/bank-providers.md) ([#258](https://github.com/mkolakowski/WalletWeather/issues/258)), which also lifts the 2026-11-20 call that it waits. **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **How the phone hands the result back:** the app opens a server page in the system sign-in sheet, which shares Safari's sign-in; the page asks the two-factor code, runs Teller or Plaid, and sends the sheet to a `walletweather://` address when done. Not letting the phone's API token start and finish a connection.
- **Which providers:** Teller and Plaid, whichever the server has keys for; SimpleFIN stays in the web app (it means pasting a setup token).
- **Where a new connection's accounts are matched:** in the web app for now; not on the page in the sheet; not a new screen in the app.
- **Plaid in the sheet:** without `is_mobile_app`, so no Universal Link, Apple app-site file or Plaid dashboard entry; a bank that would hand off to its own app shows its web sign-in instead. Not setting up a Universal Link.

**Why:** connecting stays browser-only with a fresh two-factor code, as security check #179 keeps it, so no API change is needed and the phone never holds what connects a bank. Plaid's Hosted Link can send the sheet back to any address when it finishes, without registering it, so the server's own page can check the result under the same sign-in and hand the app only "done" and the connection's number.

**What it changes:** the server gains one page (`/app-connect-bank`) and Plaid is told that page's address for a connection started from the phone; the app gains a Connect a bank button in Settings → Bank sync.


## 2026-11-21: who may connect, and the sync kept with the account

**Decided:** 2026-11-21, by Matthew, while planning [`Plans/sync-access.md`](../../../Plans/sync-access.md), from the question "is there a way to move the syncing out of the admin, by the admin allowing users to setup syncs as permissions and the sync living with the acct vs the user". **Status:** accepted; replaces question 3 of 2026-11-16 (one Admin switch for everyone) and the first part of 2026-11-20 (one switch for all providers); question 7 (only the owner links) is kept.

**The questions and what was chosen** (the first option listed is the one chosen):

- **Who may set up a sync:** an admin ticks each person for each provider (SimpleFIN, Teller, Plaid); not a tick per person for all providers; not ticks with no global switch.
- **The Admin → Bank sync switch:** kept as an off-for-everyone kill switch, with the ticks deciding while it's on; not removed.
- **On upgrade:** whoever has a connection gets that provider ticked, everyone else starts unticked, and admins can always connect; not everyone ticked for everything; not nobody but admins.
- **What "the sync lives with the account" means:** the bank login stays the person's who connected it, but each account's link, status, sync log, Unmatched list and Sync now belong to the account, and the connection passes to another owner when its person leaves; not the connection itself belonging to the accounts (any owner reconnecting or disconnecting it); not kept per person.
- **Who sees and runs a shared account's sync:** owners and editors (status, log, Sync now, matching by hand); read-only people see the synced lines only; not owners only; not everyone with read access.
- **Who links or unlinks an account:** owners only, as before; not editors too.
- **Email alerts:** bank sync first, then email alerts on the same model in a later phase of the same plan; not both together; not bank sync only.
- **What waits for after the first release:** the iPhone (phase 4) and email alerts (phase 5); phases 1 to 3 go out together.

**Why:** a per-provider tick lets an admin keep a paid provider (Plaid's logins, Teller's billed calls) to a few people while still letting others use SimpleFIN, and the kill switch keeps one place to stop everything, which `PRIVACY.md`'s "nothing leaves the server unless the operator chooses" relies on. Keeping the login with its person means nobody else can use or change someone's bank credentials, while the account holding its sync means everyone who keeps the account up to date can see why a line came in and fix a match.

## 2026-11-21: sync access, open questions 1 to 4

**Decided:** 2026-11-21, by Matthew, settling open questions 1 to 4 of [`Plans/sync-access.md`](../../../Plans/sync-access.md) (#269), each as the plan had assumed. **Status:** accepted.

**The questions and what was chosen** (the first option listed is the one chosen):

- **Unticking a person for a provider they have a connection of** (phase 1): the connection is paused and kept, ticking again carries on, and their Settings says an admin has paused it; not left syncing (unticking only stopping new connections); not disconnected.
- **What an editor is told about whose login feeds a shared account** (phase 2): "Synced from <name>'s <provider> connection · <bank account name>"; not the provider only; not just "Bank sync on".
- **Who gets a connection when its person leaves and its linked accounts have different other owners** (phase 3): the other owner of the first-linked account gets the whole connection, the other accounts keep syncing and their owners can unlink, and the delete screens name who gets it; not chosen by the person deleting; not split into a copy per owner.
- **A mailbox when its person leaves** (phase 5): disconnected with them, lines already in kept; not passed on like a bank connection.

**Why:** pausing matches what the kill switch already does and loses nothing if the untick was a mistake. Naming the person and provider tells an editor who to ask when a sync breaks, without showing anything about the login. One whole connection avoids two copies of a bank token tripping a provider's limits, and a mailbox is someone's own email, which nobody else should keep reading.
