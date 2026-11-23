# The web app's design refresh: the choices behind it

Decisions for `Plans/web-refresh.md`: a more modern look for the web client, from a design review of web 1.107.0 done on 2026-11-23. The review ran the app in a demo with sample data, at desktop and phone width in the Dark and Light themes, and showed each suggestion as a before and after picture ([the review page](https://claude.ai/artifact/SjuH49ZXMrDCG4xPE6ytaf), private to Matthew). It made fifteen suggestions (01 to 15), showed a bolder direction with a sidebar (B), and found five bugs.

## 2026-11-23: scope, order and how phases are checked

**Decided:** 2026-11-23, by Matthew, while planning. **Status:** accepted.

- **The whole review is built, and released once at the end.** The other options were a first release with only the look and the bugs, or one that stopped after Settings, Admin and Reports.
- **Nothing is held back for later.** Navigation, the theme colour fixes, dates and column lines, and Admin's sections were each offered as something that could wait.
- **Each phase is checked by screenshots on its issue:** before and after pictures of the pages it touched (desktop and phone, Dark and Light) as a link on the phase issue, plus the full API test run. Matthew looks before the release. The other options were adding a contrast test to the suite, or tests alone with no look between phases.

## 2026-11-23: eight design calls

**Decided:** 2026-11-23, by Matthew, in two rounds of questions before the plan was written. **Status:** accepted.

1. **Navigation is a refined top bar** (suggestion 03): the app's mark, a tinted active page, an account button, and the search field always in view. The sidebar (B) is not built: at 1440px it has to collapse to an icon rail on Forecast and Bills & income so their tables keep their columns, and Settings and Admin would show two columns of navigation. "Top bar now, sidebar later" was the third option.
2. **Log out lives in the account menu,** with the email address and a link to Settings → Your account. Keeping it always visible beside the account button was the other option.
3. **Column lines are dropped in read view only.** Forecast and Bills & income show row lines when reading; Spreadsheet mode keeps its full grid; the slash between forecast and actual pairs goes. This changes #81 and #220, which gave both tables (and the Unmatched panel's) a line between every column. Dropping the lines everywhere, or keeping them, were the other options. No setting: the grid is still one click away in Spreadsheet mode.
4. **Dates print as "Nov 12", with a setting.** The year shows when it isn't the current one. Settings → Appearance gets a Date format choice that switches back to 2026-11-12, as the rule on changes some people want reversed asks. Date inputs, exports and the API are untouched. "No setting" and "keep ISO dates" were the other options.
5. **All 21 failing theme colours are fixed, on the web and the iPhone.** Each moves just far enough to reach 4.5:1 at the same hue, so Dracula, Nord, Solarized and Monokai drift a little from their official palettes. The iPhone app's copy of the themes (`WebTheme.swift`) changes with them. Fixing only labels and button text, or only the Dark theme and the two vanishing chip colours, were the other options.
6. **Admin splits into six sections:** General (branding), Sign-in security (two-factor, API tokens), Bank and email, Users (user management, permissions), Backups, Audit log. API tokens under Users, or four larger sections, were the other options.
7. **The Forecast summary's figures sit by column:** current balance leads, then opening over difference, forecast out/in over forecast end, actual out/in over actual end, highest over lowest. Keeping today's left-to-right order was the other option.
8. **Rows are roomier, with a setting.** Table rows are 36px with a taller toolbar by default; a Compact choice in Settings → Appearance restores 34px and today's toolbar. Keeping today's density (seven rows instead of five on a 900px-tall window), or roomier with no setting, were the other options.

**Also settled in the review:** the system font stays (no hosted typeface); the full-width layout and its 40px gutter stay on the data pages; every table column stays; the Forecast table keeps its present width, so it falls back to cards at about the same window width as today.

**What it changes:** `Plans/web-refresh.md` and its phase issues. Call 3 changes the look #81 and #220 chose; the phone bottom bar and the tabs inside Settings (2026-11-14, [usability](usability.md)) stay, with the Settings tabs drawn as a list down the left on wide windows.
