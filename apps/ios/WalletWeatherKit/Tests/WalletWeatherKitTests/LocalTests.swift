import Foundation
import Testing
@testable import WalletWeatherKit

/// Using the app on this iPhone, without a server (Plans/standalone.md,
/// phase 4, #235): a household set up from nothing and edited through the
/// same `APIClient` calls the pages make, answered on the phone from the
/// store through the core, and nothing sent over the network.
struct LocalTests {
    let server: LocalServer
    let client: APIClient
    let day = LocalDay(year: 2026, month: 3, day: 10)

    init() throws {
        server = try LocalServer.inMemory()
        client = APIClient(connection: server.connection)
    }

    private func account(_ name: String, _ balance: Double, starting: LocalDay? = nil) async throws -> Int {
        try await client.createAccount(AccountBody(name: name, startingBalance: balance, startingDate: starting ?? day)).id
    }

    private func bill(_ name: String, _ amount: String, day of: Int, account: Int, income: Bool = false) async throws {
        var draft = BillDraft(today: day)
        draft.name = name
        draft.amountText = amount
        draft.kind = income ? .income : .spending
        draft.dayOfMonth = of
        try await client.addRecurring(draft, account: account)
    }

    private func spend(_ name: String, _ amount: String, on date: LocalDay, account: Int, notes: String = "") async throws {
        var draft = NewTransactionDraft(today: date)
        draft.name = name
        draft.amountText = amount
        draft.notes = notes
        try await client.add(draft, account: account)
    }

    @Test func aNewHouseholdStartsEmptyWithTheServersCategories() async throws {
        #expect(try await client.checkServer().appVersion == LocalServer.answersAs)
        #expect(try await client.accounts(today: day).isEmpty)
        #expect(try await client.dashboard(today: day).cards.isEmpty)
        #expect(try await client.recurring(today: day).items.isEmpty)
        let categories = try await client.categories()
        #expect(categories.map(\.name).sorted() == LocalStore.defaultCategories.map(\.0).sorted())
        // The Important notice is asked once, as after signing up on the web.
        #expect(try await client.me().noticeRequired)
        try await client.acknowledgeNotice()
        #expect(try await client.me().noticeRequired == false)
    }

    @Test func aHouseholdIsSetUpAndEdited() async throws {
        let checking = try await account("Checking", 1000)
        let savings = try await account("Savings", 5000)
        try await bill("Rent", "800", day: 1, account: checking)
        try await bill("Pay", "2000", day: 15, account: checking, income: true)
        try await spend("Coffee", "4.50", on: day, account: checking, notes: "with Sam")

        let accounts = try await client.accounts(today: day)
        #expect(accounts.map(\.name) == ["Checking", "Savings"])
        #expect(accounts.allSatisfy { $0.level == "owner" })
        // As on the server: a monthly bill with no start date shows from the
        // month's start, and an unpaid line before today counts at its
        // planned amount. 1000 - 800 rent (the 1st) - 4.50.
        #expect(accounts[0].currentBalance == Money(Decimal(string: "195.5")!))

        let march = try await client.forecast(account: checking, month: YearMonth(day), today: day)
        #expect(march.rows.map(\.description) == ["Rent", "Coffee", "Pay"])
        let april = try await client.forecast(account: checking, month: YearMonth(day).next, today: day)
        #expect(april.rows.map(\.description) == ["Rent", "Pay"])
        // A month opens on the saved lines before it (1000 - 4.50).
        #expect(april.openingBalance == Money(Decimal(string: "995.5")!))
        #expect(april.forecastEndingBalance == Money(Decimal(string: "2195.5")!))

        let bills = try await client.recurring(today: day)
        #expect(bills.items.map(\.description) == ["Pay", "Rent"])
        #expect(bills.totals.billsMonthly == Money(Decimal(800)))
        #expect(bills.totals.netMonthly == Money(Decimal(1200)))
        let rent = try #require(bills.items.first { $0.description == "Rent" })
        #expect(rent.nextDate == LocalDay(year: 2026, month: 4, day: 1))

        // Skip April's rent, then mark May's paid at a different amount.
        try await client.skip(rent, on: LocalDay(year: 2026, month: 4, day: 1))
        let skipped = try await client.forecast(account: checking, month: YearMonth(day).next, today: day)
        #expect(skipped.rows.map(\.description) == ["Pay"])
        let may = try await client.forecast(account: checking, month: YearMonth(year: 2026, month: 5), today: day)
        let mayRent = try #require(may.rows.first { $0.description == "Rent" })
        var paid = LineDraft(mayRent, today: day)
        paid.paid = true
        paid.amountText = "810"
        paid.paidOn = LocalDay(year: 2026, month: 5, day: 2)
        try await client.save(mayRent, draft: paid, account: checking)
        let mayAfter = try await client.forecast(account: checking, month: YearMonth(year: 2026, month: 5), today: day)
        let saved = try #require(mayAfter.rows.first { $0.description == "Rent" })
        #expect(saved.isPaid && saved.transactionId != nil)
        #expect(saved.actualAmount == Money(Decimal(-810)))

        // Deleting that line skips its date rather than projecting it again.
        try await client.delete(saved)
        let mayGone = try await client.forecast(account: checking, month: YearMonth(year: 2026, month: 5), today: day)
        #expect(mayGone.rows.map(\.description) == ["Pay"])

        // Moving money is two paid lines.
        let move = try #require(TransferBody({
            var d = MoveMoneyDraft(today: day, from: checking, to: savings)
            d.amountText = "250"
            return d
        }()))
        let transfer = try await client.moveMoney(move)
        #expect(transfer.fromAccountName == "Checking" && transfer.toAccountName == "Savings")
        let after = try await client.accounts(today: day)
        #expect(after[0].currentBalance == Money(Decimal(string: "-54.5")!))
        #expect(after[1].currentBalance == Money(Decimal(5250)))

        // Ending a bill moves it to the ended list.
        try await client.updateRecurring(rent.id, RecurringBody(ending: rent, after: LocalDay(year: 2026, month: 3, day: 1)))
        #expect(try await client.recurring(today: day).items.map(\.description) == ["Pay"])
        #expect(try await client.recurring(ended: true, today: day).items.map(\.description) == ["Rent"])

        // Dashboard, its charts, the Calendar and both searches answer.
        #expect(try await client.dashboard(today: day).cards.count == 2)
        for window in ChartWindow.allCases { _ = try await client.charts(window, today: day) }
        let calendar = try await client.calendar(YearMonth(day))
        #expect(calendar.events.contains { $0.description == "Coffee" })
        _ = try await client.calendar(YearMonth(day), account: checking)
        #expect(try await client.searchTransactions("coffee").results.map(\.description) == ["Coffee"])
        #expect(try await client.searchTransactions("SAM").total == 1)
        #expect(try await client.search("sav").accounts.results.map(\.name) == ["Savings"])
        #expect(try await client.search("transfer").transactions.results.map(\.description).sorted() == ["← Transfer", "→ Transfer"])
        #expect(try await client.search("rent").recurring.results.map(\.description) == ["Rent"])
    }

    @Test func whatNeedsAServerSaysSo() async throws {
        // Bank sync reads as a server without it.
        #expect(try await client.bankStatus() == nil)
        for call in [{ _ = try await client.netWorth(.month, today: day) } as () async throws -> Void,
                     { _ = try await client.budgets(today: day) },
                     { _ = try await client.savedReports() }] {
            do {
                try await call()
                Issue.record("answered")
            } catch let error as APIError {
                guard case let .server(status, detail) = error else { Issue.record("\(error)"); continue }
                #expect(status == 404)
                #expect(detail.contains("needs a server"))
            }
        }
    }

    @Test func savingChecksWhatTheServerChecks() async throws {
        await #expect(throws: APIError.self) {
            try await client.createAccount(AccountBody(name: "  ", startingBalance: 0, startingDate: day))
        }
        let checking = try await account("Checking", 0)
        var weekly = BillDraft(today: day)
        weekly.name = "Gym"
        weekly.amountText = "10"
        weekly.frequency = .weekly
        try await client.addRecurring(weekly, account: checking)
        #expect(try await client.recurring(today: day).items.first?.anchorDate == day)
        do {
            try await client.add(NewTransactionDraft(today: day), account: 12345)
            Issue.record("saved to an account that isn't there")
        } catch let error as APIError {
            guard case let .server(status, _) = error else { Issue.record("\(error)"); return }
            #expect(status == 404)
        }
    }

    /// Done when: nothing is sent over the network in standalone. Every
    /// request the household's session doesn't answer itself is refused.
    @Test func nothingReachesTheNetwork() async throws {
        let before = RefuseProtocol.refused
        let checking = try await account("Checking", 100)
        try await bill("Rent", "50", day: 1, account: checking)
        try await spend("Lunch", "12", on: day, account: checking)
        _ = try await client.me()
        _ = try await client.accounts(today: day)
        _ = try await client.dashboard(today: day)
        _ = try await client.forecast(account: checking, month: YearMonth(day), today: day)
        _ = try await client.recurring(today: day)
        _ = try await client.calendar(YearMonth(day))
        _ = try await client.search("lunch")
        _ = try await client.searchTransactions("lunch")
        #expect(RefuseProtocol.refused == before)

        // Anything else the session is asked for fails, and is counted.
        let session = LocalServer.makeSession()
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: URL(string: "https://example.com/")!)
        }
        #expect(RefuseProtocol.refused == before + 1)
    }

    /// The household is still there after the app restarts.
    @Test func theStoreKeepsItsRowsOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ww-local-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = "disk\(UUID().uuidString.prefix(6).lowercased()).\(LocalServer.host)"
        do {
            let first = LocalServer(container: try LocalStore.container(at: folder), host: host)
            let (status, _) = first.answer(method: "POST", path: "/api/accounts", query: [:],
                                           body: try JSONEncoder().encode(AccountBody(name: "Kept", startingBalance: 1, startingDate: day)))
            #expect(status == 200)
        }
        let again = LocalServer(container: try LocalStore.container(at: folder), host: host)
        let (_, body) = again.answer(method: "GET", path: "/api/accounts", query: ["today": day.description], body: nil)
        let list = try APIClient.decoder().decode([Account].self, from: body)
        #expect(list.map(\.name) == ["Kept"])
    }

    @Test func theAccountFormReadsWhatsTyped() {
        var draft = AccountDraft(today: day)
        #expect(draft.problem == "Give the account a name.")
        draft.name = "Card"
        #expect(draft.balance == 0)
        draft.balanceText = "-1,250.50"
        #expect(draft.balance == Decimal(string: "-1250.5"))
        #expect(draft.body?.startingBalance == -1250.5)
        draft.balanceText = "lots"
        #expect(draft.problem != nil)
    }
}
