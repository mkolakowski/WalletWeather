import Foundation
import Testing
@testable import WalletWeatherKit

/// Tap through (#305): an account's coming lines for the Dashboard's right
/// half, and finding a Calendar line again in the account's Forecast.
struct TapThroughTests {
    func forecast() throws -> ForecastMonth { try DecodingTests().sample("forecast") }
    func calendar() throws -> CalendarMonth { try DecodingTests().sample("calendar-all") }

    func day(_ text: String) -> LocalDay { LocalDay(text)! }

    /// A bare line, for a month the samples don't have.
    func line(_ name: String, on date: String, paid: Bool = false, recurring: Int? = nil, transaction: Int? = nil) -> ForecastLine {
        ForecastLine(forecastDate: day(date), actualDate: day(date), description: name, category: nil, categoryId: nil, notes: nil,
                     forecastAmount: Money(Decimal(-10)), forecastBalance: .zero, actualAmount: Money(Decimal(-10)), actualBalance: .zero,
                     diffAmount: nil, diffBalance: .zero, isActualReal: paid, recurringId: recurring,
                     transactionId: transaction, transferId: nil)
    }

    func month(_ rows: [ForecastLine]) -> ForecastMonth {
        ForecastMonth(openingBalance: .zero, forecastEndingBalance: .zero, actualEndingBalance: .zero, currentBalance: .zero, rows: rows)
    }

    // MARK: Coming up

    @Test func comingUpIsUnpaidFromTodayEarliestFirst() throws {
        let coming = try forecast().comingUp(today: day("2026-11-12"))
        // Paid lines and the days before today are out; the paycheck on the
        // 11th has passed and so has the rent.
        #expect(coming.map(\.description) == ["Electric", "Streaming service", "Internet", "Paycheck"])
        #expect(coming.map { $0.plannedDate?.description } == ["2026-11-12", "2026-11-15", "2026-11-18", "2026-11-25"])
        #expect(coming.allSatisfy { !$0.isPaid })
    }

    @Test func comingUpIncludesTodayAndSkipsPaidLinesOnIt() throws {
        let coming = try forecast().comingUp(today: day("2026-11-11"))
        #expect(coming.first?.description == "Paycheck")          // unpaid, today
        #expect(!coming.contains { $0.description == "Gas station" })  // paid, today
    }

    @Test func comingUpStopsAtFiveAndKeepsTheEarliest() throws {
        let many = month((1...9).map { line("Bill \($0)", on: String(format: "2026-11-%02d", 10 + $0), recurring: $0) })
        let coming = many.comingUp(today: day("2026-11-10"))
        #expect(coming.map(\.description) == ["Bill 1", "Bill 2", "Bill 3", "Bill 4", "Bill 5"])
        #expect(many.comingUp(today: day("2026-11-10"), limit: 2).count == 2)
    }

    @Test func comingUpOrdersByDateWhateverOrderTheRowsCameIn() throws {
        let shuffled = month([line("Late", on: "2026-11-20", recurring: 1), line("Early", on: "2026-11-14", recurring: 2),
                              line("Same day", on: "2026-11-14", recurring: 3)])
        #expect(shuffled.comingUp(today: day("2026-11-01")).map(\.description) == ["Early", "Same day", "Late"])
    }

    @Test func comingUpRunsOnIntoNextMonthWhenFewerThanFiveAreLeft() throws {
        let november = try forecast()
        let december = month([line("Rent", on: "2026-12-01", recurring: 2), line("Gym", on: "2026-12-05", recurring: 5),
                              line("Done", on: "2026-12-06", paid: true, transaction: 70), line("Electric", on: "2026-12-12", recurring: 3)])
        let coming = november.comingUp(today: day("2026-11-12"), following: december)
        #expect(coming.map(\.description) == ["Electric", "Streaming service", "Internet", "Paycheck", "Rent"])
        #expect(coming.last?.plannedDate == day("2026-12-01"))
        // Without next month's lines, only this month's.
        #expect(november.comingUp(today: day("2026-11-12")).count == 4)
    }

    @Test func comingUpIgnoresNextMonthWhenThisOneHasFiveAlready() throws {
        let november = month((1...5).map { line("Now \($0)", on: "2026-11-\(20 + $0)", recurring: $0) })
        let december = month([line("Later", on: "2026-12-01", recurring: 9)])
        #expect(november.comingUp(today: day("2026-11-20"), following: december).map(\.description)
                == (1...5).map { "Now \($0)" })
    }

    @Test func comingUpIsEmptyWhenEverythingIsPaid() throws {
        let done = month([line("Paid", on: "2026-11-20", paid: true, transaction: 3)])
        #expect(done.comingUp(today: day("2026-11-01")).isEmpty)
    }

    // MARK: A Calendar line in a Forecast month

    @Test func aSavedLineIsFoundByItsTransaction() throws {
        let calendar = try calendar()
        let store = try #require(calendar.events.first { $0.description == "Department store" })
        let found = try #require(try forecast().line(for: store))
        #expect(found.transactionId == 5 && found.description == "Department store" && found.isPaid)
    }

    @Test func aProjectedLineIsFoundByItsBillAndDate() throws {
        let calendar = try calendar()
        // The Calendar has two paychecks, the 11th and the 25th, from one bill.
        let second = try #require(calendar.events.last { $0.description == "Paycheck" })
        #expect(second.transactionId == nil && second.recurringId == 1)
        let found = try #require(try forecast().line(for: second))
        #expect(found.recurringId == 1 && found.plannedDate == day("2026-11-25") && found.isProjection)
        let first = try #require(calendar.events.first { $0.description == "Paycheck" })
        #expect(try forecast().line(for: first)?.plannedDate == day("2026-11-11"))
    }

    @Test func aLineNotInTheMonthIsNotFound() throws {
        let calendar = try calendar()
        // Another account's line: its transaction and its bill are not in Checking's month.
        let movie = try #require(calendar.events.first { $0.description == "Movie theater" })
        #expect(try forecast().line(for: movie) == nil)
        let phone = try #require(calendar.events.first { $0.description == "Phone bill" })
        #expect(try forecast().line(for: phone) == nil)
        // A bill on a date it has no line for.
        let gone = month(try forecast().rows.filter { $0.recurringId != 3 })
        let electric = try #require(calendar.events.first { $0.description == "Electric" })
        #expect(gone.line(for: electric) == nil)
    }

    @Test func aTransactionIdIsNotMatchedByTheBillBehindIt() throws {
        // A saved line that's no longer there isn't swapped for the bill's projected date.
        let calendar = try calendar()
        let store = try #require(calendar.events.first { $0.description == "Department store" })
        let without = month(try forecast().rows.filter { $0.transactionId != 5 })
        #expect(without.line(for: store) == nil)
    }

    @Test func aTransferLegIsFoundByItsTransaction() throws {
        let leg = line("Transfer", on: "2026-11-09", paid: true, transaction: 31)
        let transfer = ForecastLine(forecastDate: leg.forecastDate, actualDate: leg.actualDate, description: "Transfer", category: nil,
                                    categoryId: nil, notes: nil, forecastAmount: Money(Decimal(-100)), forecastBalance: .zero,
                                    actualAmount: Money(Decimal(-100)), actualBalance: .zero, diffAmount: nil, diffBalance: .zero,
                                    isActualReal: true, recurringId: nil, transactionId: 31, transferId: 8)
        let event = try APIClient.decoder().decode(CalendarEvent.self, from: Data("""
        {"date":"2026-11-09","account_id":1,"account_name":"Checking","description":"Transfer","amount":-100,
         "recurring_id":null,"transaction_id":31,"transfer_id":8,"is_actual_real":true,"notes":null}
        """.utf8))
        let found = try #require(month([transfer]).line(for: event))
        #expect(found.isTransfer && found.transactionId == 31)
    }

    @Test func theMonthsToLookInAreItsOwnThenTheNeighbours() throws {
        let calendar = try calendar()
        let rent = try #require(calendar.events.first)
        #expect(rent.forecastMonths == [YearMonth(year: 2026, month: 11), YearMonth(year: 2026, month: 10), YearMonth(year: 2026, month: 12)])
    }
}
