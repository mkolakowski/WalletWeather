import Foundation

// The months a page's month-name menu offers (#313): tap the name on Today
// Forecast, Calendar or Compare to jump instead of paging with the arrows.

/// The months offered under "This month", in calendar order (#364).
public struct MonthMenuChoices: Sendable, Equatable {
    /// The six months before this one and the six after it, oldest first,
    /// with the shown month among them when it's further away than that.
    /// This month is left out: it's the menu's first item, "This month".
    public let months: [YearMonth]

    /// All of them in listing order.
    public var all: [YearMonth] { months }

    /// For the month `shown`, with `today` in this month. This month is not
    /// listed ("This month" is its own item), and no month is listed twice.
    public init(shown: YearMonth, today: LocalDay) {
        let now = YearMonth(today)
        var list = (-6...6).filter { $0 != 0 }.map { YearMonth(index: now.index + $0) }
        if shown != now, !list.contains(shown) {
            list.append(shown)
            list.sort { $0.index < $1.index }
        }
        months = list
    }
}
