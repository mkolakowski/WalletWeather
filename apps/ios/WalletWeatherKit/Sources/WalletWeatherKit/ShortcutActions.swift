import Foundation

// Add a transaction and Mark a bill paid (Plans/outside-the-app.md, phase 5,
// #332): two App Intents in the app, offered as App Shortcuts (Siri, the
// Action button). What they do is worked out here, so the tests can run each
// against the household on this iPhone and a server's answers.
//
// Decided 2026-11-23 (docs/dev/decisions/ios-review.md, "which actions open
// the app"): Add a transaction opens the app's Add transaction sheet, filled
// in, for a last look; Mark a bill paid runs without opening the app and says
// what it did. Both act on the connection in front, need the phone unlocked,
// and ask for Face ID first while the app's lock is on (the app's own lock
// does that for Add a transaction, which opens the app).

// MARK: - Add a transaction

extension NewTransactionDraft {
    /// The Add transaction sheet's draft, filled in from the Shortcut: the
    /// amount as spending (the sheet can change it to income), the name
    /// trimmed, and the date.
    public static func fromShortcut(amount: Decimal, name: String, date: LocalDay) -> NewTransactionDraft {
        var draft = NewTransactionDraft(today: date)
        draft.kind = .spending
        draft.amountText = amount == 0 ? "" : amountString(abs(amount))
        draft.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LineDraft.nameMax))
        return draft
    }
}

// MARK: - Mark a bill paid

/// Whether Mark a bill paid may go ahead, decided from the summary of the
/// connection in front (the bills it offers are that summary's).
public enum MarkPaidCheck: Equatable, Sendable {
    /// No saved connection: nothing set up, or only the demo used.
    case noConnection
    /// The summary can't be read: the phone is locked.
    case phoneLocked
    /// A saved connection with no summary yet.
    case notLoaded
    /// A server set to keep Nothing: no bills are kept to pick from.
    case keepsNothing(name: String)
    /// The bill picked isn't on the connection in front (another connection,
    /// or deleted since).
    case notHere(name: String)
    /// This sign-in can't change the bill's account (read-only, or an
    /// account shared to look at).
    case cannotChange(account: String)
    /// The app's lock is on and Face ID didn't pass.
    case appLocked
    /// Go ahead: the bill, on the summary's connection.
    case ready(ConnectionSummary.Bill, connection: ConnectionSummary)

    /// `link` is the bill picked. `unlocked` is true once Face ID (or the
    /// passcode) has passed; the intent decides first with false and asks
    /// only when the answer is `appLocked`.
    public static func decide(front: UUID?, read: SummaryRead, link: SearchLink, lockOn: Bool, unlocked: Bool) -> MarkPaidCheck {
        guard let front else { return .noConnection }
        let summary: ConnectionSummary
        switch read {
        case .missing: return .notLoaded
        case .unreadable: return .phoneLocked
        case let .found(found): summary = found
        }
        guard summary.keepsNumbers else { return .keepsNothing(name: summary.name) }
        guard case let .bill(connection, id) = link, connection == front,
              let bill = summary.bills.first(where: { $0.id == id }) else { return .notHere(name: summary.name) }
        // To confirm is counted only on accounts this sign-in may change.
        guard summary.accounts.first(where: { $0.id == bill.accountId })?.toConfirm != nil else {
            return .cannotChange(account: bill.accountName)
        }
        if lockOn && !unlocked { return .appLocked }
        return .ready(bill, connection: summary)
    }

    /// What Siri says when it doesn't go ahead; nil for `ready`.
    public var refusal: String? {
        switch self {
        case .noConnection:
            return "WalletWeather has no saved connection yet, and the demo can't be changed. Connect to your server or start a household on this iPhone first."
        case .phoneLocked:
            return "Unlock your iPhone to mark a bill paid."
        case .notLoaded:
            return "WalletWeather has no bills for Siri yet. Open the app once so it can load them."
        case let .keepsNothing(name):
            return "\(name) keeps no numbers on this iPhone, so there are no bills to pick. Mark it paid in WalletWeather, or turn on Last-known numbers for it."
        case let .notHere(name):
            return "That bill isn't on \(name), the connection you're using. Open WalletWeather to mark it paid."
        case let .cannotChange(account):
            return "You can't change \(account) with this sign-in, so the bill wasn't marked paid."
        case .appLocked:
            return "WalletWeather is locked. Unlock it with Face ID or your passcode to mark a bill paid."
        case .ready:
            return nil
        }
    }
}

/// Marking a bill's next date paid, as planned, the way a swipe on Forecast
/// does, through whichever connection holds it.
public enum BillPaying {
    /// What was marked paid.
    public struct Paid: Equatable, Sendable {
        public let name: String
        /// The amount it was paid at, without a sign.
        public let amount: Money
        public let planned: LocalDay
        public let paidOn: LocalDay
    }

    /// The bill's earliest date that isn't paid yet among `rows`.
    public static func nextUnpaid(_ bill: Int, in rows: [ForecastLine]) -> ForecastLine? {
        rows.filter { $0.recurringId == bill && !$0.isPaid && $0.transferId == nil && $0.plannedDate != nil }
            .min { $0.plannedDate! < $1.plannedDate! }
    }

    /// Marks the bill's earliest unpaid date this month (or, with none left,
    /// next month) paid as planned. Nil when it has no date left to pay in
    /// either.
    public static func pay(bill: Int, account: Int, client: APIClient, today: LocalDay = .today())
        async throws(APIError) -> Paid? {
        let month = YearMonth(today)
        var line = nextUnpaid(bill, in: try await client.forecast(account: account, month: month, today: today).rows)
        if line == nil {
            line = nextUnpaid(bill, in: try await client.forecast(account: account, month: month.next, today: today).rows)
        }
        guard let line, let planned = line.plannedDate else { return nil }
        let draft = LineDraft.paidAsPlanned(line, today: today)
        try await client.save(line, draft: draft, account: account)
        return Paid(name: line.description, amount: Money(abs(line.plannedAmount.amount)), planned: planned,
                    paidOn: draft.paidOn)
    }

    /// What Siri says after: "Rent is marked paid on Nov 24, $1,500.00, on Home."
    public static func said(_ paid: Paid?, bill: String, connection: String) -> String {
        guard let paid else { return "\(bill) has no date left to pay this month or next." }
        return "\(paid.name) is marked paid on \(paid.paidOn.short), \(paid.amount.formatted), on \(connection)."
    }
}
