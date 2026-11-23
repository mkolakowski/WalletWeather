import Foundation

/// The three pages that each keep an account (iOS #317).
public enum AccountPage: String, CaseIterable, Sendable {
    case forecast, bills, calendar
}

/// Pages follow the same account (decided 2026-11-23, #317): when the person
/// picks an account on Forecast, Bills & income or Calendar, the other pages
/// show it too, unless the switch in Settings → Dates & display is off.
///
/// An account id of 0 is "All accounts". Forecast has no All accounts, so
/// picking it on Bills & income or Calendar leaves Forecast where it is.
public enum AccountFollow {
    /// What the other pages take after a pick on `page`: the account id for
    /// each page that changes. Pages left out stay where they are, and with
    /// `following` off nothing changes.
    public static func others(pickedOn page: AccountPage, account: Int, following: Bool = true) -> [AccountPage: Int] {
        guard following else { return [:] }
        var taken: [AccountPage: Int] = [:]
        for other in AccountPage.allCases where other != page {
            // Forecast has no All accounts.
            if other == .forecast && account == 0 { continue }
            taken[other] = account
        }
        return taken
    }
}
