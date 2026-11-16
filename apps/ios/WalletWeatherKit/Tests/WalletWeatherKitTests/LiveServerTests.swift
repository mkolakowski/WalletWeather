import Foundation
import Testing
@testable import WalletWeatherKit

/// Against a real server, only when one is given (a demo server is fine):
///   WW_LIVE_SERVER=http://localhost:8300 WW_LIVE_TOKEN=ww_… swift test
/// The token is ended by the test, so give it a throwaway one.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_TOKEN"] != nil))
struct LiveServerTests {
    @Test func signingOutEndsTheToken() async throws {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        let client = APIClient(connection: Connection(server: server, token: env["WW_LIVE_TOKEN"]))
        _ = try await client.me()
        try await client.endToken()
        await #expect(throws: APIError.tokenRevoked) { _ = try await client.me() }
    }
}

/// The Forecast page's changes (#88) against a real server, only when one
/// is given (a demo server; it changes that server's data):
///   WW_LIVE_SERVER=http://localhost:8300 WW_LIVE_EDIT_TOKEN=ww_… swift test
/// Uses the first account it may edit, in this month.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_EDIT_TOKEN"] != nil), .serialized)
struct LiveForecastTests {
    let client: APIClient
    let today = LocalDay.today()
    let month = YearMonth(.today())

    init() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        client = APIClient(connection: Connection(server: server, token: env["WW_LIVE_EDIT_TOKEN"]))
    }

    func editableAccount() async throws -> Account {
        let me = try await client.me()
        #expect(!me.isReadOnly)
        return try #require(try await client.accounts().first(where: \.canEdit))
    }

    @Test func markAProjectionPaidThenUndoIt() async throws {
        let account = try await editableAccount()
        let before = try await client.forecast(account: account.id, month: month)
        let line = try #require(before.rows.first { $0.isProjection && !$0.isTransfer })
        var draft = LineDraft.paidAsPlanned(line, today: today)
        draft.amountText = amountString(abs(line.plannedAmount.amount) + 1)
        try await client.save(line, draft: draft, account: account.id)

        let paid = try #require(try await client.forecast(account: account.id, month: month).rows.first {
            $0.recurringId == line.recurringId && $0.forecastDate == line.forecastDate })
        #expect(paid.isPaid && !paid.isProjection)
        #expect(paid.categoryId == line.categoryId)
        #expect(abs(paid.amount.amount) == abs(line.plannedAmount.amount) + 1)
        #expect(paid.differsFromPlan)

        try await client.save(paid, draft: .unpaid(paid, today: today), account: account.id)
        let undone = try #require(try await client.forecast(account: account.id, month: month).rows.first { $0.id == paid.id })
        #expect(!undone.isPaid && undone.amount == line.plannedAmount && undone.categoryId == line.categoryId)
    }

    @Test func addThenDeleteAOneOff() async throws {
        let account = try await editableAccount()
        var draft = NewTransactionDraft(today: today)
        draft.name = "Live test \(UUID().uuidString.prefix(6))"
        draft.amountText = "3.21"
        try await client.add(draft, account: account.id)
        let found = try await client.searchTransactions(draft.name)
        let hit = try #require(found.results.first)
        #expect(found.total == 1 && hit.amount == Money(Decimal(string: "-3.21")!) && hit.isActual)
        try await client.delete(hit.line)
        #expect(try await client.searchTransactions(draft.name).total == 0)
    }
}

/// Bills & income and moving money (#89) against a real server, only when
/// one is given (a demo server; it changes that server's data):
///   WW_LIVE_SERVER=http://localhost:8300 WW_LIVE_EDIT_TOKEN=ww_… swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_EDIT_TOKEN"] != nil), .serialized)
struct LiveBillsTests {
    let client: APIClient
    let today = LocalDay.today()

    init() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        client = APIClient(connection: Connection(server: server, token: env["WW_LIVE_EDIT_TOKEN"]))
    }

    @Test func addSkipThenEndABill() async throws {
        let account = try #require(try await client.accounts().first(where: \.canEdit))
        var draft = BillDraft(today: today)
        draft.name = "Live bill \(UUID().uuidString.prefix(6))"
        draft.amountText = "12.34"
        draft.frequency = .weekly
        try await client.addRecurring(draft, account: account.id)
        let added = try #require(try await client.recurring(account: account.id).items.first { $0.description == draft.name })
        #expect(added.amount == Money(Decimal(string: "-12.34")!) && added.nextDate == today && added.nextDates.count == 6)

        try await client.skip(added, on: added.nextDates[0])
        let skipped = try #require(try await client.recurring(account: account.id).items.first { $0.id == added.id })
        #expect(skipped.nextDate == added.nextDates[1])

        // It shows on the Calendar on its next date.
        let month = YearMonth(added.nextDates[1])
        let cal = try await client.calendar(month, account: account.id)
        #expect(cal.events(on: added.nextDates[1]).contains { $0.recurringId == added.id })

        let yesterday = LocalDay.today(now: Date().addingTimeInterval(-86_400))
        try await client.updateRecurring(added.id, RecurringBody(ending: skipped, after: yesterday))
        #expect(try await client.recurring(account: account.id).items.contains { $0.id == added.id } == false)
        #expect(try await client.recurring(account: account.id, ended: true).items.contains { $0.id == added.id })
    }

    @Test func moveMoney() async throws {
        let editable = try await client.accounts().filter(\.canEdit)
        try #require(editable.count >= 2)
        var draft = MoveMoneyDraft(today: today, from: editable[0].id, to: editable[1].id)
        draft.amountText = "1.23"
        let moved = try await client.moveMoney(try #require(TransferBody(draft)))
        #expect(moved.amount == Money(Decimal(string: "1.23")!) && moved.toAccountName == editable[1].name)
        let rows = try await client.forecast(account: editable[1].id, month: YearMonth(today)).rows
        #expect(rows.contains { $0.isTransfer && $0.isPaid && $0.amount == moved.amount })
    }
}

/// The More pages (#91) against a real server, only when one is given;
/// reads only.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_EDIT_TOKEN"] != nil))
struct LiveMoreTests {
    @Test func netWorthBudgetsAndReports() async throws {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        let client = APIClient(connection: Connection(server: server, token: env["WW_LIVE_EDIT_TOKEN"]))
        for window in ChartWindow.allCases {
            let worth = try await client.netWorth(window)
            #expect(worth.window == window && worth.trend.last?.date == worth.end)
        }
        let month = YearMonth(.today())
        let budgets = try await client.budgets()
        #expect(budgets.label == month.label)
        if let report = try await client.savedReports().first {
            #expect(try await client.runReport(report.id).rangeLabel.isEmpty == false)
        }
    }
}

/// Email and password sign-in (#100) against a real server, only when one is
/// given (a demo server: its admin login is public):
///   WW_LIVE_SERVER=http://localhost:8300 WW_LIVE_EMAIL=… WW_LIVE_PASSWORD=… swift test
/// The token it makes is ended straight away. The wrong-password try counts
/// toward the server's sign-in limit for that email.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_PASSWORD"] != nil), .serialized)
struct LivePasswordSignInTests {
    let server: URL
    let email: String
    let password: String

    init() throws {
        let env = ProcessInfo.processInfo.environment
        server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        email = try #require(env["WW_LIVE_EMAIL"])
        password = try #require(env["WW_LIVE_PASSWORD"])
    }

    @Test func signsInAndEndsTheToken() async throws {
        let issued = try await APIClient(connection: Connection(server: server))
            .signIn(email: email.uppercased(), password: password, deviceName: "Live test phone")
        #expect(issued.name == "Live test phone")
        #expect(issued.access == "full")
        #expect(issued.expiresAt != nil)
        let client = APIClient(connection: Connection(server: server, token: issued.token))
        #expect(try await client.me().email == email.lowercased())
        try await client.endToken()
        await #expect(throws: APIError.tokenRevoked) { _ = try await client.me() }
    }

    @Test func aWrongPasswordIsRefused() async {
        await #expect(throws: APIError.wrongPassword) {
            _ = try await APIClient(connection: Connection(server: server))
                .signIn(email: email, password: password + "-wrong", deviceName: "Live test phone")
        }
    }
}
