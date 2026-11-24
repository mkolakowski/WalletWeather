# The iPhone app's design review: the choices behind its plans

Decisions for `Plans/ios-settings.md` (#298), `Plans/connections.md` (#303), `Plans/duo-more.md` (#309) and `Plans/ios-labels.md` (#312), and the single issues filed with them (#293, #313 to #329), from a design review of iOS 0.34.0 done on 2026-11-23. The review read every screen's code and ran the app in the demo on the iPhone Duo simulator: closed, open on its side, open upright, half open, and at the Accessibility Large text size. It made 27 findings (R1 to R27) and twelve ideas (F1 to F12), and drew today beside the proposal for each ([the review page](https://claude.ai/artifact/YanSV7o5FqX9WC6SdzZkyj), private to Matthew).

## 2026-11-23: what is planned, and how it's filed

**Decided:** 2026-11-23, by Matthew, in four rounds of questions. **Status:** accepted.

- **Every suggestion carries a before and an after picture.** The first draft pictured only the most visual findings; Matthew asked for both pictures on all of them before anything was filed. Where a script can't reach a screen (anything below the first screen of Settings, a swipe, an alert), today's side is redrawn from the code and says so.
- **Four plans, and single issues for what stands alone.** `ios-settings` (four phases), `connections` (four), `duo-more` (five) and `ios-labels` (two); the demo's dead end on Tags as a bug (#293); five small changes on their own (#313 to #317). Three plans with the label fixes as single issues, or plans only, were the other options.
- **All twelve ideas are issues** (#318 to #329). Widgets, reminders, and Shortcuts and Siri (#318 to #320) each open with a privacy question, since they put numbers outside the app; roadmap item 39 lists them.
- **The first screen and sign-in on the fold (R3) are not filed.** See "the Duo" below.

## 2026-11-23: Settings

**Decided:** 2026-11-23, by Matthew. **Status:** accepted.

1. **Sections and pages** (shape A): a connection card, More pages, Your household, This iPhone and About, each row opening its own page. One regrouped scrolling page (B), and a More tab with Settings behind a row (C), were drawn beside it.
2. **Open, Settings behaves like the Duo's own Settings** (R1): a sidebar about a third of the width and the chosen page beside it, crossing the fold as the system's does. The review first drew it as two halves meeting at the fold, like the other pages; Matthew asked for the system's shape instead. A picture of the Duo's Settings is on the review page.
3. **Themes people make themselves** (R19.5), asked for by Matthew: My themes under the built-in looks, with an editor.
4. **Custom themes are kept in iCloud,** so they follow to the person's other iPhones. On this iPhone only (the review's pick), or on the server so the web app gets them too, were the other options.
5. **A faint pair of colours gets a warning and still saves.** Refusing to save under 4.5:1 was the other option.
6. **Pages follow the same account, with a switch** (R9): picking an account on one page moves the others, on by default. Leaving each page on its own was the other option.

7. **A custom theme changes six colours** (decided 2026-11-23, by Matthew, before phase 4, #297): page, card, text, accent, money in and money out, with the warning and outline colours worked out from them. Accent only, accent and page, and every colour (about a dozen, warning and outline included) were the other options. This was the plan's one open question.

## 2026-11-23: connections, the demo and the lock

**Decided:** 2026-11-23, by Matthew. **Status:** accepted.

1. **Connections cover servers, this iPhone and the demo, with one in front at a time.** Servers only at first, or a different connection in each Duo window from the start, were the other options. A connection per window is looked at again after phase 4.
2. **One household on this iPhone, one lock for the whole app, and the household's backup and bank sync keep running while a server is in front.** These were stated with the first choice.
3. **The chip that says where you are shows under the Dashboard's title and at the top of Settings.** Under every page's title was the other option.
4. **With the lock on, the app opens in the demo.** Matthew's note: "if the user has face/touch id turned on for the app, it will be required to exit demo mode, the app will boot to demo mode until face/touch id is re applied". Read as: when the app opens, or comes back after a minute away (the clock the lock uses today), it shows the demo; choosing a real connection is what asks for Face ID or Touch ID.
5. **A switch brings the plain lock screen back; the chip says "Demo" and is the way out; the passcode works when Face ID fails.** "When locked, show the demo" is in Privacy & lock, on by default, as the rule on behaviour some people would want the other way asks. Always the demo with the chip, and always the demo with nothing on screen saying so, were the other options.

**What it replaces:** `Plans/ios-app.md` listed "more than one server at a time" as out of scope, and the demo opened only from the first screen (2026-11-16, [the iPhone app's decisions](ios-app.md)). The demo's bar on every page becomes the chip.

## 2026-11-23: the Duo

**Decided:** 2026-11-23, by Matthew. **Status:** accepted.

1. **The first screen and sign-in stay as they are when open** (R3). The review found both sit on the fold as one centred column and drew one card in each half; Matthew chose to keep them. Nothing is filed.
2. **Flat open, pages keep today's layout; half open, each page stacks at the hinge; the change is animated** (R5). Matthew's note: "keep existing when not folded, but use proposed, with animations taking the not folded to folded view". With Reduce Motion on, the two layouts cross-fade.
3. **An account opens in Forecast everywhere it's shown** (R7), and the Calendar's lines open like Forecast's (R8). These were proposed and filed without change.

**Left as an assumption:** R2 moves the gap between the two panes 42 points, onto the fold, when the Duo lies flat. It rests on the hinge being the screen's centre line. Matthew was told R2 still stood after the note on R5 and filed the plan as drawn; `Plans/duo-more.md` lists it as an open question that phase 1 checks first.

**What it changes:** the four plans and issues #293 to #329; roadmap items 35 to 39.

## 2026-11-23: where the fold is, and what R2 becomes

**Settled:** 2026-11-23, by the check `Plans/duo-more.md` asked for before phase 1 (#304), not by a new choice. **Status:** accepted; Matthew can overturn it.

**The question:** R2 proposed moving the gap between the two panes 42 points, onto the screen's centre line, when the Duo lies flat. It assumed the fold needs keeping clear there. The plan said to check first, and to drop R2 if the Duo already keeps content clear of a flat fold by itself.

**What the simulator reports** (`reservedRegions(kind: .division)`, logged from Forecast in each pose):

- Flat, on its side or upright: no region at all. iOS asks for nothing to be kept clear, and the Duo's own Settings runs its page across the fold.
- Half open like a book: a band 40 points wide, x 455.5 to 495.5 of the screen's 951, so centred on the centre line.
- Half open like a laptop: the same band across, y 455.5 to 495.5.

**What follows:**

- **Flat, the two panes stay exactly where they are.** This also matches Matthew's note on R5, "keep existing when not folded".
- **R2 applies half open like a book,** where today the right-hand pane starts at 461.5 points and so sits on the band. There the panes go either side of it.
- R5's stacked layout covers half open like a laptop, as decided.

Still to confirm on a real Duo: that it reports the same as the simulator.

## 2026-11-23: what shows outside the app while the phone is locked

**Decided:** 2026-11-23, by Matthew, before #318 to #320 are built. **Status:** accepted.

Widgets, reminders, and Shortcuts, Siri and Spotlight each put numbers outside the app, which hides them in the app switcher. Each issue opened with the question of what shows while the phone is locked.

1. **Widgets (#318): amounts hidden until the phone is unlocked.** Labels show, with •••• in place of amounts. Always showing amounts, a switch hidden by default, and not building widgets yet were the other options.
2. **Reminders (#319): the bill's name, the amount hidden until unlocked** ("Rent is due tomorrow"). Name and amount, nothing specific ("A bill is due tomorrow"), and not building reminders yet were the other options.
3. **Shortcuts, Siri and Spotlight (#320): Siri answers balance questions only when the phone is unlocked, and the phone's search lists bills and accounts by name, without amounts.** Amounts in search, always answering, and not building these yet were the other options.

Each still updates `docs/privacy.md` and `apps/ios/README.md` ("What's kept on the phone") in the same change.
