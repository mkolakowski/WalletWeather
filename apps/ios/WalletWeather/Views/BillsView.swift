import SwiftUI
import WalletWeatherKit

/// Bills & income: every repeating bill and paycheck on all accounts or
/// one, with the monthly totals, each with its amount, how often and its
/// next date. Tap one to change it; swipe right to skip a date, left to end
/// it. + adds a bill or moves money. On the open Duo the list stays on the
/// left and the right half shows the tapped item, or the totals and what's
/// due in the next week until one is tapped.
struct BillsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 0 for all accounts.
    @SceneStorage("bills.account") private var accountId = 0
    @SceneStorage("bills.ended") private var showEnded = false

    @State private var accounts: [Account] = []
    @State private var list: Loadable<RecurringList> = .loading
    @State private var kept = KeptTracker()
    @State private var categories: [TransactionCategory] = []
    @State private var open: OpenBill?
    @State private var moving = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())
    @State private var skipping: RecurringItem?
    @State private var ending: RecurringItem?
    @State private var problem: String?

    private var editableAccounts: [Account] { accounts.filter(model.canEdit) }
    private var account: Account? { accounts.first { $0.id == accountId } }

    var body: some View {
        PageStack {
            content
                .keptBar(kept)
                .background(PageBackground().ignoresSafeArea())
                .navigationTitle("Bills & income")
                .toolbar { NewWindowItem(place: .bills) }
                .toolbar {
                    if !editableAccounts.isEmpty {
                        AddMenu(addTitle: "Add bill or income", canMove: editableAccounts.count > 1,
                                onAdd: addBill, onMove: {
                                    moveDraft = MoveMoneyDraft(today: .today(), from: account?.id)
                                    moving = true
                                })
                    }
                }
        }
        .billEditorSheet($open, categories: categories) { await load() }
        .sheet(isPresented: $moving) {
            MoveMoneySheet(accounts: editableAccounts, draft: $moveDraft) { await load() }
        }
        .sheet(item: $skipping) { item in
            SkipDateSheet(item: item) { await load() }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $ending) { item in
            EndBillSheet(item: item) { await load() }
                .presentationDetents([.medium])
        }
        .task(id: model.generation) { await loadAll() }
        .task(id: "\(accountId)/\(showEnded)") { await load() }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        switch list {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            ProblemView(error: error) { Task { await loadAll() } }
        case let .loaded(data):
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    listView(data).frame(maxWidth: .infinity)
                    Group {
                        if let binding = Binding($open) {
                            BillEditor(open: binding, accounts: editableAccounts, categories: categories, embedded: true,
                                       onClose: { open = nil }, onSkip: { skipping = $0 }, onEnd: { ending = $0 }) { await load() }
                                .id(binding.wrappedValue.id)
                        } else {
                            ScrollView {
                                BillsSummaryView(data: data, showEnded: showEnded, onOpen: openItem)
                                    .padding(.leading, 28).padding(.trailing, 16).padding(.bottom, 24)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                listView(data)
            }
        }
    }

    private func listView(_ data: RecurringList) -> some View {
        let trailing: CGFloat = sizeClass == .regular ? 28 : 16
        return List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        accountPicker
                        Picker("Show", selection: $showEnded) {
                            Text("Current").tag(false)
                            Text("Ended").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if !showEnded { BillTotalsGrid(totals: data.totals) }
                    }
                    .card()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: trailing))

                Section {
                    if data.items.isEmpty {
                        Text(showEnded ? "Nothing has ended." : "No bills or income yet. Tap + to add one.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(data.items) { item in
                        Button { openItem(item) } label: {
                            BillCard(item: item, showAccount: account == nil, selected: open?.item?.id == item.id)
                        }
                        .buttonStyle(.plain)
                        .modifier(BillSwipes(item: item, editable: canEdit(item),
                                             onSkip: { skipping = $0 }, onEnd: { ending = $0 }))
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: trailing))
            }
            .listRowBackground(Palette.row)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    @ViewBuilder
    private var accountPicker: some View {
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
        } else if let only = accounts.first {
            Text(only.name).font(.title3.weight(.semibold))
        }
    }

    // MARK: - Actions

    private func canEdit(_ item: RecurringItem) -> Bool {
        item.canEdit && model.me.map { !$0.isReadOnly } == true
    }

    private func openItem(_ item: RecurringItem) {
        open = OpenBill(item: item, editable: canEdit(item))
    }

    private func addBill() {
        let target = account.flatMap { model.canEdit($0) ? $0 : nil } ?? editableAccounts.first
        open = OpenBill(newOn: target?.id)
    }

    // MARK: - Loading

    private func loadAll() async {
        guard let client = model.client(kept) else { return }
        do {
            accounts = try await client.accounts()
        } catch {
            list = .failed(error)
            kept.clear()
            return
        }
        if accountId != 0, !accounts.contains(where: { $0.id == accountId }) { accountId = 0 }
        categories = (try? await client.categories()) ?? []
        await load()
        if let name = AppModel.debugSetting("WW_DEBUG_OPEN_LINE"),
           let item = list.value?.items.first(where: { $0.description == name }) { openItem(item) }
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do {
            list = .loaded(try await client.recurring(account: accountId == 0 ? nil : accountId, ended: showEnded))
        } catch {
            list = .failed(error)
            kept.clear()
        }
    }
}

// MARK: - The totals

/// Bills, income and what's left, per month.
private struct BillTotalsGrid: View {
    let totals: RecurringList.Totals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow(alignment: .bottom) {
                Caption("Bills a month")
                Caption("Income a month")
                Caption("Left over")
            }
            GridRow {
                figure(Money(-totals.billsMonthly.amount), color: Palette.bad)
                figure(totals.incomeMonthly, color: Palette.good)
                figure(totals.netMonthly, color: Palette.amount(totals.netMonthly.isNegative))
            }
        }
    }

    private func figure(_ value: Money, color: Color) -> some View {
        Text(value.formatted)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .minimumScaleFactor(0.7).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The right half of the open Duo before an item is tapped: the totals
/// with their counts, and what's due in the next seven days.
struct BillsSummaryView: View {
    let data: RecurringList
    let showEnded: Bool
    let onOpen: (RecurringItem) -> Void

    var body: some View {
        let today = LocalDay.today()
        let weekOut = LocalDay.today(now: today.date.addingTimeInterval(7 * 86_400))
        let soon = data.items.filter { item in item.nextDate.map { $0 <= weekOut } ?? false }
            .sorted { ($0.nextDate ?? today) < ($1.nextDate ?? today) }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Caption("Each month")
                row("\(data.totals.billsCount) bill\(data.totals.billsCount == 1 ? "" : "s")",
                    Money(-data.totals.billsMonthly.amount), Palette.bad)
                row("\(data.totals.incomeCount) paycheck\(data.totals.incomeCount == 1 ? "" : "s") and income",
                    data.totals.incomeMonthly, Palette.good)
                Divider()
                row("Left over", data.totals.netMonthly, Palette.amount(data.totals.netMonthly.isNegative))
                Text("Weekly and every-2-weeks items are counted as a month's worth.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card()
            if !showEnded {
                VStack(alignment: .leading, spacing: 8) {
                    Caption("Due in the next 7 days")
                    if soon.isEmpty {
                        Text("Nothing due this week.").font(.callout)
                    }
                    ForEach(soon) { item in
                        Button { onOpen(item) } label: {
                            HStack {
                                Text(item.nextDate.map { $0 == today ? "Today" : $0.short } ?? "")
                                    .foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                                Text(item.description).lineLimit(1)
                                Spacer()
                                Text(item.amount.formatted)
                                    .foregroundStyle(item.isIncome ? Palette.good : Palette.bad)
                            }
                            .font(.subheadline.monospacedDigit())
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            Text("Tap a bill or paycheck on the left to change it, skip a date or end it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: Money, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted).monospacedDigit().foregroundStyle(color)
        }
        .font(.callout)
    }
}

// MARK: - A bill

/// One bill or paycheck: name and amount, how often, the next date, and
/// the account and category.
struct BillCard: View {
    let item: RecurringItem
    let showAccount: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.isIncome ? "arrow.down.left.circle.fill" : "arrow.up.right.circle")
                    .foregroundStyle(item.isIncome ? Palette.good : .secondary)
                    .accessibilityLabel(item.isIncome ? "Income" : "Bill")
                Text(item.description).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(item.amount.formatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(item.isIncome ? Palette.good : Palette.bad)
            }
            Text(item.howOften).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(nextText).font(.subheadline.weight(.medium))
                    .foregroundStyle(item.expired ? .secondary : .primary)
                let detail = [showAccount ? item.accountName : nil, item.categoryName].compactMap { $0 }
                if !detail.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(detail.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(selected ? 2 : 0)
        .card()
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.accent, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }

    private var nextText: String {
        if item.expired, let end = item.endDate { return "Ended \(end.short)" }
        guard let next = item.nextDate else { return item.active ? "No dates ahead" : "Switched off" }
        if next == .today() { return "Next: today" }
        return "Next: \(next.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }
}

/// Swipe right to skip a date, left to end it. Only on items this person
/// may change, and not on ones that have ended.
struct BillSwipes: ViewModifier {
    let item: RecurringItem
    let editable: Bool
    let onSkip: (RecurringItem) -> Void
    let onEnd: (RecurringItem) -> Void

    func body(content: Content) -> some View {
        if editable && !item.expired {
            content
                .swipeActions(edge: .leading) {
                    if !item.nextDates.isEmpty {
                        Button("Skip a date", systemImage: "forward.end") { onSkip(item) }.tint(Palette.warn)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("End", systemImage: "stop.circle") { onEnd(item) }.tint(Palette.bad)
                }
        } else {
            content
        }
    }
}

// MARK: - Skip a date, end it

/// Skip once: the next six dates, the next one first (decided 2026-11-15).
struct SkipDateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: RecurringItem
    let onSkipped: () async -> Void

    @State private var confirm: LocalDay?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        ForEach(item.nextDates, id: \.self) { day in
                            Button { confirm = day } label: {
                                HStack {
                                    Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                    Spacer()
                                    if day == item.nextDate { Text("Next").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } footer: {
                        Text("Only that date is skipped; \(item.description) keeps its other dates. Skipped dates can be restored in the web app's Bills & income.")
                    }
                }
                .listRowBackground(Palette.row)
            }
            .navigationTitle("Skip a date of \(item.description)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
            }
            .confirmationDialog(confirm.map { "Skip \(item.description) on \($0.short)?" } ?? "",
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                titleVisibility: .visible, presenting: confirm) { day in
                Button("Skip \(day.short)", role: .destructive) { Task { await skip(day) } }
            }
            .alert("Couldn't skip it", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
        }
    }

    private func skip(_ day: LocalDay) async {
        guard let client = model.client else { return }
        do {
            try await client.skip(item, on: day)
        } catch {
            problem = AppModel.describe(error)
            return
        }
        await onSkipped()
        dismiss()
    }
}

/// End: the last date it runs (today by default); after that it stops
/// and moves to the ended list (decided 2026-11-15).
struct EndBillSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: RecurringItem
    let onEnded: () async -> Void

    @State private var last = LocalDay.today()
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        DatePicker("Last date", selection: Binding(get: { last.date }, set: { last = LocalDay.today(now: $0) }),
                                   displayedComponents: .date)
                    } footer: {
                        Text("\(item.description) is projected up to this date and no further. It moves to Ended the day after.")
                    }
                }
                .listRowBackground(Palette.row)
            }
            .navigationTitle("End \(item.description)")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End") { Task { await end() } }.buttonStyle(.glassProminent)
                }
            }
            .alert("Couldn't end it", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
        }
    }

    private func end() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await client.updateRecurring(item.id, RecurringBody(ending: item, after: last))
        } catch {
            problem = AppModel.describe(error)
            return
        }
        await onEnded()
        dismiss()
    }
}

// MARK: - The editor

/// A bill open in the editor, kept by the page so the Duo closing mid-edit
/// keeps what was typed. `item` is nil for a new one.
struct OpenBill: Identifiable, Equatable {
    let item: RecurringItem?
    let editable: Bool
    var draft: BillDraft
    var accountId: Int?
    var id: String { item.map { "b\($0.id)" } ?? "new" }

    init(item: RecurringItem, editable: Bool, today: LocalDay = .today()) {
        self.item = item
        self.editable = editable
        draft = BillDraft(item, today: today)
        accountId = item.accountId
    }

    init(newOn account: Int?, today: LocalDay = .today()) {
        item = nil
        editable = true
        draft = BillDraft(today: today)
        accountId = account
    }
}

extension View {
    /// A sheet on a compact width; on the open Duo the page shows the
    /// editor in its right half instead, as Forecast does.
    func billEditorSheet(_ open: Binding<OpenBill?>, categories: [TransactionCategory],
                         onSaved: @escaping () async -> Void) -> some View {
        modifier(BillEditorSheet(open: open, categories: categories, onSaved: onSaved))
    }
}

private struct BillEditorSheet: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var open: OpenBill?
    let categories: [TransactionCategory]
    let onSaved: () async -> Void
    @State private var accounts: [Account] = []
    @State private var skipping: RecurringItem?
    @State private var ending: RecurringItem?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { open != nil && sizeClass != .regular },
                set: { if !$0 && sizeClass != .regular { open = nil } })) {
                if let binding = Binding($open) {
                    BillEditor(open: binding, accounts: accounts, categories: categories,
                               onClose: { open = nil },
                               onSkip: { item in open = nil; skipping = item },
                               onEnd: { item in open = nil; ending = item }, onSaved: onSaved)
                }
            }
            .sheet(item: $skipping) { SkipDateSheet(item: $0, onSkipped: onSaved).presentationDetents([.medium, .large]) }
            .sheet(item: $ending) { EndBillSheet(item: $0, onEnded: onSaved).presentationDetents([.medium]) }
            .task(id: model.generation) {
                accounts = ((try? await model.client?.accounts()) ?? []).filter(model.canEdit)
            }
    }
}

/// Add or change a bill or paycheck: Spending or Income, the amount and
/// name, the account (for a new one), how often and from when, an end
/// date, category and notes. An existing one also offers Skip a date and
/// End. Read-only accounts show it with nothing to change.
struct BillEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var open: OpenBill
    let accounts: [Account]
    let categories: [TransactionCategory]
    var embedded = false
    let onClose: () -> Void
    let onSkip: (RecurringItem) -> Void
    let onEnd: (RecurringItem) -> Void
    let onSaved: () async -> Void

    @State private var saving = false
    @State private var problem: String?

    private var isNew: Bool { open.item == nil }
    private var title: String { isNew ? "New bill or income" : open.item?.description ?? "" }

    var body: some View {
        if embedded {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(open.editable ? "Cancel" : "Done", action: onClose).buttonStyle(.glass)
                    Spacer(minLength: 0)
                    Text(title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    if open.editable {
                        Button(isNew ? "Add" : "Save") { Task { await save() } }
                            .buttonStyle(.glassProminent).disabled(!canSave)
                    }
                }
                .padding(.leading, 28).padding(.trailing, 16).padding(.vertical, 8)
                form
            }
        } else {
            NavigationStack {
                form
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(open.editable ? "Cancel" : "Done", role: .cancel, action: onClose)
                        }
                        if open.editable {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(isNew ? "Add" : "Save") { Task { await save() } }
                                    .buttonStyle(.glassProminent).disabled(!canSave)
                            }
                        }
                    }
            }
        }
    }

    private var form: some View {
        Form {
            Group {
                if open.editable {
                    editingSections
                } else if let item = open.item {
                    readOnlySection(item)
                }
            }
            .listRowBackground(Palette.row)
        }
        .scrollContentBackground(.hidden)
        .background { if !embedded { PageBackground().ignoresSafeArea() } }
        .contentMargins(.leading, embedded ? 12 : 0, for: .scrollContent)
        .disabled(saving)
        .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    @ViewBuilder
    private var editingSections: some View {
        Section {
            Picker("Kind", selection: $open.draft.kind) {
                ForEach(NewTransactionDraft.Kind.allCases) { Text($0 == .spending ? "Bill" : "Income").tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            LabeledContent("Amount") {
                TextField("0.00", text: $open.draft.amountText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
            }
            TextField("Name", text: $open.draft.name).textInputAutocapitalization(.words)
            if isNew && accounts.count > 1 {
                Picker("Account", selection: $open.accountId) {
                    ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                }
            } else if let item = open.item {
                LabeledContent("Account", value: item.accountName)
            }
        }
        Section {
            Picker("Repeats", selection: $open.draft.frequency) {
                ForEach(Frequency.allCases) { Text($0.title).tag($0) }
            }
            if open.draft.frequency == .monthly {
                Picker("On the", selection: $open.draft.dayOfMonth) {
                    ForEach(1...31, id: \.self) { Text(ordinal($0)).tag($0) }
                }
                Toggle("Starts later", isOn: $open.draft.hasStart.animation())
                if open.draft.hasStart { dayPicker("Starts", \.start) }
            } else {
                dayPicker("First date", \.start)
            }
            Toggle("Ends", isOn: $open.draft.ends.animation())
            if open.draft.ends { dayPicker("Last date", \.endDate) }
        } footer: {
            if open.draft.frequency == .monthly && open.draft.dayOfMonth > 28 {
                Text("In shorter months it falls on the last day.")
            } else if open.draft.frequency != .monthly {
                Text("It repeats on the same weekday as the first date.")
            }
        }
        Section {
            Picker("Category", selection: $open.draft.categoryId) {
                Text("None").tag(Int?.none)
                ForEach(categoryChoices) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("Notes", text: $open.draft.notes, axis: .vertical).lineLimit(1...4)
        } footer: {
            if let problem = open.draft.problem, !open.draft.name.isEmpty || !open.draft.amountText.isEmpty {
                Text(problem).foregroundStyle(Palette.bad)
            }
        }
        if open.draft.matchDays != nil, open.draft.matchPercent != nil {
            Section {
                Stepper("Days either side: \(open.draft.matchDays ?? 5)",
                        value: Binding(get: { open.draft.matchDays ?? 5 }, set: { open.draft.matchDays = $0 }), in: 0...31)
                Stepper("Amount may differ by \(open.draft.matchPercent ?? 10)%",
                        value: Binding(get: { open.draft.matchPercent ?? 10 }, set: { open.draft.matchPercent = $0 }),
                        in: 0...100, step: 5)
            } header: {
                Text("Bank sync")
            } footer: {
                Text("A synced bank line that goes the same way and is this close to one of its dates pays it, instead of landing as a second line. Set both to 0 for an exact match.")
            }
        }
        if let item = open.item, !item.expired {
            Section {
                if !item.nextDates.isEmpty {
                    Button("Skip a date…") { onSkip(item) }
                }
                Button("End…", role: .destructive) { onEnd(item) }
                    .foregroundStyle(Palette.bad)  // kept red under a look's own text colour
            }
        }
    }

    private func readOnlySection(_ item: RecurringItem) -> some View {
        Section {
            LabeledContent("Amount", value: item.amount.formatted)
            LabeledContent("Repeats", value: item.howOften)
            if let next = item.nextDate { LabeledContent("Next", value: next.short) }
            if let end = item.endDate { LabeledContent(item.expired ? "Ended" : "Ends", value: end.short) }
            LabeledContent("Account", value: item.accountName)
            LabeledContent("Category", value: item.categoryName ?? "None")
            if let notes = item.notes, !notes.isEmpty { LabeledContent("Notes", value: notes) }
        } footer: {
            Text(model.me?.isReadOnly == true
                 ? "This phone signed in with a read-only token, so nothing can be changed here."
                 : "You can see this account but not change it.")
        }
    }

    private var canSave: Bool {
        guard open.draft.problem == nil, open.accountId != nil || !isNew else { return false }
        guard let item = open.item else { return true }
        return open.draft != BillDraft(item, today: .today())
    }

    /// Your categories, plus the item's own when it isn't one of them.
    private var categoryChoices: [TransactionCategory] {
        guard let id = open.item?.categoryId, !categories.contains(where: { $0.id == id }) else { return categories }
        return categories + [TransactionCategory(id: id, name: open.item?.categoryName ?? "Its category", color: nil)]
    }

    private func dayPicker(_ label: String, _ key: WritableKeyPath<BillDraft, LocalDay>) -> some View {
        DatePicker(label, selection: Binding(get: { open.draft[keyPath: key].date },
                                             set: { open.draft[keyPath: key] = LocalDay.today(now: $0) }),
                   displayedComponents: .date)
    }

    private func save() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            if let item = open.item {
                try await client.updateRecurring(item.id, RecurringBody(open.draft, active: item.active))
            } else if let account = open.accountId {
                try await client.addRecurring(open.draft, account: account)
            }
        } catch {
            problem = AppModel.describe(error)
            return
        }
        await onSaved()
        onClose()
    }
}
