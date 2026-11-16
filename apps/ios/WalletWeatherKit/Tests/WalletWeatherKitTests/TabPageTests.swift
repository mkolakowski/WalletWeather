import Testing
@testable import WalletWeatherKit

/// Choosing the tab bar's pages (#158).
struct TabPageTests {
    @Test func nothingStoredIsTheDefault() {
        #expect(TabPage.bar(from: nil) == [.dashboard, .forecast, .bills, .calendar])
        #expect(TabPage.notIn(TabPage.defaultBar) == [.netWorth, .budgets, .reports])
    }

    @Test func roundTrips() {
        let bar: [TabPage] = [.forecast, .netWorth, .dashboard]
        #expect(TabPage.bar(from: TabPage.stored(bar)) == bar)
        #expect(TabPage.bar(from: "") == [])
    }

    @Test func dropsUnknownAndRepeatedAndCapsAtFour() {
        #expect(TabPage.bar(from: "forecast,weather,forecast,bills") == [.forecast, .bills])
        #expect(TabPage.bar(from: "dashboard,forecast,bills,calendar,budgets").count == TabPage.maxInBar)
    }

    @Test func everyPageHasATitleAndSymbol() {
        #expect(TabPage.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }
}
