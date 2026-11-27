# The iPhone app's UI review suite: the choices behind it

Decisions for `Plans/ios-ui-review.md` (#348), the one WalletWeather artifact (#351) and its before-and-after page (#352), and the issues filed from the first review (#357 to #370). The suite is three layers: a source check in `swift test`, a simulator walk, and a design review written up by `/ios-ui-review`. The first review ran on iOS 0.70.0 on 2026-11-24 and is the *iOS UI review* page of [the WalletWeather artifact](https://claude.ai/artifact/W9sBSzEo3kphuf6SEq5dHB) (private to Matthew).

## 2026-11-24: what the suite is, and what a run covers

**Decided:** 2026-11-24, by Matthew, in one round of questions. **Status:** accepted.

1. **All of it is built:** the source check, the walk, a first full review and the skill. Tools now and the review later, and the walk and review without the source check, were the other options.
2. **A standard run covers the iPhone Duo closed and open on its side, and an iPhone 17,** in light and dark, at Large and Accessibility Large. The Duo alone, and every pose, look and size every time, were the other options. As built, each configuration is asked only for what it's good at (one device in full, dark at the top of each screen, large text down each screen's length), because every screen needs a fresh launch and a run is 70 to 100 minutes, not the 30 to 40 first said.
3. **Findings go on a review page and Matthew picks what's filed.** Fixing clear bugs straight away, and filing everything, were the other options.
4. **A new slip in the source check fails `swift test`.** Stated with the first choice; today's slips sit on a baseline that only shrinks.

## 2026-11-24 and 25: one artifact, and the before-and-after page

**Decided:** by Matthew, as the first pages were published. **Status:** accepted.

1. **One WalletWeather artifact, with a page for each thing that would have been its own artifact** (#351). It started with Home, the write-up of the suite's changes, the UI review and the before-and-after page; the 23 Nov review keeps its own link, listed on Home. Rebuilding the older pages inside it, and starting clean, were the other options.
2. **Every page carries a bar listing every page.** Asked for the day the artifact went up.
3. **Stubs for standing pages, then all five filled from the repo** (#353): Changelog, Roadmap, Plans, Decisions and Waiting on you, each written by a script. Leaving them as stubs, filling four, and changing the set were the other options.
4. **A before-and-after set is taken at each TestFlight upload** (#352). Each release, every iOS version bump, and only when asked were the other options.
5. **A set covers the top of every screen in light, on an iPhone 17 and on the Duo open on its side.** The iPhone alone, and both Duo poses in light and dark, were the other options.
6. **The page shows changed screens only, side by side, the changed part outlined.** A drag-to-compare slider, and every screen every time, were the other options.

## 2026-11-25: what the first review's findings become

**Decided:** 2026-11-25, by Matthew, in two rounds of questions. **Status:** accepted.

1. **B1, Cancel in the line editor closing the app, is fixed straight away** (#357). Filing it for later, and trying it on his phone first, were the other options.
2. **The other four bugs are filed:** Connections' rows (#358), Compare at a phone's width (#359, with its own choice left open: one side at a time, or close it when narrow), tag colours for VoiceOver (#360), and To confirm at the largest text sizes once it has been run again on the current build.
3. **Filed as they stand:** tap targets under 44 points (#361), labels cut short at large text (#362), Tags and Tab bar looking like the other Settings pages (#363), the month menu in calendar order (#364), the source check's baseline worked down (#368), four named corner radii (#369), Reports' list in a card (#370).
4. **Content cards become solid, and glass is kept for what floats** (D1, #365): the tab bar, the connection chip, toolbar buttons, the Undo bar, banners. Keeping glass cards, glass for one summary card a page, and seeing more first were the other options. Pictures in every look come before anything ships. This replaces "a card: Liquid Glass" as the app's look (`Theme.swift`, and the mockups of 2026-11-14).
5. **Captions are darkened to 4.5:1** (D2, with #365). Keeping the system's grey, and deciding from D1's pictures, were the other options.
6. **Every date follows the date format chosen, weekday included: "Sat 2026-12-12"** (I1, #366). Written-out dates staying as they are, and only lists following, were the other options.
7. **An entry is a "line" everywhere, on the iPhone and the web** (I5, #367). "Transaction" everywhere, and leaving it, were the other options.

**What it changes:** issues #357 to #370; the source check's rules and baseline; the review skill's learnings, which record what was judged so the next review doesn't raise it again.

## 2026-11-26: Compare on a narrow screen shows one side at a time

**Decided:** 2026-11-26, by Matthew, when #359 was picked up. **Status:** accepted.

1. **Under about 600 points Compare shows one side at a time, with a switch at the top** (B4, #359). Closing Compare when the width turns compact was the other option: smaller, but it loses the place and the feature with it.
2. **The switch names each side by its account and month** ("Checking, Nov 2026"), and the account and month pickers under it change the side shown. The open Duo keeps two columns.

**What it changes:** `Compare.narrowWidth` and `Compare.days(of:left:right:)` in the Kit, `CompareView` in `BigScreenViews.swift`; iOS 0.73.4.

## 2026-11-26: four corner radii

**Decided:** 2026-11-26, by Matthew, when #369 was picked up. **Status:** accepted.

1. **The app uses four corner radii: card 22, bar 14, row 10, tile 6** (D3, #369). Card 22, bar 14, row 12, tile 8, and card 24, bar 16, row 12, tile 8 were the other options.
2. **Done on the current cards, apart from #365.** Waiting for the solid-cards choice, and skipping the work, were the other options. `Theme.swift` and `SettingsView.swift` were being edited for #365, so their four literals stay on the source check's baseline until that lands.
3. **Each odd size snapped by what the shape is**, not only by distance: the 12s on fields and rows became 10, selected-row highlights of 8 became 10, 7s became 6, 24s and 18s went to a card's 22 or a bar's 14.

**What it changes:** `Radius` (`Views/Radius.swift`), about fifty call sites, the source check's `corner-radius` rule and its survey; iOS 0.73.14. Pictures before and after are on the *Corner radii* page of the WalletWeather artifact.

## 2026-11-27: solid cards are built without a before-and-after set

**Decided:** 2026-11-27, by Matthew, when #365 was picked up again. **Status:** accepted.

1. **Solid cards (D1) and darker captions (D2) are built now, without the before-and-after set the issue asked for first.** The 224 pictures from the paused work (25 November) were gone (the walk keeps its last three runs), and a smaller set, or the full set of several hundred pictures and about three hours, were the other options. The page tint behind the cards stays as it was.
2. **Glass stays on what floats:** the tab bar, toolbar buttons, the Undo bar, the problem banner and the drop target.
3. **No setting for it.** A solid-or-glass switch was not asked for and not added.

**What it changes:** `Card` and `Caption` in `Theme.swift`, `SettingNote` in `SettingsView.swift`, the debug switches for the pictures are gone; iOS 0.73.15. The *Solid cards* page of the WalletWeather artifact shows Dashboard and Reminders in five looks, as built.
