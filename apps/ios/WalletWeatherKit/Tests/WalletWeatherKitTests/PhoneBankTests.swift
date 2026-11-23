import Foundation
import Security
import SwiftData
import Testing
@testable import WalletWeatherKit

/// Bank sync on a phone without a server (Plans/standalone.md, phase 8,
/// #239): claiming a SimpleFIN token and pulling lines from a stand-in
/// Bridge (nothing reaches the network), the 23½-hour and daily guards, the
/// access address kept in the Keychain only, a line never landing twice,
/// bills paid by the core's matching, and the Unmatched list with Match…
/// and Leave on the household in memory.
@MainActor @Suite(.serialized)
struct PhoneBankTests {
    nonisolated static let access = "https://phone-user:s3cret-pass@bridge.simplefin.org/simplefin"
    static let claimURL = "https://bridge.simplefin.org/simplefin/claim/0123abcd"
    static var token: String { Data(claimURL.utf8).base64EncodedString() }

    let server: LocalServer
    let client: APIClient
    let defaults: UserDefaults
    let secrets = MemoryBankSecret()
    let today = LocalDay.today()

    init() throws {
        server = try LocalServer.inMemory()
        client = APIClient(connection: server.connection)
        defaults = UserDefaults(suiteName: "ww-phone-bank-\(UUID().uuidString)")!
        FakeBridge.reset()
    }

    func bank() -> PhoneBank {
        let server = self.server
        return PhoneBank(secrets: secrets, defaults: defaults, session: FakeBridge.session(), household: { server })
    }

    static func epoch(_ day: LocalDay) -> Int { SimpleFIN.epoch(day) + 12 * 3600 }

    /// Bridge's answer: one checking account with these lines.
    static func accounts(_ lines: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "errors": [],
            "accounts": [
                ["id": "ACT-1", "name": "Everyday Checking", "org": ["name": "Example Bank"], "balance": "1200.00",
                 "transactions": lines],
                ["id": "ACT-2", "name": "Card", "org": ["name": "Example Bank"], "balance": "-50.00", "transactions": []],
            ],
        ])
    }

    func line(_ id: String, _ day: LocalDay, _ amount: String, _ text: String, pending: Bool = false) -> [String: Any] {
        ["id": id, "posted": Self.epoch(day), "amount": amount, "description": text, "pending": pending]
    }

    func checking() async throws -> Int {
        try await client.createAccount(AccountBody(name: "Checking", startingBalance: 1000, startingDate: today.adding(days: -60))).id
    }

    func rent(on day: LocalDay, account: Int) async throws {
        var draft = BillDraft(today: today)
        draft.name = "Rent"
        draft.amountText = "800"
        draft.kind = .spending
        draft.dayOfMonth = day.day
        draft.hasStart = false
        try await client.addRecurring(draft, account: account)
    }

    // MARK: Connecting

    @Test func aTokenIsClaimedAndTheAccountsListed() async throws {
        FakeBridge.lines = Self.accounts([])
        let bank = bank()
        try await bank.connect(token: "  " + Self.token + "\n")
        #expect(secrets.read() == Self.access)
        #expect(bank.connected)
        #expect(bank.state.bankAccounts.map(\.name) == ["Everyday Checking", "Card"])
        #expect(bank.state.bankAccounts.first?.org == "Example Bank")
        let seen = FakeBridge.seen
        #expect(seen.count == 2)
        #expect(seen[0].method == "POST" && seen[0].url == Self.claimURL)
        #expect(seen[1].method == "GET" && seen[1].url.hasPrefix("https://bridge.simplefin.org/simplefin/accounts?balances-only=1"))
        // The credentials go in the header, never in the address asked.
        #expect(seen[1].auth == "Basic " + Data("phone-user:s3cret-pass".utf8).base64EncodedString())
        #expect(!seen[1].url.contains("s3cret"))
        #expect(bank.state.calls.count == 1)   // the listing counts, as on the server
    }

    @Test func aBadTokenSendsNothing() async throws {
        let bank = bank()
        for bad in ["not a token!", Data("http://bridge.simplefin.org/claim/x".utf8).base64EncodedString(),
                    Data("https://example.com/simplefin/claim/x".utf8).base64EncodedString(),
                    Data("https://u:p@bridge.simplefin.org/claim/x".utf8).base64EncodedString()] {
            await #expect(throws: SimpleFIN.Failure.self) { try await bank.connect(token: bad) }
        }
        #expect(FakeBridge.seen.isEmpty)
        #expect(secrets.read() == nil)
        do {
            try await bank.connect(token: Data("https://evil.example/claim".utf8).base64EncodedString())
        } catch {
            #expect(error.message == "That token points at evil.example, which isn't SimpleFIN. Nothing was sent to it.")
        }
        FakeBridge.claimStatus = 403
        do {
            try await bank.connect(token: Self.token)
            Issue.record("a used token was taken")
        } catch {
            #expect(error.message.hasPrefix("SimpleFIN says this token was already used"))
        }
        #expect(secrets.read() == nil)
        // An access address on another host is refused too.
        FakeBridge.claimStatus = 200
        FakeBridge.accessAnswer = "https://u:p@elsewhere.example/simplefin"
        await #expect(throws: SimpleFIN.Failure.self) { try await bank.connect(token: Self.token) }
        #expect(secrets.read() == nil)
    }

    @Test func theAccessAddressIsKeptInTheKeychainOnly() async throws {
        let account = try await checking()
        FakeBridge.lines = Self.accounts([line("t1", today.adding(days: -2), "-12.00", "Coffee")])
        let bank = bank()
        try await bank.connect(token: Self.token)
        bank.link("ACT-1", to: account, start: today.adding(days: -30), today: today)
        try await bank.sync(today: today)

        // Not in the phone's settings…
        let settings = try PropertyListSerialization.data(fromPropertyList: defaults.dictionaryRepresentation(), format: .xml, options: 0)
        #expect(!String(decoding: settings, as: UTF8.self).contains("s3cret"))
        #expect(!String(decoding: settings, as: UTF8.self).contains("phone-user"))
        // …nor in the household, nor its backup (which iCloud Drive and a
        // move to a server carry).
        let payload = try JSONSerialization.data(withJSONObject: try server.backupPayload())
        #expect(!String(decoding: payload, as: UTF8.self).contains("s3cret"))
        #expect(!String(decoding: payload, as: UTF8.self).contains("bridge.simplefin.org"))
        // The Keychain item: this device only, never iCloud Keychain, and
        // readable after the first unlock (for background time).
        let saved = KeychainBankSecret.saved
        #expect(saved[kSecAttrSynchronizable as String] as? Bool == false)
        #expect((saved[kSecAttrAccessible as String] as! CFString) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        #expect(saved[kSecAttrService as String] as? String == "net.iptater.walletweather.simplefin")

        bank.disconnect()
        #expect(secrets.read() == nil)
        #expect(!bank.connected)
        #expect(bank.state == PhoneBankState())
    }

    // MARK: The guards

    @Test func aSyncByItselfComesAtMostEvery23AndAHalfHours() async throws {
        let account = try await checking()
        FakeBridge.lines = Self.accounts([])
        let bank = bank()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        try await bank.connect(token: Self.token, now: start)
        #expect(!bank.isDue(now: start))          // no account matched yet
        bank.link("ACT-1", to: account, today: today)
        #expect(bank.isDue(now: start))           // never synced
        #expect(try await bank.syncIfDue(now: start) != nil)
        let asked = FakeBridge.seen.count
        for later: TimeInterval in [60, 3600, 23 * 3600, 23.5 * 3600 - 1] {
            #expect(!bank.isDue(now: start.addingTimeInterval(later)))
            #expect(await bank.syncIfDue(now: start.addingTimeInterval(later)) == nil)
        }
        #expect(FakeBridge.seen.count == asked)
        #expect(bank.isDue(now: start.addingTimeInterval(23.5 * 3600)))
        // A failed sync counts as one too.
        FakeBridge.accountsStatus = 500
        #expect(await bank.syncIfDue(now: start.addingTimeInterval(23.5 * 3600)) == nil)
        #expect(bank.state.lastSyncOk == false)
        #expect(!bank.isDue(now: start.addingTimeInterval(30 * 3600)))
        #expect(bank.isDue(now: start.addingTimeInterval(47 * 3600)))
        // Once SimpleFIN stops taking it, nothing by itself until connected again.
        FakeBridge.accountsStatus = 403
        await #expect(throws: SimpleFIN.Failure.self) { try await bank.sync(now: start.addingTimeInterval(48 * 3600)) }
        #expect(bank.state.needsReconnect)
        #expect(!bank.isDue(now: start.addingTimeInterval(100 * 3600)))
    }

    @Test func syncNowStopsAtTwentyCallsADay() async throws {
        let account = try await checking()
        FakeBridge.lines = Self.accounts([])
        let bank = bank()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        try await bank.connect(token: Self.token, now: start)
        bank.link("ACT-1", to: account, today: today)
        for i in 1..<PhoneBank.callsPerDay { try await bank.sync(now: start.addingTimeInterval(Double(i) * 60)) }
        #expect(bank.state.calls.count == 20)
        let asked = FakeBridge.seen.count
        let now = start.addingTimeInterval(20 * 60)
        #expect(bank.waitSeconds(now: now) == 86_400 - 20 * 60)
        do {
            try await bank.sync(now: now)
            Issue.record("a 21st call was made")
        } catch {
            #expect(error.message == "Bank sync has asked SimpleFIN 20 times in the last 24 hours, the most it allows without risking your connection. It can run again in 1420 minutes.")
        }
        #expect(FakeBridge.seen.count == asked)
        #expect(!bank.isDue(now: now))
        // A day after the first call, one more is allowed.
        #expect(bank.waitSeconds(now: start.addingTimeInterval(86_400)) == 0)
        try await bank.sync(now: start.addingTimeInterval(86_400))
    }

    // MARK: Lines landing

    @Test func linesLandOnceAndPayBills() async throws {
        let account = try await checking()
        let paid = today.adding(days: -3)
        try await rent(on: paid, account: account)
        // A line typed by hand that the bank sends too.
        var draft = NewTransactionDraft(today: today.adding(days: -4))
        draft.name = "Groceries"
        draft.amountText = "50"
        draft.paid = true
        try await client.add(draft, account: account)

        FakeBridge.lines = Self.accounts([
            line("rent", paid.adding(days: 1), "-800.00", "ACH Withdrawal LANDLORD LLC / PPD ID 77"),
            line("coffee", today.adding(days: -2), "-4.5", "POS Withdrawal CORNER CAFE / 1234 MAIN ST"),
            line("groceries", today.adding(days: -4), "-50.00", "GROCERIES"),
            line("pending", today.adding(days: -1), "-9.99", "Streaming", pending: true),
            line("old", today.adding(days: -40), "-1.00", "Before the start"),
        ])
        let bank = bank()
        try await bank.connect(token: Self.token)
        bank.link("ACT-1", to: account, start: today.adding(days: -30), today: today)
        let first = try await bank.sync(today: today)
        #expect(first == PhoneBankResult(added: 1, matched: 1, skipped: 1, messages: []))
        #expect(bank.state.lastSyncStatus == "1 new line, 1 matched a bill, 1 already here")
        // The coffee, and the groceries typed by hand that the bank's line
        // claimed (on the list, as on the server, until matched or left).
        #expect(bank.state.unmatched == 2)
        #expect(bank.state.link(for: "ACT-1")?.syncedThrough == today)

        // The same lines again: nothing lands twice.
        let again = try await bank.sync(today: today)
        #expect(again == PhoneBankResult(added: 0, matched: 0, skipped: 3, messages: []))

        let month = try await client.forecast(account: account, month: YearMonth(paid), today: today)
        let rentRow = try #require(month.rows.first { $0.description == "Rent" && $0.isPaid })
        #expect(rentRow.actualAmount == Money(-800.0))
        #expect(rentRow.actualDate == paid.adding(days: 1))
        #expect(rentRow.plannedDate == paid)
        let lines = try server.allLines()
        #expect(lines.count == 3)   // groceries (claimed), rent paid, the coffee
        #expect(Set(lines.compactMap(\.bankRef)) == [SimpleFIN.lineRef("ACT-1", "rent"), SimpleFIN.lineRef("ACT-1", "coffee"),
                                                      SimpleFIN.lineRef("ACT-1", "groceries")])
        let coffee = try #require(lines.first { $0.bankRef == SimpleFIN.lineRef("ACT-1", "coffee") })
        #expect(coffee.name == "CORNER CAFE")
        #expect(coffee.notes == "POS Withdrawal CORNER CAFE / 1234 MAIN ST")
        #expect(coffee.amount == -4.5)
        let rentLine = try #require(lines.first { $0.recurringID != nil })
        #expect(rentLine.bankMatch == "auto" && rentLine.bankText == "ACH Withdrawal LANDLORD LLC / PPD ID 77")

    }

    @Test func theRefsAreTheServers() {
        // main.bank_txn_ref and bank_account_ref: sha256 of these texts.
        #expect(SimpleFIN.lineRef("A", "1") == sha("simplefin:A:1"))
        #expect(SimpleFIN.accountRef("A") == sha("simplefin-account:A"))
    }

    private func sha(_ text: String) -> String {
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/shasum")
        task.arguments = ["-a", "256"]
        let input = Pipe(), output = Pipe()
        task.standardInput = input
        task.standardOutput = output
        try? task.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        task.waitUntilExit()
        return String(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).prefix(64))
    }

    @Test func amountsAndDaysAreReadAsTheServerReadsThem() {
        #expect(SimpleFIN.amount("-12.345") == "-12.34")   // half to even, as Decimal.quantize
        #expect(SimpleFIN.amount("-12.355") == "-12.36")
        #expect(SimpleFIN.amount("10") == "10")
        #expect(SimpleFIN.amount(NSNumber(value: 4.5)) == "4.5")
        #expect(SimpleFIN.amount("abc") == nil)
        #expect(SimpleFIN.amount("1e13") == nil)
        #expect(SimpleFIN.amount(true) == nil)
        #expect(SimpleFIN.day(epoch: 1_794_528_000) == LocalDay(year: 2026, month: 11, day: 13))
        #expect(SimpleFIN.shortName("Withdrawal Example Internet / TYPE: x") == "Example Internet")
        #expect(SimpleFIN.shortName("Plain") == nil)
    }

    // MARK: The Unmatched list

    @Test func unmatchedLinesAreMatchedOrLeft() async throws {
        let account = try await checking()
        let due = today.adding(days: -10)
        try await rent(on: due, account: account)
        FakeBridge.lines = Self.accounts([
            // Too far from the bill's amount to pay it by itself.
            line("rent", due.adding(days: 1), "-650.00", "ACH Withdrawal LANDLORD LLC / PPD 77"),
            line("coffee", today.adding(days: -2), "-4.50", "CORNER CAFE"),
        ])
        let bank = bank()
        try await bank.connect(token: Self.token)
        bank.link("ACT-1", to: account, start: today.adding(days: -30), today: today)
        try await bank.sync(today: today)
        #expect(bank.state.unmatched == 2)

        var list = try await client.bankUnmatched(account: account)
        #expect(list.count == 2)
        #expect(list.lines.map(\.description) == ["CORNER CAFE", "LANDLORD LLC"])   // newest first
        let month = try await client.forecast(account: account, month: YearMonth(today), today: today)
        #expect(month.rows.contains { $0.description == "CORNER CAFE" && $0.bankUnmatched == true })

        let rentLine = try #require(list.lines.last)
        let candidates = try await client.bankCandidates(account: account, line: rentLine.id)
        #expect(candidates.line.learnName == "LANDLORD LLC")
        #expect(candidates.line.bankText == "ACH Withdrawal LANDLORD LLC / PPD 77")
        let choice = try #require(candidates.choices.first)
        #expect(choice.description == "Rent" && choice.forecastDate == due && choice.recurringId != nil)
        #expect(choice.daysAfter == 1 && choice.amountDiff == Money(150.0) && choice.sameDirection)

        let result = try await client.bankMatch(account: account, line: rentLine.id, to: choice, remember: true)
        #expect(result.learned == "LANDLORD LLC")
        #expect(result.alsoMatched == 0)
        // Matching it again is refused: it's gone from the list.
        await #expect(throws: APIError.self) { try await client.bankMatch(account: account, line: rentLine.id, to: choice, remember: false) }
        let paid = try await client.forecast(account: account, month: YearMonth(due), today: today)
        let row = try #require(paid.rows.first { $0.description == "Rent" && $0.isPaid })
        #expect(row.actualAmount == Money(-650.0) && row.plannedDate == due)

        list = try await client.bankUnmatched(account: account)
        #expect(list.count == 1)
        try await client.bankLeave(account: account, line: list.lines[0].id)
        #expect(try await client.bankUnmatched(account: account).count == 0)
        bank.recount()
        #expect(bank.state.unmatched == 0)

        // The bill now knows the landlord's name: next month's line pays it
        // at any amount within its days.
        let next = due.adding(days: 31)
        let nextDue = LocalDay(year: next.year, month: next.month, day: min(due.day, next.endOfMonth.day))
        if nextDue <= today {
            FakeBridge.lines = Self.accounts([line("rent2", nextDue, "-700.00", "ACH Withdrawal LANDLORD LLC / PPD 78")])
            let synced = try await bank.sync(today: today)
            #expect(synced.matched == 1)
        }
    }

    @Test func theUnmatchedRoutesCheckWhatTheyAreGiven() async throws {
        let account = try await checking()
        let (missing, _) = server.answer(method: "GET", path: "/api/accounts/\(account)/bank-unmatched/12345/candidates",
                                         query: [:], body: nil)
        #expect(missing == 404)
        let (noAccount, _) = server.answer(method: "GET", path: "/api/accounts/999/bank-unmatched", query: [:], body: nil)
        #expect(noAccount == 404)
        FakeBridge.lines = Self.accounts([line("coffee", today.adding(days: -2), "-4.50", "CORNER CAFE")])
        let bank = bank()
        try await bank.connect(token: Self.token)
        bank.link("ACT-1", to: account, start: today.adding(days: -30), today: today)
        try await bank.sync(today: today)
        let id = try #require(try await client.bankUnmatched(account: account).lines.first?.id)
        func match(_ body: [String: Any]) -> Int {
            server.answer(method: "POST", path: "/api/accounts/\(account)/bank-unmatched/\(id)/match", query: [:],
                          body: try! JSONSerialization.data(withJSONObject: body)).status
        }
        #expect(match([:]) == 400)
        #expect(match(["transaction_id": 42]) == 404)
        #expect(match(["recurring_id": 42, "forecast_date": today.description]) == 404)
    }
}

extension LocalServer {
    /// Every line in the household, for the tests.
    func allLines() throws -> [LocalTransaction] {
        try ModelContext(container).fetch(FetchDescriptor<LocalTransaction>())
    }
}

/// A stand-in SimpleFIN Bridge: answers the claim and the accounts, and
/// records what it was asked. The suite runs one test at a time.
final class FakeBridge: URLProtocol, @unchecked Sendable {
    struct Seen { let method: String; let url: String; let auth: String? }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [Seen] = []
    nonisolated(unsafe) static var lines = Data()
    nonisolated(unsafe) static var claimStatus = 200
    nonisolated(unsafe) static var accountsStatus = 200
    nonisolated(unsafe) static var accessAnswer = PhoneBankTests.access

    static var seen: [Seen] { lock.withLock { _seen } }

    static func reset() {
        lock.withLock { _seen = [] }
        lines = Data()
        claimStatus = 200
        accountsStatus = 200
        accessAnswer = PhoneBankTests.access
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeBridge.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock {
            Self._seen.append(Seen(method: request.httpMethod ?? "GET", url: url.absoluteString,
                                   auth: request.value(forHTTPHeaderField: "Authorization")))
        }
        let (status, body): (Int, Data)
        if url.host() != "bridge.simplefin.org" {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        } else if url.path().hasPrefix("/simplefin/claim/") {
            (status, body) = (Self.claimStatus, Data(Self.accessAnswer.utf8))
        } else if url.path() == "/simplefin/accounts" {
            (status, body) = (Self.accountsStatus, Self.lines)
        } else {
            (status, body) = (404, Data())
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
