import Foundation

// Reminders worked out on the phone (Plans/outside-the-app.md, phase 2,
// #319): Settings → Reminders has three switches, all off to start. Each time
// the connection in front's summary is written, the app replaces the
// reminders it has scheduled, so they're worked out while the phone is
// unlocked and arrive later on their own.
//
// Decided 2026-11-23 and 2026-11-24 (docs/dev/decisions/ios-review.md):
// - a reminder's text never carries an amount ("Rent is due tomorrow"); the
//   amount shows only in its expanded view, which reads the summary, so a
//   locked phone and the app lock keep it hidden;
// - Bill due tomorrow arrives at 9:00 AM the day before, changeable;
// - Balance heading under watches one account, picked, starting at $100,
//   and warns once when the forecast first goes under within 7 days, again
//   only after it's back above and dips again;
// - only the connection in front gets reminders; nothing for the demo or a
//   server set to keep Nothing.

/// The three switches and what goes with them. Kept in the app's own
/// settings under `key` (stable): only choices, never a number of the
/// person's own beyond the amount they typed.
public struct ReminderSettings: Codable, Equatable, Sendable {
    public static let key = "reminders.settings"
    /// Where Balance heading under starts (decided 2026-11-24).
    public static let startAmount = Money(100.0)

    public var billsOn = false
    /// When Bill due tomorrow arrives, the day before.
    public var billHour = 9
    public var billMinute = 0
    public var balanceOn = false
    public var balanceAmount = ReminderSettings.startAmount
    /// The account Balance heading under watches, per connection (an
    /// account id means nothing on another connection); none picked is the
    /// first account.
    public var balanceAccounts: [String: Int] = [:]
    public var bankLinesOn = false

    public init() {}

    public var anyOn: Bool { billsOn || balanceOn || bankLinesOn }

    public func balanceAccount(for connection: UUID) -> Int? { balanceAccounts[connection.uuidString.lowercased()] }

    public mutating func setBalanceAccount(_ account: Int?, for connection: UUID) {
        balanceAccounts[connection.uuidString.lowercased()] = account
    }

    public static func load(from defaults: UserDefaults) -> ReminderSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) } ?? ReminderSettings()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// What's already been said, so a dip or new bank lines are told once.
/// Kept in the app's own settings under `key` (stable).
public struct ReminderState: Codable, Equatable, Sendable {
    public static let key = "reminders.state"

    /// The dips already warned of, `<connection>/<account>` → the dip's
    /// first day as it was then. Cleared once the forecast is back above.
    public var dips: [String: LocalDay] = [:]
    /// The bank lines to match last time bank sync on this iPhone ran.
    public var bankLines: Int?

    public init() {}

    public static func load(from defaults: UserDefaults) -> ReminderState {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReminderState.self, from: $0) } ?? ReminderState()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// One reminder to schedule.
public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case bill, balance, bankLines = "bank-lines"
    }

    /// Stable: `net.iptater.walletweather.reminder.<kind>.<connection>.<item>`.
    public let id: String
    public let kind: Kind
    /// No amount, ever.
    public let title: String
    public let body: String
    /// When it arrives; nil for straight away (a minute or so).
    public let fireAt: Date?
    public let connection: UUID?
    /// The bill's or account's id.
    public let item: Int?
    /// The day it's about: the bill's due date, or the dip's first day.
    public let day: LocalDay?

    /// What the expanded view needs to find its amount in the summary: ids
    /// and a day, never a number.
    public var userInfo: [String: String] {
        var info = ["kind": kind.rawValue]
        if let connection { info["connection"] = connection.uuidString.lowercased() }
        if let item { info["item"] = String(item) }
        if let day { info["day"] = day.description }
        return info
    }
}

public enum ReminderPlan {
    /// Every reminder's id starts with it. Stable.
    public static let prefix = "net.iptater.walletweather.reminder."
    /// The notification category the expanded view answers. Stable.
    public static let category = "net.iptater.walletweather.reminder"
    /// iOS keeps at most 64 scheduled; bills leave room for the rest.
    public static let maxBills = 50

    static func id(_ kind: PlannedReminder.Kind, _ connection: UUID?, _ item: Int?) -> String {
        prefix + kind.rawValue + "." + (connection?.uuidString.lowercased() ?? "phone") + "." + (item.map(String.init) ?? "all")
    }

    /// "Dec 3".
    static func dayName(_ day: LocalDay, calendar: Calendar) -> String {
        day.date.formatted(Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated).day()
            .locale(Locale(identifier: "en_US")))
    }

    /// The reminders for the connection in front, from its summary (nil for
    /// the demo, an unsaved connection, or none in front), and the state
    /// after them. A server set to keep Nothing has no numbers, so nothing.
    public static func make(_ summary: ConnectionSummary?, settings: ReminderSettings, state: ReminderState,
                            now: Date = .now, calendar: Calendar = .current) -> (reminders: [PlannedReminder], state: ReminderState) {
        var state = state
        guard let summary, summary.keepsNumbers else {
            state.dips = [:]
            return ([], state)
        }
        let today = LocalDay.today(calendar: calendar, now: now)
        var out: [PlannedReminder] = []

        if settings.billsOn {
            let bills = summary.bills.filter { !$0.isIncome }
                .compactMap { bill -> (ConnectionSummary.Bill, LocalDay, Date)? in
                    guard let due = bill.nextDate, due > today else { return nil }
                    var parts = calendar.dateComponents([.year, .month, .day], from: due.adding(days: -1).date)
                    parts.hour = settings.billHour
                    parts.minute = settings.billMinute
                    guard let at = calendar.date(from: parts), at > now else { return nil }
                    return (bill, due, at)
                }
                .sorted { ($0.2, $0.0.id) < ($1.2, $1.0.id) }
                .prefix(maxBills)
            for (bill, due, at) in bills {
                out.append(PlannedReminder(id: id(.bill, summary.id, bill.id), kind: .bill,
                                           title: "\(bill.name) is due tomorrow",
                                           body: "\(bill.accountName) · \(summary.name)",
                                           fireAt: at, connection: summary.id, item: bill.id, day: due))
            }
        }

        // Only the account watched now keeps its dip remembered.
        let watched = summary.account(settings.balanceAccount(for: summary.id))
        let dipKey = watched.map { "\(summary.id.uuidString.lowercased())/\($0.id)" }
        state.dips = state.dips.filter { $0.key == dipKey }
        if settings.balanceOn, let account = watched, let dipKey {
            let lows = account.weekLows ?? [ConnectionSummary.DayBalance(date: today, low: account.balance)]
            if let dip = lows.first(where: { $0.date >= today && $0.low < settings.balanceAmount }) {
                if state.dips[dipKey] == nil {
                    state.dips[dipKey] = dip.date
                    let when = dip.date == today ? "today" : "on \(dayName(dip.date, calendar: calendar))"
                    out.append(PlannedReminder(id: id(.balance, summary.id, account.id), kind: .balance,
                                               title: "\(account.name) is heading low",
                                               body: "Forecast to go under your reminder amount \(when) · \(summary.name)",
                                               fireAt: nil, connection: summary.id, item: account.id, day: dip.date))
                }
            } else {
                state.dips[dipKey] = nil   // back above: the next dip warns again
            }
        } else {
            state.dips = [:]
        }
        return (out, state)
    }

    /// After bank sync on this iPhone: a reminder when more lines wait to be
    /// matched than last time, told once. The count is kept either way, so
    /// turning the switch on later doesn't tell of old lines.
    public static func bankLines(_ waiting: Int, settings: ReminderSettings,
                                 state: ReminderState) -> (reminder: PlannedReminder?, state: ReminderState) {
        var state = state
        let before = state.bankLines ?? waiting
        state.bankLines = waiting
        guard settings.bankLinesOn, waiting > before else { return (nil, state) }
        let new = waiting - before
        return (PlannedReminder(id: id(.bankLines, nil, nil), kind: .bankLines,
                                title: "New bank lines to match",
                                body: new == 1 ? "1 new line from your bank waits to be matched." :
                                    "\(new) new lines from your bank wait to be matched.",
                                fireAt: nil, connection: nil, item: nil, day: nil), state)
    }
}

// MARK: - The expanded view

/// What a reminder's expanded view shows: the amount it's about, read from
/// the summary, or •••• when the summary can't be read (the phone is locked)
/// or the app's lock is on.
public enum ReminderDetail: Equatable, Sendable {
    /// A bill: its amount and due day.
    case bill(name: String, amount: String, due: LocalDay?)
    /// A dip: the forecast's low that day. The amount it's under stays in
    /// the app's own settings, out of the extension's reach.
    case balance(account: String, low: String, day: LocalDay?)
    /// Nothing more to show (bank lines, or the item is gone).
    case none

    public static func decide(_ userInfo: [AnyHashable: Any], read: (UUID) -> SummaryRead,
                              lockOn: Bool) -> ReminderDetail {
        guard let kind = (userInfo["kind"] as? String).flatMap(PlannedReminder.Kind.init(rawValue:)),
              let connection = (userInfo["connection"] as? String).flatMap(UUID.init(uuidString:)),
              let item = (userInfo["item"] as? String).flatMap({ Int($0) }) else { return .none }
        let day = (userInfo["day"] as? String).flatMap(LocalDay.init)
        let hidden = WidgetContent.hiddenAmount
        let summary: ConnectionSummary?
        if case let .found(found) = read(connection), found.keepsNumbers { summary = found } else { summary = nil }
        let show = summary != nil && !lockOn
        switch kind {
        case .bill:
            let bill = summary?.bills.first { $0.id == item }
            return .bill(name: bill?.name ?? "This bill", amount: show ? (bill?.amount.formatted ?? hidden) : hidden,
                         due: bill?.nextDate ?? day)
        case .balance:
            let account = summary?.accounts.first { $0.id == item }
            let low = account?.weekLows?.first { $0.date == day }?.low
            return .balance(account: account?.name ?? "This account", low: show ? (low?.formatted ?? hidden) : hidden,
                            day: day)
        case .bankLines:
            return .none
        }
    }
}
