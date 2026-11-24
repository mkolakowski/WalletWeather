import Foundation

// Bills and accounts in the phone's search (Plans/outside-the-app.md, phase
// 4, #331): one entry for each bill, paycheck and account in a connection's
// summary, by name only, kept in step with the summary itself. Writing a
// summary replaces its connection's entries, so a bill or account deleted in
// the app leaves on the next write; deleting a summary (signing out, leaving
// the household, Delete everywhere) removes them; a server set to Nothing has
// a summary with its name only, so it has none. The demo never has a summary.
//
// Decided 2026-11-23 (docs/dev/decisions/ios-review.md, "what goes into the
// phone's search"): the household on this iPhone and servers that keep
// Last-known numbers are indexed, by name only; not servers set to Nothing,
// not the demo.

/// One entry in the phone's search. Names only: never an amount or a date.
public struct SearchEntry: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case bill
        case income
        case account
    }

    /// The entry's identifier in the index (`SearchLink.id`). Stable.
    public let id: String
    /// The connection the entry belongs to, its group in the index.
    public let connection: UUID
    public let kind: Kind
    /// The bill's or account's name.
    public let title: String
    /// What it is and where it lives: "Bill · Checking · Home".
    public let detail: String
    public let keywords: [String]

    /// Every entry for a summary: none for a summary with no numbers (a
    /// server set to Nothing).
    public static func entries(for summary: ConnectionSummary) -> [SearchEntry] {
        guard summary.keepsNumbers else { return [] }
        let accounts = summary.accounts.map { account in
            SearchEntry(id: SearchLink.account(summary.id, account.id).id, connection: summary.id, kind: .account,
                        title: account.name, detail: "Account · \(summary.name)",
                        keywords: ["WalletWeather", "account", summary.name])
        }
        let bills = summary.bills.map { bill in
            let kind: Kind = bill.isIncome ? .income : .bill
            let what = bill.isIncome ? "Income" : "Bill"
            return SearchEntry(id: SearchLink.bill(summary.id, bill.id).id, connection: summary.id, kind: kind,
                               title: bill.name, detail: "\(what) · \(bill.accountName) · \(summary.name)",
                               keywords: ["WalletWeather", what.lowercased(), bill.accountName, summary.name])
        }
        return accounts + bills
    }
}

/// Where a search entry opens: a bill on its connection's Bills & income, an
/// account in its connection's Forecast.
public enum SearchLink: Equatable, Sendable {
    case bill(UUID, Int)
    case account(UUID, Int)

    /// `<connection>/bill/<id>` or `<connection>/account/<id>`, the
    /// connection in lower case. Stable: never change the shape.
    public var id: String {
        switch self {
        case let .bill(connection, item): return "\(connection.uuidString.lowercased())/bill/\(item)"
        case let .account(connection, item): return "\(connection.uuidString.lowercased())/account/\(item)"
        }
    }

    public var connection: UUID {
        switch self {
        case let .bill(connection, _), let .account(connection, _): return connection
        }
    }

    public init?(id: String) {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, let connection = UUID(uuidString: String(parts[0])),
              let item = Int(parts[2]), item > 0 else { return nil }
        switch parts[1] {
        case "bill": self = .bill(connection, item)
        case "account": self = .account(connection, item)
        default: return nil
        }
    }
}

/// The phone's search index, as the summary store drives it. The app's is
/// Core Spotlight; the tests keep one in memory.
public protocol SearchIndexing: Sendable {
    /// A connection's entries become these, and only these.
    func replace(connection: UUID, with entries: [SearchEntry])
    /// A connection's entries go.
    func remove(connection: UUID)
    /// Every entry goes.
    func removeAll()
}
