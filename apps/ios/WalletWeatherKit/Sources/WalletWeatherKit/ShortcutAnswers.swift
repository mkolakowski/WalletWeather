import Foundation

// Open To confirm and What's my balance (Plans/outside-the-app.md, phase 3,
// #320): two App Intents in the app, offered as App Shortcuts so they also
// work from Siri and the Action button. What they do is worked out here, with
// no App Intents, so the tests can check the privacy rules.
//
// Decided 2026-11-23 (docs/dev/decisions/ios-review.md): amounts never show
// outside the app on a locked phone (the intent needs the phone unlocked, and
// the summary stays closed while it's locked), the app's own lock hides them
// even on an unlocked phone until Face ID passes, and a server set to keep
// Nothing has no numbers to tell. The demo has no summary, so nothing to tell.

/// Where Open To confirm lands: the connection in front, at the account with
/// the most lines waiting (as the To confirm widget opens it).
public struct ToConfirmTarget: Equatable, Sendable {
    public let connection: UUID?
    public let account: Int?

    public init(connection: UUID?, account: Int?) {
        self.connection = connection
        self.account = account
    }

    /// `read` is the summary of `front`. Without one that holds numbers, the
    /// app opens on the connection's Forecast at the account it last showed.
    public static func decide(front: UUID?, read: SummaryRead) -> ToConfirmTarget {
        guard let front else { return ToConfirmTarget(connection: nil, account: nil) }
        if case let .found(summary) = read, summary.keepsNumbers {
            return ToConfirmTarget(connection: front, account: summary.toConfirmAccount)
        }
        return ToConfirmTarget(connection: front, account: nil)
    }
}

/// What's my balance: the answer Siri or Shortcuts gives, from the summary of
/// the connection in front. It never reaches a server.
public enum BalanceAnswer: Equatable, Sendable {
    /// No saved connection (nothing set up, or only the demo used): the demo
    /// has no summary.
    case noConnection
    /// A saved connection with no summary yet, or one that's gone.
    case notLoaded
    /// The summary can't be read: the phone is locked.
    case phoneLocked
    /// The app's own lock is on and wasn't unlocked: no amounts.
    case appLocked
    /// A server set to keep Nothing: no numbers are kept on the phone.
    case keepsNothing(name: String)
    /// A connection with numbers kept but no accounts yet.
    case noAccounts(name: String)
    /// Each account's balance, with the connection's name and when the
    /// numbers are from.
    case balances(ConnectionSummary)

    /// `unlocked` is true once Face ID (or the passcode) has passed for the
    /// app's lock. The intent decides first with `unlocked` false; only an
    /// answer of `appLocked` asks for Face ID, and then decides again.
    public static func decide(front: UUID?, read: SummaryRead, lockOn: Bool, unlocked: Bool) -> BalanceAnswer {
        guard front != nil else { return .noConnection }
        switch read {
        case .missing: return .notLoaded
        case .unreadable: return .phoneLocked
        case let .found(summary):
            // Names show with the lock on (as on the widgets); amounts don't.
            guard summary.keepsNumbers else { return .keepsNothing(name: summary.name) }
            guard summary.accounts.isEmpty == false else { return .noAccounts(name: summary.name) }
            if lockOn && !unlocked { return .appLocked }
            return .balances(summary)
        }
    }

    /// What Siri says and shows.
    public func text(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .noConnection:
            return "WalletWeather has no saved connection yet, and the demo's numbers aren't kept for Siri. Connect to your server or start a household on this iPhone first."
        case .notLoaded:
            return "WalletWeather has no numbers for Siri yet. Open the app once so it can load them."
        case .phoneLocked:
            return "Unlock your iPhone to hear your balance."
        case .appLocked:
            return "WalletWeather is locked. Unlock it with Face ID or your passcode to hear your balance."
        case let .keepsNothing(name):
            return "\(name) keeps no numbers on this iPhone, so there's no balance to tell. Turn on Last-known numbers for it in WalletWeather to hear it here."
        case let .noAccounts(name):
            return "\(name) has no accounts yet."
        case let .balances(summary):
            let each = summary.accounts.map { "\($0.name) has \($0.balance.formatted)" }
            return "In \(summary.name), \(Self.asOf(summary.madeAt, now: now, calendar: calendar)): \(Self.join(each))."
        }
    }

    /// When the numbers are from, written to be read aloud: "as of just
    /// now", "as of 12 minutes ago", "as of 2 hours ago" (within today), "as
    /// of yesterday", then the date as the app writes dates ("as of Nov 22").
    static func asOf(_ date: Date, now: Date, calendar: Calendar) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "as of just now" }
        if calendar.isDate(date, inSameDayAs: now) {
            let minutes = Int(seconds / 60)
            if minutes < 60 { return minutes == 1 ? "as of 1 minute ago" : "as of \(minutes) minutes ago" }
            let hours = minutes / 60
            return hours == 1 ? "as of 1 hour ago" : "as of \(hours) hours ago"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "as of yesterday"
        }
        return "as of \(LocalDay.display(of: date, now: now))"
    }

    /// "A", "A and B", "A, B and C".
    static func join(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}
