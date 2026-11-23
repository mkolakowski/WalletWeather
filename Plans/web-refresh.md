# Web refresh: a modern look for the web app

Tracking issue: #289

## Status

| Phase | Apps | Issue | State |
| --- | --- | --- | --- |
| 1. Surfaces, titles and controls | Web | #281 | Not started |
| 2. Four bugs the review found | Web | #282 | Not started |
| 3. Readable themes, web and iPhone | Web, iOS | #283 | Not started |
| 4. Settings, Admin and Reports | Web | #284 | Not started |
| 5. Forecast and Bills tables | Web | #285 | Not started |
| 6. Date format and row height settings | Server, Web | #286 | Not started |
| 7. Dashboard, Calendar, sign-in, phone | Web | #287 | Not started |
| 8. Top bar and account menu | Web | #288 | Not started |

Planned 2026-11-23 from the request "I would like to update some of the web applications design to be more modern, can you perform a review and create me an artifact with images showing before and afters for suggested changes". The review of web 1.107.0 made fifteen suggestions (01 to 15), showed a bolder sidebar direction (B) and found five bugs; its before and after pictures are on [the review page](https://claude.ai/artifact/SjuH49ZXMrDCG4xPE6ytaf) (private to Matthew). Scope, checks and eight design calls were decided the same day ([decision page](../docs/dev/decisions/web-refresh.md)).

Sessions: may span — eight phases, each ending with a look from Matthew at its screenshots; released once, after phase 8.

## Agents and tools

| Phase | Apps | Main session | Subagents | Why |
| --- | --- | --- | --- | --- |
| 1. Surfaces, titles and controls | Web | Sonnet | Sonnet: headless before and after screenshots; the full test run | Theme tokens and shared component styles from a settled design; no behaviour changes. |
| 2. Four bugs the review found | Web | Sonnet | Sonnet: screenshots at 1180px and 1440px | Four small fixes with known causes. |
| 3. Readable themes, web and iPhone | Web, iOS | Sonnet | Sonnet: `swift test` and a simulator screenshot through `with-simulator.sh`; headless screenshots in all ten themes | Values from a script, mirrored in `WebTheme.swift`, which a test pins to the stylesheet. |
| 4. Settings, Admin and Reports | Web | Sonnet | Sonnet: headless screenshots of every Settings tab and Admin section | Layout from the mock-up; Admin's sections follow the pattern Settings already has. |
| 5. Forecast and Bills tables | Web | Opus | Sonnet: screenshots of read view, an open line, the add row, Spreadsheet mode and the card fallback, at 1280, 1440 and 390px | The table styles are about 300 lines of rules that depend on each other (line editor, add row, Spreadsheet mode, card fallback, phone cards). |
| 6. Date format and row height settings | Server, Web | Sonnet | Haiku: find every place the web client prints a date; Sonnet: API tests for the two new fields | Two per-person settings stored like `chart_position`, and one date helper used everywhere. |
| 7. Dashboard, Calendar, sign-in, phone | Web | Sonnet | Sonnet: headless screenshots at 1440 and 390px | Component styles from the mock-up. |
| 8. Top bar and account menu | Web | Sonnet | Sonnet: screenshots at five widths, and a keyboard pass of the menu | New behaviour (a menu), and the search box's fit code depends on the bar's width. |

## Open questions

None. The eight design calls were decided on 2026-11-23 before the plan was written ([decision page](../docs/dev/decisions/web-refresh.md#2026-11-23-eight-design-calls)). A question that comes up while building goes here, with the phase it blocks.

## The plan

**Goal:** the web client looks current without moving anything people rely on. Every page, figure, column and theme stays where it is; what changes is how they are drawn: fewer nested boxes, real page titles, controls with clear weights, readable colours in every theme, and Settings and Admin laid out as sections.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/web-refresh.md)):

- **The whole review is built, and released once at the end.** Nothing is held back.
- **Each phase is checked by screenshots on its issue** (desktop and phone, Dark and Light), plus the full API test run. Matthew looks before the release.
- **Navigation is a refined top bar** with an account button; the sidebar (B) is not built.
- **Log out lives in the account menu.**
- **Column lines are dropped in read view only;** Spreadsheet mode keeps its grid. No setting.
- **Dates print as "Nov 12", with a Date format setting** to switch back to 2026-11-12.
- **All 21 failing theme colours are fixed, on the web and the iPhone.**
- **Admin splits into six sections:** General, Sign-in security, Bank and email, Users, Backups, Audit log.
- **The Forecast summary's figures sit by column,** led by the current balance.
- **Rows are roomier (36px), with a Compact setting** that restores 34px.

**Out of scope:**

- The sidebar (direction B).
- A hosted typeface: the system font stays.
- Moving or removing any page, figure or table column.
- Starting the Net worth chart's axis at the data's low instead of $0 (raised in the review, not asked for).
- Letting System pair any dark theme with any light one (raised in the review, not asked for).
- The iPhone app's own look. Only its copy of the web themes' colours changes (phase 3).

**What's there today:**

- `apps/web/index.html` holds everything: the stylesheet (lines 14 to about 1155), the markup and the script. Theme colours are CSS variables on `:root` and `:root[data-theme="…"]`: ten themes (Dark, Light, Dracula, Solarized, Nord, Synthwave, Forest, Mint, Monokai, Sunset), with System following the device between Dark and Light.
- `apps/ios/WalletWeatherKit/Sources/WalletWeatherKit/WebTheme.swift` copies eight of those themes' colours (page, panel, border, text, accent, good, bad, warn). `WebThemeTests` checks they still match the stylesheet.
- Per-person look settings are columns on `users` (`theme_preference`, `chart_position`), returned by `/api/me`.
- The web client has no automated tests of its look. The API tests don't render it.
- Tables that don't fit fall back to cards (`_twCheck`, `_twLabel`, #82). The Forecast table needs about 1,120px, which a window of about 1,250px or narrower can't give it.

**Reference material** in [`Plans/web-refresh/`](web-refresh/):

- `trial.css`: the stylesheet behind every After picture, as overrides on the shipped CSS. It is a reference for values and intent, not a patch: several rules use mock-up shortcuts (`nth-child` order, `[onclick^=]` and `[style*=]` selectors, `!important` over inline styles) that the real change replaces with markup.
- `mock-tweaks.js`: the markup changes the pictures needed, made in the browser (the mark, the account button, short dates, chart labels, Admin's sections, theme previews).
- `theme-contrast.py`: measures eight text and background pairs in each theme and prints the smallest fix for each failing one. Run it with `python3 Plans/web-refresh/theme-contrast.py`.
- `demo-compose.yml` and `capture.py`: the throwaway demo stack and the screenshot script every phase's check uses. The commands are at the top of `demo-compose.yml`.

**How every phase is checked:** a throwaway demo stack (`DEMO_MODE=true`, its own Compose project and port, never the real database) is opened headless with Playwright. Before pictures come from the commit the phase started on, After pictures from its last commit, at 1440×900 and 390×844, in Dark and Light. They go on a page whose link is posted on the phase issue. The full API test run passes. A phase that changes an interaction also lists numbered "How to test" steps.

**Versions:** each phase bumps `WEB_VERSION` and adds its changelog entries under `[Unreleased]`. Phase 3 also bumps the iOS version; phase 6 also bumps `APP_VERSION` and `SCHEMA_VERSION`. One release is cut after phase 8.

### Phase 1: Surfaces, titles and controls

Review suggestions 01 and 02.

**What changes:**

- **Dark and Light tokens:** calmer surfaces and softer borders; hairline, shadow and radius values (14px cards, 9px controls) that every theme gets; dark text on the accent in the Dark theme, which takes filled buttons from 2.5:1 to about 7.6:1.
- **Light theme depth:** a tinted page with white cards and a soft shadow, instead of grey panels on a white page.
- **Titles and labels:** page titles at 26px in sentence case; labels at 12.5px in sentence case. Capitals stay for table headers and the Forecast and Actual eyebrows.
- **Fewer frames:** Dashboard and Net worth lose their outer panel, so cards sit on the page.
- **Controls:** one neutral segmented control (Month, 30 days, 90 days; the account switcher); secondary buttons with a soft fill instead of an outline; dropdowns styled to match; destructive buttons tinted instead of filled red.
- **Footer** pinned to the bottom of short pages.

**What you have to do:** look at the screenshots on the issue.

**Done when:** before and after screenshots of Dashboard, Net worth, Forecast, Bills & income, Calendar, Reports, Settings and Admin are on the issue (1440 and 390px, Dark and Light); nothing overlaps or clips in any of the ten themes; the full test run passes.

### Phase 2: Four bugs the review found

The fifth bug (chips that vanish in Solarized and Synthwave) is a colour value and is fixed in phase 3.

**What changes:**

- **Net worth chart axis:** the amounts on the left are clipped ("$22,449.67" shows as "9.67") because the chart stretches to its box and the labels sit outside the visible area. Labels go inside the plot in short form ($22.4k) and stop stretching.
- **Card labels:** when the Forecast table falls back to cards (a window of about 1,250px or narrower), labels read as two headings joined ("Forecast dateStart date", "Actual dateEnds", "Forecast amtAmount"). `_twLabel` copies the header's text, which also holds the hidden headings the add row swaps in. It should take the visible heading only.
- **Reports bar chart:** drawn 180px wide in a 1,032px panel, because it sits in the pie chart's flex row. It fills the panel.
- **Reports category filter:** clipped after its third row in a 120px box. It shows in full.

**What you have to do:** look at the screenshots on the issue.

**Done when:** before and after screenshots of each fix are on the issue (the card labels at 1180px wide); the full test run passes.

### Phase 3: Readable themes, web and iPhone

Review suggestions 14 and 15.

**What changes:**

- **Contrast:** the 21 text colours under 4.5:1, in nine themes, move to the values `theme-contrast.py` prints (same hue, smallest change that passes). Where a darker accent already rescues the button text (Solarized, Mint), the button text stays.
- **Chips:** Solarized and Synthwave get a chip colour that differs from the panel.
- **Every theme** gets the hairline and shadow values phase 1 added, so the eight named themes carry the new shapes in their own palettes.
- **iPhone:** `WebTheme.swift` takes the same accent, good, bad and warn values, so `WebThemeTests` passes and the app's themes match the web's.
- **Theme picker:** each card previews its theme as a tiny screen in its own colours (a balance, a green and a red amount, a button). System shows half dark and half light. Light gets a caption.

**What you have to do:** look at the screenshots on the issue.

**Done when:** `theme-contrast.py` reports no pair under 4.5:1; screenshots of Forecast in all ten themes and of Settings → Appearance are on the issue; `swift test` passes and one themed screen is checked in the simulator (through `with-simulator.sh`); the full test run passes.

### Phase 4: Settings, Admin and Reports

Review suggestions 11, 12 and 13.

**What changes:**

- **Settings:** on wide windows the sections list down the left under a "Settings" title and stay in view while the page scrolls; content sits in a column of about 840px with help text wrapping near 72 characters; fields fill their row with the button beside the last one; row actions are quiet with Delete in red; the Delete my account panel is outlined in red. The phone keeps its scrolling tabs.
- **Admin:** the same layout with six sections: General (branding), Sign-in security (two-factor, API tokens), Bank and email, Users (user management, permissions), Backups, Audit log. Sections switch the way Settings' tabs do. On and off settings become switches, with their status line in muted text. The user row's buttons say Disable, Reset password and Delete in words, with Delete in red text.
- **Reports:** six totals three across and two down, forecast above actual; filters top-aligned with their checklists as pills; saved reports and templates as flat lists with the current one tinted.

**What you have to do:** look at the screenshots on the issue.

**Done when:** screenshots of every Settings tab, every Admin section and Reports are on the issue (1440 and 390px); every Admin control still works from its new section (numbered "How to test" steps on the issue); the full test run passes.

### Phase 5: Forecast and Bills tables

Review suggestions 05 and 06, apart from dates and row height (phase 6).

**What changes:**

- **Summary strips:** the tiles on Forecast, Bills & income, Net worth and Reports join into one strip. On Forecast the current balance leads at 38px and the other eight figures sit by column: opening over difference, forecast out/in over forecast end, actual out/in over actual end, highest over lowest. The order is set in markup so it holds in the All accounts view and with the bank-balance line.
- **Read view:** row lines only, a row highlight on hover, and no slash between forecast and actual pairs, on Forecast, Bills & income and the Unmatched panel. Spreadsheet mode keeps its full grid.
- **Row buttons:** the pencil becomes an SVG icon with no box until the row is hovered.
- **Pills:** one style on Forecast and Bills & income (filled, no outline).
- **Toolbar:** primary action filled, the rest soft; Prev, Next and the dropdowns at one height.
- **Width:** the Forecast table stays within about 15px of today's minimum width, so the card fallback starts at about the same window width.

**What you have to do:** look at the screenshots on the issue.

**Done when:** screenshots of read view, an open line, the add row, Spreadsheet mode and the card fallback are on the issue, for Forecast and Bills & income, at 1280, 1440 and 390px; the Forecast table does not fall back to cards at 1280px; the full test run passes.

**Depends on:** phase 1 (tokens and controls).

### Phase 6: Date format and row height settings

The two settings decided as calls 4 and 8.

**What changes:**

- **Schema and API:** two per-person columns on `users`, stored like `chart_position`: a date format (short or ISO, short by default) and a row height (roomy or compact, roomy by default). `/api/me` returns both and the settings endpoint takes both.
- **Dates:** one helper prints every date the web client shows in tables, cards, charts and the calendar: "Nov 12", with the year when it isn't the current one, or 2026-11-12 when the setting says ISO. Date inputs, CSV exports and the API are untouched.
- **Row height:** 36px rows and a taller toolbar by default; Compact restores 34px rows and today's toolbar.
- **Settings → Appearance:** a Date format choice and a Row height choice, each with a one-line footer saying what it does.

**What you have to do:** look at the screenshots on the issue.

**Done when:** API tests cover both fields (a happy path that reads them back from `/api/me`, and a refused value); screenshots of Forecast in each of the four combinations are on the issue; the full test run passes.

**Depends on:** phase 5 (the table styles the row height applies to).

### Phase 7: Dashboard, Calendar, sign-in, phone

Review suggestions 04, 07, 09 and 10.

**What changes:**

- **Dashboard cards:** highs and lows as plain label and figure pairs at 20px, with no inner boxes; one hairline instead of dashed dividers; a taller trend line; the legend shows all five rows and the donut's total fits its ring. Three cards fill the row instead of leaving an empty column.
- **Calendar:** the days join into one grid with hairlines; today is a filled date with a light wash; events keep their category tint without a border, with the amount in bold.
- **Sign-in:** the card centred in the window with the app's mark above the name, and taller fields and button.
- **Phone:** on Forecast the current balance spans the width with the other eight figures in a two-column strip; the account switcher scrolls sideways as a segmented control; the bottom bar marks the active page with colour and a short bar.
- **Net worth:** the "Per account" heading matches the page's other headings.

**What you have to do:** look at the screenshots on the issue.

**Done when:** screenshots of Dashboard, Calendar and sign-in at 1440px, and of Dashboard and Forecast at 390px, are on the issue in Dark and Light; the full test run passes.

**Depends on:** phase 1.

### Phase 8: Top bar and account menu

Review suggestion 03.

**What changes:**

- **The bar:** the app's mark beside its name; the active page marked by a tinted pill with no border; the bar stays in view while the page scrolls.
- **Account button:** the email address and Log out fold into one round button showing the person's initials. Its menu holds the email address, a link to Settings → Your account, and Log out. It opens on click, closes on Escape or a click outside, and works from the keyboard.
- **Search:** with the bar's space back, the search field shows in full at 1440px. `_fitGlobalSearch` measures the new bar.
- **Phone:** unchanged. The More sheet already holds the email address and Log out.

**What you have to do:** look at the screenshots on the issue, then cut the release.

**Done when:** screenshots of the bar at 1100, 1280, 1440 and 1680px and at 390px are on the issue, with the menu open and closed; the menu passes a keyboard pass (Tab, Enter, Escape); the full test run passes; released.

**Depends on:** phase 1.
