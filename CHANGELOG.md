# Changelog

All notable changes to WalletWeather are recorded in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Four independent version numbers are tracked:

- **App version** (`APP_VERSION` in `apps/server/app/main.py`) — the user-facing
  application version shown in the UI and exposed via `/api/version`.
- **Web version** (`WEB_VERSION` in `apps/web/index.html`) — the SPA
  version, bumped for frontend-only changes.
- **Schema version** (`SCHEMA_VERSION` in `apps/server/app/db.py`) — the database
  schema generation, bumped whenever a model or migration changes.
- **iOS version** (`MARKETING_VERSION` in `apps/ios/project.yml`, kept equal to
  `AppInfo.version` in `apps/ios/WalletWeatherKit`) — the iPhone app, from
  0.1.0, bumped for changes under `apps/ios`. It joins a section's version
  line from the release the app first ships in.

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

App version: **1.98.2** · Web version: **1.116.1** · Schema version: **39** · iOS version: **0.67.0**

### Added

- **iPhone: bills and accounts in the iPhone's search.** Swipe down on the Home Screen and type a bill's, paycheck's or account's name to find it; picking it opens Bills & income, or the account in Forecast, on its connection. Entries show the name and where it lives ("Bill · Checking · Home"), never an amount, and can be searched only while your iPhone is unlocked. The household on this iPhone and servers that keep Last-known numbers are included; servers set to keep Nothing and the demo aren't. Deleted bills leave the search the next time WalletWeather loads, and signing out or switching a server to Nothing removes its entries. To leave WalletWeather out of search, turn off Search under Settings → Apps → WalletWeather (iOS 0.67.0).
- **iPhone: Siri, Shortcuts and the Action button.** Two actions are ready without any setup. **Open To confirm** ("Open To confirm in WalletWeather") opens the app on the lines waiting to confirm, on the connection you're using. **What's my balance** ("What's my balance in WalletWeather") tells each account's balance on that connection, naming it and saying how old the numbers are ("as of 2 hours ago"), without opening the app. It answers only on an unlocked iPhone, asks for Face ID first while WalletWeather's lock is on, and for a server set to keep Nothing it says no numbers are kept. It reads the same summary as the widgets and never contacts your server; the privacy policy says so. Assign either to the Action button in Settings → Action Button → Shortcut (iOS 0.66.0).

### Changed

- **The bank sync guide is up to date, and the app links to it.** The guide on the project's GitHub Pages (Set up bank sync) now has a **Service pages** table with each service's own sign-in, setup and help pages (SimpleFIN Bridge, Teller, Plaid), says each service has its own card under Connect a bank, covers connecting SimpleFIN from an iPhone used on its own, and uses SimpleFIN Bridge's current address. In the web app's Settings → Bank sync and in the iPhone app, each service's links and the setup steps now point to the matching section of the guide (web 1.116.1, app 1.98.2, iOS 0.66.1).

## [1.98.1] — 2026-11-24

App version: **1.98.1** · Web version: **1.116.0** · Schema version: **39** · iOS version: **0.65.1**

Setting up bank sync is easier to follow: the steps for adding your Teller and Plaid keys link to the pages they name, and Teller, Plaid and SimpleFIN Bridge each have a card under Connect a bank, on the web and in the iPhone app. This release also carries the iPhone app's work since 0.34.0 (reminders, widgets, several servers at once, Duo layouts and more); see the iPhone entries below.

### Added

- **iPhone: reminders.** Settings → Reminders has three switches, all off until you turn them on, when the iPhone asks to allow notifications. **Bill due tomorrow** arrives at 9:00 AM the day before each bill (change the time under the switch). **Balance heading under** watches one account you pick and warns once when its forecast first goes under your amount (starting at $100) within the next 7 days, and again only after it's back above and dips again. **New bank lines to match** tells you when bank sync on this iPhone brings in lines to match. Reminders are worked out on the iPhone for the connection you're using, none for the demo or a server set to keep Nothing. Their text never shows an amount ("Rent is due tomorrow"); press and hold one to see the amount, which stays hidden while your iPhone or WalletWeather is locked. Tapping one opens Bills & income, the account in Forecast, or the Dashboard (iOS 0.65.0).
- **iPhone: widgets.** Three widgets for the Home Screen (small and medium, the small one in StandBy too) and the Lock Screen (rectangular, inline and round): **Balance** (one account's balance and the month's low), **Next bills** (the next three, with dates and amounts) and **To confirm** (how many lines wait). Each shows a connection, the one in front when you add it; press and hold the widget and choose Edit Widget to pick another connection or account. Tapping one opens that page in the app, on its connection. Amounts show as •••• while the iPhone is locked, and while WalletWeather's own lock is on. A server set to keep Nothing shows its name and "Turn on Last-known numbers to see numbers here". The widgets read a small summary the app keeps on the iPhone and never contact your server; the privacy policy says what it holds and when it's deleted (iOS 0.64.0).
- **iPhone: copy your household to a server, inside the app.** Settings → Move to a server → Copy to a server…: pick a server you're signed in to with full access, see what goes, and choose to add to what's there or replace it (Replace asks again, and is never chosen for you). No file or passphrase is needed, and this iPhone keeps its copy. Export for a server and Import a server backup are still there (iOS 0.63.0).
- **iPhone: connections at a glance.** Settings → Connections shows each connection's total today and how old it is ("as of 2 h ago"): a server's from its last-known numbers (only when it keeps them), the household on this iPhone's as of now, and the demo's sample. While the lock has the demo in front, totals are hidden like addresses (iOS 0.62.0).
- **iPhone: filter Forecast by category or tag.** A row of chips under All lines and To confirm lists the month's categories (most spending first) and tags. Choose one to see only its lines, with their count and total for the month; All puts everything back (iOS 0.61.0).
- **iPhone: open a bank's CSV in WalletWeather.** WalletWeather now shows up for a CSV in Files, Mail and the share sheet, and opens its import on that file. If WalletWeather is locked, the import waits until you unlock it (iOS 0.60.0).
- **iPhone: quick add remembers names.** As you type a name in Add transaction, names you've used in the last six months are offered with their category; tapping one fills both. When a tag rule will apply, a note says so ("Will be tagged Work"). Nothing new is kept on the iPhone (iOS 0.59.0).
- **iPhone: change a transfer.** Open a transfer and tap Change transfer: the Move money form opens filled in, and saving changes both of its lines together, with a server and for the household on this iPhone. Before, a transfer could only be deleted in the app and changed in the web app (iOS 0.58.0).
- **iPhone: bank sync on the Dashboard.** When bank sync needs something, a slim card at the top of the Dashboard says so: "3 bank lines to match" opens the lines to match, and "Northwind Bank needs reconnecting" opens Settings → Bank sync. With nothing to do, the Dashboard is as before (iOS 0.55.0).
- **iPhone: themes of your own.** Settings → Appearance → My themes: New theme starts from any look, and you choose six colours (page, card, text, accent, money in and money out) with a live preview. A line under the colours warns when a pair is hard to read (under 4.5:1); the theme still saves. Tap a theme to use it; ⋯ or a long press edits, duplicates or deletes it. Your themes' names and colours (nothing else) are kept in your own iCloud, so they reach your other iPhones; with iCloud off they stay on this iPhone. The privacy policy says so (iOS 0.54.0).
- **iPhone: drag and drop.** Drop a bank's CSV from Files on Forecast or the Dashboard and the import opens on it, starting on the account that page shows. Drag a one-off line from Forecast or the Calendar onto another Calendar day, in the same window or another WalletWeather window, to move its planned date; Undo puts it back. Lines that come from a bill, and paid lines, stay where they are (iOS 0.53.0).
- **iPhone: keyboard shortcuts and long-press menus.** With a keyboard attached, hold ⌘ to see them: ⌘N add (a transaction, or a bill on Bills & income), ⌘F Search, ⌘1 to ⌘5 the tabs, ⌘R refresh, ⌘[ and ⌘] the previous and next month, ⌘T this month, ⌘↩ save an editor and Escape close it. Long-press (or right-click) any line or bill, on Forecast, To confirm, the Calendar, Bills & income or in Search, for the same actions as its swipes; a Search result also offers Open in Forecast. With a pointer, rows and cards light up under it (iOS 0.52.0).
- **iPhone: match bank lines from the phone, with a server too.** Settings → Bank sync shows "N lines to match" under each bank connection and shared account with lines waiting; it opens the Unmatched list, where each line can pay a bill or line it's close to (Pay this, with "Always match" to make it a rule) or be left as its own line, as in the web app. With the Duo open, the list and a line's choices sit side by side over the whole screen. The Bank sync row in Settings reads "3 to match" while lines wait. A read-only sign-in can look but not change. The demo has two sample lines (iOS 0.51.0).
- **iPhone: switch connection from the Dashboard.** With more than one connection, a chip under the Dashboard's title (and at the top of Settings) names the one in front and opens the list to switch, with Manage connections… at the end. A connection whose sign-in has ended is marked ⚠ Sign in again in the list and on the chip. With a single connection there is no chip. The household on this iPhone now keeps its iCloud Drive backup and bank sync going whichever connection is in front (iOS 0.50.0).
- **iPhone: with the lock on, WalletWeather opens in the demo.** When the app starts, or comes back after a minute away, it shows the demo's sample numbers instead of a lock screen, so someone handed the phone sees a working app and none of yours. Opening any of your own connections asks for Face ID, Touch ID or your passcode first. While it's like that, Settings → Connections shows only the names you gave your connections, with no addresses or email, and their pages stay shut. Turn it off with **When locked, show the demo** in Settings → Privacy & lock to get the lock screen back (iOS 0.49.0).
- **iPhone: the demo and the household on this iPhone are in Connections,** beside your servers. Tap Demo to look around, and any other row to come back. A **Demo · sample numbers** chip under the Dashboard's title and at the top of Settings replaces the bar that ran across every page, and opens the list.
- **iPhone: tap an account or a Calendar line to open it.** An account opens in Forecast from the Dashboard's cards, Net worth's rows and the Calendar's balances. A line on the Calendar opens in the line editor, swipes to Paid, Edit or Delete, and offers Undo, as on Forecast. With the Duo open, tapping an account on the Dashboard shows it on the right: what's coming, how many lines wait to confirm, its charts and a way into Forecast; tap it again for every account's charts (iOS 0.47.0).
- **iPhone: several servers at once.** Settings → the card at the top now opens **Connections**: every server you're signed in to and the household on this iPhone, with a tick on the one in front. Tap another to switch to it; nothing is signed out and nothing kept is deleted. **Add a server** signs in to another one (or to the same one as someone else) with any of the usual ways. Each connection has its own page, where you can rename it and **Sign out** of that one only; signing out of the one in front brings the one you used last forward (iOS 0.46.0).
- **Breaking: iPhone: a link or QR code from the web app adds a server** instead of replacing the one you're signed in to. Signing in again to a server and person already in the list renews that sign-in.
- **iPhone: a Date format choice.** Settings → Dates & display → Date format: **Follow the web app** (with a server on 1.98.0 or later, dates are written the way you chose in the web app's Settings → Appearance), **Nov 12**, or **2026-11-12**. On this iPhone alone the choice is Nov 12 or 2026-11-12. `GET /api/me`'s `date_format` is read for this. Date pickers, and long forms with a weekday such as "Wed, Nov 18", don't change (iOS 0.45.0).
- **iPhone: Undo after marking a line paid, and haptics.** After a swipe to Paid or a tap on Paid in To confirm, a bar at the bottom of Forecast says "Rent marked paid" with **Undo** for five seconds (fifteen with VoiceOver). Undo puts the line back to not paid at its planned amount and date, as switching Paid off in the editor does. The phone gives a short tap when a line is marked paid and when a save goes through; its own System Haptics setting turns that off (iOS 0.40.0).
- **iPhone: change a line's name, date and planned amount.** For a line you added yourself, the editor's Name, Planned for and Planned amount are now fields, so a mistyped one-off no longer has to be deleted and added again. A line that comes from a repeating bill, and a transfer, show them as text as before: a bill's date changes in its bill. While a line isn't paid, its actual amount and date follow the plan you set (iOS 0.39.0).
- **iPhone: a + menu on the Dashboard.** Add a transaction (it asks which account), move money or import a CSV from the first page, without going to Forecast first. It shows when you may change at least one account (iOS 0.38.0).
- **iPhone: tap the month's name to jump.** On Forecast, Calendar and Compare the month between the arrows is now a button: This month, the months either side, and the six months ahead of today and behind it. The arrows work as before (iOS 0.37.0).

### Changed

- **iPhone: bank setup links and cards.** In the app, the SimpleFIN text under More → Bank sync now links to SimpleFIN Bridge's sign-in and setup-token pages, "Your Teller and Plaid keys" shows Teller and Plaid each in a card with links to their dashboard, quickstart, certificates and Keys pages, and the keys page and Connect a bank sheet the app opens link to the same pages, with Teller and Plaid each in a card (app 1.98.1, iOS 0.65.1).
- **Bank sync setup: links, and a card for each provider.** In Settings → Bank sync, the steps for adding your Teller and Plaid keys now link to the pages they mention (Teller's dashboard, quickstart and certificates; Plaid's dashboard and Keys page), and Teller, Plaid and SimpleFIN Bridge each have a card under Connect a bank with their own links and connect button (web 1.116.0).
- **iPhone: the Calendar shows amounts and colour bars,** as the web's phone Calendar does: each day with lines shows its net as a short amount and a bar per line in its category's colour (green for income, red for spending, an outline for a transfer when there's no colour), paler until paid. Today is a filled circle, and the chosen day is tinted. At the largest text sizes the closed Calendar keeps its dots (iOS 0.57.0).
- **iPhone: Forecast's summary as one strip,** as the web draws it: today's balance leads in large type, with Forecast end, Actual end and the month's lowest point (and its day) in one strip under it. At the largest text sizes the strip stacks (iOS 0.56.0).
- **Breaking: iPhone: "Back to the first screen" and the demo's Leave are gone.** Choose another connection in Settings → Connections instead; the household's numbers stay on this iPhone either way.
- **iPhone: every page reads at the largest text sizes.** With the phone's text size turned up (Settings → Accessibility → Display & Text Size → Larger Text), figures that shared a row stack one to a row, a label never breaks inside a word, an amount is never cut, and the Calendar keeps whole day numbers (its amounts move to the day's list at the largest sizes). With the Duo open, Forecast shows its line cards instead of the table at those sizes. Nothing changes at the usual size (iOS 0.48.0).
- **iPhone: a save that fails says so at the top of the form,** with the way forward where there is one (Try again, Sign in to Cloudflare, Sign in again), in place of a "Couldn't save" alert. It stays until you try again or close the form. A problem with what you typed is still written under that field.
- **iPhone: Appearance shows each look as a tiny screen in its own colours,** with a balance bar, an amount in and out, and a button, as the web app's Settings does. Match this iPhone is half Light and half Dark; Match the web app shows the theme saved on your server. Tap one to use it. Getting started's Choose a look uses the same previews (iOS 0.45.0).
- **Breaking: iPhone: a date outside this year now shows its year,** as in the web app: "Dec 29, 2027" where it read "Dec 29".
- **iPhone Duo: Settings is a sidebar and a page when open,** like the Duo's own Settings. The list (where you are, the other pages, your household, this iPhone, About) stands down the left with each row's value under its name, and the row you choose opens beside it under a card with its name and a line about it. Calendar, Net worth, Budgets and Reports open there too when they aren't in the tab bar. Closing the Duo on a page shows that page; opening it again shows the sidebar with the same page chosen. Closed, Settings is the list it was (iOS 0.44.0).
- **iPhone Duo: every page folds the same way.** Half open like a laptop, each two-pane page now stacks at the hinge, as only Forecast did: the Dashboard's charts stand up and its accounts lie flat; Bills & income's list above its editor or totals; the Calendar's month above the day; Net worth's total and chart above its accounts; Budgets, Reports and Search likewise. Half open like a book, the two panes sit either side of the fold instead of the right-hand one sitting on it. The panes move from one arrangement to the other as the Duo folds, or fade if Reduce Motion is on. Lying flat, every page is exactly as it was (iOS 0.43.0).
- **iPhone Duo: pull down in either half to refresh,** on every page, and on Reports and Search, which couldn't be refreshed before. **Breaking:** the Dashboard's Refresh button is gone; pull down instead.
- **iPhone Duo: one title size when open.** Net worth, Budgets, Reports and Search take the small title, as the other pages do.
- **iPhone: labels read in sentence case.** The small grey labels over figures ("Balance today", "Rest of this month", "Forecast end") are no longer in capitals, so every label in a card is written one way, as in the web app since 1.98.0 (iOS 0.42.0).
- **iPhone: Reports' rows look like the other lists.** With the Duo open, a saved report's name is plain text with a chevron and a highlight on the open one, where it used to be tinted like a link. The Tags page takes the app's own background and row colours in every look.
- **iPhone: with the Duo open, the Search field sits over its results,** at the top of the left half, instead of over the half where a tapped result opens.
- **Breaking: iPhone: pages follow the account you pick.** Choosing an account on Forecast, Bills & income or Calendar now moves the other two to it, in that window. Choosing All accounts on Bills & income or Calendar moves the other of those two; Forecast, which has no All accounts, stays where it is. To keep each page on its own account as before, turn off **Pages follow the same account** in Settings → Dates & display, a new page under This iPhone (iOS 0.41.0).
- **Breaking: iPhone: Settings is a short list of sections, each opening its own page.** At the top a card says where you are (your server and who's signed in, On this iPhone, or the demo) and opens that connection's page: Keep on this iPhone, Cloudflare, Open the web app and Sign out for a server; Back to the first screen and Delete everything for the household on this iPhone; Leave the demo in the demo. Under it: the pages that aren't in the tab bar, as tiles; **Your household** (Tags, Bank sync with its state on the row, Import a CSV, and on this iPhone Add an account, iCloud & backup and Move to a server); **This iPhone** (Appearance, Tab bar, Privacy & lock); **About** (Important notice, Help & Getting started, the versions). Every setting that was there is still there, and nothing you chose is reset. Each explanation now sits under the setting it explains, on that setting's page (iOS 0.36.0).
- **iPhone: the app says "this iPhone" everywhere,** where some screens said "this phone". The look "Match the phone" is now "Match this iPhone"; what you chose is unchanged.
- **iPhone: Help & Getting started** (Settings → About) can bring the Getting started card back to the Dashboard, and links to the privacy policy.
- **iPhone: the sign-in is kept per server, ready for more than one.** Nothing looks different yet. The phone's sign-in (the server's address, its token and any Cloudflare sign-in) moves from one Keychain item to one item for each server, with the same protection as before: on this device only, never in iCloud. Updating carries your sign-in over without signing you out, along with whether the phone keeps last-known numbers, the numbers themselves (now in a folder per server, deleted when that server is signed out) and the web theme it matches. The account each page shows is remembered per server in each window. If the carry-over can't be written, the old sign-in stays where it was and the next start tries again (`ConnectionStore`; iOS 0.35.0).

### Fixed

- **iPhone: the demo no longer dead-ends on Tags.** In "Try the demo", Settings → Tags said "The server said no" with a Try again that could never work, because the demo had no tags. It now has three sample tags (Holiday, Work, Kids) and two rules, a few of its lines and one bill carry them, a tag found in Search lists its lines, and the editors' Tags row opens. Like the rest of the demo they can be looked at and not changed (`Demo/tags.json`; iOS 0.34.1).

## [1.98.0] — 2026-11-23

App version: **1.98.0** · Web version: **1.115.3** · Schema version: **39** · iOS version: **0.34.0**

The web app has a calmer, more modern look from top to bottom: softer surfaces, real page titles, one set of controls, a single summary strip and row-line tables on Forecast and Bills & income, plainer Dashboard cards, one joined Calendar grid, a centred sign-in, Settings and Admin laid out as sections, and a top bar that stays in view with an account menu. Every theme is easier to read, and the iPhone app's copies of the themes take the same colours. Two new choices in Settings → Appearance: **Date format** (Nov 12 or 2026-11-12) and **Row height** (Roomy or Compact). **Before you update:** Log out has moved into the round account button at the right of the top bar on a wide window (a phone keeps it in More), and dates now read like Nov 12 until you choose Full dates. The database moves to schema 39 on the first start, by itself.

### Added

- **Settings → Appearance has a Date format choice and a Row height choice,** each saved to your account so they follow you across browsers. Date format is Short (Nov 12) or Full (2026-11-12); Row height is Roomy or Compact. `GET /api/me` returns `date_format` (`short` or `iso`) and `row_height` (`roomy` or `compact`), both null until you choose, and `PATCH /api/me/preferences` takes either and refuses any other value.

### Changed

- **Breaking: Log out has moved into an account menu.** On a wide window the email address and the Log out button are one round button showing your initials at the right of the top bar. Click it (or press Enter or Space) to see your email address, a link to Settings → Your account and Log out; Escape, a click elsewhere or choosing an item closes it, and the arrow keys move between items. On a phone nothing moves: the More sheet still has your email address and Log out.
- **The top bar is lighter and stays in view as you scroll.** The app's mark sits beside its name, the page you're on is a tinted pill with no outline, and the search box shows in full from a 1280px window up instead of only a magnifier (below that it is still the magnifier, and the bar stays on one line).
- **Dashboard cards are plainer and fill the row.** Three cards sit across a wide window instead of leaving an empty column. Each card's highest and lowest forecast balances are a label over a 20px figure with no boxes around them, the dashed dividers are single thin lines, the balance trend line is taller, the donut's total fits inside its ring and its legend shows every category instead of cutting off. Where the charts go (above, below or inside the cards) still works as you set it in Settings.
- **Calendar is one grid.** The days join into a single grid with thin lines between them, today is a filled date on a light wash, and each event keeps its category colour without an outline, with its amount in bold.
- **Sign-in sits in the middle of the window,** with the app's mark above its name and taller fields and button. The notice, two-factor and offline screens share the centred layout.
- **On a phone, Forecast's current balance spans the full width** above the other figures in a two-column strip, and the bottom bar marks the page you're on with its colour and a short bar.
- **Net worth's "Per account" heading** matches the other page headings.
- **Dates now read "Nov 12" instead of 2026-11-12** in tables, cards, charts, the calendar, search results and Admin, with the year added when it isn't the current one (Nov 12, 2025). Choose Full under Settings → Appearance → Date format to get 2026-11-12 back. Date fields you type into, CSV exports and the API are unchanged.
- **Table rows on Forecast and Bills & income are 36px high, with a taller toolbar** (the buttons and dropdowns above the table are 38px). Choose Compact under Settings → Appearance → Row height for the earlier 34px rows and toolbar.
- On Forecast, Bills & income, Net worth and Reports the summary tiles join into one strip. On Forecast the current balance leads in large type and the other figures sit under each other by column: opening balance over the difference, forecast out and in over forecast end, actual out and in over actual end, highest over lowest point. The order is the same in All accounts, which has no current balance.
- The Forecast, Bills & income and Unmatched tables show lines between rows only, with the row under the pointer highlighted. The slash between a forecast figure and its actual one is gone. Spreadsheet mode keeps its full grid.
- The pencil that opens a row is a drawn icon with no box until you point at the row. Category and tag pills in these tables are one filled style with no outline, and Unmatched is a tinted pill.
- Forecast's toolbar buttons and dropdowns are one height, and Spreadsheet mode is a soft button like the others (filled when on).
- Bills & income now fits a 1280px window as a table instead of turning into cards (it needs about 1276px; Forecast needs about 1251px, 10px more than before).
- **Breaking:** Admin is split into six sections, switched like Settings' tabs: General, Sign-in security, Bank and email, Users, Backups and Audit log. Each has its own address (such as `#admin/users`), so a bookmark to a part of Admin keeps working.
- On a wide window, Settings and Admin list their sections down the left and keep them in view while you scroll, with the settings in a narrower, easier-to-read column. Phones keep the tabs along the top.
- Admin's on and off settings (two-factor, bank sync, email alerts) are switches, and the buttons on each user say Disable, Reset password and Delete in words.
- Row actions in Settings and Admin stay quiet until you point at the row, and Delete reads in red. The Delete my account panel is outlined in red.
- Reports shows its six totals three across, with forecast above actual. Its filters line up at the top and show their choices as pills, and the saved reports and templates are plain lists with the open one highlighted.
- Every theme is easier to read: grey labels, red and green amounts, warnings and links that were too faint in Dracula, Solarized, Nord, Synthwave, Forest, Mint, Monokai and Sunset are a shade stronger, keeping their colour. The iPhone app's copies of these themes take the same colours.
- Settings → Appearance shows each theme as a tiny screen in its own colours, with a balance, an amount in and out, and a button. System shows half Dark and half Light.
- A calmer, more modern look for the Dark and Light themes: softer surfaces and borders, rounder cards with a light shadow, and, in Light, white cards on a tinted page. Filled buttons in Dark are now much easier to read.
- Dashboard and Net worth open with a proper page title, and their cards sit straight on the page instead of inside another box. Section headings and labels read in normal sentence case rather than capitals; table headers keep their capitals.
- Controls look the same everywhere: the account switcher and the Month / 30 days / 90 days choice are one segmented control, secondary buttons have a soft fill, dropdowns match the other fields, and buttons that delete something are tinted red rather than solid red.
- The footer stays at the bottom of the window on short pages.

### Database

- Schema 39: each person gains two display settings, `users.date_format` and `users.row_height` (empty until set, which means Short dates and Roomy rows). Added by itself on the first start.

### Fixed

- **Settings and Admin have a real page heading,** which screen readers find (it was drawn text beside the section list), looking the same on a wide window and shown above the tabs on a phone. The active section in the list reads clearly in every theme.
- **Calendar events with no category colour show their kind again:** a soft green tint for income, red for spending and an outline for a transfer (on a phone, the colour of the event's bar).
- **Grey, accent and red text on the new tinted surfaces is readable in every theme.** The account switcher, Settings tabs, Dashboard window switcher and chips (grey text), the active page pills, the checked account list and the initials button (accent text), and the tinted Delete buttons (red text) were under the 4.5:1 contrast target in Dracula, Solarized, Nord, Synthwave, Forest, Mint, Monokai and Sunset (and some in Light). Each uses a shade of its own colour that reaches 4.5:1.
- **Settings, Admin, Forecast and Bills panels use the phone's tighter padding again,** so they get their width back on a phone.
- **The account menu behaves better with the keyboard and when the window narrows:** choosing Your account returns focus to the account button, the menu closes if the window becomes phone-width, and an email like `sam+shopping@example.com` shows S rather than SS.
- **Changing Date format updates the dates already on the Settings page** (the notice, API tokens, remembered browsers, bank sync), without a reload. The Calendar's phone amounts no longer print -$0 or $1000.0k, the Dashboard no longer overflows on a very narrow phone, and the browser's theme colour matches the Dark theme.
- **The Calendar fits a phone.** Its Prev, month, Next, Today and Future view buttons wrap onto lines instead of running off the right edge (so the page no longer scrolls sideways), and each day shows its date over a short amount such as -$1.7k, with its events as small colour bars, instead of cutting an amount off mid-figure. Tap a day to see its events listed in full below the grid.
- The Net worth chart shows its amounts in full, in short form inside the chart (such as $22.4k), instead of cut off at the left edge ("9.67" for $22,449.67).
- When the Forecast table turns into cards in a narrower window, each figure carries one label ("Forecast date") instead of two run together ("Forecast dateStart date").
- The Reports bar chart uses the full width of its panel instead of a narrow strip on the left.
- The Reports filters (accounts, categories and tags) show every choice instead of cutting the list off after three rows.
- On a phone, the Reports page no longer scrolls sideways: the report's name, Pin and buttons wrap onto a second line.
- Tags and category chips no longer disappear into the background in the Solarized and Synthwave themes, and the selected account tab stands out from the bar.

## [1.97.0] — 2026-11-23

App version: **1.97.0** · Web version: **1.108.0** · Schema version: **38** · iOS version: **0.33.0**

Teller and Plaid now use each person's own keys, added in Settings → Bank sync or from the iPhone app; the keys in `.env` are copied once to the people already using them, so every connection keeps syncing. An account can take lines from bank alert emails and bank sync at once, joining an alert's line to the bank's instead of doubling it, and an admin now ticks who may connect a mailbox, as for bank sync. On an iPhone without a server, SimpleFIN bank sync now works on the phone itself. **Before you update:** leave the `TELLER_` and `PLAID_` lines in `.env` until this version has started once. The database moves to schema 38 on the first start, by itself. Also pull the newer PostgreSQL image on your server (see Security).

### Added

- **Add, replace or remove your own Teller and Plaid keys from the iPhone app.** More → Bank sync now lists Teller and Plaid with whether you've saved your own keys (and their environment), and **Add your bank keys** (or **Your bank keys**) opens your server's new page, `/app-bank-keys`, in the app's sign-in sheet. There you sign in if needed and add, replace or remove keys just as in the web app's Settings → Bank sync, with a fresh two-factor code each time; Teller's certificate is picked from Files (the `teller.zip` Teller downloads, or the two files inside it). The keys go in only through that signed-in page, never with the app's token, and the app never holds them: it learns only which services have keys. Someone ticked for Teller or Plaid without keys yet is told to add theirs rather than that an admin decides. `GET /api/bank/status` gains `providers_ticked` and `own_keys` (the environment only, never the id or the secret). Needs server 1.97.0.
- **Admin → Users now shows who has saved their own Teller and Plaid keys.** In the Bank sync column, next to each person's Teller and Plaid ticks, it says **own keys, development** (or whichever environment they saved) once they've added keys in Settings → Bank sync, and **ticked, no keys yet** when you've ticked a service for them and they haven't. You see whether they have keys and where, never the keys themselves: `GET /api/admin/users` carries `bank_keys` per person (`teller` and `plaid`, each `{"environment": …}` or `null`) and no application id, client id, secret or certificate. (1.96.0, web 1.107.0, #277)
- **Your own Teller and Plaid keys, in Settings → Bank sync.** Each person who connects a bank through Teller or Plaid now uses keys from a developer account of their own, so their bank logins count against their own Teller or Plaid account and nobody else's keys reach their bank. Settings → Bank sync has a **Your Teller keys** card (your application id, the environment, and the `teller.zip` Teller downloads when you make a certificate; picking the two files inside it, or pasting their text, works too; the sandbox needs no certificate) and a **Your Plaid keys** card (client id, secret and environment). **Check and save** asks Teller or Plaid first and says what's wrong if they don't accept the keys. Once saved, a card shows the id, the environment and when they were checked, never the secret, with **Replace** and **Remove**. Saving and removing need you signed in in a browser and, with two-factor on, a fresh code, as connecting a bank does; each is recorded in the audit log as `bank_keys_saved` or `bank_keys_removed`, naming only the service and environment. Teller or Plaid is offered to you once an admin has ticked you for it in Admin → Users **and** you've saved your keys; for apps, `providers[].available` in `/api/bank` and `providers_allowed` in `/api/bank` and `/api/bank/status` now follow your own keys, and `/api/bank` carries `keys`. (#276)

- **An account can now take lines from your bank's alert emails and from bank sync at once, without doubling them.** When bank sync brings in a purchase that an email alert already put in the account, it joins the alert's line instead of adding a second one: the line keeps the alert's merchant name and takes the bank's amount and date, so a restaurant tip added after the alert is corrected by itself. Anything you changed on the line yourself (its name, amount, date, category, tags or notes) stays as you left it. A bill the alert already marked paid stays paid, once, at the bank's amount. An alert that arrives after the bank's line is joined to it the same way. A joined line shows the **Bank sync** mark, and opening it on Forecast says "From an email alert, posted by the bank on …". (#210)
- **How close a bank line must be to join an alert is set per account.** By default the bank's line may come up to 7 days after the alert and be up to 30% higher (a tip), always on the same account and going the same way; when two alerts are as close, nothing is joined and the bank's line waits on the Unmatched list for you. Settings → Accounts shows the sentence "Join an alert to the bank's line within [7] days, up to [30]% higher (tips)" under each account you own that has both email alerts and bank sync (0 to 31 days, 0 to 100%). For apps, `GET /api/accounts` and `PATCH /api/accounts/{id}` carry `alert_join_days` and `alert_join_percent`. (#210)
- **Un-join and Join by hand.** A wrong join can be undone with **Un-join** in the line's open editor on Forecast: the alert's line goes back to the alert's amount and date and the bank's line becomes its own line again, and the two aren't joined again by themselves. On the Unmatched list, **Join…** pairs an alert's line with one of the bank's lines (or the other way round) when they weren't joined by themselves, showing how each compares. (#210)
- **Alerts that never posted are flagged.** An alert's line that no bank line has met, 10 days after it and with bank sync having read that far, shows **Never posted** on the Unmatched list, with "No bank line in 10 days: a dropped hold or a declined charge? Delete it or keep it." and **Delete** and **Keep** beside it. Nothing is deleted by itself. (#210)
- **An admin now chooses who may connect a mailbox for email alerts, the same way as bank sync.** Admin → Users has an **Email alerts** column with a **Microsoft 365** tick for each person (admins can always connect). Someone who isn't ticked doesn't see Connect in Settings → Email alerts. Unticking someone pauses their mailbox: it's kept with everything they taught, it isn't checked, and Settings says an admin has paused it, until they're ticked again. The **Email alerts** switch in Admin still turns alerts off for everyone. Everyone who already has a mailbox connected is ticked when you upgrade, so nothing stops working. (#268)
- **Shared accounts with email alerts.** If you own or can edit an account that takes lines from someone else's bank alert emails, Settings → Email alerts lists it under **Shared accounts with email alerts**: whose mailbox it comes from, when it was last checked, whether that mailbox is paused or needs reconnecting, a **Check now** for that account, and its **Unmatched** lines. The mailbox itself stays theirs: only they can teach banks, reconnect or disconnect it. (#268)

- **iOS 0.31.0, shared accounts that sync, in Settings:** the **Bank sync** card now lists the accounts you own or edit that take their lines from someone else's bank connection, each saying "Synced from Sam's SimpleFIN connection", how that account's own last sync went and when it syncs next, how many lines wait to be matched (in the web app), and a **Sync now** of its own. Sync now is off while an admin has paused that person's connection, while they need to connect it again, while they can't sign in, and over the day's limit, and each says why. If you only have shared accounts and no bank of your own, the card skips "No bank connected". **Connect a bank** now shows only when an admin has ticked you for Teller or Plaid; if you're ticked for none, the card says an admin chooses who may connect a bank, in Admin → Users. Try the demo shows a sample shared account (a Credit Card synced from Sam's Plaid connection). Needs server 1.92.0 for shared accounts and 1.92.1 to hide Connect a bank from someone who isn't ticked; an older server shows the card as before, with Connect a bank offered. (#267)
- **iOS 0.32.0, bank sync on an iPhone without a server.** If you use WalletWeather on your iPhone alone, Settings → **Bank sync** now offers **Connect SimpleFIN**: make a setup token at SimpleFIN Bridge, paste it, and pick which of your accounts each bank account fills and how far back to bring lines in from (up to 90 days), as in the web app's Settings. The connection is kept in this iPhone's Keychain only: never in iCloud sync, an iCloud Drive backup or an exported file. The phone syncs at most once every 23½ hours, when you open the app or when iOS gives it time in the background, and **Sync now** is there whenever you want it, up to 20 times a day like on a server. A bank line that pays a planned bill marks it paid, the same way a server matches it; the rest wait under **Unmatched (N)** in the card, where **Match…** pays a bill or planned line with it (and can teach the bill the line's name) and **Leave** keeps it as its own line. Such lines wear an **Unmatched** mark on Forecast, as in the web app. The same bank line never lands twice, also on your other devices through iCloud. Only SimpleFIN can come to the phone: Teller and Plaid need keys that must stay on a server. A backup made on the phone now carries each line's bank link, so moving to a server doesn't bring them in again. (#239)
- **`GET /api/bank/status` now says which services you may connect a bank through.** It carries `providers_allowed` (`simplefin`, `teller`, `plaid`: the ones an admin has ticked for you in Admin → Users, or every one for an admin, and that you have what they need: from 1.95.0, your own keys for Teller and Plaid), the same list the signed-in browser's `/api/bank` already had, so an API token can tell the iPhone app whether to offer **Connect a bank**. (#267)

### Changed

- **Breaking: Teller's and Plaid's keys move from `.env` to each person's Settings.** On the first start of this version, the Teller and Plaid keys in your `.env` (and Teller's certificate from `TELLER_CERT_DIR`) are copied, once, to everyone who has a Teller or Plaid connection, as their own keys, so every connection keeps syncing. After that the server no longer reads `TELLER_APP_ID`, `TELLER_ENV`, `TELLER_CERT_DIR`, `PLAID_CLIENT_ID`, `PLAID_SECRET` or `PLAID_ENV`; Admin → Bank sync says so, and how many people the keys were copied to. Leave those lines in `.env` until you've started this version once; after that you can remove them. If your server had connections but the keys couldn't be read on that start, the copy is tried again at the next one. Anyone else who wants Teller or Plaid adds their own keys in Settings → Bank sync, and every provider can now be ticked for anyone in Admin → Users. (#276)
- **Each Teller and Plaid connection keeps the keys it was made with.** A connection goes on syncing with its own encrypted copy of the keys whatever its person later does with theirs, and keeps syncing for whoever it passes to when its person is deleted, without that person seeing the keys. Removing your keys, or replacing them with a different application or client id, is refused while connections use them, naming those connections; replacing them with the same id (a renewed Teller certificate, a rotated Plaid secret) is allowed and the connections carry on with the new ones. (#276)
- **Sealed backups and moves carry your Teller and Plaid keys** and each connection's copy, so a restored connection syncs as before; **Download my data** never carries them. An older backup without keys restores as before. (#276)
- **Bank sync and email alerts now match lines to bills with the shared code the iPhone app uses** (server 1.94.1), so a server and a phone on its own decide the same way which bill a bank line pays, what's on the Unmatched list and what Match… offers. Nothing changes in what gets matched. (#239)
- **Teaching an alert to an account that takes bank sync is allowed now**, since the two are joined; the email alert account pickers no longer grey such accounts out. Alerts that were kept aside before because their account had bank sync are brought in at the next check and joined to the bank's line already there when one fits; one that finds none (for example, because the bank's line already paid a bill) shows as **Never posted**, for you to delete. Settings → Bank sync's sync log has a **Joined** column, and Sync now says how many lines joined an alert. (#210)

### Database

- Schema 38: a new table holds each person's own Teller and Plaid keys (the secret part encrypted), and each bank connection gains an encrypted copy of the keys it was made with. Added by itself on the first start, along with the one-time copy of `.env`'s keys described above. (#276)
- Schema 37: each account gains its two join settings (7 days and 30% to start), each line from an email alert keeps the alert's own amount and date (encrypted), a joined line keeps what the bank's line was (encrypted) so it can be un-joined, and each sync in the log counts the lines it joined. Added by itself on the first start. (#210)

### Security

- **Update the database image: PostgreSQL 16.16 fixes 52 security problems.** PostgreSQL released 16.16 on November 12, 2026; the worst (CVE-2026-6460) let a signed-in database user run code on the database server. WalletWeather's database is reachable only by the app, on Compose's internal network, so the risk is low, but a WalletWeather release doesn't update the database image: on your server, run `docker compose pull db && docker compose up -d db` (your data stays in its volume). The app's own image, rebuilt for this release, picks up Python 3.12's latest security fixes by itself. A scan of every Python package the server installs found no known advisories. (#280)

## [1.92.0] — 2026-11-22

App version: **1.92.0** · Web version: **1.103.0** · Schema version: **35** · iOS version: **0.30.0**

Bank sync moves out of one Admin switch: an admin now ticks who may connect a bank and through which service, and a linked account's sync belongs to the account, so everyone who can edit a shared account can see its sync, match its lines and press Sync now. Deleting someone passes their bank connection to the account's other owner instead of stopping the sync. **Before you update:** everyone who already has a bank connected keeps it working, but nobody else can connect a bank until you tick them in Admin → Users. The database moves to schema 35 on the first start, by itself; there are no settings to add.

### Changed

- **Breaking: deleting someone no longer takes their bank connection away from an account that stays.** When a person is deleted (by themselves or by an admin), each of their bank connections that still feeds an account with another owner passes to that owner and keeps syncing: the other owner of the account it was matched to first, the longest-standing one if there are several (skipping anyone who can't sign in, and anyone who has connected the same bank account themselves). It goes with all its matches, its sync logs stay on the accounts, the new holder is ticked for its service in Admin → Users if they weren't (so it doesn't arrive paused), and its bank categories are copied over, landing in the new holder's category of the same name. A connection that feeds no account staying with someone else is removed, as before. Settings → Delete account, and an admin's Delete in Admin → Users, now say which connections pass to whom and which are removed. Each hand-over is recorded in the audit log as `bank_connection_passed`, naming the deleted person and the new holder by number, under the admin who deleted them. (#266)
- **A match to an account you don't own can't be changed by mistake.** In Settings → Bank sync, a bank account matched to someone else's account (a connection passed on to you, or an account where you're no longer an owner) shows that account's name as text, not a dropdown, and **Save matches** leaves it alone; only that account's owners can stop it syncing. An owner of a shared account that syncs from someone else's connection now has **Stop syncing** on its card, which takes away the match (lines already in stay, the connection stays its person's), recorded in the audit log as `bank_link_removed`. Before, saving matches could quietly unmatch such an account. (#266)
- **Breaking: a linked account's bank sync now belongs to the account, not only to the person who connected the bank.** Everyone an account is shared with to edit, and every owner, can now see its sync log, work through its Unmatched list (Match… and Leave as its own line, in Settings and on the Forecast tab), see the bank's balance on its Forecast tab and use **Adjust to bank**, and press **Sync now** for it. Their Settings → Bank sync tab lists these accounts under **Shared accounts that sync**, each saying "Synced from <name>'s <provider> connection · <bank account>", how its last sync went and when it syncs next; they never see the bank login itself or the other accounts on it. Some things stay with the person who connected the bank: reconnecting, disconnecting and where the bank's categories land. Only an account's owners can match it to a bank account or remove the match. If an admin has paused that person's connection, Sync now says so and waits. People the account is shared with read-only still see only the lines that come in. A Sync now pressed for someone else's connection is recorded in the audit log under the person who pressed it. For apps, `POST /api/bank/sync` takes `account_id` to sync the connection that feeds one account, and `/api/bank` and `/api/bank/status` list these accounts in `shared`. (#265)
- **Breaking: an admin now chooses who may connect a bank, and through which service.** Admin → Users has a **Bank sync** column with a tick for each service your server offers (SimpleFIN, and Teller or Plaid once their keys are in `.env`). Only a ticked person can connect through that service; admins always can. The Admin → Bank sync switch still turns bank sync off for everyone at once. When you update, everyone who already has a bank connected is ticked for its service, so nothing that works today stops, but nobody else can connect a bank until you tick them. Unticking someone pauses their connections of that service instead of removing them: their Settings → Bank sync says an admin has paused it, the daily sync and Sync now skip it, and ticking them again carries on where it left off. Connecting a bank ticks you for its service too, so an admin's own connection keeps syncing if they stop being an admin. The iPhone app's **Connect a bank** offers only the services you're ticked for. Changing the ticks needs an admin signed in in a browser, and each change is recorded in the audit log as `bank_access_changed`. (#264)

### Database

- Schema 35: a new table holds which services each person may connect a bank through. It's filled once, on the first start after updating, from the bank connections people already have. (#264)

## [1.89.0] — 2026-11-21

App version: **1.89.0** · Web version: **1.100.0** · Schema version: **34** · iOS version: **0.30.0**

You can now connect a bank through Teller or Plaid from the iPhone app: Settings → Bank sync → **Connect a bank** opens your server's new connect page in the phone's sign-in sheet, and the sheet closes by itself when the bank is connected. No database change and no settings to add; Teller and Plaid still need their keys in `.env`.

### Added

- **iOS 0.30.0, connect a bank from your iPhone:** Settings → Bank sync now has a **Connect a bank** button. It opens your server's new connect page in the phone's sign-in sheet (the one the app signs in with, which shares Safari's sign-in), where you pick **Teller** or **Plaid** (whichever your server has keys for), type your two-factor code if it's on, and sign in to your bank on Teller's or Plaid's own page. When it's done the sheet closes by itself and the card says which bank was connected; match its accounts to yours in the web app, Settings → Bank sync, as before. SimpleFIN is still connected in the web app. The app never sees anything that reads your bank: connecting stays something only a signed-in browser can do, and the page hands the app only the new connection's number. Needs server 1.89.0. (#258)
- **A connect page for the iPhone app** (`/app-connect-bank`): signs in if needed (password, Google or two-factor code), offers Teller and Plaid, and sends the sheet back to the app when the provider is done. Teller's page comes back to it when opened from the app, and a Plaid connection started there tells Plaid to return to it (Plaid's `completion_redirect_uri`, set to the address your browser used, which needs no registration with Plaid). Banks that would hand off to their own app show their web sign-in instead, so there's no Universal Link to set up. The page loads scripts from your server only. (#258)

## [1.88.0] — 2026-11-21

App version: **1.88.0** · Web version: **1.99.0** · Schema version: **34** · iOS version: **0.29.2**

### Added

- **iOS 0.29.0, every bank connection in Settings:** the **Bank sync** card now lists each bank you've connected, whether through SimpleFIN, Teller or Plaid, with its bank's name, the provider, how its last sync went in plain words, when it syncs by itself next, and a **Sync now** of its own that syncs only that connection (each has its own 20-a-day limit, and a connection over it says so, naming its provider). A connection that needs connecting again or has no account matched says so. Try the demo shows a sample with two connections. It needs server 1.86.0 for the list; a server from 1.70.0 to 1.85.0 keeps the one row it had, and connecting a bank stays in the web app. (#257)
- **Your bank's balance next to yours:** a bank account matched to one of your accounts now keeps the balance its provider reported at the last sync, and the account's Forecast tab shows it under **Current balance**: "Bank: $1,234.56 as of …". When it differs from your balance (counting lines up to today) it says **Bank differs by** the amount, in amber, with an **Adjust to bank** button that adds one paid line named "Adjust to bank", dated today, for exactly the gap; **Undo** beside it deletes that line again. If a sync or an edit changed the gap since you looked, nothing is added and it says so (`POST /api/accounts/{id}/bank-adjust` takes the gap you saw, and the forecast carries `bank_balance`). SimpleFIN and Plaid give the balance with every sync. Teller bills for each balance it's asked for in production, so WalletWeather asks only at an account's first sync, when a sync brings in a line it hasn't seen, or when its balance is a week old; a quiet day makes no billed call. A card's or loan's balance counts against you. Planned lines dated up to today that aren't paid yet (which your balance counts but the bank can't have posted) are named beside the gap, and Adjust to bank asks you to confirm when there are any. If Teller can't give a balance, the last good one stays unless new lines came in, it's retried at most once a day, and the lines still come in. Only the connection's owner sees it (not people an account is shared with), and not while an admin has bank sync switched off. Adjusting is recorded in the audit log as `bank_balance_adjusted`. The [bank sync guide](https://mkolakowski.github.io/WalletWeather/bank-sync.html) has the details. (#256)
- **Teller's and Plaid's categories land in yours:** Teller and Plaid label each line they send with a category of their own ("groceries", "FOOD_AND_DRINK"). Settings → Bank sync now has a **Categories from your banks** table, one row for each of those categories a sync has seen, with a dropdown of your own categories. A row is filled in by itself where one of your categories has the same name (your Groceries, Income and Dining, for instance, match Teller's and Plaid's out of the box); change it, or pick Uncategorized, and press Save categories. Lines that come in afterwards land in the category their row says. A line that pays one of your planned bills keeps the bill's category, your auto-tag rules run after the category is set (so a rule limited to a category sees it), and changing the table never touches lines already here. SimpleFIN gives no categories, so nothing changes for it. Each line keeps the provider's own category, as stored data (see `PRIVACY.md`). The [bank sync guide](https://mkolakowski.github.io/WalletWeather/bank-sync.html) has the details. (#255)
- **Bank sync through Teller and Plaid:** besides SimpleFIN Bridge, a bank can now be connected through [Teller](https://teller.io/) or [Plaid](https://plaid.com/), which reach banks their own way, so a bank SimpleFIN can't reach may work through one of them. Each is offered in Settings → Bank sync once the server has its keys in `.env` (Teller: `TELLER_APP_ID`, `TELLER_ENV` and its certificate in `TELLER_CERT_DIR`; Plaid: `PLAID_CLIENT_ID`, `PLAID_SECRET` and `PLAID_ENV`); the one Admin → Bank sync switch covers all three, and Admin says which are set up. You sign in to your bank on the provider's own page in a new tab, never on WalletWeather's: Plaid's Hosted Link, or WalletWeather's Teller page running Teller Connect. Settings notices when you're done; no webhook or public address is needed. Synced lines go through the same path as SimpleFIN's: posted lines only, the daily sync and Sync now, auto-tag rules, bill matching, the Unmatched list and the sync log. The setup is in the [bank sync guide](https://mkolakowski.github.io/WalletWeather/bank-sync.html). (#254)
- **More than one bank connection:** each bank login is a connection of its own, from any mix of SimpleFIN, Teller and Plaid, listed in Settings → Bank sync with its own Sync now and Disconnect. The SimpleFIN connection you have becomes the first on the list, unchanged. Each of your accounts takes lines from one bank account across all your connections: a second match is refused, naming the connection that has it, so no line comes in twice. A new token from a SimpleFIN Bridge account you already have connected updates that connection and keeps its matches, rather than making a second one that lists the same bank accounts. (#254)

### Changed

- **Disconnecting a Teller or Plaid bank ends it there too,** so the provider stops reading your bank; deleting your user does the same for all of yours. If the provider can't be reached at that moment, the connection is still forgotten here and the message says to remove it in the provider's dashboard. (#254)
- **Encrypted backups carry every bank connection,** as a list. Backups made before this still restore their one connection. (#254)
- **The iPhone app keeps working unchanged:** `GET /api/bank/status` keeps its shape, now summing up every connection, and gains a `connections` list; Sync now from the phone syncs them all. (#254)

### Fixed

- **iOS 0.29.1, the open iPhone Duo no longer lets cards slide under a big "Dashboard" title:** with the Duo open, the left column of the Dashboard scrolled up behind the large page title, so its text showed through the title as a ghost inside a hard-edged band. Dashboard, Bills & income, Calendar and Forecast now use the small title in the two-pane layout; the iPhone and the closed Duo keep the large one. (#260)
- **iOS 0.29.2, the demo's bar no longer covers the page title:** in the demo, the "Demo · sample numbers" bar sat over the top of the page and hid part of the title (most visible on the open Duo). The page now starts below the bar. (#261)

### Database

- **Schema 34:** a matched bank account keeps the balance its provider gave at the last sync (`bank_account_links.bank_balance_enc`, encrypted like every amount, and `bank_balance_at`, when the bank had it), empty until the next sync. Made by itself when the app starts. (#256)
- **Schema 33:** each synced line keeps what Teller or Plaid called its category (`transactions.bank_category`, empty for every line already there and for SimpleFIN), and a new table `bank_category_maps` holds each user's table of provider categories and where they land. Made by itself when the app starts. (#255)
- **Schema 32:** a user may have many bank connections (`bank_connections` loses its one-per-user rule and gains `provider`, `simplefin` for the ones already there, and `cursor`, where Plaid's next sync starts), and a new table `bank_link_attempts` holds a Teller or Plaid connection while it's being made, a day at most. Made by itself when the app starts. (#254)

### Security

- **One page loads another site's script:** `/bank/teller`, the page that runs Teller Connect, loads Teller's script from `cdn.teller.io`, as Teller requires, under a Content-Security-Policy of its own that allows only that and no inline scripts. No other page loads anything from another site; `PRIVACY.md` names the exception. Teller's certificate and key and Plaid's secret stay on the server, and an access token Teller hands the page is kept only if Teller accepts it straight away. (#254)

## [1.85.0] — 2026-11-20

App version: **1.85.0** · Web version: **1.96.0** · Schema version: **31** · iOS version: **0.28.0**

The iPhone app can now be used without a server: your numbers live on the iPhone, sync between your devices through your own iCloud, back up to iCloud Drive by themselves, and move to a server and back. It imports a bank's CSV and has tags and auto-tag rules, with or without a server. On the server, CSV import, Bills & income and search now run on the shared engine, with the same results, and two CSV import bugs are fixed. No database change and no settings to add.

### Added

- **iOS 0.28.0, auto-tag rules on the iPhone:** Settings → Tags now lists your auto-tag rules, as in the web app: "a description containing these words gets this tag", optionally only in one category. Add, change, switch off or delete them on the iPhone. On an iPhone with no server they work as on a server: a line gets the tag when it's added, changed or imported, and **Apply to existing lines** adds it to the ones already there. With a server, the list edits your server's rules.

- **iOS 0.27.0, tags on the iPhone:** lines and bills now show their tags as small chips in each tag's colour, in Forecast, Bills & income and a tag's list of lines. Open a line or a bill to choose its tags, or make one on the spot with **New tag…**. Settings has a new **Tags** page to add, rename, recolour and delete tags (deleting one takes it off every line and bill). Search finds tags, and tapping one lists its lines. It works on an iPhone with no server and on one signed in to a server, on the same tags as the web app. A bill's date marked paid still takes the bill's tags.

- **iOS 0.26.0, tags kept on the iPhone:** an iPhone used without a server now keeps tags: on lines, on bills and bill payments, and auto-tag rules. Moving between your server and the iPhone (Export for a server, Import a server backup), the iCloud Drive backups and Sync with iCloud all keep them; before, tags were left behind on the way to the phone. A CSV import tags lines with tags you already have, as on a server.

- **iOS 0.25.0, delete everywhere:** with Sync with iCloud on, **Delete everything on this iPhone** in Settings now offers two choices. **Delete on this iPhone only** clears this phone and leaves the synced copy in your iCloud and on your other devices, as before. **Delete everywhere** deletes every account, bill and line in your iCloud and on every device signed in to it, then on this phone. If iCloud can't be reached at that moment, this phone is emptied and the rest is deleted the next time WalletWeather opens while connected; the first screen says which happened. Your encrypted backups in iCloud Drive are kept either way, as the way back from a mistake.

- **iOS 0.24.0, sync with iCloud:** on an iPhone used without a server, your accounts, bills and lines now stay the same on every iPhone signed in to your Apple ID, through your own private iCloud. An edit on one shows on the others, also while the app is closed. When two devices change the same thing, the later change wins, and something deleted stays deleted. A second device that already had numbers of its own adds them to the shared ones, and the usual categories each device started with become one set. It's on unless you turn off **Sync with iCloud** in Settings → On this iPhone; turning it off keeps every number on that iPhone. While it's on, your numbers can be read on the iPhone after its first unlock (so they can sync in the background) instead of only while it's unlocked.

- **iOS 0.23.0, import a bank's CSV on the iPhone:** **Import a CSV…** in Settings, and in Forecast's **+** menu for the account on screen, opens a CSV from the Files app (your bank's export, for example). Pick the account, check how the amounts are signed, and see what will happen before anything changes: how many lines will be added, which are already on the account, which repeat, and which rows are left out and why. The columns are worked out from their names; open **Columns** to change any, and the phone remembers your choices per account for the next file with the same headings. **Import** adds each row as a paid line on its date. A line with the same date, amount and description as one already there is left out, so importing the same file twice adds nothing. Rows marked as repeating join their bill, or make one. It works on an iPhone with no server, and on one signed in to a server, for accounts you can change.

- **iOS 0.22.0, delete a transfer and bring back skipped dates:** open a transfer between accounts (in Forecast, the Calendar or Search) and **Delete transfer** removes it with both of its lines, on both accounts, after asking. On an iPhone with no server this is the way to undo Move money; with a server it works too, for accounts you can edit. A bill or paycheck that has skipped dates now shows **Bring back the skipped date** (or **Bring back N skipped dates**) in its editor in Bills & income, which puts them all back in the Forecast and Calendar. Before, both were possible only in the web app. Tags still can't be made on an iPhone with no server.

- **iOS 0.21.0, automatic backup to iCloud Drive:** on an iPhone used without a server, WalletWeather now backs your numbers up to your iCloud Drive by itself. It turns on when you add your first account, asking for your backup passphrase if you haven't chosen one (**Not now** leaves it off). A backup is made at most once a day, only when something changed, and the last 14 are kept. They're the same encrypted files as Export for a server, so a server's Settings → Restore opens them too. They sit in the Files app under iCloud Drive → WalletWeather → Backups. Settings → On this iPhone has a new Backup card with the switch, the date of the last backup, **Back up now** and **Restore from a backup…**. On a new iPhone, the first screen's **Restore from an iCloud backup** lists the backups, asks before replacing anything, opens the chosen one with your backup passphrase from iCloud Keychain (or one you type) and turns backup on again. It needs iCloud Drive turned on for WalletWeather in the phone's Settings; the app says so when it isn't.

- **iOS 0.20.0, move between your server and the iPhone:** on an iPhone used without a server, Settings has a new card, "Move to or from a server". **Export for a server** saves your numbers as your server's own encrypted backup, which its Settings → Restore takes. **Import a server backup** replaces what's on the iPhone with a backup your server made. It asks first, naming the accounts that will replace yours, and an empty Dashboard offers it too. Backups are locked with a backup passphrase you choose the first time you export. It's kept in your iCloud Keychain, so your other Apple devices know it, and Settings → Backup passphrase shows it after Face ID, Touch ID or your passcode. Nobody can recover a lost passphrase, and the app says so when you choose it. Tags, tag rules and bank and email-alert links stay on the server, because the iPhone doesn't have them yet. (iOS 0.20.0, #236)

- **iOS 0.19.0, use the iPhone app without a server:** the first screen now asks how you'd like to use WalletWeather. **On this iPhone** keeps your accounts, bills and transactions on the phone, with nothing to set up. **Your own server** signs in as before. Each choice lists what it gives and what it costs, and **Try the demo** is underneath. On this iPhone, Dashboard, Forecast, Bills & income, the Calendar, Move money and Search work as they do with a server, worked out by the same shared engine. You add accounts from an empty Dashboard or Settings → On this iPhone, and a new household starts with the usual categories. Net worth, Budgets, Reports and bank sync stay in their places, greyed and marked "Needs a server", with a note on what a server adds. Your numbers can't be read while the phone is locked, and they're included in the phone's own iCloud or computer backup. Settings → On this iPhone has **Back to the first screen**, which keeps your numbers, and **Delete everything on this iPhone**. Not yet on the phone: changing or deleting a transfer, bringing back a skipped date, and tags. Moving between the phone and a server, and a backup to iCloud Drive, come next. (iOS 0.19.0, #235)

### Changed

- **CSV import on the shared engine:** reading a CSV file for import, spotting lines already on the account, and grouping repeating rows into bills are now done by the shared engine, the same code the iPhone uses without a server. The results are the same as before; the server's own code wrote the answers the engine is checked against.
- **Backups keep transfers:** a backup now records which lines were a transfer between your accounts, so a restore, or a move between your server and the iPhone, brings each transfer back as a transfer. Before, a restored transfer came back as two plain lines (the balances were right). Backups made before this still restore as before. A backup made by this version can't be restored on an older server: update that server first. (1.84.0, backup version 5, `apps/server/app/backup.py`, #236)
- **Bills & income and Search on the shared engine:** the Bills & income list and its monthly and yearly totals, the search box's results, and transaction search are now worked out by the shared engine too, the same code the iPhone app will use without a server. They were checked against the old code on 54 new test cases, including names in other alphabets, and agreed except in one place: a line's or bill's tags are now listed in the same order everywhere, as on Forecast, so tags whose names start with letters beyond plain A–Z (such as "Iğdır") may swap places with their neighbours. On an account with about 1,500 lines, a search that matches every line takes about 10 ms longer. (1.83.0, `packages/core/`, #235)

### Fixed

- **CSV import with a tag named twice:** a row whose Tags column names the same tag twice (for example "Work trip; work trip") made the whole import fail. Each tag is now added to the line once.
- **CSV files with a stray line break:** a file with a line break inside an unquoted field now gets a clear "couldn't be read as CSV" message instead of a server error.

## [1.82.0] — 2026-11-18

App version: **1.82.0** · Web version: **1.96.0** · Schema version: **31** · iOS version: **0.18.0**

The server now works its money numbers out with a new shared engine, the same code the iPhone app will use to run without a server, and the iPhone demo does the same. Nothing should look different. No database change.

### Changed

- **A shared engine for the numbers:** balances, the Forecast, the Calendar, the Dashboard and its charts are now worked out by a new shared engine instead of separate code in the server. Before the switch, the old and new code were checked against each other on 63 test cases across three households and agreed to the last digit. Pages built on the forecast (Budgets, Net worth, Reports, Search and bank matching) use it too. If a number looks different from before, please open an issue. (1.82.0, `packages/core/`, run by `apps/server/app/jscore.py`, #233)
- **A bigger image:** the container image grows by about 8 MB for the JavaScript engine that runs the shared one (quickjs-ng, MIT).
- **iOS 0.18.0, a better demo:** "Try the demo" now works its Dashboard, charts, Forecast, Calendar and account balances out on the phone with the same shared engine, instead of showing recorded answers. Every demo account's Forecast and every month is now worked out properly, and the demo's purchases stay in the past whatever today's date is. It's the first step toward using the app without a server. (iOS 0.18.0, #234)

## [1.81.0] — 2026-11-18

App version: **1.81.0** · Web version: **1.96.0** · Schema version: **31** · iOS version: **0.17.1**

Two refinements to matching bank lines by hand: learned names ignore changing codes, and the match lists show the bill's own days first. No database change.

### Changed

- **Learned bank names ignore codes:** a bill that learned a bank line's name now also takes lines whose name differs only by numbers or a code after `*` or `#`. A bill taught "AMAZON MKTPL*2K4AB1" takes next month's "AMAZON MKTPL*9XZ3", while "AMAZON PRIME" is still a different name. (1.80.0, #230)
- **Shorter lists when matching by hand:** Match… and "Paid by a bank line…" now show only what falls within the bill's own bank-match days (5 days for a planned line that isn't a bill), with "Show N more, up to 60 days away" for the rest. When nothing falls within those days, everything shows, with a line saying so. (1.81.0, web 1.96.0, #231)

## [1.79.0] — 2026-11-18

App version: **1.79.0** · Web version: **1.95.0** · Schema version: **31** · iOS version: **0.17.1**

Matching bank lines by hand, rebuilt: a pop-in that shows the bank line and the planned lines side by side in words, matching from Forecast, and bills that learn which bank lines are theirs. Schema 31 is added on start-up.

### Added

- **Match bank lines from Forecast:** a line from your bank that paid no planned line yet shows an "Unmatched" mark on Forecast, and its open line has Match…, which opens the same box as on Settings → Bank sync. A planned line's open line has "Paid by a bank line…", which lists the unmatched bank lines within 60 days of it, closest first, with "This paid it" on each. Either way, Forecast then shows one paid line where there were two. Only the account's owner sees these buttons. (1.78.0, web 1.94.0, #223)
- **Bills learn which bank lines are theirs:** when you match a bank line to a bill by hand, a ticked box "Match lines named … from now on" teaches the bill that name. From then on, a new line with that name pays that bill when it lands within the bill's ± days, whatever the amount, so a bill that varies (power, phone) is matched too, and it wins over other bills that fit by amount. Lines with that name already on the Unmatched list are matched straight away when they fall within the bill's days, and the note says how many. The bill's editor shows the name it learned, with Forget. (1.79.0, web 1.95.0, #224)

### Changed

- **Matching a bank line by hand is a pop-in:** Match… on Settings → Bank sync → Unmatched (and on Email alerts) now opens a box with the bank's line at the top (name, amount, date and the bank's full text) and a card for each planned line it could pay. Each card says in plain words how the bank's line compares, such as "$2.17 more · 1 day earlier", the closest one is highlighted, and Pay this is on the card. A bill now shows once, at its nearest unpaid date, with its other dates in a menu on the card. Before, it was listed again for every date in the 60 days. (1.77.0, web 1.93.0, #222)

### Database

- Schema 31: bills keep the bank-line name they were taught, encrypted like the bank's text on a line. Added on start-up. (#224)

## [1.76.3] — 2026-11-17

App version: **1.76.3** · Web version: **1.92.0** · Schema version: **30** · iOS version: **0.17.1**

No server change: this release holds the web app's links to SimpleFIN Bridge.

### Added

- **Links to SimpleFIN from the bank sync pages:** Settings → Bank sync and Admin → Bank sync now start with a line linking to SimpleFIN Bridge's sign-in page, your SimpleFIN account and the page that makes a setup token, each opening in a new tab. (web 1.92.0, #227)

### Fixed

- **SimpleFIN links go to the right page:** the "make a setup token" and "disable the token" links opened SimpleFIN Bridge's homepage, because SimpleFIN's old address now sends every page there. They now open the page they name. (web 1.92.0, #227)

## [1.76.2] — 2026-11-17

App version: **1.76.2** · Web version: **1.91.0** · Schema version: **30** · iOS version: **0.17.1**

No server change: this release holds the iPhone app's upside-down portrait, which put it on TestFlight.

### Changed

- **The iPhone app turns upside down too:** it now follows the phone into upside-down portrait as well as portrait and both landscapes. The App Store requires this of an app that can open a second window, as WalletWeather can on the Duo, and it lets the app go on TestFlight. (iOS 0.17.1)

## [1.76.1] — 2026-11-18

App version: **1.76.1** · Web version: **1.91.0** · Schema version: **30** · iOS version: **0.17.0**

No server change: this release holds the web app's new Unmatched tables.

### Changed

- **The Unmatched lists look like Forecast:** the lines that paid no bill (Settings → Bank sync, and Settings → Email alerts) are in a table with Forecast's columns and grid: Description, Actual date, Actual amt and Notes, with green and red amounts. **Match…** opens the planned lines a line can pay in the same style, with the date, the planned amount, how far the line's amount is from it (Δ Amt, coloured as in Forecast) and how many days apart. (web 1.91.0, #220)

## [1.76.0] — 2026-11-17

App version: **1.76.0** · Web version: **1.90.0** · Schema version: **30** · iOS version: **0.17.0**

### Added

- **Make a new account from a bank account (Settings → Bank sync):** a bank account with no match has a **New account…** choice in its Your account list. Pick it, check the name (it starts as the bank's own), and Save matches makes the account, matches it from the "Bring in from" date and syncs straight away. Its starting balance is worked out from the bank's balance and the lines that come in, so its balance today is the bank's. If the sync can't run (the day's limit, SimpleFIN down) nothing is made, and you can try again. If the bank sends no balance, the account starts at 0 and says so. It uses one of the day's 20 syncs. (app 1.76.0, web 1.90.0, #215)
- For apps and scripts: `POST /api/bank/accounts` with `ref`, `name` and an optional `start_date`; browser session only. (#215)
- **Bank sync in the iPhone app:** Settings has a Bank sync card that says whether a bank is connected, when it last synced and how many lines came in or paid a bill, any error in plain words, and when it syncs by itself next. **Sync now** runs a sync from the phone (it isn't shown for a read-only sign-in), and over the day's limit the card says when it can run again, in the web app's words. With no bank connected it says connecting is done in the web app (Settings → Bank sync). Needs server 1.70.0 or later for the details, and 1.73.0 for the bill settings below. Try the demo shows a sample status. (iOS 0.17.0)
- **A bill's bank match settings in the iPhone app:** a bill or income's editor has a Bank sync section with the days either side and how far the amount may differ that let a synced bank line pay one of its dates, the same two settings as the web app's editor. (iOS 0.17.0)

## [1.75.0] — 2026-11-17

App version: **1.75.0** · Web version: **1.89.0** · Schema version: **30** · iOS version: **0.16.0**

Email alerts are still off unless an admin switches them on and sets
`MS_CLIENT_ID`, and they have still not been tried with a real Microsoft
mailbox.

### Added

- **Email alerts pay your planned bills:** an alert that comes in and is close to one of your bills or paychecks pays it instead of landing as a second line, the same way bank sync does. The bill's line in Forecast is marked paid at the alert's date and amount, with an "Email alert" mark. Close means the same account and direction, within the bill's own days and percent settings (5 days and 10% to start) of one of its unpaid dates; when two dates are equally close nothing is matched, so you choose. A wrong match can be un-matched from its row: the bill goes back to planned and the alert's line stays as its own line, and isn't matched again. (app 1.75.0, web 1.89.0, #209)
- **Alerts that paid no bill** are listed under Settings → Email alerts for each account, with a count: match one by hand to any planned line that isn't paid yet, or leave it as its own line (the same screen as bank sync's Unmatched list). The check log and Check now say how many of a check's lines matched a bill. (app 1.75.0, web 1.89.0, #209)
- For apps and scripts: forecast rows have `match_source` (`alert` or `bank`, null when nothing paid the line); the Unmatched endpoints under `/api/accounts/{id}/bank-unmatched` and `POST /api/transactions/{id}/bank-unmatch` now cover alert lines too, each line with a `source`; `GET /api/mail` has `unmatched` (accounts and counts), and check results and the check log have `matched`. (#209)

### Database

- Schema 30: a column on the mailbox's check log for how many alerts matched a bill. Added on start-up. (#209)

## [1.74.0] — 2026-11-17

App version: **1.74.0** · Web version: **1.88.0** · Schema version: **29** · iOS version: **0.16.0**

Email alerts are still off unless an admin switches them on and sets
`MS_CLIENT_ID`, and they have still not been tried with a real Microsoft
mailbox.

### Added

- Email alerts now check your mailbox by themselves: every 5, 15 or 60 minutes, as you choose under Settings → Email alerts (it starts at 5), so a purchase shows up within minutes without pressing Check now. The tab says when the next check is due, or why checking is waiting (no folder yet, nothing taught, or switched off by an admin) or has stopped (Microsoft no longer accepts the sign-in: disconnect and connect again). A failed check is tried again at the same interval. The Dashboard shows a warning when checks have been failing for more than a day, the sign-in needs making again, or alerts couldn't be read. (#207)
- A Check log under Settings → Email alerts: every check that brought something in or failed, newest first, whether it ran by itself or by Check now, how many lines came in, were already there or couldn't be read, and any error; Show lines lists what a check brought in. Checks that found nothing new aren't listed. Only you see it, and entries are kept as long as the audit log (180 days unless changed). (#207)
- For apps and scripts: `GET /api/mail/status` gives the mailbox's state and can be read with any API token, and `POST /api/mail/check` (Check now) works with a token that has write access. (#207)

### Database

- Schema 29: a table for the mailbox's check log, a column on the mailbox for how often it's checked, and a column on transactions naming the check that brought a line in. Added on start-up. (#207)

## [1.73.0] — 2026-11-17

App version: **1.73.0** · Web version: **1.87.0** · Schema version: **28** · iOS version: **0.16.0**

Email alerts (below) are off unless an admin switches them on and sets
`MS_CLIENT_ID`. They have been tested only against a stand-in for Microsoft,
never with a real mailbox, so treat them as a first try.

### Added

- **Bank sync pays your planned bills:** a synced line that's close to one of
  your bills or paychecks pays it instead of landing as a second line. The
  bill's line in Forecast is marked paid at the bank's date and amount, with
  a "Bank sync" mark. Close means the same account and direction, within 5
  days and 10% of one of the bill's unpaid dates; each bill has its own two
  settings in its editor. When two dates are equally close nothing is
  matched, so you choose. A wrong match can be un-matched from its row: the
  bill goes back to planned and the bank's line stays as its own line, and
  isn't matched again. (app 1.73.0, web 1.87.0, #196)
- **An Unmatched list for each bank-synced account** (Settings → Bank sync):
  synced lines that didn't pay a bill, with a count beside the account. Match
  one by hand to any planned line that isn't paid yet, or leave it as its own
  line. Lines synced before this version are on the list too. The sync log
  now also counts the lines that paid a bill. (app 1.73.0, web 1.87.0, #196)
- For apps and scripts: bills and income have `match_days` and
  `match_percent`; forecast rows have `bank_match`; new endpoints under
  `/api/accounts/{id}/bank-unmatched` and `POST
  /api/transactions/{id}/bank-unmatch`. (#196)
- Email alerts, first part: switch on your bank's email alert for every transaction, and WalletWeather reads those emails from one folder of your Microsoft 365 or Outlook.com mailbox and adds each as a paid line, named after the merchant, with your auto-tag rules run on it. The person who runs the server registers a free Microsoft app and sets `MS_CLIENT_ID`, then switches email alerts on in Admin → Email alerts (off until then). Each user connects their own mailbox in Settings → Email alerts, by typing a code at Microsoft's sign-in page (or with a Connect button on servers reached over `https://` that also set `MS_CLIENT_SECRET`), picks the folder and the day to read from, and teaches it their bank's alert once: WalletWeather highlights what it thinks are the amount, merchant, date and card digits in a sample, and you correct any by selecting the right words. Check now brings alerts in; an email is never brought in twice. Alerts that couldn't become lines are listed with the reason, to teach from or dismiss. With two-factor sign-in on, connecting and disconnecting ask for a code. Checking by itself, Gmail, matching alerts to bills and joining them to bank sync come in later versions; until then an account matched to bank sync can't take alerts. See the [setup guide](https://mkolakowski.github.io/WalletWeather/email-alerts.html). (#206)

### Security

- Email alerts make the server call Microsoft (login.microsoftonline.com and graph.microsoft.com only) for users who connect a mailbox, and only then. It asks for read-only mail access and never changes the mailbox. The sign-in is stored encrypted, never shown or logged, and goes only into encrypted backups, never "Download my data". Alert emails are read as plain text, with no link followed and no image fetched; a mail that fails the mailbox provider's own check that it came from the bank's domain never becomes a line ("may not be from your bank"); one check brings in at most 50 lines. `PRIVACY.md` and `SECURITY.md` say what leaves the server, what's stored and what the sign-in can read. (#206)

### Database

- Schema 28: two match settings on bills and income, three columns on
  transactions for lines paid by bank sync (how they were matched, the bank's
  own text, and whether one was left as its own line), and a matched count in
  the sync log. Added on start-up. (#196)
- Schema 27: tables for a user's mailbox, the banks taught and their kinds of alert, and alerts that didn't become lines, and a column on transactions naming the email a line came from. Added on start-up. (#206)

## [1.71.0] — 2026-11-16

App version: **1.71.0** · Web version: **1.85.0** · Schema version: **26** · iOS version: **0.16.0**

### Changed

- **Bank-synced lines get short names:** some banks send the whole ACH
  record as a transaction's description ("Withdrawal Example Internet /
  TYPE: … ID: … ACH Trace Number: …"). Bank sync now names such a line after
  the company, the part before " / " without "Withdrawal" or "Deposit", and
  keeps the bank's full text in the line's notes. Lines already synced are
  shortened the same way when the server starts, after any notes of their
  own. Lines you renamed or added by hand are left alone. Auto-tag rules
  still match the bank's full text, and nothing is synced twice. (app 1.71.0)

## [1.70.0] — 2026-11-16

App version: **1.70.0** · Web version: **1.85.0** · Schema version: **26** · iOS version: **0.16.0**

### Added

- Bank sync now runs by itself about once a day for everyone with a bank connected; Settings → Bank sync says when the next one is due, and Sync now still works any time. A failed sync is tried again about 6 hours later, and if SimpleFIN stops accepting your connection the tab says so and the daily sync waits until you connect again. The Dashboard shows a warning when bank sync has been failing for more than a day. A daily sync and Sync now never run at the same moment, and both count toward the 20 syncs a day. (#195)
- A sync log for each matched account (Settings → Bank sync → Sync log): every sync, newest first, whether it ran by itself or by Sync now, how many lines came in and how many were already there, and any error; Show lines lists what a sync brought in. Only the account's owner sees it, and entries are kept as long as the audit log (180 days unless changed). (#195)
- For apps and scripts: `GET /api/bank/status` gives the sync's state and can be read with any API token, and `POST /api/bank/sync` (Sync now) works with a token that has write access. (#195)

### Database

- Schema 26: a table for the sync log, two columns on bank connections (the last sync that worked, and whether it needs connecting again), and a column on transactions naming the sync that brought a line in. Added on start-up. (#195)

## [1.69.0] — 2026-11-16

App version: **1.69.0** · Web version: **1.84.0** · Schema version: **25** · iOS version: **0.16.0**

### Added

- Bank sync, first part: transactions can come straight from your bank through [SimpleFIN Bridge](https://bridge.simplefin.org/), a service you subscribe to yourself (about $15 a year). An admin switches it on in Admin → Bank sync (it's off until then). Each user then has a Bank sync tab in Settings: paste the setup token from SimpleFIN Bridge, match each bank account to one of your own accounts with a date to start from (today, or up to 90 days back), and press Sync now. Only lines the bank has posted come in, as paid lines, your auto-tag rules run on them, and a line already there (by CSV or by hand) isn't brought in twice. Disconnect forgets the connection; the lines already brought in stay. With two-factor sign-in on, connecting and disconnecting ask for a code. Admin's user list shows who has a bank connected. Syncing on a schedule comes in a later release. (#194)

### Security

- Bank sync makes the server call out to SimpleFIN for users who connect a bank, and only then. A pasted token may only point at SimpleFIN (the hosts in the new `SIMPLEFIN_HOSTS` setting, SimpleFIN Bridge by default); the address SimpleFIN issues is stored encrypted, never shown or logged, and goes only into encrypted backups, never "Download my data". Sync now stops after 20 calls in 24 hours, since SimpleFIN disables a token that asks much more often. `PRIVACY.md` says what leaves the server and what's stored. (#194)

### Database

- Schema 25: two new tables for bank connections and the bank accounts matched to yours, and a column on transactions holding a hash of the bank's own id for each synced line. Added on start-up; nothing existing changes. (#194)

## [1.68.1] — 2026-11-16

App version: **1.68.1** · Web version: **1.83.0** · Schema version: **24** · iOS version: **0.16.0**

### Fixed

- `BACKUP_PASSPHRASE` set in `.env` now reaches the app. In 1.68.0, `docker-compose.yml` didn't pass it to the container, so Admin kept saying it wasn't set and system backups didn't run. Update your `docker-compose.yml` from this release (or add the line `BACKUP_PASSPHRASE: ${BACKUP_PASSPHRASE:-}` under the app's `environment:`), then run `docker compose up -d`. (#200)

## [1.68.0] — 2026-11-16

App version: **1.68.0** · Web version: **1.83.0** · Schema version: **24** · iOS version: **0.16.0**

### Security

- Backups are now encrypted with a passphrase, so a backup file on its own can't be read. Settings → Backup asks you for one (twice) when you download a backup, and again when you restore it. Nobody can recover a lost passphrase, not even the person running the server, so write it down somewhere safe. A wrong passphrase, or a damaged file, is refused and nothing is changed. Backups made by earlier versions still restore, with a note that the file wasn't encrypted: delete those once you have a new one. (#193)

### Changed

- **Breaking:** the scheduled system backups and Admin's "Run backup now" are encrypted with `BACKUP_PASSPHRASE`, a new setting in `.env` (at least 12 characters, see `.env.example`). Until you add it they don't run, and Admin → System backups says so. Keep a copy of it somewhere other than the server: it's the only way to open those backups. Admin's list of backups now says which files are encrypted. (#193)
- Settings → Your account has a "Download my data" button: a plain, readable JSON copy of your data, for you to read or take elsewhere. It isn't a backup and isn't encrypted. (#193)

## [1.67.1] — 2026-11-16

App version: **1.67.1** · Web version: **1.82.0** · Schema version: **24** · iOS version: **0.16.0**

### Security

More from the security review (plan: `Plans/security-fixes.md`, #190).

- **Breaking: the server won't start with a guessable `SESSION_SECRET`.**
  Anyone who knows that secret can sign themselves in as any user, and the
  server used to start with it empty or left as `.env.example` has it. It
  now refuses to start when the secret is empty, shorter than 16 characters
  or still `replace_with_random_string`, and says so in its log. Check your
  `.env` before updating. (#185)
- **Upper limits on what's accepted:** names, descriptions and passwords
  have maximum lengths (a description 500 characters, an account name 120),
  a request over 25 MB is refused (`MAX_BODY_MB` in `.env` changes that),
  and a forecast or report can't span more than ten years. Before, a very
  long name at sign-up was a server error and a request could be any size.
  (#185)
- **Amounts must be real numbers:** `NaN` and `Infinity` were accepted as
  amounts, from the API, a CSV or a backup, and every page showing that
  account then failed. They're refused now, as is an amount past a
  trillion. (#185)
- **A bill needs a schedule the forecast can run:** a recurring item must be
  weekly, biweekly or monthly, with a start date (weekly, biweekly) or a
  day of the month from 1 to 31 (monthly). One saved without was never
  projected, and a day of 0 broke the forecast. (#185)
- **Breaking: changes made from another site's page are refused.** A page
  on another address, including another app on the same home domain, could
  ask your browser to make a change here while you were signed in; only the
  cookie's settings stood in the way. The server now answers 403 to any
  change a browser says comes from elsewhere. If you reach the app through
  a reverse proxy that rewrites the `Host` header, set `APP_BASE_URL` to
  the address you open (or list addresses in `TRUSTED_ORIGINS`), or saving
  will be refused with a message saying so. API tokens, scripts and the
  iPhone app are unaffected. (#187)
- **The usual security headers:** pages and answers can no longer be shown
  inside another site's frame, browsers are told not to guess file types or
  pass the address on to other sites, and answers about you aren't kept in
  any cache. (#187)
- **The API's built-in documentation pages are off:** `/docs`, `/redoc` and
  `/openapi.json` described every route to anyone who asked. The README
  documents the API. (#187)
- **Updated libraries with known security advisories:** the web framework
  (FastAPI 0.163.1 with Starlette 1.10.0), the Google sign-in library
  (Authlib 1.9.8) and the cryptography library (50.0.2) were behind fixes
  for 38 published advisories between them. Few could be reached in the
  way WalletWeather uses them, but one could (see 1.62.0's note on required
  two-factor). Two libraries nothing used, python-multipart and
  APScheduler, are no longer in the image. If you use Google sign-in, try
  it once after updating. (#188)
- **A tighter container:** `docker-compose.yml` now runs the app with a
  read-only file system (it writes only to the backups volume), no Linux
  capabilities and no way to gain privileges. Copy those lines into your
  own compose file if you keep one. (#188)
- **Changing your password signs out your other browsers:** a session
  used to stay good for two weeks whatever happened, so a browser someone
  else was signed in on survived a password change. Now a password change,
  and switching two-factor sign-in on or off, signs out every browser but
  the one you're using, and Settings → Change password has a
  **Sign out my other browsers** button that does only that. Apps and
  scripts signed in with an API token keep working. When an administrator
  resets someone's password, that user's browsers are signed out and
  their API tokens stop too. Nobody is signed out by the update itself.
  (#186)

- **Breaking: sharing an account is by invitation.** The Sharing page used
  to list every user's email and name to anyone with an account, and a
  share took effect without the other person's say. Now you type the
  person's email under Settings → Sharing; they see the invitation the
  next time they open WalletWeather and the account appears for them once
  they accept. Nobody can look up who else uses the instance, and nobody
  can put an account on your dashboard uninvited. Existing shares stay as
  they are. People you share with can leave an account themselves.
  (`GET/POST /api/invitations`, `POST /api/invitations/{id}/accept`,
  `DELETE /api/invitations/{id}`; `POST /api/permissions` no longer gives
  access to someone new.) (#189)
- **Breaking: only an owner changes who has access.** An editor could give
  anyone read or edit access to an account they'd been let into, and
  remove other people. Now that takes an owner. (#189)
- **Breaking: the first Google sign-in to a user removes its password.**
  If a user already has a password when Google sign-in first links to it,
  someone else may have registered that address first and still know the
  password. So the password is removed, along with two-factor, every
  session and every API token of that user: only the address's Google
  owner is left. If that's you, and you want a password as well, an
  administrator can set one, and the iPhone app signs in again. (#189)
- **Sign-in limits that don't depend on one address:** five wrong
  passwords for an email from one address already paused that pair. Now 20
  wrong passwords for an email from all addresses together pause the
  email, 50 from one address across all emails pause the address, and one
  address can register 10 users an hour. All three are settings (see
  `.env.example`). (#189)

### Fixed

- **Saving a line with a tag one of your tag rules also adds:** if you
  ticked a tag on a transaction and one of your own tag rules would have
  added that same tag, saving failed with a server error. The same
  happened importing a CSV row with that tag. It saves now, with the tag
  on the line once. (#182)
- **Notes survive a backup:** a backup held every note, but importing one
  never read them, so notes on bills and transactions were lost on every
  restore. They come back now. Backups you already have contain the notes,
  so importing one again restores them. (#191)

### Database

- **Schema 23:** `users.session_epoch`, the number a session has to carry
  to still count. (#186)
- **Schema 24:** `account_invitations`, offers of access waiting for an
  answer. (#189)

## [1.62.0] — 2026-11-16

App version: **1.62.0** · Web version: **1.79.0** · Schema version: **22** · iOS version: **0.16.0**

### Security

These come from a security review of the server (#178). Update if other
people can reach your instance.

- **Colours can no longer carry anything but a colour:** a category's or
  tag's colour could be any text, and the web app wrote it into the page
  as it was. Someone you share an account with could have
  used that to run their own script in your browser. A colour is now a hex
  colour (like `#58a6ff`) or nothing, wherever it comes in, an imported
  backup included, and the web app checks again before using one. (#183)
- **Breaking: an administrator's address can't be registered by whoever
  types it first.** Registering with a password doesn't prove you own the
  address, so anyone could register an address listed in `ADMIN_EMAILS`
  before its owner and become an administrator. Now such an address can be
  registered only while the instance has no users at all (so set yours up
  first on a new install). After that, an administrator adds it under
  Admin → User management. Addresses in the demo's own domain
  (`@demo.walletweather.local`) can't be registered either. (#183)
- **A registration code:** set `REGISTRATION_CODE` in `.env` and the sign-up
  form asks for it, so only people you gave it to can make a user. Use it,
  or `ALLOW_REGISTRATION=false`, on any instance strangers can reach. With
  a code set, Google sign-in makes new users only for addresses on
  `ALLOWED_EMAILS`. (#183)
- **Required two-factor can't be sidestepped:** when an admin requires
  two-factor sign-in, a user who hadn't set it up yet could reach the rest
  of the app with a specially written request. The hold now goes by the
  address the request was really sent to. (#183)
- **A line can only belong to a bill on its own account:** a transaction
  could name any recurring item, including one on an account its maker
  couldn't see, and deleting that line struck the date from the other
  person's bill. Marking a bill paid also accepted any category, which
  showed its name. Both are now refused with 404. (#183)
- **Google sign-in needs a verified address:** an address Google hasn't
  verified no longer signs in, links to or creates a user. (#183)

### Added

- **Try the demo in the iPhone app:** the Connect screen has a Try the demo
  button under Sign in. It opens the app on sample numbers built into it, so
  you can look around every page before setting up a server, and it's how
  Apple's reviewer will get in. A bar at the top of each page says it's the
  demo, with Leave to go back. Editors open as usual, but nothing you change
  is saved. The demo connects to nothing and keeps nothing on the phone.
  (iOS 0.16.0)
- **A privacy manifest in the iPhone app:** it tells Apple the app does no
  tracking and collects no data, and why it reads its own settings and the
  dates of the numbers it keeps. The privacy policy now also mentions the
  demo, the tab bar and Getting started settings, and that a sign-in is named
  after the phone. (iOS 0.16.0)
- **Add a user from the Admin panel:** Admin → User management has an Add a
  user form (email, optional name, a password you pass on). It works with
  registration switched off and needs no registration code
  (`POST /api/admin/users`, logged as `user_created`). (#183)

### Database

- **Schema 22:** category and tag colours that aren't hex colours are
  blanked when the server starts; those categories and tags show without a
  colour until you pick one again. (#183)

## [1.61.1] — 2026-11-16

App version: **1.61.1** · Web version: **1.78.0** · Schema version: **21** · iOS version: **0.15.0**

No server change: this release holds the iPhone app 0.15.0, which landed
just after v1.61.0 was tagged.

### Added

- **Four more Getting started tasks in the iPhone app:** Lock the app (only
  on a phone with Face ID or Touch ID), Choose a look, Mark a bill paid and
  Try Search. Each opens a short sheet that explains it and takes you there.
  Each ticks itself once you've done it: the lock turned on, a look picked
  (or Keep this look), a line marked paid in Forecast, a first search. One
  you've already done, like the lock being on, starts ticked. If you'd
  already finished the tab bar task, the card comes back once for the new
  ones. (iOS 0.15.0)

## [1.61.0] — 2026-11-16

App version: **1.61.0** · Web version: **1.78.0** · Schema version: **21** · iOS version: **0.14.0**

### Added

- **A Getting started card in the iPhone app:** the Dashboard opens with a
  short list of things worth trying, the first being "Make the tab bar
  yours". It opens a sheet that shows the bar, with Swap beside each of its
  three pages and a picture of the bar that follows your swaps. Save puts
  the new bar in place. The task is ticked once you've saved there or
  changed the bar in Settings → Tab bar. The card goes for good once every
  task is done, or when you close it. It shows on new sign-ins, and once
  after updating if you're already signed in. (iOS 0.13.0)
- **Admins can require two-factor sign-in:** Admin → Two-factor sign-in has
  a "Require two-factor sign-in" switch, with a count of the users who
  haven't set it up yet. Once it's on, everyone who signs in with a password
  and hasn't set up two-factor sees only a set-up screen after signing in,
  until they've scanned the QR code and saved their recovery codes. Users
  who sign in only with Google aren't asked. You have to set up your own
  first. If you switch off someone's two-factor while it's required, they
  set it up again at their next sign-in. (app 1.60.0, web 1.77.0)

### Changed

- **Breaking: the iPhone app's More tab is now Settings, and a tab bar
  along the bottom holds three pages:** with four pages, More and Search, an
  iPhone held upright had more buttons than iOS shows, so iOS added a second
  More page of its own. Now the bar is three pages, Settings (a gear) and
  Search. Where the bar runs down the side of a tall screen, as on the
  iPhone Duo closed upright or open on its side, it holds a fourth page.
  Along the bottom, or with the closed Duo on its side, the fourth page
  waits in Settings. The bar comes with Dashboard, Forecast and Bills &
  income. The pages not in the bar are listed at the top of Settings under
  Other pages. Settings → Tab bar has a Swap button on each page to put
  another page in its place. A bar of four you chose before is kept, and
  shows its first three along the bottom. (iOS 0.12.0, 0.14.0)
- **Breaking:** **With two-factor sign-in on, a few things now ask for a
  code from your authenticator app (or a recovery code) every time:**
  changing your password, deleting your account, making an API token, and
  letting the iPhone app in on its "Let the app in?" page. A code you've
  just used won't work twice, so if you've only just signed in with one,
  wait for the next. Scripts that make tokens or change the password through
  the API for such an account need to send `code` too. Accounts without
  two-factor are unaffected. (app 1.61.0, web 1.78.0)
- **While two-factor is required, a user who hasn't set it up can't use
  their API tokens or the iPhone app either:** every request answers "This
  instance requires two-factor sign-in. Set it up in Settings in a browser
  first." until they do, and the app's email and password sign-in refuses
  them. Nothing changes while the switch is off.

### Security

- Switching the requirement on or off is recorded in the audit log, and only
  works from a browser session, not with an API token.
- Wrong codes on those actions, and when switching two-factor off or making
  new recovery codes, count toward the same limit as wrong codes at sign-in,
  so a browser left signed in can't be used to guess a code.

## [1.59.0] — 2026-11-15

App version: **1.59.0** · Web version: **1.76.0** · Schema version: **21** · iOS version: **0.11.0**

### Added

- **The iPhone app's email and password sign-in takes a two-factor code:**
  if your account has two-factor sign-in on, a Code field appears under the
  password after the first try. Type the code from your authenticator app
  (or a recovery code) and sign in again. It needs server 1.59.0 or later;
  with an older server, use Sign in (the browser sheet) as before. For
  scripts: `POST /api/auth/token` takes an optional `code`, and answers 403
  with `"two_factor_required": true` when one is needed or wrong.
  (app 1.59.0, iOS app 0.11.0)
- **Remember this browser for two-factor sign-in:** the code step now has a
  "Don't ask on this browser for 30 days" tick box. Tick it, and for the next
  30 days your email and password alone sign you in on that browser; other
  browsers still ask for a code. Settings → Your account → Two-factor sign-in
  lists the browsers you've remembered (with "This browser" marked), and you
  can forget any of them, or all at once. Changing your password, switching
  two-factor off, or an admin switching it off or resetting your password
  forgets every remembered browser. (app 1.58.0, web 1.76.0)

### Database

- Schema 21: a new `remembered_browsers` table holds each remembered
  browser's short name (like "Safari on iPhone"), when it was remembered and
  last used, when it runs out, and a hash of its cookie (never the cookie
  itself). The server creates it when it starts.

### Security

- A remembered browser skips only the code, never the password, and wrong
  passwords are still limited as before. The browser's cookie is HttpOnly
  and marked Secure when the app is reached over HTTPS. The audit log
  records a browser remembered and browsers forgotten.

## [1.57.0] — 2026-11-15

App version: **1.57.0** · Web version: **1.75.0** · Schema version: **20** · iOS version: **0.10.0**

### Added

- **Two-factor sign-in:** in Settings → Your account you can switch on a
  second step for your password: a 6-digit code from an authenticator app on
  your phone (any app that scans a QR code for sign-in codes). Setting it up
  shows a QR code to scan and ten one-time recovery codes to keep somewhere
  safe; each recovery code signs you in once if you don't have your phone.
  After that, signing in with your email and password asks for a code. You
  can switch it off or get new recovery codes there too, with your password
  and a code. Signing in with Google is unchanged: Google has its own
  two-step check. (app 1.57.0, web 1.75.0)
- **Admins can switch a user's two-factor sign-in off** in Admin → Users, for
  someone who has lost their phone and their recovery codes. The Users list
  shows who has it on. An admin can't switch it on for anyone, and resetting
  a user's password leaves it on.

### Changed

- **The iPhone app's email and password sign-in refuses an account with
  two-factor sign-in on**, with a message to sign in through the browser
  instead, which asks for the code and works as before
  (`POST /api/auth/token` answers 403). Accounts without two-factor are
  unaffected.

### Database

- Schema 20: `users` gains `totp_secret_enc` (the authenticator key,
  encrypted with `ENCRYPTION_KEY`), `totp_enabled_at` and `totp_last_step`,
  and a new `recovery_codes` table holds the recovery codes as hashes. The
  server adds them when it starts; existing users have two-factor off.

### Security

- Two-factor sign-in (above) means a stolen password alone no longer opens
  an account that has it on. Wrong codes count toward the sign-in limit
  (`LOGIN_MAX_FAILURES` in `LOGIN_WINDOW_MINUTES`) for the account from any
  address, a code works only once, and a right password doesn't reset the
  count. The audit log records a password accepted with a code still to
  come, two-factor switched on or off (and by whom), a recovery code used
  and recovery codes remade.

## [1.56.0] — 2026-11-15

App version: **1.56.0** · Web version: **1.74.0** · Schema version: **19** · iOS version: **0.10.0**

### Added

- **Search everything from the top bar:** type in the search box to find
  transactions, bills and income, accounts, categories, tags and saved
  reports at once, grouped by kind. Each result shows one detail (a
  transaction's date, amount and account; a bill's amount and next date; an
  account's balance; how many transactions carry a category or tag). Choosing
  one opens it where it lives: a transaction or bill in its editor, an
  account in Forecast, a category or tag as its transactions, a report run.
  When the bar has no room, and on a phone, it's a magnifier that opens a
  full-width search. Search only finds what you can see. The server's new
  `GET /api/search` does the searching. (web 1.74.0)
- **Search everything in the iPhone app:** the round search button now finds
  transactions, bills and income, accounts, categories, tags and saved
  reports, grouped by kind. Tap a result to open it where it lives: a
  transaction or a bill in its editor, an account in Forecast, a category or
  tag as its transactions, a report run. On the open iPhone Duo the results
  stay on the left and what you tap opens on the right. With a server older
  than 1.56.0 it still searches transactions, and says an update finds the
  rest. Nothing about a search is kept on the phone. (iOS app 0.10.0)

### Fixed

- Forecast's Search transactions no longer shows an older search's results
  when two searches overlap.
- When a manual backup in the Admin panel fails with an error that has no
  message of its own, it now names it (for example "Backup failed:
  InvalidToken", which means a row can't be decrypted with the server's
  `ENCRYPTION_KEY`) instead of an empty "Backup failed:".

## [1.55.0] — 2026-11-15

App version: **1.55.0** · Web version: **1.73.0** · Schema version: **19** · iOS version: **0.9.0**

### Added

- **Sign in to the iPhone app with your email and password:** the Connect
  screen's **Other ways to sign in** now starts with an email and password
  form, for accounts that have a password. It makes the phone's token the
  same way the Sign in button does (full access, 90 days, listed in Settings
  → API tokens), and counts toward the same limit on failed sign-ins. If you
  sign in with Google, use Sign in instead. (iOS app 0.9.0)
- **Sign in to the iPhone app with a QR code:** in the web app's Settings →
  API tokens on a computer, a new token now has a **Show QR code** button.
  Choose **Scan a QR code** under Other ways to sign in on the phone and
  point it at the screen. The app asks for the camera only then, and asks
  before it connects. The phone's Camera app can open the code too. The code
  shows only when you ask for it and goes away with Done, since anyone who
  can see it can use the token. (web 1.73.0)

### Changed

- On the iPhone app's Connect screen, a problem signing in now shows beside
  the way you tried, instead of always at the top.

## [1.54.3] — 2026-11-15

App version: **1.54.3** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.8.1**

### Added

- **Choose the iPhone app's tab bar:** More → This phone → Tab bar lets you
  switch pages on or off and drag them into order. Net worth, Budgets and
  Reports can go in the bar too. More and Search always stay, with room for
  four pages beside them, and pages not in the bar are listed at the top of
  More. (iOS app 0.8.0)
- **An app icon** for the iPhone app: a sun behind a cloud with WalletWeather's
  green upward line, with dark and tinted versions for the home screen.

### Changed

- The iPhone app's line editor always shows **Actual amount** and **Actual
  date**, filled in with the planned ones. Changing either marks the line
  paid; the Paid switch undoes that. (iOS app 0.8.1)
- The iPhone app's More page is made of cards like the other pages, in every
  look, instead of a plain settings list.
- **Breaking:** in the iPhone app's Forecast, swiping right on a paid line
  now offers **Edit** instead of Undo paid; to undo, open the line and turn
  Paid off. Unpaid lines offer Paid and Edit. (iOS app 0.8.0)
- Lines in Forecast's **To confirm** list now have an **Edit** button, and
  swipe like any other line: right to mark paid or edit, left to delete.
- The iPhone app now names its sign-in after the phone's model ("iPhone 16
  Pro Max") instead of just "iPhone", and the Connect screen has a **Name for
  this phone** field to change it before signing in. That name is what the
  web app's Settings → API tokens shows. (iOS only tells apps the name you
  gave your phone with a permission from Apple, so the model is the default.)

### Fixed

- The iPhone app's line editor, opened as a sheet, no longer runs its rows
  into the left edge of the screen.

## [1.54.2] — 2026-11-15

App version: **1.54.2** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.7.0**

### Added

- **To confirm, on the iPhone's Forecast** (iOS app 0.7.0): a switch beside
  All lines narrows the month to the lines due up to today and not yet paid,
  each with **Paid as planned** and a box for the amount it really came to.
  It's made for ticking lines off with your bank's app open beside
  WalletWeather on the iPhone Duo's inner screen, and works on any iPhone.
- **Compare, on the open iPhone Duo:** a Compare button on Forecast puts two
  accounts, or one account in two months, side by side, one in each half,
  lined up by day of the month so both sides scroll together.
- **Half open like a small laptop,** the iPhone Duo's Forecast puts the
  chart and lines above the fold and the open line (or the month's summary)
  below it, on the half that lies on the table.
- **A second WalletWeather window:** the app can now have more than one
  window, and Open in new window in each page's menu on the inner screen
  opens one on that page.
- **The web app's themes on the iPhone** (iOS app 0.6.0). More → Appearance
  now offers Dracula, Solarized, Nord, Synthwave, Forest, Mint, Monokai and
  Sunset beside Light, Dark, AMOLED black and Sepia, in the web app's colours.
  **Match the web app** uses the theme saved in the web app's Settings, and
  still applies when the app opens offline. Picking a look on the phone never
  changes the web app.

### Changed

- In the iPhone app's AMOLED black, Sepia and the web themes, the rows of
  More, the editors and the sheets now take the look's card colour instead of
  plain white or black. Light and Dark are unchanged.

### Fixed

- In the iPhone app's Sepia look, Delete, End… and Sign out were drawn in
  the brown text colour instead of red. They're red again, in every look.
- In the iPhone app with Last-known numbers, a page that was never loaded no
  longer shows the "Offline · as loaded …" bar above its "Can't reach the
  server" message.

## [1.54.1] — 2026-11-15

App version: **1.54.1** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.5.0**

### Added

- **Last-known numbers on the iPhone** (iOS app 0.5.0). When you sign in, the
  app asks what this phone should keep: **Nothing** (as before, the app needs
  a connection) or **Last-known numbers**, which keeps the pages you load so
  they still open when your server can't be reached, under a bar saying when
  they were loaded. Changes wait until the server answers again. The kept
  numbers can't be read while the phone is locked, stay out of iCloud and
  computer backups, and are deleted when you sign out or choose Nothing. You
  can change the choice in More → This phone. If you're already signed in,
  the app stays on Nothing until you change it there.

### Changed

- Signing out of the iPhone app also sets what the phone keeps back to
  Nothing, so the next sign-in is asked again.
- The privacy policy (`docs/privacy.md`) now says what the iPhone app keeps
  with Last-known numbers.

## [1.54.0] — 2026-11-15

App version: **1.54.0** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.4.0**

### Added

- **Net worth, Budgets and Reports in the iPhone app**, under More, read-only
  (iOS app 0.4.0, which needs server 1.54.0). Net worth shows the total today,
  how it moved, its chart (Month, 30 days or 90 days) and each account.
  Budgets shows this month's spending against each budget, what's left or how
  far over, and the categories with spending but no budget. Reports runs your
  saved reports; building or changing one stays in the web app.
- **Looks for the iPhone app:** More → Appearance offers Match the phone,
  Light, Dark, and two looks of the app's own, AMOLED black and Sepia.
- **The iPhone app lock:** WalletWeather offers once to lock itself with Face
  ID or Touch ID (at first sign-in, or after this update if you're already
  signed in), and you can change it in More. With it on, the app asks when it
  opens and when you come back after a minute or more away.
- The iPhone app now hides your numbers in the app switcher.
- `GET /api/networth`, `GET /api/budgets/progress` and
  `POST /api/saved-reports/{id}/run` take `today=`, so "this month" is the
  phone's month rather than the server's.

### Changed

- The privacy policy now says the iPhone app keeps its own settings on the
  phone (the look you picked and whether the lock is on), beside the sign-in.

## [1.53.0] — 2026-11-15

App version: **1.53.0** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.3.0**

### Added

- **Bills & income in the iPhone app** (iOS app 0.3.0, which needs server
  1.53.0): every bill and paycheck on all your accounts or one, with what
  they come to each month and what's left over, and each one's amount, how
  often it repeats and its next date. Tap one to change it, or **+** to add
  one. Swipe right to skip a date (pick from the next six), or left to end it
  after a date you choose; it then moves to **Ended**. On an iPhone Duo held
  open, the right half shows the tapped one, or the monthly totals and what's
  due in the next seven days.
- **The Calendar in the iPhone app**: the month with dots for each day's
  bills (red), income (green) and money moved (grey), today marked, and the
  tapped day's lines underneath. It shows all accounts, or one, which adds
  each day's closing balance. Held open, the Duo writes each day's net and
  balance into the month and shows the tapped day, or today's lines and
  balances, on the right.
- **Move money between two accounts** from the **+** menu on Forecast, Bills
  & income and Calendar, which now also holds the page's own Add. It's
  recorded as paid on both accounts.
- `GET /api/recurring` items now carry `next_date` and `next_dates` (the next
  six dates from today, leaving out skipped and already-paid ones).

### Fixed

- Changing or ending a bill on an account someone shared with you for editing
  no longer needs its category to be one of your own when you leave it as it
  was.

## [1.52.0] — 2026-11-15

App version: **1.52.0** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.2.0**

### Added

- **The iPhone app's Forecast page** (iOS app 0.2.0, which needs server
  1.52.0). Pick an account and page through its months; each line shows its
  amount, planned and paid dates, category and both balances. Swipe a line
  right to mark it paid as planned (dated its planned day, or today if you're
  paying early), or right again to undo; swipe left to delete it (a date of a
  repeating bill or paycheck is skipped, leaving the rest). Tap a line to mark
  it paid at a different amount or on another day, or to change its category
  and notes. **+** adds a one-off transaction, as spending or income, paid
  today unless you turn Paid off. On an iPhone Duo held open, the balance
  chart and the full table sit on the left and the tapped line's editor on
  the right; before you tap one, the right half shows the month against plan,
  what's still to come, what's past its date and not marked paid, the low and
  the high, and what was paid differently from plan. Closing the Duo
  mid-edit keeps the line open, with what you'd typed. A read-only account or
  token shows no editing.
- **Search in the iPhone app**: the round button beside the pages bar finds
  transactions by name or notes on every account you can see, and tapping one
  opens it to mark paid or change. Bills, accounts, categories and reports
  come later.
- `GET /api/me` now says what the API token in use may do (`token_access`:
  `read`, `full` or `admin`, or null in a browser), and each line of
  `GET /api/accounts/{id}/forecast` carries its `category_id`.

### Fixed

- Saving a line on an account someone shared with you for editing no longer
  needs its category to be one of your own when you leave the category as it
  was. Before, the line's category (the owner's) was refused, so the only way
  to save was to clear it.

## [1.51.0] — 2026-11-15

App version: **1.51.0** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.1.2**

### Added

- **Signing out of the iPhone app now ends its token** on your server, so it
  shows as revoked in **Settings → API tokens** straight away rather than
  staying usable until it expires. If the server can't be reached when you
  sign out, the app still signs out and tells you the token is still listed,
  to revoke there. Connecting the app to another server with the "Open in
  WalletWeather" button ends the old server's token the same way (iOS app
  0.1.2).
- `DELETE /api/tokens/current` ends the API token the request is signed with,
  and nothing else. Any token may do this, read-only ones too; a token still
  can't list, make or revoke other tokens. A signed-in browser gets a 400,
  since it has no token to end.

## [1.50.0] — 2026-11-15

App version: **1.50.0** · Web version: **1.72.0** · Schema version: **19** · iOS version: **0.1.1**

### Added

- **The iPhone app, version 0.1.1** (built from source for now; not on
  TestFlight or the App Store yet). It signs in to your own server with the
  phone's sign-in sheet (see below), with the "Open in WalletWeather" button
  in the web app's Settings, or with a pasted token; a Cloudflare service
  token can be entered under Advanced. It shows the Important notice at first
  sign-in, checks that the server is new enough (1.50.0 or later), and opens
  on a read-only Dashboard: "rest of this month", each account's balance
  today, month-end forecast and actual and the month's low and high, the
  charts with the Month / 30 days / 90 days switch, and pinned reports. On an
  iPhone Duo it uses one column when closed and two halves when open. Plain
  `http://` addresses work only on the home network, with a warning. The
  only thing it keeps on the phone is the sign-in, in the Keychain on that
  device; signing out removes it. Forecast, Bills & income, Calendar and
  Search come in the next versions. See `apps/ios/README.md`.

- **Signing in the iPhone app.** The coming WalletWeather app for iPhone signs
  in through a new page, `/app-sign-in`, which it opens in the phone's own
  sign-in sheet: you sign in there as you do on the web (email and password,
  or Google, and Cloudflare first if your server is behind Cloudflare
  Access), then tap **Allow**. The app gets its own API token, named after
  the phone, lasting 90 days, and listed in **Settings → API tokens**, where
  revoking it signs the app out. When your server is behind Cloudflare
  Access, the app is also handed your Cloudflare sign-in, so no Cloudflare
  service token is needed. Behind the page are two new endpoints:
  `POST /api/app-sign-in` (from a signed-in browser only) makes a one-time
  code that lasts five minutes, and `POST /api/app-sign-in/token` swaps it
  for the token; `GET /app-sign-in/cloudflare` hands back only the
  Cloudflare sign-in, for when it runs out.
- **Settings → API tokens → Open in WalletWeather**: on an iPhone, a token
  you've just made has an "Open in WalletWeather" button beside Copy, which
  hands the token and your server's address to the iPhone app. The app asks
  before it connects.
- `GET /api/dashboard` now gives each account card its balance today
  (`current_balance`, the same figure the Forecast page shows), and it and
  `GET /api/dashboard/charts` take the viewer's date as `today=`, as the
  Forecast already does, so "this month" is the viewer's month whatever time
  zone the server runs in.

### Database

- Schema 19 adds `app_sign_in_codes`, the one-time codes the iPhone app's
  sign-in page hands out. Only a fingerprint (SHA-256) of each code is kept,
  each works once, and they're removed with their user. The table is created
  on startup; nothing to do by hand.

## [1.49.0] — 2026-11-15

App version: **1.49.0** · Web version: **1.71.0** · Schema version: **18**

### Added

- **Admin → Audit log**: admins can now read the audit log, newest first,
  filter it by event or by part of an email address, and page back with
  **Load more**. When an entry names someone by number ("user #7"), the panel
  adds their email while that user still exists. The panel uses the new
  `GET /api/admin/audit`, which also works with an admin API token (not a
  read-only or full one).
- Old audit log entries are now deleted automatically, once a day, when
  they're older than `AUDIT_RETENTION_DAYS` (a new setting, 180 days by
  default, never less than 1). Add it to your `.env` to keep entries for a
  different time; it's listed in `.env.example`.
- **Settings → Your account → Change password**: change your own password by
  typing the current one and the new one twice (at least 8 characters). Users
  who sign in only with Google see a note instead, since they have no
  password here; an admin can still set one for them. The form uses the new
  `POST /api/me/password`, which works from a signed-in browser only, not
  with an API token. `GET /api/me` now also says whether you have a password
  (`has_password`).
- The audit log in the database now also records what people do, not only
  sign-ins: changing your own password, an admin resetting one, an admin
  disabling, enabling or deleting a user, an admin changing a permission, the
  instance title or the backup settings, a backup being made (by hand or on
  schedule), downloaded or restored, exporting or importing your own data,
  deleting your own account, and an API token being made or revoked. Each
  entry says who did it; when it was done to someone else, it names them by
  user number (for example "user #7"), never by email address. Entries never
  hold amounts, account names or passwords. A refused action (a wrong
  password, a missing permission) writes nothing.

## [1.47.1] — 2026-11-15

App version: **1.47.1** · Web version: **1.69.0** · Schema version: **18**

### Fixed

- Backups now include your tags, your tag rules and which tags are on each
  bill, income item and transaction. Before, exporting and restoring a backup
  (yours, or the scheduled and admin system backups) lost every tag. Restoring
  matches tags by name: your own are reused, missing ones are created, and
  importing the same file twice doesn't repeat tags or rules. Backup files are
  now version 4: older backups still import, but a version 4 file can't be
  imported by an older WalletWeather.

## [1.47.0] — 2026-11-15

App version: **1.47.0** · Web version: **1.69.0** · Schema version: **18**

### Changed

- On Bills & income, **+ Add recurring** now sits at the start of the table's
  controls row, with a divider after it, like Forecast's Add transaction, and
  the separate "Bills & income" panel above the totals is gone. On a phone it
  is a full-width button above the other controls. It still hides on accounts
  you can't edit.

## [1.46.1] — 2026-11-15

App version: **1.46.1** · Web version: **1.68.1** · Schema version: **18**

### Added

- **+ Add recurring** on Bills & income now opens a new line at the top of
  the table, like Forecast's Add transaction: a field under each column
  (Description, Start date, Ends, Category, Amount, Account, Repeats, Tags,
  Notes), with Save, **+ Another** and Cancel. The account is a dropdown on the
  All accounts tab and fixed on an account's own tab. The separate add form
  above the table is gone.
- Apps can sign in with an email and password and get an API token back,
  without opening Settings: `POST /api/auth/token` with `email`, `password`,
  a `name` for the token and `access` (`read` or `full`; admin tokens are made
  only in Settings). The token expires in 90 days unless the request asks for
  30, 365 or `null` (never), and it shows in your Settings list like any other.
  It shares the sign-in limit and the sign-in log with the web sign-in, so
  wrong passwords in an app count toward the same 15-minute pause. Accounts
  that only sign in with Google have no password, so they make a token in
  Settings instead.

### Changed

- **Breaking:** Bills & income amounts are entered signed, like Forecast's:
  negative for a bill, positive for income, in the new line and when editing.
  The Expense/Income dropdown is gone.
- **Breaking:** editing a Bills & income item no longer has a Day of month
  box: a monthly item repeats on its start date's day. An item saved without a
  start date opens with its next day-of-month date filled in, and saving the
  row keeps it (spreadsheet mode only saves it if you change something else on
  that row).
- Bills & income's date columns are now always wide enough to show a whole
  date while you edit (Category, Tags and Notes ask for less room). On a
  window narrower than about 1250px the table switches to the stacked cards it
  uses on phones instead of cutting dates off.
- Deleting a user (yourself in Settings, or someone else from the Admin page)
  now also removes their email address from the sign-in log. What happened
  and when stays in the log; whose it was doesn't. Entries already logged for
  users deleted before this release keep their email.

## [1.45.0] — 2026-11-15

App version: **1.45.0** · Web version: **1.67.0** · Schema version: **18**

### Changed

- Bills & income's table now uses Forecast's column layout: Description,
  Start date, Ends, Category, Amount, Account, Repeats, Monthly, Yearly, Tags
  and Notes, with the ✎ at the end of the Notes cell as on Forecast. Start date
  and Ends have their own columns (and Start date sorts), Repeats just says
  Weekly, Bi-weekly or Monthly (with the day when the start date doesn't
  give it), and an item's tags moved from under its description into the Tags
  column. Rows are as short as Forecast's, and opening one to edit no longer
  changes its height or moves any column.

## [1.44.0] — 2026-11-15

App version: **1.44.0** · Web version: **1.66.0** · Schema version: **18**

### Added

- API tokens can expire. When you make one under **Settings → Your account →
  API tokens**, pick 30 days, 90 days (pre-selected), a year or Never; an
  expired token is refused with `401` and shows as expired in the list. Over
  the API, `POST /api/tokens` takes `expires_in_days` (30, 90 or 365), and
  leaving it out still means the token never expires, so existing scripts and
  tokens carry on as before.
- Each token in Settings now shows when it was made, when it expires and when
  it was last used (or "Never used"), so an unused or forgotten token is easy
  to spot. The last-used time is updated at most once a minute.
- Admins can see and revoke everyone's API tokens. The Admin page has an **API
  tokens** panel listing each token's owner, name, access, expiry and last
  use (never the token itself), with **Revoke**; a revoked token stops working
  at once. As with your own tokens, this needs a signed-in browser: no API
  token, admin ones included, can list or revoke tokens
  (`GET /api/admin/tokens`, `DELETE /api/admin/tokens/{id}`).

- The server now keeps a log of sign-ins: each successful sign-in (with a
  password or Google), each failed one and each blocked one, with the email
  that was typed, the address it came from and when. Passwords are never
  recorded. There's no screen for it yet; an Admin page view comes in a later
  release.

### Changed

- On Forecast's new line, the Tags picker now fills all the free space to the
  right of the Repeats dropdown, with no column line between them. While the
  line is open, the headings above read "Repeats" and "Tags" over their
  fields, with no lines between the four columns they sit over, and the
  remaining column lines match the new line's. No column moves when the line
  opens.

### Database

- Two new columns on `api_tokens`, `expires_at` and `last_used_at` (schema 17).
  They're added automatically on start; nothing to do. Tokens made before this
  never expire.
- New `audit_events` table for the sign-in log (schema 18). It's created
  automatically on start; nothing to do.

### Security

- Password guessing is now limited. After 5 wrong passwords for the same email
  from the same address within 15 minutes, that email can't sign in from that
  address for 15 minutes after the last wrong one, even with the right
  password; the sign-in screen says how long to wait (the API answers `429`
  with `Retry-After`). It works the same for emails with no account, so it
  never reveals which emails exist. Change the numbers with
  `LOGIN_MAX_FAILURES` and `LOGIN_WINDOW_MINUTES` in `.env`. **Behind a
  Cloudflare Tunnel**, set `TRUST_PROXY_HEADERS=true` so the limit applies
  per visitor rather than to everyone at once, but only if the server can't
  be reached any other way.

## [1.42.0] — 2026-11-15

App version: **1.42.0** · Web version: **1.65.0** · Schema version: **16**

### Added

- WalletWeather can be installed on your phone. Open it in Safari (Share →
  **Add to Home Screen**) or Chrome (**Install app**), and it opens full screen
  with its own icon, named after your instance's title. With no connection, the
  installed app opens to a "You're offline" notice with **Try again**: your
  balances and transactions are never stored on the phone. Behind Cloudflare
  Access, an expired Cloudflare sign-in takes you to Cloudflare's sign-in page
  as before.

- Bills & income items can be tagged. The add form has a Tags picker; editing
  an item (or spreadsheet mode) shows one under its description, and an item's
  tags show as small chips under its description in the table. Tags carry
  through: the item's upcoming lines on Forecast show them, and a line saved
  from it starts with them. Clearing all of an item's tags in the picker
  removes them; lines already saved keep the tags they have.

## [1.41.0] — 2026-11-15

App version: **1.41.0** · Web version: **1.63.0** · Schema version: **16**

### Added

- API tokens, for scripts and (later) the phone apps. Make one under
  **Settings → Your account → API tokens**, give it a name and an access
  level, and copy it: it's shown only once. Send it as
  `Authorization: Bearer <token>` on any `/api/...` request. A **Read-only**
  token can only look; **Full access** can do anything you can except the
  Admin panel; **Admin** (offered only to admins) also reaches the Admin
  panel, and stops reaching it the moment you're no longer an admin. Revoking
  a token stops it at once. Tokens can't make or revoke tokens; that needs a
  signed-in browser. The README's "Using the API with a token" has an example.

- Tags now work on repeating lines in Forecast. The Tags picker on the new line
  stays available when you set Repeats, and the tags are saved with the
  repeating item. Its upcoming lines show those tags, opening one shows a Tags
  picker filled with them, and saving it keeps or changes them (clear them all
  and the line is saved with none).

### Database

- New `api_tokens` table (schema 16). Only a SHA-256 fingerprint of each token
  is stored, never the token itself. It's created automatically on start;
  nothing to do.

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

[Unreleased]: https://github.com/mkolakowski/walletweather/compare/v1.98.1...HEAD
[1.98.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.98.1
[1.98.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.98.0
[1.97.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.97.0
[1.92.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.92.0
[1.89.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.89.0
[1.88.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.88.0
[1.85.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.85.0
[1.82.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.82.0
[1.81.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.81.0
[1.79.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.79.0
[1.76.3]: https://github.com/mkolakowski/walletweather/releases/tag/v1.76.3
[1.76.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.76.2
[1.76.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.76.1
[1.76.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.76.0
[1.75.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.75.0
[1.74.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.74.0
[1.73.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.73.0
[1.71.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.71.0
[1.70.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.70.0
[1.69.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.69.0
[1.68.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.68.1
[1.68.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.68.0
[1.67.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.67.1
[1.62.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.62.0
[1.61.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.61.1
[1.61.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.61.0
[1.59.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.59.0
[1.57.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.57.0
[1.56.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.56.0
[1.55.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.55.0
[1.54.3]: https://github.com/mkolakowski/walletweather/releases/tag/v1.54.3
[1.54.2]: https://github.com/mkolakowski/walletweather/releases/tag/v1.54.2
[1.54.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.54.1
[1.54.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.54.0
[1.53.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.53.0
[1.52.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.52.0
[1.51.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.51.0
[1.50.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.50.0
[1.49.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.49.0
[1.47.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.47.1
[1.47.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.47.0
[1.46.1]: https://github.com/mkolakowski/walletweather/releases/tag/v1.46.1
[1.45.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.45.0
[1.44.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.44.0
[1.42.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.42.0
[1.41.0]: https://github.com/mkolakowski/walletweather/releases/tag/v1.41.0
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
