# More for the Duo: one fold layout, and what it makes room for

Tracking issue: #309

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. One fold layout | #304 | Planned 2026-11-23; not started |
| 2. Tap through | #305 | Planned 2026-11-23; not started |
| 3. Match bank lines in the app | #306 | Planned 2026-11-23; not started |
| 4. Keyboard and pointer | #307 | Planned 2026-11-23; not started |
| 5. Drag and drop | #308 | Planned 2026-11-23; not started |

Planned 2026-11-23 from a design review of iOS 0.34.0, asked for as "can you perform a design review of the ios app, looking for ux inconsistancies and suggest more features for the duo. please also take a look at overhauling settings and I would also like a plan for the ability to connect to multiple servers as well as running local and even accessing the demo (from the settings)". The review ran the app in the demo on the Duo simulator in every pose and at a large text size, made 27 findings (R1 to R27) and twelve ideas (F1 to F12), and drew today beside the proposal for each ([the review page](https://claude.ai/artifact/YanSV7o5FqX9WC6SdzZkyj), private to Matthew). The choices made in four rounds of questions are on the [decision page](../docs/dev/decisions/ios-review.md).

Sessions: may span — five phases, each tried on Matthew's Duo before the next, as phase 4 of the first iPhone plan was.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. One fold layout | Opus | Sonnet: the pictures in every pose | One container replaces eight hand-built layouts, on a system feature that has to be measured in the simulator first. |
| 2. Tap through | Sonnet | Sonnet: the tests and the pictures | It follows the pattern Forecast and Search already use for opening a line. |
| 3. Match bank lines in the app | Sonnet | Sonnet: record the samples and write the decoding and demo tests | The list, the sheet and the calls exist for the household on this iPhone; this gives them to servers and two panes. |
| 4. Keyboard and pointer | Sonnet | Sonnet: the pictures | System modifiers on views that already exist. |
| 5. Drag and drop | Opus | Sonnet: the pictures | System drag and drop across apps and windows, tried in the simulator before it is designed. |

## Open questions

1. **Where is the fold when the Duo lies flat?** Blocks phase 1. The review measured the gap between the two panes 42 points left of the screen's centre line (a card ends at 1218 px, the next starts at 1384 px, the centre is 1426 px), and took the hinge to be that line, which is where iOS reports it half open. Phase 1 starts by checking this on the simulator and on Matthew's Duo. Working assumption: the gap moves onto the fold and nothing else about the flat layout changes. If the Duo already keeps content clear of a flat fold by itself, R2 is dropped.

## The plan

**Goal:** Every page treats the Duo's fold the same way, flat and half open, and the big screen does more: tapping through from the Dashboard and the Calendar, matching bank lines, a keyboard, and drag and drop.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/ios-review.md)):

- **Flat open, pages keep today's layout. Half open, each page stacks at the hinge,** and the cards move from one layout to the other as the Duo folds (R5). With Reduce Motion on, the two layouts cross-fade.
- **The first screen and sign-in stay as they are** when open (R3).
- **Settings is a sidebar, not two halves** (R1): `Plans/ios-settings.md`.
- **An account opens in Forecast everywhere** it's shown (R7).

**Out of scope:**

- iPad and Mac.
- Four notes from the review that aren't proposed yet: a window for one account or bill, two connections side by side, a denser To confirm for the narrow half beside a bank's app, and the front screen while half open.
- Compare remembering its sides and gaining "against plan": drawn in the review as a small addition, not asked for.

**What's there today:**

- Each two-pane page builds its own row with 28-point paddings either side of the middle: `DashboardView.twoPanes`, `ForecastView.twoPanes`, and the same in `BillsView`, `CalendarView`, `MoreView` (Net worth, Budgets, Reports), `SearchView` and `CompareView` (`foldGap` 56). The middle is the middle of the space left of the side tab bar, not the screen's.
- Only Forecast reads the fold's region (`ForecastView.tabletopFold`, iOS 27.1's `reservedRegions(kind: .division)`); half open, the other pages run across the hinge, and the bottom tab bar covers content on all of them.
- Four pages take the small title when open (#260); Net worth, Budgets, Reports and Search keep the large one.
- Pull to refresh reaches the left pane only on three pages; Reports and Search have none; the Dashboard has a Refresh button.
- The Dashboard's account cards and the Calendar's lines aren't buttons (`DashboardView.swift:235`, `CalendarView.swift:342`).
- The Kit has the unmatched-lines calls (`BankUnmatched.swift`); the list (`UnmatchedListView`) exists only for the household on this iPhone. With a server the app says "in the web app".
- There is no context menu, keyboard shortcut, drag or drop anywhere in the app.

**How every phase is checked:** `swift test` passes, with a Kit test for the fold's arithmetic. Duo simulator pictures in every pose (closed, open on its side, open upright, half open both ways) are linked from the phase issue. Matthew tries each phase on the Duo and says what stays, as with phase 4 of `Plans/ios-app.md`.

**Versions:** each phase bumps the iOS version and adds its changelog entries under `[Unreleased]`. No server, web or schema change.

### Phase 1: One fold layout

From the review: R2, R4, R5, R6. R3 is kept as it is.

**What changes:**

- **First, the open question:** where the fold is when the Duo lies flat, checked on the simulator and on Matthew's Duo.
- **A shared container** every two-pane page uses: one column when narrow; two panes with the gap on the fold when flat (R2); stacked at the hinge when half open, clear of the tab bar (R5).
- **The change is animated:** as the Duo folds, the cards move from the flat layout to the stacked one. With Reduce Motion on, the two cross-fade.
- **What goes where, half open:** Dashboard, the chosen account's chart above and the accounts below; Forecast, the chart and lines above and the editor or summary below (as today); Bills & income, the list above and the editor or totals below; Calendar, the month above and the day below; Net worth, the total and chart above and the accounts below.
- **One title size when open** (R4): Net worth, Budgets, Reports and Search take the small title too.
- **Refresh from either half,** and on Reports and Search; the Dashboard's Refresh button goes (R6).

**What you have to do:** Fold and unfold the Duo on each page, both ways up.

**Done when:**

- A Kit test for the fold's arithmetic: from the window's width, the tab bar's side and the fold's region to each pane's frame.
- Measured on a picture of the flat Duo, the middle of the gap is within a point of the fold.
- Pictures of Dashboard, Forecast, Bills & income, Calendar and Net worth in every pose, and frames of the fold animation, are linked from the issue.
- Half open, nothing sits on the hinge or under the tab bar.

**Depends on:** Nothing.

### Phase 2: Tap through

From the review: R7, R8.

**What changes:**

- **Dashboard, open:** tap an account and the right half shows its chart, what's coming, and a way into Forecast. With none chosen, today's column of charts stays.
- **An account opens in Forecast** when tapped closed, and from Net worth's rows and the Calendar's Balances today (R7).
- **The Calendar's lines are buttons** (R8): the editor takes the right half when open, and is Forecast's sheet when closed. They swipe to Paid as in Forecast.

**What you have to do:** On your Duo, tap an account on the Dashboard, then a line on the Calendar, open and closed.

**Done when:**

- Kit tests for what's worked out off screen (an account's coming lines).
- Pictures closed and open, and numbered "How to test" steps, are on the issue.

**Depends on:** Phase 1.

### Phase 3: Match bank lines in the app

From the review: The review's part 4; with #321.

**What changes:**

- **Unmatched bank lines, with a server too:** the lines on the left and what each could pay on the right when open; a list and a sheet when closed.
- **Match, Pay this, Always match** (the rule the web app's pop-in offers) **and Leave.**
- **A count on the Bank sync row** in Settings. (#321 puts it on the Dashboard.)
- A read-only sign-in sees the list and can't change it. The demo has sample unmatched lines.

**What you have to do:** With a bank connected to your server, match one line and leave another from your phone, then look at them in the web app.

**Done when:**

- Samples recorded from a demo server for the unmatched list and its candidates, with Kit decoding tests; `DemoTests` covers the page.
- Pictures closed and open, and numbered "How to test" steps, are on the issue.

**Depends on:** Phase 1.

### Phase 4: Keyboard and pointer

From the review: R13.

**What changes:**

- **Shortcuts:** ⌘N add a transaction, ⌘F search, ⌘1 to ⌘5 the pages in the tab bar, ⌘R refresh, ← and → previous and next month, ⌘T this month, ⌘⏎ save the open editor.
- **A long-press (or right-click) menu on every line and bill,** wherever it's listed: Forecast, To confirm, Search, Calendar, Bills & income. The same actions as the swipes, which stay (R13).
- A hover highlight on rows, for a pointer.

**What you have to do:** With a keyboard on your Duo, hold ⌘ to see the list and try each. Long-press a line in each list.

**Done when:**

- A picture of the menu on each list is linked from the issue.
- Numbered "How to test" steps for the shortcuts are on the issue.

**Depends on:** Phase 2 (the Calendar's lines must be buttons first).

### Phase 5: Drag and drop

From the review: Noted for later in `Plans/ios-app.md` phase 4.

**What changes:**

- **Drop a bank's CSV on Forecast** (or the Dashboard) and the import sheet opens on that file and account.
- **With two WalletWeather windows, drag a line onto a Calendar day** to move its planned date. Only lines whose date can be changed (#316); a date that comes from a bill isn't dragged.

**What you have to do:** On your Duo, put Files beside WalletWeather and drag a CSV across. Then two WalletWeather windows, and drag a line to another day.

**Done when:**

- Pictures of the drop highlight and the import sheet it opens are linked from the issue.
- Numbered "How to test" steps are on the issue; a part that doesn't work well on the Duo is dropped and recorded here with why.

**Depends on:** Phase 1, and #316 for moving a date.
