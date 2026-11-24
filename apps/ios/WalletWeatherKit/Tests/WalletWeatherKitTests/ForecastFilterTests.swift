import Foundation
import Testing
@testable import WalletWeatherKit

/// Filtering the Forecast by a category or a tag (#327).
struct ForecastFilterTests {
    let holiday = TagInfo(id: 1, name: "Holiday", color: "#ff0000")
    let work = TagInfo(id: 2, name: "Work", color: nil)

    func line(_ name: String, _ amount: Decimal, category: String?, tags: [TagInfo]? = nil, paid: Bool = false) -> ForecastLine {
        let day = LocalDay(year: 2026, month: 11, day: 10)
        return ForecastLine(forecastDate: day, actualDate: paid ? day : nil, description: name, category: category,
                            categoryId: nil, notes: nil, forecastAmount: Money(amount), forecastBalance: .zero,
                            actualAmount: paid ? Money(amount - 1) : nil, actualBalance: .zero, diffAmount: nil,
                            diffBalance: .zero, isActualReal: paid, recurringId: nil, transactionId: 1, transferId: nil,
                            tags: tags)
    }

    var rows: [ForecastLine] {
        [line("Market", -100, category: "Groceries", tags: [holiday]),
         line("Cafe", -40, category: "Dining"),
         line("Store", -184.66, category: "Groceries", paid: true),
         line("Pay", 2000, category: "Income", tags: [work]),
         line("Gym", -50, category: "Health", tags: [work, holiday]),
         line("Mystery", -5, category: nil)]
    }

    @Test func chipsListCategoriesBySpendingThenTagsByName() {
        let chips = ForecastFilter.chips(for: rows)
        #expect(chips.map(\.filter.rawValue) == ["c:Groceries", "c:Health", "c:Dining", "c:Income", "t:Holiday", "t:Work"])
        #expect(chips.map(\.count) == [2, 1, 1, 1, 2, 2])
        #expect(chips.first { $0.filter.name == "Holiday" }?.color == "#ff0000")
        #expect(chips.first { $0.filter.name == "Work" }?.color == nil)
    }

    @Test func noCategoriesOrTagsMeansNoChips() {
        #expect(ForecastFilter.chips(for: [line("Mystery", -5, category: nil)]).isEmpty)
        #expect(ForecastFilter.chips(for: []).isEmpty)
    }

    @Test func aCategoryKeepsItsLinesAndATagKeepsItsLines() {
        #expect(ForecastFilter(.category, "Groceries").apply(to: rows).map(\.description) == ["Market", "Store"])
        #expect(ForecastFilter(.tag, "Holiday").apply(to: rows).map(\.description) == ["Market", "Gym"])
        #expect(ForecastFilter(.category, "Holiday").apply(to: rows).isEmpty)
        #expect(ForecastFilter.apply(nil, to: rows) == rows)
    }

    @Test func theTotalCountsPaidLinesAtTheirRealAmount() {
        let kept = ForecastFilter(.category, "Groceries").apply(to: rows)
        #expect(ForecastFilter.total(of: kept) == Money(-100 + -185.66))
        #expect(ForecastFilter(.category, "Groceries").summary(of: kept) == "Groceries · 2 lines · -$285.66")
        let one = ForecastFilter(.category, "Dining").apply(to: rows)
        #expect(ForecastFilter(.category, "Dining").summary(of: one) == "Dining · 1 line · -$40.00")
    }

    @Test func aFilterWithinToConfirmKeepsOnlyThoseLines() {
        let today = LocalDay(year: 2026, month: 11, day: 15)
        let month = ForecastMonth(openingBalance: .zero, forecastEndingBalance: .zero, actualEndingBalance: .zero,
                                  currentBalance: .zero, rows: rows)
        let confirming = month.toConfirm(today: today)
        #expect(ForecastFilter(.category, "Groceries").apply(to: confirming).map(\.description) == ["Market"])
    }

    @Test func aChoiceSurvivesStoringAndIsFoundByName() {
        let filter = ForecastFilter(.tag, "Holiday")
        #expect(ForecastFilter(rawValue: filter.rawValue) == filter)
        #expect(ForecastFilter(rawValue: "x") == nil && ForecastFilter(rawValue: "z:Food") == nil)
        #expect(ForecastFilter.named("groceries", in: rows) == ForecastFilter(.category, "Groceries"))
        #expect(ForecastFilter.named("work", in: rows) == ForecastFilter(.tag, "Work"))
        #expect(ForecastFilter.named("Nothing", in: rows) == nil)
    }
}
