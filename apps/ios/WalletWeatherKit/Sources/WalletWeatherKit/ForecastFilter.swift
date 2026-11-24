import Foundation

/// Filtering the Forecast by one category or one tag (#327): which chips the
/// month offers, which lines a chip keeps, and the small total line above
/// the list. Pure, so it is tested without the app.
public struct ForecastFilter: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case category, tag }

    public let kind: Kind
    /// The category's or tag's name; what a line is matched on, and what a
    /// debug setting or a remembered choice can say.
    public let name: String

    public init(_ kind: Kind, _ name: String) {
        self.kind = kind
        self.name = name
    }

    /// A chip the month offers: the filter, how many lines it keeps, and,
    /// for a tag, its colour (`#rrggbb`, or nil for a steady one by name).
    public struct Chip: Sendable, Hashable, Identifiable {
        public let filter: ForecastFilter
        public let count: Int
        public let color: String?
        public var id: String { filter.rawValue }
    }

    /// Stored text ("c:Groceries", "t:Holiday"), for the remembered choice.
    public var rawValue: String { (kind == .category ? "c:" : "t:") + name }

    public init?(rawValue: String) {
        guard rawValue.count > 2 else { return nil }
        let name = String(rawValue.dropFirst(2))
        switch rawValue.prefix(2) {
        case "c:": self.init(.category, name)
        case "t:": self.init(.tag, name)
        default: return nil
        }
    }

    /// A choice written by hand (`WW_DEBUG_FILTER=Groceries`): the month's
    /// category of that name, else its tag of that name (any case).
    public static func named(_ text: String, in rows: [ForecastLine]) -> ForecastFilter? {
        let chips = chips(for: rows)
        func match(_ kind: Kind) -> ForecastFilter? {
            chips.first { $0.filter.kind == kind && $0.filter.name.caseInsensitiveCompare(text) == .orderedSame }?.filter
        }
        return match(.category) ?? match(.tag)
    }

    public func keeps(_ line: ForecastLine) -> Bool {
        switch kind {
        case .category: return line.category == name
        case .tag: return line.tags?.contains { $0.name == name } ?? false
        }
    }

    /// The lines this filter keeps, in their order.
    public func apply(to rows: [ForecastLine]) -> [ForecastLine] { rows.filter(keeps) }

    /// The month's chips: its categories (most money going out first, then
    /// by name), then its tags (by name). Only those that appear in `rows`,
    /// so an empty list means the row of chips is hidden.
    public static func chips(for rows: [ForecastLine]) -> [Chip] {
        var spent: [String: Decimal] = [:]
        var counts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var tagColors: [String: String] = [:]
        for line in rows {
            if let category = line.category, !category.isEmpty {
                counts[category, default: 0] += 1
                if line.amount.isNegative { spent[category, default: 0] += -line.amount.amount }
            }
            for tag in line.tags ?? [] where !tag.name.isEmpty {
                tagCounts[tag.name, default: 0] += 1
                if let color = tag.color { tagColors[tag.name] = color }
            }
        }
        func before(_ a: String, _ b: String) -> Bool { a.localizedCaseInsensitiveCompare(b) == .orderedAscending }
        let categories = counts.keys.sorted { a, b in
            let (x, y) = (spent[a] ?? 0, spent[b] ?? 0)
            return x != y ? x > y : before(a, b)
        }
        let tags = tagCounts.keys.sorted(by: before)
        return categories.map { Chip(filter: .init(.category, $0), count: counts[$0] ?? 0, color: nil) }
            + tags.map { Chip(filter: .init(.tag, $0), count: tagCounts[$0] ?? 0, color: tagColors[$0]) }
    }

    /// What `filter` leaves of `rows`: all of them when nil.
    public static func apply(_ filter: ForecastFilter?, to rows: [ForecastLine]) -> [ForecastLine] {
        filter.map { $0.apply(to: rows) } ?? rows
    }

    /// The lines' amounts added up (what each counts at: the real amount
    /// when paid).
    public static func total(of rows: [ForecastLine]) -> Money {
        rows.reduce(Money.zero) { $0 + $1.amount }
    }

    /// "Groceries · 3 lines · -$284.66", for the lines this filter left.
    public func summary(of lines: [ForecastLine]) -> String {
        let count = lines.count == 1 ? "1 line" : "\(lines.count) lines"
        return "\(name) · \(count) · \(Self.total(of: lines).formatted)"
    }
}
