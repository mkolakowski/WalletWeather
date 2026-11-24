import Foundation

/// A total beside each connection in Settings → Connections (#329): what
/// the accounts add up to today, and how old that is. The logic is here so
/// it can be tested; the page reads the numbers and draws it.
///
/// - A server shows the total from its kept Dashboard (`KeptResponses`, the
///   one the Dashboard writes each time it loads), and only when the person
///   chose Last-known numbers for it. Choosing Nothing keeps no numbers, so
///   there is no total. Another connection's numbers are never requested
///   from the network.
/// - The household on this iPhone and the demo work theirs out on the phone.
/// - Locked in the demo, no total shows, as no address or email does
///   (`ConnectionsVisibility.showsTotals`).
public enum ConnectionTotals {
    /// Where a connection's number came from.
    public enum Reading: Equatable, Sendable {
        /// A server's kept Dashboard, loaded at this moment.
        case kept(Money, Date)
        /// Worked out on the phone just now: the household on this iPhone.
        case live(Money)
        /// The demo's sample numbers.
        case sample(Money)
    }

    /// What a row shows: the total, and the caption under it.
    public struct Figure: Equatable, Sendable {
        public let total: Money
        public let caption: String
    }

    /// The Dashboard's accounts, added up: each card's balance today.
    public static func total(of dashboard: Dashboard) -> Money {
        dashboard.cards.reduce(Money.zero) { $0 + $1.currentBalance }
    }

    /// A server's kept Dashboard, read the way the pages read it (its own
    /// folder, a file that is unreadable while the phone is locked): its
    /// total and when it was kept; nil when nothing is kept.
    public static func kept(in keeper: KeptResponses, server: URL) -> (total: Money, keptAt: Date)? {
        let key = KeptResponses.key(server: server, method: "GET", path: "/api/dashboard", query: [:])
        guard let found = keeper.load(key),
              let dashboard = try? APIClient.decoder().decode(Dashboard.self, from: found.data) else { return nil }
        return (total(of: dashboard), found.keptAt)
    }

    /// What each row has to show, by row: a server that keeps numbers and
    /// has some kept, the household on this iPhone (saved or not) when its
    /// total is known, and the demo's sample total when known.
    /// `keptTotal` reads one server's kept numbers.
    public static func readings(saved: [SavedConnection], keptTotal: (SavedConnection) -> (total: Money, keptAt: Date)?,
                                household: Money?, demo: Money?) -> [ConnectionRow.Target: Reading] {
        var found: [ConnectionRow.Target: Reading] = [:]
        for connection in saved {
            switch connection.kind {
            case .server:
                guard connection.keep == .lastKnown, let kept = keptTotal(connection) else { continue }
                found[.saved(connection.id)] = .kept(kept.total, kept.keptAt)
            case .thisPhone:
                if let household { found[.saved(connection.id)] = .live(household) }
            }
        }
        if let household { found[.thisIPhone] = .live(household) }
        if let demo { found[.demo] = .sample(demo) }
        return found
    }

    /// The total and caption for a row, or nil: locked in the demo, or no
    /// number for it.
    public static func figure(for row: ConnectionRow, among readings: [ConnectionRow.Target: Reading],
                              visibility: ConnectionsVisibility, now: Date = .now,
                              calendar: Calendar = .current) -> Figure? {
        guard visibility.showsTotals, let reading = readings[row.target] else { return nil }
        switch reading {
        case let .kept(total, keptAt): return Figure(total: total, caption: asOf(keptAt, now: now, calendar: calendar))
        case let .live(total): return Figure(total: total, caption: "as of now")
        case let .sample(total): return Figure(total: total, caption: "sample numbers")
        }
    }

    /// How old a kept total is: "as of just now", "as of 12 min ago",
    /// "as of 2 h ago" (within today), "as of yesterday", then the date as
    /// the app writes dates ("as of Nov 22").
    public static func asOf(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "as of just now" }
        if calendar.isDate(date, inSameDayAs: now) {
            let minutes = Int(seconds / 60)
            return minutes < 60 ? "as of \(minutes) min ago" : "as of \(minutes / 60) h ago"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "as of yesterday"
        }
        return "as of \(LocalDay.display(of: date, now: now))"
    }
}
