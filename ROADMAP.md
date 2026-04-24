# WalletWeather — Feature Review & Roadmap

A prioritized look at gaps in the current app (as of v1.6.0 / schema 7) and
what's worth building next. Items are ordered within each tier by
value-to-effort, with effort estimated against the app's existing
architecture (FastAPI + Postgres + single-file vanilla-JS SPA, no build
tools, single `docker compose` deployment).

---

## Tier 1 — Core finance gaps (build these first)

These are features almost every personal-finance app has and that the current
data model can't really fake. Each one closes a real workflow gap.

### 1. Account transfers
Right now, moving money between two accounts has to be modeled as two
unrelated postings — once as expense, once as income — which double-counts
in the spending donut and breaks "income vs spending" totals. A first-class
`Transfer` entity (or a `transfer_pair_id` linking two postings) lets the
dashboard exclude transfers from spending/income and shows them as their
own line. **Effort: medium.** Touches the posting model, recurring
transactions, and the new dashboard charts.

### 2. Budgets per category
The app already has Categories and a Forecast, so budgets are the natural
third leg. Monthly (and ideally rolling 30/90-day) caps per category, with
"% of budget used" surfaced on the dashboard and on the new donut chart.
This is also what makes the spending donut actionable rather than just
descriptive. **Effort: medium.** New `category_budgets` table, a budgets
admin screen, and a couple of new dashboard tiles.

### 3. Transaction search & filters
The transactions list scales linearly today — no search box, no date-range
filter beyond the page. A simple text search across description/notes plus
filters for account, category, amount range, and date range covers 90% of
real usage. **Effort: small-to-medium.** Mostly a query-builder on the
existing endpoint plus UI controls.

### 4. CSV import for bank exports
Manual entry is the biggest barrier to actually using a forecasting app
day-to-day. A "paste CSV / upload CSV" flow with column mapping (date,
amount, description, optional category) and a deduplication pass against
existing postings would dramatically reduce friction. OFX/QIF can come
later — CSV covers most banks. **Effort: medium.** Upload endpoint,
mapping UI, dedupe heuristic.

### 5. Net worth view
You already have all the pieces — accounts, balances, daily history. A
single "Net Worth" tab that sums actual balances across accounts over time
and renders one larger sparkline (and a current total) is one of the most
satisfying views in any finance app. **Effort: small.** Mostly a
roll-up of the per-account daily balance series you just added.

---

## Tier 2 — Quality-of-life (high impact, modest effort)

### 6. Bill / low-balance / over-budget notifications
Even a quiet in-app "🔔 3 things need attention" panel goes a long way:
bills due in N days, accounts forecasted to go negative, categories over
budget. Email is a nice-to-have layered on top. **Effort: small** for
in-app, **medium** if SMTP support is added. Pairs naturally with budgets
(item 2) and transfers (item 1).

### 7. Subscription audit
You already track recurring transactions — surface them as their own page
("you're spending $X/mo across N subscriptions") with sort by amount and
cost-per-year. Nearly free given the data is already there. **Effort:
small.** New page, no new tables.

### 8. Auto-categorization rules
"If description matches `STARBUCKS`, set category to Coffee." Lets users
import CSVs (item 4) without re-categorizing every row. Rules apply on
ingest and optionally as a one-time backfill. **Effort: small-to-medium.**
New `category_rules` table and a rule-application pass.

### 9. Split transactions
A single $120 grocery run that's actually $90 groceries + $30 household
needs to live as two posting children of one parent transaction. Without
this, categorization accuracy ceilings out. **Effort: medium.** Touches
the posting model and the transactions UI.

### 10. Tags
Lighter-weight than splits — one category but many tags ("vacation",
"reimbursable"). Useful for cross-cutting reports that don't belong in the
category hierarchy. **Effort: small.** Many-to-many table, a tag picker,
filter chips.

### 11. Year-over-year comparison
The dashboard's new time windows (Month / 30d / 90d) lend themselves
naturally to a "vs same period last year" overlay on the spending donut and
totals tile. **Effort: small** once the dashboard charts are stable.

---

## Tier 3 — Security & operational hygiene

These are gaps that matter more the moment a non-trivial number of people
use the instance. The README explicitly flags one of them.

### 12. Encrypted backups
The README confirms backups are unencrypted. Given the rest of the app uses
Fernet at rest, an encrypted-export option (or just "use the same Fernet
key on restore") closes that loop. **Effort: small.** Wrap the existing
backup file in Fernet on the way out.

### 13. Password reset
There's no self-serve flow today. Even a token-based "admin can issue a
reset link" mechanism (no SMTP required for v1) prevents lockouts.
**Effort: small.** New table for reset tokens, two endpoints, one page.

### 14. Two-factor authentication (TOTP)
Standard `pyotp` + a QR code on enrollment. Self-hosted apps with real
financial data warrant this. **Effort: small-to-medium.** New columns on
`users`, an enrollment page, a verify step in login.

### 15. Login rate limiting & audit log
Rate-limit failed logins by IP+username, and write significant events
(login, password change, admin actions, backup, restore) to an
`audit_events` table viewable by admins. Cheap insurance.
**Effort: small.**

### 16. API tokens
For users who want to script ingest (e.g., a cron job pushing CSVs from
their bank), a personal access token system avoids needing to share
session cookies. **Effort: small.** Pairs naturally with item 4.

---

## Tier 4 — Polish & integration

### 17. PWA / installable app
Add a manifest and service worker so the app installs on phones and works
offline-read. Vanilla SPA + no build tools makes this an afternoon's work.
**Effort: small.**

### 18. Calendar view of bills & paychecks
A month grid showing recurring transactions on their due dates is a
classic "ah, that's why I ran low on the 17th" view. **Effort: small.**

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

1. **Account transfers** (1.7.0) — fixes a correctness gap in your brand-new
   dashboard charts.
2. **Transaction search & filters** (1.7.0) — biggest day-to-day usability win.
3. **Budgets per category** (1.8.0) — turns the donut from descriptive into
   actionable.
4. **CSV import + auto-categorization rules** (1.8.0) — they're really one
   feature once you start building either.
5. **Encrypted backups** (1.8.0 patch) — closes the one security gap your own
   README calls out.

Notifications, net worth view, and subscription audit are great 1.9.0
candidates after that.
