import SwiftUI
import WalletWeatherKit

/// Calendar: the month with each day's bills and paychecks, today marked.
/// All accounts by default, or one, which adds each day's closing balance
/// (decided 2026-11-15). Closed: a compact month with dots, and the tapped
/// day's lines under it. Open: the month on the left with amounts written
/// in each day, and on the right the tapped day's lines, or today's lines
/// and balances until a day is tapped.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 0 for all accounts.
    @SceneStorage("calendar.account") private var accountId = 0
    @SceneStorage("calendar.month") private var monthText = ""
    @SceneStorage("calendar.day") private var dayText = ""

    @State private var accounts: [Account] = []
    @State private var month: Loadable<CalendarMonth> = .loading
    @State private var kept = KeptTracker()
    @State private var categories: [TransactionCategory] = []
    @State private var adding = false
    @State private var newDraft = NewTransactionDraft(today: .today())
    @State private var moving = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())

    private var shownMonth: YearMonth { YearMonth(monthText) ?? YearMonth(.today()) }
    private var account: Account? { accounts.first { $0.id == accountId } }
    private var editableAccounts: [Account] { accounts.filter(model.canEdit) }
    private var selected: LocalDay? { LocalDay(dayText).flatMap { shownMonth.contains($0) ? $0 : nil } }

    var body: some View {
        PageStack {
            content
                .keptBar(kept)
                .background(PageBackground().ignoresSafeArea())
                .navigationTitle("Calendar")
                .toolbar { NewWindowItem(place: .calendar) }
                .toolbar {
                    if !editableAccounts.isEmpty {
                        AddMenu(addTitle: "Add transaction", canMove: editableAccounts.count > 1, onAdd: {
                            newDraft = NewTransactionDraft(today: selected ?? .today())
                            adding = true
                        }, onMove: {
                            moveDraft = MoveMoneyDraft(today: selected ?? .today(), from: account?.id)
                            moving = true
                        })
                    }
                }
        }
        .sheet(isPresented: $adding) {
            if let target = account.flatMap({ model.canEdit($0) ? $0 : nil }) ?? editableAccounts.first {
                AddTransactionSheet(account: target, accountChoices: account == nil ? editableAccounts : [],
                                    categories: categories, draft: $newDraft) { await load() }
            }
        }
        .sheet(isPresented: $moving) {
            MoveMoneySheet(accounts: editableAccounts, draft: $moveDraft) { await load() }
        }
        .task(id: model.generation) { await loadAll() }
        .task(id: "\(accountId)/\(monthText)") { await load() }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        switch month {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            ProblemView(error: error) { Task { await loadAll() } }
        case let .loaded(data):
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            header
                            MonthGrid(month: shownMonth, data: data, selected: selected, wide: true, onTap: select)
                                .card()
                        }
                        .padding(.leading, 16).padding(.trailing, 28).padding(.bottom, 24)
                    }
                    .refreshable { await load() }
                    .frame(maxWidth: .infinity)
                    ScrollView {
                        Group {
                            if let day = selected {
                                DayLines(day: day, data: data, showAccount: account == nil, onClose: { dayText = "" })
                            } else {
                                TodayView(data: data, month: shownMonth, accounts: account.map { [$0] } ?? accounts,
                                          showAccount: account == nil)
                            }
                        }
                        .padding(.leading, 28).padding(.trailing, 16).padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        MonthGrid(month: shownMonth, data: data, selected: selected, wide: false, onTap: select)
                            .card()
                        let day = selected ?? (shownMonth.contains(.today()) ? .today() : shownMonth.start)
                        DayLines(day: day, data: data, showAccount: account == nil, onClose: nil)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .refreshable { await load() }
            }
        }
    }

    /// The account switcher (All accounts, or one) and the month.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if accounts.count > 1 {
                Menu {
                    Picker("Account", selection: $accountId) {
                        Text("All accounts").tag(0)
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(account?.name ?? "All accounts").font(.title3.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel("Showing \(account?.name ?? "all accounts"). Switch account")
            }
            HStack {
                Button("Previous month", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
                Spacer()
                Text(shownMonth.label).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            if account == nil && accounts.count > 1 {
                Text("Pick one account to see each day's closing balance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func select(_ day: LocalDay) {
        dayText = selected == day && sizeClass == .regular ? "" : day.description
    }

    private func move(_ by: Int) {
        dayText = ""
        monthText = (by < 0 ? shownMonth.previous : shownMonth.next).description
    }

    // MARK: - Loading

    private func loadAll() async {
        guard let client = model.client(kept) else { return }
        do {
            accounts = try await client.accounts()
        } catch {
            month = .failed(error)
            kept.clear()
            return
        }
        if accountId != 0, !accounts.contains(where: { $0.id == accountId }) { accountId = 0 }
        if let name = AppModel.debugSetting("WW_DEBUG_ACCOUNT"), let found = accounts.first(where: { $0.name == name }) {
            accountId = found.id
        }
        if let day = AppModel.debugSetting("WW_DEBUG_DAY") { dayText = day }
        categories = (try? await client.categories()) ?? []
        await load()
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do {
            month = .loaded(try await client.calendar(shownMonth, account: accountId == 0 ? nil : accountId))
        } catch {
            month = .failed(error)
            kept.clear()
        }
    }
}

// MARK: - The month

/// The month's days in weeks, starting on the phone's first weekday.
/// Compact: the day and dots (red for bills, green for income, grey for
/// money moved). Wide: the day's bills and income written in, and with one
/// account its closing balance.
struct MonthGrid: View {
    let month: YearMonth
    let data: CalendarMonth
    let selected: LocalDay?
    let wide: Bool
    let onTap: (LocalDay) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    Text(weekdaySymbols[i]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: wide ? 4 : 2) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(1...month.end.day, id: \.self) { n in
                    let day = LocalDay(year: month.year, month: month.month, day: n)
                    Button { onTap(day) } label: {
                        DayCell(day: day, summary: data.summary(of: day), balance: data.balance(on: day),
                                selected: day == selected, wide: wide)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month.start.date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

struct DayCell: View {
    let day: LocalDay
    let summary: CalendarMonth.DaySummary
    let balance: Money?
    let selected: Bool
    let wide: Bool

    var body: some View {
        let isToday = day == .today()
        VStack(spacing: wide ? 2 : 3) {
            Text("\(day.day)")
                .font(wide ? .subheadline.weight(isToday ? .bold : .regular) : .callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(selected ? Color.white : (isToday ? Palette.accent : .primary))
                .frame(width: 30, height: 30)
                .background {
                    if selected { Circle().fill(Palette.accent) } else if isToday { Circle().strokeBorder(Palette.accent, lineWidth: 1.5) }
                }
            if wide {
                amounts
            } else {
                HStack(spacing: 3) {
                    if summary.hasBill { dot(Palette.bad) }
                    if summary.hasIncome { dot(Palette.good) }
                    if summary.hasTransfer { dot(.secondary) }
                }
                .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: wide ? 78 : 44, alignment: .top)
        .padding(.vertical, wide ? 4 : 2)
        .background(wide && selected ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Wide: the day's net, and the closing balance with one account.
    @ViewBuilder
    private var amounts: some View {
        if summary.count > 0 {
            Text((summary.net.isNegative ? "" : "+") + summary.net.short)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(summary.net.isNegative ? Palette.bad : Palette.good)
                .lineLimit(1).minimumScaleFactor(0.7)
            if summary.count > 1 {
                Text("\(summary.count) lines").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 0)
        if let balance {
            Text(balance.short).font(.system(size: 10).monospacedDigit())
                .foregroundStyle(balance.isNegative ? Palette.bad : .secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    private var accessibilityText: String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if day == .today() { parts.append("today") }
        if summary.count > 0 { parts.append("\(summary.count) line\(summary.count == 1 ? "" : "s"), net \(summary.net.formatted)") }
        if let balance { parts.append("closing balance \(balance.formatted)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - A day's lines

/// The lines of one day, with its closing balance when one account is shown.
struct DayLines: View {
    let day: LocalDay
    let data: CalendarMonth
    let showAccount: Bool
    let onClose: (() -> Void)?

    var body: some View {
        let lines = data.events(on: day)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day == .today() ? "Today" : day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.headline)
                Spacer()
                if let onClose {
                    Button("Close", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).buttonStyle(.glass)
                }
            }
            if let balance = data.balance(on: day) {
                HStack {
                    Caption("Closing balance")
                    Spacer()
                    Text(balance.formatted).font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.amount(balance.isNegative))
                }
            }
            if lines.isEmpty {
                Text("Nothing on this day.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(lines) { line in
                Divider()
                CalendarLineRow(line: line, showAccount: showAccount)
            }
        }
        .card()
    }
}

struct CalendarLineRow: View {
    let line: CalendarEvent
    let showAccount: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: line.isPaid ? "checkmark.circle.fill" : (line.isTransfer ? "arrow.left.arrow.right" : "circle"))
                .foregroundStyle(line.isPaid ? Palette.good : .secondary)
                .font(.subheadline)
                .accessibilityLabel(line.isPaid ? "Paid" : "Not paid yet")
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description).lineLimit(2)
                let detail = [showAccount ? line.accountName : nil, line.categoryName,
                              line.recurringId != nil ? "repeats" : nil].compactMap { $0 }
                if !detail.isEmpty {
                    Text(detail.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let amount = line.amount {
                Text(amount.formatted).monospacedDigit()
                    .foregroundStyle(line.isTransfer ? .secondary : (amount.isNegative ? Palette.bad : Palette.good))
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// The right half of the open Duo before a day is tapped: today's lines,
/// and each account's balance today.
struct TodayView: View {
    let data: CalendarMonth
    let month: YearMonth
    let accounts: [Account]
    let showAccount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Caption("Balances today")
                ForEach(accounts) { account in
                    HStack {
                        Text(account.name)
                        Spacer()
                        Text(account.currentBalance.formatted).monospacedDigit()
                            .foregroundStyle(Palette.amount(account.currentBalance.isNegative))
                    }
                    .font(.callout)
                }
            }
            .card()
            if month.contains(.today()) {
                DayLines(day: .today(), data: data, showAccount: showAccount, onClose: nil)
            } else {
                Text("Today isn't in \(month.label).").font(.callout).foregroundStyle(.secondary)
            }
            Text("Tap a day on the left to see its lines.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
