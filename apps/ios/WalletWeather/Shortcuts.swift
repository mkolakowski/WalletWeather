import AppIntents
import LocalAuthentication
import WalletWeatherKit

// Open To confirm and What's my balance (Plans/outside-the-app.md, phase 3,
// #320), offered as App Shortcuts so they also work from Siri, Spotlight and
// the Action button. What each does is decided in WalletWeatherKit
// (ShortcutAnswers.swift), where the tests check the privacy rules. Neither
// reaches a server: they read the summary the app wrote for the widgets.
//
// The intents' type names are their identifiers in people's shortcuts and on
// the Action button: never rename them.

/// Opens the app on the lines waiting to confirm, on the connection in front,
/// as the To confirm widget does. The app's own lock still asks first.
nonisolated struct OpenToConfirmIntent: AppIntent {
    static let title: LocalizedStringResource = "Open To confirm"
    static let description = IntentDescription("Opens WalletWeather on the lines waiting to confirm, on the connection in front.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        let front = OutsideSettings.shared.front
        let read = front.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        let target = ToConfirmTarget.decide(front: front, read: read)
        ShortcutOpen.send(WidgetOpen(page: .toConfirm, connection: target.connection, account: target.account))
        return .result()
    }
}

/// Tells each account's balance on the connection in front, naming it and
/// when its numbers are from. Only with the phone unlocked (Siri asks to
/// unlock first), and after Face ID while the app's lock is on.
nonisolated struct BalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "What's my balance"
    static let description = IntentDescription(
        "Tells the balance of each account on the connection in front, and when the numbers are from. Needs your iPhone unlocked, and Face ID while WalletWeather's lock is on.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = OutsideSettings.shared
        let front = settings.front
        let read = front.flatMap { SummaryStore.shared?.read($0) } ?? .missing
        var answer = BalanceAnswer.decide(front: front, read: read, lockOn: settings.lockOn, unlocked: false)
        if answer == .appLocked, await Self.unlock() {
            answer = BalanceAnswer.decide(front: front, read: read, lockOn: true, unlocked: true)
        }
        return .result(dialog: IntentDialog(stringLiteral: answer.text()))
    }

    /// Face ID (or the passcode), as the app's own lock asks.
    private static func unlock() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Hear your balance")
        } catch {
            return false
        }
    }
}

/// The phrases Siri knows, and the actions Shortcuts and the Action button
/// offer without setting anything up.
nonisolated struct WalletWeatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BalanceIntent(),
                    phrases: ["What's my balance in \(.applicationName)",
                              "What's my \(.applicationName) balance",
                              "Ask \(.applicationName) for my balance"],
                    shortTitle: "What's my balance",
                    systemImageName: "dollarsign.circle")
        AppShortcut(intent: OpenToConfirmIntent(),
                    phrases: ["Open To confirm in \(.applicationName)",
                              "Show what to confirm in \(.applicationName)"],
                    shortTitle: "Open To confirm",
                    systemImageName: "checklist")
    }
}

/// Hands Open To confirm to the app's windows, as a widget's tap does. When
/// the shortcut launches the app, it can run before the windows are ready:
/// it waits here until they are.
enum ShortcutOpen {
    static var handler: ((WidgetOpen) -> Void)? {
        didSet {
            guard let handler, let waiting else { return }
            self.waiting = nil
            handler(waiting)
        }
    }

    private static var waiting: WidgetOpen?

    static func send(_ open: WidgetOpen) {
        if let handler { handler(open) } else { waiting = open }
    }
}
