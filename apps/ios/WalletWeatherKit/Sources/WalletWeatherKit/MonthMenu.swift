import Foundation

// The months a page's month-name menu offers (#313): tap the name on Today
// Forecast, Calendar or Compare to jump instead of paging with the arrows.

/// The months offered next to "This month", in the order they are listed.
public struct MonthMenuChoices: Sendable, Equatable {
    /// The month before the one shown, then the month after it.
    public let neighbours: [YearMonth]
    /// The six months after this one, nearest first.
    public let ahead: [YearMonth]
    /// The six months before this one, nearest first.
    public let behind: [YearMonth]

    /// All of them in listing order.
    public var all: [YearMonth] { neighbours + ahead + behind }

    /// For the month `shown`, with `today` in this month. Neither the shown
    /// month nor this month is listed (the page is already on one, and
    /// "This month" is its own item), and no month is listed twice.
    public init(shown: YearMonth, today: LocalDay) {
        let now = YearMonth(today)
        var seen: Set<YearMonth> = [shown, now]
        func fresh(_ months: [YearMonth]) -> [YearMonth] {
            months.filter { seen.insert($0).inserted }
        }
        neighbours = fresh([shown.previous, shown.next])
        ahead = fresh((1...6).map { YearMonth(index: now.index + $0) })
        behind = fresh((1...6).map { YearMonth(index: now.index - $0) })
    }
}
