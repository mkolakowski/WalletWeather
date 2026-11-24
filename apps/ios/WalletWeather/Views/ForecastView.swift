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
    /// At the accessibility text sizes the open Duo's table becomes the
    /// cards the closed phone shows, in its pane (#311).
    @Environment(\.dynamicTypeSize) private var typeSize
    @SceneStorage("forecast.account") private var accountId = 0
    /// The account chosen on each other connection, in this window (#299).
    @SceneStorage("forecast.account.byConnection") private var accountMemo = ""
    private let follower = AccountFollower()
    @SceneStorage("forecast.month") private var monthText = ""
    /// The "To confirm" switch (#90): only the lines due up to today and
    /// not yet paid, each with Paid as planned and a box for another amount.
    @SceneStorage("forecast.confirming") private var confirming = false
    /// The category or tag chosen under the picker (#327), as `ForecastFilter.rawValue`; empty is All.
    @SceneStorage("forecast.filter") private var filterText = ""

    @State private var accounts: Loadable<[Account]> = .loading
    @State private var month: Loadable<ForecastMonth> = .loading
    @State private var kept = KeptTracker()
    @State private var categories: [TransactionCategory] = []
    @State private var open: OpenLine?
    @State private var adding = false
    @State private var newDraft = NewTransactionDraft(today: .today())
    @State private var moving = false
    @State private var importingCSV = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())
    @State private var pendingDelete: ForecastLine?
    @State private var problem: ListProblem?
    @State private var comparing = false
    /// The Undo bar after a line is marked paid from the list (#315), and
    /// the count that gives the success haptic.
    @State private var undoOffer: UndoOffer?
    @State private var paidCount = 0
    @State private var debugMenuLine: ForecastLine?

    private var shownMonth: YearMonth { YearMonth(monthText) ?? YearMonth(.today()) }
    private var account: Account? {
        guard let list = accounts.value else { return nil }
        return list.first { $0.id == accountId } ?? list.first
    }
    private var editable: Bool { account.map(model.canEdit) ?? false }
    private var editableAccounts: [Account] { (accounts.value ?? []).filter(model.canEdit) }

    /// A line as something to drag onto a Calendar day (#308): a one-off
    /// not yet paid, on an account this person may change, not while the
    /// lock has the demo in front.
    private func drag(_ line: ForecastLine) -> LineDrag? {
        guard let account else { return nil }
        return LineDrag(line: line, accountId: account.id,
                        canChange: LineDrag.allowed(canEdit: editable, lockedInDemo: settings.lockedInDemo))
    }

    var body: some View {
        PageStack {
            content
                // A bank's CSV dropped here imports to this account (#308), where + offers Import a CSV.
                .csvDropTarget(enabled: editable, account: account?.id) { await loadMonth() }
                .keptBar(kept)
                .sensoryFeedback(.success, trigger: paidCount)
                .background(PageBackground().ignoresSafeArea())
                // The large title on the phone; a glass capsule on the open Duo (#341).
                .pageTitle("Forecast")
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
        .csvImporter(isPresented: $importingCSV, account: account?.id) { await loadMonth() }
        .pageShortcuts(.forecast, shortcuts)
        // Debug only: `WW_DEBUG_CONTEXT=1` shows the first line's long-press menu as a sheet (#307).
        .sheet(item: $debugMenuLine) { line in
            RowMenuSheet(title: line.description,
                         actions: RowAction.forLine(canChange: editable && line.canEdit(onEditableAccount: true), isPaid: line.isPaid))
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
        .problemAlert($problem)
        .scopedToConnection($accountId, memo: $accountMemo)
        // The bar belongs to the account and month it was shown on, and goes
        // when the editor opens or the connection changes.
        .onChange(of: accountId) { old, _ in
            undoOffer = nil
            if old != 0 { filterText = "" }   // the first pick (0 → an account) isn't a change of account
        }
        .onChange(of: monthText) { undoOffer = nil }
        .onChange(of: model.generation) { undoOffer = nil; filterText = "" }
        .onChange(of: open != nil) { _, isOpen in if isOpen { undoOffer = nil } }
        // A line dragged onto a Calendar day, in this window or another (#308).
        .onChange(of: model.lastLineMove) { _, move in
            if let move, open?.line.transactionId == move.transactionId { open = nil }
            Task { await loadMonth() }
        }
        .task(id: model.generation) { await loadAll() }
        .task(id: "\(accountId)/\(monthText)") { await loadMonth() }
        // An account chosen in Search (#112): this month of it.
        .onChange(of: model.forecastRequest, initial: true) { _, request in
            guard let request else { return }
            accountId = request
            follower.picked(request, on: .forecast, following: settings.pagesFollowAccount)
            monthText = ""
            confirming = model.forecastToConfirm
            model.forecastToConfirm = false
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
                    filterBlock(data)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                Section {
                    if showingConfirm {
                        confirmRows(data)
                    } else {
                        if data.rows.isEmpty { emptyMonth } else if shown(data).isEmpty { emptyFilter }
                        ForEach(shown(data)) { line in
                            Button { openLine(line) } label: { LineCard(line: line, today: .today()) }
                                .buttonStyle(.plain)
                                .pointerCard()
                                .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                                     onDelete: { pendingDelete = $0 }))
                                .lineDrag(drag(line))
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
        // On the list's own half when the Duo is open, so the bar never crosses the fold.
        .undoBar($undoOffer)
    }

    /// The open Duo: chart and table on the left, the editor or the
    /// month's summary on the right, either side of the fold with nothing to
    /// read or tap on it. Half open like a small laptop (#90), the fold runs
    /// across: the chart and table above it, the editor below, on the half
    /// that lies on the table. `FoldLayout` (#304) does the arranging; either
    /// half pulls to refresh.
    private func twoPanes(_ data: ForecastMonth) -> some View {
        FoldLayout { edges in
            listPane(data, edges: edges)
        } trailing: { edges in
            sidePane(data, edges: edges)
        }
        .refreshable { await loadMonth() }
    }

    private func listPane(_ data: ForecastMonth, edges: FoldPanes.Edges) -> some View {
        List {
            Group {
                Section {
                    header(data)
                    if !showingConfirm {
                        ForecastChart(data: data, month: shownMonth)
                            .card()
                    }
                    confirmSwitch(data)
                    filterBlock(data)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: edges.leading, bottom: 4, trailing: edges.trailing))
                Section {
                    if showingConfirm {
                        confirmRows(data)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: edges.leading, bottom: 5, trailing: edges.trailing))
                    } else {
                        if typeSize.isAccessibilitySize {
                            if data.rows.isEmpty { emptyMonth } else if shown(data).isEmpty { emptyFilter }
                            ForEach(shown(data)) { line in
                                Button { openLine(line) } label: {
                                    LineCard(line: line, today: .today())
                                        .overlay {
                                            if open?.id == line.id {
                                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                    .strokeBorder(Palette.accent, lineWidth: 2.5)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .pointerCard()
                                .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                                     onDelete: { pendingDelete = $0 }))
                                .lineDrag(drag(line))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: edges.leading, bottom: 5, trailing: edges.trailing))
                            }
                        } else {
                            if data.rows.isEmpty { emptyMonth } else if shown(data).isEmpty { emptyFilter } else { LineTableHeader().listRowSeparator(.hidden) }
                            ForEach(shown(data)) { line in
                                Button { openLine(line) } label: {
                                    LineTableRow(line: line, selected: open?.id == line.id)
                                }
                                .buttonStyle(.plain)
                                .pointerRow()
                                .modifier(LineSwipes(line: line, editable: editable, onPaid: markPaid, onEdit: openLine,
                                                     onDelete: { pendingDelete = $0 }))
                                .lineDrag(drag(line))
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: edges.leading, bottom: 0, trailing: edges.trailing))
            }
            .listRowBackground(Palette.row)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // On the list's own half when the Duo is open, so the bar never crosses the fold.
        .undoBar($undoOffer)
    }

    @ViewBuilder
    private func sidePane(_ data: ForecastMonth, edges: FoldPanes.Edges) -> some View {
        Group {
            if let binding = Binding($open) {
                LineEditor(open: binding, categories: categories, embedded: true, onClose: { open = nil }) { await loadMonth() }
                    .id(binding.wrappedValue.id)
            } else {
                ScrollView {
                    MonthSummaryView(month: shownMonth, data: data, onOpen: openLine)
                        .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
                }
            }
        }
    }

    private func header(_ data: ForecastMonth) -> some View {
        MonthHeader(accounts: accounts.value ?? [], account: account, month: shownMonth, data: data,
                    onSwitch: switchAccount, onMove: move, onJump: jump)
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

    // MARK: - Category and tag filter (#327)

    /// The chosen filter, when this month still has it: a category or tag
    /// that isn't in the month shows as All (and is forgotten once the month loads).
    private func activeFilter(_ data: ForecastMonth) -> ForecastFilter? {
        guard let chosen = ForecastFilter(rawValue: filterText),
              ForecastFilter.chips(for: data.rows).contains(where: { $0.filter == chosen }) else { return nil }
        return chosen
    }

    /// The month's lines under the chosen filter (every line on All).
    private func shown(_ data: ForecastMonth) -> [ForecastLine] {
        ForecastFilter.apply(activeFilter(data), to: data.rows)
    }

    /// The row of chips, and under it the small total of what the list
    /// shows; nothing when the month has no categories or tags.
    @ViewBuilder
    private func filterBlock(_ data: ForecastMonth) -> some View {
        let chips = ForecastFilter.chips(for: data.rows)
        if !chips.isEmpty {
            let active = activeFilter(data)
            ForecastFilterChips(chips: chips, selected: active) { filterText = $0?.rawValue ?? "" }
            if let active {
                let lines = showingConfirm
                    ? ForecastFilter.apply(active, to: data.toConfirm(today: .today()))
                    : active.apply(to: data.rows)
                Text(active.summary(of: lines))
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Filter: " + active.summary(of: lines))
            }
        }
    }

    private var emptyFilter: some View {
        Text("No lines here for this filter.")
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    @ViewBuilder
    private func confirmRows(_ data: ForecastMonth) -> some View {
        let lines = ForecastFilter.apply(activeFilter(data), to: data.toConfirm(today: .today()))
        if lines.isEmpty, activeFilter(data) != nil {
            emptyFilter
        } else if lines.isEmpty {
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
            offerUndo(line, account: account.id)
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
            AddMenu(addTitle: "Add transaction", canMove: editableAccounts.count > 1, onAdd: startAdding, onMove: {
                moveDraft = MoveMoneyDraft(today: .today(), from: account?.id)
                moving = true
            }, onImport: { importingCSV = true })
        }
    }

    // MARK: - Actions

    /// The keyboard (#307): ⌘N, ⌘R, ⌘[ and ⌘] for the months, ⌘T.
    private var shortcuts: [ShortcutHandler] {
        [ShortcutHandler(.addTransaction, enabled: editable && account != nil) { startAdding() },
         ShortcutHandler(.refresh) { Task { await loadMonth() } },
         ShortcutHandler(.previousMonth) { move(-1) },
         ShortcutHandler(.nextMonth) { move(1) },
         ShortcutHandler(.thisMonth, enabled: shownMonth != YearMonth(.today())) { jump(to: YearMonth(.today())) }]
    }

    private func startAdding() {
        newDraft = NewTransactionDraft(today: shownMonth.contains(.today()) ? .today() : shownMonth.start)
        adding = true
    }

    private func openLine(_ line: ForecastLine) {
        guard let account else { return }
        open = OpenLine(line, account: account, editable: editable)
    }

    private func move(_ by: Int) {
        open = nil
        monthText = (by < 0 ? shownMonth.previous : shownMonth.next).description
    }

    private func jump(to month: YearMonth) {
        open = nil
        monthText = month == YearMonth(.today()) ? "" : month.description
    }

    private func switchAccount(_ id: Int) {
        open = nil
        accountId = id
        follower.picked(id, on: .forecast, following: settings.pagesFollowAccount)
    }

    private func markPaid(_ line: ForecastLine) {
        guard let account else { return }
        Task {
            if await change(line, { try await $0.save(line, draft: .paidAsPlanned(line, today: .today()), account: account.id) }) {
                settings.start.done.insert(.markPaid)  // Getting started (#177)
                offerUndo(line, account: account.id)
            }
        }
    }

    /// The success haptic and the Undo bar for a line just marked paid; a
    /// later one replaces the bar.
    private func offerUndo(_ line: ForecastLine, account: Int) {
        paidCount += 1
        undoOffer = UndoOffer(message: "\(line.description) marked paid") { await undoPaid(line, account: account) }
    }

    /// Takes "paid" back the way the editor's Paid switch does: finds the
    /// line again in the reloaded month (a projected date is a transaction
    /// now) and saves it not paid, which keeps it at its planned amount with
    /// its notes and category. A failure shows the problem's alert.
    private func undoPaid(_ line: ForecastLine, account: Int) async -> Bool {
        guard let client = model.client else { return false }
        guard let paid = month.value?.reloaded(line) else {
            problem = .gone("\(line.description) isn't in this month any more, so it can't be undone here.")
            return false
        }
        var done = false
        do {
            try await client.save(paid, draft: .unpaid(paid, today: .today()), account: account)
            done = true
        } catch {
            problem = ListProblem(error)
        }
        await loadMonth()
        return done
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
            problem = ListProblem(error)
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
        // Debug only: `WW_DEBUG_FILTER=<category or tag name>` starts Forecast filtered by it (#327).
        if let name = AppModel.debugSetting("WW_DEBUG_FILTER"),
           let filter = ForecastFilter.named(name, in: month.value?.rows ?? []) { filterText = filter.rawValue }
        if let name = AppModel.debugSetting("WW_DEBUG_OPEN_LINE"),
           let line = month.value?.rows.first(where: { $0.description == name }) { openLine(line) }
        // Debug only: `WW_DEBUG_ADD_NAME=<text>` opens Add transaction with that typed as the name, so the
        // suggestions and the tag rule note show (#325).
        if let typed = AppModel.debugSetting("WW_DEBUG_ADD_NAME"), editable { startAdding(); newDraft.name = typed }
        // Debug only: `WW_DEBUG_CHANGE_TRANSFER=1` opens Change transfer on the month's first transfer (#324).
        if AppModel.debugSetting("WW_DEBUG_CHANGE_TRANSFER") == "1", let line = month.value?.rows.first(where: \.isTransfer) { openLine(line) }
        if AppModel.debugSetting("WW_DEBUG_CONTEXT") == "1", let first = month.value?.rows.first { debugMenuLine = first }
        // Debug only: `WW_DEBUG_UNDO=<line name>` shows the Undo bar for that line, saving nothing (#315).
        if let name = AppModel.debugSetting("WW_DEBUG_UNDO"), month.value?.rows.contains(where: { $0.description == name }) == true {
            undoOffer = UndoOffer(message: "\(name) marked paid", undo: { false }, stays: true)
        }
    }

    private func loadMonth() async {
        guard let client = model.client(kept), let account else { return }
        do {
            let loaded = try await client.forecast(account: account.id, month: shownMonth)
            month = .loaded(loaded)
            // A month without the chosen category or tag goes back to All; one that has it keeps it.
            if activeFilter(loaded) == nil, !filterText.isEmpty { filterText = "" }
        } catch {
            month = .failed(error)
            kept.clear()
        }
    }
}

// MARK: - Filter chips (#327)

/// "All", then the month's categories and tags as capsules in a row that
/// scrolls sideways; the chosen one in the accent. Chips grow with the text
/// size and the row keeps scrolling.
struct ForecastFilterChips: View {
    let chips: [ForecastFilter.Chip]
    let selected: ForecastFilter?
    let onChoose: (ForecastFilter?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", dot: nil, on: selected == nil) { onChoose(nil) }
                ForEach(chips) { item in
                    chip(item.filter.name, dot: item.filter.kind == .tag ? tagDot(item) : nil, on: selected == item.filter) {
                        onChoose(item.filter)
                    }
                    .accessibilityLabel("\(item.filter.kind == .tag ? "Tag" : "Category") \(item.filter.name), \(item.count) \(item.count == 1 ? "line" : "lines")")
                }
            }
            .padding(.vertical, 2)
        }
        // Clipped to the row, so chips never run out beside the tab bar.
    }

    private func tagDot(_ item: ForecastFilter.Chip) -> Color {
        Palette.category(item.color, name: item.filter.name)
    }

    private func chip(_ title: String, dot: Color?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? Palette.accent : Color.clear, in: .capsule)
            .background(.quaternary, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Swipes

/// Swipe right to mark a line paid as planned, or to edit it (#160: a paid
/// line offers Edit, not Undo paid; undoing is the editor's Paid switch);
/// swipe left to delete. Only on lines this person may change.
struct LineSwipes: ViewModifier {
    /// This person may change the line: an account they can edit, and not a transfer.
    let canChange: Bool
    let isPaid: Bool
    let onPaid: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    init(line: ForecastLine, editable: Bool, onPaid: @escaping (ForecastLine) -> Void,
         onEdit: @escaping (ForecastLine) -> Void, onDelete: @escaping (ForecastLine) -> Void) {
        canChange = editable && line.canEdit(onEditableAccount: true)
        isPaid = line.isPaid
        self.onPaid = { onPaid(line) }
        self.onEdit = { onEdit(line) }
        self.onDelete = { onDelete(line) }
    }

    /// A line on the Calendar (#305): the same swipes, on the same lines.
    init(event: CalendarEvent, editable: Bool, onPaid: @escaping (CalendarEvent) -> Void,
         onEdit: @escaping (CalendarEvent) -> Void, onDelete: @escaping (CalendarEvent) -> Void) {
        canChange = editable && !event.isTransfer
        isPaid = event.isPaid
        self.onPaid = { onPaid(event) }
        self.onEdit = { onEdit(event) }
        self.onDelete = { onDelete(event) }
    }

    func body(content: Content) -> some View {
        if canChange {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isPaid {
                        Button("Paid", systemImage: "checkmark.circle", action: onPaid)
                            .tint(Palette.good)
                    }
                    Button("Edit", systemImage: "pencil", action: onEdit)
                        .tint(Palette.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                }
                // The same actions on a long-press or a right-click (#307).
                .modifier(RowMenu(actions: RowAction.forLine(canChange: true, isPaid: isPaid)) { action in
                    switch action {
                    case .markPaid: onPaid()
                    case .edit: onEdit()
                    case .delete: onDelete()
                    default: break
                    }
                })
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
    let onJump: (YearMonth) -> Void

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
            MonthBar(month: month, onMove: onMove, onPick: onJump)
            // The balance today leads; the month's other figures sit in one
            // strip under it, as the web draws it since 1.98.0 (#322).
            VStack(alignment: .leading, spacing: 2) {
                Caption("Today")
                Text(data.currentBalance.formatted)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.amount(data.currentBalance.isNegative))
                    .wholeFigure(defaultScale: 0.6)
                    // The same cap as the Dashboard's balance (#311).
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            .accessibilityElement(children: .combine)
            let low = data.lowest
            FitsAcross {
                HStack(alignment: .top, spacing: 12) {
                    stripFigure("Forecast end", data.forecastEndingBalance)
                    stripFigure("Actual end", data.actualEndingBalance)
                    stripFigure("Lowest", low.balance, on: low.date)
                }
                // Its full height, or the Lowest column (a line taller, with
                // its date) shrinks its figure to fit.
                .fixedSize(horizontal: false, vertical: true)
            } stacked: {
                // The larger text sizes: one to a row, the label over it (#311).
                VStack(alignment: .leading, spacing: 10) {
                    stripFigure("Forecast end", data.forecastEndingBalance)
                    stripFigure("Actual end", data.actualEndingBalance)
                    stripFigure("Lowest", low.balance, on: low.date)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .card()
    }

    /// One of the strip's figures: its label, the amount, and the day under
    /// it when it has one (the lowest point's).
    private func stripFigure(_ label: String, _ value: Money, on day: LocalDay? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(label).fixedSize(horizontal: false, vertical: true)
            Text(value.formatted)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
                .wholeFigure(defaultScale: 0.7)
            if let day {
                Text(day.short).font(.caption2).foregroundStyle(.secondary)
            }
        }
        // From zero, so the three columns share the strip equally.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
            FitsAcross {
                HStack(alignment: .firstTextBaseline) {
                    PaidMark(line: line, today: today)
                    Text(line.description).font(.headline).lineLimit(2)
                    Spacer(minLength: 8)
                    amount
                }
            } stacked: {
                // The larger text sizes: the name, then the amount under it (#311).
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        PaidMark(line: line, today: today)
                        Text(line.description).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                    amount
                }
            }
            FitsAcross {
                HStack(spacing: 6) {
                    Text(dates).font(.subheadline).foregroundStyle(.secondary)
                    if let category = line.category {
                        Text("·").foregroundStyle(.tertiary)
                        Text(category).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    marks
                }
            } stacked: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dates).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let category = line.category {
                        Text(category).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if line.isTransfer || line.bankUnmatched == true { HStack(spacing: 6) { marks } }
                }
            }
            TagChips(tags: line.tags ?? [])
            FigureRow(spacing: 14) {
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

    private var amount: some View {
        Text(line.amount.formatted)
            .font(.headline.monospacedDigit())
            .foregroundStyle(line.amount.isNegative ? Palette.bad : Palette.good)
            .wholeFigure()
    }

    @ViewBuilder
    private var marks: some View {
        if line.isTransfer {
            Text("Transfer").font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        if line.bankUnmatched == true { UnmatchedPill() }
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
                .wholeFigure()
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
struct LineTableHeader: View {
    // The columns' widths grow with the text size (#311); at the
    // accessibility sizes the pane shows cards instead (`listPane`).
    @ScaledMetric(relativeTo: .footnote) private var dateWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .footnote) private var moneyWidth: CGFloat = 80

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Text("Day").frame(width: dateWidth, alignment: .leading)
            Text("Name\nCategory").frame(maxWidth: .infinity, alignment: .leading)
            Text("Forecast\nActual").frame(width: moneyWidth, alignment: .trailing)
            Text("Balance\nDifference").frame(width: moneyWidth, alignment: .trailing)
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
    // The columns' widths grow with the text size (#311); at the
    // accessibility sizes the pane shows cards instead (`listPane`).
    @ScaledMetric(relativeTo: .footnote) private var dateWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .footnote) private var moneyWidth: CGFloat = 80

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The table is always one month, so the day is enough.
            Text(line.plannedDate.map { String($0.day) } ?? "").frame(width: dateWidth, alignment: .leading)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    PaidMark(line: line, today: .today()).font(.caption)
                    Text(line.description).lineLimit(2)
                    if line.bankUnmatched == true { UnmatchedPill() }
                }
                HStack(spacing: 4) {
                    Text(line.category ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    TagChips(tags: line.tags ?? [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                money(line.forecastAmount, colored: false)
                money(line.isPaid ? line.actualAmount : nil, colored: false).font(.caption2)
            }
            .frame(width: moneyWidth, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                money(line.actualBalance, colored: false)
                money(line.differsFromPlan ? line.diffAmount : nil, colored: true, blank: true).font(.caption2)
            }
            .frame(width: moneyWidth, alignment: .trailing)
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
            .wholeFigure(defaultScale: 0.7)
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
    /// The dates' column grows with the text size (#311).
    @ScaledMetric(relativeTo: .subheadline) private var dateWidth: CGFloat = 50
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let today = LocalDay.today()
        let s = ForecastSummary(data, today: today)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Caption("\(month.label) against plan")
                Group {
                    if typeSize <= .large {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("")
                                Text("So far").font(.caption).foregroundStyle(.secondary)
                                Text("Planned").font(.caption).foregroundStyle(.secondary)
                            }
                            row("Income", s.incomeSoFar, s.incomePlanned, Palette.good)
                            row("Spending", s.spendingSoFar, s.spendingPlanned, Palette.bad)
                        }
                    } else {
                        // Past Large: each row's name, then its two figures
                        // labelled, one to a line (#311).
                        VStack(alignment: .leading, spacing: 12) {
                            stackedRow("Income", s.incomeSoFar, s.incomePlanned, Palette.good)
                            stackedRow("Spending", s.spendingSoFar, s.spendingPlanned, Palette.bad)
                        }
                    }
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

            FigureRow(spacing: 14) {
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

            Text("Tap a line to mark it paid or change it.")
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

    private func stackedRow(_ label: String, _ soFar: Money, _ planned: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            LabeledLine(label: "So far") {
                Text(soFar.formatted).monospacedDigit().foregroundStyle(color).wholeFigure()
            }
            LabeledLine(label: "Planned") {
                Text(planned.formatted).monospacedDigit().foregroundStyle(.secondary).wholeFigure()
            }
        }
    }

    private func extreme(_ label: String, _ value: Money, _ day: LocalDay?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(label)
            Text(value.formatted).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
                .wholeFigure(defaultScale: 0.7)
            Text(day?.short ?? "Start of month").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func lineButton(_ line: ForecastLine, showingDiff: Bool = false) -> some View {
        Button { onOpen(line) } label: {
            FitsAcross {
                HStack {
                    Text(line.plannedDate?.short ?? "").foregroundStyle(.secondary).frame(width: dateWidth, alignment: .leading)
                    Text(line.description).lineLimit(1)
                    Spacer()
                    lineFigure(line, showingDiff: showingDiff)
                }
            } stacked: {
                // The larger text sizes: the name, then its date and figure (#311).
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.description).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(line.plannedDate?.short ?? "").foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        lineFigure(line, showingDiff: showingDiff)
                    }
                }
            }
            .font(.subheadline.monospacedDigit())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func lineFigure(_ line: ForecastLine, showingDiff: Bool) -> some View {
        if showingDiff, let diff = line.diffAmount, diff != .zero {
            Text(diff.formatted).foregroundStyle(diff.isNegative ? Palette.bad : Palette.good).wholeFigure()
        } else if showingDiff {
            Text("paid \(line.actualDate?.short ?? "")").foregroundStyle(.secondary).wholeFigure()
        } else {
            Text(line.plannedAmount.formatted).foregroundStyle(Palette.amount(line.plannedAmount.isNegative)).wholeFigure()
        }
    }
}
