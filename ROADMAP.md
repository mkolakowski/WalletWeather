# WalletWeather — Feature Review & Roadmap

A prioritized look at gaps in the current app (as of v1.9.0 / schema 9) and
what's worth building next. Items are ordered within each tier by
value-to-effort, with effort estimated against the app's existing
architecture (FastAPI + Postgres + single-file vanilla-JS SPA, no build
tools, single `docker compose` deployment).

Items struck through (~~like this~~) have shipped — the version tag in
parentheses is when they landed. New items should keep the original
numbering so older discussion and commit messages stay intelligible.

<!--
*** AI ASSISTANT INSTRUCTIONS — READ BEFORE EDITING THIS FILE ***

When you complete a roadmap item:
  1. Wrap the `### N. Title` heading AND the body paragraph in `~~…~~`
     strikethrough. Do not delete the text — this doc is also a ledger.
  2. Append ` ✅ **Shipped in vX.Y.Z.**` to the heading (outside the
     strikethrough) so it's still easy to scan.
  3. If the "Suggested first slice" list references the item, strike
     that bullet too.
  4. Do not renumber surviving items. If you add a new idea, give it the
     next unused number.
-->


---

## Tier 1 — Core finance gaps (build these first)

These are features almost every personal-finance app has and that the current
data model can't really fake. Each one closes a real workflow gap.

### ~~1. Account transfers~~ ✅ **Shipped in v1.7.0.**
~~Right now, moving money between two accounts has to be modeled as two
unrelated postings — once as expense, once as income — which double-counts
in the spending donut and breaks "income vs spending" totals. A first-class
`Transfer` entity (or a `transfer_pair_id` linking two postings) lets the
dashboard exclude transfers from spending/income and shows them as their
own line. **Effort: medium.** Touches the posting model, recurring
transactions, and the new dashboard charts.~~

### ~~2. Budgets per category~~ ✅ **Shipped in v1.7.0.**
~~The app already has Categories and a Forecast, so budgets are the natural
third leg. Monthly (and ideally rolling 30/90-day) caps per category, with
"% of budget used" surfaced on the dashboard and on the new donut chart.
This is also what makes the spending donut actionable rather than just
descriptive. **Effort: medium.** New `category_budgets` table, a budgets
admin screen, and a couple of new dashboard tiles.~~

### ~~3. Transaction search & filters~~ ✅ **Shipped in v1.7.0.**
~~The transactions list scales linearly today — no search box, no date-range
filter beyond the page. A simple text search across description/notes plus
filters for account, category, amount range, and date range covers 90% of
real usage. **Effort: small-to-medium.** Mostly a query-builder on the
existing endpoint plus UI controls.~~

### ~~4. CSV import for bank exports~~ ✅ **Shipped in v1.7.0.**
~~Manual entry is the biggest barrier to actually using a forecasting app
day-to-day. A "paste CSV / upload CSV" flow with column mapping (date,
amount, description, optional category) and a deduplication pass against
existing postings would dramatically reduce friction. OFX/QIF can come
later — CSV covers most banks. **Effort: medium.** Upload endpoint,
mapping UI, dedupe heuristic.~~

### ~~5. Net worth view~~ ✅ **Shipped in v1.7.0.**
~~You already have all the pieces — accounts, balances, daily history. A
single "Net Worth" tab that sums actual balances across accounts over time
and renders one larger sparkline (and a current total) is one of the most
satisfying views in any finance app. **Effort: small.** Mostly a
roll-up of the per-account daily balance series you just added.~~

---

## Tier 2 — Quality-of-life (high impact, modest effort)

### 6. Bill / low-balance / over-budget notifications
Even a quiet in-app "🔔 3 things need attention" panel goes a long way:
bills due in N days, accounts forecasted to go negative, categories over
budget. Email is a nice-to-have layered on top. **Effort: small** for
in-app, **medium** if SMTP support is added. Pairs naturally with budgets
(item 2) and transfers (item 1).

### ~~7. Subscription audit~~ ✅ **Shipped in v1.8.0.**
~~You already track recurring transactions — surface them as their own page
("you're spending $X/mo across N subscriptions") with sort by amount and
cost-per-year. Nearly free given the data is already there. **Effort:
small.** New page, no new tables.~~

### ~~8. Auto-categorization rules~~ ✅ **Shipped (as auto-tag rules) in v1.11.0.**
~~"If description matches `STARBUCKS`, set category to Coffee." Lets users
import CSVs (item 4) without re-categorizing every row. Rules apply on
ingest and optionally as a one-time backfill. **Effort: small-to-medium.**
New `category_rules` table and a rule-application pass.~~

> Shipped in tag-rule flavor rather than category-rule: a new `tag_rules`
> table maps a description-substring (with optional category gate) to a
> target tag, applied on transaction create / PATCH / CSV import, with a
> Backfill button to replay across history. Tags felt like the right
> first cut because (a) tags can wear many labels at once where category
> can only have one, and (b) it composes with the category gate so a
> "STARBUCKS in Coffee category → tag work-coffee" rule is expressible.
> A category-overwrite variant could still ship later if useful.

### 9. Split transactions
A single $120 grocery run that's actually $90 groceries + $30 household
needs to live as two posting children of one parent transaction. Without
this, categorization accuracy ceilings out. **Effort: medium.** Touches
the posting model and the transactions UI.

### ~~10. Tags~~ ✅ **Shipped in v1.8.0.**
~~Lighter-weight than splits — one category but many tags ("vacation",
"reimbursable"). Useful for cross-cutting reports that don't belong in the
category hierarchy. **Effort: small.** Many-to-many table, a tag picker,
filter chips.~~

### 11. Year-over-year comparison
The dashboard's new time windows (Month / 30d / 90d) lend themselves
naturally to a "vs same period last year" overlay on the spending donut and
totals tile. **Effort: small** once the dashboard charts are stable.

---

## Tier 3 — Security & operational hygiene

These are gaps that matter more the moment a non-trivial number of people
use the instance. The README explicitly flags one of them.

### ~~12. Encrypted backups~~
~~The README confirms backups are unencrypted. Given the rest of the app uses
Fernet at rest, an encrypted-export option (or just "use the same Fernet
key on restore") closes that loop. **Effort: small.** Wrap the existing
backup file in Fernet on the way out. Planned as phase 1 of
`Plans/bank-sync.md`.~~ Done in 1.68.0 (#193): every backup is encrypted
with a passphrase (not the Fernet key, so a backup restores on any server),
and "Download my data" stays as a readable copy.

### 13. Password reset
There's no self-serve flow today. Even a token-based "admin can issue a
reset link" mechanism (no SMTP required for v1) prevents lockouts.
**Effort: small.** New table for reset tokens, two endpoints, one page.

### ~~14. Two-factor authentication (TOTP)~~ ✅ **Shipped in v1.57.0.**
~~Standard `pyotp` + a QR code on enrollment. Self-hosted apps with real
financial data warrant this. **Effort: small-to-medium.** New columns on
`users`, an enrollment page, a verify step in login. Planned in
`Plans/two-factor.md` (#170).~~

> **Shipped (1.57.0, #165):** set-up in Settings → Your account with a QR
> code, a code step after the password, ten recovery codes and an admin
> switch-off. The codes are written from the standard, so `pyotp` wasn't
> needed. Remember this browser for 30 days followed in 1.58.0 (#167), a code
> in the iOS app's sign-in in 1.59.0 (#166) and an admin "require it" in
> 1.60.0 (#168), and a code for sensitive actions in 1.61.0 (#169), the
> last phase of `Plans/two-factor.md`.

### ~~15. Login rate limiting & audit log~~ ✅ **Shipped in v1.44.0 (rate limiting) and v1.49.0 (audit events, Admin → Audit log).**
~~Rate-limit failed logins by IP+username, and write significant events
(login, password change, admin actions, backup, restore) to an
`audit_events` table viewable by admins. Cheap insurance.
**Effort: small.**~~

### ~~16. API tokens~~ ✅ **Shipped in v1.41.0.**
~~For users who want to script ingest (e.g., a cron job pushing CSVs from
their bank), a personal access token system avoids needing to share
session cookies. **Effort: small.** Pairs naturally with item 4.~~

---

## Tier 4 — Polish & integration

### ~~17. PWA / installable app~~ ✅ **Shipped in v1.42.0.**
~~Add a manifest and service worker so the app installs on phones and works
offline-read. Vanilla SPA + no build tools makes this an afternoon's work.
**Effort: small.**~~ Offline it shows a notice rather than reading data
(decided 2026-11-14, `Plans/phone-path.md`).

### ~~18. Calendar view of bills & paychecks~~ ✅ **Shipped in v1.9.0.**
~~A month grid showing recurring transactions on their due dates is a
classic "ah, that's why I ran low on the 17th" view. **Effort: small.**~~

### 19. PDF export of monthly statement
A one-page "April 2026: income $X, spending $Y, top 5 categories, top 10
transactions" PDF is great for personal records and for sharing with a
spouse/accountant. **Effort: small** using ReportLab or WeasyPrint.

### 20. iCal feed for bills
A read-only `.ics` URL with one event per upcoming recurring transaction
lets users see bills in their normal calendar app. Tiny, extremely sticky.
**Effort: small.**

### 21. Webhooks
"Post to URL X when a transaction over $Y posts" or "when balance drops
below $Z". Pairs with the notification work. **Effort: small.**

---

## Tier 5 — Bigger bets (consider only if scope expands)

### 22. Multi-currency
Real if anyone holds accounts in more than one currency. Requires a rates
table, a base currency on each user, conversion at posting time, and FX
gain/loss accounting. **Effort: large.** I'd only do this if you have
a concrete use case — it touches almost every screen.

### 23. Investments / brokerage accounts
Holdings, lots, cost basis, dividends, daily price refresh. A whole
sub-application. **Effort: very large.** Reasonable as a v2 if WalletWeather
becomes someone's primary finance tool.

### 24. Loans / amortization schedules
Mortgage, auto, student loans with interest schedules feeding the forecast.
**Effort: medium-to-large.** Useful but narrower audience than the items
above.

### 25. Receipt attachments
Per-posting file uploads (image/PDF), stored encrypted on disk. Nice but
storage and backup story gets complicated quickly. **Effort: medium.**

### 26. Native iOS app
A SwiftUI app for iPhone that signs in to your own server with an API token
(item 16) and covers the everyday pages: Dashboard, Forecast, Bills & income
and Calendar, with two-pane layouts on the iPhone Duo's inner screen. Planned
in `Plans/ios-app.md` (#93). **Effort: large.**

### 27. Offline editing in the iOS app
Make changes in the iOS app without a connection and have them sync later.
The server has no sync today, so this needs endpoints for queued changes and
rules for when the phone and the server disagree. It builds on the app's
"Last-known numbers" choice (`Plans/ios-app.md`, phase 8). **Effort: large.**

### 28. Search across everything
One search box that finds transactions, bills and income, accounts,
categories and saved reports, in the web app's top bar and in the iOS app.
Today only transactions can be searched (item 3). It needs one search endpoint
that returns matches grouped by kind (#111). **Effort: medium.**

### 29. Bank sync (SimpleFIN, Plaid)
Pull transactions from the bank on a schedule instead of uploading a CSV
(item 4), land them through the same import path with the provider's
transaction id for de-duplication, and apply the auto-tag rules (item 8).
Two providers were looked at (#163). Decided 2026-11-16: SimpleFIN Bridge,
planned in `Plans/bank-sync.md`; Plaid is not planned:

- **SimpleFIN Bridge:** the user pays for it themselves and pastes one token
  into the app, and the server polls. No approval, no third-party script, no
  public address. It gives no categories, so a mapping and the tag rules do
  that work.
- **Plaid:** each instance brings its own Plaid keys, as Google sign-in does
  with `GOOGLE_CLIENT_ID`; the project can't ship a shared one. Plaid
  supplies a category per transaction, to be mapped onto the user's
  categories. It needs Plaid's production approval per operator, loads its
  sign-in window from Plaid's servers (`PRIVACY.md` says the web client
  loads nothing from other sites) and needs a public HTTPS return address
  for the large banks, against the README's advice to stay off the public
  internet.

**Progress:** phase 1 (encrypted backups) shipped in 1.68.0; phase 2
(connect a bank and Sync now) in 1.69.0 (#194); phase 3 (the daily sync
and its log) in 1.70.0 (#195). Matching bills and the iOS part follow.

Either one stores a long-lived, read-only bank token, so encrypted backups
(item 12) and two-factor sign-in (item 14) should come first. `PRIVACY.md`
("What leaves the server"), `docs/privacy.md`, `SECURITY.md` ("Known
limits"), the README's security notes, `.env.example` and the first-login
notice would all change, and disconnecting a bank or deleting a user has to
remove the connection at the provider. How pending bank rows meet the
forecast and "To confirm" is an open design question. Planned in
`Plans/bank-sync.md`, with encrypted backups as its first phase.
**Effort: large.**

### 30. Bank alert emails
Switch on "alert me for every transaction" at the bank and let the server
read those emails from your own mailbox: each becomes a line minutes after
the purchase, tagged by the auto-tag rules (item 8) and matched to the
planned bill it pays, then joined to the posted row bank sync (item 29)
brings days later. Microsoft 365 first, then Gmail and other IMAP
mailboxes. The app is taught each bank's alert from a sample rather than
shipping a reader per bank. It stores a sign-in that can read mail, so it
is off until an admin allows it, and `PRIVACY.md`, `SECURITY.md` and
`.env.example` change with it. Planned 2026-11-16 in
`Plans/bank-alert-emails.md` (#212). **Effort: large.**

**Progress:** phase 1 (connect Microsoft 365, teach a bank's alert, Check
now) shipped in 1.73.0 (#206), switched off by default and not yet tried with
a real mailbox; the checking by itself, its status and log shipped in
1.74.0 (#207); alerts paying your planned bills are built in 1.75.0 (#209),
not released yet.

### 31. Standalone iPhone app (no server)
Use WalletWeather on an iPhone with no server: the data lives on the phone,
backs up to iCloud Drive in the server's backup format, syncs between the
person's devices, and moves to a server (or back) with the existing Import.
The money logic becomes one JavaScript core run by the server, the phone
(JavaScriptCore) and later the web, checked against an answer key made by
today's server. Bank sync can run on the phone. Overlaps item 27, which is
offline editing for people who use a server. Planned 2026-11-18 in
`Plans/standalone.md` (#240). **Effort: large.**

### 32. The web app without a server
The web app working entirely in the browser, its data kept there, on the
same JavaScript core as item 31. Browser storage can be wiped, so it needs
the backup and export that item 31 builds. Waits for item 31 (decided
2026-11-18). **Effort: medium.**

### 33. Net worth, Budgets and Reports in standalone
The More pages in the standalone iPhone app (item 31), which starts with
Dashboard, Forecast, Bills & income and Calendar. Their logic moves into
the shared core first. Waits for item 31 (decided 2026-11-18).
**Effort: medium.**

---

## What's already in good shape (don't re-prioritize these)

- Multi-account, categories with colors, recurring transactions, and a
  forecast that blends actuals + projections.
- Reports page with breakdowns.
- Admin panel + Fernet encryption at rest + backup/restore round-trip.
- Per-user theming (now server-side), demo mode, and the new dashboard
  charts with selectable time window and placement.
- Three independent version numbers + a CHANGELOG with maintenance
  instructions baked into the source files themselves.

---

## Suggested first slice

If I had to pick five for the next two minor releases:

1. ~~**Account transfers** (1.7.0) — fixes a correctness gap in your brand-new
   dashboard charts.~~ ✅ shipped in 1.7.0.
2. ~~**Transaction search & filters** (1.7.0) — biggest day-to-day usability win.~~ ✅ shipped in 1.7.0.
3. ~~**Budgets per category** (1.8.0) — turns the donut from descriptive into
   actionable.~~ ✅ shipped in 1.7.0 (earlier than planned).
4. **CSV import + auto-categorization rules** (1.8.0) — they're really one
   feature once you start building either. ~~_(CSV import shipped in 1.7.0.)_~~
   **Auto-categorization rules still pending.**
5. **Encrypted backups** (1.8.0 patch) — closes the one security gap your own
   README calls out.

~~Notifications, net worth view, and subscription audit are great 1.9.0
candidates after that.~~ Net worth view landed in 1.7.0, subscription audit
in 1.8.0, and the Calendar view (item 18) shipped in 1.9.0.

### Next-up candidates (post-1.9.0)

Highest-value remaining items, in priority order:

- **Auto-categorization rules (#8)** — pairs with the now-shipped CSV importer
  and saves the user from re-categorizing every imported row.
- **Encrypted backups (#12)** — still the one security gap the README
  explicitly calls out.
- **Notifications panel (#6)** — now cheap to build on top of budgets and
  transfers, which have both landed.
- **Split transactions (#9)** — the biggest remaining correctness gap in
  categorization now that tags are in.
- **Password reset (#13)** and **TOTP (#14)** — natural pair for a 2.0
  security pass.
