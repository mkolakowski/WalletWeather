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

    /// The row's paid-on chip (#349): both buttons record the day picked,
    /// a day still to come is taken as today, and the amount still applies.
    @Test func confirmedOnThePickedDay() throws {
        let gym = try #require(try month().rows.first { $0.description == "Gym" })
        let tenth = LocalDay(year: 2026, month: 11, day: 10)
        let asPlanned = LineDraft.confirmed(gym, amountText: nil, on: tenth, today: today)
        #expect(asPlanned.paid && asPlanned.paidOn == tenth && asPlanned.paidAmount == Decimal(39))
        let typed = LineDraft.confirmed(gym, amountText: "41.50", on: tenth, today: today)
        #expect(typed.paidOn == tenth && typed.paidAmount == Decimal(string: "41.50"))
        let later = LineDraft.confirmed(gym, amountText: nil, on: LocalDay(year: 2026, month: 11, day: 20), today: today)
        #expect(later.paidOn == today)
        // Left on the chip's first day, it's the day a swipe would use.
        #expect(LineDraft.confirmed(gym, amountText: nil, on: LineDraft.paidOn(gym, today: today), today: today)
                == LineDraft.paidAsPlanned(gym, today: today))
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

    @Test func compareGoesToOneSideAtATimeUnderSixHundredPoints() throws {
        // The closed Duo and an iPhone are narrow; the open Duo is not (#359).
        #expect(Compare.isNarrow(width: 402))
        #expect(Compare.isNarrow(width: 599.5))
        #expect(!Compare.isNarrow(width: 600))
        #expect(!Compare.isNarrow(width: 1000))
    }

    @Test func compareOneSideShowsOnlyItsOwnDays() throws {
        let m = try month()
        let first3 = Array(m.rows.prefix(3))
        // The left has every line; the right only three, so on the right
        // alone the days the left has and it hasn't are gone.
        let right = Compare.days(of: .right, left: m.rows, right: first3)
        #expect(right.allSatisfy { !$0.right.isEmpty })
        #expect(right.count < Compare.days(left: m.rows, right: first3).count)
        let left = Compare.days(of: .left, left: m.rows, right: first3)
        #expect(left.map(\.day) == Compare.days(left: m.rows, right: first3).map(\.day))
        // Nothing on a side gives nothing to show.
        #expect(Compare.days(of: .right, left: m.rows, right: []).isEmpty)
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
