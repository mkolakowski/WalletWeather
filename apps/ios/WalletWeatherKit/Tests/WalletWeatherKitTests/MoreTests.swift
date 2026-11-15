import Foundation
import Testing
@testable import WalletWeatherKit

/// The More pages (#91), from samples recorded from the demo server at app
/// 1.54.0 (with three budgets added), seen on Nov 15, 2026.
struct MoreTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try DecodingTests().sample(name)
    }

    @Test func netWorth() throws {
        let worth: NetWorth = try sample("networth")
        #expect(worth.window == .month && worth.label == "November 2026")
        #expect(worth.trend.count == 30 && worth.accounts.count == 3)
        #expect(worth.total(on: today)?.formatted == "$22,399.49")
        #expect(worth.change(through: today)?.formatted == "$674.15")
        #expect(worth.actualEndTotal.formatted == "$25,074.50")
        #expect(worth.accounts.first { $0.accountName == "Credit Card" }?.actualEnd.formatted == "-$1,020.48")
        // A day after the window ends reads its last point.
        #expect(worth.total(on: LocalDay("2026-12-20")!) == worth.trend.last?.balance)
    }

    @Test func budgets() throws {
        let b: BudgetProgress = try sample("budgets")
        #expect(b.budgeted.map(\.categoryName) == ["Groceries", "Shopping", "Dining"])
        let shopping = try #require(b.budgeted.first { $0.categoryName == "Shopping" })
        #expect(shopping.over && shopping.fraction == 1 && shopping.remaining.formatted == "-$22.18")
        let groceries = try #require(b.budgeted.first { $0.categoryName == "Groceries" })
        #expect(abs(groceries.fraction - 0.474) < 0.0001)
        #expect(b.totals.budget.formatted == "$400.00")
        #expect(b.budgetedSpend.formatted == "$237.26")
        #expect(b.budgetedLeft.formatted == "$162.74")
        #expect(b.unbudgetedSpend.formatted == "$2,013.58")
        #expect(b.unbudgeted.allSatisfy { $0.pct == nil && $0.fraction == 0 })
    }

    @Test func reportRunTotals() throws {
        let run: ReportRun = try sample("report-run")
        #expect(run.totals.actualSpending.formatted == "-$2,250.84")
        #expect(run.totals.actualIncome == .zero)
        #expect(run.groups.first?.forecastTotal.formatted == "-$1,650.00")
    }
}
