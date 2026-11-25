# iOS UI review: a suite that looks for bugs, inconsistencies and a dated look

Tracking issue: #348

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. The source check | #344 | Built 2026-11-24, in `swift test`; closed |
| 2. The simulator walk | #345 | Built 2026-11-24; `ui-walk.sh quick` ran clean on the closed Duo; closed |
| 3. The first review | #346 | Open |
| 4. The skill, with what was learned | #347 | Open |

Phase 2 built 2026-11-24 (8596674; no version, nothing the app does changed): a UI-test target with its own scheme (`apps/ios/UITests`), 55 screens in `Screens.swift`, the checks in `Checks.swift`, seven flows that use the app (`testUse`), and `Scripts/ui-walk.sh`, `ui-report.py` and `ui-sheet.swift`. Verified: `ui-walk.sh quick` on the closed Duo (54 screens, 109 pictures, 12 minutes); a Debug-only page of ten planted faults opens every run and the test fails if a check misses one (it did on the first run: one check could never fire, and was dropped); `swift test`, 536 passed. While being built it found that cancelling the line editor stops the app, and that Compare breaks up on the Duo's front screen. A standard run is 70 to 100 minutes, not the 30 to 40 said when scoping: every screen needs a fresh launch.

Phase 1 built 2026-11-24 (16e1c25, widened in 2254ae7; no version): `UISourceTests` in the Kit's tests, twelve rules over the app's own Swift, each with its reason, its fix and lines it must and mustn't catch. The baseline (`WalletWeatherKit/Tests/UISourceBaseline.txt`) holds 51 slips and only shrinks. Verified: `swift test`, 536 passed; a slip planted in `UndoBar.swift` failed the test three times over, once per rule, and was taken out again.

Planned 2026-11-24, asked for as "can you plan and implement a user interface review/testing suite thats goal is to look for bugs and inconstancies in the ios app? please include user interface design in the review, I want to keep this app looking modern. use what you learn to create a skill to repeat the task with learnings". Scoped the same evening in one round of questions: build all of it; a standard run covers the iPhone Duo closed and open on its side plus an iPhone 17, in light and dark, at Large and Accessibility Large; findings go on a review page with pictures and Matthew picks what's filed.

Sessions: may span — four phases, the third with a long simulator run and a round of picking.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. The source check | Opus | None | Choosing rules that catch real slips without crying wolf is the design work. |
| 2. The simulator walk | Opus | None | A new test target, and checks tuned against what the simulator really reports. |
| 3. The first review | Opus | Sonnet: a first pass over the pictures, if the run is large | Judging the look is the main session's; every finding is checked against the code before it's written up. |
| 4. The skill, with what was learned | Sonnet | None | Writing down a routine that has just been run. |

## Open questions

None. A question that comes up while building goes here, with the phase it blocks.

## The plan

**Goal:** One command and one skill that go over the whole iPhone app and say what's broken, what's inconsistent and what looks dated, the same way every time, and that get better at it with each run.

**Decided 2026-11-24** (by Matthew, in the scoping round):

- **All four phases are built,** not the tools alone.
- **A standard run covers the iPhone Duo closed and open on its side, and an iPhone 17** (the plain iPhone TestFlight testers hold, with the bar along the bottom), in light and dark, at Large and Accessibility Large. `quick` (one device, one look) and `full` (every Duo pose, every look, three text sizes) are arguments.
- **Findings go on a review page, and Matthew picks what's filed.** Every finding has a picture of today beside the proposal. Nothing in the app changes until then.
- **A new slip in the source check fails `swift test`.** Today's slips go on a baseline, which only shrinks.

**Out of scope:**

- Fixing what the review finds. Each fix is its own issue or plan, filed after Matthew picks.
- The web app (`Plans/web-refresh.md` had its own review) and the widgets on a real Home Screen.
- Pixel-for-pixel snapshot tests. "Locked layouts" covers a layout Matthew calls final; this suite looks for faults, it doesn't freeze the look.
- Anything a simulator can't show: Face ID, the camera, a real server's sign-in, a real Duo's hinge.
- Running in CI. The simulator walk needs this Mac; the source check runs wherever `swift test` does.

**What's there today:**

- `swift test` (532 tests) covers the Kit: nothing with a screen. The project has no UI-test target; #341 was verified with a throwaway one.
- The app has about fifty Debug launch settings (`WW_DEBUG_*`, `apps/ios/README.md`) that open it on a page, a sheet or a state with no taps, and "Try the demo" needs no server.
- The 23 Nov design review (`docs/dev/decisions/ios-review.md`) was done by hand: screenshots taken one launch at a time, findings from reading code. Its conventions (sentence-case labels, one row style, `ProblemBanner` for a failed save, sizes that follow the text size) are decided but nothing checks them.
- Simulators are shared with mkplus's sessions (`with-simulator.sh`), and the Duo's poses are set from outside the app (`duo-set.sh`).

**The three layers:**

| Layer | What it is | Needs | Tier |
| --- | --- | --- | --- |
| Source check | A test that reads the app's Swift and matches rules against it | Nothing | fast, in `swift test` |
| Simulator walk | A UI-test target that drives the app in the demo and checks each screen | The simulator lock | live |
| Design review | Claude reading the pictures and the walk's report against a checklist | The walk's output | by hand, through the skill |

**How every phase is checked:** `swift test` passes; what each phase adds is run for real and its output linked from the phase issue.

**Versions:** none of this changes what the app does, so no version is bumped and nothing goes in the changelog, unless a phase has to change the app itself (an identifier a test needs is not a change people see).

### Phase 1: The source check

**What changes:**

- `UISourceTests` in the Kit's tests reads every Swift file under `apps/ios/WalletWeather`, `Widgets` and `Notifications` and matches rules against them. Each rule has an id, a one-line reason and the decision it comes from. To start with:
  - a fixed font size that ignores the phone's text size (`.font(.system(size:` with no `relativeTo`, outside a `@ScaledMetric`);
  - a colour that bypasses the theme (`Color(red:`, `Color(.sRGB`, `.red`, `.blue` and the like as a style, outside `Theme.swift`);
  - styling Apple has replaced (`.foregroundColor(`, `.cornerRadius(`, `NavigationView`, `.navigationBarItems`, `.accentColor(`);
  - a label in capitals or Title Case where the app writes sentence case (`.textCase(.uppercase)`, a string literal such as "Add Transaction");
  - three dots typed as "..." where the app writes "…";
  - a button that is only a symbol, with no accessibility label;
  - an `.alert(` reporting a failed save in an editor, where `ProblemBanner` is the decided way;
  - an animation that doesn't look at Reduce Motion in a file that moves things around.
- A baseline file beside the test lists today's slips (rule, file, the line's text). A slip not on it fails the test and says how to fix it or, when it's right as written, how to mark it (`// ui-check: allow <rule> — why`). A baseline entry that no longer matches fails too, so the baseline only shrinks.
- With `WW_UI_SOURCE_REPORT=<file>` the test writes everything it matched, baseline included, as JSON for the review.

**What you have to do:** Nothing.

**Done when:**

- `swift test` passes with the new test in it, and a slip added on purpose fails it with a message that says what to do.
- The baseline is in the repo, and the count of slips per rule is on the issue.

**Depends on:** Nothing.

### Phase 2: The simulator walk

**What changes:**

- A UI-test target, `WalletWeatherUITests`, in `project.yml`. It launches the app in the demo (and the sample household on this iPhone, for what the demo can't show) and works through a table of screens: each one a name, the launch settings that open it, and the taps that follow. Every tab, every Settings page, the editors and sheets, Search, the first-run screens.
- On each screen it:
  - waits for it to settle, and notes a spinner that never goes or a screen that's all but empty;
  - saves a picture, then scrolls to the end saving a picture of each screenful;
  - runs Apple's accessibility audit (contrast, cut-off text, text that doesn't follow the text size, small hit regions, missing descriptions);
  - runs its own checks on what's on screen: tap targets under 44 points, things hanging off the edge, text over text, labels that leak code (`Optional(`, `nil`, `NaN`, a format placeholder), a button with no name, labels in capitals or Title Case, amounts and dates written two ways on one screen;
  - writes down what it measured (the left margin, the bar's height and where the tab bar is, every visible string), so the report can compare screens with each other.
- It also uses the app: opens a line and cancels, adds a transaction in the demo, switches tabs, turns the phone on its side, and notes a crash, a hang or an alert nobody asked for.
- `apps/ios/Scripts/ui-walk.sh` runs it under the simulator lock: build once, then once per configuration (device or pose, look, text size), with `quick`, `standard` (the default) and `full`. The pictures and each configuration's findings go to `apps/ios/build/ui-review/<run>/`, which isn't tracked.
- `apps/ios/Scripts/ui-report.py` merges a run: findings grouped by check and by screen, the same finding across configurations folded into one, and the cross-screen comparisons (margins that differ, a word used two ways such as "Delete" and "Remove", amounts and dates written differently between pages).
- `apps/ios/README.md` gains "Reviewing the UI".

**What you have to do:** Nothing.

**Done when:**

- `ui-walk.sh quick` finishes on the closed Duo with a picture of every screen in the table and a findings file.
- The report script turns that run into one summary.
- A fault planted on purpose (a label reading `Optional(…)`, a 20-point button) is found.

**Depends on:** Nothing; built after phase 1 so the review has both.

### Phase 3: The first review

**What changes:**

- A standard run on the current build.
- Every finding of the walk and the source check is looked at: real, or the check being wrong. A wrong check is fixed or its exception written down, and that goes in the learnings.
- A design review from the pictures against a checklist kept in the repo (`design-checklist.md`, beside the skill): Apple's iOS 26 look (glass bars and controls, concentric corners, the system's own lists, sheets and menus, SF Symbols, type styles, spacing) and this app's decided conventions.
- A review page (an artifact, private to Matthew): bugs, inconsistencies and design suggestions, each with a picture of today beside the proposal, each checked against the code.
- A round of picking, then issues (or plans, where one needs phases) for what Matthew chooses, and a decision page for the choices.

**What you have to do:** Read the review page and pick.

**Done when:**

- The review page is linked from the issue.
- What Matthew picked is filed, and what he turned down is recorded so the next run doesn't raise it again.

**Depends on:** Phases 1 and 2.

### Phase 4: The skill, with what was learned

**What changes:**

- `/ios-ui-review` (`.claude/skills/ios-ui-review/`): the routine as it actually went. Check the disk and the lock, run the source check and the walk, read the report, look at the pictures, check each finding against the code, build the review page with today beside the proposal, ask, file. Arguments: `quick`, `standard`, `full`, a page's name to look at only that page, and `since <version>` to look only at pages whose files changed.
- `learnings.md` beside it: what the checks get wrong and why, what a script can't reach and the way round it, what was turned down and shouldn't be raised again, how long each configuration takes. The skill reads it first and adds to it last.
- `design-checklist.md` beside it: what "modern" is measured against, with the date it was last brought up to date against Apple's guidance.
- A rule in `CLAUDE.md` naming the source check and the skill, and when the skill is due (before a TestFlight build that changes screens).

**What you have to do:** Nothing; try `/ios-ui-review quick` when you like.

**Done when:**

- The skill, its learnings and its checklist are in the repo and listed in `CLAUDE.md`.
- A dry run of `/ios-ui-review quick` follows the skill as written, start to finish.

**Depends on:** Phase 3.
