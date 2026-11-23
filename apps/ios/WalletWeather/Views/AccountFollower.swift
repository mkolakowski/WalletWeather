import SwiftUI
import WalletWeatherKit

/// Writes the other pages' accounts after a pick (#317). It holds the three
/// pages' scene-storage keys, which are shared by the window, so the page
/// that was picked on can set the others'; the rule itself is
/// `AccountFollow` in the Kit. Call it only where the person picks, never
/// from `onChange(of: accountId)`, which also fires when a page falls back,
/// the Debug setting sets one or the connection in front changes.
struct AccountFollower: DynamicProperty {
    @SceneStorage("forecast.account") private var forecast = 0
    @SceneStorage("bills.account") private var bills = 0
    @SceneStorage("calendar.account") private var calendar = 0

    func picked(_ account: Int, on page: AccountPage, following: Bool) {
        for (other, id) in AccountFollow.others(pickedOn: page, account: account, following: following) {
            switch other {
            case .forecast: if forecast != id { forecast = id }
            case .bills: if bills != id { bills = id }
            case .calendar: if calendar != id { calendar = id }
            }
        }
    }
}
