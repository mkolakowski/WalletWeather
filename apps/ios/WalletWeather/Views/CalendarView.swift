import SwiftUI
import WalletWeatherKit

/// Calendar: the month with each day's bills and paychecks, today marked.
/// All accounts by default, or one, which adds each day's closing balance
/// (decided 2026-11-15). Closed: a compact month with each day's net and a
/// colour bar per line (#323), and the tapped day's lines under it. Open: the month on the left with amounts written
/// in each day, and on the right the tapped day's lines, or today's lines
/// and balances until a day is tapped. A line opens in the line editor (the
/// right half when open, a sheet when closed) and swipes to Paid, Edit and
/// Delete as in Forecast; an account's balance opens it in Forecast (#305).
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 0 for all accounts.
    @SceneStorage("calendar.account") private var accountId = 0
    /// The account chosen on each other connection, in this window (#299).
    @SceneStorage("calendar.account.byConnection") private var accountMemo = ""
    @Environment(AppSettings.self) private var settings
    private let follower = AccountFollower()
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
    /// A line open in the editor (#305), the Undo bar after one is marked
    /// paid from the list, and what a failed change says.
    @State private var openLine: OpenLine?
    @State private var undoOffer: UndoOffer?
    @State private var paidCount = 0
    @State private var pendingDelete: CalendarEvent?
    @State private var problem: ListProblem?
    /// Counts lines moved by a drop on a day (#308), for the success haptic.
    @State private var movedCount = 0

    private var shownMonth: YearMonth { YearMonth(monthText) ?? YearMonth(.today()) }
    private var account: Account? { accounts.first { $0.id == accountId } }

    /// The account menu's selection: a pick here also moves the other pages
    /// (#317); the page's own automatic changes don't go through it.
    private var pickedAccount: Binding<Int> {
        Binding(get: { accountId },
                set: { id in
                    accountId = id
                    follower.picked(id, on: .calendar, following: settings.pagesFollowAccount)
                })
    }
    private var editableAccounts: [Account] { accounts.filter(model.canEdit) }
    private var selected: LocalDay? { LocalDay(dayText).flatMap { shownMonth.contains($0) ? $0 : nil } }

    var body: some View {
        PageStack {
            content
                .opensForecast()
                .keptBar(kept)
                .sensoryFeedback(.success, trigger: paidCount)
                .sensoryFeedback(.success, trigger: movedCount)
                .background(PageBackground().ignoresSafeArea())
                // The large title on the phone; a glass capsule on the open Duo (#341).
                .pageTitle("Calendar")
                .toolbar { NewWindowItem(place: .calendar) }
                .toolbar {
                    if !editableAccounts.isEmpty {
                        AddMenu(addTitle: "Add line", canMove: editableAccounts.count > 1, onAdd: startAdding, onMove: {
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
        .pageShortcuts(.calendar, shortcuts)
        .lineEditorSheet($openLine, categories: categories) { await load() }
        .confirmationDialog(pendingDelete.map(deleteTitle) ?? "", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { event in
            Button(event.recurringId != nil && event.transactionId == nil ? "Delete this date" : "Delete", role: .destructive) {
                delete(event)
            }
        } message: { event in
            Text(event.recurringId != nil && event.transactionId == nil
                 ? "The repeating bill or paycheck keeps its other dates." : "This can't be undone.")
        }
        .problemAlert($problem)
        // The editor and the bar belong to the account and month they were shown on.
        .onChange(of: accountId) { undoOffer = nil; openLine = nil }
        .onChange(of: monthText) { undoOffer = nil; openLine = nil }
        .onChange(of: model.generation) { undoOffer = nil; openLine = nil }
        .onChange(of: openLine != nil) { _, isOpen in if isOpen { undoOffer = nil } }
        // A line moved by a drop here or in another window (#308).
        .onChange(of: model.lastLineMove) { _, move in
            if let move, openLine?.line.transactionId == move.transactionId { openLine = nil }
            Task { await load() }
        }
        .scopedToConnection($accountId, memo: $accountMemo)
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
                // The open Duo (#304): the month on the left (above, half open
                // like a laptop), the day on the right (below).
                FoldLayout { edges in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            header
                            MonthGrid(month: shownMonth, data: data, selected: selected, wide: true, onTap: select, drop: dayDrop)
                                .card()
                        }
                        .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
                    }
                } trailing: { edges in
                    sidePane(data, edges: edges)
                }
                .refreshable { await load() }
            } else {
                List {
                    Section {
                        header
                        MonthGrid(month: shownMonth, data: data, selected: selected, wide: false, onTap: select, drop: dayDrop)
                            .card()
                    }
                    .calendarRows(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    let day = selected ?? (shownMonth.contains(.today()) ? .today() : shownMonth.start)
                    DayLines(day: day, data: data, showAccount: account == nil, onClose: nil,
                             insets: EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16), actions: actions)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
                .undoBar($undoOffer)
            }
        }
    }

    /// The right half of the open Duo: the line in its editor, or the tapped
    /// day's lines, or today's, with the Undo bar on the lines' own half.
    @ViewBuilder
    private func sidePane(_ data: CalendarMonth, edges: FoldPanes.Edges) -> some View {
        if let binding = lasting($openLine) {
            LineEditor(open: binding, categories: categories, embedded: true, onClose: { openLine = nil }) { await load() }
                .id(binding.wrappedValue.id)
        } else {
            let insets = EdgeInsets(top: 5, leading: edges.leading, bottom: 5, trailing: edges.trailing)
            List {
                if let day = selected {
                    DayLines(day: day, data: data, showAccount: account == nil, onClose: { dayText = "" },
                             insets: insets, actions: actions)
                } else {
                    TodayView(data: data, month: shownMonth, accounts: account.map { [$0] } ?? accounts,
                              showAccount: account == nil, insets: insets, actions: actions)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .undoBar($undoOffer)
        }
    }

    /// The account switcher (All accounts, or one) and the month.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if accounts.count > 1 {
                Menu {
                    Picker("Account", selection: pickedAccount) {
                        Text("All accounts").tag(0)
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(account?.name ?? "All accounts").font(.title3.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel("Showing \(account?.name ?? "all accounts"). Switch account")
            }
            MonthBar(month: shownMonth, onMove: move, onPick: jump)
            if account == nil && accounts.count > 1 {
                Text("Pick one account to see each day's closing balance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    /// The keyboard (#307): ⌘N, ⌘R, ⌘[ and ⌘] for the months, ⌘T.
    private var shortcuts: [ShortcutHandler] {
        [ShortcutHandler(.addTransaction, enabled: !editableAccounts.isEmpty) { startAdding() },
         ShortcutHandler(.refresh) { Task { await load() } },
         ShortcutHandler(.previousMonth) { move(-1) },
         ShortcutHandler(.nextMonth) { move(1) },
         ShortcutHandler(.thisMonth, enabled: shownMonth != YearMonth(.today())) { jump(to: YearMonth(.today())) }]
    }

    private func startAdding() {
        newDraft = NewTransactionDraft(today: selected ?? .today())
        adding = true
    }

    private func select(_ day: LocalDay) {
        openLine = nil
        dayText = selected == day && sizeClass == .regular ? "" : day.description
    }

    private func move(_ by: Int) {
        openLine = nil
        dayText = ""
        monthText = (by < 0 ? shownMonth.previous : shownMonth.next).description
    }

    private func jump(to month: YearMonth) {
        openLine = nil
        dayText = ""
        monthText = month == YearMonth(.today()) ? "" : month.description
    }

    // MARK: - Lines (#305)

    /// What a line in the lists can do: open in the editor, and Forecast's swipes.
    private var actions: CalendarLineActions {
        CalendarLineActions(
            canEdit: { event in accounts.first { $0.id == event.accountId }.map(model.canEdit) ?? false },
            open: { event in Task { await open(event) } },
            paid: markPaid,
            delete: { pendingDelete = $0 },
            drag: { event in
                let canEdit = accounts.first { $0.id == event.accountId }.map(model.canEdit) ?? false
                return LineDrag(event: event, canChange: LineDrag.allowed(canEdit: canEdit, lockedInDemo: settings.lockedInDemo))
            })
    }

    // MARK: - Drag a line to a day (#308)

    /// The month takes dropped lines when some account may change and the
    /// lock hasn't put the demo in front; nil otherwise, so no day is a target.
    private var dayDrop: DayDrop? {
        guard !settings.lockedInDemo, !editableAccounts.isEmpty else { return nil }
        let debug = DropDebug.highlightedDay(AppModel.debugSetting("WW_DEBUG_DROP"), month: shownMonth, today: .today())
        return DayDrop(debugDay: debug, onDrop: dropLine)
    }

    /// A line dropped on `day`: taken when it moves to another day on an
    /// account this person may change; saved after the drop ends.
    private func dropLine(_ drag: LineDrag, on day: LocalDay) -> Bool {
        guard drag.moves(to: day), let account = accounts.first(where: { $0.id == drag.accountId }),
              LineDrag.allowed(canEdit: model.canEdit(account), lockedInDemo: settings.lockedInDemo) else { return false }
        Task { await moveLine(drag, to: day, offeringUndo: true) }
        return true
    }

    /// Moves the line's planned date as the editor's "Planned for" does: the
    /// line is read again from its account's Forecast and saved with only
    /// that changed. Then every page showing lines reads them again. Undo
    /// moves it back the same way. True when the server took it.
    private func moveLine(_ drag: LineDrag, to day: LocalDay, offeringUndo: Bool) async -> Bool {
        guard let client = model.client else { return false }
        var done = false
        do {
            let forecast = try await client.forecast(account: drag.accountId, month: drag.month)
            if let line = drag.line(in: forecast), let draft = LineDraft.moved(line, to: day, today: .today()) {
                try await client.save(line, draft: draft, account: drag.accountId)
                done = true
            } else {
                problem = .gone("\(drag.name) isn't planned for \(drag.plannedOn.short) any more. Pull down to refresh.")
            }
        } catch {
            problem = ListProblem(error)
        }
        if done && offeringUndo {
            movedCount += 1
            let moved = drag.moved(to: day)
            undoOffer = UndoOffer(message: "\(drag.name) moved to \(day.short)") {
                await moveLine(moved, to: drag.plannedOn, offeringUndo: false)
            }
        }
        model.lastLineMove = LineMove(transactionId: drag.transactionId)
        return done
    }

    /// The line in the editor: the Calendar's line is found again in its
    /// account's Forecast (`APIClient.forecastLine`), which holds what the
    /// editor works from. Transfers and accounts that can't be edited open
    /// read-only, as in Forecast.
    private func open(_ event: CalendarEvent) async {
        guard let client = model.client, let account = accounts.first(where: { $0.id == event.accountId }) else { return }
        do {
            guard let line = try await client.forecastLine(for: event) else {
                problem = .gone("\(event.description) isn't in the forecast any more. Pull down to refresh the Calendar.")
                return
            }
            openLine = OpenLine(line, account: account, editable: model.canEdit(account))
        } catch {
            problem = ListProblem(error)
        }
    }

    private func markPaid(_ event: CalendarEvent) {
        Task {
            guard let client = model.client else { return }
            do {
                guard let line = try await client.forecastLine(for: event) else {
                    problem = .gone("\(event.description) isn't in the forecast any more. Pull down to refresh the Calendar.")
                    return
                }
                try await client.save(line, draft: .paidAsPlanned(line, today: .today()), account: event.accountId)
                settings.start.done.insert(.markPaid)  // Getting started (#177)
                paidCount += 1
                undoOffer = UndoOffer(message: "\(line.description) marked paid") {
                    await undoPaid(line, account: event.accountId)
                }
            } catch {
                problem = ListProblem(error)
            }
            await load()
        }
    }

    /// Takes "paid" back as Forecast's Undo does: finds the line again in its
    /// reloaded month (a projected date is a transaction now) and saves it
    /// not paid.
    private func undoPaid(_ line: ForecastLine, account: Int) async -> Bool {
        guard let client = model.client else { return false }
        var done = false
        do {
            let reloaded = try await client.forecast(account: account, month: YearMonth(line.plannedDate ?? .today()))
            if let paid = reloaded.reloaded(line) {
                try await client.save(paid, draft: .unpaid(paid, today: .today()), account: account)
                done = true
            } else {
                problem = .gone("\(line.description) isn't in the forecast any more, so it can't be undone here.")
            }
        } catch {
            problem = ListProblem(error)
        }
        await load()
        return done
    }

    private func delete(_ event: CalendarEvent) {
        Task {
            guard let client = model.client else { return }
            do {
                if let line = try await client.forecastLine(for: event) { try await client.delete(line) }
            } catch {
                problem = ListProblem(error)
            }
            await load()
        }
    }

    private func deleteTitle(_ event: CalendarEvent) -> String {
        event.transactionId == nil && event.recurringId != nil
            ? "Delete \(event.description) on \(event.date.short)?" : "Delete \(event.description)?"
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
        // Debug only: `WW_DEBUG_OPEN_LINE=<name>` also opens that line of the day (#305).
        if let name = AppModel.debugSetting("WW_DEBUG_OPEN_LINE"), let data = month.value,
           let event = data.events.first(where: { $0.description == name && (selected == nil || $0.date == selected) }) {
            await open(event)
        }
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
    /// Lines dropped on a day move there (#308); nil where nothing may move.
    var drop: DayDrop? = nil
    @State private var hovered: LocalDay?

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
                                selected: day == selected, wide: wide,
                                dropTarget: drop != nil && (day == hovered || day == drop?.debugDay))
                    }
                    .buttonStyle(.plain)
                    .modifier(DayDropTarget(day: day, drop: drop, hovered: $hovered))
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
    /// A dragged line is over this day (#308): outlined and tinted, with no
    /// change to the cell's size.
    var dropTarget = false

    // Sizes that hold text grow with it (#311): the day's circle, the dots
    // and the 9 and 10 point figures, each exactly as before at Large.
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var scaledCircle: CGFloat = 30
    @ScaledMetric(relativeTo: .callout) private var dotSize: CGFloat = 5
    @ScaledMetric(relativeTo: .caption2) private var countSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption2) private var balanceSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var netSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 4

    /// The day's net and balance written in. At the accessibility sizes
    /// seven columns can't hold amounts: the grid shows the day and its dots,
    /// and the amounts are in the day's list below.
    private var showsAmounts: Bool { wide && !typeSize.isAccessibilitySize }

    /// The closed phone's cell (#323): the day's net under the number and a
    /// bar per line, as the web's phone Calendar draws it. Past the
    /// accessibility sizes there is no room, so the day keeps its dots.
    private var showsBars: Bool { !wide && !typeSize.isAccessibilitySize }

    /// The day's circle: 30 at Large, growing with the text up to the width
    /// a column has on the closed phone (seven across the card); past that
    /// the number shrinks inside it.
    private var circle: CGFloat { min(scaledCircle, 44) }

    var body: some View {
        let isToday = day == .today()
        VStack(spacing: showsAmounts ? 2 : 3) {
            Text("\(day.day)")
                .font(wide ? .subheadline.weight(isToday || selected ? .bold : .regular) : .callout.weight(isToday || selected ? .bold : .regular))
                // Today is the filled circle (#323); the chosen day is the
                // tinted cell around its number.
                .foregroundStyle(isToday ? Color.white : (selected ? Palette.accent : .primary))
                // Always the whole number: past where the circle fits its
                // column, the number shrinks inside it rather than cut.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, typeSize <= .large ? 0 : 3)
                .frame(width: circle, height: circle)
                .background {
                    if isToday { Circle().fill(Palette.accent) }
                }
            if showsAmounts {
                amounts
            } else if showsBars {
                if let net = summary.shortNet {
                    fitted { scaled in
                        Text(net)
                            .font(.system(size: scaled ? netSize : 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(summary.net.isNegative ? Palette.bad : Palette.good)
                    }
                }
                bars(spacing: 2)
                    .padding(.horizontal, 3)
                    .frame(height: barsHeight(spacing: 2), alignment: .top)
            } else {
                HStack(spacing: 3) {
                    if summary.hasBill { dot(Palette.bad) }
                    if summary.hasIncome { dot(Palette.good) }
                    if summary.hasTransfer { dot(.secondary) }
                }
                .frame(height: dotSize + 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: showsAmounts ? 100 : (showsBars ? 66 : 44), alignment: .top)
        .padding(.vertical, showsAmounts ? 4 : 2)
        .background(selected ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if selected && !wide {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.6), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if dropTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Palette.accent.opacity(0.18))
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent, lineWidth: 2.5)
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Colour bars (#323)

    /// One thin bar per line, the first three; decorative (the cell's label
    /// carries the count and net).
    private func bars(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(summary.visibleBars.enumerated()), id: \.offset) { _, bar in
                barShape(bar)
            }
        }
        .accessibilityHidden(true)
    }

    /// The room `DayBar.limit` bars take, held whether or not a day has
    /// them, so every cell in the month is the same height.
    private func barsHeight(spacing: CGFloat) -> CGFloat {
        CGFloat(DayBar.limit) * barHeight + CGFloat(DayBar.limit - 1) * spacing
    }

    @ViewBuilder
    private func barShape(_ bar: DayBar) -> some View {
        let opacity = bar.isPaid ? 0.85 : 0.45
        switch bar.style {
        case let .category(hex): Capsule().fill(Palette.category(hex, name: "").opacity(opacity)).frame(height: barHeight)
        case .income: Capsule().fill(Palette.good.opacity(opacity)).frame(height: barHeight)
        case .spending: Capsule().fill(Palette.bad.opacity(opacity)).frame(height: barHeight)
        case .transfer: Capsule().strokeBorder(Color.secondary.opacity(bar.isPaid ? 1 : 0.6), lineWidth: 1).frame(height: barHeight)
        }
    }

    /// Wide: the day's net, and the closing balance with one account.
    @ViewBuilder
    private var amounts: some View {
        if summary.count > 0 {
            fitted { _ in
                Text(summary.shortNet ?? "")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(summary.net.isNegative ? Palette.bad : Palette.good)
            }
            if summary.count > 1 {
                fitted { scaled in
                    Text("\(summary.count) lines").font(.system(size: scaled ? countSize : 9)).foregroundStyle(.secondary)
                }
            }
            bars(spacing: 2)
                .padding(.horizontal, 4)
                .padding(.top, 1)
        }
        Spacer(minLength: 0)
        if let balance {
            fitted { scaled in
                Text(balance.short).font(.system(size: scaled ? balanceSize : 10).monospacedDigit())
                    .foregroundStyle(balance.isNegative ? Palette.bad : .secondary)
            }
        }
    }

    /// A figure in a cell: whole at the phone's text size when it fits the
    /// column, else as at the default size, shrinking a little as it always
    /// has. Never cut short.
    private func fitted<Figure: View>(@ViewBuilder _ text: @escaping (_ scaled: Bool) -> Figure) -> some View {
        ViewThatFits(in: .horizontal) {
            text(true).fixedSize()
            text(false).dynamicTypeSize(.large).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: dotSize, height: dotSize)
    }

    private var accessibilityText: String {
        var parts = [day.written(width: .wide)]
        if day == .today() { parts.append("today") }
        if summary.count > 0 { parts.append("\(summary.count) line\(summary.count == 1 ? "" : "s"), net \(summary.net.formatted)") }
        if let balance { parts.append("closing balance \(balance.formatted)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - A day's lines

/// What a line in the Calendar's lists does (#305): the person can change it,
/// opens in the editor, and Forecast's swipes (`LineSwipes`).
struct CalendarLineActions {
    let canEdit: (CalendarEvent) -> Bool
    let open: (CalendarEvent) -> Void
    let paid: (CalendarEvent) -> Void
    let delete: (CalendarEvent) -> Void
    /// The line as something to drag onto a day (#308), or nil when its
    /// date can't move here.
    let drag: (CalendarEvent) -> LineDrag?
}

extension View {
    /// A row of a Calendar list that is a card of its own: no list chrome.
    func calendarRows(_ insets: EdgeInsets) -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(insets)
    }
}

/// The lines of one day, with its closing balance when one account is shown:
/// rows of a list, each a card that opens in the editor and swipes.
struct DayLines: View {
    let day: LocalDay
    let data: CalendarMonth
    let showAccount: Bool
    let onClose: (() -> Void)?
    let insets: EdgeInsets
    let actions: CalendarLineActions

    var body: some View {
        let lines = data.events(on: day)
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day == .today() ? "Today" : day.written(width: .wide))
                        .font(.headline)
                    Spacer()
                    if let onClose {
                        Button("Close", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).buttonStyle(.glass)
                    }
                }
                if let balance = data.balance(on: day) {
                    let figure = Text(balance.formatted).font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.amount(balance.isNegative))
                        .wholeFigure()
                    FitsAcross {
                        HStack {
                            Caption("Closing balance")
                            Spacer()
                            figure
                        }
                    } stacked: {
                        VStack(alignment: .leading, spacing: 2) {
                            Caption("Closing balance")
                            figure
                        }
                    }
                }
                if lines.isEmpty {
                    Text("Nothing on this day.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .card()
            .calendarRows(insets)
            ForEach(lines) { line in
                Button { actions.open(line) } label: { CalendarLineRow(line: line, showAccount: showAccount).card() }
                    .buttonStyle(.plain)
                    .pointerCard()
                    .accessibilityHint("Opens the line")
                    .modifier(LineSwipes(event: line, editable: actions.canEdit(line), onPaid: actions.paid,
                                         onEdit: actions.open, onDelete: actions.delete))
                    .lineDrag(actions.drag(line))
                    .calendarRows(insets)
            }
        }
    }
}

struct CalendarLineRow: View {
    let line: CalendarEvent
    let showAccount: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: line.isPaid ? "checkmark.circle.fill" : (line.isTransfer ? "arrow.left.arrow.right" : "circle"))
                .foregroundStyle(line.isPaid ? Palette.good : .secondary)
                .font(.subheadline)
                .accessibilityLabel(line.isPaid ? "Paid" : "Not paid yet")
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description).lineLimit(large ? nil : 2)
                let detail = [showAccount ? line.accountName : nil, line.categoryName,
                              line.recurringId != nil ? "repeats" : nil].compactMap { $0 }
                if !detail.isEmpty {
                    Text(detail.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(large ? nil : 1)
                }
                // The accessibility sizes: the amount under the words (#311).
                if large { amount }
            }
            Spacer(minLength: 8)
            if !large { amount }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amount: some View {
        if let amount = line.amount {
            Text(amount.formatted).monospacedDigit()
                .foregroundStyle(line.isTransfer ? .secondary : (amount.isNegative ? Palette.bad : Palette.good))
                .wholeFigure()
        }
    }
}

/// The right half of the open Duo before a day is tapped: each account's
/// balance today (each opens in Forecast), and today's lines.
struct TodayView: View {
    let data: CalendarMonth
    let month: YearMonth
    let accounts: [Account]
    let showAccount: Bool
    let insets: EdgeInsets
    let actions: CalendarLineActions

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Caption("Balances today")
                ForEach(accounts) { account in
                    OpenInForecastButton(account: account.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                ForecastHint()
                            }
                            Spacer()
                            Text(account.currentBalance.formatted).monospacedDigit()
                                .foregroundStyle(Palette.amount(account.currentBalance.isNegative))
                                .wholeFigure()
                        }
                        .font(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens in Forecast")
                }
            }
            .card()
            .calendarRows(insets)
        }
        if month.contains(.today()) {
            DayLines(day: .today(), data: data, showAccount: showAccount, onClose: nil, insets: insets, actions: actions)
        } else {
            Text("Today isn't in \(month.label).").font(.callout).foregroundStyle(.secondary).calendarRows(insets)
        }
        Text("Tap a day to see its lines.").font(.footnote).foregroundStyle(.secondary).calendarRows(insets)
    }
}
