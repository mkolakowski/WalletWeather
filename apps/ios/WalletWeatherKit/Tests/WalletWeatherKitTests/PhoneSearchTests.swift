import Foundation
import Testing
@testable import WalletWeatherKit

/// Bills and accounts in the phone's search (Plans/outside-the-app.md, phase
/// 4, #331): what's indexed for each connection kind (the household on this
/// iPhone, a server keeping Last-known numbers, a server set to Nothing, the
/// demo), that no amount goes in, and what's removed (a bill gone on the next
/// write, signing out, leaving the household, Delete everywhere). Against an
/// index in memory and temporary folders: never Core Spotlight or the app
/// group.
struct PhoneSearchTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "search-tests-\(UUID().uuidString)")
    let index = MemorySearchIndex()
    var summaries: SummaryStore { SummaryStore(directory: folder).searchable(index) }
    let november = LocalDay(year: 2026, month: 11, day: 15)
    static let made = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let server = Connection(server: URL(string: "https://money.example.test")!, token: "ww_token")

    func tidy() { try? FileManager.default.removeItem(at: folder) }

    /// A summary loaded from the demo's samples, as `saved` would get one.
    func sample(_ saved: SavedConnection) async throws -> ConnectionSummary {
        try await ConnectionSummary.fetch(saved, client: APIClient(connection: Demo.connection), readOnly: false,
                                          today: november, now: Self.made)
    }

    // MARK: What's indexed

    @Test func aServerKeepingNumbersHasItsBillsAndAccountsByName() async throws {
        defer { tidy() }
        let home = SavedConnection(connection: server, name: "Home", keep: .lastKnown)
        let summary = try await sample(home)
        summaries.write(summary)
        let entries = try #require(index.entries[home.id])
        #expect(entries.count == summary.accounts.count + summary.bills.count)
        #expect(entries.filter { $0.kind == .account }.map(\.title) == summary.accounts.map(\.name))
        #expect(Set(entries.filter { $0.kind != .account }.map(\.title)) == Set(summary.bills.map(\.name)))
        let account = try #require(entries.first { $0.kind == .account })
        #expect(account.detail == "Account · Home")
        #expect(account.id == SearchLink.account(home.id, summary.accounts[0].id).id)
        let bill = try #require(summary.bills.first { !$0.isIncome })
        let billEntry = try #require(entries.first { $0.id == SearchLink.bill(home.id, bill.id).id })
        #expect(billEntry.kind == .bill)
        #expect(billEntry.detail == "Bill · \(bill.accountName) · Home")
        if let pay = summary.bills.first(where: \.isIncome) {
            let payEntry = try #require(entries.first { $0.id == SearchLink.bill(home.id, pay.id).id })
            #expect(payEntry.kind == .income)
            #expect(payEntry.detail.hasPrefix("Income · "))
        }
        #expect(entries.allSatisfy { $0.connection == home.id && $0.keywords.contains("WalletWeather") })
    }

    @Test func noAmountGoesIn() async throws {
        defer { tidy() }
        let home = SavedConnection(connection: server, name: "Home", keep: .lastKnown)
        let summary = try await sample(home)
        summaries.write(summary)
        let entries = try #require(index.entries[home.id])
        let amounts = summary.accounts.flatMap { [$0.balance, $0.monthLow] } + summary.bills.map(\.amount)
        for entry in entries {
            let text = ([entry.id, entry.title, entry.detail] + entry.keywords).joined(separator: " ")
            #expect(!text.contains("$"))
            for amount in amounts {
                #expect(!text.contains(amount.formatted.replacingOccurrences(of: "-", with: "").dropFirst()))
            }
        }
    }

    @Test func theHouseholdOnThisIPhoneIsIndexed() async throws {
        defer { tidy() }
        // Its keep choice doesn't matter: its numbers are on the phone anyway.
        let household = SavedConnection(connection: LocalServer.connection, name: "On this iPhone", keep: .nothing)
        let summary = ConnectionSummary(id: household.id, name: household.name, kind: .thisPhone, madeAt: Self.made,
                                        keepsNumbers: ConnectionSummary.keepsNumbers(household),
                                        accounts: [.init(id: 1, name: "Checking", balance: Money(10.0), monthLow: Money(5.0),
                                                         monthLowDate: nil, toConfirm: 0)],
                                        bills: [.init(id: 7, name: "Rent", accountId: 1, accountName: "Checking",
                                                      amount: Money(-1500.0), nextDate: november)])
        summaries.write(summary)
        #expect(index.entries[household.id]?.map(\.title) == ["Checking", "Rent"])
        #expect(index.entries[household.id]?.last?.detail == "Bill · Checking · On this iPhone")
    }

    @Test func aServerSetToNothingIsNotIndexed() async throws {
        defer { tidy() }
        var home = SavedConnection(connection: server, name: "Home", keep: .lastKnown)
        summaries.write(try await sample(home))
        #expect(index.entries[home.id]?.isEmpty == false)
        // Choosing Nothing writes a summary with the name only: its entries go.
        home.keep = .nothing
        summaries.write(.nameOnly(home))
        #expect(index.entries[home.id] == nil)
        #expect(SearchEntry.entries(for: .nameOnly(home)).isEmpty)
    }

    @Test func theDemoIsNeverIndexed() throws {
        let suite = "ww-search-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            tidy()
        }
        // The demo can't be saved, so it never gets a summary, nor entries.
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: folder.appending(path: "Kept"), summaries: summaries)
        #expect(store.add(Demo.connection) == nil)
        #expect(summaries.ids().isEmpty)
        #expect(index.entries.isEmpty)
    }

    // MARK: What's removed

    @Test func aBillDeletedInTheAppLeavesOnTheNextWrite() throws {
        defer { tidy() }
        let id = UUID()
        func summary(bills: [ConnectionSummary.Bill]) -> ConnectionSummary {
            ConnectionSummary(id: id, name: "Home", kind: .server, madeAt: Self.made, keepsNumbers: true,
                              accounts: [], bills: bills)
        }
        let rent = ConnectionSummary.Bill(id: 1, name: "Rent", accountId: 1, accountName: "Checking",
                                          amount: Money(-1500.0), nextDate: november)
        let gym = ConnectionSummary.Bill(id: 2, name: "Gym", accountId: 1, accountName: "Checking",
                                         amount: Money(-40.0), nextDate: november)
        summaries.write(summary(bills: [rent, gym]))
        #expect(index.entries[id]?.map(\.title) == ["Rent", "Gym"])
        summaries.write(summary(bills: [rent]))
        #expect(index.entries[id]?.map(\.title) == ["Rent"])
    }

    @Test func signingOutAndLeavingTheHouseholdRemoveEntries() async throws {
        let suite = "ww-search-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            tidy()
        }
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: folder.appending(path: "Kept"), summaries: summaries)
        let home = try #require(store.add(server, name: "Home", keep: .lastKnown))
        let other = try #require(store.add(Connection(server: URL(string: "https://other.example.test")!, token: "t2"),
                                           keep: .lastKnown))
        let household = try #require(store.add(LocalServer.connection))
        for connection in [home, other, household] { summaries.write(try await sample(connection)) }
        store.remove(home.id)
        #expect(index.entries[home.id] == nil)
        #expect(index.entries[other.id] != nil)
        // Leaving the household, or Delete everywhere, removes its saved connection.
        store.remove(household.id)
        #expect(Set(index.entries.keys) == [other.id])
    }

    @Test func pruningAndDeletingEverythingEmptyTheSearch() throws {
        defer { tidy() }
        let one = ConnectionSummary(id: UUID(), name: "One", kind: .server, madeAt: Self.made, keepsNumbers: true,
                                    accounts: [.init(id: 1, name: "Checking", balance: .zero, monthLow: .zero,
                                                     monthLowDate: nil, toConfirm: nil)], bills: [])
        let two = ConnectionSummary(id: UUID(), name: "Two", kind: .server, madeAt: Self.made, keepsNumbers: true,
                                    accounts: [.init(id: 1, name: "Savings", balance: .zero, monthLow: .zero,
                                                     monthLowDate: nil, toConfirm: nil)], bills: [])
        summaries.write(one)
        summaries.write(two)
        summaries.prune(keeping: [one.id])
        #expect(Set(index.entries.keys) == [one.id])
        summaries.deleteAll()
        #expect(index.entries.isEmpty)
        #expect(index.removedAll == 1)
    }

    @Test func reindexingRebuildsFromTheSummaries() throws {
        defer { tidy() }
        let one = ConnectionSummary(id: UUID(), name: "One", kind: .server, madeAt: Self.made, keepsNumbers: true,
                                    accounts: [.init(id: 1, name: "Checking", balance: .zero, monthLow: .zero,
                                                     monthLowDate: nil, toConfirm: nil)], bills: [])
        // Written before the app indexed anything (an update to the app).
        SummaryStore(directory: folder).write(one)
        #expect(index.entries.isEmpty)
        // Something left from before that no summary backs.
        index.replace(connection: UUID(), with: SearchEntry.entries(for: one))
        summaries.reindex()
        #expect(Set(index.entries.keys) == [one.id])
        #expect(index.entries[one.id]?.map(\.title) == ["Checking"])
    }

    @Test func aLockedPhoneLeavesTheSearchAsItIs() throws {
        defer { tidy() }
        let one = ConnectionSummary(id: UUID(), name: "One", kind: .server, madeAt: Self.made, keepsNumbers: true,
                                    accounts: [.init(id: 1, name: "Checking", balance: .zero, monthLow: .zero,
                                                     monthLowDate: nil, toConfirm: nil)], bills: [])
        summaries.write(one)
        let locked = SummaryStore(directory: folder, protectedDataAvailable: { false }).searchable(index)
        locked.reindex()
        #expect(index.entries[one.id]?.map(\.title) == ["Checking"])
        #expect(index.removedAll == 0)
    }

    // MARK: Where an entry opens

    @Test func anEntrysLinkReadsBack() {
        let id = UUID()
        for link in [SearchLink.bill(id, 12), .account(id, 3)] {
            #expect(SearchLink(id: link.id) == link)
            #expect(link.connection == id)
        }
        #expect(SearchLink.bill(id, 12).id == id.uuidString.lowercased() + "/bill/12")
        for bad in ["", "nope", "\(id)/bill", "\(id)/bill/x", "\(id)/bill/0", "\(id)/line/4", "x/bill/4", "\(id)/bill/4/5"] {
            #expect(SearchLink(id: bad) == nil)
        }
    }
}

/// The phone's search, in memory.
final class MemorySearchIndex: SearchIndexing, @unchecked Sendable {
    private let lock = NSLock()
    private var byConnection: [UUID: [SearchEntry]] = [:]
    private var removeAllCount = 0

    var entries: [UUID: [SearchEntry]] { lock.withLock { byConnection } }
    var removedAll: Int { lock.withLock { removeAllCount } }

    func replace(connection: UUID, with entries: [SearchEntry]) {
        lock.withLock { byConnection[connection] = entries.isEmpty ? nil : entries }
    }

    func remove(connection: UUID) {
        lock.withLock { byConnection[connection] = nil }
    }

    func removeAll() {
        lock.withLock {
            byConnection = [:]
            removeAllCount += 1
        }
    }
}
