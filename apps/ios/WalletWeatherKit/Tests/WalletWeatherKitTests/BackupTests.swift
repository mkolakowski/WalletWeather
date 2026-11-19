import Foundation
import Testing
@testable import WalletWeatherKit

/// Moving between a server and the iPhone (Plans/standalone.md, phase 5,
/// #236). Done when a round trip (phone → server → phone) gives the same
/// Forecast:
///
/// 1. `household()` is set up on the phone; its Forecasts for three months
///    are `Samples/moves/forecast.json` and its sealed backup is
///    `Samples/moves/from-phone.json` (written with
///    `WRITE_BACKUP_FIXTURES=1 swift test --filter BackupTests`).
/// 2. The server's tests (apps/server/tests/test_backup_moves.py) import
///    from-phone.json, check the server gives the same Forecasts, and seal
///    the server's own backup of it as `Samples/moves/from-server.json`.
/// 3. Here, from-server.json is imported onto an empty phone, which gives
///    those Forecasts again.
@Suite(.serialized) struct BackupTests {
    /// Committed with the fixtures; a test passphrase, not a secret.
    static let passphrase = "move me to a server 2026"
    static let months = [YearMonth(year: 2026, month: 1), YearMonth(year: 2026, month: 2), YearMonth(year: 2026, month: 3)]
    static let today = LocalDay(year: 2026, month: 2, day: 10)
    static let quick = (n: 16, r: 8, p: 1)

    static var samples: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Samples/moves")
    }

    static func sample(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples/moves"))
        return try Data(contentsOf: url)
    }

    // MARK: The household

    /// Two accounts, bills of each rhythm (one ended, one switched off, one
    /// with a skipped date), a paid bill, lines with notes and categories,
    /// names beyond ASCII, and a transfer.
    static func household() async throws -> LocalServer {
        let server = try LocalServer.inMemory()
        let client = APIClient(connection: server.connection)
        try await client.acknowledgeNotice()
        let start = LocalDay(year: 2026, month: 1, day: 1)
        let checking = try await client.createAccount(AccountBody(name: "Checking", startingBalance: 1234.56, startingDate: start)).id
        let savings = try await client.createAccount(AccountBody(name: "Épargne 🍕", startingBalance: 5000, startingDate: start)).id
        let categories = try await client.categories()
        func category(_ name: String) -> Int? { categories.first { $0.name == name }?.id }

        func bill(_ name: String, _ amount: String, _ frequency: Frequency = .monthly, day: Int = 1,
                  start: LocalDay? = nil, ends: LocalDay? = nil, income: Bool = false, category cat: String? = nil,
                  notes: String = "", account: Int, active: Bool = true) async throws {
            var draft = BillDraft(today: Self.today)
            draft.name = name
            draft.amountText = amount
            draft.frequency = frequency
            draft.dayOfMonth = day
            if let start { draft.start = start; draft.hasStart = true }
            if let ends { draft.ends = true; draft.endDate = ends }
            draft.kind = income ? .income : .spending
            draft.categoryId = cat.flatMap(category)
            draft.notes = notes
            if active {
                try await client.addRecurring(draft, account: account)
            } else {
                // Switched off: saved, then saved again as inactive.
                try await client.addRecurring(draft, account: account)
                let item = try #require(try await client.recurring(today: Self.today).items.first { $0.description == name })
                try await client.updateRecurring(item.id, RecurringBody(draft, active: false))
            }
        }
        try await bill("Rent", "1450", day: 1, category: "Rent/Mortgage", notes: "landlord: Jürgen", account: checking)
        try await bill("Paycheck", "2100", .biweekly, start: LocalDay(year: 2026, month: 1, day: 9), income: true,
                       category: "Income", account: checking)
        try await bill("Gym", "12.50", .weekly, start: LocalDay(year: 2026, month: 1, day: 6),
                       ends: LocalDay(year: 2026, month: 2, day: 20), account: checking)
        try await bill("Phone", "65.43", day: 31, category: "Utilities", account: checking)
        try await bill("Old magazine", "9.99", day: 20, account: checking, active: false)
        try await bill("Interest", "4.17", day: 28, income: true, account: savings)

        let items = try await client.recurring(today: Self.today).items
        let paycheck = try #require(items.first { $0.description == "Paycheck" })
        try await client.skip(paycheck, on: LocalDay(year: 2026, month: 2, day: 6))

        // January's rent, paid on the 3rd.
        let january = try await client.forecast(account: checking, month: Self.months[0], today: Self.today)
        let rent = try #require(january.rows.first { $0.description == "Rent" })
        var paid = LineDraft(rent, today: Self.today)
        paid.paid = true
        paid.paidOn = LocalDay(year: 2026, month: 1, day: 3)
        try await client.save(rent, draft: paid, account: checking)

        for (name, amount, day, notes, cat) in [("Groceries", "84.20", 4, "", "Groceries"), ("Café crème", "4.75", 12, "with Sam", "Dining"),
                                                ("Car repair", "300", 21, "estimate", "")] {
            var line = NewTransactionDraft(today: LocalDay(year: 2026, month: 1, day: day))
            line.name = name
            line.amountText = amount
            line.notes = notes
            line.categoryId = cat.isEmpty ? nil : category(cat)
            line.paid = name != "Car repair"
            try await client.add(line, account: checking)
        }
        var move = MoveMoneyDraft(today: LocalDay(year: 2026, month: 1, day: 15), from: checking, to: savings)
        move.amountText = "250"
        move.description = "Rainy day"
        _ = try await client.moveMoney(try #require(TransferBody(move)))
        return server
    }

    /// Each account's Forecast for each month, by account name, with what
    /// differs between stores (ids, today's balance) left out.
    static func forecasts(_ server: LocalServer) throws -> [String: [[String: Any]]] {
        let (_, body) = server.answer(method: "GET", path: "/api/accounts", query: ["today": today.description], body: nil)
        let accounts = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        var out: [String: [[String: Any]]] = [:]
        for account in accounts {
            let id = try #require(account["id"] as? Int)
            out[try #require(account["name"] as? String)] = try months.map { month in
                let (status, data) = server.answer(method: "GET", path: "/api/accounts/\(id)/forecast",
                                                   query: ["start": month.start.description, "end": month.end.description,
                                                           "today": today.description], body: nil)
                #expect(status == 200)
                return normalized(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]))
            }
        }
        return out
    }

    /// A Forecast without what differs between stores: ids become whether
    /// there is one, and today's balance goes (the server's tests do the same).
    static func normalized(_ forecast: [String: Any]) -> [String: Any] {
        var out = forecast
        for key in ["current_balance", "bank_unmatched_count"] { out.removeValue(forKey: key) }
        out["rows"] = (forecast["rows"] as? [[String: Any]] ?? []).map { row in
            var clean: [String: Any] = [:]
            for (key, value) in row where key != "tags" {
                if key.hasSuffix("_id") { clean["has_" + key.dropLast(3)] = !(value is NSNull) } else { clean[key] = value }
            }
            return clean
        }
        return out
    }

    // MARK: Tests

    @Test func theHeaderIsWrittenAsPythonWritesIt() throws {
        struct File: Decodable { let headers: [Header] }
        struct Header: Decodable { let bytes: String }
        let data = try Self.sample("vectors")
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let headers = try #require(raw["headers"] as? [[String: Any]])
        let expected = try JSONDecoder().decode(File.self, from: data).headers
        for (header, want) in zip(headers, expected) {
            let fields = try #require(header["header"] as? [String: Any])
            let got = try #require(BackupFile.headerBytes(fields))
            #expect(String(decoding: got, as: UTF8.self) == want.bytes)
        }
    }

    @Test func aSealedFileOpensOnlyWithItsPassphrase() throws {
        let payload: [String: Any] = ["version": 5, "exported_at": "2026-02-10T09:00:00.000000Z", "accounts": [Any]()]
        let file = try BackupFile.seal(payload, passphrase: Self.passphrase, kind: "user", cost: Self.quick)
        #expect(!String(decoding: file, as: UTF8.self).contains("accounts"))
        let opened = try BackupFile.open(file, passphrase: Self.passphrase)
        #expect(opened.encrypted && opened.payload["exported_at"] as? String == "2026-02-10T09:00:00.000000Z")
        #expect(throws: BackupFile.Problem.wrongPassphrase) { try BackupFile.open(file, passphrase: "not the passphrase at all") }
        #expect(throws: BackupFile.Problem.locked) { try BackupFile.open(file, passphrase: nil) }
        // An edited header doesn't open, whatever the passphrase.
        var edited = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
        edited["kind"] = "system"
        #expect(throws: BackupFile.Problem.wrongPassphrase) {
            try BackupFile.open(try JSONSerialization.data(withJSONObject: edited), passphrase: Self.passphrase)
        }
        // A plain backup (Download my data, an older server's) passes through.
        let plain = try BackupFile.open(try JSONSerialization.data(withJSONObject: payload), passphrase: nil)
        #expect(!plain.encrypted)
        #expect(throws: BackupFile.Problem.notABackup) { try BackupFile.open(Data("[1,2]".utf8), passphrase: nil) }
        #expect(throws: BackupFile.Problem.passphrase("The passphrase must be at least 12 characters.")) {
            try BackupFile.seal(payload, passphrase: "short", kind: "user", cost: Self.quick)
        }
    }

    @Test func aBackupMadeOnThePhoneComesBackTheSame() async throws {
        let original = try await Self.household()
        let payload = try original.backupPayload()
        #expect(payload["version"] as? Int == 5)
        #expect((payload["transfers"] as? [Any])?.count == 1)
        let copy = try LocalServer.inMemory()
        let summary = try copy.importBackup(payload)
        #expect(summary == LocalServer.ImportSummary(accounts: 2, recurring: 6, transactions: 6, transfers: 1))
        #expect(NSDictionary(dictionary: try Self.forecasts(copy)) == NSDictionary(dictionary: try Self.forecasts(original)))
    }

    @Test func anImportReplacesTheHouseholdAndABadFileChangesNothing() async throws {
        let server = try await Self.household()
        let before = try Self.forecasts(server)
        var bad = try server.backupPayload()
        var accounts = try #require(bad["accounts"] as? [[String: Any]])
        accounts[0]["starting_date"] = "not a date"
        bad["accounts"] = accounts
        #expect(throws: (any Error).self) { try server.importBackup(bad) }
        #expect(NSDictionary(dictionary: try Self.forecasts(server)) == NSDictionary(dictionary: before))
        #expect(throws: (any Error).self) { try server.importBackup(["version": 99, "accounts": [Any]()]) }

        try server.importBackup(["version": 4, "accounts": [["name": "Only this", "starting_balance": 10, "starting_date": "2026-01-01"]]])
        let (_, body) = server.answer(method: "GET", path: "/api/accounts", query: [:], body: nil)
        let names = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]]).compactMap { $0["name"] as? String }
        #expect(names == ["Only this"])
    }

    /// Step 1: the phone's sealed backup, as committed, is today's household.
    @Test func theCommittedPhoneBackupIsTheHousehold() async throws {
        let server = try await Self.household()
        if ProcessInfo.processInfo.environment["WRITE_BACKUP_FIXTURES"] == "1" {
            try BackupFile.seal(try server.backupPayload(), passphrase: Self.passphrase)
                .write(to: Self.samples.appending(path: "from-phone.json"))
            let forecasts = try JSONSerialization.data(withJSONObject: try Self.forecasts(server), options: [.sortedKeys, .prettyPrinted])
            try forecasts.write(to: Self.samples.appending(path: "forecast.json"))
            return
        }
        let opened = try BackupFile.open(try Self.sample("from-phone"), passphrase: Self.passphrase)
        #expect(opened.encrypted)
        let fresh = try server.backupPayload()
        func comparable(_ payload: [String: Any]) -> NSDictionary {
            var p = payload
            p.removeValue(forKey: "exported_at")
            p["accounts"] = (payload["accounts"] as? [[String: Any]] ?? []).map { a in
                var a = a
                a.removeValue(forKey: "created_at")
                return a
            }
            return NSDictionary(dictionary: p)
        }
        #expect(comparable(opened.payload) == comparable(fresh), "rewrite with WRITE_BACKUP_FIXTURES=1")
        let committed = try #require(try JSONSerialization.jsonObject(with: try Self.sample("forecast")) as? [String: Any])
        #expect(NSDictionary(dictionary: committed) == NSDictionary(dictionary: try Self.forecasts(server)))
    }

    /// Step 3: the server's backup of it gives the same Forecasts here.
    @Test func theServersBackupGivesTheSameForecast() throws {
        let opened = try BackupFile.open(try Self.sample("from-server"), passphrase: Self.passphrase)
        #expect(opened.encrypted)
        let phone = try LocalServer.inMemory()
        let summary = try phone.importBackup(opened.payload)
        #expect(summary.transfers == 1)
        let committed = try #require(try JSONSerialization.jsonObject(with: try Self.sample("forecast")) as? [String: Any])
        #expect(NSDictionary(dictionary: try Self.forecasts(phone)) == NSDictionary(dictionary: committed))
    }
}
