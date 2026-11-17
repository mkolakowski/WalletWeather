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
