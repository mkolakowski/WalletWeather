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

    @Test func dropsUnknownAndRepeatedAndCapsAtFour() {
        #expect(TabPage.maxInBar == 4)
        #expect(TabPage.bar(from: "forecast,weather,forecast,bills") == [.forecast, .bills])
        #expect(TabPage.bar(from: "dashboard,forecast,bills,calendar,budgets").count == TabPage.maxInBar)
    }

    /// Three along the bottom, four down the side: a fourth page waits while
    /// the bar is along the bottom, and a bar saved before #174 keeps all four.
    @Test func showsThreeAtTheBottomAndFourDownTheSide() {
        let bar = TabPage.bar(from: "calendar,netWorth,forecast,dashboard")
        #expect(bar == [.calendar, .netWorth, .forecast, .dashboard])
        #expect(TabPage.shown(bar, onSide: false) == [.calendar, .netWorth, .forecast])
        #expect(TabPage.shown(bar, onSide: true) == bar)
        #expect(TabPage.room(onSide: false) == 3)
        #expect(TabPage.shown(TabPage.defaultBar, onSide: true) == TabPage.defaultBar)
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
