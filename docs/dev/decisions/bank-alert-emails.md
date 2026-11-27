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

## 2026-11-27: what Google's own pages say about the two Gmail routes

**Checked:** 2026-11-27, at the start of phase 3 (#208), from Google's public help and developer pages. **Status:** both routes stand; neither is dropped.

**Gmail by app password (IMAP):**
- An app password is "a 16-digit passcode that gives a less secure app or device permission to access your Google Account", and "can only be used with accounts that have 2-Step Verification turned on" ([app passwords](https://support.google.com/accounts/answer/185833)).
- Google now calls them a fallback: "App passwords aren't recommended and are unnecessary in most cases" (same page, and [Add Gmail to another email client](https://support.google.com/mail/answer/7126229)).
- The option may not appear when 2-Step Verification is "set up only for security keys", on "a work, school, or another organization account", or with Advanced Protection.
- "We revoke your app passwords when you change your Google Account password." No expiry by time is stated. Removed from the App Passwords page.
- Since March 14, 2025, IMAP no longer takes the account's own password for any Google Account, "with the exception of app passwords" ([transition from less secure apps](https://knowledge.workspace.google.com/admin/sync/transition-from-less-secure-apps-to-oauth)).
- Since January 2025 "IMAP access is always turned on in Gmail"; there's no setting to switch on.
- The server name and port weren't on the pages read; `imap.gmail.com` on port 993 with TLS is what Gmail's clients use.

**Gmail with Google sign-in (Gmail API):**
- `gmail.readonly` is a **restricted** scope, and so is `gmail.metadata` (headers only, no bodies), so there's no narrower scope that reads an alert ([Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)).
- Reading bank alerts fits Google's fourth approved use: "Applications that use information from emails to provide reporting or monitoring services for the benefit of users ... (such as applications that automate travel itineraries or track flights or package delivery statuses)" ([Gmail API policy](https://developers.google.com/gmail/api/policy)). Finance isn't named either way.
- **Verification isn't needed** ([when verification is not needed](https://support.google.com/cloud/answer/13464323)) when:
  - the project is in **Personal mode** ("the only user of your app"): no verification, no warning screen, no user cap, no 7-day expiry, but only the account that made the project can sign in, and a project can't be changed out of Personal mode later ([app audience](https://support.google.com/cloud/answer/15549945));
  - the app has "a limited audience (fewer than 100 users)": users click through the "unverified app" warning screen. Set to "In production", the cap is "100 new users in total", over "the entire lifetime of the project" and can't be reset;
  - the project is in **Testing**: at most 100 listed test users, and "Authorizations by a test user will expire seven days from the time of consent" for any scope beyond name, email and profile, Gmail's included.
- **The security assessment** (CASA) is part of verifying a restricted scope ([restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)). No page says in so many words that an app excused from verification is excused from the assessment too; that's the reading this plan builds on, as the plan said on 2026-11-16.
- **Rules that apply anyway:** "All apps that integrate with Google APIs are required to comply with Google's API Services User Data Policy regardless of whether they have been verified." Its Limited Use rules: use the data only for "user-facing features that are prominent in the requesting application's user interface"; no transfers except for those features with consent, security or law; no human reads mail without the user's agreement; never for advertising, credit-worthiness or lending, or training AI models ([User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), [Gmail API policy](https://developers.google.com/gmail/api/policy)). WalletWeather already works this way: the values stay on the instance, nothing is sent on, and no outside service reads the mail.
- **Two limits on how it can be built:** Google's code-on-another-device flow is "supported only for" email, openid, profile and a few Drive and YouTube scopes, so Gmail can't be signed in with a code as Microsoft can ([limited-input devices](https://developers.google.com/identity/protocols/oauth2/limited-input-device)); and a web sign-in comes back to a redirect address that must be `https://` unless it's `localhost` ([web server apps](https://developers.google.com/identity/protocols/oauth2/web-server)). So "Connect Gmail" needs the instance on `https://`, as the Microsoft Connect button does.
- A refresh token lapses when it's been unused for six months, when it's revoked, or when "The user changed passwords and the refresh token contains Gmail scopes" ([OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)).

**What it changes:** nothing is dropped. The guide says app passwords are Google's own fallback and unavailable on work or school accounts; the sign-in route is offered on `https://` only, and the guide explains Personal mode, "In production" with the warning screen, and why "Testing" makes you reconnect every 7 days.

## 2026-11-27: the IMAP host guard, the sender check, the Gmail project and how the ways appear

**Decided:** 2026-11-27, by Matthew, at the start of phase 3 (#208). **Status:** accepted.

**The questions:** how strict the server is about the IMAP servers it connects to; how an IMAP mailbox's sender check is read, when a server other than Gmail may add no Authentication-Results header of its own; which Google Cloud project "Connect Gmail" uses; and how the new ways appear in Settings and Admin.

**The decisions, with the options not taken:**
- **Host guard:** exact host names on `IMAP_HOSTS` (default `imap.gmail.com`), no wildcards; port 993 with TLS from the first byte, the certificate and its name checked; no STARTTLS and no other port. A host not on the list is refused before any connection is made. A mail server at home works when the admin lists it. Not `host:port` entries; not STARTTLS on 143; not refusing home and loopback addresses that are listed.
- **Sender check on IMAP:** the topmost Authentication-Results header counts only when its server id is the one that host stamps: `mx.google.com` is built in for `imap.gmail.com`, and another host gives its id on the list (`imap.fastmail.com=fastmail.com`). Without one, that mailbox's alerts land under "may not be from your bank", and the guide says how to find the id. Gmail through Google sign-in expects `mx.google.com` the same way. Not the topmost header whatever wrote it, as Microsoft's; not Gmail only for now.
- **Gmail's project:** the instance's Google sign-in project (`GOOGLE_CLIENT_ID`), so anyone in the household can connect behind the warning screen; or, when `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` are set, that project instead, which can be in Personal mode (no warning screen, only its creator can connect). Not the sign-in project only; not a project of its own only.
- **How they appear:** three choices in Settings → Email alerts: Microsoft 365, Connect Gmail (shown only when `GMAIL_API_ENABLED` is set, a project is configured and the instance is on `https://`) and "Gmail or another mailbox" (an app password). Admin → Users ticks each of the three per person, as bank sync's providers. Not two choices with the Gmail ways grouped; not three choices under two ticks.

**Why:** a user-typed server name is a way to make the server connect somewhere, so the admin's list decides and nothing on it can be downgraded to plain text. A mail server that writes no header of its own leaves the sender's header on top, so a forged alert could pass a check that trusts whatever is first. Personal mode is the tidiest for one person, but a household on one instance needs the shared project. Separate ticks let an admin allow the app-password way without the Google project, or the other way round.

**Set while building, not asked:** a revoked app password (Google revokes them when the account's password changes) is recorded as a sign-in to make again, as a lapsed Microsoft sign-in is, and stops the schedule; connecting again means disconnecting first, as with Microsoft.

## 2026-11-27: reconnecting a mailbox keeps what was taught

**Decided:** 2026-11-27, by Matthew (#394). **Status:** accepted.

**The questions:** when a mailbox's sign-in is renewed in place, so the banks taught, the folder and the log are kept, may it sign in to a different mailbox address? And when is Reconnect offered?

**The decisions, with the options not taken:**
- **Same address only:** after signing in again, the server checks the mailbox's address; a different one is refused ("that's another mailbox: disconnect first to switch"). Not any address with the folder cleared.
- **Always offered:** a Reconnect section above Disconnect, there whether or not the sign-in has lapsed (to swap in a new app password before the old one is removed), highlighted with a button in the red notice when it has. Not only after a lapse.

**Why:** taught banks, cards and the folder belong to the mailbox they were set up on; switching mailboxes is what Disconnect is for. Swapping an app password early avoids a gap in checking.

**What it changes:** the "Set while building" line of 2026-11-27 above (connecting again means disconnecting first) is replaced: a lapsed sign-in or revoked app password is renewed with Reconnect, keeping everything.
