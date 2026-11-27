import LocalAuthentication
import Observation
import SwiftUI
import WalletWeatherKit
import WidgetKit

/// The app's own settings, kept on this phone in its preferences (not the
/// Keychain: they hold no money data): the look (and, for Match the web app,
/// the name of the theme saved on the server), and the app lock.
///
/// The lock (decided 2026-11-14 and 2026-11-15): offered once, at first
/// sign-in or after updating for someone already signed in; changeable in
/// Settings. When on, it asks for Face ID or Touch ID (or the passcode) when the
/// app starts and when it comes back after a minute or more away.
///
/// With "When locked, show the demo" on as well (#301, on by default), the
/// app opens in the demo instead, and goes back to it after a minute away;
/// a real connection then asks first. `LockGate`, in the Kit, holds the
/// rules; this keeps one and asks Face ID.
@MainActor @Observable
final class AppSettings {
    static let lockAfter: TimeInterval = LockGate.lockAfter

    var look: Look {
        didSet {
            defaults.set(look.rawValue, forKey: Keys.look)
            Palette.look = shownLook
            start.done.insert(.look)
        }
    }

    /// The pages in the tab bar beside Settings and Search, in order (#158).
    /// Any change ticks Getting started's tab bar task (#175).
    var tabs: [TabPage] {
        didSet {
            defaults.set(TabPage.stored(tabs), forKey: Keys.tabs)
            start.done.insert(.tabBar)
        }
    }

    /// The Getting started tasks this phone offers (#177): the lock only
    /// with Face ID, Touch ID or Optic ID set up.
    var startTasks: [StartTask] {
        StartTask.allCases.filter { $0 != .lock || biometryName != nil }
    }

    /// Tasks done before the card knew of them: the lock on, a look chosen.
    var startAlsoDone: Set<StartTask> {
        var done: Set<StartTask> = []
        if lockEnabled { done.insert(.lock) }
        if look != .system { done.insert(.look) }
        return done
    }

    var showsStartCard: Bool { start.showsCard(among: startTasks, alsoDone: startAlsoDone) }

    /// The Getting started card on the Dashboard (#175): kept per phone.
    var start: GettingStarted {
        didSet {
            guard start != oldValue else { return }
            defaults.set(GettingStarted.stored(start.done), forKey: Keys.startDone)
            defaults.set(start.dismissed, forKey: Keys.startDismissed)
        }
    }

    /// The theme saved in the web app, for Match the web app: kept here so
    /// it still applies when the app opens without a connection.
    var serverTheme: String? {
        didSet {
            guard serverTheme != oldValue else { return }
            defaults.set(serverTheme, forKey: Keys.serverTheme)
            Palette.look = shownLook
        }
    }

    /// Themes the person made (#297), in the order they were made: kept in
    /// iCloud's key-value store and mirrored here (`ThemeCloud`). Changed
    /// only through `saveTheme` and `deleteTheme`, or by iCloud.
    private(set) var customThemes: [CustomTheme]
    /// Nil while `WW_DEBUG_CUSTOM_THEMES=sample` keeps sample themes in
    /// memory only.
    private var themeCloud: ThemeCloud?

    /// Adds a theme, or replaces the one with its id; the look follows when
    /// that theme is the one in use.
    func saveTheme(_ theme: CustomTheme) {
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            customThemes.append(theme)
        }
        themeCloud?.save(customThemes)
        if case let .custom(inUse) = look, inUse.id == theme.id { look = .custom(theme) }
    }

    /// Deletes a theme; when it was in use, the app goes back to Match this
    /// iPhone.
    func deleteTheme(_ id: UUID) {
        customThemes.removeAll { $0.id == id }
        themeCloud?.save(customThemes)
        if case let .custom(inUse) = look, inUse.id == id { look = .system }
    }

    /// iCloud brought the themes as another iPhone left them: the look in
    /// use takes its new colours, falls back to Match this iPhone when its
    /// theme was deleted there, or comes back when the theme it was saved
    /// with has only now arrived.
    private func themesArrived(_ themes: [CustomTheme]) {
        customThemes = themes
        if case let .custom(inUse) = look {
            let now = themes.first { $0.id == inUse.id }
            if now != inUse { look = now.map(Look.custom) ?? .system }
        } else if look == .system, let saved = defaults.string(forKey: Keys.look),
                  saved.hasPrefix(CustomTheme.prefix), let back = Look(rawValue: saved, themes: themes) {
            look = back
        }
    }

    /// The look on screen: Match the web app resolved to the server's theme.
    var shownLook: Look {
        look == .web ? .matching(ServerTheme(serverTheme)) : look
    }

    /// Settings → Dates & display → Date format (#296): Follow the web app
    /// (the default), Nov 12 or 2026-11-12.
    var dateChoice: DateFormatChoice {
        didSet {
            defaults.set(dateChoice.rawValue, forKey: Keys.dateFormat)
            applyDateStyle()
        }
    }

    /// The web app's `date_format`, from `/api/me` of the server in front:
    /// kept here so it still applies when the app opens without a
    /// connection. Nil with no server (this iPhone alone, the demo).
    var serverDateFormat: String? {
        didSet {
            guard serverDateFormat != oldValue else { return }
            defaults.set(serverDateFormat, forKey: Keys.serverDateFormat)
            applyDateStyle()
        }
    }

    /// How dates are written now. Debug only: `WW_DEBUG_DATES=iso|short`
    /// forces it, for screenshots.
    var dateStyle: DateStyle {
        if let forced = AppModel.debugSetting("WW_DEBUG_DATES").flatMap(DateStyle.init(rawValue:)) { return forced }
        return dateChoice.style(server: serverDateFormat)
    }

    /// Sets the style every `LocalDay.short` reads; the root re-reads it by
    /// rebuilding the pages when `dateStyle` changes.
    private func applyDateStyle() { DateDisplay.style = dateStyle }

    /// Pages follow the same account (#317): an account picked on Forecast,
    /// Bills & income or Calendar is shown on the other two. On unless
    /// turned off; a phone that never set it reads as on.
    var pagesFollowAccount: Bool {
        didSet { defaults.set(pagesFollowAccount, forKey: Keys.followAccount) }
    }

    private(set) var lockEnabled: Bool {
        didSet {
            defaults.set(lockEnabled, forKey: Keys.lockEnabled)
            gate.lockOn = lockEnabled || debugLockedDemo
            Self.copyLockForWidgets(lockEnabled)
        }
    }

    /// The widgets hide every amount while the app's lock is on, even on an
    /// unlocked phone (#318, decided 2026-11-23): the setting is copied into
    /// the app group, and they draw again.
    private static func copyLockForWidgets(_ on: Bool) {
        guard OutsideSettings.shared.lockOn != on else { return }
        OutsideSettings.shared.lockOn = on
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Settings → Privacy & lock → When locked, show the demo (#301): on
    /// unless turned off; a phone that never set it reads as on.
    private(set) var lockShowsDemo: Bool {
        didSet {
            defaults.set(lockShowsDemo, forKey: Keys.lockShowsDemo)
            gate.showsDemo = lockShowsDemo
        }
    }

    /// Whether the lock has been offered (once per install).
    var lockOffered: Bool {
        didSet { defaults.set(lockOffered, forKey: Keys.lockOffered) }
    }

    /// The app is locked: the lock screen covers it until unlocked.
    private(set) var locked: Bool
    /// Set when the app leaves with the lock on, and cleared once the lock
    /// has decided what comes back (#301): until then the app-switcher cover
    /// stays up, so no number shows for a frame before the demo or the lock
    /// screen takes over.
    var checkingLock = false
    /// When the lock falls due, and whether the app is locked in the demo.
    private(set) var gate: LockGate
    /// The lock sent the app to the demo and nobody has unlocked since: a
    /// real connection asks first, and Connections hides their details.
    var lockedInDemo: Bool { gate.lockedInDemo }
    /// Debug only: `WW_DEBUG_LOCKED_DEMO=1` starts as if the lock had just
    /// sent the app to the demo, whether or not the lock is on.
    private let debugLockedDemo: Bool
    private var leftAt: Date?
    private let defaults: UserDefaults

    private enum Keys {
        static let look = "appearance"
        static let serverTheme = "appearance.web"
        static let tabs = "tabs"
        static let startDone = "start.done"
        static let startDismissed = "start.dismissed"
        static let lockEnabled = "lock.enabled"
        static let lockOffered = "lock.offered"
        static let lockShowsDemo = "lock.showsDemo"
        static let followAccount = "pages.followAccount"
        static let dateFormat = "dates.format"
        static let serverDateFormat = "dates.server"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Debug only: `WW_DEBUG_CUSTOM_THEMES=sample` puts two sample themes
        // in memory, never in iCloud or the preferences (#297).
        let themes: [CustomTheme]
        if AppModel.debugSetting("WW_DEBUG_CUSTOM_THEMES") == "sample" {
            themes = CustomThemeStore.samples
            themeCloud = nil
        } else {
            let cloud = ThemeCloud(defaults: defaults)
            themes = cloud.load()
            themeCloud = cloud
        }
        customThemes = themes
        // Debug only: `WW_DEBUG_LOOK=<look>` for screenshots in each look;
        // `custom-light` and `custom-dark` name the sample themes.
        let debugName = AppModel.debugSetting("WW_DEBUG_LOOK")
        let debug = CustomThemeStore.sample(named: debugName).map(Look.custom)
            ?? debugName.flatMap { Look(rawValue: $0, themes: themes) }
        // A saved look that's no longer there falls back to Match this iPhone.
        let saved = debug ?? Look(rawValue: defaults.string(forKey: Keys.look) ?? "", themes: themes) ?? .system
        look = saved
        serverTheme = defaults.string(forKey: Keys.serverTheme)
        // Debug only: `WW_DEBUG_TABS=forecast,netWorth` for screenshots.
        tabs = TabPage.bar(from: AppModel.debugSetting("WW_DEBUG_TABS") ?? defaults.string(forKey: Keys.tabs))
        // Debug only: `WW_DEBUG_START=fresh` (or `tour`, which also opens the
        // guided tab bar sheet) shows Getting started as on a new phone.
        start = AppModel.debugSetting("WW_DEBUG_START") != nil
            ? GettingStarted()
            : GettingStarted(done: GettingStarted.done(from: defaults.string(forKey: Keys.startDone)),
                             dismissed: defaults.bool(forKey: Keys.startDismissed))
        let enabled = defaults.bool(forKey: Keys.lockEnabled)
        lockEnabled = enabled
        Self.copyLockForWidgets(enabled)
        let showsDemo = defaults.object(forKey: Keys.lockShowsDemo) as? Bool ?? true
        lockShowsDemo = showsDemo
        let debugLockedDemo = AppModel.debugSetting("WW_DEBUG_LOCKED_DEMO") == "1"
        self.debugLockedDemo = debugLockedDemo
        gate = LockGate(lockOn: enabled || debugLockedDemo, showsDemo: showsDemo || debugLockedDemo)
        lockOffered = defaults.bool(forKey: Keys.lockOffered)
        pagesFollowAccount = defaults.object(forKey: Keys.followAccount) as? Bool ?? true
        dateChoice = defaults.string(forKey: Keys.dateFormat).flatMap(DateFormatChoice.init(rawValue:)) ?? .follow
        serverDateFormat = defaults.string(forKey: Keys.serverDateFormat)
        // Locked from a fresh start, unless launched for screenshots. With
        // the demo shown when locked, the start decides instead
        // (`lockAtLaunch`), once it knows what's in front.
        locked = enabled && !showsDemo && !debugLockedDemo && AppModel.debugSetting("WW_DEBUG_SERVER") == nil
        Palette.look = shownLook
        DateDisplay.style = dateStyle
        themeCloud?.arrived = { [weak self] in self?.themesArrived($0) }
    }

    // MARK: - The lock

    /// "Face ID", "Touch ID" or "Optic ID"; nil when the phone has none set
    /// up (the lock isn't offered then).
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    /// Whether the lock should be offered now: never offered, and the phone
    /// can do it. Not in a screenshot launch.
    var shouldOfferLock: Bool {
        !lockOffered && !lockEnabled && biometryName != nil && AppModel.debugSetting("WW_DEBUG_SERVER") == nil
    }

    /// Turns the lock on after one successful check, so it can't be left on
    /// with a face or finger that doesn't work; off at once.
    /// Locked in the demo, turning it off asks first (#301): whoever holds
    /// the phone could otherwise open the numbers that way.
    func setLock(_ on: Bool) async {
        lockOffered = true
        if !on {
            if gate.changingTheLockNeedsAuthentication {
                guard await authenticate(reason: "Turn off the lock") else { return }
            }
            lockEnabled = false
            gate.turnedOff()
            return
        }
        if await authenticate(reason: "Turn on the lock for WalletWeather") {
            lockEnabled = true
            start.done.insert(.lock)
        }
    }

    /// When locked, show the demo (#301): on at once; off asks first while
    /// locked in the demo, which it then leaves unlocked.
    func setLockShowsDemo(_ on: Bool) async {
        if !on, gate.changingTheLockNeedsAuthentication {
            guard await authenticate(reason: "Turn off When locked, show the demo") else { return }
            gate.turnedOff()
        }
        lockShowsDemo = on
    }

    func unlock() async {
        if await authenticate(reason: "Unlock WalletWeather") { locked = false }
    }

    /// Locked in the demo, asks for Face ID, Touch ID or the passcode before
    /// a real connection opens (#301); true when it may. Unlocked, it asks
    /// for nothing.
    func mayOpenYourNumbers() async -> Bool {
        guard gate.leavingNeedsAuthentication else { return true }
        guard await authenticate(reason: "Open your numbers") else { return false }
        gate.authenticated()
        return true
    }

    /// The start, once it knows what's in front: with the demo shown when
    /// locked, the lock falls due now. Otherwise the lock screen was
    /// decided at init, as before #301.
    func lockAtLaunch(front: LockGate.Front) -> LockGate.Decision {
        guard lockShowsDemo || debugLockedDemo, gate.lockOn,
              debugLockedDemo || AppModel.debugSetting("WW_DEBUG_SERVER") == nil else { return LockGate.Decision(show: .asItIs) }
        return lockFallsDue(away: nil, front: front, beforeDemo: nil)
    }

    /// Back after `away` seconds with `front` in front: what the lock shows.
    /// The lock screen is set here; the demo is the caller's to bring
    /// forward.
    func lockFallsDue(away: TimeInterval?, front: LockGate.Front, beforeDemo: LockGate.Front?) -> LockGate.Decision {
        let decision = gate.comeBack(away: away, front: front, beforeDemo: beforeDemo)
        if decision.show == .lockScreen { locked = true }
        return decision
    }

    /// Follows the app in and out of the background. Coming back to the
    /// front, returns how long it was away, for `lockFallsDue`.
    func scenePhaseChanged(to phase: ScenePhase) -> TimeInterval? {
        switch phase {
        case .background:
            if leftAt == nil { leftAt = .now }
            if lockEnabled { checkingLock = true }
            return nil
        case .active:
            defer { leftAt = nil }
            return leftAt.map { Date.now.timeIntervalSince($0) }
        default:
            return nil
        }
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Over the app while it's locked: the name and an Unlock button, which
/// asks at once when it appears.
struct LockView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 44
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: symbolSize)).foregroundStyle(Palette.accent)
            Text("WalletWeather is locked").font(.title2.bold())
            Button {
                Task { await settings.unlock() }
            } label: {
                Label("Unlock with \(settings.biometryName ?? "passcode")", systemImage: "faceid")
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PageBackground().ignoresSafeArea())
        .task { await settings.unlock() }
    }
}

/// Over the app whenever it isn't in front (the app switcher, Control
/// Centre, a Face ID prompt), so the numbers don't show in the app
/// switcher's snapshot.
struct PrivacyCover: View {
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 52
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill").font(.system(size: symbolSize)).symbolRenderingMode(.multicolor)
            Text("WalletWeather").font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PageBackground().ignoresSafeArea())
        .accessibilityHidden(true)
    }
}
