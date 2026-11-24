# Bank alert emails: transactions read from the bank's alert emails

Tracking issue: #212

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Connect Microsoft 365 and Check now | Server, Web | #206 | Released in 1.73.0 (2026-11-17), ahead of the one-release plan; waiting for your try with a real mailbox |
| 2. The mailbox checked by itself | Server, Web | #207 | Released in 1.74.0 (2026-11-17); closed 2026-11-17 |
| 3. Gmail and other mailboxes | Server, Web | #208 | Not started |
| 4. Alerts matched to bills, and the first release | Server, Web | #209 | Released in 1.75.0 (2026-11-17), closed 2026-11-17; it isn't the first release (phase 1 shipped in 1.73.0) |
| 5. Alerts joined to bank sync rows | Server, Web | #210 | Built 2026-11-22 for 1.94.0 (schema 37, web 1.105.0); released in v1.97.0 (2026-11-23) |
| 6. Status and Check now in the iOS app | iOS | #211 | Built in iOS 0.69.0, 2026-11-24; your try from TestFlight left |


Phase 6 built 2026-11-24 in iOS 0.69.0 (no server change: `GET /api/mail/status` and `POST /api/mail/check` were already there). Placed and worded that day at your call: an Email alerts card on Settings → Bank sync under the bank cards (More is Settings now), in plain status lines, and the Bank sync row names the mailbox's trouble when the banks have none. Verified: 12 new Kit tests (`MailAlertsTests`: the status as the server sends it, each state in words, the row's value, Check now's request and refusal, an older server, the demo's sample, none for the household on this iPhone) in a full `swift test` of 532 that passed; the app builds for the simulator. Not yet: simulator pictures (PortSSD unplugged) and Check now from your phone.
Phase 5 built 2026-11-22 for 1.94.0 (schema 37, web 1.105.0), not released yet: API tests in `apps/server/tests/test_mail_alerts_join.py` (17 tests against the stand-in SimpleFIN and Microsoft: an exact join, a tip a few days later, your edits kept, the account's own settings and their limits, a lower amount or an earlier row or the other direction not joined, the nearest winning and a tie left, undo bringing both back and not joined again, the CSV cases, never posted, a bill paid once at the bank's amount, an alert after its bank row, an un-match keeping a joined line whole, join by hand and its checks, another user's and a read-only share's lines, signed out), the screens checked in a headless browser with the API stubbed at 1100 and 390 px, no page errors. Built on open questions 7 and 8 and the three design calls of 2026-11-22 (the comment on #210). Set in building, not asked: the bank row may come 0 to 7 days after the alert, never before, and its amount may be the alert's or higher, never lower; the join is checked against the alert's own amount and date, kept on each alert line from this version (older alert lines use their values as they are); an alert that lands after its bank row is joined to it the same way (so alerts kept aside before as "bank_linked" don't double when they land), and a tie either way pays no bill and waits on the Unmatched list; a CSV line is still claimed by an exactly equal bank row before any join, and an alert line is never claimed as a CSV row; undo puts the bank row back off the Unmatched list (as un-match does), or as it was for a join by hand; "never posted" counts the 10 days from the alert to the last day bank sync read, and only for alerts on or after the account's bank start date; on the Unmatched list it has Delete and Keep (Keep is Leave as its own line); a joined line that pays no bill shows the Unmatched pill as any bank line does, and one that pays a bill the Bank sync pill; the join settings are the owner's, 0 to 31 days and 0 to 100% as a bill's; the sync log has a Joined column; the Unmatched list keeps its shape (the shared core's answer key pins it) and a new `GET /api/accounts/{id}/bank-unmatched/joins` says which lines can be joined, are joined, or never posted. A joined line keeps the bank row in `join_enc` and the alert's values in `alert_enc` (both encrypted), so undo restores both lines and backups carry them.

Phase 4 built 2026-11-17 in 1.75.0 (schema 30, web 1.89.0), released in 1.75.0 the same day: API tests in `apps/server/tests/test_mail_alerts_matching.py` (bank sync phase 4's matcher called as an alert lands, the Unmatched list and its match by hand, leave and un-match endpoints extended to alert lines), the screens checked in a headless browser. Built on what the plan said (the bill's own settings; the "Email alert" mark and the list in Settings → Email alerts follow bank sync's pattern, not asked). An alert's matched line reuses bank sync's match columns and says where it came from by `mail_ref`.

Phase 2 built 2026-11-17 in 1.74.0 (schema 29, web 1.88.0), released in 1.74.0: API tests in `apps/server/tests/test_mail_alerts_daily.py` (the scheduler called with chosen times), the screens checked in a headless browser. Built on open question 5's answer (5, 15 or 60 minutes per user) and its assumption for the log's retention (as the audit log). The log is **one per mailbox** in Settings, not per account as first planned (your call: an alert with no account yet, or one that failed the sender check, belongs to no account); a failed check is tried again at the user's interval, and the scheduler looks every minute (both set in building).

Phase 1 built 2026-11-16 in 1.72.0 (schema 27, web 1.86.0) and released 2026-11-17 in 1.73.0 together with bank sync phase 4, at your say, ahead of the plan's one release for phases 1 to 4 (it ships switched off, and its release notes and guide say it hasn't been tried with a real mailbox): API tests in `apps/server/tests/test_mail_alerts.py` against a stand-in Microsoft (34 tests, the reader on alerts worded different ways included), and the screens driven in a headless browser against the same stand-in. Endpoints were checked against Microsoft's device code and Graph list-messages pages that day. The teaching screen's "select text, then pick" was your call; the 30-day start date, 50 lines and 100 mails per check and 15 seconds between checks were set in building ([decision](../docs/dev/decisions/bank-alert-emails.md)). Not yet tried against a real Microsoft mailbox.

Planned 2026-11-16. All nine open questions settled the same day. Four calls were made that day while planning ([decision](../docs/dev/decisions/bank-alert-emails.md)): the app is taught each sender's alert from a sample; an account can have alerts and bank sync together, joined; Gmail gets both an app-password route and a Google sign-in route; phases 1 to 4 go out as one release.

Sessions: may span — phase 1 needs your own Microsoft app registration, phase 4 waits for bank sync phase 4 (#196), and phases 4 to 6 each end with a release and your try on your own instance.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Connect Microsoft 365 and Check now | Server, Web | Opus | Sonnet: tests against a stand-in Microsoft; Sonnet: the teaching screen once its endpoints exist | A second service the server calls, a stored secret that can read a mailbox, a schema version, and a reader that takes text written by strangers. |
| 2. The mailbox checked by itself | Server, Web | Sonnet | none | Follows the bank sync scheduler, status and log in `main.py`. |
| 3. Gmail and other mailboxes | Server, Web | Opus | Sonnet: tests against a stand-in IMAP server and a stand-in Gmail | Two more ways in, one of them an address the user types (so a guard on where the server may connect), and Google's terms to check first. |
| 4. Alerts matched to bills, and the first release | Server, Web | Sonnet | Sonnet: tests for the matching cases | Reuses the matcher and the Unmatched list bank sync phase 4 builds; suggest Opus if they turn out not to fit. |
| 5. Alerts joined to bank sync rows | Server, Web | Opus | Sonnet: tests for the joining cases | A wrong join hides a real transaction or doubles one, and a tip changes the amount between the alert and the posted row. |
| 6. Status and Check now in the iOS app | iOS | Sonnet | none | One row and one button on an existing screen, against endpoints that exist. |

## Open questions

All nine were settled on 2026-11-16. `/resolve-open-questions bank-alert-emails` works through them.

1. ~~**How you sign in to Microsoft.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): both ways. A Connect button that goes to Microsoft and comes back when the instance is on `https://`; a code typed at microsoft.com/devicelogin otherwise.
2. ~~**Who may connect a mailbox.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): as bank sync, with a switch of its own in Admin, off by default; then any user connects their own mailbox; demo users can't; a browser session only; a fresh code with two-factor on.
3. ~~**Which mail the server reads, and what it keeps.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): one folder you name (Inbox by default), only mail from taught senders. Kept, encrypted: the values read, the sample each sender was taught from, and alerts it couldn't read (removed with the log). Other mail is never stored and the mailbox is never changed.
4. ~~**What an alert becomes.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): a paid line dated when the alert says, marked "from an alert".
5. ~~**How often the mailbox is checked, and how long the log is kept.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): each user picks 5, 15 or 60 minutes in Settings. Not asked, so built on these unless you say otherwise: it starts at 5 minutes, and the log is kept as long as the audit log (`AUDIT_RETENTION_DAYS`), as bank sync's is.
6. ~~**A mail from the bank's address that fails the sender check.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): skipped, counted in the log and shown with the couldn't-read alerts as "may not be from your bank"; never made into a line, and no button to add it anyway.
7. ~~**How close an alert and a bank row must be to be joined.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): settable per account, how many days after the alert and how much higher the amount, starting at 7 days and 30%. Always the same account and direction; the nearest date wins and a tie is left for you. An alert no bank row has met after 10 days is flagged "never posted" for you to delete or keep; nothing is removed by itself.
8. ~~**Whose values win when they're joined.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): the bank's amount and date, the alert's merchant name, and your own edits to the line over both.
9. ~~**Work or school Microsoft 365 accounts.**~~ Decided 2026-11-16 ([decision](../docs/dev/decisions/bank-alert-emails.md)): personal (Outlook.com) and work or school accounts are both allowed; a work tenant may want its admin to approve the app, and the guide says so. `MS_TENANT` can narrow it.

## The plan

**Goal:** you switch on "alert me for every transaction" at your bank, and WalletWeather reads those emails from your mailbox: each becomes a line minutes after the purchase, tagged by the auto-tag rules, marking the planned bill it pays. Microsoft 365 first, then Gmail and other mailboxes. It is roadmap item 30.

**Decided 2026-11-16** (asked while planning; [decision page](../docs/dev/decisions/bank-alert-emails.md)):

- **Taught per sender.** A built-in reader guesses the amount, merchant, date and the card's last four digits from any alert; you check its guess once on a sample from each bank and correct it. No reader per bank shipped with the app.
- **Alerts and bank sync on the same account, joined.** The alert adds the line straight away; when the bank's posted row arrives it joins that line and corrects the amount instead of adding a second one (phase 5), by settings each account has. Until phase 5 is out, an account takes one or the other.
- **Gmail both ways:** an app password over IMAP (which also reads other IMAP mailboxes), and "Connect Gmail" with Google sign-in and read-only access.
- **One first release.** Phases 1 to 4 (Microsoft 365, the schedule, Gmail, bill matching) are built and pushed one by one, switched off by default, and go out together in one release. If you want to try Microsoft 365 before that, a one-off test image can be built by hand after phase 1.
- **Done means** API tests in CI, then a release and your try on your own instance, as bank sync did.

**Out of scope:** sending email (roadmap item 6's notifications); a mailbox the server runs itself or an address mail is delivered to (needs the instance on the public internet); reading attachments or statements; reading mail with a language model or any outside service; push from Microsoft or Google the moment mail arrives (needs a public address; the server asks every few minutes instead); connecting a mailbox from the iOS app; more than one mailbox per user; text-message alerts.

**What's there today:**

- Bank sync (`Plans/bank-sync.md`) lands SimpleFIN rows as paid lines through the CSV import's path, with the bank's id on `transactions`, a per-user lock, a scheduler thread, a status endpoint, a per-account log and an admin switch (`bank_sync_enabled` and the `/api/bank` routes in `apps/server/app/main.py`). Alerts follow each of those patterns.
- Bank sync phase 4 (#196, not built yet) adds the matcher that marks a planned bill paid, the Unmatched list and matching by hand. Phase 4 here reuses them.
- Stored secrets are encrypted with `ENCRYPTION_KEY` (`encrypt_str` in `apps/server/app/db.py`); backups are encrypted and carry the bank connection; "Download my data" never does.
- `authlib` and `httpx` are pinned already (Google sign-in, SimpleFIN), and Python's own `imaplib`, `email` and `html.parser` read IMAP and mail. No new library is expected.
- Google sign-in already has a Google Cloud project per instance (`GOOGLE_CLIENT_ID`), which the Gmail sign-in route can extend.
- `PRIVACY.md` "What leaves the server" lists Google sign-in and SimpleFIN only.

**How the mailboxes work** (from a first look on 2026-11-16; each to be checked against the provider's own pages at the start of its phase):

- **Microsoft 365:** you register an app of your own in Microsoft's Entra portal (free, done in a browser) and give WalletWeather its id, as `GOOGLE_CLIENT_ID` works. You sign in once and allow read-only mail access (`Mail.Read`); the server keeps a renewable sign-in and asks Microsoft Graph for new mail in one folder. The sign-in renews each time it's used and lapses after about 90 days unused. Microsoft no longer takes a plain password over IMAP, which is why this route is its own.
- **Gmail by app password:** with 2-Step Verification on, Google gives a 16-character app password that reads the mailbox over IMAP and doesn't lapse. It's Google's own feature for this, so its terms allow it. It can read the whole mailbox.
- **Gmail by Google sign-in:** Google counts read-only mail access as a "restricted" permission. A published app needs Google's review and a yearly paid security assessment; an app for personal use with fewer than 100 users is exempt, which is what a self-hosted instance with its own Google Cloud project is. The catches: while the project is in "Testing" the sign-in lapses every 7 days; set to "In production" without review it lasts, behind an "unverified app" warning screen. Phase 3 confirms this against Google's own policy pages before building; if they say otherwise, this route is dropped and the plan says so.

**What guards it:** an email is text written by a stranger, and the mailbox sign-in is the most powerful secret the app would hold.

- Only taught senders, only mail that passed the mailbox provider's sender check, and never more lines per check than a cap.
- Mail is read as text: HTML is stripped, no link is followed, no image is fetched, nothing in it is run, and long mail is cut off.
- What a sender is taught is stored as the text around each value, never as a pattern you or anyone writes, so a crafted one can't hang the server.
- The server connects only to Microsoft's and Google's named addresses, and for IMAP only to hosts on an allowed list in `.env`.
- Read-only access everywhere it can be asked for; the guide recommends a mail rule that files bank alerts into their own folder, so that folder is all the server reads.

### Phase 1: Connect Microsoft 365 and Check now

**Apps:** Server and Web. No iOS work.

- **Settings in `.env`:** `MS_CLIENT_ID` (and `MS_TENANT`, defaulting to any account), and `MS_CLIENT_SECRET` for the Connect button only, added to `.env.example` with where each value comes from. Without `MS_CLIENT_ID` the Microsoft route isn't offered.
- **Admin:** a switch that allows email alerts on the instance, off by default; the users list shows who has a mailbox connected.
- **Connect, in Settings → Email alerts:** sign in to Microsoft either way (decided 2026-11-16): a Connect button that goes to Microsoft and comes back, offered when the instance is on `https://` and `MS_CLIENT_SECRET` is set, or a short code typed at microsoft.com/devicelogin, which works on any address. Then pick the folder, and the tab shows the mailbox's address and when it was last checked. Browser session only; demo users can't; a fresh code with two-factor on.
- **Schema:** a table for a user's mailbox connection (the provider, the sign-in encrypted with `ENCRYPTION_KEY`, the folder, the last check and its result), a table of taught senders (the address, what each kind of alert from it looks like, which account each card's last four digits belongs to) and on `transactions` the alert's own id, so a mail is never read into two lines.
- **Teach a sender:** the tab lists recent mail in the folder (sender, subject and date only); you pick one of your bank's alerts; the reader shows what it took as the amount, the merchant, the date and the card's last four digits; you correct any of them by marking the right text, say whether it's money out or in, and pick the account that card belongs to. A sender can be taught more than one kind of alert (a purchase, a deposit); kinds it wasn't taught are ignored.
- **Check now:** asks Microsoft for mail since the last check, takes the mail from taught senders that passed the sender check, reads each, and lands it as a paid line marked "from an alert" through the path bank sync uses: duplicates skipped by the alert's id, the auto-tag rules run, and the button says how many came in.
- **Couldn't read:** an alert from a taught sender that the reader couldn't make sense of goes on a list, where you can teach from it or dismiss it.
- **With bank sync:** an account linked to bank sync can't take alerts yet, and the screen says that arrives with phase 5.
- **Disconnect:** removes the stored sign-in and the taught senders; lines already brought in stay. Deleting a user removes their connection. The screen says how to remove the app's access at Microsoft too.
- **Audit log:** mailbox connected, disconnected, check run (how many lines), check failed, sender taught.
- **Backups:** the connection and the taught senders go into encrypted backups, never into "Download my data".
- **Documents:** `PRIVACY.md` "What leaves the server" and `docs/privacy.md` (the server calls Microsoft; what Microsoft sees; what's stored of your mail), `SECURITY.md` "Known limits" (what the stored sign-in can read, and why a folder of its own is recommended), a setup guide on the project site (`docs/email-alerts.md`: registering the Microsoft app, the mail rule, teaching a sender), the README, `.env.example`, `ROADMAP.md` item 30, the changelog.
- **Security checks:** each new route gets its sign-in dependency (and `current_admin` for the switch) in `test_security_guards.py`.
- **Tests,** against a stand-in Microsoft (no real network): connect and list folders; the reader on a set of sample alerts in different wordings, plain text and HTML; teaching and correcting; a check lands lines once and a second check adds none; an untaught sender is ignored; a mail that failed the sender check makes no line; a mail with a script, a link and a huge body is read as text and cut off; the per-check cap; the tag rules run; disconnect removes the secret; a token or a demo user can't connect; with the admin switch off everything is refused; Microsoft being down or the sign-in lapsed gives a plain error and changes nothing; another user's connection can't be read.

**You:** register an app in Microsoft's Entra portal by the guide (in a browser) and put its id in your server's `.env`; switch on alerts for every transaction at one bank; make the mail rule. Nothing to try on your instance yet unless you ask for the one-off test image.

**Done when:** the tests pass in CI and the work is pushed, switched off by default. Not released by itself.

### Phase 2: The mailbox checked by itself

**Apps:** Server and Web. No iOS work.

- A background check, like bank sync's, that looks at each connected mailbox as often as its user has chosen in Settings (5, 15 or 60 minutes, decided 2026-11-16; it starts at 5), never at the same moment as a Check now for the same user.
- Settings shows when the last check ran and what it brought in and, when it failed, why and what to do (a lapsed sign-in asks you to connect again). The Dashboard shows a small warning when checks have been failing for more than a day or alerts are waiting on the couldn't-read list.
- **A log, for the mailbox's owner** (decided 2026-11-17: one per mailbox, not per account; heading and the sentences below read "per account" in the first draft): per account, each check that brought something in or failed: when, by schedule or Check now, how many lines came in, were skipped as already there, couldn't be read or failed the sender check; opening one shows the lines. Checks that found nothing aren't listed.
- A status endpoint an API token may read, and Check now allowed to a token with write access, ready for phase 6.
- Tests: the scheduler checks a due mailbox and skips one checked just now; each user's own interval is kept, and a value that isn't 5, 15 or 60 is refused; a failure is recorded and doesn't stop other users' checks; a lapsed sign-in stops the schedule until reconnected; the status endpoint's shape; the log's shape, and that someone the account is shared with can't read it; a read-only token can't Check now.

**You:** nothing yet.

**Done when:** the tests pass in CI and the work is pushed. Not released by itself.

### Phase 3: Gmail and other mailboxes

**Apps:** Server and Web. No iOS work.

- **First, the terms:** read Google's own pages on app passwords, restricted permissions and the personal-use exemption, and record what they say on the decision page. A route they don't allow is dropped here, with a note in the plan.
- **IMAP with an app password:** in Settings → Email alerts, choose "Gmail or another mailbox", give the address and the app password (and, for a mailbox that isn't Gmail, its server name). The password is stored encrypted. The server connects over TLS only, opens the folder read-only so nothing is marked read, and only to hosts on `IMAP_HOSTS` in `.env` (defaulting to Gmail's; the guide says how to add another).
- **Gmail with Google sign-in:** a "Connect Gmail" button asking for read-only mail access, offered only when `GMAIL_API_ENABLED` is set and Google sign-in is configured. The guide covers adding the permission to your Google Cloud project, "Testing" against "In production", and the warning screen. A lapsed sign-in asks you to connect again, as with Microsoft.
- Teaching, Check now, the schedule, the log and the couldn't-read list work the same on every kind of mailbox; the sender check reads the result each provider stamps on the mail.
- **Documents:** the setup guide gains Gmail and IMAP sections; `PRIVACY.md`, `docs/privacy.md`, `SECURITY.md`, `.env.example`, the changelog.
- **Tests,** against a stand-in IMAP server and a stand-in Gmail: connect each way; a wrong password is a plain error; a host not on the list is refused before any connection; a server without TLS is refused; a check lands lines once; the mailbox is unchanged afterwards; the Gmail route is refused when not switched on; a lapsed Google sign-in is recorded and stops the schedule.

**You:** make a Gmail app password (needs 2-Step Verification), and if you want the sign-in route too, add the permission to your Google Cloud project by the guide.

**Done when:** the tests pass in CI and the work is pushed. Not released by itself.

### Phase 4: Alerts matched to bills, and the first release

**Apps:** Server and Web. The iOS app shows the result with no change of its own.

- When an alert lands, the matcher from bank sync phase 4 (#196) looks for the planned bill or income line it pays, by that bill's own days and amount settings; a match marks the bill paid at the alert's date and amount instead of adding a line, says it was matched by an alert, and can be un-matched.
- Unmatched alerts land as paid lines and join the account's **Unmatched** list, where matching by hand and "Leave as its own line" work as they do for bank rows.
- The log (phase 2) gains how many alerts matched and how many didn't.
- Tests: an alert matches a bill; two candidates are left unmatched; un-match and no re-match; match by hand from the Unmatched list; a transfer leg isn't matched.
- **The release:** phases 1 to 4 go out as one version, after `/cve-scan` if anything was bumped.

**You:** update your instance, switch email alerts on in Admin, connect your Microsoft 365 mailbox, teach your bank's alert, press Check now, then leave it for a few days: buy something and watch the line arrive, and see a bill marked paid by an alert. Connect Gmail the same way if you use it.

**Done when:** the tests pass in CI, the version is released, alerts have arrived by themselves on your instance from a Microsoft 365 mailbox for three days, and one bill has been marked paid by an alert.

**Depends on:** phases 1 to 3, and bank sync phase 4 (#196) built.

### Phase 5: Alerts joined to bank sync rows

**Apps:** Server and Web.

- An account may now have both alerts and bank sync. When a bank row lands, the server first looks for an alert's line it is the posted version of: the same account and direction, within that account's own settings (decided 2026-11-16), the nearest date winning and a tie left for you. A join keeps one line, with the bank's id added, the bank's amount and date, the alert's merchant name, your own edits over both, and a mark that says it came by alert and was confirmed by the bank.
- **Per account:** two join settings on each account, how many days after the alert the bank's row may come and how much higher its amount may be (a tip), starting at 7 days and 30%, in the web client's account editor and on the accounts endpoint. A schema version adds them.
- A bill the alert had already marked paid stays paid, at the bank's amount.
- A join can be undone: the bank row becomes its own line and that pair isn't joined again. An alert's line and a bank row can be joined by hand from the Unmatched list.
- An alert no bank row has met after 10 days is flagged "never posted" on the Unmatched list (a hold that dropped off, a declined charge), for you to delete or keep.
- The logs say how many rows were joined.
- Tests: an exact join; a tip (the bank's amount higher); an account's own settings are used, and their limits checked; the bank row a few days later; two candidates (left for you); a join undone and not remade; a row already brought in by CSV; an alert that never posts; a bill paid by the alert stays paid once; another user's lines can't be joined.

**You:** on an account with both, watch a couple of weeks: every purchase once, restaurant tips corrected, nothing doubled.

**Done when:** the tests pass in CI, the version is released, and two weeks on your instance have shown no doubled and no missing lines on an account with both.

**Depends on:** phase 4 released.

### Phase 6: Status and Check now in the iOS app

**Apps:** iOS. No server or web work expected (the endpoints come from phase 2).

- An "Email alerts" row under More: connected or not, the last check, how many alerts are waiting on the couldn't-read list, and any error in plain words. A Check now button, hidden for a read-only token.
- When no mailbox is connected, the row says connecting is done in the web app. Demo mode shows a sample status.
- Tests: `swift test` in `apps/ios/WalletWeatherKit` on samples recorded from the server; a simulator look through the shared simulator lock.

**You:** install the build on your phone, open More, and press Check now.

**Done when:** `swift test` passes, the simulator screenshots look right, the iOS version is released, and Check now has worked from your phone.

**Depends on:** phase 4 released.
