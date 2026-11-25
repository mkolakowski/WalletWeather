import Foundation
import Testing
@testable import WalletWeatherKit

/// The months the month-name menu offers (#313).
struct MonthMenuTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    @Test func onThisMonthItIsSixBackAndSixAheadInCalendarOrder() {
        let choices = MonthMenuChoices(shown: ym(2026, 11), today: today)
        #expect(choices.months == (-6...6).filter { $0 != 0 }.map { ym(2026, 11).offset($0) })
        #expect(choices.months.first == ym(2026, 5))
        #expect(choices.months.last == ym(2027, 5))
    }

    @Test func awayFromThisMonthTheShownOneStaysInTheList() {
        // Inside the six either way: the same list, so it can carry the tick.
        let near = MonthMenuChoices(shown: ym(2027, 3), today: today)
        #expect(near.months == MonthMenuChoices(shown: ym(2026, 11), today: today).months)
        #expect(near.months.contains(ym(2027, 3)))
        // Further out: it's added, in its place in the order.
        let far = MonthMenuChoices(shown: ym(2027, 8), today: today)
        #expect(far.months.count == 13)
        #expect(far.months.last == ym(2027, 8))
        let past = MonthMenuChoices(shown: ym(2026, 1), today: today)
        #expect(past.months.first == ym(2026, 1))
    }

    @Test func alwaysInOrderWithNoRepeatsAndNotThisMonth() {
        for shown in (-14...14).map({ ym(2026, 11).offset($0) }) {
            let all = MonthMenuChoices(shown: shown, today: today).all
            #expect(all == all.sorted { $0.index < $1.index })
            #expect(Set(all).count == all.count)
            #expect(!all.contains(ym(2026, 11)))
            #expect(shown == ym(2026, 11) || all.contains(shown))
        }
    }

    @Test func crossesTheYearBothWays() {
        let choices = MonthMenuChoices(shown: ym(2026, 1), today: LocalDay(year: 2026, month: 1, day: 3))
        #expect(choices.months.first == ym(2025, 7))
        #expect(choices.months.last == ym(2026, 7))
    }
}

private extension YearMonth {
    func offset(_ months: Int) -> YearMonth { YearMonth(index: index + months) }
}
