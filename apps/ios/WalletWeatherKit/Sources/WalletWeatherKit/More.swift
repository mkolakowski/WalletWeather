import Foundation

// The pages under More (ios-app phase 5, #91), read-only: Net worth from
// `GET /api/networth`, Budgets from `GET /api/budgets/progress`, and
// Reports (`POST /api/saved-reports/{id}/run`, in Models.swift).

/// `GET /api/networth?window=&today=`: every account added up over the
/// window, day by day, and each account's own figures.
public struct NetWorth: Sendable, Codable, Equatable {
    public let window: ChartWindow
    public let label: String
    public let start: LocalDay
    public let end: LocalDay
    public let openingTotal: Money
    public let forecastEndTotal: Money
    public let actualEndTotal: Money
    public let trend: [DashboardCharts.BalancePoint]
    public let accounts: [AccountWorth]

    public struct AccountWorth: Sendable, Codable, Equatable, Identifiable {
        public let accountId: Int
        public let accountName: String
        public let openingBalance: Money
        public let forecastEnd: Money
        public let actualEnd: Money
        public var id: Int { accountId }
    }

    /// The total today: the trend's point for today, or its last one when
    /// the window ends earlier.
    public func total(on day: LocalDay) -> Money? {
        trend.last { $0.date <= day }?.balance
    }

    /// How far the total moved over the window so far.
    public func change(through day: LocalDay) -> Money? {
        total(on: day).map { Money($0.amount - openingTotal.amount) }
    }
}

/// `GET /api/budgets/progress?window=&today=`: spending against each
/// budget, and categories with spending but no budget.
public struct BudgetProgress: Sendable, Codable, Equatable {
    public let label: String
    public let rows: [Row]
    public let totals: Totals

    public struct Row: Sendable, Codable, Equatable, Identifiable {
        public let categoryId: Int?
        public let categoryName: String
        public let categoryColor: String?
        public let budget: Money
        public let spend: Money
        public let remaining: Money
        /// Spent as a percentage of the budget; nil with no budget.
        public let pct: Double?
        public let over: Bool
        public let hasBudget: Bool

        public var id: String { categoryName }
        /// 0…1 for the bar, capped at 1 when over.
        public var fraction: Double { min(max((pct ?? 0) / 100, 0), 1) }
    }

    public struct Totals: Sendable, Codable, Equatable {
        public let budget: Money
        public let spend: Money
        public let remaining: Money
    }

    public var budgeted: [Row] { rows.filter(\.hasBudget) }
    public var unbudgeted: [Row] { rows.filter { !$0.hasBudget } }

    /// Spending in budgeted categories only: the server's `totals.spend`
    /// counts every category, budgeted or not.
    public var budgetedSpend: Money { budgeted.reduce(Money.zero) { $0 + $1.spend } }
    public var budgetedLeft: Money { Money(totals.budget.amount - budgetedSpend.amount) }
    public var unbudgetedSpend: Money { unbudgeted.reduce(Money.zero) { $0 + $1.spend } }
}
