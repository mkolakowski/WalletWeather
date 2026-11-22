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

    /// On the day it was recorded, the household gives the demo server's
    /// own answers (the recorded samples the decoding tests use), worked out
    /// by the core instead of copied (#234).
    @Test func theHouseholdGivesTheRecordedAnswers() throws {
        let day = Demo.recordedDay
        let pairs: [(Data, String)] = [
            (try Demo.dashboard(today: day), "dashboard"),
            (try Demo.charts(window: "month", today: day), "charts-month"),
            (try Demo.charts(window: "90d", today: day), "charts-90d"),
            (try Demo.forecast(account: 1, start: YearMonth(day).start, end: day.endOfMonth, today: day), "forecast"),
            (try Demo.calendar(account: nil, start: YearMonth(day).start, end: day.endOfMonth, today: day), "calendar-all"),
            (try Demo.calendar(account: 1, start: YearMonth(day).start, end: day.endOfMonth, today: day), "calendar-checking"),
            (try Demo.accounts(today: day), "accounts"),
        ]
        for (computed, name) in pairs {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
            let recorded = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            let problems = Self.differences(try JSONSerialization.jsonObject(with: computed), recorded, missingIsFine: Self.newerFields)
            #expect(problems.isEmpty, "\(name): \(problems.prefix(5).joined(separator: "; "))")
        }
    }

    /// Fields servers added after the samples were recorded (bank sync,
    /// #196, #209, #223).
    static let newerFields: Set<String> = ["bank_unmatched_count", "bank_match", "match_source", "bank_unmatched"]

    @Test func everyAccountsForecastAgreesWithItsCalendar() async throws {
        let today = LocalDay.today()
        for account in 1...3 {
            let month = try await client.forecast(account: account, month: YearMonth(today), today: today)
            let calendar = try await client.calendar(YearMonth(today), account: account)
            #expect(calendar.balance(on: today.endOfMonth) == month.actualEndingBalance)
        }
        let savings = try await client.forecast(account: 2, month: YearMonth(today), today: today)
        #expect(savings.rows.isEmpty)
        #expect(savings.openingBalance == Money(Decimal(18500)))
    }

    @Test func datesFollowToday() async throws {
        let forecast = try await client.forecast(account: 1, month: YearMonth(march), today: march)
        #expect(!forecast.rows.isEmpty)
        #expect(forecast.rows.allSatisfy { $0.forecastDate.map { YearMonth($0) == YearMonth(march) } ?? true })
        let dashboard = try await client.dashboard(today: march)
        #expect(dashboard.cards.first?.monthLabel == "March 2027")
        // The household moves by days, so its lines stay in the past.
        let cleared = forecast.rows.filter(\.isActualReal)
        #expect(cleared.allSatisfy { ($0.actualDate ?? march) <= march })
        // The recorded samples still move by whole months; November 30 has
        // no February match, so the month's last day.
        let shifted = Demo.shift(Data(#"{"d":"2026-11-30","m":"November 2026"}"#.utf8), by: 3)
        #expect(String(decoding: shifted, as: UTF8.self) == #"{"d":"2027-02-28","m":"February 2027"}"#)
        let days = Demo.shift(Data(#"{"d":"2026-11-15"}"#.utf8), days: 106)
        #expect(String(decoding: days, as: UTF8.self) == #"{"d":"2027-03-01"}"#)
    }

    /// Where two JSON values differ: numbers to a billionth, everything else
    /// exactly. Keys in `missingIsFine` may be absent from the recording.
    static func differences(_ got: Any, _ want: Any, path: String = "$", missingIsFine: Set<String> = []) -> [String] {
        switch (got, want) {
        case let (g as [String: Any], w as [String: Any]):
            let extra = Set(g.keys).subtracting(w.keys).subtracting(missingIsFine)
            if !extra.isEmpty || !Set(w.keys).subtracting(g.keys).isEmpty { return ["\(path): keys differ \(extra)"] }
            return w.keys.sorted().flatMap { differences(g[$0]!, w[$0]!, path: "\(path).\($0)", missingIsFine: missingIsFine) }
        case let (g as [Any], w as [Any]):
            guard g.count == w.count else { return ["\(path): \(g.count) items != \(w.count)"] }
            return zip(g, w).enumerated().flatMap { differences($1.0, $1.1, path: "\(path)[\($0)]", missingIsFine: missingIsFine) }
        case let (g as NSNumber, w as NSNumber):
            let isBool = { (n: NSNumber) in CFGetTypeID(n) == CFBooleanGetTypeID() }
            if isBool(g) || isBool(w) { return g == w && isBool(g) == isBool(w) ? [] : ["\(path): \(g) != \(w)"] }
            return abs(g.doubleValue - w.doubleValue) <= 1e-9 ? [] : ["\(path): \(g) != \(w)"]
        case let (g as String, w as String):
            return g == w ? [] : ["\(path): \(g) != \(w)"]
        case (is NSNull, is NSNull):
            return []
        default:
            return ["\(path): \(got) != \(want)"]
        }
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

    @Test func bankSyncShowsASampleStatusAndSyncNowSavesNothing() async throws {
        let status = try #require(try await client.bankStatus())
        #expect(status.enabled && status.connected && status.lastSyncOk == true)
        let last = try #require(BankStatus.date(status.lastSyncAt))
        let next = try #require(BankStatus.date(status.nextSyncAt))
        // Made from now, so never moved by months like the sample dates.
        #expect(last < .now && Date.now.timeIntervalSince(last) < 24 * 3600)
        #expect(next > .now)
        let summary = status.summary(when: { _ in "earlier" })
        #expect(summary.tone == .ok && summary.canSync && summary.headline == "Synced earlier")
        // Two connections, one through SimpleFIN and one through Teller (#257).
        let rows = status.connectionRows(when: { _ in "earlier" })
        #expect(rows.map(\.provider) == ["SimpleFIN", "Teller"])
        #expect(rows.allSatisfy { $0.summary.tone == .ok && $0.summary.canSync })
        // One account shared by someone else's connection, ticked for Teller (#267).
        #expect(status.mayConnectInApp)
        let shared = try #require(status.shared?.first)
        #expect(shared.accountName == "Credit Card" && shared.from == "Synced from Sam's Plaid connection")
        let sharedSummary = shared.summary(when: { _ in "earlier" })
        #expect(sharedSummary.tone == .ok && sharedSummary.canSync)
        await #expect(throws: APIError.demoReadOnly) { _ = try await client.syncBankNow() }
        await #expect(throws: APIError.demoReadOnly) { _ = try await client.syncBankNow(connection: 2) }
        await #expect(throws: APIError.demoReadOnly) { _ = try await client.syncBankNow(account: 3) }
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
