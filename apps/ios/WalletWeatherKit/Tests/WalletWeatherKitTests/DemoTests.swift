import Foundation
import Testing
@testable import WalletWeatherKit

/// "Try the demo" (#92): every page's request answers from the samples
/// built into the app, decoded by the same models as a real server's,
/// with dates moved to the month asked for, nothing saved and nothing kept.
struct DemoTests {
    let client = APIClient(connection: Demo.connection)
    let november = LocalDay(year: 2026, month: 11, day: 15)
    let march = LocalDay(year: 2027, month: 3, day: 15)

    @Test func everyPageAnswers() async throws {
        #expect(try await client.checkServer().appVersion.isEmpty == false)
        #expect(try await client.me().noticeRequired == false)
        let accounts = try await client.accounts(today: november)
        #expect(accounts.count == 3)
        #expect(try await client.dashboard(today: november).cards.count == 3)
        for window in ChartWindow.allCases {
            _ = try await client.charts(window, today: november)
            _ = try await client.netWorth(window, today: november)
        }
        _ = try await client.budgets(today: november)
        let reports = try await client.savedReports()
        #expect(!reports.isEmpty)
        _ = try await client.runReport(reports[0].id, today: november)
        #expect(!(try await client.categories()).isEmpty)
        for account in accounts {
            _ = try await client.forecast(account: account.id, month: YearMonth(november), today: november)
            _ = try await client.calendar(YearMonth(november), account: account.id)
        }
        _ = try await client.calendar(YearMonth(november))
        #expect(try await client.recurring(today: november).items.count == 7)
        #expect(try await client.recurring(ended: true, today: november).items.isEmpty)
    }

    @Test func anotherAccountsForecastIsBuiltFromTheCalendar() async throws {
        let card = try await client.forecast(account: 3, month: YearMonth(november), today: november)
        let calendar = try await client.calendar(YearMonth(november), account: 3)
        #expect(!card.rows.isEmpty)
        #expect(card.rows.count == calendar.events.count)
        #expect(calendar.balance(on: november.endOfMonth) == card.actualEndingBalance)
        let savings = try await client.forecast(account: 2, month: YearMonth(november), today: november)
        #expect(savings.rows.isEmpty)
        #expect(savings.openingBalance == Money(Decimal(18500)))
    }

    @Test func datesMoveToTheMonthAskedFor() async throws {
        let forecast = try await client.forecast(account: 1, month: YearMonth(march), today: march)
        #expect(!forecast.rows.isEmpty)
        #expect(forecast.rows.allSatisfy { $0.forecastDate.map { YearMonth($0) == YearMonth(march) } ?? true })
        let dashboard = try await client.dashboard(today: march)
        #expect(dashboard.cards.first?.monthLabel == "March 2027")
        // November 30 has no February match: the month's last day.
        let shifted = Demo.shift(Data(#"{"d":"2026-11-30","m":"November 2026"}"#.utf8), by: 3)
        #expect(String(decoding: shifted, as: UTF8.self) == #"{"d":"2027-02-28","m":"February 2027"}"#)
    }

    @Test func billsForOneAccountHaveTheirOwnTotals() async throws {
        let card = try await client.recurring(account: 3, today: november)
        #expect(card.items.allSatisfy { $0.accountId == 3 })
        #expect(card.totals.billsCount == card.items.count)
        #expect(card.totals.incomeCount == 0)
    }

    @Test func searchFindsWhatContainsTheText() async throws {
        let found = try await client.search("rent")
        #expect(found.recurring.results.map(\.description) == ["Rent"])
        #expect(try await client.search("gym").recurring.results.count == 1)
        #expect(try await client.search("savings").accounts.results.map(\.name) == ["Savings"])
        let groceries = try await client.searchTransactions("grocery")
        #expect(groceries.total == groceries.results.count && groceries.total > 0)
        let byCategory = try await client.transactions(.category(1))
        #expect(!byCategory.results.isEmpty)
        #expect(byCategory.results.allSatisfy { $0.categoryId == 1 })
    }

    @Test func editingSaysTheDemoSavesNothing() async throws {
        let day = november
        await #expect(throws: APIError.demoReadOnly) {
            try await client.skip(try await client.recurring(today: day).items[0], on: day)
        }
        await #expect(throws: APIError.demoReadOnly) { try await client.acknowledgeNotice() }
        await #expect(throws: APIError.demoReadOnly) { try await client.endToken() }
        #expect(APIError.demoReadOnly.message.contains("doesn't save changes"))
    }

    @Test func nothingIsKept() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "demo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let keeper = KeptResponses(directory: folder)
        let kept = APIClient(connection: Demo.connection, keeper: keeper)
        _ = try await kept.dashboard(today: november)
        let key = KeptResponses.key(server: Demo.server, method: "GET", path: "/api/dashboard",
                                    query: ["today": november.description])
        #expect(keeper.load(key) == nil)
        #expect(Demo.connection.isDemo)
        #expect(!Connection(server: URL(string: "https://example.com")!).isDemo)
    }
}
