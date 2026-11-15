import Foundation
import Testing
@testable import WalletWeatherKit

/// The responses the app reads, decoded from samples recorded from the demo
/// server (`DEMO_MODE=true`) at app 1.50.0 (version, me, and the
/// Forecast page's samples at 1.52.0). Re-record them when the server's
/// shape tests (apps/server/tests/test_app_shapes.py) change.
struct DecodingTests {
    func sample<T: Decodable>(_ name: String, as type: T.Type = T.self, status: Int = 200) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
        let data = try Data(contentsOf: url)
        let response = HTTPURLResponse(url: URL(string: "https://ww.example/api/x")!, statusCode: status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        return try APIClient.decode(T.self, data: data, response: response, path: "/api/x")
    }

    @Test func version() throws {
        let v: ServerVersion = try sample("version")
        #expect(v.appVersion == "1.52.0")
        #expect(v.schemaVersion == "19")
    }

    @Test func me() throws {
        let me: Me = try sample("me")
        #expect(me.email == "admin@demo.walletweather.local")
        #expect(me.noticeRequired == false)
        #expect(me.isAdmin)
    }

    @Test func accounts() throws {
        let accounts: [Account] = try sample("accounts")
        #expect(accounts.map(\.name) == ["Checking", "Savings", "Credit Card"])
        #expect(accounts[2].currentBalance == Money(Decimal(string: "-955.48")!))
        #expect(accounts.allSatisfy { $0.canEdit })
    }

    @Test func dashboardRoundsToCents() throws {
        let dash: Dashboard = try sample("dashboard")
        let checking = try #require(dash.cards.first)
        #expect(checking.name == "Checking")
        // 7594.980000000001 on the wire.
        #expect(checking.forecastEnd.formatted == "$7,594.98")
        #expect(checking.forecastLowDate == LocalDay("2026-11-11"))
        #expect(checking.currentBalance.formatted == "$4,854.97")
        let rest = dash.restOfMonth
        #expect(rest.count == dash.cards.map(\.upcomingCount).reduce(0, +))
    }

    @Test(arguments: ["charts-month", "charts-90d"])
    func charts(_ name: String) throws {
        let charts: DashboardCharts = try sample(name)
        #expect(!charts.accounts.isEmpty)
        let first = try #require(charts.accounts.first)
        #expect(first.balanceTrend.first?.date == charts.start)
        #expect(first.balanceTrend.last?.date == charts.end)
        #expect(first.topCategories.count <= 6)
    }

    @Test func pinnedReports() throws {
        let saved: [SavedReport] = try sample("saved-reports")
        #expect(saved.filter(\.pinned).map(\.name) == ["This month's spending"])
        let run: ReportRun = try sample("report-run")
        #expect(run.rangeLabel == "November 2026")
        #expect(run.topGroups.count <= 5)
        #expect(run.topGroups.first?.name == "Rent/Mortgage")
        #expect(run.itemCount > 0)
    }

    @Test func issuedToken() throws {
        let token: IssuedToken = try sample("token")
        #expect(token.token.hasPrefix("ww_"))
        #expect(token.name == "iPhone Duo")
        #expect(token.user.email == "admin@demo.walletweather.local")
    }

    @Test func revokedTokenIsItsOwnError() throws {
        #expect(throws: APIError.tokenRevoked) { let _: Me = try sample("error-revoked", status: 401) }
    }
}
