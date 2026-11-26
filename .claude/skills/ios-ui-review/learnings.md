# What the UI review has learned

`/ios-ui-review` reads this before it starts and adds to it before it ends.
One entry per thing learned, newest at the bottom of its section, each with
the date and the issue. An entry that turns out wrong is corrected or
removed, not argued with. What's already judged about a single finding goes
in `apps/ios/UITests/Known.json` (so the report stops raising it) with one
line of why; the reasoning in full goes here.

## How long it takes, and what it costs

- **2026-11-24 (#345):** about 13 seconds a screen with every screenful,
  8 at the top only, and 6 more with Apple's whole audit. Opening a screen is
  7 to 9 seconds of that whatever is asked: the app is launched afresh for
  every screen, because the Debug launch settings are read at launch. A
  whole configuration is 8 to 20 minutes; `quick` is about 12.
- **2026-11-24 (#345):** a picture is about 200 KB (JPEG, 1100 pixels wide);
  a configuration with every screenful is about 30 MB. The last three runs
  are kept. The build folder (`build/sim-dd`) is about 1 GB.
- **2026-11-24 (#345):** the walk needs 5 GB free and refuses under that. A
  full disk has stopped Docker Desktop on this Mac before. mkplus's
  `free-space.py list` shows what can be cleared; ask before clearing, they
  are another project's caches.

- **2026-11-25 (#346):** the first standard run took 2 hours and was stopped by the session's
  2-hour limit on a background command with two configurations to go: 52
  minutes for the iPhone 17's four, then about 11 each for the Duo's, plus a
  wait for the lock and one configuration that wrote nothing. Run the
  standard set as two commands, the iPhone's configurations and then the
  Duo's, each well inside the limit.
- **2026-11-25 (#346):** `ui-walk.sh` keeps the last three runs and deletes
  the rest. A run a review is being written from has to be moved out of
  `build/ui-review/` first (the first review's is in `build/ui-kept/`), or
  the next three short runs delete it.
- **2026-11-25 (#352):** other sessions commit to this checkout while a run
  is going: iOS went from 0.70.0 to 0.71.1 during the first review. Say
  which version a run was built from, and never rebuild `build/sim-dd` while
  a walk that was started with `--no-build` is using it.

## What a script can't reach, and the way round it

- **2026-11-25 (#382):** a hang in Apple's audit uses up the test's whole
  1-hour limit (B2, #385: the locked demo on the open Duo in dark). To tell
  the audit from the app: the same screen with `--no-audit`, and the app's
  CPU while it waits. To find the commit: a worktree of each one, run with
  `--only <screen> --config <one>` and a watchdog that stops it when the
  test has run a couple of minutes with no result (a worktree's first build
  is about 8 minutes). A watchdog that matches on a path also matches the
  build, and an older run's log looks stuck: key it to this run's log.
  #385's cause, found that way: the first card's text sat in the open
  Duo's soft blur under the title capsule. Text there, with nothing above
  it, is what the dark contrast audit can't finish on.
- **Menus, alerts the system owns, drag and drop, the keyboard and pointer,
  Face ID, the camera:** the app has Debug launch settings that show each as
  a sheet or a state (`apps/ios/README.md`). A new one of these needs a new
  setting, in the change that adds it. (2026-11-24, #345)
- **The Duo's pose** is set from outside the app (`duo-set.sh`), so it's part
  of the configuration, never a step in a test. Turning an ordinary iPhone on
  its side is a step (`XCUIDevice.shared.orientation`). (2026-11-24, #345)
- **Text size:** the launch argument `-UIPreferredContentSizeCategoryName`
  sets it for the app alone, so the simulator's own setting is never
  touched. (2026-11-24, #345)
- **The glass setting iOS 27 added** (clear to opaque), Reduce Motion and
  Reduce Transparency: no launch setting and no `simctl` switch was found.
  Judge them from the code. (2026-11-24, #346)
- **Motion:** pictures are stills. The source check's `motion` rule points
  at the code; read it. (2026-11-24, #346)
- **A real phone:** everything here is the simulator, on the newest iOS
  Xcode has. A crash or a layout that depends on the iOS version has to be
  tried on Matthew's phone before it's called certain. (2026-11-24, #346)

- **The open Duo's front screen is black,** and it's the one
  `app.screenshot()` takes: every picture of the open Duo in the first
  review was black, and nobody noticed for two hours because the checks read
  the element tree, not the picture. The walk now takes every screen and
  keeps the one the size of the app's window. Look at one picture from each
  configuration as soon as it lands. (2026-11-25, #346)

## What the checks get wrong, and what was done about it

- **The element tree finds what the pictures can't** (2026-11-25, #382):
  the account picker in a `.largeTitle` toolbar item was on screen but not
  in the tree, so VoiceOver couldn't reach it (B1, #383). Run a review of a
  new control with `WW_UI_TREE=1` and look for it in each configuration's
  `.tree.txt`; a control that shows on one device and not another is the
  sign.
- **A screen that isn't what its name says on one device only** (2026-11-25,
  #386): look at what's below that device's fold. On the open Duo's short
  panes a step's target (Bills' "Rent") or a sheet hung off the end of a
  section (My themes' note, in the lazily loaded Settings pane) can be off
  screen, so the tap misses or the sheet never shows. A `shows` word that
  depends on the date breaks under `WW_UI_TODAY`: check for something the
  launch setting itself puts on screen.
- **The `save-a-line` flow is stale** (2026-11-25, #382): it taps the word
  "Paid", which doesn't flip the switch, so nothing changes, Save stays
  greyed out and `nothing-happened` fires. It needs to tap the switch.
  Not fixed yet: `WalkTests.swift` had another session's edits in it.
- **A row read out as one** (a card or row with
  `accessibilityElement(children: .combine)`) appears as a text the size of
  the row with its words inside it. `text-overlap` skips a text that's
  above another in the tree, that contains the other's words, or that's
  three times its size and wraps it. (2026-11-24, #345)
- **A title in the bar** has the page scrolling under it: `text-overlap`
  leaves anything in a navigation bar alone. (2026-11-24, #345)
- **Strips that scroll sideways** (Forecast's category chips, the widget
  gallery) run past the edge on purpose: `off-edge` skips anything in a
  scrolling area that's under 120 points tall or stops short of the
  window's edge, and anything scrolled out of its area isn't counted as on
  screen at all. (2026-11-24, #345)
- **Apple's own controls are the size Apple made them:** `small-target`
  skips switches, segmented controls, steppers, sliders, text fields, date
  pickers, the list's reorder handle, the Back button, and anything in a
  navigation bar or toolbar. A link inside a sentence is a note, never a
  slip. (2026-11-24, #345)
- **The system's Back button has no label in the tree** (`#BackButton`);
  VoiceOver has its own word for it. `unnamed-control` skips it. Assumed,
  not heard: nobody has listened to VoiceOver say it. (2026-11-24, #345)
- **A text field with a placeholder is named by it.** `unnamed-control`
  counts the placeholder. (2026-11-24, #345)
- **iOS names a symbol by itself** ("Horizontal Bar Chart On A Document"), so
  a symbol-only button is never nameless to the tree. The walk can't tell a
  good name from that; the source check's `icon-only-button` rule does, from
  the code. (2026-11-24, #345)
- **The tab bar's Search has a hidden twin** with no frame, and a bar button
  with a symbol over it isn't "hittable" to XCTest. The walk's `find` looks
  at every match and taps the middle of the first one on screen. A step
  that "can't find" something in a bar is this, not the app. (2026-11-24,
  #345)
- **A page that's still arriving** isn't missing: a step waits 2.5 seconds
  before it scrolls to look for its target, or it scrolls the target away.
  (2026-11-24, #345)
- **A flow leaves things behind** (a keyboard over the tab bar): every flow
  starts from a fresh launch. (2026-11-24, #345)
- **Apple's audit** is a list of candidates, not findings. Its contrast part
  measures the picture, glass included, and names the same text on every
  screen it's on; check each against the picture and the theme's colours
  before writing it up. (2026-11-24, #345)
- **The left margin the report prints** is where most text starts, so a
  centred page or a form reads as "off the usual margin". It points at
  screens to look at; it doesn't measure the page's edge. (2026-11-24, #345)
- **A launch setting that has stopped working** used to leave the walk
  reviewing the Dashboard under another page's name (Tags and Unmatched need
  `WW_DEBUG_PLACE=more` beside their own setting). Every screen in the table
  now names words that must be on it (`shows`), and `not-what-it-says` is a
  bug. (2026-11-24, #345)
- **`grep` in a clean checkout** finds nothing and says so by failing, which
  ended `ui-walk.sh` under `set -e` the first time it ran after a commit.
  Scripts here end such a pipe with `|| true`. (2026-11-24, #345)

- **`shows` has to be at the top of the screen at every text size.** At
  Accessibility Large five screens were called `not-what-it-says` because
  the words they're known by had moved below the fold ("Add a server", "All
  lines"). Use the bar's title or the first heading. (2026-11-25, #346)
- **An ordinary iPhone's tab bar holds three pages,** so a launch setting
  that puts a fourth page in the bar opens something else. The Calendar's
  screens put it first. (2026-11-25, #346)
- **A crash in a flow marks the whole configuration FAILED** in
  `ui-walk.sh`'s line, though every screen was walked. Read `report.md`'s
  Crashes section, not the word. (2026-11-25, #346)
- **Debug-only overlays trip the checks:** the drop highlight
  (`forecast-drop`) and the widget gallery sit over or beside real content.
  They're marked `expected` in the table or are in `Known.json`.
  (2026-11-25, #346)

## Judged already: don't raise these again

Filled in from each round of picking. A line here also has its entry in
`apps/ios/UITests/Known.json` when a check would otherwise raise it.

- **A bank's own text in capitals** ("VERIZON WIRELESS") is data, shown as
  the bank wrote it. In `Known.json`. (2026-11-25, #346)
- **Everything in the first review was picked for filing** (#357 to #370;
  `docs/dev/decisions/ios-ui-review.md`), so nothing was turned down. Before
  raising a finding again, check its issue is closed: an open issue means
  it's known and waiting, not new.
- **Decided, so not open questions any more:** content cards are solid and
  glass is for what floats (#365); captions reach 4.5:1 (#365); every date
  follows the date format, weekday included (#366); an entry is a "line"
  (#367). A review now checks the app against these.

## What was worth the time, and what wasn't

- **Worth it:** `since <version>` with the screens a change draws, on
  seven configurations, about 6 minutes of walking (2026-11-25, #382). It
  found both of 0.73.0's bugs before the TestFlight build.
- **A review gets a page of its own** (`ios-ui-review-<version>`), dated,
  rather than replacing the *iOS UI review* page: the first review's issues
  (#357 to #370) link to its findings. (2026-11-25, #382)
- **Worth it:** the flows that use the app (`testUse`). The first run found
  the one crash, in a minute and a half, where fifty pictures showed
  nothing wrong. Add a flow for every new thing a person can do.
  (2026-11-24, #345)
- **Worth it:** the overview sheets (`sheets/overview.*.jpg`), eight screens
  an image. Looking at all of them first shows which screens are worth a
  closer look, and that each screen is what its name says. (2026-11-24, #345)
- **Worth it:** the page of planted faults. The first run showed one check
  (`symbol-name-label`) could never fire, the same day it was written.
  (2026-11-24, #345)
- **Not worth it:** every look at every text size on every device. Dark
  shows up colour faults at the top of a screen; large text shows up layout
  faults down its length. The standard run asks each configuration for what
  it's good at. (2026-11-24, #345)
