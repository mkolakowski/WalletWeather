import Foundation

// Bills & income and Calendar (ios-app phase 3, #89): the repeating bills
// and paychecks from `GET /api/recurring`, the Calendar's month from
// `GET /api/calendar`, and moving money with `POST /api/transfers`.

/// How often a bill or paycheck repeats, as the server names it.
public enum Frequency: String, Sendable, Codable, CaseIterable, Identifiable {
    case monthly = "monthly_day"
    case weekly
    case biweekly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly: "Every month"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        }
    }
}

/// `GET /api/recurring`: every bill and paycheck on the accounts you can
/// see (or one account), with the monthly totals.
public struct RecurringList: Sendable, Codable, Equatable {
    public let items: [RecurringItem]
    public let totals: Totals

    public struct Totals: Sendable, Codable, Equatable {
        public let billsCount: Int
        public let billsMonthly: Money
        public let incomeCount: Int
        public let incomeMonthly: Money
        public let netMonthly: Money
    }
}

/// One repeating bill or paycheck.
public struct RecurringItem: Sendable, Codable, Equatable, Identifiable {
    public let id: Int
    public let description: String
    /// Signed: negative for a bill, positive for income.
    public let amount: Money
    /// Unknown cadences decode as nil and show as they are, read-only.
    public let frequency: String
    public let dayOfMonth: Int?
    public let anchorDate: LocalDay?
    public let endDate: LocalDay?
    public let categoryId: Int?
    public let categoryName: String?
    public let categoryColor: String?
    public let notes: String?
    public let active: Bool
    public let expired: Bool
    /// The amount as a month's worth (income positive), or nil.
    public let monthly: Money?
    public let accountId: Int
    public let accountName: String
    /// owner, edit or read.
    public let accountLevel: String
    /// The next date it's due, leaving out skipped and already-paid dates
    /// (server 1.53.0).
    public let nextDate: LocalDay?
    /// The next six such dates, for "skip once".
    public let nextDates: [LocalDay]

    public var kind: Frequency? { Frequency(rawValue: frequency) }
    public var isIncome: Bool { !amount.isNegative }
    public var canEdit: Bool { (accountLevel == "owner" || accountLevel == "edit") && kind != nil }

    /// "Monthly on the 12th", "Every week, Mondays", "Every 2 weeks, Fridays".
    public var howOften: String {
        switch kind {
        case .monthly:
            guard let day = dayOfMonth else { return "Every month" }
            return "Monthly on the \(ordinal(day))"
        case .weekly, .biweekly:
            let base = kind == .weekly ? "Every week" : "Every 2 weeks"
            guard let anchorDate else { return base }
            return "\(base), \(anchorDate.date.formatted(.dateTime.weekday(.wide)))s"
        case nil:
            return frequency
        }
    }
}

/// "1st", "2nd", "3rd", "11th", "22nd".
public func ordinal(_ n: Int) -> String {
    let tens = (n / 10) % 10, ones = n % 10
    let suffix = tens == 1 ? "th" : (ones == 1 ? "st" : ones == 2 ? "nd" : ones == 3 ? "rd" : "th")
    return "\(n)\(suffix)"
}

// MARK: - Adding and changing a bill

/// The bill editor's fields. A new bill starts as a monthly bill on
/// today's day of the month.
public struct BillDraft: Sendable, Equatable {
    public var kind: NewTransactionDraft.Kind
    public var name: String
    public var amountText: String
    public var frequency: Frequency
    /// Monthly: the day it's due (29 to 31 fall on the month's last day
    /// when the month is shorter).
    public var dayOfMonth: Int
    /// Weekly and every 2 weeks: the first date, which sets the weekday.
    /// Monthly: when it starts (nothing before it), if `hasStart`.
    public var start: LocalDay
    public var hasStart: Bool
    public var ends: Bool
    public var endDate: LocalDay
    public var categoryId: Int?
    public var notes: String

    public var amount: Decimal? { parseAmount(amountText) }

    public init(today: LocalDay) {
        kind = .spending
        name = ""
        amountText = ""
        frequency = .monthly
        dayOfMonth = today.day
        start = today
        hasStart = false
        ends = false
        endDate = today
        categoryId = nil
        notes = ""
    }

    public init(_ item: RecurringItem, today: LocalDay) {
        kind = item.isIncome ? .income : .spending
        name = item.description
        amountText = amountString(abs(item.amount.amount))
        frequency = item.kind ?? .monthly
        dayOfMonth = item.dayOfMonth ?? item.anchorDate?.day ?? today.day
        start = item.anchorDate ?? today
        hasStart = item.anchorDate != nil
        ends = item.endDate != nil
        endDate = item.endDate ?? today
        categoryId = item.categoryId
        notes = item.notes ?? ""
    }

    /// What's wrong before it can be saved, or nil.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give it a name." }
        guard let amount, amount > 0 else { return "Enter an amount above zero." }
        if !(1...31).contains(dayOfMonth) { return "Pick a day from 1 to 31." }
        if ends, frequency != .monthly || hasStart, endDate < start { return "It can't end before it starts." }
        if notes.count > 256 { return "Notes can be up to 256 characters." }
        return nil
    }
}

/// The body of `POST /api/accounts/{id}/recurring` and
/// `PATCH /api/recurring/{id}`. A PATCH replaces the whole item, so it
/// carries everything; tags are left out, which leaves them as they are.
public struct RecurringBody: Sendable, Encodable, Equatable {
    public let description: String
    public let amount: Decimal
    public let frequency: Frequency
    public let dayOfMonth: Int?
    public let anchorDate: LocalDay?
    public let endDate: LocalDay?
    public let categoryId: Int?
    public let notes: String?
    public let active: Bool

    enum CodingKeys: String, CodingKey {
        case description, amount, frequency, notes, active
        case dayOfMonth = "day_of_month", anchorDate = "anchor_date", endDate = "end_date", categoryId = "category_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(description, forKey: .description)
        try c.encode(Double(Money(amount).amount.description) ?? 0, forKey: .amount)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(dayOfMonth, forKey: .dayOfMonth)
        try c.encode(anchorDate, forKey: .anchorDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(notes, forKey: .notes)
        try c.encode(active, forKey: .active)
    }

    /// From the editor. `active` is kept from the item being changed.
    public init(_ draft: BillDraft, active: Bool = true) {
        description = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        amount = (draft.kind == .spending ? -1 : 1) * abs(draft.amount ?? 0)
        frequency = draft.frequency
        switch draft.frequency {
        case .monthly:
            dayOfMonth = draft.dayOfMonth
            anchorDate = draft.hasStart ? draft.start : nil
        case .weekly, .biweekly:
            dayOfMonth = nil
            anchorDate = draft.start
        }
        endDate = draft.ends ? draft.endDate : nil
        categoryId = draft.categoryId
        let trimmed = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmed.isEmpty ? nil : trimmed
        self.active = active
    }

    /// The item as it is, ending after `last` (End, decided 2026-11-15).
    public init(ending item: RecurringItem, after last: LocalDay) {
        var draft = BillDraft(item, today: last)
        draft.ends = true
        draft.endDate = last
        self.init(draft, active: item.active)
    }
}

// MARK: - The Calendar

/// `GET /api/calendar?start=&end=[&account_id=]`: the month's lines on
/// every account you can see, or one; with one account, each day's
/// closing balance too.
public struct CalendarMonth: Sendable, Codable, Equatable {
    public let start: LocalDay
    public let end: LocalDay
    public let events: [CalendarEvent]
    /// `YYYY-MM-DD` → the day's closing balance; nil across accounts.
    public let dailyBalances: [String: Money]?

    public func balance(on day: LocalDay) -> Money? { dailyBalances?[day.description] }

    /// The lines on `day`, as the server sorts them.
    public func events(on day: LocalDay) -> [CalendarEvent] { events.filter { $0.date == day } }

    /// What a day's cell shows: whether bills, income or transfers fall on
    /// it, and their net.
    public func summary(of day: LocalDay) -> DaySummary {
        var s = DaySummary()
        for e in events where e.date == day {
            let amount = e.amount ?? .zero
            if e.isTransfer { s.hasTransfer = true } else if amount.isNegative { s.hasBill = true } else { s.hasIncome = true }
            s.net = s.net + amount
            s.count += 1
        }
        return s
    }

    public struct DaySummary: Sendable, Equatable {
        public var hasBill = false
        public var hasIncome = false
        public var hasTransfer = false
        public var net = Money.zero
        public var count = 0
    }
}

/// One line on the Calendar.
public struct CalendarEvent: Sendable, Codable, Equatable, Identifiable {
    /// The planned date (or the paid date for a line with none).
    public let date: LocalDay
    public let accountId: Int
    public let accountName: String
    public let description: String
    /// The real amount when paid, else the planned one.
    public let amount: Money?
    public let categoryName: String?
    public let categoryColor: String?
    public let recurringId: Int?
    public let transactionId: Int?
    public let transferId: Int?
    public let isActualReal: Bool
    public let notes: String?

    public var isTransfer: Bool { transferId != nil }
    public var isPaid: Bool { isActualReal }

    public var id: String {
        "\(accountId)-\(transactionId.map { "t\($0)" } ?? "r\(recurringId ?? 0)")-\(date)-\(description)"
    }
}

// MARK: - Moving money

/// The Move money sheet: from one account to another, on a day.
public struct MoveMoneyDraft: Sendable, Equatable {
    public var fromAccountId: Int?
    public var toAccountId: Int?
    public var amountText = ""
    public var date: LocalDay
    public var description = "Transfer"
    public var notes = ""

    public init(today: LocalDay, from: Int? = nil, to: Int? = nil) {
        date = today
        fromAccountId = from
        toAccountId = to
    }

    public var amount: Decimal? { parseAmount(amountText) }

    public var problem: String? {
        guard let from = fromAccountId, let to = toAccountId else { return "Pick both accounts." }
        if from == to { return "Pick two different accounts." }
        guard let amount, amount > 0 else { return "Enter an amount above zero." }
        if description.count > 100 { return "The description can be up to 100 characters." }
        if notes.count > 256 { return "Notes can be up to 256 characters." }
        return nil
    }
}

/// The body of `POST /api/transfers`.
public struct TransferBody: Sendable, Encodable, Equatable {
    public let fromAccountId: Int
    public let toAccountId: Int
    public let amount: Double
    public let transferDate: LocalDay
    public let description: String
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case amount, description, notes
        case fromAccountId = "from_account_id", toAccountId = "to_account_id", transferDate = "transfer_date"
    }

    public init?(_ draft: MoveMoneyDraft) {
        guard draft.problem == nil, let from = draft.fromAccountId, let to = draft.toAccountId,
              let amount = draft.amount else { return nil }
        fromAccountId = from
        toAccountId = to
        self.amount = Double(Money(amount).amount.description) ?? 0
        transferDate = draft.date
        let name = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        description = name.isEmpty ? "Transfer" : name
        let trimmed = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmed.isEmpty ? nil : trimmed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fromAccountId, forKey: .fromAccountId)
        try c.encode(toAccountId, forKey: .toAccountId)
        try c.encode(amount, forKey: .amount)
        try c.encode(transferDate, forKey: .transferDate)
        try c.encode(description, forKey: .description)
        try c.encode(notes, forKey: .notes)
    }
}

/// `POST /api/transfers`: the money moved, as much as the app shows.
public struct Transfer: Sendable, Codable, Equatable, Identifiable {
    public let id: Int
    public let fromAccountName: String?
    public let toAccountName: String?
    public let amount: Money
    public let transferDate: LocalDay
}
