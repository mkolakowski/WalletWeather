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

When you bump any of these in source, add a matching line to this file under
the appropriate version heading. Format for each entry:

```
- <area>: <one-line description> (<your name or handle>)
```

## [Unreleased]

App version: **1.7.1** · Web version: **1.7.3**

### Added

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
