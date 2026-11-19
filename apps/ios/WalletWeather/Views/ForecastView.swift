import Charts
import SwiftUI
import WalletWeatherKit

/// Forecast: one account at a time, month by month. Closed (and on any
/// iPhone) each line is a card; open, the Duo shows the balance chart and
/// the full table on the left and, on the right, the tapped line's editor
/// or, before one is tapped, the month's summary. Swipe a line to mark it
/// paid as planned, or back to undo; + in the top corner adds a one-off.
struct ForecastView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("forecast.account") private var accountId = 0
    @SceneStorage("forecast.month") private var monthText = ""
    /// The "To confirm" switch (#90): only the lines due up to today and
    /// not yet paid, each with Paid as planned and a box for another amount.
    @SceneStorage("forecast.confirming") private var confirming = false

    @State private var accounts: Loadable<[Account]> = .loading
    @State private var month: Loadable<ForecastMonth> = .loading
    @State private var kept = KeptTracker()
    @State private var categories: [TransactionCategory] = []
    @State private var open: OpenLine?
    @State private var adding = false
    @State private var newDraft = NewTransactionDraft(today: .today())
    @State private var moving = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())
    @State private var pendingDelete: ForecastLine?
    @State private var problem: String?
    @State private var comparing = false

    private var shownMonth: YearMonth { YearMonth(monthText) ?? YearMonth(.today()) }
    private var account: Account? {
        guard let list = accounts.value else { return nil }
        return list.first { $0.id == accountId } ?? list.first
    }
    private var editable: Bool { account.map(model.canEdit) ?? false }
    private var editableAccounts: [Account] { (accounts.value ?? []).filter(model.canEdit) }

    var body: some View {
        PageStack {
            content
                .keptBar(kept)
                .background(PageBackground().ignoresSafeArea())
                .navigationTitle("Forecast")
                .toolbar { NewWindowItem(place: .forecast) }
                .toolbar { toolbar }
        }
        .lineEditorSheet($open, categories: categories) { await loadMonth() }
        .sheet(isPresented: $adding) {
            if let account {
                AddTransactionSheet(account: account, categories: categories, draft: $newDraft) { await loadMonth() }
            }
        }
        .fullScreenCover(isPresented: $comparing) {
            if let account {
                CompareView(accounts: accounts.value ?? [], left: .init(accountId: account.id, month: shownMonth),
                            right: .init(accountId: account.id, month: shownMonth.previous))
            }
        }
        .sheet(isPresented: $moving) {
            MoveMoneySheet(accounts: editableAccounts, draft: $moveDraft) { await loadMonth() }
        }
        .confirmationDialog(pendingDelete.map(deleteTitle) ?? "", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { line in
            Button(line.isProjection ? "Delete this date" : "Delete", role: .destructive) {
                Task { await change(line) { try await $0.delete(line) } }
            }
        } message: { line in
            Text(line.isProjection ? "The repeating bill or paycheck keeps its other dates." : "This can't be undone.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
        .task(id: model.generation) { await loadAll() }
        .task(id: "\(accountId)/\(monthText)") { await loadMonth() }
        // An account chosen in Search (#112): this month of it.
        .onChange(of: model.forecastRequest, initial: true) { _, request in
            guard let request else { return }
            accountId = request
            monthText = ""
            confirming = false
            model.forecastRequest = nil
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        switch (accounts, month) {
        case (.failed(let error), _), (_, .failed(let error)):
            ProblemView(error: error) { Task { await loadAll() } }
        case (.loaded(let list), _) where list.isEmpty:
            ContentUnavailableView("No accounts yet", systemImage: "building.columns",
                                   description: Text(model.isLocal
                                                     ? "Add your first account on the Dashboard or in Settings, and it shows here."
                                                     : "Add an account in the web app's Settings, and it shows here."))
        case (.loaded, .loaded(let data)):
            if sizeClass == .regular {
                twoPanes(data)
            } else {
                cards(data)
            }
        default:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Any iPhone, and the Duo closed: the summary, then a card per line.
    private func cards(_ data: ForecastMonth) -> some View {
        List {
            Group {
                Section {
                    header(data)
                    confirmSwitch(data)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                Section {
                    if showingConfirm {
                        confirmRows(data)
                    } else {
                        if data.rows.isEmpty { emptyMonth }
                        ForEach(data.rows) { line in
                            Button { openLine(line) } label: { LineCard(line: line, today: .today()) }
                                .buttonStyle(.plain)
                                .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                                     onDelete: { pendingDelete = $0 }))
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .listRowBackground(Palette.row)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await loadMonth() }
    }

    /// The open Duo: chart and table on the left, the editor or the
    /// month's summary on the right, meeting at the fold with nothing to
    /// read or tap on it. Half open like a small laptop (#90), the fold runs
    /// across: the chart and table above it, the editor below, on the half
    /// that lies on the table.
    private func twoPanes(_ data: ForecastMonth) -> some View {
        GeometryReader { proxy in
            if let fold = Self.tabletopFold(proxy) {
                VStack(spacing: 0) {
                    listPane(data).frame(height: max(0, fold.minY))
                    Color.clear.frame(height: fold.height)
                    sidePane(data).frame(maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    listPane(data).frame(maxWidth: .infinity)
                    sidePane(data).frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The fold when the Duo is half open with it running across (like a
    /// laptop on a table), in this view's space; nil otherwise (iOS 27.1's
    /// division region).
    static func tabletopFold(_ proxy: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division)
                .first { $0.isActive && $0.frame.width > $0.frame.height }?.frame
        }
        return nil
    }

    private func listPane(_ data: ForecastMonth) -> some View {
        List {
            Group {
                Section {
                    header(data)
                    if !showingConfirm {
                        ForecastChart(data: data, month: shownMonth)
                            .card()
                    }
                    confirmSwitch(data)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 28))
                Section {
                    if showingConfirm {
                        confirmRows(data)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 28))
                    } else {
                        if data.rows.isEmpty { emptyMonth } else { LineTableHeader().listRowSeparator(.hidden) }
                        ForEach(data.rows) { line in
                            Button { openLine(line) } label: {
                                LineTableRow(line: line, selected: open?.id == line.id)
                            }
                            .buttonStyle(.plain)
                            .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                                 onDelete: { pendingDelete = $0 }))
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 28))
            }
            .listRowBackground(Palette.row)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await loadMonth() }
    }

    @ViewBuilder
    private func sidePane(_ data: ForecastMonth) -> some View {
        Group {
            if let binding = Binding($open) {
                LineEditor(open: binding, categories: categories, embedded: true, onClose: { open = nil }) { await loadMonth() }
                    .id(binding.wrappedValue.id)
            } else {
                ScrollView {
                    MonthSummaryView(month: shownMonth, data: data, onOpen: openLine)
                        .padding(.leading, 28).padding(.trailing, 16).padding(.bottom, 24)
                }
            }
        }
    }

    private func header(_ data: ForecastMonth) -> some View {
        MonthHeader(accounts: accounts.value ?? [], account: account, month: shownMonth, data: data,
                    onSwitch: switchAccount, onMove: move)
    }

    // MARK: - To confirm (#90)

    private var showingConfirm: Bool { confirming && editable }

    /// All lines, or only those to confirm; shown when this person may
    /// change the account.
    @ViewBuilder
    private func confirmSwitch(_ data: ForecastMonth) -> some View {
        if editable {
            let count = data.toConfirm(today: .today()).count
            Picker("Show", selection: $confirming) {
                Text("All lines").tag(false)
                Text(count > 0 ? "To confirm (\(count))" : "To confirm").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func confirmRows(_ data: ForecastMonth) -> some View {
        let lines = data.toConfirm(today: .today())
        if lines.isEmpty {
            Text(shownMonth.start > .today() ? "Nothing to confirm yet in \(shownMonth.label)." : "Everything up to today is confirmed.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        ForEach(lines) { line in
            ConfirmRow(line: line, onEdit: { openLine(line) }) { amount in await confirm(line, amount: amount) }
                .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                     onDelete: { pendingDelete = $0 }))
        }
    }

    /// Paid as planned (no amount), or paid at the amount typed.
    private func confirm(_ line: ForecastLine, amount: String?) async {
        guard let account else { return }
        let draft = amount.map { LineDraft.paid(line, amountText: $0, today: .today()) }
            ?? .paidAsPlanned(line, today: .today())
        if await change(line, { try await $0.save(line, draft: draft, account: account.id) }) {
            settings.start.done.insert(.markPaid)  // Getting started (#177)
        }
    }

    private var emptyMonth: some View {
        Text("Nothing planned or recorded in \(shownMonth.label).")
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Compare (#90): only with room for two sides, the open Duo.
        if sizeClass == .regular, account != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Compare", systemImage: "rectangle.split.2x1") { comparing = true }
            }
        }
        if editable {
            AddMenu(addTitle: "Add transaction", canMove: editableAccounts.count > 1, onAdd: {
                newDraft = NewTransactionDraft(today: shownMonth.contains(.today()) ? .today() : shownMonth.start)
                adding = true
            }, onMove: {
                moveDraft = MoveMoneyDraft(today: .today(), from: account?.id)
                moving = true
            })
        }
    }

    // MARK: - Actions

    private func openLine(_ line: ForecastLine) {
        guard let account else { return }
        open = OpenLine(line, account: account, editable: editable)
    }

    private func move(_ by: Int) {
        open = nil
        monthText = (by < 0 ? shownMonth.previous : shownMonth.next).description
    }

    private func switchAccount(_ id: Int) {
        open = nil
        accountId = id
    }

    private func markPaid(_ line: ForecastLine) {
        guard let account else { return }
        Task {
            if await change(line, { try await $0.save(line, draft: .paidAsPlanned(line, today: .today()), account: account.id) }) {
                settings.start.done.insert(.markPaid)  // Getting started (#177)
            }
        }
    }

    /// A change made from the list (a swipe, a delete). If that line is
    /// open in the editor, the editor closes: what it held is out of date.
    /// True when the server took it.
    @discardableResult
    private func change(_ line: ForecastLine, _ action: (APIClient) async throws -> Void) async -> Bool {
        guard let client = model.client else { return false }
        var done = false
        do {
            try await action(client)
            done = true
        } catch {
            problem = AppModel.describe(error)
        }
        if open?.id == line.id { open = nil }
        await loadMonth()
        return done
    }

    private func deleteTitle(_ line: ForecastLine) -> String {
        line.isProjection ? "Delete \(line.description) on \(line.plannedDate?.short ?? "")?" : "Delete \(line.description)?"
    }

    // MARK: - Loading

    private func loadAll() async {
        guard let client = model.client(kept) else { return }
        do {
            let list = try await client.accounts()
            accounts = .loaded(list)
            if !list.contains(where: { $0.id == accountId }), let first = list.first { accountId = first.id }
        } catch {
            accounts = .failed(error)
            kept.clear()
            return
        }
        categories = (try? await client.categories()) ?? []
        await loadMonth()
        if AppModel.debugSetting("WW_DEBUG_CONFIRM") != nil { confirming = true }
        if AppModel.debugSetting("WW_DEBUG_COMPARE") != nil { comparing = true }
        if let name = AppModel.debugSetting("WW_DEBUG_OPEN_LINE"),
           let line = month.value?.rows.first(where: { $0.description == name }) { openLine(line) }
    }

    private func loadMonth() async {
        guard let client = model.client(kept), let account else { return }
        do {
            month = .loaded(try await client.forecast(account: account.id, month: shownMonth))
        } catch {
            month = .failed(error)
            kept.clear()
        }
    }
}

// MARK: - Swipes

/// Swipe right to mark a line paid as planned, or to edit it (#160: a paid
/// line offers Edit, not Undo paid; undoing is the editor's Paid switch);
/// swipe left to delete. Only on lines this person may change.
struct LineSwipes: ViewModifier {
    let line: ForecastLine
    let editable: Bool
    let onPaid: (ForecastLine) -> Void
    let onEdit: (ForecastLine) -> Void
    let onDelete: (ForecastLine) -> Void

    func body(content: Content) -> some View {
        if editable && line.canEdit(onEditableAccount: true) {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !line.isPaid {
                        Button("Paid", systemImage: "checkmark.circle") { onPaid(line) }
                            .tint(Palette.good)
                    }
                    Button("Edit", systemImage: "pencil") { onEdit(line) }
                        .tint(Palette.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(line) }
                }
        } else {
            content
        }
    }
}

// MARK: - The month's header

/// The account, with the web app's account switcher; its month, with
/// previous and next; balance today, and the forecast and actual month-end.
struct MonthHeader: View {
    let accounts: [Account]
    let account: Account?
    let month: YearMonth
    let data: ForecastMonth
    let onSwitch: (Int) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let account {
                if accounts.count > 1 {
                    Menu {
                        Picker("Account", selection: Binding(get: { account.id }, set: onSwitch)) {
                            ForEach(accounts) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(account.name).font(.title3.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Account: \(account.name). Switch account")
                } else {
                    Text(account.name).font(.title3.weight(.semibold))
                }
            }
            HStack {
                Button("Previous month", systemImage: "chevron.left") { onMove(-1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(month.label).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { onMove(1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow(alignment: .bottom) {
                    Caption("Today")
                    Caption("Forecast end").fixedSize(horizontal: false, vertical: true)
                    Caption("Actual end").fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    figure(data.currentBalance)
                    figure(data.forecastEndingBalance)
                    figure(data.actualEndingBalance)
                }
            }
        }
        .card()
    }

    private func figure(_ value: Money) -> some View {
        Text(value.formatted)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(Palette.amount(value.isNegative))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - A line, closed

/// One line as a card, as the web app's phone layout shows it: name and
/// amount, the planned and paid dates, category, both balances, and the
/// difference when there is one. Not-yet-paid lines are dimmed a little.
struct LineCard: View {
    let line: ForecastLine
    let today: LocalDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                PaidMark(line: line, today: today)
                Text(line.description).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(line.amount.formatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(line.amount.isNegative ? Palette.bad : Palette.good)
            }
            HStack(spacing: 6) {
                Text(dates).font(.subheadline).foregroundStyle(.secondary)
                if let category = line.category {
                    Text("·").foregroundStyle(.tertiary)
                    Text(category).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if line.isTransfer {
                    Text("Transfer").font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 14) {
                balance("Balance", line.actualBalance)
                balance("Planned", line.forecastBalance)
                if line.differsFromPlan, let diff = line.diffAmount, diff != .zero {
                    balance("Difference", diff, colored: true)
                }
            }
            if let notes = line.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .opacity(line.isPaid ? 1 : 0.82)
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the line")
    }

    private var dates: String {
        let planned = line.plannedDate?.short ?? ""
        guard line.isPaid, let paid = line.actualDate else { return planned }
        return paid == line.plannedDate ? "Paid \(paid.short)" : "Planned \(planned) · paid \(paid.short)"
    }

    private func balance(_ label: String, _ value: Money, colored: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted).font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(colored ? (value.isNegative ? Palette.bad : Palette.good) : Palette.amount(value.isNegative))
        }
    }
}

/// Paid (a filled check), not paid yet (an empty circle), or past its date
/// and not marked paid (an orange clock).
struct PaidMark: View {
    let line: ForecastLine
    let today: LocalDay

    var body: some View {
        Group {
            if line.isPaid {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
                    .accessibilityLabel("Paid")
            } else if let day = line.plannedDate, day < today {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Palette.warn)
                    .accessibilityLabel("Past its date, not marked paid")
            } else {
                Image(systemName: "circle").foregroundStyle(.secondary)
                    .accessibilityLabel("Not paid yet")
            }
        }
        .font(.subheadline)
    }
}

// MARK: - The table, open

/// The full table on the open Duo, in half its width: each money column
/// holds two figures, so all seven of the web app's columns fit — date;
/// name over category; forecast over actual; balance over the difference.
private enum Column {
    static let date: CGFloat = 24
    static let money: CGFloat = 80
}

struct LineTableHeader: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Text("Day").frame(width: Column.date, alignment: .leading)
            Text("Name\nCategory").frame(maxWidth: .infinity, alignment: .leading)
            Text("Forecast\nActual").frame(width: Column.money, alignment: .trailing)
            Text("Balance\nDifference").frame(width: Column.money, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

struct LineTableRow: View {
    let line: ForecastLine
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The table is always one month, so the day is enough.
            Text(line.plannedDate.map { String($0.day) } ?? "").frame(width: Column.date, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    PaidMark(line: line, today: .today()).font(.caption)
                    Text(line.description).lineLimit(2)
                }
                Text(line.category ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                money(line.forecastAmount, colored: false)
                money(line.isPaid ? line.actualAmount : nil, colored: false).font(.caption2)
            }
            .frame(width: Column.money, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                money(line.actualBalance, colored: false)
                money(line.differsFromPlan ? line.diffAmount : nil, colored: true, blank: true).font(.caption2)
            }
            .frame(width: Column.money, alignment: .trailing)
        }
        .font(.footnote.monospacedDigit())
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .opacity(line.isPaid ? 1 : 0.85)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [line.description, line.plannedDate?.short ?? "", line.amount.formatted,
                     line.isPaid ? "paid" : "not paid", "balance \(line.actualBalance.formatted)"]
        if let category = line.category { parts.insert(category, at: 1) }
        return parts.joined(separator: ", ")
    }

    private func money(_ value: Money?, colored: Bool, blank: Bool = false) -> some View {
        Text(value?.formatted ?? (blank ? " " : "—"))
            .foregroundStyle(value.map { colored ? ($0.isNegative ? Palette.bad : Palette.good) : Palette.amount($0.isNegative) }
                             ?? Color.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The month's balance, planned (dashed) and actual, with today marked.
struct ForecastChart: View {
    let data: ForecastMonth
    let month: YearMonth

    struct Point: Identifiable {
        let day: LocalDay
        let balance: Money
        let series: String
        var id: String { "\(series)\(day)" }
    }

    /// One point per day a line falls on (the day's last balance), from
    /// the opening balance on the 1st.
    private var points: [Point] {
        func series(_ name: String, _ day: (ForecastLine) -> LocalDay?, _ value: (ForecastLine) -> Money) -> [Point] {
            var byDay: [LocalDay: Money] = [month.start: data.openingBalance]
            let ordered = data.rows.compactMap { line in day(line).map { ($0, value(line)) } }
            for (d, v) in ordered.sorted(by: { $0.0 < $1.0 }) where month.contains(d) { byDay[d] = v }
            return byDay.keys.sorted().map { Point(day: $0, balance: byDay[$0]!, series: name) }
        }
        return series("Planned", { $0.plannedDate }, { $0.forecastBalance })
            + series("Actual", { $0.actualDate ?? $0.plannedDate }, { $0.actualBalance })
    }

    var body: some View {
        let today = LocalDay.today()
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day.date), y: .value("Balance", point.balance.amount),
                         series: .value("Series", point.series))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: point.series == "Planned" ? [4, 3] : []))
            }
            if month.contains(today) {
                RuleMark(x: .value("Today", today.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Today").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(["Actual": Palette.accent, "Planned": Color.secondary])
        .chartXScale(domain: month.start.date...month.end.date)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Money(v).short).foregroundStyle(.secondary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day()).foregroundStyle(.secondary)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 170)
        .accessibilityLabel("Balance through \(month.label)")
        .accessibilityValue("Ends at \(data.actualEndingBalance.formatted)")
    }
}

// MARK: - The month's summary, open

/// The right half of the open Duo before a line is tapped: income and
/// spending against plan, what's still to come, the low and the high, and
/// the lines that differ from plan.
struct MonthSummaryView: View {
    let month: YearMonth
    let data: ForecastMonth
    let onOpen: (ForecastLine) -> Void

    var body: some View {
        let today = LocalDay.today()
        let s = ForecastSummary(data, today: today)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Caption("\(month.label) against plan")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        Text("So far").font(.caption).foregroundStyle(.secondary)
                        Text("Planned").font(.caption).foregroundStyle(.secondary)
                    }
                    row("Income", s.incomeSoFar, s.incomePlanned, Palette.good)
                    row("Spending", s.spendingSoFar, s.spendingPlanned, Palette.bad)
                }
                .font(.callout)
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Caption("Still to come")
                if s.comingCount == 0 {
                    Text(month < YearMonth(today) ? "This month is over." : "Nothing left to come this month.")
                        .font(.callout)
                } else {
                    let net = Text(s.comingNet.formatted).bold()
                        .foregroundStyle(s.comingNet.isNegative ? Palette.bad : Palette.good)
                    Text("**\(s.comingCount)** line\(s.comingCount == 1 ? "" : "s") not paid yet, net \(net)")
                }
                if !s.overdue.isEmpty {
                    Divider()
                    Label("Past their date, not marked paid", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.warn)
                    ForEach(s.overdue) { lineButton($0) }
                }
            }
            .card()

            HStack(spacing: 14) {
                extreme("Low", s.low.balance, s.low.date)
                extreme("High", s.high.balance, s.high.date)
            }

            VStack(alignment: .leading, spacing: 8) {
                Caption("Different from plan")
                if s.differing.isEmpty {
                    Text("Everything paid so far matched its plan.").font(.callout)
                } else {
                    ForEach(s.differing) { lineButton($0, showingDiff: true) }
                }
            }
            .card()

            Text("Tap a line on the left to mark it paid or change it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ soFar: Money, _ planned: Money, _ color: Color) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(soFar.formatted).monospacedDigit().foregroundStyle(color)
            Text(planned.formatted).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func extreme(_ label: String, _ value: Money, _ day: LocalDay?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(label)
            Text(value.formatted).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(day?.short ?? "Start of month").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func lineButton(_ line: ForecastLine, showingDiff: Bool = false) -> some View {
        Button { onOpen(line) } label: {
            HStack {
                Text(line.plannedDate?.short ?? "").foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                Text(line.description).lineLimit(1)
                Spacer()
                if showingDiff, let diff = line.diffAmount, diff != .zero {
                    Text(diff.formatted).foregroundStyle(diff.isNegative ? Palette.bad : Palette.good)
                } else if showingDiff {
                    Text("paid \(line.actualDate?.short ?? "")").foregroundStyle(.secondary)
                } else {
                    Text(line.plannedAmount.formatted).foregroundStyle(Palette.amount(line.plannedAmount.isNegative))
                }
            }
            .font(.subheadline.monospacedDigit())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
