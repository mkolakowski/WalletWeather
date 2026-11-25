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
