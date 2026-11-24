import Foundation
import Testing
@testable import WalletWeatherKit

/// The total beside each connection (#329): which row shows one, how old it
/// says it is, and that none shows while locked in the demo.
struct ConnectionTotalsTests {
    private func server(_ host: String, keep: KeepChoice) -> SavedConnection {
        SavedConnection(connection: Connection(server: URL(string: "https://\(host)")!, token: "t"), name: host,
                        keep: keep, account: "me@example.com")
    }

    private func m(_ value: Double) -> Money { Money(value) }
    private let open = ConnectionsVisibility(locked: false)
    private let locked = ConnectionsVisibility(locked: true)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// 2026-11-23 3:00 PM Eastern.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 15))! }

    private func rows(_ saved: [SavedConnection], front: LockGate.Front, visibility: ConnectionsVisibility) -> [ConnectionRow] {
        ConnectionRow.rows(saved: saved, front: front, householdExists: false, visibility: visibility)
    }

    // MARK: - Which row shows a total

    @Test func aServerThatKeepsShowsItsKeptTotalAndAge() {
        let home = server("home.example.com", keep: .lastKnown)
        let keptAt = now.addingTimeInterval(-2 * 3600)
        let readings = ConnectionTotals.readings(saved: [home], keptTotal: { _ in (m(1234.5), keptAt) },
                                                 household: nil, demo: nil)
        let row = rows([home], front: .demo, visibility: open)[0]
        #expect(ConnectionTotals.figure(for: row, among: readings, visibility: open, now: now, calendar: calendar)
            == .init(total: m(1234.5), caption: "as of 2 h ago"))
    }

    @Test func aServerThatKeepsNothingShowsNone() {
        let home = server("home.example.com", keep: .nothing)
        // Even if a stale copy were left in its folder, its choice wins.
        let readings = ConnectionTotals.readings(saved: [home], keptTotal: { _ in (m(5), self.now) },
                                                 household: nil, demo: nil)
        #expect(readings[.saved(home.id)] == nil)
        let row = rows([home], front: .saved(home.id), visibility: open)[0]
        #expect(ConnectionTotals.figure(for: row, among: readings, visibility: open, now: now) == nil)
    }

    @Test func aServerWithNothingKeptYetShowsNone() {
        let home = server("home.example.com", keep: .lastKnown)
        let readings = ConnectionTotals.readings(saved: [home], keptTotal: { _ in nil }, household: nil, demo: nil)
        #expect(readings[.saved(home.id)] == nil)
    }

    @Test func theHouseholdAndTheDemoShowTheirOwn() {
        let readings = ConnectionTotals.readings(saved: [], keptTotal: { _ in nil }, household: m(900), demo: m(7000))
        let all = ConnectionRow.rows(saved: [], front: .demo, householdExists: true, visibility: open)
        let phone = ConnectionTotals.figure(for: all[0], among: readings, visibility: open, now: now)
        #expect(phone == .init(total: m(900), caption: "as of now"))
        let demo = ConnectionTotals.figure(for: all[1], among: readings, visibility: open, now: now)
        #expect(demo == .init(total: m(7000), caption: "sample numbers"))
    }

    @Test func aSavedHouseholdShowsItsTotal() {
        let phone = SavedConnection(connection: LocalServer.connection)
        let readings = ConnectionTotals.readings(saved: [phone], keptTotal: { _ in nil }, household: m(-20), demo: nil)
        let row = rows([phone], front: .saved(phone.id), visibility: open)[0]
        #expect(ConnectionTotals.figure(for: row, among: readings, visibility: open, now: now)?.total == m(-20))
    }

    // MARK: - Locked in the demo

    @Test func lockedInTheDemoNoTotalShows() {
        let home = server("home.example.com", keep: .lastKnown)
        let readings = ConnectionTotals.readings(saved: [home], keptTotal: { _ in (m(10), self.now) },
                                                 household: m(20), demo: m(30))
        #expect(!locked.showsTotals)
        #expect(open.showsTotals)
        for row in ConnectionRow.rows(saved: [home], front: .demo, householdExists: true, visibility: locked) {
            #expect(ConnectionTotals.figure(for: row, among: readings, visibility: locked, now: now) == nil)
        }
        // Unlocked, the same readings show.
        let shown = ConnectionRow.rows(saved: [home], front: .demo, householdExists: true, visibility: open)
            .compactMap { ConnectionTotals.figure(for: $0, among: readings, visibility: open, now: now) }
        #expect(shown.count == 3)
    }

    // MARK: - How old

    @Test func asOfTextFollowsTheKeptBarsStyle() {
        func text(_ ago: TimeInterval) -> String { ConnectionTotals.asOf(now.addingTimeInterval(-ago), now: now, calendar: calendar) }
        #expect(text(10) == "as of just now")
        #expect(text(-30) == "as of just now")
        #expect(text(12 * 60) == "as of 12 min ago")
        #expect(text(2 * 3600 + 600) == "as of 2 h ago")
        // 3:00 PM now: 14 h ago is 1 AM today.
        #expect(text(14 * 3600) == "as of 14 h ago")
        // 16 h ago is 11 PM yesterday.
        #expect(text(16 * 3600) == "as of yesterday")
        #expect(text(30 * 3600).hasPrefix("as of yesterday"))
        #expect(ConnectionTotals.asOf(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!,
                                      now: now, calendar: calendar) == "as of Nov 20")
    }

    // MARK: - From the kept Dashboard

    @Test func theTotalIsTheSumOfEachCardsBalance() throws {
        let url = try #require(Bundle.module.url(forResource: "dashboard", withExtension: "json", subdirectory: "Samples"))
        let data = try Data(contentsOf: url)
        let dashboard = try APIClient.decoder().decode(Dashboard.self, from: data)
        let expected = dashboard.cards.reduce(Money.zero) { $0 + $1.currentBalance }
        #expect(ConnectionTotals.total(of: dashboard) == expected)

        let folder = FileManager.default.temporaryDirectory.appending(path: "totals-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let keeper = KeptResponses(directory: folder)
        let host = URL(string: "https://totals.example.com")!
        #expect(ConnectionTotals.kept(in: keeper, server: host) == nil)
        keeper.save(data, for: KeptResponses.key(server: host, method: "GET", path: "/api/dashboard",
                                                 query: ["today": "2026-11-23"]))
        let kept = try #require(ConnectionTotals.kept(in: keeper, server: host))
        #expect(kept.total == expected)
        #expect(ConnectionTotals.kept(in: keeper, server: URL(string: "https://other.example.com")!) == nil)
    }
}
