# iOS labels: one way to label, report and size

Tracking issue: #312

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Labels and rows | #310 | Planned 2026-11-23; not started |
| 2. Large text and problems | #311 | Planned 2026-11-23; not started |

Planned 2026-11-23 from a design review of iOS 0.34.0, asked for as "can you perform a design review of the ios app, looking for ux inconsistancies and suggest more features for the duo. please also take a look at overhauling settings and I would also like a plan for the ability to connect to multiple servers as well as running local and even accessing the demo (from the settings)". The review ran the app in the demo on the Duo simulator in every pose and at a large text size, made 27 findings (R1 to R27) and twelve ideas (F1 to F12), and drew today beside the proposal for each ([the review page](https://claude.ai/artifact/YanSV7o5FqX9WC6SdzZkyj), private to Matthew). The choices made in four rounds of questions are on the [decision page](../docs/dev/decisions/ios-review.md).

Sessions: may span — two phases that each touch most pages, so not alongside the fold work.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Labels and rows | Sonnet | Sonnet: the pictures of every page | One component changed and two lists brought into line. |
| 2. Large text and problems | Opus | Sonnet: the pictures at three text sizes | Fixed frames across many files, and layouts that have to change shape at the largest sizes. |

## Open questions

None. A question that comes up while building goes here, with the phase it blocks.

## The plan

**Goal:** Across the iPhone app, a label is written one way, a list row looks one way, a problem is reported one way, and every size follows the phone's text size.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/ios-review.md)):

- **Labels are sentence case,** as the web app's have been since 1.98.0 (R17).

**Out of scope:**

- Settings' rows and notes (R20 to R22): `Plans/ios-settings.md`.
- The date format (R18): `Plans/ios-settings.md`.
- Any change to what a page shows or does.

**What's there today:**

- `Caption` (`Theme.swift:273`) writes small capitals; beside it in the same cards are sentence-case labels; Settings has bold `SectionTitle` headings (`MoreView.swift:995`); lists use the system's headers.
- Reports' rows are tinted like links when open (`MoreView.swift:570`); Bills & income, Search and Tags use plain rows with a highlight.
- Open, the Search field sits at the top right while the results are on the left (`SearchView.swift:63`).
- Fixed sizes: the Calendar's 30-point day circle and its 9 and 10 point figures (`CalendarView.swift:254`, `:287`), the Forecast table's 24 and 80 point columns (`ForecastView.swift:593`), 50 and 56 point date columns in the summaries. Nothing uses `ScaledMetric`. At Accessibility Large, day numbers turn into "…", amounts are cut, labels hyphenate and figures wrap mid-number (pictured in the review).
- Problems arrive as an alert in the editors (`LineEditor.swift:132`), red text under the field in New account and the passphrase sheet, and a line in the Bank sync card.

**How every phase is checked:** `swift test` passes. Duo simulator pictures of every page, closed and open, are linked from the phase issue: in two looks for phase 1, and at three text sizes (Large, Extra Extra Extra Large, Accessibility Large) for phase 2.

**Versions:** each phase bumps the iOS version and adds its changelog entries under `[Unreleased]`.

### Phase 1: Labels and rows

From the review: R17, R26, R27.

**What changes:**

- **One label style, in sentence case** (R17): "Balance today", not "BALANCE TODAY". `Caption` keeps its name and loses its capitals.
- **Reports' rows are plain,** with a chevron and a highlight for the open one, like Bills & income and Search (R27).
- **Open, the Search field sits over its results** (R26).

**What you have to do:** Look at the pictures.

**Done when:**

- Pictures of every page, closed and open, in two looks, are linked from the issue.
- `swift test` passes.

**Depends on:** Nothing. Best done when the fold work (`Plans/duo-more.md` phase 1) isn't in flight, since both touch every page.

### Phase 2: Large text and problems

From the review: R16, R25.

**What changes:**

- **Sizes follow the phone's text size** (R25): the fixed frames scale; at the accessibility sizes, figures that share a row stack one to a row; a label never breaks mid-word; a day's number is always whole.
- **Two rules for problems** (R16): what you typed is answered under its field; what the server refused is one banner at the top of the form with the way forward (Try again, Sign in again). The same in the editors, New account, the passphrase sheet and Bank sync.

**What you have to do:** Set your phone's text size to its largest and open Forecast and the Calendar on the Duo.

**Done when:**

- Pictures of Dashboard, Forecast, Bills & income and Calendar, closed and open, at Large, Extra Extra Extra Large and Accessibility Large, with nothing cut, hyphenated or replaced by "…".
- A picture of each kind of problem in an editor, New account and Bank sync.
- `swift test` passes.

**Depends on:** Phase 1.
