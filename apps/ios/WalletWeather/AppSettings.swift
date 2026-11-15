import LocalAuthentication
import Observation
import SwiftUI

/// The app's own settings, kept on this phone in its preferences (not the
/// Keychain: they hold no money data): the look, and the app lock.
///
/// The lock (decided 2026-11-14 and 2026-11-15): offered once, at first
/// sign-in or after updating for someone already signed in; changeable in
/// More. When on, it asks for Face ID or Touch ID (or the passcode) when the
/// app starts and when it comes back after a minute or more away.
@MainActor @Observable
final class AppSettings {
    static let lockAfter: TimeInterval = 60

    var look: Look {
        didSet {
            Palette.look = look
            defaults.set(look.rawValue, forKey: Keys.look)
        }
    }

    private(set) var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: Keys.lockEnabled) }
    }

    /// Whether the lock has been offered (once per install).
    var lockOffered: Bool {
        didSet { defaults.set(lockOffered, forKey: Keys.lockOffered) }
    }

    /// The app is locked: the lock screen covers it until unlocked.
    private(set) var locked: Bool
    private var leftAt: Date?
    private let defaults: UserDefaults

    private enum Keys {
        static let look = "appearance"
        static let lockEnabled = "lock.enabled"
        static let lockOffered = "lock.offered"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = Look(rawValue: defaults.string(forKey: Keys.look) ?? "") ?? .system
        look = saved
        Palette.look = saved
        let enabled = defaults.bool(forKey: Keys.lockEnabled)
        lockEnabled = enabled
        lockOffered = defaults.bool(forKey: Keys.lockOffered)
        // Locked from a fresh start, unless launched for screenshots.
        locked = enabled && AppModel.debugSetting("WW_DEBUG_SERVER") == nil
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
    func setLock(_ on: Bool) async {
        lockOffered = true
        if !on {
            lockEnabled = false
            return
        }
        if await authenticate(reason: "Turn on the lock for WalletWeather") { lockEnabled = true }
    }

    func unlock() async {
        if await authenticate(reason: "Unlock WalletWeather") { locked = false }
    }

    /// Follows the app in and out of the background: away a minute or more
    /// with the lock on, it locks.
    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            if leftAt == nil { leftAt = .now }
        case .active:
            if lockEnabled, let leftAt, Date.now.timeIntervalSince(leftAt) >= Self.lockAfter { locked = true }
            leftAt = nil
        default:
            break
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
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Palette.accent)
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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill").font(.system(size: 52)).symbolRenderingMode(.multicolor)
            Text("WalletWeather").font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PageBackground().ignoresSafeArea())
        .accessibilityHidden(true)
    }
}
