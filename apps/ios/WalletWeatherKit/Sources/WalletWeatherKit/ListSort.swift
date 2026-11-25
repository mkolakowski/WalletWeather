import Foundation

// The sort button in a page's top bar (#350): To confirm in Forecast, and
// Bills & income. Each list keeps its own choice and starts in the order it
// always had.

/// How a list is sorted: by date, amount or name, either way round.
public struct ListSort: Sendable, Hashable, RawRepresentable {
    public enum Key: String, Sendable, CaseIterable {
        case date, amount, name

        /// The menu's heading for this key.
        public var title: String {
            switch self {
            case .date: "Date"
            case .amount: "Amount"
            case .name: "Name"
            }
        }
    }

    public var key: Key
    /// Oldest (or soonest) first, smallest first, A to Z.
    public var ascending: Bool

    public init(_ key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// `date.up`, `amount.down`, …: what a page stores.
    public var rawValue: String { "\(key.rawValue).\(ascending ? "up" : "down")" }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ".")
        guard parts.count == 2, let key = Key(rawValue: String(parts[0])),
              parts[1] == "up" || parts[1] == "down" else { return nil }
        self.init(key, ascending: parts[1] == "up")
    }

    /// To confirm's order before the button: oldest first.
    public static let toConfirmDefault = ListSort(.date, ascending: true)
    /// Bills & income's order before the button: by name, A to Z.
    public static let billsDefault = ListSort(.name, ascending: true)

    /// The stored choice, or `fallback` when there's none (or it's unreadable).
    public static func stored(_ text: String, default fallback: ListSort) -> ListSort {
        ListSort(rawValue: text) ?? fallback
    }

    /// The menu's choices, in order: each key with its two directions.
    public static let choices: [ListSort] = Key.allCases.flatMap { [ListSort($0, ascending: true), ListSort($0, ascending: false)] }

    /// What the menu calls this choice. Dates still to come (Bills) read
    /// soonest and latest; dates gone by (To confirm) read oldest and newest.
    public func title(future: Bool) -> String {
        switch (key, ascending) {
        case (.date, true): future ? "Soonest first" : "Oldest first"
        case (.date, false): future ? "Latest first" : "Newest first"
        case (.amount, true): "Smallest first"
        case (.amount, false): "Largest first"
        case (.name, true): "A to Z"
        case (.name, false): "Z to A"
        }
    }

    /// What VoiceOver reads as the button's value: "Date, oldest first".
    public func spoken(future: Bool) -> String { "\(key.title), \(title(future: future).lowercased())" }

    /// `items` in this order. Amounts compare by size, bills and income
    /// alike; a missing date goes last either way round; ties fall back to
    /// the name, then the original order, so the list never shuffles.
    public func apply<T>(to items: [T], date: (T) -> LocalDay?, amount: (T) -> Decimal, name: (T) -> String) -> [T] {
        // Worked out once per item, so the comparison closure needs none of them.
        let keyed = items.enumerated().map { (offset: $0.offset, item: $0.element, date: date($0.element),
                                              size: abs(amount($0.element)), name: name($0.element)) }
        let up = ascending
        func flip(_ order: ComparisonResult) -> ComparisonResult {
            up ? order : order == .orderedAscending ? .orderedDescending : order == .orderedDescending ? .orderedAscending : .orderedSame
        }
        func compare<V: Comparable>(_ x: V, _ y: V) -> ComparisonResult {
            x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
        }
        let key = self.key
        return keyed.sorted { a, b in
            var order: ComparisonResult
            switch key {
            case .date:
                switch (a.date, b.date) {
                case let (x?, y?): order = flip(compare(x, y))
                case (nil, nil): order = .orderedSame
                case (nil, _): return false
                case (_, nil): return true
                }
            case .amount: order = flip(compare(a.size, b.size))
            case .name: order = flip(a.name.localizedStandardCompare(b.name))
            }
            if order == .orderedSame, key != .name { order = a.name.localizedStandardCompare(b.name) }
            return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
        }.map(\.item)
    }

    /// Forecast lines: the planned date, the planned amount, the name.
    public func apply(to lines: [ForecastLine]) -> [ForecastLine] {
        apply(to: lines, date: \.plannedDate, amount: \.plannedAmount.amount, name: \.description)
    }

    /// Bills and income: the next date due, the amount, the name.
    public func apply(to items: [RecurringItem]) -> [RecurringItem] {
        apply(to: items, date: \.nextDate, amount: \.amount.amount, name: \.description)
    }
}
