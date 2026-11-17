# Bank alert emails

Decisions made while planning and building [`Plans/bank-alert-emails.md`](../../../Plans/bank-alert-emails.md) (tracking issue #212).

## 2026-11-16: how alerts are read, alerts with bank sync, the Gmail route and the first release

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions:** how the app learns to read each bank's alert, what happens on an account that has both alerts and bank sync, which way a Gmail mailbox is read, and how big the first release is.

**Options considered:**
- Reading: taught per sender from a sample email; a built-in reader shipped for each named bank; both.
- With bank sync: both on one account, the bank's posted row joined to the alert's line; one source per account; decide later.
- Gmail: IMAP with an app password; the Gmail API with Google sign-in; no Gmail code, a filter forwarding alerts to the Microsoft 365 mailbox.
- First release: connect Microsoft 365 and Check now; that plus the schedule; Microsoft 365, the schedule, bill matching and Gmail at once.

**The decision:** the app is taught each sender's alert from a sample, with a built-in reader making the first guess. An account can have alerts and bank sync together: the alert adds the line, and the bank's row joins it and corrects the amount. Gmail gets both routes, the app password over IMAP and Google sign-in with read-only access. Microsoft 365, the schedule, Gmail and bill matching go out as one first release; joining with bank sync and the iOS part follow.

**Why:** teaching works for any bank and needs no release when a bank rewords its email. Alerts arrive in minutes and bank sync days later, so having both is the point, and joining is what stops a line being doubled. The app password never lapses and reads other IMAP mailboxes too; Google sign-in gives tighter, read-only access for those who want it.

**What it changes:** roadmap item 30. Until the joining phase is out, an account takes alerts or bank sync, not both. The Google sign-in route is confirmed against Google's own policy pages at the start of the Gmail phase and dropped if they don't allow it. The plan's nine open questions each carry the assumption their phase is built on.

**What was found about the terms (2026-11-16, from a first look, not yet from Google's and Microsoft's own pages):** Google's app passwords are its own feature for reading a mailbox over IMAP, with 2-Step Verification on. Read-only Gmail access through Google sign-in is a "restricted" permission: a published app needs Google's review and a yearly security assessment, an app for personal use with fewer than 100 users is exempt, and while a project is in "Testing" its sign-in lapses after 7 days. Microsoft's sign-in renews on use and lapses after about 90 days unused.

## 2026-11-16: the plan's first six open questions

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions:** how you sign in to Microsoft, who may connect a mailbox, which mail is read and what's kept, what an alert becomes, what happens to a mail that fails the sender check, and how often the mailbox is checked.

**The decisions, with the options not taken:**
- **Signing in to Microsoft:** both ways, a Connect button that goes to Microsoft and comes back when the instance is on `https://` (it needs `MS_CLIENT_SECRET`), and a code typed at microsoft.com/devicelogin otherwise; not the code only; not the button only.
- **Who may connect:** as bank sync, with an "Email alerts" switch of its own in Admin, off by default; then any user connects their own mailbox, never a demo user, in a browser session only, with a fresh two-factor code to connect or disconnect; not one switch shared with bank sync; not admins only.
- **Mail read and kept:** one folder you name (Inbox by default), only mail from taught senders. Kept, encrypted: the values read, the sample each sender was taught from, and alerts that couldn't be read, removed with the log. Other mail is never stored, and the mailbox is never changed; not values only with no email text stored; not the full text of every alert.
- **What an alert becomes:** a paid line dated when the alert says, marked "from an alert"; not a line waiting under "To confirm"; not paid with only the unsure ones waiting.
- **A mail that fails the sender check:** skipped, counted in the log and shown with the couldn't-read alerts as "may not be from your bank"; not skipped silently; not with an "Add anyway" button.
- **How often:** each user picks 5, 15 or 60 minutes in Settings; not a fixed 5 or 15 minutes.

**Why:** the code works on a home-network address and the button is smoother where `https://` exists. A mailbox sign-in is a bigger secret than a bank token, so it gets its own switch. Keeping the sample and the unread alerts is what makes teaching and fixing possible without fetching mail again. Paid at once is what alerts are for. A forged alert must never become a line by a tap.

**What it changes:** phase 1 (#206) builds both sign-in ways and adds `MS_CLIENT_SECRET` to `.env.example`; phase 2 (#207) adds the per-user setting. Not asked, and built on unless said otherwise: the setting starts at 5 minutes, and the log is kept as long as the audit log.

## 2026-11-16: joining alerts to bank rows, and which Microsoft accounts

**Decided:** 2026-11-16, by Matthew. **Status:** accepted.

**The questions:** how close a bank sync row must be to an alert's line to be joined to it, what happens to an alert no bank row ever meets, whose values the joined line keeps, and which Microsoft accounts may connect.

**The decisions, with the options not taken:**
- **How close:** settable per account, how many days after the alert the bank's row may come and how much higher its amount may be, starting at 7 days and 30%. Always the same account and direction; the nearest date wins and a tie is left to join by hand; not a fixed 7 days and 30% for everyone; not the exact amount only.
- **Never posted:** an alert no bank row has met after 10 days is flagged "never posted" on the Unmatched list, to delete or keep; not removed by itself; not left alone for good.
- **Whose values:** the bank's amount and date, the alert's merchant name, and the user's own edits over both; not everything from the bank; not the alert's date.
- **Microsoft accounts:** personal (Outlook.com) and work or school, with `MS_TENANT` to narrow it; not work or school only; not personal only.

**Why:** a card used in restaurants needs room for a tip and a card that isn't doesn't, so the allowance belongs to the account. A line is never removed without the user, as "No destructive fixes" asks of everything else. The posted amount and date are the true ones, and SimpleFIN has no payee field, so the alert's name reads better.

**What it changes:** phase 5 (#210) gains two settings per account and a schema version for them. All nine of the plan's open questions are now settled.

## 2026-11-16: how a guess is corrected while teaching

**Decided:** 2026-11-16, by Matthew, while building phase 1 (#206). **Status:** accepted.

**The question:** on the teaching screen, the sample alert is shown as plain text with the reader's guesses highlighted. How does the user correct a wrong or missing value?

**Options considered:** select the right words, then pick Amount, Merchant, Date or Card from a bar under the text; pick the value first ("Fix"), then select its words; type each value into a box and let the server find it in the alert.

**The decision:** select the words, then pick which value they are; each value also has a Clear button, except the amount, which is required.

**Why:** one step per correction, the same with a finger or a mouse, and the marked words are exactly what the anchors are built from, so a value that appears twice is never ambiguous.

**Set while building, not asked:** the start date reaches back up to 30 days; one check opens at most 100 alerts and lands at most 50 lines, saying when more is waiting; Check now waits 15 seconds after the last check; a taught kind's marked amount has to be the amount itself, not text with a number in it.

## 2026-11-17: where the check log lives

**Decided:** 2026-11-17, by Matthew, while building phase 2 (#207). **Status:** accepted.

**The question:** the plan had each account's owner reading a log of checks, as bank sync's sync log does. An alert whose card isn't matched yet, or that failed the sender check, belongs to no account. Where does the log live?

**Options considered:** one log per mailbox; one per account as planned; both.

**The decision:** one log per mailbox, in Settings → Email alerts, listing each check that brought something in or failed, with the lines it brought in and the account each went to; not one per account; not both.

**Why:** a check can bring in lines for several accounts and some alerts have none; a mailbox is what a check belongs to. It's simpler to build and nothing is left out of it.

**Set while building, not asked:** the scheduler looks every minute, since the shortest interval is five; a failed check is tried again at the user's own interval; checks that found nothing aren't kept; the log is kept as long as the audit log.

## 2026-11-17: phase 1 ships ahead of the plan's one release

**Decided:** 2026-11-17, by Matthew, when asked to cut v1.73.0 (told to the release session, #216). **Status:** accepted.

**The question:** the plan said phases 1 to 4 would go out as one release. v1.73.0 was due with bank sync phase 4 (#196); should phase 1 of email alerts (#206) go in it?

**The decision:** yes. Phase 1 shipped in v1.73.0, switched off until an admin turns it on and sets `MS_CLIENT_ID`, with the release notes and the setup guide saying it has only been tested against a stand-in for Microsoft, never a real mailbox.

**Why:** it can't affect anyone who doesn't switch it on, and trying it on a real mailbox early finds what a stand-in can't, before more is built on it.

**What it changes:** phases 2 to 4 are released as they're ready, not together; phase 4 is no longer "the first release". The plan's other choices stand.
