import Foundation
import Testing
@testable import WalletWeatherKit

/// The Calendar's amounts and colour bars (#323): each day's short net, and
/// which colour or style each line's bar takes.
struct CalendarBarTests {
    let day = LocalDay(year: 2026, month: 11, day: 20)

    func event(_ amount: Double?, color: String? = nil, transfer: Int? = nil, paid: Bool = false,
               on date: LocalDay? = nil) -> CalendarEvent {
        CalendarEvent(date: date ?? day, accountId: 3, accountName: "Checking", description: "Line",
                      amount: amount.map { Money($0) }, categoryName: color == nil ? nil : "Food", categoryColor: color,
                      recurringId: nil, transactionId: 1, transferId: transfer, isActualReal: paid, notes: nil)
    }

    func month(_ events: [CalendarEvent]) -> CalendarMonth {
        CalendarMonth(start: LocalDay(year: 2026, month: 11, day: 1), end: LocalDay(year: 2026, month: 11, day: 30),
                      events: events, dailyBalances: nil)
    }

    @Test func aCategoryColourWins() {
        #expect(DayBar(of: event(-40, color: "#3fb950")).style == .category("#3fb950"))
        #expect(DayBar(of: event(40, color: "#A371F7")).style == .category("#A371F7"))
    }

    @Test func withoutAColourIncomeIsGreenSpendingRedAndATransferOutlined() {
        #expect(DayBar(of: event(100)).style == .income)
        #expect(DayBar(of: event(-100)).style == .spending)
        #expect(DayBar(of: event(-100, transfer: 5)).style == .transfer)
        #expect(DayBar(of: event(nil)).style == .income, "no amount reads as zero, not spending")
    }

    @Test func aBadColourIsNoColour() {
        #expect(DayBar(of: event(-5, color: "red")).style == .spending)
        #expect(DayBar(of: event(-5, color: "#12345")).style == .spending)
        #expect(DayBar(of: event(-5, color: "#12345g")).style == .spending)
        #expect(DayBar(of: event(5, color: "")).style == .income)
    }

    @Test func aPaidLineIsMarkedPaid() {
        #expect(DayBar(of: event(-5, paid: true)).isPaid)
        #expect(!DayBar(of: event(-5)).isPaid)
    }

    @Test func theDaysShortNetAndBars() {
        let summary = month([event(-2000), event(400, color: "#58a6ff"), event(-30)]).summary(of: day)
        #expect(summary.shortNet == "-$1.6K")
        #expect(summary.bars.map(\.style) == [.spending, .category("#58a6ff"), .spending])
        #expect(month([event(2800)]).summary(of: day).shortNet == "+$2.8K")
        #expect(month([event(0)]).summary(of: day).shortNet == "+$0")
    }

    @Test func aDayWithNoLinesHasNoNetAndNoBars() {
        let summary = month([event(-5, on: LocalDay(year: 2026, month: 11, day: 21))]).summary(of: day)
        #expect(summary.shortNet == nil)
        #expect(summary.visibleBars.isEmpty)
    }

    @Test func cellsDrawAtMostThreeBars() {
        let summary = month((1...5).map { event(Double(-$0)) }).summary(of: day)
        #expect(summary.count == 5)
        #expect(summary.bars.count == 5)
        #expect(summary.visibleBars.count == DayBar.limit)
        #expect(DayBar.limit == 3)
    }
}
