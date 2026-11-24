# Outside the app: widgets, reminders, Siri and search

Tracking issue: #333

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. Widgets and the summary they read | #318 | On TestFlight (0.65.0, build 479); pictures and phone check to come |
| 2. Reminders worked out on the phone | #319 | On TestFlight (0.65.0, build 479); pictures and phone check to come |
| 3. Open To confirm and What's my balance | #320 | Released in 1.98.2 (iOS 0.66.0); on TestFlight from build 492 (0.68.1, #337); phone check to come |
| 4. Bills and accounts in the phone's search | #331 | Released in 1.98.2 (iOS 0.67.0); on TestFlight from build 492 (0.68.1, #337); phone check to come |
| 5. Add a transaction and Mark a bill paid | #332 | Released in 1.98.3 (iOS 0.68.0/0.68.1); on TestFlight as build 492; phone check to come |

Planned 2026-11-23 (about 11:00 PM ET), from #318, #319 and #320 (ideas F1 to F3 of the iOS review), on iOS 0.63.0.

- **Phase 1:** iOS 0.64.0, 2026-11-23 (042eea0). Verified: 16 new Kit tests on the summary (written, read, refused while locked, deleted on sign-out, on Nothing and on Delete everywhere, no numbers for Nothing) in a full `swift test` of 468 that passed; the app and widget extension build for the simulator. Not yet: simulator pictures (the shared simulator lock refused while the external SSD was unplugged) and the check on the phone from TestFlight.
- **Phase 2:** iOS 0.65.0, 2026-11-24 (e6b7213). Settled while building (2026-11-24, ios-review.md): Balance heading under watches one picked account, starting at $100; reminders follow the connection in front. Verified: 15 new Kit tests (each switch, nothing when off, for the demo or Nothing, a dip told once, bank lines once, no amount in any text, the expanded view's ••••) in a full `swift test` of 483 that passed; app and both extensions build. Not yet: TestFlight (the new expanded-view extension needs its App ID registered), simulator pictures (PortSSD) and the check on the phone.
- **Phase 3:** iOS 0.66.0, 2026-11-24 (3a493db), on TestFlight as build 482. Built in the app itself (no new extension, so no App ID to register): `OpenToConfirmIntent` and `BalanceIntent` as App Shortcuts, the answers decided in WalletWeatherKit's `ShortcutAnswers.swift`. With no saved connection (only the demo) What's my balance says there's nothing kept to tell; with the demo in front and a saved connection behind it, it answers for that saved connection, by name. Verified: 13 new Kit tests (unlocked, app lock on before and after Face ID, Nothing, the demo, a locked phone, no summary yet, where Open To confirm lands) in a full `swift test` of 496 that passed; the app builds for the simulator with both intents in its App Intents metadata. Not yet: whether Face ID can show from Siri without opening the app (if not, the answer says to unlock WalletWeather) and the check on the phone.
- **Phase 4:** iOS 0.67.0, 2026-11-24 (a62a238), on TestFlight as build 485. The index follows the summary store itself (writing replaces a connection's entries, deleting removes them, and the app rebuilds it from the summaries at start), so Nothing, sign-out, leaving the household and Delete everywhere need no code of their own. A named Core Spotlight index with complete protection, so nothing in it is searchable while the phone is locked. No setting of its own: iOS has a per-app Search switch. Verified: 11 new Kit tests (each connection kind, no amount in any field, a bill gone on the next write, sign-out, leaving the household, prune and Delete everywhere, rebuilding, a locked phone left alone, the links) in a full `swift test` of 507 that passed; the app builds for the simulator. Not yet: simulator pictures (PortSSD unplugged) and the check on the phone.
- **Phase 5:** iOS 0.68.0, 2026-11-24 (c207a3e), on TestFlight as build 489. Add a transaction opens the Dashboard's Add transaction sheet on the connection in front, filled in (amount as spending; the sheet can change it). Mark a bill paid runs in the background on the connection in front: its bill is picked from that summary's bills (not income), its earliest unpaid date this month or next is marked paid as planned (the same `save` as a swipe), then the summary is written again. Read as settled from #332: Face ID only while the app lock is on (the phone unlocked otherwise), as for What's my balance. Refused: no saved connection (the demo), a locked phone, Nothing, a bill not on the connection in front, an account the sign-in can't change. Verified: 13 new Kit tests (the sheet's draft; paying on the household on this iPhone, next month's date after this month's, nothing left to pay; paying on a server's answers and a server's refusal; each refusal, the app lock before and after Face ID) in a full `swift test` of 520 that passed; the app builds with all four intents and the bill entity in its App Intents metadata. Not yet: whether a change made this way on a household with iCloud sync reaches iCloud before the app opens, and the check on the phone.
- **Builds 482, 485 and 489 never reached TestFlight** (found 2026-11-24, #337): App Store Connect failed each after accepting the upload (ITMS-90626), because two App Intent descriptions said "iPhone". Fixed in iOS 0.68.1; `testflight.sh` now checks the archive's App Intents metadata before uploading. Build 492 (0.68.1) is VALID, in the External Testing group with What to test, and waiting for Beta App Review; it carries phases 3 to 5.

Sessions: may span — five iOS versions, each tried on your phone from TestFlight before the next builds on it.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. Widgets and the summary | Opus | Sonnet: `swift test` runs and simulator pictures | A new app group and extension target, the summary every later phase reads, and the privacy decision. |
| 2. Reminders | Opus | Sonnet: `swift test` runs and simulator pictures | Scheduling ahead around files a locked phone keeps closed, and the privacy decision on what a locked phone shows. |
| 3. Open To confirm, What's my balance | Opus | Sonnet: `swift test` runs | App Intents with the unlocked-only rule and the app lock. |
| 4. The phone's search | Opus | Sonnet: `swift test` runs and simulator pictures | What goes into the system's index, and taking it out again, under the privacy decision. |
| 5. Add a transaction, Mark a bill paid | Opus | Sonnet: `swift test` runs | Actions that change someone's numbers, through whichever connection holds them. |

**Tools for every phase:** `(cd apps/ios/WalletWeatherKit && swift test)`; `cd apps/ios && xcodegen generate`; the Duo simulator only through `~/GitHub/mkplus/Scripts/with-simulator.sh`, with the Debug launch settings in `apps/ios/README.md`; `apps/ios/Scripts/testflight.sh` after a full passing run. System frameworks only: WidgetKit, App Intents, UserNotifications, Core Spotlight. No packages.

**Rules that bind every phase:** the 2026-11-23 decision on what shows while the phone is locked ([ios-review.md](../docs/dev/decisions/ios-review.md)), plus this plan's two decisions below; `docs/privacy.md` and `apps/ios/README.md` ("What's kept on the phone") change in the same commit as the feature; settings-toggle rule; stable identifiers (the app group, the summary's file names, the widget kinds, the intent and Spotlight identifiers are new ones that never get renamed); release routine (`MARKETING_VERSION` and `AppInfo.version` together, then `xcodegen generate`, a changelog entry under `[Unreleased]`); one simulator at a time; commit to `main` by file name.

## Open questions

None left: all six were settled on 2026-11-23, so no phase waits on a choice.

1. ~~**When does "bill due tomorrow" arrive?**~~ 9:00 AM the day before, one time for every bill, changeable under the switch ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-when-reminders-arrive-and-how-they-start)).
2. ~~**Are the three reminder switches on or off to start?**~~ Off; iOS asks for permission when the first is turned on ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-when-reminders-arrive-and-how-they-start)).
3. ~~**How far ahead does "balance heading under" warn, and how often?**~~ When the forecast first goes under the amount within the next 7 days, once for each dip ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-when-reminders-arrive-and-how-they-start)).
4. ~~**If the expanded reminder can't show the amount reliably, what then?**~~ Reminders carry no amount at all, and Matthew is told before it ships that way ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-when-reminders-arrive-and-how-they-start)).
5. ~~**Which connections go into the phone's search?**~~ The household on this iPhone and servers that keep Last-known numbers; not servers set to Nothing, not the demo, and signing out removes a server's entries ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-what-goes-into-the-phones-search-and-which-actions-open-the-app)).
6. ~~**Do Add a transaction and Mark a bill paid finish without opening the app?**~~ Add a transaction opens the filled-in Add transaction sheet; Mark a bill paid runs without opening the app (after Face ID) and says what it did ([decided 2026-11-23](../docs/dev/decisions/ios-review.md#2026-11-23-what-goes-into-the-phones-search-and-which-actions-open-the-app)).

Settled while planning (2026-11-23, recorded in [ios-review.md](../docs/dev/decisions/ios-review.md)):

- **With the app's own lock on, amounts stay hidden outside the app even on an unlocked phone.** Widgets show ••••, Siri asks for Face ID before answering, and names still show in the phone's search.
- **A server set to keep Nothing gets a widget with no numbers:** the widget names the connection and says to turn on Last-known numbers to see numbers there.

## The plan

### The goal

Today nothing of WalletWeather shows outside the app, and the app switcher hides it. The plan puts the numbers people check most where they already look: widgets on the Home Screen, the Lock Screen and in StandBy; reminders for a bill due tomorrow, a balance heading under a set amount, and new bank lines to match; Siri and Shortcuts actions (also on the Action button); and bills and accounts in the phone's own search. All of this keeps to what was decided about a locked phone.

### Out of scope

- Pushes from a server (roadmap item 6 is the server's side of reminders). Everything here is worked out on the phone.
- iPad, Mac, Apple Watch and Control Center controls.
- Live Activities and interactive widget buttons (a widget opens the app at the right place, nothing more).
- Anything a locked phone would have to fetch: the app never reaches a server while the phone is locked.

### What the code allows, and the approach that follows

- A server's sign-in is a Keychain item readable only while the phone is unlocked. The last-known numbers (`KeptResponses`) are written with complete file protection. So is the household on this iPhone (`LocalStore`), unless iCloud sync is on. So **nothing can be fetched or worked out while the phone is locked.** Every widget's numbers and every reminder are prepared while it's unlocked: when a page loads, or when a background refresh runs on an unlocked phone. The extensions only read what was prepared.
- **The summary** (WalletWeatherKit, new): one small JSON file per connection in a new app group, `group.net.iptater.walletweather`. It holds the connection's name and kind, when it was made, each account's name, balance and month's low, the next bills (name, date, amount), the To confirm count, and the bills' and accounts' names and ids for search and Shortcuts.
  - It's written with complete file protection, so nothing reads it while the phone is locked, not even the widgets.
  - It's left out of backups.
  - It's deleted with its connection's sign-out, on choosing Nothing, and by Delete everywhere.
  - A server set to Nothing gets a summary with its name and no numbers.
  - The app-lock setting is copied into the group so the extensions can hide amounts.
- `KeptResponses` and the household store stay where they are. Nothing moves into the group, so nothing is migrated and the extensions can reach only the summary.

### Phase 1: Widgets and the summary they read (#318)

**What changes:**

- **The groundwork:** the app group on the app and a new widget extension target (`project.yml`, then `xcodegen generate`), and the summary with its writer, reader and clean-up in WalletWeatherKit. The app writes the summary after it loads numbers and asks WidgetKit to reload.
- **Three widgets,** each set to a connection when it's added (the one in front to start, changed by editing the widget), and each naming that connection:
  - **Balance:** one account's balance and the month's low. Pick the account when editing the widget.
  - **Next bills:** the next three bills, with names, dates and amounts.
  - **To confirm:** how many lines wait to confirm.
- **Where they go:** Home Screen (small and medium), Lock Screen (rectangular, inline, circular) and StandBy (the small size, with StandBy's own colours).
- **The privacy rules:**
  - Amounts are marked privacy-sensitive, so a locked phone redacts them.
  - They show as •••• when the summary can't be read or the app lock is on. Labels and bill names still show.
  - A connection set to Nothing shows the prompt to turn on Last-known numbers.
  - Tapping a widget opens the page it shows, through the app's `walletweather://` links.
- `docs/privacy.md` and `apps/ios/README.md` say what the summary holds, where it lives and when it's deleted.

**What you have to do:**

- Add each widget from the TestFlight build, then lock the phone and check that amounts show as ••••.
- Turn the app lock on and check again.
- The first signed build with an app group may need Xcode on the Mac to register the group and the extension's App ID once. That would be the one step done in person.

**Done when:** Kit tests cover the summary (written, read, refused while unreadable, deleted on sign-out, on Nothing and on Delete everywhere, no numbers for Nothing). Simulator pictures show each widget size with amounts and with ••••. Your check on the phone passes.

### Phase 2: Reminders worked out on the phone (#319)

**What changes:**

- **Settings → Reminders,** with three switches, each with a one-line footer:
  - **Bill due tomorrow,** with its time.
  - **Balance heading under,** with the amount.
  - **New bank lines to match.**
- **How they're worked out:** each time the summary is written (a page loads, or a background refresh on an unlocked phone), the app replaces its scheduled local notifications.
  - Bills due tomorrow are scheduled for their time the day before.
  - The forecast's first dip under the amount is scheduled ahead of that day.
  - A rise in the To confirm count from bank sync on this iPhone is notified once.
  - Nothing is scheduled for the demo or for a server set to Nothing.
- **What a locked phone shows:** the reminder's text never carries an amount ("Rent is due tomorrow"). The amount shows in the reminder's expanded view, a notification content extension reading the summary. A locked phone keeps the summary closed, and the app lock hides it, so the amount shows only when it's allowed.
- `docs/privacy.md` and `apps/ios/README.md` say what reminders show and where.

**What you have to do:**

- Turn each switch on in the TestFlight build and wait for a reminder.
- Check one on the locked phone (name, no amount) and expanded after unlocking (amount).

**Done when:** Kit tests cover what gets scheduled for each switch (and nothing when it's off, for the demo, or for Nothing). Simulator pictures show the settings page and a delivered reminder. Your check on the phone passes. Built as open questions 1 to 4 settled.

### Phase 3: Open To confirm and What's my balance (#320)

**What changes:**

- **Two App Intents,** offered as App Shortcuts with phrases, so they also work from the Action button and Siri:
  - **Open To confirm** opens the app on the lines waiting to confirm.
  - **What's my balance** answers from the summary of the connection in front, naming it and when its numbers are from. It needs the phone unlocked: with the phone locked, Siri asks to unlock first. With the app lock on, it asks for Face ID before answering. A connection set to Nothing gets an answer that says no numbers are kept.
- `docs/privacy.md` and `apps/ios/README.md` say what Siri can answer and when.

**What you have to do:** run both from Shortcuts, from Siri and from the Action button, with the phone locked and unlocked.

**Done when:** Kit tests cover the answer for each case (unlocked, app lock on, Nothing, the demo). Your check on the phone passes.

### Phase 4: Bills and accounts in the phone's search (#331, split from #320)

**What changes:**

- **Core Spotlight entries** for each bill and account, by name and with no amounts, from the summary. Each opens where it lives in the app.
- **Taking entries out:** a connection's entries go when it's signed out, set to Nothing, or by Delete everywhere, and a bill or account deleted in the app leaves the index on the next write.
- `docs/privacy.md` and `apps/ios/README.md` say what the phone's search holds.

**What you have to do:** search for a bill and an account on your phone and open each. Then sign out of a test server and check its entries are gone.

**Done when:** Kit tests cover what's indexed for each connection kind and what's removed, and that no amount goes in. Your check on the phone passes. Built as open question 5 settled.

### Phase 5: Add a transaction and Mark a bill paid (#332, split from #320)

**What changes:**

- **Two more App Intents,** also offered for the Action button:
  - **Add a transaction** takes an amount, a description and a date.
  - **Mark a bill paid** takes a bill, picked from the summary's bills.
  - Both need the phone unlocked (and Face ID with the app lock on). Both act on the connection in front, through the app's existing calls.
- `docs/privacy.md` and `apps/ios/README.md` change only if what's kept changes.

**What you have to do:** add a transaction and mark a bill paid from Shortcuts and from the Action button. Check that each shows in the app.

**Done when:** Kit tests cover each action against the household on this iPhone and against a test server's answers, and the refusals (locked, Nothing, the demo). Your check on the phone passes. Built as open question 6 settled.
