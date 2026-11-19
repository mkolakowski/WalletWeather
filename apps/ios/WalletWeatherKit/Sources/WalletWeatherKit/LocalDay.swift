import Foundation

/// A calendar day with no time or zone, as the server sends dates
/// (`YYYY-MM-DD`). "Today" is the phone's own date, sent to the server as
/// `today=` so it never goes by the server's clock.
public struct LocalDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`; nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = LocalDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD date: \(text)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// The day it is now where the phone is.
    public static func today(calendar: Calendar = .current, now: Date = .now) -> LocalDay {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDay(year: c.year!, month: c.month!, day: c.day!)
    }

    /// `YYYY-MM-DD`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon on this day in the phone's time zone, for charts and formatting.
    public var date: Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar.current.date(from: c) ?? .distantPast
    }

    /// "Nov 3".
    public var short: String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The last day of this day's month.
    public var endOfMonth: LocalDay {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = 1; c.hour = 12
        let first = Calendar.current.date(from: c)!
        let days = Calendar.current.range(of: .day, in: .month, for: first)!.count
        return LocalDay(year: year, month: month, day: days)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension LocalDay {
    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private var utcNoon: Date {
        Self.gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// The day `days` later (earlier when negative).
    func adding(days: Int) -> LocalDay {
        let moved = Self.gregorian.date(byAdding: .day, value: days, to: utcNoon) ?? utcNoon
        let c = Self.gregorian.dateComponents([.year, .month, .day], from: moved)
        return LocalDay(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Days from `other` to this day.
    func days(since other: LocalDay) -> Int {
        Self.gregorian.dateComponents([.day], from: other.utcNoon, to: utcNoon).day ?? 0
    }
}

