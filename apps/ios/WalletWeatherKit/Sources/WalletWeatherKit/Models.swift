import Foundation

// What the app reads from the server. Only the fields the app uses are
// decoded, so a field the web app adds doesn't break the app; a field it
// drops or renames does, which the server's shape tests
// (apps/server/tests/test_app_shapes.py) and the recorded samples in
// Tests/WalletWeatherKitTests/Samples guard against.

/// `GET /api/version`.
public struct ServerVersion: Sendable, Codable, Equatable {
    public let appVersion: String
    public let schemaVersion: String
}

/// `GET /api/me`.
public struct Me: Sendable, Codable, Equatable {
    public let id: Int
    public let email: String
    public let name: String?
    public let isAdmin: Bool
    public let noticeRequired: Bool
    /// What the app's token may do: read, full or admin (server 1.52.0).
    public let tokenAccess: String?
    /// The theme saved in the web app, for "Match the web app" (#102).
    public let themePreference: String?
    /// How the web app writes dates, `short` or `iso` (server 1.98.0); nil
    /// from an older server, the demo and the household on this iPhone, which
    /// read as short (#296).
    public let dateFormat: String?

    /// A read-only token: the app shows no editing anywhere.
    public var isReadOnly: Bool { tokenAccess == "read" }
}

/// One of `GET /api/accounts`.
public struct Account: Sendable, Codable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let currentBalance: Money
    /// owner, edit or read: what this person may do with the account.
    public let level: String

    public var canEdit: Bool { level == "owner" || level == "edit" }
}

/// A new account: `POST /api/accounts` (#235).
public struct AccountBody: Sendable, Encodable, Equatable {
    public let name: String
    public let startingBalance: Double
    public let startingDate: LocalDay

    enum CodingKeys: String, CodingKey {
        case name, startingBalance = "starting_balance", startingDate = "starting_date"
    }

    public init(name: String, startingBalance: Double, startingDate: LocalDay) {
        self.name = name
        self.startingBalance = startingBalance
        self.startingDate = startingDate
    }
}

/// What a create answers: the new row's id.
public struct CreatedID: Sendable, Decodable, Equatable {
    public let id: Int
}

/// `GET /api/dashboard`: a card per account for the current month.
public struct Dashboard: Sendable, Codable, Equatable {
    public let cards: [Card]

    public struct Card: Sendable, Codable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let monthLabel: String
        public let openingBalance: Money
        public let currentBalance: Money
        public let forecastEnd: Money
        public let actualEnd: Money
        public let forecastHigh: Money
        public let forecastHighDate: LocalDay?
        public let forecastLow: Money
        public let forecastLowDate: LocalDay?
        public let actualHigh: Money
        public let actualLow: Money
        public let upcomingCount: Int
        public let upcomingNet: Money
    }

    /// "Rest of this month" across every account, as the web Dashboard sums it.
    public var restOfMonth: (count: Int, net: Money, projected: Money) {
        cards.reduce((0, Money.zero, Money.zero)) { sum, card in
            (sum.0 + card.upcomingCount, sum.1 + card.upcomingNet, sum.2 + card.forecastEnd)
        }
    }
}

/// The three windows of the Dashboard's charts.
public enum ChartWindow: String, Sendable, Codable, CaseIterable, Identifiable {
    case month
    case days30 = "30d"
    case days90 = "90d"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .month: "Month"
        case .days30: "30 days"
        case .days90: "90 days"
        }
    }
}

/// `GET /api/dashboard/charts`.
public struct DashboardCharts: Sendable, Codable, Equatable {
    public let window: ChartWindow
    public let label: String
    public let start: LocalDay
    public let end: LocalDay
    public let accounts: [AccountCharts]

    public struct AccountCharts: Sendable, Codable, Equatable, Identifiable {
        public let accountId: Int
        public let accountName: String
        public let totals: Totals
        public let categories: [CategorySpend]
        public let balanceTrend: [BalancePoint]

        public var id: Int { accountId }

        /// The top five categories by actual spending and the rest as
        /// "Other", as the web app's donut shows them.
        public var topCategories: [CategorySpend] {
            let spent = categories.filter { $0.spendingActual.amount > 0 }
                .sorted { $0.spendingActual > $1.spendingActual }
            guard spent.count > 5 else { return spent }
            let rest = spent.dropFirst(5).reduce(Money.zero) { $0 + $1.spendingActual }
            return Array(spent.prefix(5)) + [CategorySpend(name: "Other", color: nil, spendingActual: rest)]
        }

        public var totalSpending: Money {
            categories.reduce(Money.zero) { $0 + $1.spendingActual }
        }
    }

    public struct Totals: Sendable, Codable, Equatable {
        public let incomeActual: Money
        public let spendingActual: Money
        public let netActual: Money
        public let incomeForecast: Money
        public let spendingForecast: Money
        public let netForecast: Money
    }

    public struct CategorySpend: Sendable, Codable, Equatable, Identifiable {
        public let name: String
        /// `#rrggbb`, or nil when the category has no colour.
        public let color: String?
        public let spendingActual: Money

        public var id: String { name }

        public init(name: String, color: String?, spendingActual: Money) {
            self.name = name
            self.color = color
            self.spendingActual = spendingActual
        }
    }

    public struct BalancePoint: Sendable, Codable, Equatable, Identifiable {
        public let date: LocalDay
        public let balance: Money

        public var id: LocalDay { date }
    }
}

/// One of `GET /api/saved-reports`.
public struct SavedReport: Sendable, Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let pinned: Bool
}

/// `POST /api/saved-reports/{id}/run`: a saved report's groups and totals, for
/// a pinned report on the Dashboard and the Reports page under More.
public struct ReportRun: Sendable, Codable, Equatable {
    public let rangeLabel: String
    public let groups: [Group]
    public let totals: Totals

    public struct Group: Sendable, Codable, Equatable, Identifiable {
        public let name: String
        public let color: String?
        public let actualTotal: Money
        public let actualCount: Int
        public let forecastTotal: Money

        public var id: String { name }
    }

    public struct Totals: Sendable, Codable, Equatable {
        public let actualIncome: Money
        public let actualSpending: Money
        public let actualNet: Money
        public let forecastNet: Money
    }

    public var itemCount: Int { groups.reduce(0) { $0 + $1.actualCount } }

    /// The five biggest groups by size, as the web app's pinned report bars.
    public var topGroups: [Group] {
        Array(groups.filter { $0.actualTotal.amount != 0 }
            .sorted { abs($0.actualTotal.amount) > abs($1.actualTotal.amount) }
            .prefix(5))
    }
}

/// `POST /api/app-sign-in/token`: the app's new token, shown once.
public struct IssuedToken: Sendable, Codable, Equatable {
    public let id: Int
    public let name: String
    public let access: String
    public let token: String
    public let expiresAt: String?
    public let user: User

    public struct User: Sendable, Codable, Equatable {
        public let id: Int
        public let email: String
    }
}

/// `{"detail": "..."}`, the server's error answer.
struct ServerError: Decodable {
    let detail: String
    /// Set on the password sign-in's answer when the account has two-factor
    /// sign-in on and a code is missing or wrong (#166).
    let twoFactorRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case detail
        case twoFactorRequired = "two_factor_required"
    }
}
