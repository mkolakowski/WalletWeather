import Foundation

/// The words and rules of using the app on this iPhone, without a server
/// (Plans/standalone.md, phase 4, #235), kept here so the tests can read
/// them.
public enum Standalone {
    /// The first screen's two ways (open question 7, decided 2026-11-18):
    /// each with what it gives and what it costs.
    public struct Way: Sendable, Equatable {
        public let title: String
        public let summary: String
        public let pros: [String]
        public let cons: [String]
    }

    public static let onThisPhone = Way(
        title: "On this iPhone",
        summary: "Your numbers live on this iPhone. Nothing to set up.",
        pros: ["No server to run or update",
               "Your numbers stay on your own devices",
               "Saved in this iPhone's iCloud or computer backup"],
        cons: ["No web app and no sharing with others",
               "No bank-alert emails or email alerts",
               "No Net worth, Budgets or Reports yet"])

    public static let ownServer = Way(
        title: "Your own server",
        summary: "Sign in to a WalletWeather server you run, at home or in the cloud.",
        pros: ["The web app and this iPhone, on the same numbers",
               "Share accounts, bank sync on a schedule, and alerts",
               "Net worth, Budgets and Reports"],
        cons: ["You run and update a server"])

    /// Where to learn how to set up a server.
    public static let setupGuide = URL(string: "https://github.com/mkolakowski/WalletWeather#readme")!

    /// What a server adds, shown where something needs one (open question 2,
    /// decided 2026-11-18).
    public static let serverAdds = "A WalletWeather server adds the web app, sharing accounts with others, bank sync on a schedule, bank-alert emails and email alerts, and Net worth, Budgets and Reports. You run it yourself, at home or in the cloud."
}

extension TabPage {
    /// Pages that need a server: shown on this iPhone's household, greyed
    /// and marked "Needs a server" (open question 2).
    public var needsServer: Bool {
        switch self {
        case .netWorth, .budgets, .reports: true
        case .dashboard, .forecast, .bills, .calendar: false
        }
    }
}

/// The New account form (#235): the web app's fields.
public struct AccountDraft: Sendable, Equatable {
    public var name = ""
    public var balanceText = ""
    public var startingDate: LocalDay

    public init(today: LocalDay) { startingDate = today }

    /// The starting balance: what's typed, with a leading minus for money
    /// owed (a credit card); nothing typed is zero.
    public var balance: Decimal? {
        let typed = balanceText.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return 0 }
        guard let value = parseAmount(typed) else { return nil }
        return typed.hasPrefix("-") || typed.hasPrefix("−") ? -value : value
    }

    /// What's missing before it can be saved, or nil.
    public var problem: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Give the account a name." }
        if trimmed.count > 120 { return "Keep the name to 120 characters." }
        if balance == nil { return "Enter the balance as a number, such as 1250.00 or -300." }
        return nil
    }

    public var body: AccountBody? {
        guard problem == nil, let balance else { return nil }
        return AccountBody(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           startingBalance: Double(Money(balance).amount.description) ?? 0,
                           startingDate: startingDate)
    }
}
