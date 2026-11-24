# Connections: several servers, this iPhone and the demo

Tracking issue: #303

## Status

| Phase | Issue | State |
| --- | --- | --- |
| 1. The list underneath | #299 | Built in iOS 0.35.0, 2026-11-23; checked on Matthew's phone; released in 1.98.2 (2026-11-24) |
| 2. Connections in Settings | #300 | Built in iOS 0.46.0, 2026-11-23; checked on Matthew's phone; released in 1.98.2 (2026-11-24) |
| 3. This iPhone, the demo, and the lock | #301 | Built in iOS 0.49.0, 2026-11-23; checked on Matthew's phone; released in 1.98.2 (2026-11-24) |
| 4. Quick switch, and what runs behind | #302 | Built in iOS 0.50.0, 2026-11-23; checked on Matthew's phone; released in 1.98.2 (2026-11-24) |

Phase 4 built 2026-11-23 in iOS 0.50.0 (no server change), by an orchestrated run (a Sonnet worker wrote it; this thread checked it): `ConnectionChip` (was `DemoChip`) names the connection in front under the Dashboard's title and at the top of Settings, shown when there's more than one thing to switch between (`ConnectionChipState` in the Kit). A token expired or revoked answer marks that saved connection (`SavedConnection.signInEnded`, optional), shown as ⚠ Sign in again in Connections, the chip's menu and on the chip; a new sign-in clears it. `HouseholdRuns.mayRun` lets the household's backup and bank sync run whatever is in front, without reloading a server's pages, including at launch. Every phase of the plan is now built. Verified: `swift test`, 344 passed (11 new in `ConnectionChipTests`); Duo simulator pictures of the chip, its choices, Connections with an ended sign-in, the chip while locked, and no chip with one connection, on the picture page linked from #302.

Phase 3 built 2026-11-23 in iOS 0.49.0 (no server change), by an orchestrated run (an Opus worker wrote it; this thread checked what shows while locked and closed a one-frame gap): Connections lists the demo (never saved) and On this iPhone (Use on this iPhone, and Restore from an iCloud backup, when there's no household yet); Back to the first screen and the demo's Leave are gone. `DemoChip` replaces `DemoBar`. `LockGate` in the Kit: with the lock on and `lock.showsDemo` on (the default), launch and a minute away bring the demo forward and remember what was in front; every way out while locked goes through `mayLeaveDemo()` (`deviceOwnerAuthentication`, "Open your numbers"). While locked, `ConnectionsVisibility` hides addresses and emails, names a server still called by its address "Server", and keeps connection pages shut; turning the lock or the switch off asks first. `AppSettings.checkingLock` keeps the app-switcher cover up until the decision, so no number shows for a frame. Verified: `swift test`, 333 passed (new `LockGateTests`); Duo simulator pictures from `WW_DEBUG_LOCKED_DEMO=1` with `WW_DEBUG_CONNECTIONS=sample`: the Dashboard, the chip's choices, Connections and Settings locked, and Connections unlocked, on the picture page linked from #301. Not checked: Face ID and the passcode, and coming back after a minute, which need Matthew's phone.

Phase 2 built 2026-11-23 in iOS 0.46.0 (no server change), by an orchestrated run (an Opus worker wrote it; this thread checked it and fixed three things): the connection card opens Connections (a new Settings page), listing every saved connection with a tick on the one in front; `AppModel.switchTo` brings one forward without ending a token or deleting kept numbers; `signOut(of:)` ends one connection's token with its own client and removes only it, bringing the most recently used forward when it was in front. `SavedConnection.signInTarget` decides renew or add from the server and the person (`account`, filled from `/api/me`); a person not yet known means add. Add a server and Sign in again open the sign-in screen as a sheet (`ConnectView(inSheet:)`); links add or renew instead of replacing. Fixed in this thread: renewing a connection whose person wasn't known now clears its kept numbers; the household's row reads "Your household, with no server"; a row's detail wraps instead of cutting the email. Verified: `swift test`, 299 passed (new in `ConnectionStoreTests` and `SettingsLayoutTests`); Duo simulator pictures of Connections closed, open and in Sepia from a `WW_DEBUG_CONNECTIONS=sample` launch (in memory only, never the Keychain), on the picture page linked from #300. Not checked: signing in to a second real server, switching, and signing out of one, which need Matthew's phone.

Phase 1 built 2026-11-23 in iOS 0.35.0 (0f062b5; no server change), by an orchestrated run (an Opus worker wrote it; this thread checked it): `ConnectionStore` in the Kit keeps one Keychain item per connection (`connection.<id>`, the same service and protection as the single item had) and the id of the one in front in the app's settings (`connections.active`). The single sign-in is carried over once: written as the first connection with its keep choice and saved web theme, read back, its kept numbers moved into `Kept/<id>/`, and only then removed with `keep.choice`; if the copy can't be written the old item stays in use and the next start tries again. Each page's account is remembered per connection in each window (`<key>.byConnection` beside the three scene-storage keys). Until phase 2, a new sign-in still replaces the one before. Verified: `swift test`, 230 passed (16 new in `ConnectionStoreTests`: the carry-over with and without Cloudflare, the household on this iPhone, nothing saved, a failed write, add, remove and switch, kept numbers per connection, the Keychain attributes); on the Duo simulator the new build launched over an install that held the household on this iPhone and opened it as before, twice, and the demo still opened. Not checked: a server sign-in with kept numbers carrying over, which needs Matthew's phone.

Planned 2026-11-23 from a design review of iOS 0.34.0, asked for as "can you perform a design review of the ios app, looking for ux inconsistancies and suggest more features for the duo. please also take a look at overhauling settings and I would also like a plan for the ability to connect to multiple servers as well as running local and even accessing the demo (from the settings)". The review ran the app in the demo on the Duo simulator in every pose and at a large text size, made 27 findings (R1 to R27) and twelve ideas (F1 to F12), and drew today beside the proposal for each ([the review page](https://claude.ai/artifact/YanSV7o5FqX9WC6SdzZkyj), private to Matthew). The choices made in four rounds of questions are on the [decision page](../docs/dev/decisions/ios-review.md).

Sessions: may span — four phases; phase 1 changes where the sign-in is kept, so each ends with a check on Matthew's phone.

## Agents and tools

| Phase | Main session | Subagents | Why |
| --- | --- | --- | --- |
| 1. The list underneath | Opus | Sonnet: the Kit tests | It moves a sign-in that's already on people's phones, in the Keychain, and what the app keeps changes shape. |
| 2. Connections in Settings | Opus | Sonnet: the Kit tests and the pictures | Sign-in, sign-out and links each change what they do to the other servers. |
| 3. This iPhone, the demo, and the lock | Opus | Sonnet: the Kit tests and the pictures | The lock is a privacy decision, and the demo becomes what a locked app shows. |
| 4. Quick switch, and what runs behind | Sonnet | Sonnet: the Kit tests and the pictures | A menu on a pattern phase 2 set, and two guards loosened. |

## Open questions

1. **May each connection have its own colour?** A tint on the chip so two servers are hard to mix up. Blocks nothing. Left until switching proves confusing.

## The plan

**Goal:** The iPhone app keeps several connections at once: any number of servers, each with its own sign-in, the household on this iPhone, and the demo. You switch from Settings or from the Dashboard's title without signing out of anything. With the lock on, the app opens in the demo.

**Decided 2026-11-23** ([decision page](../docs/dev/decisions/ios-review.md)):

- **It covers servers, this iPhone and the demo, with one in front at a time.**
- **One household on this iPhone, one lock for the whole app,** and the household's iCloud Drive backup and bank sync keep running while a server is in front.
- **A different connection in each Duo window is not planned.** It is looked at again after phase 4.
- **The chip that says where you are** shows under the Dashboard's title and at the top of Settings.
- **With the lock on, the app opens in the demo** and stays there until Face ID or Touch ID is given; leaving the demo for a real connection is what asks for it.
- **"When locked, show the demo" is a switch** in Privacy & lock, on by default; off brings back today's lock screen. The chip reads "Demo" and is the way out. The phone's passcode works when Face ID fails, as with the lock today.

**Out of scope:**

- Several households on one iPhone: there is one store, one iCloud zone and one backup folder.
- A different connection in each Duo window.
- Any server change. The server already gives each device its own token and lists them in Settings → API tokens.
- Totals across connections (#329) and moving a household between connections inside the app (#328): their own issues.
- The first screen for a new install, which stays as it is.

**What's there today:**

- One `Connection` (address, token, Cloudflare sign-in) in one Keychain item: service `net.iptater.walletweather`, account `connection`, this device only, never iCloud (`apps/ios/WalletWeather/Keychain.swift`).
- `AppModel` holds that one connection. Signing out deletes it and every kept number (`KeptResponses.standard`, one `Kept` folder); `keep.choice` and the saved web theme (`appearance.web`) are one value each.
- Each page keeps its account per window (`forecast.account`, `bills.account`, `calendar.account`). CSV columns are already kept per server.
- The household on this iPhone answers at `this-iphone.walletweather.invalid` (`LocalServer`); the demo at `demo.walletweather.invalid` (`Demo`), and is never saved.
- Three exits lead to the first screen: Sign out, "Back to the first screen" (`AppModel.leaveLocal`) and the demo bar's Leave (`AppModel.leaveDemo`).
- A link from the web app's Settings signs out of the server you're in before connecting to the new one (`AppModel.connect(link:)`: "This replaces the server you're signed in to").
- The household's backup and bank sync run only while it is the connection in front (`AppModel.backgroundBankSync`, and the scene-phase handler in `WalletWeatherApp.swift`).
- The lock is a full screen, `LockView`, over the app while `AppSettings.locked` is true.
- `Plans/ios-app.md` listed "more than one server at a time" as out of scope.

**How every phase is checked:** `swift test` passes, with Kit tests for the store, the move from today's sign-in, switching, signing out of one, and links. The existing demo and on-this-iPhone tests pass unchanged. Duo simulator pictures are linked from the phase issue. Each phase ends with numbered "How to test" steps on Matthew's phone, since a simulator has no second server and no Face ID to script.

**Versions:** each phase bumps the iOS version and adds its changelog entries under `[Unreleased]`. `apps/ios/README.md` ("What's kept on the phone") and the privacy policy change with phase 1. No server, web or schema change.

### Phase 1: The list underneath

From the review: The ground for R12 and R24.

**What changes:**

- **Several saved connections** in the Kit: for each, an id, what kind it is, a name, the server's address, when it was added and last used.
- **Secrets stay in the Keychain,** one item per connection, with today's protection (this device only, never iCloud).
- **Today's sign-in is carried over:** read once, written as the first connection, and only then removed. Nobody is signed out by updating.
- **Kept per connection:** last-known numbers (a folder each, deleted with its connection), Keep on this iPhone, the saved web theme, and each page's account.
- `AppModel` reads the connection in front from the store. Nothing looks different yet.

**What you have to do:** Update your phone and check you're still signed in, with your kept numbers if you keep them.

**Done when:**

- Kit tests: the move from today's item (with and without a Cloudflare sign-in, the household on this iPhone, and nothing saved); add, remove and switch; kept numbers per connection, gone with it; the Keychain attributes unchanged.
- `LocalTests` and `DemoTests` pass unchanged.
- On the simulator, an install signed in before the change opens signed in after it.
- The README's "What's kept on the phone" and the privacy policy describe a sign-in per server.

**Depends on:** Nothing. It can be built before the Settings plan.

### Phase 2: Connections in Settings

From the review: R12 (for servers).

**What changes:**

- **The connection card** at the top of Settings opens **Connections**: the list, with a tick on the one in front. Tap one to switch.
- **Add a server** opens today's sign-in screen, with all its ways, as a sheet.
- **A page per connection:** its name (yours to change), who's signed in, Cloudflare, Keep on this iPhone, Open the web app, and Sign out of this one.
- **Signing out** ends that server's token and removes only its sign-in and its kept numbers.
- **A link from the web app's Settings, or its QR code, adds a server,** or renews the sign-in of one already in the list. It no longer replaces the one you're in.
- A connection whose sign-in has ended says "Sign in again".

**What you have to do:** Sign in to two servers on your phone and switch between them. Turn one off and switch to it and back.

**Done when:**

- Kit tests for links: a new server, the same server and person, the same server and another person.
- Pictures of the card, the list, a connection's page and Add a server are linked from the issue.
- Numbered "How to test" steps for two servers are on the issue.

**Depends on:** Phase 1, and #294 for the card's place in Settings.

### Phase 3: This iPhone, the demo, and the lock

From the review: R12, R24, and the note of 2026-11-23 on the lock.

**What changes:**

- **On this iPhone and the demo are rows in the list.** "Back to the first screen" and the demo's Leave go: switching replaces them, and leaving the demo returns to where you were.
- **Add a connection** offers Use on this iPhone when there's no household yet, and Restore from an iCloud backup.
- **The demo's full-width bar becomes the chip** (R24).
- **With the lock on, the app opens in the demo,** and returns to it after a minute away (the clock the lock uses today). Choosing a real connection asks for Face ID or Touch ID, with the passcode behind it, then opens it.
- **"When locked, show the demo"** is a switch in Privacy & lock, on by default. Off, a locked app shows today's lock screen.
- The app-switcher cover and the first screen for a new install don't change.

**What you have to do:** Turn the lock on and close the app. Open it: the demo. Pick Home: Face ID. Leave for a minute and come back: the demo again. Then try the switch off.

**Done when:**

- Kit tests for the lock: locked means the demo is in front; unlocking opens the connection chosen; the minute away.
- `DemoTests` opens every page Settings links to.
- Pictures of a locked launch, the chip's menu and the switch are linked from the issue. Face ID itself is checked on Matthew's phone.

**Depends on:** Phase 2, and #293 (the demo must not dead-end, since a locked app will show it).

### Phase 4: Quick switch, and what runs behind

From the review: The chip, decided 2026-11-23.

**What changes:**

- **The chip under the Dashboard's title** names the connection in front and opens the list to switch, with Manage connections… at the end. With one connection there is no chip.
- **The household on this iPhone keeps working behind a server:** its iCloud Drive backup and its bank sync run when they're due, whichever connection is in front.
- The chip marks a connection in front whose sign-in has ended.

**What you have to do:** With a server in front, check the iPhone household's backup still ran today (Files → iCloud Drive → WalletWeather).

**Done when:**

- Kit tests for when the backup and the bank sync may run.
- Pictures of the chip and its menu, closed and open, are linked from the issue.

**Depends on:** Phase 3.
