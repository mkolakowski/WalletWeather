# Settings on the iPhone: sections, a sidebar and custom themes

Tracking issue: #298

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Sections and pages | #294 | Planned 2026-11-23; not started |
| 2. A sidebar when the Duo is open | #295 | Planned 2026-11-23; not started |
| 3. Appearance previews, Dates & display | #296 | Planned 2026-11-23; not started |
| 4. Custom themes | #297 | Planned 2026-11-23; not started |

Planned 2026-11-23 from a design review of iOS 0.34.0, asked for as "can you perform a design review of the ios app, looking for ux inconsistancies and suggest more features for the duo. please also take a look at overhauling settings and I would also like a plan for the ability to connect to multiple servers as well as running local and even accessing the demo (from the settings)". The review ran the app in the demo on the Duo simulator in every pose and at a large text size, made 27 findings (R1 to R27) and twelve ideas (F1 to F12), and drew today beside the proposal for each ([the review page](https://claude.ai/artifact/YanSV7o5FqX9WC6SdzZkyj), private to Matthew). The choices made in four rounds of questions are on the [decision page](../docs/dev/decisions/ios-review.md).

Sessions: may span — four phases, each ending with a look from Matthew at its pictures and a try on the phone.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Sections and pages | Opus | Sonnet: `swift test` and the simulator pictures | Settings' whole structure changes, across the views that hang off it, and nothing may be lost on the way. |
| 2. A sidebar when the Duo is open | Opus | Sonnet: the simulator pictures in every pose | A layout the Duo decides, tried in the simulator against the Duo's own Settings. |
| 3. Appearance previews, Dates & display | Sonnet | Haiku: find every place the app prints a date. Sonnet: the tests and the pictures | One helper used everywhere and a page drawn from colours the app already has. |
| 4. Custom themes | Opus | Sonnet: the tests and the pictures | New storage, a new entitlement and a line in the privacy policy; the look system gains a kind of look it didn't have. |

## Open questions

1. **How much of a custom theme can change?** Blocks phase 4. Working assumption: six colours (page, card, text, accent, money in, money out), with the warning and outline colours worked out from them. Accent only was the other option; it wasn't asked directly.

## The plan

**Goal:** Settings on the iPhone becomes a short list of sections, each opening its own page, laid out like the Duo's own Settings when the Duo is open, with a previewed Appearance page, a Dates & display page and themes people make themselves. Every setting that exists today keeps a place, and no stored setting is renamed.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/ios-review.md)):

- **Sections and pages** (shape A of three drawn): a connection card, More pages, Your household, This iPhone, About; each row opens its own page.
- **Open, Settings is a sidebar and a page, like the Duo's own Settings,** not two halves at the fold (R1). Its page crosses the fold, as the system's does.
- **"This iPhone" everywhere,** in place of "this phone" (R22).
- **Pages follow the same account, with a switch** (R9, built by #317); the switch lives in Dates & display.
- **Custom themes are kept in iCloud,** so they follow you to your other iPhones (R19.5).
- **A faint pair of colours gets a warning and still saves** (R19.5).

**Out of scope:**

- Changing what any setting does. This plan moves and redraws; behaviour changes have their own issues.
- The web app's themes, and putting custom themes on the server so the web gets them.
- The first screen and sign-in, which stay one centred column when open (R3, decided).
- Bank sync's own behaviour: its cards move to their own page as they are.
- Connections (several servers, the demo from Settings): `Plans/connections.md`, which uses this plan's connection card.

**What's there today:**

- `apps/ios/WalletWeather/Views/MoreView.swift`: `SettingsView` is one scrolling column of cards (Other pages, Tags, the Bank sync card, This phone, then Your server, or On this iPhone, Backup and Move). It has no layout for a regular width, so on the open Duo the cards run across the fold.
- `apps/ios/WalletWeather/AppSettings.swift`: the look, the tab bar and the lock, in the app's preferences under `appearance`, `appearance.web`, `tabs`, `lock.enabled`, `lock.offered`, `start.done`, `start.dismissed`. `AppModel` keeps `keep.choice`.
- `apps/ios/WalletWeather/Theme.swift`: `Look` has 14 values (Match the phone, Match the web app, Light, Dark, AMOLED black, Sepia and the web's eight); `Palette` reads the colours. `WebThemeTests` holds the web themes to the stylesheet and to 4.5:1.
- Appearance is a pop-up menu of names in Settings (`MoreView.swift:72`) and a second, different list in Getting started (`GettingStartedViews.swift:246`).
- `LocalDay.short` always prints "Nov 12" (`LocalDay.swift:59`). `Me` doesn't read `date_format`, which `/api/me` has sent since server 1.98.0.
- One note under "This phone" explains the lock, the app switcher and Keep on this phone together (`MoreView.swift:106`).

**How every phase is checked:** `swift test` passes, with Kit tests for anything that has logic. Duo simulator pictures of every page the phase touches (closed and open, with a server, on this iPhone and in the demo, in two looks) are linked from the phase issue. A phase that changes an interaction also lists numbered "How to test" steps for Matthew's phone.

**Versions:** each phase bumps the iOS version (`MARKETING_VERSION` and `AppInfo.version`) and adds its changelog entries under `[Unreleased]`. No server, web or schema change.

### Phase 1: Sections and pages

From the review: R20, R21, R22, and the shape chosen in the review.

**What changes:**

- **The root list:** a connection card (which household you're in, who's signed in, its state), More pages as tiles, Your household (Tags; Bank sync with its state on the row; Import a CSV; on this iPhone also Accounts, iCloud & backup, Move to a server), This iPhone (Appearance, Tab bar, Privacy & lock), About (Important notice, Help & Getting started, versions, the privacy policy).
- **A page per section.** Bank sync's cards move to their own page as they are. Privacy & lock holds the lock switch and the app-switcher note. The connection card's page holds the address, who's signed in, Cloudflare, Keep on this iPhone, Open the web app and Sign out, or for the household on this iPhone, Delete everything.
- **One row grammar** (R20): a chevron goes somewhere; blue does something now, with ↗ when it leaves the app; red comes last.
- **Each note under its own setting** (R21), instead of one block under a card.
- **"This iPhone"** in every screen and alert that says "this phone" (R22).
- **Help & Getting started** brings the Getting started card back.
- Nothing is removed. Saved keys (`appearance`, `tabs`, `lock.enabled`, `keep.choice` and the rest) and `RootView.Place.more` keep their values.

**What you have to do:** Look at the pictures. On your phone, find each setting from the review page's table of where everything goes.

**Done when:**

- Every row of the review's "Where everything goes" table can be reached, with a server, on this iPhone and in the demo; a Kit test lists the rows each of the three shows, so none is dropped.
- Pictures of the root list and each page, closed, in two looks, are linked from the issue.
- `swift test` passes.

**Depends on:** Nothing.

### Phase 2: A sidebar when the Duo is open

From the review: R1.

**What changes:**

- **Open, the root list is a sidebar** about a third of the width, with the chosen section's page beside it, as in the Duo's own Settings (pictured on the review page). The first section is chosen when none is.
- **The page crosses the fold,** as the system's does. This is the one page that doesn't use the fold layout of `Plans/duo-more.md`.
- **Closed, nothing changes** from phase 1: the list is the screen and each row pushes its page.
- **The place is kept per window:** closing the Duo on Appearance shows Appearance pushed; opening it shows the sidebar with Appearance chosen.
- The small title when open, as on the other pages.

**What you have to do:** Open Settings on your Duo, both ways up, and close it while on a section.

**Done when:**

- Pictures closed, open on its side, open upright and half open, in two looks, are linked from the issue.
- Closing and opening the Duo keeps the section.
- `swift test` passes.

**Depends on:** Phase 1.

### Phase 3: Appearance previews, Dates & display

From the review: R18, R19.

**What changes:**

- **Appearance is a page of previews** (R19): each look as a tiny screen in its own colours, as the web app's Settings → Appearance has had since 1.98.0; Match the phone is split light and dark; the chosen one is ringed. It replaces the pop-up menu in Settings and the list in Getting started's "Choose a look": one page, two ways in.
- **Dates & display** (R18): Date format is Follow the web app (with a server on 1.98.0 or later it reads `date_format` from `/api/me`; an older server means Nov 12), Nov 12, or 2026-11-12. On this iPhone alone the choice is the phone's own. One helper prints every date. Date pickers and typed dates don't change.
- **"Pages follow the same account"** has its home here (#317 builds the behaviour).

**What you have to do:** Look at the pictures. Change the date format in the web app and see the phone follow.

**Done when:**

- Kit tests: the date helper in both formats, with the year outside the current one; `Me` reads `date_format` and manages without it.
- A search of the app finds no date printed outside the helper.
- Pictures of Appearance (closed and open) and of Forecast in each date format are linked from the issue.

**Depends on:** Phase 1. Phase 2 for the open pictures.

### Phase 4: Custom themes

From the review: R19.5, asked for on 2026-11-23.

**What changes:**

- **My themes** sit under the built-in looks on the Appearance page. **New theme** starts as a copy of any look.
- **The editor:** a name, six colours (page, card, text, accent, money in, money out; see the open question), and a live preview.
- **A readability line** checks text on card, money on card and accent on page against 4.5:1. A faint pair gets a warning and still saves (decided).
- **Kept in iCloud** (decided): names and colours only, in the phone's iCloud key-value store, so they reach your other iPhones. That is a new entitlement in `apps/ios/project.yml`. With iCloud off they stay on this iPhone. `apps/ios/README.md` ("What's kept on the phone") and the privacy policy say so in the same change.
- A custom theme is one more `Look`. The saved `appearance` value of a built-in look doesn't change, and a look that's no longer there falls back to Match the phone.
- Match the web app is untouched: the web's themes stay a fixed list.

**What you have to do:** Make a theme on your phone. If a second iPhone is signed in to the same Apple ID, see it arrive there.

**Done when:**

- Kit tests: the contrast sums against known pairs; a theme goes into storage and comes back the same; an unknown saved look falls back.
- Pictures of the list, the editor, and Dashboard and Forecast in one light and one dark custom theme are linked from the issue.
- The README and the privacy policy mention custom themes in iCloud.

**Depends on:** Phase 3.
