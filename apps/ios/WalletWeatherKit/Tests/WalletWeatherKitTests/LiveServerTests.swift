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
