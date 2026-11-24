import Foundation

// The bank card on the Dashboard (#321, idea F4 of the iOS review): one slim
// card above "Rest of this month", only while bank sync has something for
// the person to do. This is which lines it shows for each bank state, from
// the same status Settings → Bank sync reads (a server's `BankStatus` and
// the Unmatched counts, or the iPhone's own `PhoneBankState`).

/// One line of the card: its words, its symbol, and where a tap goes.
public struct BankCardLine: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        /// The Unmatched list of these accounts (nil: the household on this iPhone's).
        case unmatched(accounts: [Int]?)
        /// Settings → Bank sync, where a connection is connected again.
        case reconnect
    }

    public let action: Action
    public let text: String
    /// An SF Symbol name.
    public let symbol: String
    public var id: String {
        switch action {
        case let .unmatched(accounts): "unmatched/\(accounts?.map(String.init).joined(separator: ",") ?? "phone")"
        case .reconnect: "reconnect"
        }
    }

    /// The most urgent first: a bank that needs connecting again comes before lines to match.
    static func reconnect(_ names: [String]) -> BankCardLine? {
        guard let first = names.first else { return nil }
        let text = names.count == 1 ? "\(first) needs reconnecting" : "\(names.count) banks need reconnecting"
        return BankCardLine(action: .reconnect, text: text, symbol: "exclamationmark.triangle")
    }

    static func unmatched(total: Int, accounts: [Int]?) -> BankCardLine? {
        guard total > 0 else { return nil }
        return BankCardLine(action: .unmatched(accounts: accounts),
                            text: "\(total) bank line\(total == 1 ? "" : "s") to match", symbol: "building.columns")
    }
}

public enum BankCard {
    /// The card never shows more than this many lines (it stays slim).
    public static let maxLines = 2

    /// The lines for a server's bank sync (also the demo's): `counts` is
    /// `APIClient.unmatchedCounts(for:)`. Nothing while bank sync is off or
    /// the status couldn't be read (nil). A connection that needs connecting
    /// again is named when it's the only one, else counted; shared accounts
    /// never ask for it (only their holder can reconnect), but their lines to
    /// match count. At most `maxLines`, reconnecting first.
    public static func lines(status: BankStatus?, counts: [Int: Int]) -> [BankCardLine] {
        guard let status, status.enabled else { return [] }
        var out: [BankCardLine] = []
        if status.connected {
            let list = status.connections ?? []
            let names = list.isEmpty
                ? (status.needsReconnect == true ? ["Your bank"] : [])
                : list.filter { $0.needsReconnect == true }.map(\.name)
            if let line = BankCardLine.reconnect(names) { out.append(line) }
        }
        let accounts = (status.connected ? status.ownLinkedAccountIds : []) + (status.shared ?? []).map(\.accountId)
        let waiting = accounts.filter { (counts[$0] ?? 0) > 0 }
        if let line = BankCardLine.unmatched(total: waiting.reduce(0) { $0 + (counts[$1] ?? 0) }, accounts: waiting) {
            out.append(line)
        }
        return Array(out.prefix(maxLines))
    }

    /// The lines for the household on this iPhone, whose SimpleFIN is the
    /// one connection: named by its bank when it has one, else "SimpleFIN".
    public static func lines(phone state: PhoneBankState, connected: Bool) -> [BankCardLine] {
        guard connected else { return [] }
        var out: [BankCardLine] = []
        if state.needsReconnect {
            let orgs = Set(state.bankAccounts.map(\.org).filter { !$0.isEmpty })
            let name = orgs.count == 1 ? (orgs.first ?? "SimpleFIN") : "SimpleFIN"
            if let line = BankCardLine.reconnect([name]) { out.append(line) }
        }
        if let line = BankCardLine.unmatched(total: state.unmatched, accounts: nil) { out.append(line) }
        return Array(out.prefix(maxLines))
    }
}
