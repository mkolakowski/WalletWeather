import Foundation
import Testing
@testable import WalletWeatherKit

/// The pinned clock for comparable pictures (#352).
struct AppClockTests {
    @Test func readsADayOrADayAndTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let noon = try #require(Date.pinned(from: "2026-11-15", calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: noon) == DateComponents(year: 2026, month: 11, day: 15, hour: 12, minute: 0))
        let ten = try #require(Date.pinned(from: "2026-11-15T10:05", calendar: calendar))
        #expect(calendar.component(.hour, from: ten) == 10)
        #expect(calendar.component(.minute, from: ten) == 5)
        #expect(LocalDay.today(calendar: calendar, now: ten) == LocalDay(year: 2026, month: 11, day: 15))
    }

    @Test(arguments: ["", "tomorrow", "2026-11", "2026-11-15T10"])
    func refusesAnythingElse(_ text: String) {
        #expect(Date.pinned(from: text) == nil)
    }

    /// With no launch setting, as in these tests and in every Release build, it's the real clock.
    @Test func isTheRealClockUnlessPinned() {
        #expect(Date.pinnedNow == nil)
        #expect(abs(Date.appNow.timeIntervalSinceNow) < 2)
    }
}
