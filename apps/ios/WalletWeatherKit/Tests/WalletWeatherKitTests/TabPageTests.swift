import Testing
@testable import WalletWeatherKit

/// Choosing the tab bar's pages (#158, #174).
struct TabPageTests {
    @Test func nothingStoredIsTheDefault() {
        #expect(TabPage.bar(from: nil) == [.dashboard, .forecast, .bills])
        #expect(TabPage.notIn(TabPage.defaultBar) == [.calendar, .netWorth, .budgets, .reports])
    }

    @Test func roundTrips() {
        let bar: [TabPage] = [.forecast, .netWorth, .dashboard]
        #expect(TabPage.bar(from: TabPage.stored(bar)) == bar)
        #expect(TabPage.bar(from: "") == [])
    }

    @Test func dropsUnknownAndRepeatedAndCapsAtThree() {
        #expect(TabPage.maxInBar == 3)
        #expect(TabPage.bar(from: "forecast,weather,forecast,bills") == [.forecast, .bills])
        #expect(TabPage.bar(from: "dashboard,forecast,bills,calendar,budgets").count == TabPage.maxInBar)
    }

    /// A bar of four saved before #174 keeps its first three, in order.
    @Test func anOldBarOfFourKeepsItsFirstThree() {
        #expect(TabPage.bar(from: "calendar,netWorth,forecast,dashboard") == [.calendar, .netWorth, .forecast])
    }

    @Test func swappingKeepsThePlace() {
        let bar: [TabPage] = [.dashboard, .forecast, .bills]
        #expect(TabPage.swapping(.forecast, for: .calendar, in: bar) == [.dashboard, .calendar, .bills])
        // Not in the bar, or already in it: unchanged.
        #expect(TabPage.swapping(.reports, for: .calendar, in: bar) == bar)
        #expect(TabPage.swapping(.forecast, for: .bills, in: bar) == bar)
    }

    @Test func everyPageHasATitleAndSymbol() {
        #expect(TabPage.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }
}
