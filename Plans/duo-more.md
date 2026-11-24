# More for the Duo: one fold layout, and what it makes room for

Tracking issue: #309

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. One fold layout | #304 | Built in iOS 0.43.0, 2026-11-23; waits for a try on Matthew's Duo and a release |
| 2. Tap through | #305 | Built in iOS 0.47.0, 2026-11-23; waits for a try on Matthew's Duo and a release |
| 3. Match bank lines in the app | #306 | Built in iOS 0.51.0, 2026-11-23; waits for a try with a real bank and a release |
| 4. Keyboard and pointer | #307 | Planned 2026-11-23; not started |
| 5. Drag and drop | #308 | Planned 2026-11-23; not started |

Phase 3 built 2026-11-23 in iOS 0.51.0 (no server code change), by an orchestrated run (a Sonnet worker wrote it; this thread sent it back once so the two panes are reachable from Settings on the open Duo): Bank sync shows "N lines to match" under each connection and shared account (own accounts counted with `GET …/bank-unmatched`, shared ones from `unmatchedCount`), opening `UnmatchedListView`; `MatchChoices` (from `MatchSheet`) holds Pay this, Always match and Leave. When Settings is a sidebar the list opens as a full-screen cover with two panes through `FoldLayout`; closed, a pushed list and a sheet. The root's Bank sync row reads "N to match". The demo has two sample lines on Credit Card, read-only. Server: four new shape tests in `test_app_shapes.py` for the two GETs (fields the Kit reads; 404 for an unknown account or line, and for someone else's account). Verified: the server's shape tests (14 passed), `swift test` 352 passed (new `UnmatchedTests` and decoding samples); Duo simulator pictures closed and open, on the picture page linked from #306.

Phase 2 built 2026-11-23 in iOS 0.47.0 (no server change), by an orchestrated run (a Sonnet worker wrote it; this thread moved the chosen account's Coming up above its charts): `OpenInForecastButton` (`OpenInForecast.swift`) opens an account in Forecast from the Dashboard's cards, Net worth's rows, the Calendar's balances and Search. On a regular width the Dashboard chooses an account instead (`dashboard.account`, scoped to the connection): the other pane shows its next five unpaid lines (`comingUp` in the Kit), how many wait to confirm (opening Forecast's To confirm), Open in Forecast and its charts. The Calendar's lines are rows that open the line editor (the other pane when wide, the sheet when not), swipe like Forecast's and offer Undo; `APIClient.forecastLine(for:)` finds the event's line in its account's Forecast month by transaction id, or by bill and planned date. Verified: `swift test`, 312 passed (11 new in `TapThroughTests`); Duo simulator pictures closed and open, on the picture page linked from #305. Not checked: the taps themselves.

Phase 1 built 2026-11-23 in iOS 0.43.0 (0d908a1; no server change), by an orchestrated run (an Opus worker wrote it; this thread measured the fold first, checked the result and reworded three hints): `FoldLayout` (and `FoldReader`, which Compare uses) places a page's two panes from the fold's band through `FoldPanes.layout` in the Kit: no band, today's two halves; a band running top to bottom, the panes either side of it; a band running across, stacked, with the Dashboard's charts on top and every other page's left pane on top. A band that would leave a pane under 120 points is ignored (a page inside another's pane). The move between arrangements is a `.smooth` animation, or a short fade with Reduce Motion. Net worth, Budgets, Reports and Search take the small title when open; pull to refresh works from either pane and on Reports and Search; the Dashboard's Refresh button is gone; `ForecastView.tabletopFold` is gone. Verified: `swift test`, 268 passed (5 new in `FoldArithmeticTests`, with the measured numbers); Duo simulator pictures flat on its side and upright (Forecast and Bills & income identical to before, pixel for pixel; the Dashboard differing only by its Refresh button), half open like a book and half open like a laptop, on the picture page linked from #304. Not checked: the animation itself and scrolling the lower pane clear of the tab bar, which need a hand on a Duo.

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

None. A question that comes up while building goes here, with the phase it blocks.

## The plan

**Goal:** Every page treats the Duo's fold the same way, flat and half open, and the big screen does more: tapping through from the Dashboard and the Calendar, matching bank lines, a keyboard, and drag and drop.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/ios-review.md)):

- **Flat open, pages keep today's layout. Half open, each page stacks at the hinge,** and the cards move from one layout to the other as the Duo folds (R5). With Reduce Motion on, the two layouts cross-fade.
- **The first screen and sign-in stay as they are** when open (R3).
- **Settings is a sidebar, not two halves** (R1): `Plans/ios-settings.md`.
- **An account opens in Forecast everywhere** it's shown (R7).
- **Flat, the two panes stay exactly where they are; R2's move applies half open only.** Checked on the simulator on 2026-11-23, as this plan's open question asked: lying flat (on its side or upright) the Duo reports no fold region at all, so iOS asks for nothing to be kept clear; half open it reports a 40-point band centred on the screen's centre line (`reservedRegions(kind: .division)`: x 455.5 to 495.5 of 951 like a book, y 455.5 to 495.5 of 951 like a laptop). Today, half open like a book, the right-hand pane starts at 461.5 and so sits on that band.

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

- **A shared container** every two-pane page uses: one column when narrow; flat, today's two panes, untouched; half open like a book, the two panes either side of the fold's band (R2); half open like a laptop, stacked above and below it (R5).
- **The change is animated:** as the Duo folds, the cards move from the flat layout to the stacked one. With Reduce Motion on, the two cross-fade.
- **What goes where, half open:** Dashboard, the chosen account's chart above and the accounts below; Forecast, the chart and lines above and the editor or summary below (as today); Bills & income, the list above and the editor or totals below; Calendar, the month above and the day below; Net worth, the total and chart above and the accounts below.
- **One title size when open** (R4): Net worth, Budgets, Reports and Search take the small title too.
- **Refresh from either half,** and on Reports and Search; the Dashboard's Refresh button goes (R6).

**What you have to do:** Fold and unfold the Duo on each page, both ways up.

**Done when:**

- A Kit test for the fold's arithmetic: from the page's size and the fold's band (none, upright or across) to each pane's frame.
- Half open like a book, no card or text sits on the fold's band; flat, the pictures match today's.
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
