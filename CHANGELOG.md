# Changelog

All notable changes to WalletWeather are recorded in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Three independent version numbers are tracked:

- **App version** (`APP_VERSION` in `apps/server/app/main.py`) — the user-facing
  application version shown in the UI and exposed via `/api/version`.
- **Web version** (`WEB_VERSION` in `apps/web/index.html`) — the SPA
  version, bumped for frontend-only changes.
- **Schema version** (`SCHEMA_VERSION` in `apps/server/app/db.py`) — the database
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

App version: **1.40.0** · Web version: **1.62.1** · Schema version: **15**

### Added

- Tags now work on repeating lines in Forecast. The Tags picker on the new line
  stays available when you set Repeats, and the tags are saved with the
  repeating item. Its upcoming lines show those tags, opening one shows a Tags
  picker filled with them, and saving it keeps or changes them (clear them all
  and the line is saved with none).

## [1.40.0] — 2026-11-15

App version: **1.40.0** · Web version: **1.61.9** · Schema version: **15**

### Added

- Bills and income items can carry tags. Projected lines on Forecast show
  their item's tags, and a line saved from an item starts with them; changing
  an item's tags later leaves lines already saved as they are. This release
  adds it to the API (`tag_ids` when creating or editing a recurring item,
  `tags` in the recurring lists and on projected forecast rows); the tag
  pickers on Forecast and Bills & income follow in the next releases.

### Database

- New `recurring_tags` table linking recurring items to tags (schema 15). It's
  created automatically on start; nothing to do.

## [1.39.1] — 2026-11-15

App version: **1.39.1** · Web version: **1.61.9** · Schema version: **14**

### Changed

- The Repeats dropdown on Forecast's new line is only as wide as its longest
  choice, Bi-weekly, instead of stretching across the space under its heading.

## [1.39.0] — 2026-11-14

App version: **1.39.0** · Web version: **1.61.8** · Schema version: **14**

### Added

- Forecast's new line has a Tags picker again, next to Repeats. Tags are saved
  with one-off lines; the picker is greyed out while Repeats is set, since
  recurring items don't carry tags. While the line is open, the balance
  headings above read "Repeats" and "Tags".

## [1.38.0] — 2026-11-14

App version: **1.38.0** · Web version: **1.61.7** · Schema version: **14**

### Changed

- **Breaking:** Forecast's new line has one Repeats dropdown (None, Weekly,
  Bi-weekly, Monthly) in place of the Repeats checkbox, Every and Day. Pick
  anything but None and the date column becomes "Start date": Monthly repeats
  on that date's day of the month, Weekly and Bi-weekly count from it. A
  start date is now needed for Monthly too.
- **Breaking:** Bills & income's add form works the same way: a Repeats
  dropdown (Weekly, Bi-weekly, Monthly) and a Start date that starts as
  today, with no Day of month box. Monthly repeats on the start date's day of
  the month, and a start date is now needed for every new item. Editing an
  existing item is unchanged, Day of month included.

## [1.37.5] — 2026-11-14

App version: **1.37.5** · Web version: **1.61.5** · Schema version: **14**

### Changed

- While Repeats is ticked on Forecast's new line, more column headings now
  name what the fields hold: Forecast date reads "Starts" (or "Starts
  (optional)" when Every is Month), Forecast amt reads "Amount", and Actual
  amt is blank since it isn't used. They go back when you untick Repeats or
  close the line, and the columns don't move when they change.

## [1.37.4] — 2026-11-14

App version: **1.37.4** · Web version: **1.61.4** · Schema version: **14**

### Changed

- While Repeats is ticked on Forecast's new line, the Actual date column
  heading reads "Ends", naming the end date field under it. It goes back to
  "Actual date" when you untick Repeats or close the line.

## [1.37.3] — 2026-11-14

App version: **1.37.3** · Web version: **1.61.3** · Schema version: **14**

### Changed

- When you tick Repeats on Forecast's new line, the Ends date now takes the
  place of the Actual date field (an actual date doesn't apply to a repeating
  item), marked "Ends". Repeats, Every and Day then fit on one line, so the
  row no longer grows taller when Every is Month.

## [1.37.2] — 2026-11-14

App version: **1.37.2** · Web version: **1.61.2** · Schema version: **14**

### Fixed

- Adding a line on Forecast no longer makes the table's columns jump around
  when you tick Repeats or switch Every to or from Month: the columns keep
  their widths, and the repeat fields wrap inside their space when needed.

## [1.37.1] — 2026-11-14

App version: **1.37.1** · Web version: **1.61.1** · Schema version: **14**

### Fixed

- The new Add transaction line on Forecast showed stray "/" marks under the
  forecast date, the forecast amount and the notes, pushing those fields out
  of line. They're gone.

## [1.37.0] — 2026-11-14

App version: **1.37.0** · Web version: **1.61.0** · Schema version: **14**

### Changed

- **Breaking: "+ Add transaction" opens a new line at the top of the Forecast
  table** instead of a separate form above it. Each field sits under its
  column: Description, Forecast date, Actual date, Category, Forecast amt,
  Actual amt and Notes. Amounts are signed like the table, so type a minus
  for an expense. Fill in the forecast date and amount for a planned line,
  or the actual ones for a cleared line. Tick "Repeats" to make it a
  recurring item; the forecast date becomes its start date and the forecast
  amount its amount, with the frequency, day of month and end date beside
  it. "+ Another" saves and keeps the line open with the same dates and
  category. Enter saves and Escape cancels.
- The "↻ Add recurring" button on Forecast is gone, since "Repeats" on the
  new line does the same.

## [1.36.0] — 2026-11-14

App version: **1.36.0** · Web version: **1.60.0** · Schema version: **14**

### Changed

- **Forecast's account actions sit with the table's controls.** The "Account
  actions" panel above the summary cards is gone; "+ Add transaction",
  "⇄ Transfer" and "⬆ Import CSV" are now at the start of the row of table
  controls (View, Month, Spreadsheet mode, Per page), under the cards.

### Added

- **"↻ Add recurring" on Forecast** opens Bills & income on that account with
  the add form already open.
- **A ⋯ menu for the account on Forecast** with Rename (owners), Archive
  (owners and editors) and "Export a backup of this account", which until now
  were only in Settings → Accounts and Backup.

## [1.35.0] — 2026-11-14

App version: **1.35.0** · Web version: **1.59.0** · Schema version: **14**

### Changed

- **Tables wrap instead of scrolling sideways.** Whenever a table is wider than
  the space it has, at any window size, its header hides and each row's
  cells flow onto as many lines as they need, each with a small label naming
  its column. Wide windows look as before. While a table is wrapped, the sort
  buttons appear above Forecast and Bills & income, since the clickable
  column headers are hidden. Forecast's phone layout is unchanged.

### Changed

- **Breaking: Bills & income is laid out and works like the Forecast page.**
  - Account tabs across the top (with balances), starting with All accounts,
    replace the Account dropdown.
  - An actions panel at the top holds "+ Add recurring"; the totals sit under
    it, and the add form opens as its own panel.
  - The table looks like Forecast's, with column lines and compact rows. Its
    controls (Active / Archived, Spreadsheet mode and Per page) sit above it,
    and Per page starts on "Auto", which fits as many rows as your window
    holds; "All" is new too. On a phone, sort buttons sit above the table.
  - **Spreadsheet mode**: every row you can edit opens at once; a row saves
    shortly after you leave it and the totals refresh once you stop typing.

### Changed

- **Breaking: the Transactions page is now Forecast's "All accounts" tab.**
  Forecast's row of account tabs starts with All accounts, which holds
  everything the Transactions page had: searching all your accounts, tagging
  many results at once, and the recent transfers list where you edit, delete
  or make a transfer. The Transactions button is gone from the top bar and
  the phone's More menu. Old links to `#transactions` open the new tab, and
  editing a transfer from it brings you back to it.

### Changed

- **Every page uses the full width of your window**, the way Forecast already
  did: Dashboard, Net Worth, Bills & income, Calendar, Reports, Settings,
  Admin, Import and Transfer no longer sit in a narrower column in the middle
  on a wide screen. Phones are unchanged.

## [1.32.5] — 2026-11-14

App version: **1.32.5** · Web version: **1.56.5** · Schema version: **14**

### Changed

- In an open line, the up and down arrows on number fields (amounts, day of
  month) are on the left of the field instead of the right. The arrow keys
  still work while you're in the field.
- On Forecast and Bills & income, the Notes field in an open line stretches
  all the way to the Save button.

## [1.32.4] — 2026-11-14

App version: **1.32.4** · Web version: **1.56.4** · Schema version: **14**

### Changed

- Amounts you type into an open line line up on the right, like the column.
- On the Forecast page there's no column line between Notes and the ✎ any
  more, and a long note uses the empty space up to the ✎ before it's cut off.
  An open line looks as it did.

## [1.32.3] — 2026-11-14

App version: **1.32.3** · Web version: **1.56.3** · Schema version: **14**

### Changed

- **An open line is the same height as the others** on Forecast, Transactions
  and Bills & income (on a computer). The small labels above each field are
  gone, since every field sits under its column heading; hover over a field
  to see its name. Lines on the Forecast page are a few pixels taller so the
  buttons fit. On a phone the open line still shows its labels.
- Save, Delete and Cancel sit at the right edge of the row.

## [1.32.2] — 2026-11-14

App version: **1.32.2** · Web version: **1.56.2** · Schema version: **14**

### Fixed

- On the Forecast page, the date and amount columns were too narrow while a
  line was open, so dates showed as "11/01/2" and amounts were cut off. They
  now get the width they need.

### Changed

- The Notes column is wider on Forecast and Bills & income; a long note ends
  in "…" and shows in full when you hover over it.
- The ✎ button sits at the right end of each row.

## [1.32.1] — 2026-11-14

App version: **1.32.1** · Web version: **1.56.1** · Schema version: **14**

### Changed

- **Columns stay put when you open a line.** On Forecast, Transactions and
  Bills & income the columns are now always as wide as editing needs, so
  opening a line for editing no longer makes them jump. The last column is
  always wide enough for Save, Delete and Cancel, so in the normal view its ✎
  has some room around it. While a line is open, Transactions shows the
  actual date under Account, and Bills & income shows the type under Account,
  the day of month under Monthly and the start date under Yearly; the
  "Restore deleted dates" link sits under the description.

## [1.32.0] — 2026-11-14

App version: **1.32.0** · Web version: **1.56.0** · Schema version: **14**

### Changed

- **An open line lines up with the table's columns.** On Forecast,
  Transactions and Bills & income, each field you edit now sits under its own
  column heading, labelled, all on one line, so an open line is about as tall
  as a field. Columns that only show calculated figures hold the extra fields
  while you edit: on Forecast, Tags sit under the difference and balance
  columns; on Bills & income, Day of month and Start date sit under Monthly
  and Yearly; on Transactions, both dates share the Date column, Notes shares
  the Description column and the actual amount sits under Status.
- Save, Delete and Cancel are taller and centered in their column.

## [1.31.2] — 2026-11-14

App version: **1.31.2** · Web version: **1.55.2** · Schema version: **14**

### Changed

- An open line is shorter again: the heading line naming what you're editing
  and its balances is gone, and Save, Delete and Cancel sit at the end of the
  fields instead.
- The Tags field is narrower, one column like the others. If you have no tags
  yet it simply says "No tags"; the pointer to Settings, where you can add
  some, appears when you open it.

## [1.31.1] — 2026-11-14

App version: **1.31.1** · Web version: **1.55.1** · Schema version: **14**

### Changed

- When a line is open for editing on Forecast, Transactions or Bills &
  income, its buttons now read Save, Delete, Cancel: Cancel and Delete have
  swapped places.

## [1.31.0] — 2026-11-14

App version: **1.31.0** · Web version: **1.55.0** · Schema version: **14**

### Changed

- **Tags are picked from a dropdown.** In the Forecast and Transactions line
  editors, a Tags button shows the tags already chosen; pressing it opens a
  list with a checkbox for each tag, so you can tick as many as you like. A
  filter box at the top narrows a long list. Clicking elsewhere or pressing
  Escape closes it. This replaces the row of every tag as clickable pills.
- **An open line takes less space.** Save, Cancel and Delete sit on the same
  line as the heading instead of stacked down the side, tags are one more
  field among the others, and the spacing is tighter, so on a normal-width
  window an open line is the heading plus about two rows of fields.

## [1.30.0] — 2026-11-14

App version: **1.30.0** · Web version: **1.54.0** · Schema version: **14**

### Changed

- **Editing a line looks the same everywhere, and every field lines up.** On
  Forecast, Transactions and Bills & income, a line you open for editing
  becomes a labelled form across the table: description, category, dates,
  amounts and notes in tidy rows, tags on their own row, and Save, Cancel and
  Delete in the same place on all three pages. Before, Forecast's fields sat
  at different heights in their columns, Notes had no label and Transactions
  stacked two fields to a cell. Enter saves and Escape cancels on all three
  (new on Transactions), and a mistake is shown under the fields with the
  cursor put in the one to fix. A projected recurring date says that saving
  records it as a real transaction. Spreadsheet mode still edits in the
  cells, as before.

## [1.29.1] — 2026-11-14

App version: **1.29.1** · Web version: **1.53.1** · Schema version: **14**

### Fixed

- In the evening (from 7 PM Eastern, earlier further west), several date
  fields filled in tomorrow's date instead of today's: the date on Add
  transaction, Transfer money, and a new account's "As of" date, and the date
  in a downloaded backup's file name. They now use the date on your device.

## [1.29.0] — 2026-11-14

App version: **1.29.0** · Web version: **1.53.0** · Schema version: **14**

### Changed

- **"Expense" and "Income" everywhere.** The app used three pairs of words for
  money going out and coming in (Withdraw/Deposit, Spending/Income,
  Out/In). It now says Expense and Income on the add and edit forms, in the
  filters on Calendar, Transactions and Reports, in the Forecast and Reports
  totals, on the Dashboard charts and in the help text. Nothing stored
  changes, and saved reports and imports work as before.
- **Report filters are checkboxes.** Accounts, Categories and Tags on the
  Reports page are lists you tick, instead of boxes that needed Cmd- or
  Ctrl-click to pick more than one.
- **Breaking: the admin backup hour is in your own time.** Admin → System
  backups shows and sets the hour in the time zone of the browser you're
  using; it's still stored in UTC, and the note under the field says which
  UTC hour that is. If you had read the old field as UTC, the number shown
  will now differ, but the schedule itself hasn't moved. "Last run" is shown
  in your time too.
- **Easier to use with a keyboard or a screen reader.** The account tabs on
  the Forecast page can be reached with Tab and switched with the arrow keys,
  Enter or Space. Every form field's label is tied to its field, so screen
  readers announce it and clicking the label puts the cursor in the field. A
  clear outline shows which control has keyboard focus.

## [1.28.0] — 2026-11-14

App version: **1.28.0** · Web version: **1.52.0** · Schema version: **14**

### Changed

- **Breaking: on a phone, pages are reached from a bar at the bottom of the
  screen.** It holds Dashboard, Forecast, Bills & income and Calendar, plus
  More, which opens Net Worth, Transactions, Reports, Settings, Admin (for
  admins) and Log out. The row of buttons at the top, which wrapped onto
  several lines on a phone, now shows only on wider screens.
- **Breaking: Settings is split into tabs**: Appearance, Accounts, Categories
  & tags, Budgets, Sharing, Backup and Your account (Delete my account and the
  Important notice). One shows at a time. Each has its own address, such as
  `#settings/budgets`, so you can bookmark it, and the browser's Back button
  steps through the tabs you visited. Settings remembers the last tab you had
  open. The Dashboard's Edit button opens the Appearance tab.
- **Import and Transfer money have their own addresses** (`#import`,
  `#transfer`, and `#transfer/<number>` while editing one), so refreshing the
  page or pressing Back keeps you where you were instead of dropping you on
  the Dashboard.

### Fixed

- Opening a transfer's address directly (for example after a refresh) now
  loads that transfer before showing it. Without this the form would have
  come up blank while still set to save over that transfer.

## [1.27.0] — 2026-11-14

App version: **1.27.0** · Web version: **1.51.0** · Schema version: **14**

### Changed

- **No more browser pop-ups.** Confirmations, messages and the few places that
  asked you to type something now appear inside the app in its own style.
  - Before anything is deleted or replaced, a dialog says what will be lost.
    Its Delete (or Replace, Restore, Clear) button is red and last, and
    Cancel starts selected, so pressing Enter never deletes by accident.
    Escape cancels.
  - Saves, failures and results (an import, a restore, a password reset)
    show as a short message at the bottom of the screen.
  - Renaming an account or a tag, "Save as" for a report and an admin's
    password reset use a small form in the app instead of the browser's
    text box. A password that's too short is pointed out before anything is
    sent.
- **Errors read as sentences.** When the server refuses something, you see its
  reason ("A category with that name already exists.") instead of raw text
  such as `{"detail": …}`, and a lost connection says so.
- **Mistakes on the Add transaction and recurring edit forms are shown next to
  the form**, with the cursor put in the field that needs fixing.

## [1.26.0] — 2026-11-14

App version: **1.26.0** · Web version: **1.50.0** · Schema version: **14**

### Added

- **A Transactions page** in the top bar. It holds the search across all your
  accounts (text, account, category, tag, kind, dates and amounts), tagging
  many results at once, and the list of recent transfers with Edit and Delete,
  plus a "Transfer money" button. These had been unreachable since version
  1.32.0 of the web client, which removed the switch that opened them, and the
  transfers list was the only place to edit a transfer. Editing a transfer from
  here brings you back here afterwards.
- **"Save and add another"** on the Forecast page's Add transaction form. It
  saves and keeps the form open with the same date, type, category and status,
  ready for the next entry.

### Changed

- **Each line on the Forecast page has an ✎ button** that opens it for editing,
  with Delete inside the opened line. Double-click still works, and on a phone
  tapping a line still opens it. Accounts shared with you read-only show no
  button.

## [1.25.0] — 2026-11-14

App version: **1.25.0** · Web version: **1.49.0** · Schema version: **14**

### Changed

- **Breaking: the Subscriptions page is now "Bills & income", with one list
  instead of two.** Every recurring bill and income on the accounts you can
  see is in a single table with an Account column, and you edit any of them
  in place (✎) without leaving the page. An account filter at the top shows
  one account or all of them. A new "+ Add recurring" button adds a bill or
  income right there (adding one from the Forecast page's "Make this
  recurring" still works). The totals now show bills, income and what's left
  over per month, each with its yearly figure, for whichever accounts the
  filter shows. The old "Start date for all monthly recurring" bar is gone:
  press "Select all monthly", then set the start date in the bulk-edit bar.
  The table shows 20 rows a page by default. Rows on accounts shared with you
  read-only are marked "read only" and can't be selected or edited.
  Bookmarks to `#subscriptions` still open the page.
- The Subscriptions page's totals were showing as plain text without their
  card styling; the new totals use the same cards as the Forecast page.

## [1.24.1] — 2026-11-14

App version: **1.24.1** · Web version: **1.48.1** · Schema version: **14**

### Added

- **Delete your own account.** Settings has a new "Delete my account" section.
  It lists what will be deleted (your sign-in, your accounts and everything in
  them, your categories, tags, budgets and saved reports), points you at the
  backup export first, and asks for your password (or, if you only sign in
  with Google, your email address typed out). Deleting is refused while you
  are the only owner of an account other people can see: the section names
  those accounts, and you either make someone else an owner under Permissions
  (the account stays with them) or remove the others' access first. An account
  that has another owner is never deleted with you. Until now only an admin
  could delete a user. The API is `GET /api/me/deletion-check` and
  `DELETE /api/me`. The demo user can't be deleted.

- **An "Important notice" everyone agrees to once.** After signing in, each
  person sees a short notice before anything else: WalletWeather is a planning
  tool, its forecasts are estimates, it gives no financial, tax, legal or
  investment advice, and it comes with no warranty. Pressing "I understand and
  agree" opens the app, and the notice doesn't come back. People who already
  use an instance see it once after the update; the demo user never does. The
  same text is at the bottom of Settings, with the date you agreed to it, and
  in the README's new Disclaimer section. `GET /api/me` now reports
  `notice_required` and `notice_acknowledged_at`, and a new
  `POST /api/me/acknowledge-notice` records the agreement. The API itself
  isn't blocked before the notice is agreed to, only the web app.
- **Policy documents.** The repository now has `SECURITY.md` (how to report a
  security problem privately), `PRIVACY.md` (what an instance stores, and what
  running one for other people means), `THIRD_PARTY_NOTICES.md` (the licences
  of the software shipped in the container image) and `CONTRIBUTING.md`. The
  README's Security Notes now say what "Encryption at rest" does and doesn't
  cover.

### Fixed

- **Breaking:** **An admin deleting a user no longer takes other people's
  accounts with them.** Deleting a user from the Admin panel used to delete every account
  that user had created, including ones shared with, or co-owned by, other
  people, without saying so. Now an account that has another owner is kept,
  and the deletion is refused, naming the accounts, while the user is the
  only owner of an account other people can see. Make someone else an owner
  of each, or remove the other people's access, under the Admin panel's
  All permissions, then delete the user. These are the same rules as
  deleting your own account.

### Changed

- **Sample data uses generic merchant names.** Demo mode, the downloadable
  import sample CSV and the example in the Import page's paste box now say
  "Streaming service", "Grocery store", "Coffee shop" and the like instead of
  real company names. A demo instance resets its sample data once after the
  update to pick up the new names; nothing changes for your own data.

### Security

- **Licence check on every test run.** The tests now fail if a dependency
  under a copyleft licence (GPL, LGPL, AGPL, MPL and similar), or with no
  licence stated, is added without being reviewed and listed
  (`apps/server/tests/test_licences.py`). The two already in use, `psycopg`
  and `certifi`, are listed in `THIRD_PARTY_NOTICES.md`.

### Database

- **Schema 14:** a new `notice_ack_at` column on `users` records when each
  person agreed to the Important notice. It is added automatically on start
  and left empty for existing users, so they are asked once.

## [1.22.2] — 2026-11-14

App version: **1.22.2** · Web version: **1.46.2** · Schema version: **13**

### Added

- **Sort buttons and a stacked spreadsheet mode on the phone Forecast page.**
  The phone layout hides the table header, so a row of sort buttons (Date,
  Name, Category, Amount, Balance) now sits above the lines; tap one to sort
  by it and tap it again to flip the direction, just like the column headers
  on desktop. Spreadsheet mode on a phone now shows every line as the same
  stacked form as tap / double-tap editing (labelled boxes, two per row, plus
  the line's forecast and actual balance) instead of a grid you had to scroll
  sideways. On a phone, tapping an open line (anywhere but its boxes and
  buttons) closes it again if nothing in it was changed; with unsaved changes
  it stays open. The Forecast 🗑 delete buttons now have a red outline (on
  desktop too). Frontend only.

- **Phone-friendly Forecast page.** On screens 768px wide or narrower, each
  forecast line is a card (description and Forecast / Actual amount on top,
  the date pair under it, then category with the balance pair, any non-zero Δ
  and notes) instead of a 12-column table that had to be scrolled sideways.
  Tapping a card opens it as a stacked edit form with large ✓ / 🗑 / ✕
  buttons. The View / Month / Year controls fit in two rows, the summary
  cards are tighter, account tabs scroll sideways, "Auto (fit window)" shows
  every row (the page scrolls), and dropdowns/inputs use 16px text so iOS
  doesn't zoom in on them. Spreadsheet mode keeps its scrolling grid. The
  pagination Prev / Next buttons now hide when there is only one page.
  Frontend only.

- **Previous / next month buttons on the Forecast page.** "Prev" and "Next" buttons sit
  around the Month and Year dropdowns (Month view) and step the forecast one
  month back or forward, rolling over the year at December/January (and adding
  that year to the Year dropdown if needed). The buttons are labelled "Prev"
  and "Next". Frontend only.

- **Double-click a Forecast line to edit it.** In the read view, double-clicking
  a row turns that one line into the same compact inline inputs spreadsheet mode
  uses (plus the tag picker for saved transactions), highlighted. A ✓ Save
  button sits next to the 🗑 delete button (and a ✕ cancel): Save, or Enter,
  writes the line and closes it out; Esc or ✕ discards the changes. Saving
  warns about an empty description / missing amount or a server error instead
  of failing silently. This replaces the old ✎ editor, whose button was removed
  from the read view.

- **"Current month" button on the Forecast page.** Next to the Year dropdown
  (Month view), one click jumps the Month/Year selectors back to the current
  month and reloads the forecast. It's disabled while the selectors already
  show the current month. Frontend only.

- **Outgoing / incoming cards in the Forecast summary.** "Forecast out / in"
  and "Actual out / in" show how much leaves and enters the account over the
  displayed window (the month in Month view), with the net underneath. They
  total every row in the window — transfers included — so Opening balance +
  incoming − outgoing equals the matching Forecast end / Actual end card.
  Actual uses each row's actual amount (falling back to its forecast amount,
  as the Actual bal column does). Frontend only.

- **Recurring transactions now live at the top of the Subscriptions page.**
  The panel (add/edit/pause/delete, bulk edit, Active/Archived) moved from
  the Forecast page to above the Subscriptions table, with an Account
  selector at its top because the panel is per-account. The selector shares
  the selected account with the Forecast page's account tabs, and clicking an
  account name in the Subscriptions table now switches the panel to that
  account instead of jumping to the Forecast page.

- **Even weeks of the month are shaded in the Forecast table.** Rows in the
  2nd, 4th and 6th Sunday-to-Saturday week of their month get a slightly
  lighter cell shade (a faint overlay, so it also reads as a subtle tint on
  light themes), giving a quiet separator between weeks. It applies whenever
  the table is sorted by Forecast date or Actual date
  (`_weekOfMonth()` in `backend/static/index.html`).

- **Current balance on the Forecast page.** The account's current balance
  (starting balance plus every cleared transaction dated today or earlier —
  the same figure `GET /api/accounts` already returned) now appears in
  three places: a "Current balance" stat at the start of the Forecast
  summary, a "Balance" figure in the Today bar, and next to each account's
  name in the account tabs. It is independent of the month/range being
  viewed. `GET /api/accounts/{id}/forecast` gains a `current_balance` field
  so it is fresh on every load; the active tab updates whenever the forecast
  reloads.

- **"Today" bar in the Forecast table.** A highlighted bar now sits between
  the rows at today's date, with a label ("Today · day 14 of 31" in Month
  view), a progress fill and a percentage so you can see at a glance how far
  through the month the forecast is. It shows only when sorted by Forecast
  or Actual date (either direction) and today falls inside the displayed window; with
  pagination it appears on the page where the boundary lands. Frontend only
  (`_todayMarkerRow()` in `backend/static/index.html`).

- **Delete recurring occurrences from the forecast.** Every forecast row
  now has a 🗑 button next to ✎ (it used to be reachable only inside the
  row editor, and only for saved transactions). On a projected recurring
  row it removes just that date — the recurring transaction keeps all
  its other dates — via new `POST /api/recurring/{id}/skip`. Deleted
  dates can be brought back with the "N deleted dates · Restore" link in
  the recurring transaction's edit row (new
  `DELETE /api/recurring/{id}/skips`). `GET /api/accounts/{id}/recurring`
  rows gain `skipped_count`, and backups export/restore each template's
  `skipped_dates`.

- **Set the start date on every monthly recurring transaction at once.**
  The Recurring Transactions panel (Active view, editable accounts) has
  a new "Start date for all N monthly recurring" control with "Apply to
  all monthly" and "Clear from all monthly" buttons. It goes through
  `POST /api/recurring/bulk-update` and leaves weekly/biweekly rows
  alone.

- **Bulk editing for recurring transactions.** The Recurring
  Transactions table on the Forecast page now has row checkboxes and a
  "select all on this page" box. Selecting rows opens a bulk bar to
  change category (or clear it), amount (each row keeps its sign, so
  expenses stay expenses), day of month (monthly rows only), start/anchor
  date, or end date across all of them at once. Blank fields are left
  unchanged, and a confirmation lists exactly what will change. "Delete
  selected" removes the templates in one go. Backed by new
  `POST /api/recurring/bulk-update` and `POST /api/recurring/bulk-delete`
  endpoints, which skip rows on accounts you can only view.

- **Anchor (start) date for monthly recurring transactions.** Monthly
  templates can now carry an optional start date — set it in the
  "Start date (optional)" field on the add form, or under the
  day-of-month input in the Recurring Transactions edit row. No
  occurrences are projected before that date (`_occurrences()` in
  `backend/app/forecast.py`); leaving it blank keeps the previous
  behavior. Reuses the existing `recurring_transactions.anchor_date`
  column, so no migration is needed. Monthly rows with a start date
  display as "Monthly · day N · from YYYY-MM-DD".

### Changed

- **The web service now reports whether it's healthy.** `docker compose ps`
  shows `web` as `healthy` once the app answers on `/api/version`, and
  `unhealthy` if it stops answering for about a minute and a half (three
  failed checks, 30 seconds apart). The check lives in `docker-compose.yml`,
  so pull the new file to get it; the image itself is unchanged.

- **Container images are built only when a release is published.** The
  "Build and push to GHCR" workflow (`.github/workflows/build-and-push.yml`)
  used to run on every push to `main`. It now runs when a GitHub Release is
  published, or when started by hand from the Actions tab. So
  `ghcr.io/mkolakowski/walletweather:latest` always points at the newest
  full release instead of whatever was merged last (a pre-release doesn't
  move it), and each image is still tagged with the release's version and
  the web client version.

- **The repo is now laid out as `apps/` for room to add mobile apps.** The
  API server moved from `backend/` to `apps/server/`, the web client from
  `backend/static/` to `apps/web/`, and empty `apps/ios/` and
  `apps/android/` folders (each with a README) are ready for native apps.
  The container image is now built from the repo root
  (`docker build -f apps/server/Dockerfile .`) and is published to GHCR with
  the same name and tags as before. If you build from source with your own
  compose file, change `build: ./backend` to `context: .` plus
  `dockerfile: apps/server/Dockerfile`. The server finds
  the web client in `apps/web` (override with the `WEB_DIR` env var).

- **Outlined ✕ in the Forecast line editor.** The ✕ (cancel) button next to
  ✓ and 🗑 now has a clearly visible outline, like the red one on 🗑.
  Frontend only.

- **GitHub Actions bumped to their Node 24 majors.** The GHCR workflow now uses
  `actions/checkout@v7`, `docker/login-action@v4`, `docker/metadata-action@v6`,
  `docker/setup-buildx-action@v4` and `docker/build-push-action@v7`, which
  clears the "Node.js 20 is deprecated" warning on every build.

- **GHCR images are tagged with the web client version.** The "Build and push
  to GHCR" workflow (`.github/workflows/build-and-push.yml`) reads
  `WEB_VERSION` from `backend/static/index.html` and adds it as an image tag
  (e.g. `ghcr.io/mkolakowski/walletweather:1.45.0`) on every build, next to the
  existing branch, semver, sha and `latest` tags. The build fails if
  `WEB_VERSION` can't be found.

- **Forecast table read view: "/" separators, no row buttons.** A "/" now sits
  between the grouped Forecast/Actual columns (date, amount, balance) in the
  normal view (not in spreadsheet mode). The edit (✎) and delete (🗑) buttons
  were removed from the normal view and its actions column is hidden — rows are
  edited and deleted in Spreadsheet mode, which keeps its delete button. The
  one-row editor (`startEditForecastRow`) is left in the code but no longer has
  an entry point.
- **The Spreadsheet mode button has a visible border.**

- **Paired Forecast table columns are grouped closer together.** Forecast date
  / Actual date, Forecast amt / Actual amt and Forecast bal / Actual bal now
  sit next to each other with no divider and less padding between them, and
  they shrink to fit their contents (extra width goes to Description, Category
  and Notes). Applies in normal and spreadsheet mode.

- **Spreadsheet mode amounts are flush right.** The numbers in the Forecast amt
  and Actual amt boxes now sit against the right edge of the box: the
  number-input spinner that reserved space there is hidden (↑/↓ already move
  between rows) and the right padding is smaller.

- **Spreadsheet mode layout.** In the Forecast table's spreadsheet mode, the
  Forecast amt and Actual amt boxes now sit at the right side of their columns
  with right-aligned numbers, the Category dropdown is wider (150px instead of
  90px), and the Description box is much wider (fills its column, at least
  260px instead of 90px).

- **Forecast controls row rearranged.** View / Month / Year now sit close
  together on the left with each label beside its dropdown (instead of above
  it), "Spreadsheet mode" is centred in the row, and the pagination controls
  (Per page, range, Prev/Next) are pinned to the far right. The row wraps on
  narrow screens.
- **The Current balance card in the Forecast summary is highlighted** with an
  accent outline and soft glow.

- **The Forecast page is now nearly full-width.** It drops the 1380px content
  cap and uses 40px side gutters (about a finger width from the screen edge)
  so the table can use wide screens. Other pages keep their current width, and
  phones keep their existing narrow padding.

- **Forecast pagination moved to the top of the table.** The "Per page"
  selector, the "1–18 of 60" range and the Prev / Page / Next controls now sit
  in the same row as View / Month / Year / Spreadsheet mode instead of below
  the table, so the table can use that space for more rows in Auto mode.

- **Forecast page declutter.** Removed the "Transactions" heading, the
  "This account / Search all accounts" toggle and the "Forecast" panel title.
  The cross-account search view (`#subviewSearch`) still exists in
  `backend/static/index.html` but no longer has an entry point.
- **The Forecast table's rows-per-page now defaults to "Auto (fit window)".**
  It shows as many rows as fit between the top of the table and the bottom of
  the browser window (using the measured row height, and re-fitting when the
  window is resized, with a minimum of 5). The selector also gains an "All"
  option alongside 10 / 25 / 50 / 100.

- **Forecast table cells are packed closer together** (tighter cell padding
  and smaller row buttons), so more rows fit on screen.

- **"+ Add transaction" moved into the Account actions bar.** On the
  Forecast page the button now sits first in Account actions (next to
  Transfer money / Import CSV), and the separate "Add transaction" bar is
  gone; clicking the button opens the add form in its own panel, which
  closes on Save/Cancel.
- **The Forecast table shows 25 rows per page by default** (was 10).

- **The "Forecast page layout" setting and the week divider rows are gone.**
  The Recurring transactions panel no longer lives on the Forecast page, so
  Settings → Appearance no longer offers the above/below option, and the
  "Week of …" divider rows were replaced by the even-week shading described
  above.

- **The Forecast table now sorts by Actual date by default** (it used to
  sort by Forecast date). The Today bar works when sorted by either date
  column.

- **Recurring edit row: Save, Cancel and Delete now stack in a column on
  the far right of the editor**, lined up with the first row of inputs,
  instead of sitting in a horizontal row along the bottom. The "N deleted
  dates · Restore" link stays under the fields, and on a phone the column
  drops below the fields (still stacked, right-aligned).
- **Streamlined the Recurring transactions edit row.** Editing a row now
  opens one labelled form panel — Description, Category, Type
  (Withdraw/Deposit) and Amount on the first line; Frequency, Day of
  month, Start date, Ends and Notes on the second; Save / Cancel /
  Delete below — instead of a control squeezed into every table column.
  The amount is a plain positive number with a Withdraw/Deposit choice
  (like the add form) rather than a signed value such as `-1650`. Enter
  saves, Escape cancels, and the description is focused when the editor
  opens. The greyed-out Monthly/Yearly cells in the editor are gone, and
  the panel fits phone screens without scrolling sideways.

- **Weekly and biweekly recurring transactions now start on their
  anchor date** (labeled "Start date" in the UI). Previously the
  schedule also ran backwards from the anchor, so a biweekly deposit
  showed up on dates before the start date you gave it. The anchor still
  sets the every-1/2-week cadence.

### Fixed

- **Current balance no longer jumps ahead to tomorrow in the evening.** The
  Current balance on the Forecast page, the balance on each account tab and
  the Today bar count every line dated today or earlier. "Today" came from
  the server's clock, which is usually UTC, so from about 7–8 PM US Eastern
  tomorrow's lines were counted too. The web client now sends your own date
  (`?today=` on `GET /api/accounts` and the forecast call), and the balance
  goes by it. Calls without it, from scripts for example, still use the
  server's date.

- **Actual bal follows actual dates.** The Forecast table's Actual bal (and
  Δ Bal) running total now adds lines up in actual-date order instead of
  planned-date order (`backend/app/forecast.py` `build_forecast`). A line that
  cleared later than planned now shows the balance as of the day it actually
  cleared, so the column reads in order when the table is sorted by actual
  date (the default, and the phone's Date sort button). The Highest / Lowest
  point cards are labelled with the actual date to match, Δ Bal compares
  each line with the plan as of that same date, and Current balance / the
  Today bar count lines by actual date so they still equal Actual bal at
  today. Forecast bal and the ending balances are unchanged.

- **Lines that clear in a different month show up in the month they cleared.**
  A cleared transaction is now listed in (and counted toward) the month of its
  actual date, not its planned date. Before, a line planned for Sep 29 that
  cleared Oct 2 was listed in September but left out of October's opening
  balance, so October's balances missed it, and a line that cleared early
  (planned Nov 2, cleared Oct 30) was counted twice in November.
  Not-yet-cleared lines still appear in their planned month.

- **Current balance and the Today-bar balance now match the Forecast table's
  Actual bal column.** They used to sum only transactions marked cleared,
  while the Actual bal column also counts rows dated up to that point that
  haven't been marked actual yet (shown muted, at their forecast amount), so a
  single past-due uncleared row made the figures disagree by its amount. Both
  now use the same calculation (`forecast.actual_balance_as_of`: starting
  balance + cleared transactions before the 1st of the month, then every row
  from the 1st through today). This also changes `current_balance` on
  `GET /api/accounts` (account tabs, transfer page). Tooltips now say it matches the
  Actual bal column.

- **Changing the Frequency while editing a recurring transaction no
  longer discards your other edits.** The editor used to re-fetch and
  rebuild the row, resetting any unsaved category, end date and day of
  month; now only the Day of month field and date label update.
- Saving a recurring transaction now checks that Day of month is 1–31 and
  shows "Could not save: …" if the server rejects the change, instead of
  doing nothing.

- Deleting a saved transaction that belonged to a recurring transaction
  no longer has the recurring projection reappear on that same date; the
  date is recorded as skipped (restorable from the edit row).
- The monthly start date was hard to find in the Recurring Transactions
  edit row: it was an unlabeled date box under the day-of-month input.
  The edit row now labels "Day of month", "Start date (optional)" and
  "Anchor date", and the frequency dropdown shows "Monthly / Biweekly /
  Weekly" instead of the raw `monthly_day` value.
- `GET /` now serves `index.html` with `Cache-Control: no-cache`, so
  browsers revalidate (a cheap 304 via the ETag) and pick up a newly
  deployed version on the next load instead of reusing a stale cached
  copy.
- Editing a weekly/biweekly recurring transaction and clearing its
  anchor date now shows the same "needs an anchor date" message as the
  add form instead of failing the save.

### Database

- Schema v13: new nullable `users.recurring_position` column (`'above'` |
  `'below'`), added automatically on startup by `init_db()`
  (`ADD COLUMN IF NOT EXISTS`). It backed a short-lived "Forecast page
  layout" setting; the Recurring transactions panel has since moved to the
  Subscriptions page, so the UI no longer reads or writes it. The column and
  the `recurring_position` field on `GET /api/me` / `PATCH /api/me/preferences`
  are kept (harmless, NULL for everyone) rather than dropped.

- Schema v12: new `recurring_skips` table (`recurring_id`, `skip_date`,
  unique together, cascades with its template). Created automatically on
  startup by `init_db()`; no manual migration needed.

## [1.20.0] — 2026-09-08

App version: **1.16.1** · Web version: **1.20.0** · Schema version: **11**

### Changed

- **Forecast table redesign.** Description is now the first column
  (was 3rd, after Forecast/Actual date). The Category pill uses the
  category's real color instead of a plain gray pill. Added vertical
  separators between columns. Applied across the read-only row, the
  single-row editor, and the spreadsheet-mode grid row alike.
- **Forecast tab's URL hash is now `#forecast`** instead of `#accounts`
  — the internal page name (`accounts`, predating the nav rename) is
  untouched, but the URL now matches what the tab is actually called.
  The old `#accounts` hash (live for one release) still resolves
  correctly so no existing link/bookmark breaks.

## [1.19.0] — 2026-09-07

App version: **1.16.1** · Web version: **1.19.0** · Schema version: **11**

### Added

- **Nav tabs update the URL hash** (`#dashboard`, `#calendar`, etc.) as
  you navigate, so a page refresh or the browser's back/forward buttons
  land back on the same tab. `import`/`transfer` are deliberately
  excluded — they're contextual sub-flows off the Forecast page that
  lean on state a cold reload won't have, not independent tabs.
- **Three forward-looking "rest of this month" views.** A new "Rest of
  this month" option on the Forecast page's View selector (today through
  month end). A new Dashboard summary widget showing the count/net of
  not-yet-cleared items before month end and the projected end-of-month
  balance across every visible account, with a link into the Forecast
  page's new range. A "Future view" toggle on the Calendar that dims
  every day cell before today so what's still coming up stands out.
  `GET /api/dashboard` cards gain `upcoming_count`/`upcoming_net` to back
  the widget.
- **Forecast page: spreadsheet-style bulk editing.** "Spreadsheet mode"
  makes every visible row always-editable — date/description/category/
  forecast+actual amount/notes — instead of toggling one row at a time.
  Tab/Shift+Tab move across a row natively; ↑/↓/Enter move up and down a
  column; pasting a multi-line block into a cell fills that column
  downward across the following rows. Each row saves ~500ms after you
  leave it via the existing PATCH/POST transaction endpoints; the
  whole-table balance refresh is debounced separately (1.2s after the
  last save) so editing one row never wipes an in-progress edit on
  another mid-paste. Tags aren't editable at this density — use the
  single-row editor or bulk-tag instead.
- **Calendar: running account balance.** `GET /api/calendar` gains a
  `daily_balances` map (single-account mode only — "All accounts" has no
  one balance to show). Calendar day cells show the selected account's
  balance at the top, and the day-detail panel shows it at the top too,
  with the in/out/net summary moved below the transaction table (was
  above it) and split into separate **in** and **out** totals instead of
  just net.
- **Transactions tab: inline editing.** Search results are no longer
  read-only — an ✎ button per row (hidden for transfer legs, which are
  still edited from the Transfer page) opens the same forecast/actual
  dual-date, dual-amount, category, tag-picker, and notes edit row
  already used on the Account/Forecast page, saving via
  `PATCH /api/transactions/{id}` with a Delete option alongside it.
  `GET /api/transactions/search` rows gain `forecast_amount` and
  `recurring_id` to support this.

### Changed

- **Recurring transactions' Frequency + When columns merged into one**
  "Frequency" column, using the same combined format Subscriptions
  already shows ("Monthly · day 5", "Biweekly · from 2026-08-30").
  Table is 9 columns now instead of 10.
- **Recurring transactions panel adopts the Subscriptions page's design**,
  scoped per-account instead of cross-account: new summary tiles (active
  subscription count / monthly cost / yearly cost, hidden in the
  Archived view) and sortable Monthly/Yearly columns, normalized the same
  way Subscriptions already does. Income rows and unrecognized cadences
  show "—" and don't count toward the tiles. Frequency now shows as
  "Monthly"/"Biweekly"/"Weekly" instead of the raw stored value.
  `GET /api/accounts/{id}/recurring` rows gain `monthly_cost`/
  `yearly_cost`; the normalization factor is now defined once and shared
  with `/api/subscriptions`, which is itself unchanged.
- **Transactions page merged into the Forecast page.** The "Transactions"
  nav tab is gone. Account actions (Transfer money / Import CSV) and
  Recurring transactions now sit above a "This account" / "Search all
  accounts" toggle on the Forecast page: "This account" is the existing
  per-account forecast table, "Search all accounts" is the cross-account
  filtered search table (inline edit + bulk-tag) that used to be its own
  page, and Recent transfers sits below it. The redundant "Managing
  account" picker is gone too — everything now drives off the same
  accounts-bar tabs the forecast table already used.
- **Forecast table column order** now groups by kind instead of
  interleaving forecast/actual: Forecast amt, Actual amt, Δ Amt,
  Forecast bal, Actual bal, Δ Bal (was Forecast amt, Forecast bal,
  Actual amt, Actual bal, Δ Amt, Δ Bal). Updated in the display row, the
  single-row editor, and the spreadsheet-mode grid row alike.
- **"Accounts" nav tab renamed to "Forecast".** It shows a selected
  account's forecast table, not account management — that's still
  Settings → Accounts. Updated cross-references to match; two turned out
  to already be stale (pointing at "the Accounts page" for the Transfer
  money button, which actually lives on the Transactions page) and are
  now fixed to just point at the button itself.

### Fixed

- **Spreadsheet mode rendered zero editable rows.** Its cell-rendering
  helper passed `forecast_amount`/`actual_amount` straight into
  `escapeAttr()`, which assumes a string — a non-zero numeric value threw
  a `TypeError` (numbers have no `.replace`), aborting the render on the
  very first row and leaving the whole table empty. Fixed by stringifying
  the value first. Found with a jsdom harness that evaluates the real
  script and drives `renderForecast()` directly, rather than guessing
  from the bug report alone.

## [1.14.0] — 2026-09-07

App version: **1.14.0** · Web version: **1.14.0** · Schema version: **11**

### Added

- **CSV import: past recurring transactions.** A row with a recognized
  `Frequency` value is now always recorded as a real actual transaction
  *and* linked (`recurring_id`) to a `RecurringTransaction` template —
  previously it created only the template, with no transaction. Rows
  sharing the same Frequency + Description (or the same optional new
  `Recurring Group` column, for a bill whose description text drifts
  between statements) are clustered into one series per import; the
  template is seeded from the group's most-recent row while every row
  keeps its own actual amount, so forecast-vs-actual still reflects price
  drift over the series (e.g. a subscription price increase). Importing
  more months of the same bill in a later CSV reuses the existing
  template (matched by frequency + its stored description) instead of
  creating a duplicate. The Import page's preview table now shows a
  "(new)" vs "(existing)" badge per recurring row, and the downloadable
  template demonstrates both a multi-month series and the Recurring
  Group override.

### Changed

- **CSV import `Frequency` column behavior.** See "past recurring
  transactions" above — a Frequency-flagged row is no longer
  template-only. The commit response's `recurring_created` now counts
  new templates only; a new `recurring_linked` field counts transactions
  attached to a template (new or reused).

### Fixed

- **Archived accounts' transactions leaking into the Transactions tab.**
  `GET /api/transactions/search` built its scope of visible accounts with
  `include_archived=True`, so an archived account's transactions kept
  showing up in the unfiltered "all accounts" search view even though the
  account picker itself already hides archived accounts. Now defaults to
  non-archived accounts only, matching the Dashboard and Accounts page.
  `/api/transfers`' Recent-transfers list intentionally still includes
  archived-account legs — a transfer already happened and still explains
  the other leg's balance history.

## [1.13.1] — 2026-09-05

App version: **1.13.1** · Web version: **1.13.1** · Schema version: **11**

### Added

- **Browser-native color-scheme signal.** Every theme now sets CSS
  `color-scheme` on `:root` (`dark` for Dark/Dracula/Nord/Synthwave/
  Forest/Monokai/Sunset, `light` for Light/Solarized/Mint), plus a
  `<meta name="color-scheme" content="dark light">` tag, so the browser
  and any dark-mode browser extension can tell the page already renders
  in a matching palette instead of trying to re-invert it.
- **CSV import: Category column.** A mapped `Category` column is now
  applied per row — matched case-insensitively against the user's
  existing categories, falling back to the chosen default category when
  the column is absent or the value doesn't match anything. Previously
  the column was auto-detected but silently discarded.
- **CSV import: Tags column.** A new optional `Tags` column
  (comma/semicolon-separated) is matched case-insensitively against the
  user's existing tags and applied to each imported transaction before
  auto-tag rules run. Unmatched names are skipped rather than
  auto-created, the same conservative policy as Category.
- **CSV import: recurring transactions.** A new optional `Frequency`
  column (`Monthly` / `Weekly` / `Biweekly`, plus common aliases) marks a
  row as a recurring transaction template instead of a one-time
  transaction — the row's date becomes the anchor date (weekly/biweekly)
  or day-of-month (monthly). An optional `End Date` column sets when the
  recurrence stops. An unrecognized, non-empty Frequency value skips the
  row rather than silently importing it as one-time. Recurring rows get
  their own duplicate check against existing templates on the account.
- **CSV import: downloadable template.** New
  `GET /api/accounts/{id}/import/template` returns a starter CSV
  (populated with the user's real category/tag names where available)
  demonstrating a one-time expense, one-time income, and a recurring
  bill. A "Download template" button/link was added to the Import page.
- **Account rename.** `PATCH /api/accounts/{id}` now accepts an optional
  `name`, restricted to the `owner` permission level (403 for `edit`-level
  users — they can still archive/unarchive). Settings → Manage accounts
  gains Rename and Delete buttons, shown only for accounts where the
  caller's level is `owner`; account delete already required `owner` and
  is otherwise unchanged.

### Changed

- CSV import preview table gains Category, Tags, and Recurs columns —
  an unmatched category or tag is flagged with a warning tooltip, and a
  recurring row shows a "↻ Monthly/Weekly/Biweekly" badge. The preview
  summary and the post-commit alert both now report the recurring count
  alongside the transaction count.
- `docker-compose.yml`'s `web` service defaults back to **Option A**
  (`build: ./backend`) instead of pulling the published
  `ghcr.io/mkolakowski/walletweather:latest` image, matching the file's
  own documented default for development/cloned-repo use.

### Fixed

- CSV-imported transaction notes are now truncated to `NOTES_MAX_LEN`
  (256 characters, extracted as a shared constant used by both
  `TransactionIn` and `RecurringIn`) instead of bypassing the length cap
  that manual create/edit has always enforced.

## [1.12.0] — 2026-05-02

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

[Unreleased]: https://github.com/mkolakowski/walletweather/compare/v1.40.0...HEAD
[1.40.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.40.0
[1.39.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.39.1
[1.39.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.39.0
[1.38.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.38.0
[1.37.5]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.5
[1.37.4]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.4
[1.37.3]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.3
[1.37.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.2
[1.37.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.1
[1.37.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.37.0
[1.36.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.36.0
[1.35.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.35.0
[1.32.5]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.5
[1.32.4]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.4
[1.32.3]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.3
[1.32.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.2
[1.32.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.1
[1.32.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.32.0
[1.31.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.31.2
[1.31.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.31.1
[1.31.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.31.0
[1.30.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.30.0
[1.29.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.29.1
[1.29.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.29.0
[1.28.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.28.0
[1.27.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.27.0
[1.26.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.26.0
[1.25.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.25.0
[1.24.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.24.1
[1.22.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.22.2
[1.20.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.20.0
[1.19.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.19.0
[1.14.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.14.0
[1.13.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.13.1
[1.12.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.12.0
[1.7.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.7.0
[1.6.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.6.0
[1.5.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.5.0
[1.4.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.4.0
