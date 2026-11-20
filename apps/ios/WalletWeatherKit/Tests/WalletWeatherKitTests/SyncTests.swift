import Foundation
import SwiftData
import Testing
@testable import WalletWeatherKit

/// Sync with iCloud (Plans/standalone.md, phase 7, #238): CloudKit keeps a
/// record's later edit and a deleted record deleted (open question 6), so
/// these check the part that's ours: two devices that each set up a
/// household apart end up with one, and every device joins the copies the
/// same way. "Syncing" here copies one store's rows into another, as CloudKit
/// brings another device's records in.
@Suite(.serialized) struct SyncTests {
    let day = LocalDay(year: 2026, month: 3, day: 10)

    /// A device's household: an account, a bill and a line in "Groceries",
    /// a skipped date, and the notice agreed to.
    func device(_ account: String, bill: String, line: String) async throws -> LocalServer {
        let server = try LocalServer.inMemory()
        let client = APIClient(connection: server.connection)
        try await client.acknowledgeNotice()
        let id = try await client.createAccount(AccountBody(name: account, startingBalance: 100, startingDate: day)).id
        let groceries = try #require(try await client.categories().first { $0.name == "Groceries" }?.id)
        var draft = BillDraft(today: day)
        draft.name = bill
        draft.amountText = "50"
        draft.dayOfMonth = 1
        draft.categoryId = groceries
        try await client.addRecurring(draft, account: id)
        var add = NewTransactionDraft(today: day)
        add.name = line
        add.amountText = "12"
        add.categoryId = groceries
        try await client.add(add, account: id)
        let rec = try #require(try await client.recurring(today: day).items.first)
        try await client.skip(rec, on: LocalDay(year: 2026, month: 4, day: 1))
        return server
    }

    /// A household with nothing in it, not even the default categories.
    func empty() throws -> LocalServer {
        try LocalServer.inMemory(seeded: false)
    }

    /// Copies every row of `from` into `into`, ids and all.
    func sync(_ from: LocalServer, into: LocalServer) throws {
        let source = ModelContext(from.container)
        let target = ModelContext(into.container)
        for a in try source.fetch(FetchDescriptor<LocalAccount>()) {
            let c = LocalAccount(name: a.name, startingBalance: a.startingBalance, startingDate: a.startingDate)
            c.id = a.id; c.added = a.added; c.archived = a.archived
            target.insert(c)
        }
        for k in try source.fetch(FetchDescriptor<LocalCategory>()) {
            let c = LocalCategory(name: k.name, color: k.color)
            c.id = k.id; c.added = k.added
            target.insert(c)
        }
        for r in try source.fetch(FetchDescriptor<LocalRecurring>()) {
            let c = LocalRecurring(accountID: r.accountID)
            c.id = r.id; c.name = r.name; c.amount = r.amount; c.frequency = r.frequency; c.dayOfMonth = r.dayOfMonth
            c.anchorDate = r.anchorDate; c.endDate = r.endDate; c.categoryID = r.categoryID; c.active = r.active; c.added = r.added
            target.insert(c)
        }
        for s in try source.fetch(FetchDescriptor<LocalSkip>()) {
            let c = LocalSkip(recurringID: s.recurringID, date: s.date)
            c.id = s.id
            target.insert(c)
        }
        for t in try source.fetch(FetchDescriptor<LocalTransaction>()) {
            let c = LocalTransaction(accountID: t.accountID)
            c.id = t.id; c.name = t.name; c.amount = t.amount; c.categoryID = t.categoryID; c.recurringID = t.recurringID
            c.forecastDate = t.forecastDate; c.actualDate = t.actualDate; c.isActual = t.isActual; c.added = t.added
            target.insert(c)
        }
        for f in try source.fetch(FetchDescriptor<LocalFlag>()) {
            let c = LocalFlag(name: f.name, value: f.value)
            c.id = f.id
            target.insert(c)
        }
        try target.save()
    }

    /// What a household holds, by id, to compare two devices.
    func snapshot(_ server: LocalServer) throws -> [String] {
        let c = ModelContext(server.container)
        var out: [String] = []
        out += try c.fetch(FetchDescriptor<LocalCategory>()).map { "category \($0.id) \($0.name) \($0.color ?? "-")" }
        out += try c.fetch(FetchDescriptor<LocalRecurring>()).map { "bill \($0.id) \($0.name) cat \($0.categoryID ?? 0)" }
        out += try c.fetch(FetchDescriptor<LocalTransaction>()).map { "line \($0.id) \($0.name) cat \($0.categoryID ?? 0)" }
        out += try c.fetch(FetchDescriptor<LocalSkip>()).map { "skip \($0.id) \($0.recurringID) \($0.date)" }
        out += try c.fetch(FetchDescriptor<LocalFlag>()).map { "flag \($0.id) \($0.name)=\($0.value)" }
        return out.sorted()
    }

    @Test func twoHouseholdsBecomeOneAndBothDevicesKeepTheSameCopies() async throws {
        let phoneAlone = try await device("Checking", bill: "Rent", line: "Market")
        let padAlone = try await device("Savings", bill: "Gym", line: "Bakery")
        // Each device ends up with both households' records, brought in the
        // other way round, and joins them itself.
        let phone = try empty(), pad = try empty()
        try sync(phoneAlone, into: phone)
        try sync(padAlone, into: phone)
        try sync(padAlone, into: pad)
        try sync(phoneAlone, into: pad)
        #expect(phone.reconcile())
        #expect(pad.reconcile())
        #expect(try snapshot(phone) == snapshot(pad))

        let client = APIClient(connection: phone.connection)
        let categories = try await client.categories()
        #expect(categories.count == LocalStore.defaultCategories.count)
        #expect(Set(categories.map(\.name)).count == categories.count)
        let groceries = try #require(categories.first { $0.name == "Groceries" }?.id)
        // Both devices' bills and lines now point at the one Groceries.
        let bills = try await client.recurring(today: day).items
        #expect(Set(bills.map(\.description)) == ["Rent", "Gym"])
        #expect(bills.allSatisfy { $0.categoryId == groceries })
        let accounts = try await client.accounts(today: day)
        #expect(Set(accounts.map(\.name)) == ["Checking", "Savings"])
        for account in accounts {
            let month = try await client.forecast(account: account.id, month: YearMonth(day), today: day)
            for line in month.rows where line.transactionId != nil { #expect(line.categoryId == groceries) }
        }
        #expect(try await client.me().noticeRequired == false)
        // Nothing left to join.
        #expect(!phone.reconcile())
    }

    @Test func theSameSkippedDateIsKeptOnceAndSettingsJoin() throws {
        let server = try LocalServer.inMemory()
        let c = ModelContext(server.container)
        let a = LocalSkip(recurringID: 7, date: "2026-04-01"), b = LocalSkip(recurringID: 7, date: "2026-04-01")
        a.id = 20; b.id = 10
        c.insert(a); c.insert(b)
        c.insert(LocalSkip(recurringID: 7, date: "2026-05-01"))
        // Two devices' settings made apart.
        for (id, name, value) in [(5, "changed_at", "1795166400.5"), (3, "changed_at", "1795166000"),
                                  (9, "notice_acknowledged", "yes"), (2, "icloud_backup", "off"), (8, "icloud_backup", "on"),
                                  (4, "something_else", "first"), (6, "something_else", "second")] {
            let f = LocalFlag(name: name, value: value)
            f.id = id
            c.insert(f)
        }
        // A row from before phase 7, with no id.
        let old = LocalFlag(name: "old", value: "x")
        old.id = 0
        c.insert(old)
        try c.save()
        // Read before joining as after.
        #expect(server.changeStamp == "1795166400.5")
        #expect(server.cloudBackupOn == true)
        #expect(server.reconcile())
        let after = ModelContext(server.container)
        let skips = try after.fetch(FetchDescriptor<LocalSkip>()).sorted { $0.date < $1.date }
        #expect(skips.map(\.date) == ["2026-04-01", "2026-05-01"] && skips[0].id == 10)
        let flags = Dictionary(uniqueKeysWithValues: try after.fetch(FetchDescriptor<LocalFlag>()).map { ($0.name, $0) })
        #expect(flags.count == 5)
        #expect(flags["changed_at"]?.id == 3 && flags["changed_at"]?.value == "1795166400.5")
        #expect(flags["icloud_backup"]?.id == 2 && flags["icloud_backup"]?.value == "on")
        #expect(flags["something_else"]?.value == "first")
        #expect((flags["old"]?.id ?? 0) != 0)
        #expect(!server.reconcile())
    }

    @Test func aSettingIsWrittenToEveryCopy() throws {
        let server = try LocalServer.inMemory()
        let c = ModelContext(server.container)
        for id in [1, 2] {
            let f = LocalFlag(name: LocalServer.backupSettingFlag, value: "on")
            f.id = id
            c.insert(f)
        }
        try c.save()
        server.setCloudBackup(false)
        #expect(server.cloudBackupOn == false)
    }

    /// Delete everywhere (#249) deletes every row through the store, which
    /// is what CloudKit sends on to iCloud and the other devices.
    @Test func deleteEverywhereEmptiesTheHouseholdThroughTheStore() async throws {
        let server = try await device("Checking", bill: "Rent", line: "Market")
        let client = APIClient(connection: server.connection)
        _ = try await client.moveMoney(try #require(TransferBody({
            var d = MoveMoneyDraft(today: day, from: try await client.accounts(today: day)[0].id,
                                   to: try await client.createAccount(AccountBody(name: "Savings", startingBalance: 0, startingDate: day)).id)
            d.amountText = "5"
            return d
        }())))
        #expect(try snapshot(server).count >= 19)
        try server.emptyHousehold()
        #expect(try snapshot(server).isEmpty)
        let c = ModelContext(server.container)
        #expect(try c.fetchCount(FetchDescriptor<LocalAccount>()) == 0 && c.fetchCount(FetchDescriptor<LocalTransfer>()) == 0)
        try server.emptyHousehold()   // again: nothing to do, no error
        // With nothing syncing, no export comes: waiting for one gives up.
        #expect(await LocalStore.exported(after: .now, timeout: 0.2) == false)
    }

    @Test func syncIsOnUnlessTurnedOffAndTheTestsOpenOnThePhoneAlone() throws {
        let saved = UserDefaults.standard.object(forKey: "household.icloudSync")
        defer { UserDefaults.standard.set(saved, forKey: "household.icloudSync") }
        UserDefaults.standard.removeObject(forKey: "household.icloudSync")
        #expect(LocalStore.syncOn)
        LocalStore.syncOn = false
        #expect(!LocalStore.syncOn)
        // No iCloud entitlement here: the store opens without CloudKit.
        let folder = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try LocalStore.container(at: folder, sync: true)
        #expect(!LocalStore.syncing)
    }
}
