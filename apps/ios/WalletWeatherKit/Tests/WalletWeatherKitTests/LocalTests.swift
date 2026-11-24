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

    /// A search row names its category as the server's does, `category_name`
    /// (#330: the household hands the core `category`, which it renames).
    @Test func aSearchRowNamesItsCategory() async throws {
        let checking = try await account("Checking", 1000)
        let groceries = try #require(try await client.categories().first { $0.name == "Groceries" })
        var draft = NewTransactionDraft(today: day)
        draft.name = "Grocery store"
        draft.amountText = "84.20"
        draft.categoryId = groceries.id
        try await client.add(draft, account: checking)
        let hit = try #require(try await client.searchTransactions("grocery").results.first)
        #expect(hit.categoryName == "Groceries")
        #expect(hit.categoryId == groceries.id)
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

    /// A saved one-off's name, planned date and planned amount are fields
    /// (#316): the same client call renames, re-dates and re-prices it, and
    /// the Forecast puts it in its new place with the balances worked again.
    @Test func aSavedOneOffIsRenamedRedatedAndRepriced() async throws {
        let checking = try await account("Checking", 1000)
        let ahead = LocalDay(year: 2026, month: 3, day: 20)
        var plan = NewTransactionDraft(today: ahead)
        plan.name = "Haircut"
        plan.amountText = "40"
        plan.paid = false
        try await client.add(plan, account: checking)
        try await spend("Books", "10", on: LocalDay(year: 2026, month: 3, day: 25), account: checking)

        let month = YearMonth(day)
        let first = try await client.forecast(account: checking, month: month, today: day)
        #expect(first.rows.map(\.description) == ["Haircut", "Books"])
        let haircut = try #require(first.rows.first)
        #expect(haircut.isOneOff && !haircut.isPaid)

        var draft = LineDraft(haircut, today: day)
        draft.name = "Haircut and beard"
        draft.plannedOn = LocalDay(year: 2026, month: 3, day: 28)
        draft.plannedAmountText = "52.50"
        #expect(draft.problem == nil)
        try await client.save(haircut, draft: draft, account: checking)

        let after = try await client.forecast(account: checking, month: month, today: day)
        #expect(after.rows.map(\.description) == ["Books", "Haircut and beard"])
        let moved = try #require(after.rows.last)
        #expect(moved.transactionId == haircut.transactionId, "the same line, not a new one")
        #expect(moved.plannedDate == LocalDay(year: 2026, month: 3, day: 28))
        #expect(moved.plannedAmount == Money(Decimal(string: "-52.5")!))
        #expect(!moved.isPaid, "changing the plan doesn't mark it paid")
        // 1000 - 10 books, then - 52.50.
        #expect(after.rows[0].forecastBalance == Money(Decimal(990)))
        #expect(moved.forecastBalance == Money(Decimal(string: "937.5")!))
        #expect(after.forecastEndingBalance == Money(Decimal(string: "937.5")!))
        #expect(try await client.searchTransactions("beard").total == 1)
    }

    /// Undo after marking a line paid from the list (#315): the same calls
    /// the Forecast makes (save paid as planned, reload, find the line
    /// again, save it unpaid), for a projected date of a bill and for a
    /// saved one-off.
    @Test func undoingPaidPutsTheLineBackAtItsPlannedAmountAndDate() async throws {
        let checking = try await account("Checking", 1000)
        try await bill("Rent", "800", day: 1, account: checking)
        let ahead = LocalDay(year: 2026, month: 3, day: 20)
        var plan = NewTransactionDraft(today: ahead)
        plan.name = "Haircut"
        plan.amountText = "40"
        plan.notes = "tip"
        plan.paid = false
        try await client.add(plan, account: checking)
        let month = YearMonth(day)
        let start = try await client.forecast(account: checking, month: month, today: day)

        for name in ["Rent", "Haircut"] {
            let before = try #require(start.rows.first { $0.description == name })
            #expect(!before.isPaid)
            try await client.save(before, draft: .paidAsPlanned(before, today: day), account: checking)
            let paidMonth = try await client.forecast(account: checking, month: month, today: day)
            let paid = try #require(paidMonth.reloaded(before))
            #expect(paid.isPaid && paid.transactionId != nil, "\(name) is paid and saved")

            // Undo.
            try await client.save(paid, draft: .unpaid(paid, today: day), account: checking)
            let after = try await client.forecast(account: checking, month: month, today: day)
            let undone = try #require(after.reloaded(before), "\(name) is still there")
            #expect(!undone.isPaid, "\(name) is not paid")
            #expect(undone.plannedDate == before.plannedDate)
            #expect(undone.plannedAmount == before.plannedAmount)
            #expect(undone.actualAmount == before.plannedAmount, "an unpaid line counts at its planned amount")
            #expect(after.rows.filter { $0.description == name }.count == 1, "never a second copy")
        }
        let end = try await client.forecast(account: checking, month: month, today: day)
        let haircut = try #require(end.rows.first { $0.description == "Haircut" })
        #expect(haircut.notes == "tip" && haircut.isOneOff, "its notes stay")
        #expect(end.forecastEndingBalance == start.forecastEndingBalance)
    }

    /// Changing a transfer (#324): the server's `PATCH /api/transfers/{id}`
    /// changes both lines together, and its errors keep their shapes.
    @Test func aTransferCanBeChanged() async throws {
        let checking = try await account("Checking", 1000)
        let savings = try await account("Savings", 5000)
        let cash = try await account("Cash", 100)
        let move = try #require(TransferBody({
            var d = MoveMoneyDraft(today: day, from: checking, to: savings)
            d.amountText = "250"
            return d
        }()))
        let transfer = try await client.moveMoney(move)

        // The list gives the form what it fills in with.
        let listed = try await client.transfer(transfer.id)
        let draft = MoveMoneyDraft(changing: listed)
        #expect(draft.fromAccountId == checking && draft.toAccountId == savings)
        #expect(draft.amountText == "250" && draft.date == day && draft.description == "Transfer")
        #expect(try await client.transfers().total == 1)

        // Another amount, day, account and description: both lines follow.
        var changed = draft
        changed.amountText = "75.5"
        changed.date = day.adding(days: 2)
        changed.toAccountId = cash
        changed.description = "Pocket money"
        let saved = try await client.updateTransfer(transfer.id, try #require(TransferBody(changed)))
        #expect(saved.id == transfer.id && saved.amount == Money(Decimal(string: "75.5")!))
        #expect(saved.toAccountName == "Cash" && saved.transferDate == day.adding(days: 2))
        let after = try await client.accounts(today: day.adding(days: 2))
        #expect(after[0].currentBalance == Money(Decimal(string: "924.5")!))
        #expect(after[1].currentBalance == Money(Decimal(5000)))  // Savings is out of it now
        #expect(after[2].currentBalance == Money(Decimal(string: "175.5")!))
        let lines = try await client.search("pocket money").transactions.results
        #expect(lines.map(\.description).sorted() == ["← Pocket money", "→ Pocket money"])
        #expect(try await client.transfers().total == 1)  // changed, not duplicated

        // The server's errors: the same account on both sides, an amount of
        // nothing, and a transfer that isn't there.
        do {
            try await client.updateTransfer(transfer.id, TransferBody(from: checking, to: checking, amount: 75.5, on: day))
            Issue.record("moved money from an account to itself")
        } catch {
            guard case let .server(status, detail) = error else { Issue.record("\(error)"); return }
            #expect(status == 400 && detail == "from_account and to_account must differ")
        }
        do {
            try await client.updateTransfer(transfer.id, TransferBody(from: checking, to: cash, amount: 0, on: day))
            Issue.record("changed a transfer to an amount of nothing")
        } catch {
            guard case let .server(status, _) = error else { Issue.record("\(error)"); return }
            #expect(status == 400)
        }
        let again = try #require(TransferBody(changed))
        do {
            try await client.updateTransfer(transfer.id + 1000, again)
            Issue.record("changed a transfer that isn't there")
        } catch {
            guard case let .server(status, _) = error else { Issue.record("\(error)"); return }
            #expect(status == 404)
        }
        // Nothing above changed it.
        #expect(try await client.transfer(transfer.id).amount == Money(Decimal(string: "75.5")!))
    }

    /// Deleting a transfer and bringing back skipped dates (#246): the
    /// server's `DELETE /api/transfers/{id}` and `DELETE /api/recurring/{id}/skips`.
    @Test func aTransferCanBeDeletedAndSkippedDatesBroughtBack() async throws {
        let checking = try await account("Checking", 1000)
        let savings = try await account("Savings", 5000)
        try await bill("Rent", "800", day: 1, account: checking)
        let move = try #require(TransferBody({
            var d = MoveMoneyDraft(today: day, from: checking, to: savings)
            d.amountText = "250"
            return d
        }()))
        let transfer = try await client.moveMoney(move)

        // The transfer's lines say they are one, and deleting either takes both.
        let march = try await client.forecast(account: checking, month: YearMonth(day), today: day)
        let leg = try #require(march.rows.first { $0.isTransfer })
        #expect(leg.transferId == transfer.id)
        try await client.delete(leg)
        let after = try await client.accounts(today: day)
        #expect(after[0].currentBalance == Money(Decimal(200)))  // 1000 - 800 rent
        #expect(after[1].currentBalance == Money(Decimal(5000)))
        #expect(try await client.search("transfer").transactions.results.isEmpty)

        // Both lines are gone: an unknown transfer is a 404, as on the server.
        do {
            try await client.deleteTransfer(transfer.id)
            Issue.record("deleted a transfer that was already gone")
        } catch {
            guard case let .server(status, _) = error else { Issue.record("\(error)"); return }
            #expect(status == 404)
        }

        // Skip two of Rent's dates; the list counts them; restoring brings both back.
        var rent = try #require(try await client.recurring(today: day).items.first)
        #expect(rent.skippedCount == 0)
        try await client.skip(rent, on: LocalDay(year: 2026, month: 4, day: 1))
        try await client.skip(rent, on: LocalDay(year: 2026, month: 5, day: 1))
        rent = try #require(try await client.recurring(today: day).items.first)
        #expect(rent.skippedCount == 2)
        #expect(try await client.restoreSkippedDates(rent) == 2)
        let april = try await client.forecast(account: checking, month: YearMonth(day).next, today: day)
        #expect(april.rows.map(\.description) == ["Rent"])
        #expect(try await client.recurring(today: day).items.first?.skippedCount == 0)
        #expect(try await client.restoreSkippedDates(rent) == 0)

        // A bill that isn't there is a 404.
        let (status, _) = server.answer(method: "DELETE", path: "/api/recurring/999999/skips", query: [:], body: nil)
        #expect(status == 404)
    }

    /// CSV import on the phone (#243): the core reads the file as the
    /// server does; importing makes paid lines, links repeating rows to a
    /// bill (an existing one, or one it makes), and the same file again
    /// adds nothing.
    @Test func aBanksCSVImportsOnceAndRepeatingRowsBecomeABill() async throws {
        let checking = try await account("Checking", 1000, starting: LocalDay(year: 2026, month: 1, day: 1))
        try await bill("Streaming service", "15.99", day: 1, account: checking)
        let text = """
        Date,Description,Amount,Category,Frequency
        2026-01-05,Coffee,-4.50,dining,
        01/07/2026,"Grocery store, Main St",-84.23,Groceries,
        2026-02-01,streaming service,-15.99,,Monthly
        2026-01-10,Gym,-39,,monthly
        2026-02-10,Gym,-41,,monthly
        someday,Bad date,-5,,
        """
        let preview = try await client.previewImport(CSVImportBody(csvText: text), account: checking)
        #expect(preview.headers == ["Date", "Description", "Amount", "Category", "Frequency"])
        #expect(preview.mapping.date == 0 && preview.mapping.frequency == 4 && preview.mapping.endDate == nil)
        #expect((preview.rowCount, preview.skippedCount, preview.duplicateCount, preview.recurringCount) == (5, 1, 0, 3))
        #expect(preview.rows.map(\.description) == ["Coffee", "Grocery store, Main St", "streaming service", "Gym", "Gym"])
        #expect(preview.rows[1].date == LocalDay(year: 2026, month: 1, day: 7) && preview.rows[1].categoryMatched)
        #expect(preview.rows.map(\.recurringTemplate) == [nil, nil, "existing", "new", "new"])
        #expect(preview.skipped.first?.reason == "missing date or amount")

        var body = CSVImportBody(csvText: text)
        body.mapping = preview.mapping
        let result = try await client.commitImport(body, account: checking)
        #expect(result == CSVImportResult(inserted: 5, recurringCreated: 1, recurringLinked: 3, duplicatesSkipped: 0, totalRows: 5))
        let bills = try await client.recurring(today: day)
        let gym = try #require(bills.items.first { $0.description == "Gym" })
        // A new bill takes the series' latest row: its day and its amount.
        #expect(gym.dayOfMonth == 10 && gym.amount == Money(Decimal(-41)))
        let january = try await client.forecast(account: checking, month: YearMonth(year: 2026, month: 1), today: day)
        let coffee = try #require(january.rows.first { $0.description == "Coffee" })
        #expect(coffee.isPaid && coffee.actualAmount == Money(Decimal(string: "-4.5")!))
        #expect(january.rows.first { $0.description == "Grocery store, Main St" }?.categoryId != nil)

        // The same file again: every row is a duplicate, nothing is added.
        let again = try await client.previewImport(body, account: checking)
        #expect(again.duplicateCount == 5)
        let second = try await client.commitImport(body, account: checking)
        #expect(second.inserted == 0 && second.duplicatesSkipped == 5 && second.recurringCreated == 0)
        #expect(try await client.recurring(today: day).items.count == bills.items.count)
    }

    @Test func aCSVImportChecksWhatTheServerChecks() async throws {
        let checking = try await account("Checking", 0)
        func status(_ text: String, _ path: String = "preview", extra: [String: Any] = [:]) throws -> Int {
            let body = try JSONSerialization.data(withJSONObject: ["csv_text": text].merging(extra) { $1 })
            return server.answer(method: "POST", path: "/api/accounts/\(checking)/import/\(path)", query: [:], body: body).status
        }
        #expect(try status("  \n") == 400)
        #expect(try status("a,b\n", extra: ["sign_convention": "sideways"]) == 400)
        // Python's csv reader refuses a bare line break inside a field; so does the phone.
        #expect(try status("Date,Description\n2026-01-05,Coffee\rshop\n") == 400)
        #expect(try status("a,b\n", "commit") == 422)   // no mapping
        #expect(try status("a,b\n", "commit", extra: ["mapping": [String: Any](), "default_category_id": 424242]) == 404)
        let (missing, _) = server.answer(method: "POST", path: "/api/accounts/999999/import/preview", query: [:],
                                         body: try JSONSerialization.data(withJSONObject: ["csv_text": "a\n"]))
        #expect(missing == 404)
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
