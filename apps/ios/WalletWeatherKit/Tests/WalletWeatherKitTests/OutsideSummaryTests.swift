import Foundation
import Testing
@testable import WalletWeatherKit

/// The summary widgets read (Plans/outside-the-app.md, phase 1, #318):
/// written, read, refused while the phone is locked, deleted with its
/// connection (sign-out, leaving the household, Delete everywhere) and
/// emptied on Nothing, a server set to Nothing getting no numbers, and the
/// widgets' privacy rules. In temporary folders and settings only: never the
/// app group.
struct OutsideSummaryTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "summary-tests-\(UUID().uuidString)")
    var summaries: SummaryStore { SummaryStore(directory: folder) }
    let november = LocalDay(year: 2026, month: 11, day: 15)
    static let made = Date(timeIntervalSinceReferenceDate: 800_000_000)

    let server = Connection(server: URL(string: "https://money.example.test")!, token: "ww_token")

    func tidy() { try? FileManager.default.removeItem(at: folder) }

    func saved(keep: KeepChoice, connection: Connection? = nil, name: String = "Home") -> SavedConnection {
        SavedConnection(connection: connection ?? server, name: name, keep: keep)
    }

    /// A summary loaded from the demo's samples, as a server keeping
    /// Last-known numbers would get one.
    func sample(_ saved: SavedConnection, readOnly: Bool = false) async throws -> ConnectionSummary {
        try await ConnectionSummary.fetch(saved, client: APIClient(connection: Demo.connection), readOnly: readOnly,
                                          today: november, now: Self.made)
    }

    // MARK: What it holds

    @Test func holdsBalancesLowsBillsAndToConfirm() async throws {
        let home = saved(keep: .lastKnown)
        let summary = try await sample(home)
        #expect(summary.id == home.id)
        #expect(summary.name == "Home")
        #expect(summary.kind == .server)
        #expect(summary.madeAt == Self.made)
        #expect(summary.keepsNumbers)
        #expect(summary.accounts.map(\.name) == ["Checking", "Savings", "Credit Card"])
        let checking = try #require(summary.accounts.first)
        #expect(checking.balance == Money(4854.97))
        #expect(checking.monthLow <= checking.balance)
        #expect(summary.bills.count == 7)
        // The demo's accounts are all the owner's: each counts To confirm.
        #expect(summary.accounts.allSatisfy { $0.toConfirm != nil })
        #expect(summary.toConfirm == summary.accounts.compactMap(\.toConfirm).reduce(0, +))
        let next = summary.nextBills(today: november)
        #expect(next.count <= 3)
        #expect(next.allSatisfy { !$0.isIncome && $0.nextDate! >= november })
        #expect(next.map(\.nextDate!) == next.map(\.nextDate!).sorted())
    }

    @Test func aReadOnlyTokenCountsNoToConfirm() async throws {
        let summary = try await sample(saved(keep: .lastKnown), readOnly: true)
        #expect(summary.accounts.allSatisfy { $0.toConfirm == nil })
        #expect(summary.toConfirm == nil)
        #expect(summary.toConfirmAccount == nil)
    }

    @Test func aServerSetToNothingGetsItsNameAndNoNumbers() async throws {
        let nothing = saved(keep: .nothing, name: "Mum & Dad")
        // Asks nothing: the demo would answer, so numbers here would mean it asked.
        let summary = try await sample(nothing)
        #expect(summary == ConnectionSummary.nameOnly(nothing, madeAt: Self.made))
        #expect(summary.name == "Mum & Dad")
        #expect(!summary.keepsNumbers)
        #expect(summary.accounts.isEmpty && summary.bills.isEmpty)
        // Even handed the numbers, it keeps none.
        let dashboard = try await APIClient(connection: Demo.connection).dashboard(today: november)
        let recurring = try await APIClient(connection: Demo.connection).recurring(today: november)
        let made = ConnectionSummary.make(nothing, dashboard: dashboard, recurring: recurring, toConfirm: [1: 2])
        #expect(made.accounts.isEmpty && made.bills.isEmpty && made.toConfirm == nil)
        // A summary built by hand with numbers but keepsNumbers false drops them too.
        let forced = ConnectionSummary(id: nothing.id, name: "x", kind: .server, madeAt: .now, keepsNumbers: false,
                                       accounts: try await sample(saved(keep: .lastKnown)).accounts, bills: [])
        #expect(forced.accounts.isEmpty)
    }

    @Test func theHouseholdOnThisIPhoneAlwaysHasNumbers() {
        let household = SavedConnection(connection: LocalServer.connection, keep: .nothing)
        #expect(household.kind == .thisPhone)
        #expect(ConnectionSummary.keepsNumbers(household))
        #expect(!ConnectionSummary.keepsNumbers(saved(keep: .nothing)))
        #expect(ConnectionSummary.keepsNumbers(saved(keep: .lastKnown)))
    }

    // MARK: Written and read

    @Test func writtenAndReadBack() async throws {
        defer { tidy() }
        let summary = try await sample(saved(keep: .lastKnown))
        #expect(summaries.read(summary.id) == .missing)
        #expect(summaries.write(summary))
        #expect(summaries.read(summary.id) == .found(summary))
        #expect(summaries.ids() == [summary.id])
        #expect(summaries.all() == [summary])
        // Its file is named for the connection, which later phases rely on.
        let file = folder.appending(path: summary.id.uuidString.lowercased() + ".json")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func leftOutOfBackups() async throws {
        defer { tidy() }
        let summary = try await sample(saved(keep: .lastKnown))
        summaries.write(summary)
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let file = folder.appending(path: SummaryStore.fileName(for: summary.id))
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func refusedWhileThePhoneIsLocked() async throws {
        defer { tidy() }
        let summary = try await sample(saved(keep: .lastKnown))
        summaries.write(summary)
        let locked = SummaryStore(directory: folder, protectedDataAvailable: { false })
        #expect(locked.read(summary.id) == .unreadable)
        #expect(locked.all().isEmpty)
        // Its name is still known from the file's name, for clean-up.
        #expect(locked.ids() == [summary.id])
        // A file that isn't a summary, or is from a newer app, is unreadable too.
        try Data("not json".utf8).write(to: folder.appending(path: SummaryStore.fileName(for: summary.id)))
        #expect(summaries.read(summary.id) == .unreadable)
    }

    @Test func aNewerFileIsNotRead() throws {
        defer { tidy() }
        let newer = ConnectionSummary(id: UUID(), name: "Later", kind: .server, madeAt: .now, keepsNumbers: false,
                                      accounts: [], bills: [], version: ConnectionSummary.currentVersion + 1)
        summaries.write(newer)
        #expect(summaries.read(newer.id) == .unreadable)
    }

    // MARK: Deleted

    /// Sign out removes a connection through the store, as do leaving the
    /// household on this iPhone and Delete everywhere.
    @Test func deletedOnSignOutWithTheConnection() async throws {
        let suite = "ww-summary-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let keptRoot = folder.appending(path: "Kept")
        defer {
            defaults.removePersistentDomain(forName: suite)
            tidy()
        }
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults, keptRoot: keptRoot,
                                    summaries: summaries)
        let home = try #require(store.add(server, name: "Home", keep: .lastKnown))
        let other = try #require(store.add(Connection(server: URL(string: "https://other.example.test")!, token: "t2"),
                                           keep: .lastKnown))
        let household = try #require(store.add(LocalServer.connection))
        for connection in [home, other, household] { summaries.write(try await sample(connection)) }
        store.remove(home.id)
        #expect(summaries.read(home.id) == .missing)
        #expect(summaries.read(other.id) != .missing)
        // Leaving the household, or Delete everywhere, removes its saved connection.
        store.remove(household.id)
        #expect(summaries.read(household.id) == .missing)
        #expect(Set(summaries.ids()) == [other.id])
    }

    @Test func choosingNothingLeavesOnlyTheName() async throws {
        defer { tidy() }
        var home = saved(keep: .lastKnown)
        summaries.write(try await sample(home))
        home.keep = .nothing
        summaries.write(.nameOnly(home))
        guard case let .found(after) = summaries.read(home.id) else {
            Issue.record("No summary after choosing Nothing")
            return
        }
        #expect(!after.keepsNumbers)
        #expect(after.accounts.isEmpty && after.bills.isEmpty)
        // Nothing of the numbers is left in the file.
        let text = try String(contentsOf: folder.appending(path: SummaryStore.fileName(for: home.id)), encoding: .utf8)
        #expect(!text.contains("Checking") && !text.contains("4854"))
    }

    @Test func connectionsNoLongerSavedArePruned() throws {
        defer { tidy() }
        let kept = saved(keep: .nothing), gone = saved(keep: .nothing, name: "Gone")
        summaries.write(.nameOnly(kept))
        summaries.write(.nameOnly(gone))
        summaries.prune(keeping: [kept.id])
        #expect(summaries.ids() == [kept.id])
        summaries.deleteAll()
        #expect(summaries.ids().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    // MARK: What a widget shows

    @Test func amountsAreHiddenWhenLockedOrWithTheAppLock() async throws {
        let summary = try await sample(saved(keep: .lastKnown))
        #expect(WidgetContent.decide(.found(summary), name: "Home", lockOn: false) == .summary(summary, amountsHidden: false))
        #expect(WidgetContent.decide(.found(summary), name: "Home", lockOn: true) == .summary(summary, amountsHidden: true))
        #expect(WidgetContent.decide(.unreadable, name: "Home", lockOn: false) == .locked(name: "Home"))
        #expect(WidgetContent.decide(.missing, name: "Home", lockOn: false) == .noConnection)
        let nothing = ConnectionSummary.nameOnly(saved(keep: .nothing, name: "Mum & Dad"))
        #expect(WidgetContent.decide(.found(nothing), name: nil, lockOn: false) == .keepsNothing(name: "Mum & Dad"))
        #expect(WidgetContent.hiddenAmount == "••••")
    }

    @Test func theBalanceWidgetFallsBackToTheFirstAccount() async throws {
        let summary = try await sample(saved(keep: .lastKnown))
        #expect(summary.account(2)?.name == "Savings")
        #expect(summary.account(999)?.name == "Checking")
        #expect(summary.account(nil)?.name == "Checking")
    }

    @Test func toConfirmOpensOnTheAccountWithTheMostLines() {
        func account(_ id: Int, _ waiting: Int?) -> ConnectionSummary.Account {
            ConnectionSummary.Account(id: id, name: "A\(id)", balance: .zero, monthLow: .zero, monthLowDate: nil,
                                      toConfirm: waiting)
        }
        let summary = ConnectionSummary(id: UUID(), name: "Home", kind: .server, madeAt: .now, keepsNumbers: true,
                                        accounts: [account(1, 0), account(2, 3), account(3, nil), account(4, 3)], bills: [])
        #expect(summary.toConfirm == 6)
        #expect(summary.toConfirmAccount == 2)
    }

    // MARK: What the app tells the widgets

    @Test func theLockAndTheFrontAreCopiedForTheWidgets() throws {
        let suite = "ww-outside-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = OutsideSettings(defaults: defaults)
        #expect(!settings.lockOn && settings.front == nil)
        let id = UUID()
        settings.lockOn = true
        settings.front = id
        #expect(defaults.bool(forKey: "lock.enabled"))
        #expect(OutsideSettings(defaults: defaults).front == id)
        settings.front = nil
        #expect(settings.front == nil)
        // Without the group, nothing is kept and nothing fails.
        let none = OutsideSettings(defaults: nil)
        none.lockOn = true
        #expect(!none.lockOn)
    }

    // MARK: Links

    @Test func aWidgetsLinkOpensItsPage() throws {
        let id = UUID()
        let url = AppLink.openURL(.toConfirm, connection: id, account: 3)
        #expect(url.absoluteString == "walletweather://open?page=to-confirm&connection=\(id.uuidString.lowercased())&account=3")
        #expect(AppLink(url) == .open(.toConfirm, connection: id, account: 3))
        #expect(AppLink(AppLink.openURL(.bills, connection: nil)) == .open(.bills, connection: nil, account: nil))
        #expect(AppLink(URL(string: "walletweather://open?page=dashboard&account=-2")!) == .open(.dashboard, connection: nil, account: nil))
        #expect(AppLink(URL(string: "walletweather://open?page=elsewhere")!) == nil)
        #expect(AppLink(URL(string: "walletweather://open")!) == nil)
        #expect(AppLink(url)?.state == nil)
    }
}
