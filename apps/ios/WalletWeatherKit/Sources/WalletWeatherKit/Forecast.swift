import Foundation

// The Forecast page (ios-app phase 2, #88): one account's month of lines,
// read from `GET /api/accounts/{id}/forecast`, and what the app sends to
// change a line, the same calls the web app's editor makes.

/// A calendar month, for paging the forecast.
public struct YearMonth: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ day: LocalDay) {
        self.init(year: day.year, month: day.month)
    }

    /// `YYYY-MM`, also how it's kept for the window.
    public var description: String { String(format: "%04d-%02d", year, month) }

    public init?(_ text: String) {
        guard let first = LocalDay(text + "-01") else { return nil }
        self.init(first)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = YearMonth(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM month: \(text)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var start: LocalDay { LocalDay(year: year, month: month, day: 1) }
    public var end: LocalDay { start.endOfMonth }

    public var next: YearMonth { month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1) }
    public var previous: YearMonth { month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1) }

    /// "November 2026".
    public var label: String { start.date.formatted(.dateTime.month(.wide).year()) }

    public func contains(_ day: LocalDay) -> Bool { day.year == year && day.month == month }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}

/// `GET /api/accounts/{id}/forecast?start=&end=&today=`: a month of lines
/// with both running balances, worked out on the server.
public struct ForecastMonth: Sendable, Codable, Equatable {
    public let openingBalance: Money
    public let forecastEndingBalance: Money
    public let actualEndingBalance: Money
    /// Where the account is today, whichever month is shown.
    public let currentBalance: Money
    public let rows: [ForecastLine]
}

extension ForecastMonth {
    /// A line as it is in this month, found again after a reload (#315): by
    /// its transaction when it had one, else, for a projected date of a
    /// repeating bill or paycheck that was saved as a new transaction since,
    /// by the bill and the planned date. Nil when it isn't here any more
    /// (deleted, moved to another month or date, or another account).
    public func reloaded(_ line: ForecastLine) -> ForecastLine? {
        if let transactionId = line.transactionId {
            return rows.first { $0.transactionId == transactionId }
        }
        guard let recurringId = line.recurringId, let planned = line.plannedDate else { return nil }
        return rows.first { $0.recurringId == recurringId && $0.plannedDate == planned && $0.transferId == nil }
    }
}

/// One line of the forecast: a transaction, or a repeating bill or paycheck
/// projected onto a date with nothing saved for it yet.
public struct ForecastLine: Sendable, Codable, Equatable, Identifiable {
    public let forecastDate: LocalDay?
    /// When it cleared; for a line not yet paid, its planned date.
    public let actualDate: LocalDay?
    public let description: String
    public let category: String?
    public let categoryId: Int?
    public let notes: String?
    public let forecastAmount: Money?
    public let forecastBalance: Money
    /// What it really came to; for a line not yet paid, its planned amount.
    public let actualAmount: Money?
    public let actualBalance: Money
    public let diffAmount: Money?
    public let diffBalance: Money
    /// Paid: the real amount and date are recorded.
    public let isActualReal: Bool
    public let recurringId: Int?
    public let transactionId: Int?
    public let transferId: Int?
    /// Its tags (#251); nil from an answer without them.
    public var tags: [TagInfo]?
    /// A bank line that paid no planned line yet: on the Unmatched list
    /// (#239); nil from an answer without it.
    public var bankUnmatched: Bool?

    /// Steady across reloads: the transaction, or the repeating item and
    /// its date. Marking a projected line paid saves it as a transaction,
    /// so its id changes then.
    public var id: String {
        if let transactionId { return "t\(transactionId)" }
        if let recurringId { return "r\(recurringId)-\(plannedDate?.description ?? "")" }
        return "d\(plannedDate?.description ?? "")-\(description)"
    }

    public var isPaid: Bool { isActualReal }
    public var isTransfer: Bool { transferId != nil }
    /// A repeating item's date with nothing saved for it yet.
    public var isProjection: Bool { transactionId == nil }
    public var plannedDate: LocalDay? { forecastDate ?? actualDate }
    public var plannedAmount: Money { forecastAmount ?? actualAmount ?? .zero }
    /// The amount the line counts at: the real one when paid.
    public var amount: Money { isPaid ? (actualAmount ?? plannedAmount) : plannedAmount }

    /// Paid at a different amount, or on a different day, than planned.
    public var differsFromPlan: Bool {
        guard isPaid else { return false }
        if let diffAmount, diffAmount != .zero { return true }
        if let forecastDate, let actualDate, forecastDate != actualDate { return true }
        return false
    }

    /// Whether this line can be changed in the app: on an account you may
    /// edit. Transfers are changed on the web for now.
    public func canEdit(onEditableAccount editable: Bool) -> Bool { editable && !isTransfer }

    /// A line you added: saved, not a transfer, and not from a repeating
    /// bill. Its name, planned date and planned amount can be changed here
    /// (#316); a bill's date changes in its bill.
    public var isOneOff: Bool { transactionId != nil && recurringId == nil && !isTransfer }
}

/// The month at a glance, for the right half of the open Duo: income and
/// spending against plan, what's still to come, the low and the high, and
/// the lines that differ from plan. Transfers count as neither income nor
/// spending, as on the Dashboard.
public struct ForecastSummary: Sendable, Equatable {
    public var incomePlanned = Money.zero
    public var incomeSoFar = Money.zero
    public var spendingPlanned = Money.zero
    public var spendingSoFar = Money.zero
    /// Not paid yet, dated today or later.
    public var comingCount = 0
    public var comingNet = Money.zero
    /// Not paid yet, and their date has passed.
    public var overdue: [ForecastLine] = []
    public var low: (balance: Money, date: LocalDay?)
    public var high: (balance: Money, date: LocalDay?)
    public var differing: [ForecastLine] = []

    public init(_ month: ForecastMonth, today: LocalDay) {
        low = (month.openingBalance, nil)
        high = (month.openingBalance, nil)
        var first = true
        for line in month.rows {
            if first || line.forecastBalance < low.balance { low = (line.forecastBalance, line.plannedDate) }
            if first || line.forecastBalance > high.balance { high = (line.forecastBalance, line.plannedDate) }
            first = false
            if line.differsFromPlan { differing.append(line) }
            if !line.isPaid, let day = line.plannedDate {
                if day < today { overdue.append(line) } else {
                    comingCount += 1
                    comingNet = comingNet + line.plannedAmount
                }
            }
            guard !line.isTransfer else { continue }
            if let planned = line.forecastAmount {
                if planned.isNegative { spendingPlanned = spendingPlanned + planned } else { incomePlanned = incomePlanned + planned }
            }
            if line.isPaid, let real = line.actualAmount {
                if real.isNegative { spendingSoFar = spendingSoFar + real } else { incomeSoFar = incomeSoFar + real }
            }
        }
    }

    public static func == (a: ForecastSummary, b: ForecastSummary) -> Bool {
        a.incomePlanned == b.incomePlanned && a.incomeSoFar == b.incomeSoFar
            && a.spendingPlanned == b.spendingPlanned && a.spendingSoFar == b.spendingSoFar
            && a.comingCount == b.comingCount && a.comingNet == b.comingNet && a.overdue == b.overdue
            && a.low.balance == b.low.balance && a.low.date == b.low.date
            && a.high.balance == b.high.balance && a.high.date == b.high.date && a.differing == b.differing
    }
}

/// One of `GET /api/categories`: the signed-in person's own categories.
public struct TransactionCategory: Sendable, Codable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let color: String?

    public init(id: Int, name: String, color: String?) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// `GET /api/transactions/search`.
public struct TransactionSearch: Sendable, Codable, Equatable {
    public let total: Int
    public let results: [Hit]

    /// One transaction found, on any account you can see.
    public struct Hit: Sendable, Codable, Equatable, Identifiable {
        public let id: Int
        public let accountId: Int
        public let accountName: String?
        public let description: String
        public let amount: Money
        public let forecastAmount: Money?
        public let actualDate: LocalDay?
        public let forecastDate: LocalDay?
        public let isActual: Bool
        public let categoryId: Int?
        public let categoryName: String?
        public let recurringId: Int?
        public let transferId: Int?
        public let notes: String?
        public let tags: [TagInfo]?

        /// The same transaction as a forecast line, so it opens in the same
        /// editor. Balances aren't part of a search result; the editor
        /// doesn't show them.
        public var line: ForecastLine {
            ForecastLine(forecastDate: forecastDate, actualDate: actualDate ?? forecastDate, description: description,
                         category: categoryName, categoryId: categoryId, notes: notes,
                         forecastAmount: forecastAmount ?? (isActual ? nil : amount), forecastBalance: .zero,
                         actualAmount: amount, actualBalance: .zero,
                         diffAmount: forecastAmount.map { Money(amount.amount - $0.amount) }, diffBalance: .zero,
                         isActualReal: isActual, recurringId: recurringId, transactionId: id, transferId: transferId,
                         tags: tags)
        }
    }
}

// MARK: - Changing a line

/// What the editor holds while a line is open: whether it's paid, at what
/// amount and on what day, its category and its notes. Kept outside the
/// editor's own view so closing the Duo mid-edit keeps what was typed.
public struct LineDraft: Sendable, Equatable {
    public var paid: Bool
    /// The real amount as typed, without a sign: the line keeps its own.
    public var amountText: String
    public var paidOn: LocalDay
    public var categoryId: Int?
    public var notes: String
    /// Its tags (#251). Sent only when changed: unchanged, the server keeps
    /// a line's tags, and a bill's date marked paid takes the bill's.
    public var tagIds: [Int]
    /// Whether the name, planned date and planned amount below are fields
    /// for this line (a one-off you added, #316). For any other line they
    /// hold what it has and are never sent changed.
    public let editsPlan: Bool
    public var name: String
    public var plannedOn: LocalDay
    /// The planned amount as typed, without a sign: the line keeps its own.
    public var plannedAmountText: String

    /// The longest name the server takes.
    public static let nameMax = 500

    public var paidAmount: Decimal? { parseAmount(amountText) }
    public var plannedAmount: Decimal? { parseAmount(plannedAmountText) }

    /// What's wrong with the name or planned amount of a line whose fields
    /// show (#316), or nil.
    public var planProblem: String? {
        guard editsPlan else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Give it a name." }
        if trimmed.count > Self.nameMax { return "A name can be up to \(Self.nameMax) characters." }
        guard let planned = plannedAmount, planned >= 0 else { return "Enter the amount it's planned for." }
        return nil
    }

    /// What's wrong before it can be saved, or nil.
    public var problem: String? {
        if let planProblem { return planProblem }
        guard paid else { return nil }
        guard let amount = paidAmount, amount >= 0 else { return "Enter the amount it really came to." }
        return nil
    }

    public init(_ line: ForecastLine, today: LocalDay) {
        paid = line.isPaid
        amountText = amountString(abs(line.amount.amount))
        paidOn = line.isPaid ? (line.actualDate ?? today) : LineDraft.paidOn(line, today: today)
        categoryId = line.categoryId
        notes = line.notes ?? ""
        tagIds = (line.tags ?? []).map(\.id)
        editsPlan = line.isOneOff
        name = line.description
        plannedOn = line.plannedDate ?? today
        plannedAmountText = amountString(abs(line.plannedAmount.amount))
    }

    /// The day a line is marked paid on when no other is given (a swipe):
    /// its planned date, or today if that's still to come. An early payment
    /// is dated today; an old bill marked late keeps the day it was due.
    public static func paidOn(_ line: ForecastLine, today: LocalDay) -> LocalDay {
        guard let planned = line.plannedDate else { return today }
        return paidOn(planned: planned, today: today)
    }

    /// The same for a planned date that was just changed in the editor.
    public static func paidOn(planned: LocalDay, today: LocalDay) -> LocalDay { min(planned, today) }

    /// Paid as planned, for the swipe action.
    public static func paidAsPlanned(_ line: ForecastLine, today: LocalDay) -> LineDraft {
        var draft = LineDraft(line, today: today)
        draft.paid = true
        draft.amountText = amountString(abs(line.plannedAmount.amount))
        draft.paidOn = paidOn(line, today: today)
        return draft
    }

    /// Back to not paid, for the swipe's Undo.
    public static func unpaid(_ line: ForecastLine, today: LocalDay) -> LineDraft {
        var draft = LineDraft(line, today: today)
        draft.paid = false
        return draft
    }
}

/// The body of `POST /api/accounts/{id}/transactions` and
/// `PATCH /api/transactions/{id}`. A PATCH replaces the whole line, so it
/// carries everything the line already has.
public struct TransactionBody: Sendable, Encodable, Equatable {
    public let description: String
    public let amount: Decimal
    public let forecastDate: LocalDay?
    public let actualDate: LocalDay?
    public let forecastAmount: Decimal?
    public let isActual: Bool
    public let recurringId: Int?
    public let categoryId: Int?
    public let notes: String?
    /// Left out when nil: the server keeps a line's tags, and a line saved
    /// from a repeating item starts with the item's (#251).
    public let tagIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case description, amount, notes
        case forecastDate = "forecast_date", actualDate = "actual_date", forecastAmount = "forecast_amount"
        case isActual = "is_actual", recurringId = "recurring_id", categoryId = "category_id", tagIds = "tag_ids"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(description, forKey: .description)
        try c.encode(Self.number(amount), forKey: .amount)
        try c.encode(forecastDate, forKey: .forecastDate)
        try c.encode(actualDate, forKey: .actualDate)
        try c.encode(forecastAmount.map(Self.number), forKey: .forecastAmount)
        try c.encode(isActual, forKey: .isActual)
        try c.encode(recurringId, forKey: .recurringId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(tagIds, forKey: .tagIds)
    }

    /// Cents as a plain JSON number (`-812.34`, not `-812.3399999…`).
    private static func number(_ value: Decimal) -> Double {
        Double(Money(value).amount.description) ?? (value as NSDecimalNumber).doubleValue
    }

    /// An existing line saved with the editor's changes.
    public init(line: ForecastLine, draft: LineDraft) {
        let sign: Decimal = line.plannedAmount.isNegative || (line.plannedAmount == .zero && line.amount.isNegative) ? -1 : 1
        // A one-off's name, planned date and planned amount come from the
        // draft (#316); every other line sends what it has.
        let edited = draft.editsPlan && line.isOneOff
        let planned = edited ? sign * abs(draft.plannedAmount ?? line.plannedAmount.amount)
                             : line.forecastAmount?.amount ?? line.plannedAmount.amount
        description = edited ? draft.name.trimmingCharacters(in: .whitespacesAndNewlines) : line.description
        forecastDate = edited ? draft.plannedOn : line.forecastDate ?? line.plannedDate
        forecastAmount = planned
        recurringId = line.recurringId
        categoryId = draft.categoryId
        let trimmed = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmed.isEmpty ? nil : trimmed
        tagIds = draft.tagIds != (line.tags ?? []).map(\.id) ? draft.tagIds : nil
        if draft.paid {
            amount = sign * abs(draft.paidAmount ?? line.plannedAmount.amount)
            actualDate = draft.paidOn
            isActual = true
        } else {
            amount = planned
            actualDate = nil
            isActual = false
        }
    }

    /// A new one-off transaction.
    public init(new draft: NewTransactionDraft) {
        let signed = (draft.kind == .spending ? -1 : 1) * abs(draft.amount ?? 0)
        description = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        amount = signed
        forecastDate = draft.date
        forecastAmount = signed
        actualDate = draft.paid ? draft.date : nil
        isActual = draft.paid
        recurringId = nil
        categoryId = draft.categoryId
        let trimmed = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmed.isEmpty ? nil : trimmed
        tagIds = draft.tagIds.isEmpty ? nil : draft.tagIds
    }
}

/// The Add transaction sheet: Spending or Income, a plain amount, a name,
/// the date, and Paid (on, dated today, by default: decided 2026-11-15).
public struct NewTransactionDraft: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable, Identifiable {
        case spending, income
        public var id: String { rawValue }
        public var title: String { self == .spending ? "Spending" : "Income" }
    }

    public var kind: Kind = .spending
    public var name = ""
    public var amountText = ""
    public var date: LocalDay
    public var paid = true
    public var categoryId: Int?
    public var notes = ""
    public var tagIds: [Int] = []

    public init(today: LocalDay) { date = today }

    public var amount: Decimal? { parseAmount(amountText) }

    /// What's missing before it can be saved, or nil.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give it a name." }
        guard let amount, amount > 0 else { return "Enter an amount above zero." }
        return nil
    }
}

/// An amount as typed ("1,234.5", "$12", "-3"), as a positive number of
/// dollars; nil when it isn't one. The sign comes from the line or the
/// Spending / Income switch, never from what's typed.
public func parseAmount(_ text: String) -> Decimal? {
    let cleaned = text.filter { !" ,$-".contains($0) }
    guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber || $0 == "." }),
          cleaned.filter({ $0 == "." }).count <= 1,
          let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    return value
}

/// "812.34", "800": an amount as the editor's field first shows it.
public func amountString(_ value: Decimal) -> String {
    Money(value).amount.description
}
