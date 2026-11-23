import Foundation
import Testing
@testable import WalletWeatherKit

/// The months the month-name menu offers (#313).
struct MonthMenuTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func ym(_ y: Int, _ m: Int) -> YearMonth { YearMonth(year: y, month: m) }

    @Test func onThisMonthItIsTheNeighboursThenSixEitherWay() {
        let choices = MonthMenuChoices(shown: ym(2026, 11), today: today)
        #expect(choices.neighbours == [ym(2026, 10), ym(2026, 12)])
        // The neighbours already hold October and December.
        #expect(choices.ahead == [ym(2027, 1), ym(2027, 2), ym(2027, 3), ym(2027, 4), ym(2027, 5)])
        #expect(choices.behind == [ym(2026, 9), ym(2026, 8), ym(2026, 7), ym(2026, 6), ym(2026, 5)])
    }

    @Test func awayFromThisMonthItListsTheOnesAroundTheShownMonth() {
        let choices = MonthMenuChoices(shown: ym(2027, 8), today: today)
        #expect(choices.neighbours == [ym(2027, 7), ym(2027, 9)])
        #expect(choices.ahead == (1...6).map { ym(2026, 11).offset($0) })
        #expect(choices.behind == (1...6).map { ym(2026, 11).offset(-$0) })
    }

    @Test func noRepeatsAndNeitherTheShownNorThisMonth() {
        for shown in (-14...14).map({ ym(2026, 11).offset($0) }) {
            let all = MonthMenuChoices(shown: shown, today: today).all
            #expect(Set(all).count == all.count)
            #expect(!all.contains(shown))
            #expect(!all.contains(ym(2026, 11)))
        }
    }

    @Test func crossesTheYearBothWays() {
        let choices = MonthMenuChoices(shown: ym(2026, 1), today: LocalDay(year: 2026, month: 1, day: 3))
        #expect(choices.neighbours == [ym(2025, 12), ym(2026, 2)])
        #expect(choices.ahead.last == ym(2026, 7))
        #expect(choices.behind.last == ym(2025, 7))
    }
}

private extension YearMonth {
    func offset(_ months: Int) -> YearMonth { YearMonth(index: index + months) }
}
