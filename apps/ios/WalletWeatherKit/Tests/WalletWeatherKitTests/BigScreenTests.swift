import Foundation
import Testing
@testable import WalletWeatherKit

/// The Duo's big screen (#90): the "To confirm" list and Compare, from the
/// Forecast sample (Checking in November 2026, seen on Nov 15).
struct BigScreenTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func month() throws -> ForecastMonth { try DecodingTests().sample("forecast") }

    @Test func toConfirmIsUnpaidUpToToday() throws {
        let lines = try month().toConfirm(today: today)
        #expect(lines.map(\.description) == ["Rent", "Gym", "Paycheck", "Electric", "Streaming service"])
        #expect(lines.allSatisfy { !$0.isPaid })
        // Nothing to confirm before the month starts.
        #expect(try month().toConfirm(today: LocalDay(year: 2026, month: 10, day: 31)).isEmpty)
    }

    @Test func paidAtADifferentAmount() throws {
        let gym = try #require(try month().rows.first { $0.description == "Gym" })
        let draft = LineDraft.paid(gym, amountText: " 41.50 ", today: today)
        #expect(draft.paid && draft.paidAmount == Decimal(string: "41.50"))
        #expect(draft.paidOn == LocalDay(year: 2026, month: 11, day: 5))
        #expect(draft.problem == nil)
        #expect(LineDraft.paid(gym, amountText: "", today: today).problem != nil)
    }

    @Test func compareLinesUpByDayOfMonth() throws {
        let m = try month()
        let days = Compare.days(left: m.rows, right: Array(m.rows.prefix(3)))
        #expect(days.map(\.day) == [1, 4, 5, 6, 11, 12, 13, 15, 18, 25])
        let eleventh = try #require(days.first { $0.day == 11 })
        #expect(eleventh.left.count == 2 && eleventh.right.isEmpty)
        let first = try #require(days.first)
        #expect(first.left.map(\.description) == ["Rent"] && first.right.map(\.description) == ["Rent"])
    }

    @Test func compareBalanceThroughADay() throws {
        let m = try month()
        #expect(Compare.balance(through: 0, in: m) == m.openingBalance)
        let fifth = try #require(m.rows.first { $0.description == "Gym" })
        #expect(Compare.balance(through: 5, in: m) == fifth.actualBalance)
        #expect(Compare.balance(through: 31, in: m) == m.rows.last?.actualBalance)
    }

    @Test func dayOfAMonth() {
        let november = YearMonth(year: 2026, month: 11)
        #expect(november.day(5) == LocalDay(year: 2026, month: 11, day: 5))
        #expect(november.day(31) == nil && november.day(0) == nil)
        #expect(YearMonth(year: 2028, month: 2).day(29) != nil)
    }
}
