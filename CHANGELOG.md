# Changelog

All notable changes to WalletWeather are recorded in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Three independent version numbers are tracked:

- **App version** (`APP_VERSION` in `backend/app/main.py`) — the user-facing
  application version shown in the UI and exposed via `/api/version`.
- **Web version** (`WEB_VERSION` in `backend/static/index.html`) — the SPA
  version, bumped for frontend-only changes.
- **Schema version** (`SCHEMA_VERSION` in `backend/app/db.py`) — the database
  schema generation, bumped whenever a model or migration changes.

<!--
=============================================================================
*** AI ASSISTANT INSTRUCTIONS — READ BEFORE EDITING THIS FILE ***
=============================================================================

This changelog is updated AS FEATURES SHIP, not only at release time. The
running `[Unreleased]` section at the top is the working set of changes
that have landed on the default branch but haven't been tagged yet.

WHEN YOU FINISH A FEATURE, BUG FIX, OR BEHAVIORAL CHANGE, YOU MUST:

  1. Add a bullet under the appropriate subsection in `[Unreleased]`:
       - `### Added`     — brand-new user-visible capabilities.
       - `### Changed`   — behavioral or UX changes to existing features.
       - `### Fixed`     — bug fixes.
       - `### Database`  — schema/migration entries (paired with a
                           SCHEMA_VERSION bump in db.py).
       - `### Security`  — security-relevant changes.
     Create the subsection if it doesn't already exist. Omit empty ones.

  2. Every bullet must be a full sentence (or two) that describes the
     change in user-facing terms — not "refactored X" but "X now does Y".
     Include the specific endpoint, file, table, or flag name when it
     helps a future reader (or a future AI) locate the change in code.

  3. Update the `App version:` / `Web version:` / `Schema version:` header
     line at the top of `[Unreleased]` to match whatever bumps went into
     the matching source files. Those three version constants
     (APP_VERSION, WEB_VERSION, SCHEMA_VERSION) are the source of truth;
     this file just tracks them.

  4. Do NOT rewrite already-released sections (below `[Unreleased]`).
     Released versions are frozen history — only append to `[Unreleased]`.

WHEN YOU CUT A RELEASE (tag a version):

  5. Rename the `[Unreleased]` heading to `[X.Y.Z] — YYYY-MM-DD` with the
     concrete dates and versions baked in.
  6. Add a fresh, empty `## [Unreleased]` block above it with the current
     version numbers.
  7. Update the link-reference footer at the bottom of the file so the
     GitHub compare/tag URLs point at the new release.

WHY THIS MATTERS: a CHANGELOG that lags behind the code is worse than
useless — it gives a false sense of history. Record the change in the
same commit (or session) that introduces it.

-->

## [Unreleased]

App version: **1.12.0** · Web version: **1.12.0** · Schema version: **11**

### Added

- **Saved reports + live editor.** The Reports page is now driven by a
  saved-reports model: a left rail lists the user's reports (with a 📌
  badge on the ones pinned to the dashboard) and a Templates panel
  underneath offers starting points. Clicking a template instantiates a
  new report; every parameter on the editor — *Group by* (category /
  tag / account), *Range* (month, last 30 days, last 90 days, YTD, full
  year, custom), month / year, custom start/end, *Kind* (all / spending
  / income), *Chart* (table / bar / pie), *Include transfers* toggle,
  and multi-select Accounts / Categories / Tags filters — re-runs the
  report live (debounced) so the result and chart update as the user
  changes anything. Save / Save as / Delete / Pin-to-dashboard live in
  the editor header.
- **Pin reports to the dashboard.** Each saved report has a `pinned`
  flag; pinned reports render below the account cards on the Dashboard
  as compact panels with a top-5 bar chart and an *Edit ›* link that
  jumps back to that report on the Reports page.
- **Built-in report templates.** Seven starting points exposed via
  `GET /api/report-templates`: monthly spending by category, monthly
  income by category, year-to-date by category, last 30 days by tag,
  last 90 days spending by tag, monthly spending by account, full-year
  net by category. Templates are shipped as code (not a per-user table),
  so they're versioned with the rest of the release.
- **Reports API.** New `POST /api/report/run` runs an inline params blob
  (used by the live editor). `GET /api/saved-reports` (+ POST/PATCH/DELETE)
  manages user reports and `POST /api/saved-reports/{id}/run` resolves
  and executes a saved report. The legacy `GET /api/report` is preserved
  for back-compat. A new `_compute_report` helper backs all of them and
  supports `group_by` ∈ {category, tag, account}, six range modes,
  account / category / tag multi-select filters, kind sign filter, and a
  configurable `include_transfers` toggle.
- **New inline bar chart renderer.** Used by both the Reports editor
  (when chart_type = "bar") and the dashboard pinned-report panels.
- **Demo: sample reports + one pinned.** The demo seed now installs four
  saved reports — *This month's spending* (pinned), *Income year-to-date*,
  *Last 90 days by tag*, *Spending by account this month* — so the demo
  dashboard shows a pinned report out of the box.
- **Tag-based reports.** The Reports page now includes a *By tag* breakdown
  (forecast vs actual, Δ, count) and a *Spending by tag* pie chart, mirroring
  the existing category panels. Backed by a new `tags: [...]` array on
  `GET /api/report` — every tagged transaction contributes its full
  amount to each of its tags, so totals across tags can exceed totals
  across categories (which is the point of tags as an overlay).
- **Bulk tag operations in transaction search.** Search results gain a
  per-row checkbox, a select-all checkbox in the header, and a bulk
  action bar that appears once at least one row is selected. The bar
  has a tag picker plus *Apply tag* / *Remove tag* / *Clear* buttons and
  reports how many rows were affected after each action. Transfer-leg
  rows are excluded from selection (they don't carry tags by design).
  Backed by a new `POST /api/transactions/bulk-tag` taking
  `{transaction_ids, add_tag_ids, remove_tag_ids}`; idempotent, validates
  tag ownership, and skips rows the caller can't edit.
- **Auto-tag rules.** A new *Auto-tag rules* panel in Settings lets the
  user define `description contains X` rules (with an optional category
  filter) that auto-attach a chosen tag whenever a matching transaction
  is created, edited, or imported. A *Backfill existing transactions*
  button replays every active rule across the user's whole history in
  one shot — idempotent, so re-running is safe. Rules are additive (they
  never remove tags). New `/api/tag-rules` (GET/POST/PATCH/DELETE) and
  `/api/tag-rules/backfill`.
- **Dashboard "Edit" shortcut.** Small pencil-icon button sits inline with
  the **Dashboard** title. Clicking it switches to Settings, smooth-scrolls
  the *Dashboard charts placement* section into view, focuses the current
  selection, and briefly flashes the block so the control is impossible to
  miss. Centralizing the edit flow in Settings means future dashboard-layout
  knobs (widget toggles, card ordering) can drop into the same section
  without another navigation path.
- **Transfer page balance readouts.** The Transfer money page now shows the
  current balance for both the From and the To account under their
  respective selectors, and — when an amount has been entered — an
  "after: $X" projection that updates live as the user types. If the
  transfer would push the From balance negative the projected amount is
  painted red as a warning. Balances come from a new `current_balance`
  field on every `/api/accounts` row, computed as *starting balance + every
  cleared transaction on or before today* (a lightweight SQL scan rather
  than the full forecast walk, so the readouts refresh cheaply).
- **Global footer with versions + GitHub link.** A persistent footer sits
  below every screen (auth, app, and all SPA pages) displaying the app
  title plus the three version numbers (`app vX.Y.Z`, `web vX.Y.Z`,
  `schema vN`) as inline chips, and a **View on GitHub ↗** hyperlink to
  the project repo. Values are populated from `/api/auth/config` on first
  load so the footer is useful even before sign-in.
- **Calendar.** New top-level Calendar page and `GET /api/calendar?start=…&end=…`
  endpoint. The endpoint walks `build_forecast` for every account the user can
  see and returns a flat list of dated events (forecasted or recorded), each
  carrying the account, category name + color, tags, signed amount, forecast
  vs actual amount, `recurring_id` / `transfer_id` / `transaction_id` linkage,
  and an `is_actual_real` flag. The window is capped at 366 days. The
  frontend renders a fixed 6×7 month grid (so the layout doesn't jump between
  5- and 6-row months) with prev / next / today navigation and a summary line
  showing event count + month net. Event pills are colored by category
  (inline style from `category_color`) and marked by kind via a left border —
  income (green), spending (red), transfer (dashed gray) — with pending rows
  rendered italic/dim. A filter bar covers Account (sent as `account_id` to
  the server so we fetch less), Category, Tag, Source (*Scheduled* =
  `recurring_id != null`, *One-time* otherwise), Kind (income / spending /
  transfer), and Status (cleared / pending); all non-account filters run
  client-side against the cached event list for instant toggles. Clicking a
  day reveals a detail panel with the full event table (account, description,
  category, tags, amount, status) and a per-event **Go to account** jump.
- **Subscription audit.** New top-level Subscriptions page and
  `GET /api/subscriptions` endpoint. Aggregates every active, non-expired,
  negative-amount recurring transaction across all accounts the user can
  see, normalizes the magnitude to monthly (monthly_day × 1, biweekly ×
  26/12, weekly × 52/12) and yearly cost, and sorts descending by monthly
  drain. Summary tiles show count · monthly · yearly; each row links back
  to the Transactions page with that account preselected so the user can
  edit or cancel the recurring row inline.
- **Tags.** Lighter-weight cross-category labels — a transaction still
  carries exactly one category, but can now wear any number of tags
  (e.g. "vacation", "reimbursable", "business"). A new Settings → Tags
  panel supports create / rename / delete with an optional color; names
  are stored unencrypted (same as Category) so tag filters stay a SQL
  JOIN instead of a decrypt loop. Forecast rows render tag chips under
  the description, the forecast inline-edit row offers a clickable pill
  multi-select picker, and the Transaction search form gets a Tag
  dropdown filter plus a new Tags column in the results table. Tags are
  exposed on `GET /api/tags` (`POST`/`PATCH`/`DELETE` for CRUD) and
  returned as a `tags: [{id, name, color}, ...]` array on
  `GET /api/accounts/{id}/forecast` rows, `GET /api/accounts/{id}/transactions`,
  and `GET /api/transactions/search`. `/api/transactions/search` takes a
  new `tag_id` filter that joins `transaction_tags` and scopes to the
  caller's own tags. Transaction write endpoints
  (`POST /api/accounts/{id}/transactions`,
  `PATCH /api/transactions/{id}`) accept a `tag_ids: [int]` payload —
  `None` means "leave tags alone", `[]` clears them, a list replaces.
- **Demo mode auto-reset.** When `DEMO_MODE` is on, a new background daemon
  runs once an hour and rebuilds the demo data, but only if something has
  actually been edited since the last seed. A SHA-256 fingerprint over all
  demo-owned accounts, categories, recurring templates, transactions,
  transfers, and budgets is stamped into the new `demo_fingerprint`
  `AdminSetting` row at the end of each seed; the hourly check compares that
  baseline against a freshly computed fingerprint and skips the reset when
  they match. Visitors who just poke around without mutating anything no
  longer get their session yanked out from under them.
- New `reseed_demo_if_changed()` helper in `backend/app/demo.py`.
- New `_demo_reset_scheduler_loop()` daemon thread in `backend/app/main.py`,
  started from `_startup` only when `DEMO_MODE` is true.

### Changed

- **Default dashboard chart placement is now "Inside each card"** (previously
  "Above account cards"). Each account card becomes self-contained — its
  spending donut, totals tile, and balance sparkline render inline — which
  is the denser, more useful first-impression layout. Users who already
  picked a placement are unaffected; only the fallback when
  `users.chart_position` is null changes. Flip it on the Settings page (or
  via the new pencil button on the Dashboard).
- When `DEMO_MODE` is on, the app title is forced to **"WalletWeather Demo"**
  in the browser tab, login card, and app header, regardless of any admin-
  customized title. Non-demo instances are unaffected and still use the
  admin-settable title.
- `DEMO_MODE` now defaults to **off** (previously on). A fresh production
  install boots empty instead of exposing the demo admin login. Set
  `DEMO_MODE=true` in `.env` to opt in. `.env.example` and
  `docker-compose.yml` defaults updated to match.
- CSV importer moved out of a modal overlay into a dedicated Import page
  (`#pageImport`). The overlay was failing to dismiss on some browsers; the
  page version has its own target-account selector, navigates back to the
  target account on commit, and can be reached from "Import CSV" on the
  Account detail page.
- Transfer editor (new transfer + edit existing transfer) moved out of its
  modal overlay into a dedicated Transfer page (`#pageTransfer`). Same
  reasoning — overlay dismissal was unreliable. Reached from "Transfer
  money" on the Account detail page and from "Edit" on the Recent transfers
  list; the form now includes an inline Delete button while editing.
- No modal overlays remain in the app. The unused `.modal-overlay` and
  `.modal-card` CSS rules were deleted.
- **Account actions** panel (Transfer money + Import CSV buttons) and the
  **Recurring transactions** panel moved from the Accounts page into the
  Transactions page. A new "Managing account" picker at the top of
  Transactions drives both panels; switching it updates the recurring list
  and also keeps the Accounts-page tab highlight in sync so navigating back
  to Accounts lands on the same account. Accounts → account detail now
  focuses on summary, add-transaction, and forecast.

### Database

- Schema bumped to **v11**. New `saved_reports` table (`id`, `owner_id`,
  `name VARCHAR(120)`, `params TEXT` storing JSON, `pinned BOOLEAN`,
  `sort_order INTEGER`, `created_at`). The params blob is JSON text
  rather than typed columns so the report shape can grow (new
  group_by axes, new chart types) without further migrations. Created
  by `Base.metadata.create_all`; no `ALTER` migration needed when
  upgrading from v10.
- Schema bumped to **v10**. New `tag_rules` table (`owner_id`, optional
  human-friendly `name`, `description_pattern VARCHAR(120)` stored
  lowercased so the apply path can do a single case-insensitive substring
  check, optional `category_id`, required `tag_id`, `active`,
  `created_at`). Created by `Base.metadata.create_all` — no `ALTER`
  needed when upgrading from v9.
- Schema bumped to **v9**. New `tags` table (per-user label; `owner_id`,
  `name VARCHAR(60)`, optional `color`, `created_at`) and new
  `transaction_tags` many-to-many join (`transaction_id` + `tag_id`
  composite PK, both sides `ON DELETE CASCADE`). Both tables are created
  by `Base.metadata.create_all`; no `ALTER` migration is needed for the
  upgrade from v8.

## [1.7.0] — 2026-04-23

App version: **1.7.0** · Web version: **1.7.0** · Schema version: **8**

This release ships all five Tier-1 items from `ROADMAP.md`.

### Added

- **Account transfers.** First-class money-movement records between two
  accounts the user owns/can edit. Backed by a new `transfers` table plus a
  nullable `transactions.transfer_id` foreign key — each transfer materializes
  as a paired negative/positive posting on the two accounts so existing
  forecast and balance math runs unchanged. Dashboard charts, the spending
  donut, the reports endpoint, and budget progress all filter transfer legs
  out so transfers no longer double-count as spend + income.
  - New `Transfer` model (encrypted description, positive magnitude, notes).
  - New `GET/POST/PATCH/DELETE /api/transfers` endpoints.
  - New "Transfer money" modal on the Account detail page, and a "Recent
    transfers" list on the new Transactions page with inline edit/delete.
- **Budgets per category.** Monthly spending caps per category with live
  progress bars on a new Settings → Budgets panel. Shows a row for every
  category (budgeted or not), current-window spend, percent-of-budget,
  and a color-coded bar that turns orange at 80% and red past 100%.
  - New `category_budgets` table (per-user, unique per category).
  - New `GET/POST/DELETE /api/budgets` and `GET /api/budgets/progress`
    endpoints with a `window=month|30d|90d` selector.
- **Transaction search & filters.** New top-level Transactions page with a
  full query form: free-text (description + notes), account, category,
  kind (income / spending / transfers / all), date range, amount range,
  include-or-exclude transfers, and paged results.
  - New `GET /api/transactions/search` endpoint. SQL pre-filters on the
    cheap unencrypted columns then decrypts only the candidate set in Python
    to match encrypted description/notes/amount.
- **CSV import for bank exports.** Upload a CSV from the Account detail
  page, auto-detect columns (date / description / amount — or debit+credit
  — / optional category & notes), preview every row with per-row
  duplicate flagging, then commit. Dedupe key is `(date, rounded amount,
  lowercased description)` against the account's existing postings and
  previously imported rows in the same file.
  - New `POST /api/accounts/{id}/import/preview` and `/import/commit`
    endpoints with sign-convention options (`amount`, `amount_invert`,
    `debit_credit`).
  - New "Import CSV" modal on the Account detail page.
- **Net Worth view.** A new top-level Net Worth tab aggregates daily balance
  trends across every account the user can see, with a selectable window
  (Month / 30 days / 90 days), an inline SVG line+area chart, summary stats
  (opening · latest · change · %), and a per-account contribution table.
  - New `GET /api/networth?window=...` endpoint that reuses `build_forecast`
    per account and sums daily totals across visible accounts.

### Changed

- `build_forecast()` now carries `transfer_id` through to each output row so
  aggregation endpoints can cleanly exclude transfer legs.
- `GET /api/dashboard/charts` and `GET /api/report` now skip rows with a
  non-null `transfer_id` when computing income, spending, and category
  totals — transfers are reported separately, not as spend + income.

### Database

- New `transfers` table (created by `Base.metadata.create_all`).
- New `category_budgets` table (created by `Base.metadata.create_all`).
- New idempotent migration:
  `ALTER TABLE transactions ADD COLUMN IF NOT EXISTS transfer_id INTEGER
  REFERENCES transfers(id) ON DELETE CASCADE`.

## [1.6.0] — 2026-04-23

App version: **1.6.0** · Web version: **1.6.0** · Schema version: **7**

### Added

- Dashboard: per-account spending-by-category donut chart with top-5 + "Other"
  rollup, dollar-amount legend, and centered total-spend label. Uses each
  category's color when set, otherwise a deterministic palette hashed from the
  category name.
- Dashboard: per-account income / spending / net totals tile with "+$X vs plan"
  deltas against the forecast.
- Dashboard: per-account daily balance sparkline (inline SVG). Past days show
  realized balances, future days show the forecast projection.
- Dashboard: time-window toggle (Month · 30 days · 90 days) above the cards.
- Settings → Appearance: dashboard chart placement preference (above cards /
  below cards / inside each card), saved server-side per user.
- New `GET /api/dashboard/charts?window=month|30d|90d` endpoint returning
  per-account totals, category breakdown, and daily balance trend.
- New `users.chart_position` column (`'above' | 'below' | 'inside'`).

### Changed

- `PATCH /api/me/preferences` now accepts a `chart_position` field, validated
  against the allowed set.
- `/api/me` now returns `chart_position`.

## [1.5.0] — 2026-04-23

App version: **1.5.0** · Web version: **1.5.0** · Schema version: **6**

### Added

- Admin → Instance branding: a customizable app title that replaces
  "WalletWeather" in the browser tab, the login screen, and the app header.
  Stored in the existing `admin_settings` table — no schema change.
- New `GET /api/admin/app-title`, `POST /api/admin/app-title`, and
  `DELETE /api/admin/app-title` endpoints.
- `app_title` is now included in the `GET /api/auth/config` response.
- New `SCHEMA_VERSION`, `APP_VERSION`, and `WEB_VERSION` constants in
  `backend/app/db.py`, `backend/app/main.py`, and `backend/static/index.html`,
  with inline instructions and per-file changelog comment blocks for future
  edits.
- New `GET /api/version` endpoint exposing `app_version` and `schema_version`.
- `app_version` and `schema_version` are also included in
  `GET /api/auth/config`.

### Changed

- The default theme is now **System** (follows the OS preference) instead of
  Dark.
- The theme picker in Settings is now organized into two labeled rows: **Dark**
  (with System at the top) and **Light**.
- The Appearance description copy was updated to reflect server-side
  persistence: "Your choice is saved to your account on the server and follows
  you across browsers and devices."

### Fixed

- **Cross-user theme leak.** The selected theme was being cached in
  `localStorage`, which meant the previous user's theme would briefly render
  after another user signed in on the same browser. All theme `localStorage`
  reads/writes were removed; the server is now the sole source of truth. The
  pre-paint script now only consults `prefers-color-scheme` to pick a sensible
  default before authentication resolves.

## [1.4.0] — 2026-04-22

App version: **1.4.0** · Web version: **1.4.0** · Schema version: **6**

### Added

- **Light theme** plus eight additional themes: Dracula, Solarized, Nord,
  Synthwave, Forest, Mint, Monokai, and Sunset. Selectable from
  Settings → Appearance.
- **Demo mode**, on by default. Boots WalletWeather with a pre-seeded admin
  user (`admin@demo.walletweather.local` / `demo1234`) and sample accounts,
  recurring transactions, and actual postings so the app is explorable on
  first launch. Set `DEMO_MODE=false` in `.env` to disable; demo data is wiped
  on the next restart when disabled.
- Login screen demo banner with a "Fill demo credentials" button while demo
  mode is on.
- `DEMO_MODE` environment variable wired into `docker-compose.yml` and
  documented in `.env.example` and `README.md`.
- Per-user **server-side theme persistence**: a new `users.theme_preference`
  column stores each user's choice so it follows them across browsers and
  devices.
- New `PATCH /api/me/preferences` endpoint.
- `theme_preference` is now included in `GET /api/me`.

### Changed

- Theme picker UI replaced with a card grid that previews each theme's color
  swatches.

## [1.3.x and earlier]

Pre-versioning. See `git log` for history.

[Unreleased]: https://github.com/mkolakowski/walletweather/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.7.0
[1.6.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.6.0
[1.5.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.5.0
[1.4.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.4.0
