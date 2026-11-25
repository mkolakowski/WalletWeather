---
name: ios-ui-review
description: Review the iPhone app's user interface for bugs, inconsistencies and a dated look - run the source check and the simulator walk (every screen in the demo on an iPhone 17 and the iPhone Duo, in light, dark and large text), read the report and the pictures against the design checklist, check each finding against the code, and write a review page with a picture of today beside the proposal for every finding. It only looks; nothing in the app changes until the user picks what to file. Use when the user asks to "review the iOS UI", "check the app for UI bugs", "does the app still look modern?", "run the UI review", before a TestFlight build that changes screens, or runs /ios-ui-review. Argument - nothing for the standard run; quick, full, a page's name (forecast, settings, ...) to look at only that page, or "since <version>" for the pages whose files changed.
---

<!-- WalletWeather's own skill (Plans/ios-ui-review.md, #347), written 2026-11-24. Not from claude-playbook. -->

# iOS UI review

Finds what's broken, what's inconsistent and what looks dated in the iPhone
app, the same way every time, and writes it up for Matthew to pick from. It
never fixes what it finds, files nothing before he picks, and never uses a
real server or account: only the demo and the simulator's sample household.

Three files beside this one are part of it. Read the first two before
starting:

- [`learnings.md`](learnings.md): what the checks get wrong, what a script
  can't reach, what's already been judged, how long things take.
- [`design-checklist.md`](design-checklist.md): what "modern" is measured
  against, and when it was last brought up to date.
- [`scripts/review_kit.py`](scripts/review_kit.py) and
  [`scripts/review-template.py`](scripts/review-template.py): the review
  page's builder, and a review to start from.

The suite itself is in `apps/ios` ("Reviewing the UI" in its README):
`UISourceTests` in `swift test`, the UI tests in `UITests/`, and
`Scripts/ui-walk.sh`, `ui-report.py` and `ui-sheet.swift`.

## 1. Before the run

- It changes tracked files only at the end (the learnings, `Known.json`,
  perhaps a check): work from an issue, as the project's rules say.
- `df -g /System/Volumes/Data`: the walk refuses under 5 GB. If it's short,
  `~/GitHub/mkplus/Scripts/free-space.py list` shows what can go; ask first.
- Check nobody else is mid-run: `cat /tmp/pillowplayer-simulator.lock/command`.
  The walk waits its turn, but an hour's wait is worth knowing about.
- If the design checklist is more than three months old, or a new iOS has
  come out since its date, search for what changed and bring it up to date
  first.
- Pick the run from the argument:

| Argument | Command | About |
| --- | --- | --- |
| (none) | the standard set, as two commands: the iPhone's configurations, then the Duo's (below) | 55 + 55 minutes |
| `quick` | `apps/ios/Scripts/ui-walk.sh quick` | 12 minutes |
| `full` | `apps/ios/Scripts/ui-walk.sh full` | several hours, over the limit on one background command: ask first, and split it by device |
| a page | `apps/ios/Scripts/ui-walk.sh --only <names>` with the configurations that matter | 1 to 2 minutes a screen |
| `since <version>` | `git diff --stat <that version's commit>.. -- apps/ios/WalletWeather`, then `--only` the screens those files draw | varies |

The standard set, split so neither half meets the 2-hour limit on a
background command:

```bash
apps/ios/Scripts/ui-walk.sh --config iphone.light.large:deep --config iphone.dark.large \
    --config iphone.light.ax-l:scroll --config iphone.light.large.iso
apps/ios/Scripts/ui-walk.sh --no-build --config duo-closed.light.large:scroll --config duo-closed.light.ax-l \
    --config duo-open.light.large:scroll --config duo-open.dark.large --config duo-open.light.ax-l
```

Each makes its own run folder; move both into `apps/ios/build/ui-kept/<name>/`
before doing anything else (only the last three runs are kept), and run
`ui-report.py --sheets` on each.

## 2. Run it

Run the walk in the background (it takes the simulator lock for the whole
run, so never start a second one) and wait for it with one background
`until` loop on `<run>/report.md`, not with repeated checks. It prints one
line per configuration; `FAILED` on a line means the planted faults weren't
all found or the test stopped: read `<configuration>/xcodebuild.log` before
trusting that configuration.

The run's folder, `apps/ios/build/ui-review/<run>/`, then holds `report.md`
(read it first), `report.json`, `sheets/`, `crashes/`, `source.json` and a
folder per configuration.

## 3. Read what it found, in this order

1. **Crashes and stuck flows** (`## Crashes`, `crashed`, `flow-stuck`,
   `not-what-it-says` in `report.md`). A crash is the first finding. A stuck
   flow is the app's fault or a stale flow: look at its `.stuck.jpg` and
   `.stuck.tree.txt` before deciding which.
2. **The overview sheets,** every one: `sheets/overview.<configuration>.NN.jpg`,
   eight screens an image. Note the screens that look wrong or unlike their
   neighbours.
3. **Those screens up close:** `sheets/<screen>.<device>.looks.jpg` (one
   screen across looks and text sizes) and `<screen>.<configuration>.long.jpg`
   (down its length). Read single pictures only where a sheet is too small.
4. **The findings by check,** bugs first. Each is a candidate. Apple's
   `audit-*` findings most of all: look at the picture before believing one.
5. **Comparing screens** and **Words that mean the same thing** at the end
   of the report, and the source check's survey (radii, spacings, type
   styles).
6. **The design checklist,** line by line, against the sheets.

With `WW_UI_TREE=1` in front of the command, each screen's element tree is
written beside its pictures: the way to see why a check said what it said.

## 4. Check each finding against the code

Before a finding goes on the page: find the lines that draw it, say why it
happens, and make sure it isn't by design (the decision pages in
`docs/dev/decisions/`, the plan the screen came from, a comment at the
line). Then one of three things happens to it:

- **It's real:** it goes on the review page.
- **The check is wrong:** fix the check, or add an entry to
  `apps/ios/UITests/Known.json` with why, and a line in `learnings.md`.
- **It's by design or already decided:** `Known.json` and `learnings.md`
  ("Judged already"), so it isn't raised again.

A fault the walk should have caught and didn't is a new check, or a new
planted fault in `DebugFaults.swift`, or a new screen or flow.

## 5. Write the review page

Copy `scripts/review-template.py` into the run's folder as `review.py`, fill
it in and run it. Every finding has: what's wrong in a sentence a person
using the app would recognise, where, the proof (which check or flow, which
file and line), the fix and its size, and **a picture of today beside the
proposal**: today cut from the run's pictures, the proposal drawn with the
kit and marked as drawn. Where a script can't reach a screen, redraw today
from the code and say so. A choice between shapes draws each option, and
lists them under the finding.

Three groups, in this order: bugs, inconsistencies, design. Number them
B1…, I1…, D1…. Check the crops before publishing: draw every cut picture on
one sheet with `ui-sheet.swift` and look at it once.

The review is the *iOS UI review* page of the WalletWeather artifact, never
an artifact of its own: `review.py` writes `review.body.html`, and
`/artifact-page` wraps it as `ios-ui-review`, rebuilds Home and publishes.
Link the page from the issue.

## 6. Ask, file, record

- Ask what to file with AskUserQuestion, a few findings a round, the
  recommended choice first. A crash gets its own question, first.
- File what's picked: one issue a fix, or a plan (`/new-plan`) where one
  needs phases. Each issue links the review page and names its finding.
- Record the choices with `/record-decision`, and what was turned down in
  `learnings.md` and `Known.json`.

## 7. Wrap up

- Add to `learnings.md`: what was learned this run, with the date and issue.
- Commit the learnings, `Known.json` and any check that changed, by name.
  Pictures never go on `main`.
- Report: the run (version, configurations, minutes), the counts by group,
  the page's link, what was filed, what the walk couldn't reach.
