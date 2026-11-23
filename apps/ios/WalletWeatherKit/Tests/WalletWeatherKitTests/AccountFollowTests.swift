import Testing
@testable import WalletWeatherKit

/// Pages follow the same account (#317).
struct AccountFollowTests {
    @Test func aPickOnForecastMovesBillsAndCalendar() {
        #expect(AccountFollow.others(pickedOn: .forecast, account: 7) == [.bills: 7, .calendar: 7])
    }

    @Test func aPickOnBillsMovesForecastAndCalendar() {
        #expect(AccountFollow.others(pickedOn: .bills, account: 7) == [.forecast: 7, .calendar: 7])
    }

    @Test func aPickOnCalendarMovesForecastAndBills() {
        #expect(AccountFollow.others(pickedOn: .calendar, account: 7) == [.forecast: 7, .bills: 7])
    }

    @Test func allAccountsOnBillsMovesOnlyCalendar() {
        #expect(AccountFollow.others(pickedOn: .bills, account: 0) == [.calendar: 0])
    }

    @Test func allAccountsOnCalendarMovesOnlyBills() {
        #expect(AccountFollow.others(pickedOn: .calendar, account: 0) == [.bills: 0])
    }

    @Test func withTheSwitchOffNothingElseChanges() {
        for page in AccountPage.allCases {
            for account in [0, 7] {
                #expect(AccountFollow.others(pickedOn: page, account: account, following: false).isEmpty)
            }
        }
    }

    @Test func thePickedPageIsNeverInTheResult() {
        for page in AccountPage.allCases {
            #expect(AccountFollow.others(pickedOn: page, account: 3)[page] == nil)
        }
    }
}
