import SwiftUI
import WalletWeatherKit
import WidgetKit

// The widgets' faces. Amounts are privacy-sensitive: a locked phone redacts
// them, and they show as •••• whenever the summary can't be read or the
// app's own lock is on. Names, labels and counts still show (decided
// 2026-11-23, docs/dev/decisions/ios-review.md).

/// What a widget draws: its connection's summary as the privacy rules allow
/// (`WidgetContent`), and for Balance the account chosen.
struct SummaryEntry: TimelineEntry {
    let date: Date
    let connection: UUID?
    let content: WidgetContent
    /// Balance: the account chosen, and its name as the widget's settings
    /// remember it (shown when the summary can't be read).
    var account: Int?
    var accountName: String?
}

extension SummaryEntry {
    /// The widget gallery and placeholders: made-up numbers, never anyone's.
    static var sample: SummaryEntry { SummaryEntry(date: .appNow, connection: nil, content: .summary(sampleSummary, amountsHidden: false), account: 1) }

    static var sampleSummary: ConnectionSummary {
        func day(_ ahead: Int) -> LocalDay {
            LocalDay.today(now: Calendar.current.date(byAdding: .day, value: ahead, to: .appNow) ?? .appNow)
        }
        return ConnectionSummary(
            id: UUID(), name: "Home", kind: .server, madeAt: .appNow, keepsNumbers: true,
            accounts: [.init(id: 1, name: "Checking", balance: Money(4854.97), monthLow: Money(2291.58),
                             monthLowDate: day(6), toConfirm: 2)],
            bills: [.init(id: 1, name: "Rent", accountId: 1, accountName: "Checking", amount: Money(-1650.0), nextDate: day(2)),
                    .init(id: 2, name: "Phone", accountId: 1, accountName: "Checking", amount: Money(-65.0), nextDate: day(5)),
                    .init(id: 3, name: "Gym", accountId: 1, accountName: "Checking", amount: Money(-39.99), nextDate: day(9))])
    }
}

// MARK: - Pieces

/// An amount, or •••• when it mustn't show: hidden by the app's lock, not
/// known (the summary can't be read), or redacted by a locked phone.
struct AmountText: View {
    let money: Money?
    var hidden = false
    var short = false
    @Environment(\.redactionReasons) private var reasons

    var body: some View {
        if let money, !hidden, !reasons.contains(.privacy) {
            Text(short ? money.short : money.formatted).privacySensitive()
        } else {
            Text(WidgetContent.hiddenAmount).accessibilityLabel("Hidden")
        }
    }
}

/// "Dec 1", "Today", "Tomorrow".
func dayText(_ day: LocalDay?, today: LocalDay = .today()) -> String {
    guard let day else { return "" }
    if day == today { return "Today" }
    if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today.date), day == LocalDay.today(now: tomorrow) {
        return "Tomorrow"
    }
    return day.short
}

/// Days from today to `day`.
func daysUntil(_ day: LocalDay, today: LocalDay = .today()) -> Int {
    Calendar.current.dateComponents([.day], from: today.date, to: day.date).day ?? 0
}

/// The connection's name, small, at the top or foot of a Home Screen widget.
struct ConnectionName: View {
    let name: String?
    var body: some View {
        if let name {
            Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// What a widget shows instead of its numbers: set up in the app, or turn
/// on Last-known numbers.
struct NoNumbers: View {
    let title: String
    let content: WidgetContent
    var shownFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { shownFamily ?? environmentFamily }

    var message: String {
        switch content {
        case .keepsNothing: WidgetContent.keepsNothingPrompt
        default: "Open WalletWeather to show your numbers here"
        }
    }

    var name: String? {
        if case let .keepsNothing(name) = content { return name }
        return nil
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(name.map { "\($0): no numbers kept" } ?? "Open WalletWeather")
        case .accessoryCircular:
            Image(systemName: "eye.slash").font(.title3).widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? title).font(.headline).lineLimit(1).widgetAccentable()
                Text(message).font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ConnectionName(name: name)
                Spacer(minLength: 0)
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// The Home Screen background (StandBy and the Lock Screen draw their
    /// own), and the link a tap opens.
    func widgetFrame(_ url: URL) -> some View {
        containerBackground(.fill.tertiary, for: .widget).widgetURL(url)
    }
}

// MARK: - Balance

struct BalanceView: View {
    let entry: SummaryEntry
    /// The size to draw, for the app's Debug gallery; a widget's own otherwise.
    var shownFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { shownFamily ?? environmentFamily }

    private var url: URL { AppLink.openURL(.dashboard, connection: entry.connection, account: entry.account) }

    var body: some View {
        Group {
            switch entry.content {
            case let .summary(summary, hidden):
                if let account = summary.account(entry.account) {
                    face(connection: summary.name, account: account.name, balance: account.balance,
                         low: account.monthLow, lowDate: account.monthLowDate, hidden: hidden, made: summary.madeAt)
                } else {
                    NoNumbers(title: "Balance", content: .noConnection, shownFamily: family)
                }
            case let .locked(name):
                face(connection: name, account: entry.accountName ?? "Balance", balance: nil, low: nil, lowDate: nil,
                     hidden: true, made: nil)
            case .keepsNothing, .noConnection:
                NoNumbers(title: "Balance", content: entry.content, shownFamily: family)
            }
        }
        .widgetFrame(url)
    }

    @ViewBuilder
    private func face(connection: String?, account: String, balance: Money?, low: Money?, lowDate: LocalDay?,
                      hidden: Bool, made: Date?) -> some View {
        switch family {
        case .accessoryInline:
            HStack(spacing: 4) {
                Text(account)
                AmountText(money: balance, hidden: hidden)
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "dollarsign").font(.caption2)
                AmountText(money: balance, hidden: hidden, short: true)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .widgetAccentable()
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text(account).font(.caption).lineLimit(1)
                AmountText(money: balance, hidden: hidden).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                    .widgetAccentable()
                HStack(spacing: 3) {
                    Text("Low")
                    AmountText(money: low, hidden: hidden)
                }
                .font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account).font(.headline).lineLimit(1)
                        AmountText(money: balance, hidden: hidden)
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.5).widgetAccentable()
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Month's low").font(.caption).foregroundStyle(.secondary)
                        AmountText(money: low, hidden: hidden).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        if let lowDate { Text(dayText(lowDate)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 0)
                footer(connection: connection, made: made)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                ConnectionName(name: connection)
                Text(account).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                AmountText(money: balance, hidden: hidden)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.5).widgetAccentable()
                HStack(spacing: 3) {
                    Text("Low")
                    AmountText(money: low, hidden: hidden)
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// "Home · 2:15 PM": the connection, and when its numbers were made.
@ViewBuilder
func footer(connection: String?, made: Date?) -> some View {
    HStack(spacing: 4) {
        if let connection { Text(connection).lineLimit(1) }
        if let made {
            Text("·")
            Text(made, format: .dateTime.hour().minute())
        }
    }
    .font(.caption2).foregroundStyle(.secondary)
}

// MARK: - Next bills

struct NextBillsView: View {
    let entry: SummaryEntry
    /// The size to draw, for the app's Debug gallery; a widget's own otherwise.
    var shownFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { shownFamily ?? environmentFamily }

    private var url: URL { AppLink.openURL(.bills, connection: entry.connection) }

    var body: some View {
        Group {
            switch entry.content {
            case let .summary(summary, hidden):
                face(connection: summary.name, bills: summary.nextBills(),
                     hidden: hidden, made: summary.madeAt)
            case let .locked(name):
                lockedFace(connection: name)
            case .keepsNothing, .noConnection:
                NoNumbers(title: "Next bills", content: entry.content, shownFamily: family)
            }
        }
        .widgetFrame(url)
    }

    @ViewBuilder
    private func face(connection: String, bills: [ConnectionSummary.Bill], hidden: Bool, made: Date) -> some View {
        switch family {
        case .accessoryInline:
            if let next = bills.first {
                Text("\(next.name) · \(dayText(next.nextDate))")
            } else {
                Text("No bills coming up")
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "calendar").font(.caption2)
                if let date = bills.first?.nextDate {
                    let days = daysUntil(date)
                    Text(days <= 0 ? "Today" : "\(days)d")
                        .font(.system(.body, design: .rounded).weight(.semibold)).widgetAccentable()
                } else {
                    Text("–").font(.body.weight(.semibold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("Next bills").font(.caption).widgetAccentable()
                if bills.isEmpty { Text("None coming up").font(.caption) }
                ForEach(bills.prefix(2)) { bill in
                    HStack(spacing: 4) {
                        Text(bill.name).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(dayText(bill.nextDate)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Next bills").font(.headline).widgetAccentable()
                    Spacer(minLength: 4)
                    if family == .systemSmall { ConnectionName(name: connection) }
                }
                if bills.isEmpty {
                    Text("Nothing coming up.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(bills) { bill in
                    row(bill, hidden: hidden)
                }
                Spacer(minLength: 0)
                if family == .systemMedium { footer(connection: connection, made: made) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func row(_ bill: ConnectionSummary.Bill, hidden: Bool) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                Text(bill.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(dayText(bill.nextDate)).font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Text(bill.name).lineLimit(1)
                Spacer(minLength: 4)
                Text(dayText(bill.nextDate)).foregroundStyle(.secondary)
                AmountText(money: bill.amount, hidden: hidden).monospacedDigit().frame(minWidth: 70, alignment: .trailing)
            }
            .font(.subheadline)
        }
    }

    /// The phone is locked and the summary can't be read: the widget's
    /// labels only.
    @ViewBuilder
    private func lockedFace(connection: String?) -> some View {
        switch family {
        case .accessoryInline: Text("Next bills")
        case .accessoryCircular: Image(systemName: "calendar").font(.title3).widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("Next bills").font(.caption).widgetAccentable()
                Text("Unlock to see them").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Next bills").font(.headline)
                ConnectionName(name: connection)
                Spacer(minLength: 0)
                Text("Unlock to see them").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - To confirm

struct ToConfirmView: View {
    let entry: SummaryEntry
    /// The size to draw, for the app's Debug gallery; a widget's own otherwise.
    var shownFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { shownFamily ?? environmentFamily }

    private var url: URL {
        var account: Int?
        if case let .summary(summary, _) = entry.content { account = summary.toConfirmAccount }
        return AppLink.openURL(.toConfirm, connection: entry.connection, account: account)
    }

    var body: some View {
        Group {
            switch entry.content {
            case let .summary(summary, _):
                face(connection: summary.name, count: summary.toConfirm, made: summary.madeAt)
            case let .locked(name):
                face(connection: name, count: nil, made: nil)
            case .keepsNothing, .noConnection:
                NoNumbers(title: "To confirm", content: entry.content, shownFamily: family)
            }
        }
        .widgetFrame(url)
    }

    /// "3", or "–" when it can't be read or this person can't confirm lines.
    private func countText(_ count: Int?) -> String { count.map(String.init) ?? "–" }

    private func lines(_ count: Int?) -> String {
        guard let count else { return "To confirm" }
        return count == 1 ? "line to confirm" : "lines to confirm"
    }

    @ViewBuilder
    private func face(connection: String?, count: Int?, made: Date?) -> some View {
        switch family {
        case .accessoryInline:
            Text(count.map { "\($0) to confirm" } ?? "To confirm")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle").font(.caption2)
                Text(countText(count)).font(.system(.title3, design: .rounded).weight(.semibold)).widgetAccentable()
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Text("To confirm").font(.caption).widgetAccentable()
                Text(count.map { "\($0) \($0 == 1 ? "line" : "lines")" } ?? "–").font(.headline)
                if let connection { Text(connection).font(.caption).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .center, spacing: 12) {
                Text(countText(count)).font(.system(size: 48, weight: .semibold, design: .rounded)).widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text(lines(count)).font(.headline)
                    Text("Due up to today and not marked yet").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    footer(connection: connection, made: made)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                ConnectionName(name: connection)
                Spacer(minLength: 0)
                Text(countText(count)).font(.system(size: 44, weight: .semibold, design: .rounded)).widgetAccentable()
                Text(lines(count)).font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
