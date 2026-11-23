import Foundation
import Testing
@testable import WalletWeatherKit

/// Undo after a line is marked paid from the list (#315): the draft that
/// takes "paid" back, and finding the line again in the reloaded month.
struct UndoPaidTests {
    let today = LocalDay(year: 2026, month: 11, day: 15)

    func month() throws -> ForecastMonth { try DecodingTests().sample("forecast") }

    func line(_ month: ForecastMonth, _ name: String, at index: Int = 0) throws -> ForecastLine {
        let found = month.rows.filter { $0.description == name }
        return try #require(found.indices.contains(index) ? found[index] : nil)
    }

    /// The line as a reload shows it after it was saved as a paid
    /// transaction (`id`), for `amount` on `day`.
    func saved(_ line: ForecastLine, id: Int, amount: Decimal, on day: LocalDay) -> ForecastLine {
        ForecastLine(forecastDate: line.plannedDate, actualDate: day, description: line.description, category: line.category,
                     categoryId: line.categoryId, notes: "kept", forecastAmount: line.forecastAmount, forecastBalance: .zero,
                     actualAmount: Money(amount), actualBalance: .zero, diffAmount: nil, diffBalance: .zero,
                     isActualReal: true, recurringId: line.recurringId, transactionId: id, transferId: nil)
    }

    func body(_ line: ForecastLine, _ draft: LineDraft) throws -> [String: AnyHashable] {
        try ForecastTests().json(TransactionBody(line: line, draft: draft))
    }

    // MARK: The draft

    @Test func undoingALinePaidAsPlannedOnlyTurnsPaidOff() throws {
        let rent = try line(try month(), "Rent")
        let paid = saved(rent, id: 40, amount: -1650, on: LocalDay("2026-11-01")!)
        let draft = LineDraft.unpaid(paid, today: today)
        var expected = LineDraft(paid, today: today)
        expected.paid = false
        #expect(draft == expected)
        #expect(draft.notes == "kept" && draft.categoryId == 5)
        let sent = try body(paid, draft)
        #expect(sent["is_actual"] == false as AnyHashable)
        #expect(sent["amount"] == -1650 as AnyHashable)
        #expect(sent["forecast_amount"] == -1650 as AnyHashable)
        #expect(sent["forecast_date"] == AnyHashable("2026-11-01"))
        #expect(sent["actual_date"] == AnyHashable("null"))
        #expect(sent["notes"] == AnyHashable("kept") && sent["category_id"] == 5 as AnyHashable)
        #expect(sent["recurring_id"] == 2 as AnyHashable)
    }

    @Test func undoingALinePaidAtAnotherAmountGoesBackToThePlannedOne() throws {
        let rent = try line(try month(), "Rent")
        let paid = saved(rent, id: 41, amount: Decimal(string: "-1700.25")!, on: LocalDay("2026-11-02")!)
        let draft = LineDraft.unpaid(paid, today: today)
        #expect(!draft.paid && draft.problem == nil)
        let sent = try body(paid, draft)
        #expect(sent["is_actual"] == false as AnyHashable)
        #expect(sent["amount"] == -1650 as AnyHashable, "the planned amount, not the one paid")
        #expect(sent["actual_date"] == AnyHashable("null"))
        #expect(sent["notes"] == AnyHashable("kept"))
    }

    // MARK: Finding the line again

    @Test func aSavedLineIsFoundByItsTransaction() throws {
        let month = try month()
        let store = try line(month, "Department store")
        #expect(store.transactionId == 5)
        #expect(month.reloaded(store) == store)
    }

    @Test func aProjectedDateThatBecameATransactionIsFoundByItsBillAndDate() throws {
        let before = try month()
        // Two paychecks come from the same bill: the date picks the right one.
        let second = try line(before, "Paycheck", at: 1)
        #expect(second.isProjection && second.recurringId == 1 && second.plannedDate == LocalDay("2026-11-25"))
        let paid = saved(second, id: 42, amount: 2800, on: today)
        let rows = before.rows.map { $0.id == second.id ? paid : $0 }
        let after = ForecastMonth(openingBalance: before.openingBalance, forecastEndingBalance: before.forecastEndingBalance,
                                  actualEndingBalance: before.actualEndingBalance, currentBalance: before.currentBalance, rows: rows)
        let found = try #require(after.reloaded(second))
        #expect(found == paid && found.transactionId == 42 && found.isPaid)
        let first = try line(before, "Paycheck", at: 0)
        #expect(after.reloaded(first)?.plannedDate == LocalDay("2026-11-11"), "the other date is untouched")
    }

    @Test func aLineThatIsGoneIsNotFound() throws {
        let before = try month()
        let rent = try line(before, "Rent")
        let rows = before.rows.filter { $0.id != rent.id }
        let after = ForecastMonth(openingBalance: before.openingBalance, forecastEndingBalance: before.forecastEndingBalance,
                                  actualEndingBalance: before.actualEndingBalance, currentBalance: before.currentBalance, rows: rows)
        #expect(after.reloaded(rent) == nil)
        let store = try line(before, "Department store")
        #expect(after.reloaded(saved(store, id: 999, amount: -1, on: today)) == nil, "no such transaction")
    }
}
