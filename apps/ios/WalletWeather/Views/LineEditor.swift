import SwiftUI
import WalletWeatherKit

/// A line open in the editor, with what's been typed. It lives in the page
/// that opened it, not in the editor, so closing or opening the Duo
/// mid-edit keeps it: a sheet on the front screen, the right half open.
struct OpenLine: Identifiable, Equatable {
    let line: ForecastLine
    let account: Account
    let editable: Bool
    /// A transfer's lines can't be changed, but a person who can edit the
    /// account may delete the transfer (#246).
    let canDeleteTransfer: Bool
    var draft: LineDraft
    var id: String { line.id }

    init(_ line: ForecastLine, account: Account, editable: Bool, today: LocalDay = .today()) {
        self.line = line
        self.account = account
        self.editable = editable && line.canEdit(onEditableAccount: true)
        canDeleteTransfer = editable && line.isTransfer && line.transactionId != nil
        draft = LineDraft(line, today: today)
    }
}

extension View {
    /// On a compact width (any iPhone, the Duo closed) the open line is a
    /// sheet. On a regular width the page shows it in its right half
    /// instead, and the sheet steps aside without closing the line.
    func lineEditorSheet(_ open: Binding<OpenLine?>, categories: [TransactionCategory],
                         onSaved: @escaping () async -> Void) -> some View {
        modifier(LineEditorSheet(open: open, categories: categories, onSaved: onSaved))
    }
}

private struct LineEditorSheet: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var open: OpenLine?
    let categories: [TransactionCategory]
    let onSaved: () async -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { open != nil && sizeClass != .regular },
            // Only a swipe down on the front screen closes the line; the
            // sheet going away because the Duo opened keeps it.
            set: { if !$0 && sizeClass != .regular { open = nil } })) {
            if let binding = Binding($open) {
                LineEditor(open: binding, categories: categories, onClose: { open = nil }, onSaved: onSaved)
                    .presentationDetents([.large])
            }
        }
    }
}

/// The editor: mark the line paid with its real amount and date (or undo
/// that), change its category and notes, or delete it. On a read-only
/// account or token it shows the line and nothing to change.
struct LineEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var open: OpenLine
    let categories: [TransactionCategory]
    /// In the right half of the open Duo, inside the page's own navigation:
    /// the editor carries its own header row instead of a navigation bar.
    var embedded = false
    let onClose: () -> Void
    let onSaved: () async -> Void
    /// Embedded, how far it keeps from its pane's sides (`FoldLayout`, #304).
    @Environment(\.paneEdges) private var edges

    @State private var saving = false
    @State private var problem: String?
    @State private var confirmDelete = false
    /// Counts saves that went through, for the success haptic (#315).
    @State private var savedCount = 0

    private var line: ForecastLine { open.line }

    var body: some View {
        if embedded {
            VStack(spacing: 0) {
                paneBar
                form
            }
        } else {
            NavigationStack {
                form
                    .navigationTitle(line.description)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
            }
        }
    }

    private var paneBar: some View {
        HStack(spacing: 12) {
            Button(open.editable ? "Cancel" : "Done", action: onClose)
                .buttonStyle(.glass)
            Spacer(minLength: 0)
            Text(line.description).font(.headline).lineLimit(1)
            Spacer(minLength: 0)
            if open.editable {
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
        }
        .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.vertical, 8)
    }

    private func save() {
        Task { await run(buzz: true) { try await $0.save(line, draft: open.draft, account: open.account.id) } }
    }

    private var form: some View {
            Form {
                Group {
                    aboutSection
                    if open.editable {
                        paidSection
                        detailsSection
                        deleteSection
                    } else {
                        readOnlySection
                        if open.canDeleteTransfer { deleteSection }
                    }
                }
                .listRowBackground(Palette.row)
            }
            .scrollContentBackground(.hidden)
            .background { if !embedded { PageBackground().ignoresSafeArea() } }
            // Clear of the fold in the open Duo's pane; the usual margins in a
            // sheet (a zero here ran the rows into the screen's edge, #161).
            .contentMargins(.leading, embedded ? edges.formMargin : nil, for: .scrollContent)
            .disabled(saving)
            .sensoryFeedback(.success, trigger: savedCount)
            .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(line.isTransfer ? "Delete transfer" : line.isProjection ? "Delete this date" : "Delete", role: .destructive) {
                    Task { await run { try await $0.delete(line) } }
                }
            } message: {
                Text(deleteMessage)
            }
    }

    // MARK: - Sections

    /// A line you added (saved, not a transfer, not from a bill) on an
    /// account you may edit has its name, planned date and planned amount as
    /// fields (#316); every other line shows them as text.
    private var editsPlan: Bool { open.editable && open.draft.editsPlan }

    @ViewBuilder
    private var aboutSection: some View {
        if editsPlan { planFieldsSection } else { aboutTextSection }
    }

    private var planFieldsSection: some View {
        Section {
            LabeledContent("Account", value: open.account.name)
            LabeledContent("Name") {
                TextField("Name", text: $open.draft.name)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Name")
            }
            // An unpaid line's actual amount and date follow its plan until
            // they're changed, as they do when the line is first opened.
            DatePicker("Planned for", selection: Binding(get: { open.draft.plannedOn.date }, set: {
                open.draft.plannedOn = LocalDay.today(now: $0)
                if !open.draft.paid { open.draft.paidOn = LineDraft.paidOn(planned: open.draft.plannedOn, today: .today()) }
            }), displayedComponents: .date)
            LabeledContent("Planned amount") {
                TextField("0.00", text: Binding(get: { open.draft.plannedAmountText }, set: {
                    open.draft.plannedAmountText = $0
                    if !open.draft.paid { open.draft.amountText = $0 }
                }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .accessibilityLabel("Planned amount")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let problem = open.draft.planProblem {
                    Text(problem).foregroundStyle(Palette.bad)
                }
                Text("For a line you added. A date that comes from a repeating bill changes in its bill.")
            }
        }
    }

    private var aboutTextSection: some View {
        Section {
            LabeledContent("Account", value: open.account.name)
            if let planned = line.plannedDate {
                LabeledContent("Planned for", value: planned.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            }
            LabeledContent("Planned amount") {
                Text(line.plannedAmount.formatted).monospacedDigit()
                    .foregroundStyle(Palette.amount(line.plannedAmount.isNegative))
            }
            if line.recurringId != nil {
                Label(line.isProjection ? "From a repeating bill or paycheck" : "Saved from a repeating bill or paycheck",
                      systemImage: "repeat")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Paid, with the actual amount and date always showing (#161), filled in
    /// with the planned ones until changed. Changing either marks it paid;
    /// the switch undoes that.
    private var paidSection: some View {
        Section {
            Toggle("Paid", isOn: $open.draft.paid.animation())
            LabeledContent("Actual amount") {
                TextField("0.00", text: Binding(get: { open.draft.amountText }, set: {
                    open.draft.amountText = $0
                    open.draft.paid = true
                }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .accessibilityLabel("Actual amount")
            }
            DatePicker("Actual date", selection: Binding(get: { open.draft.paidOn.date }, set: {
                open.draft.paidOn = LocalDay.today(now: $0)
                open.draft.paid = true
            }), displayedComponents: .date)
        } footer: {
            if open.draft.paid, open.draft.planProblem == nil, let problem = open.draft.problem {
                Text(problem).foregroundStyle(Palette.bad)
            } else if !open.draft.paid && line.isPaid {
                Text("Saving marks it not paid: it goes back to its planned amount and date.")
            } else if !open.draft.paid {
                Text("Not paid yet. Changing the actual amount or date marks it paid.")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            Picker("Category", selection: $open.draft.categoryId) {
                Text("None").tag(Int?.none)
                ForEach(categoryChoices) { Text($0.name).tag(Optional($0.id)) }
            }
            TextField("Notes", text: $open.draft.notes, axis: .vertical)
                .lineLimit(1...4)
            TagsRow(selected: $open.draft.tagIds)
        } footer: {
            if open.draft.notes.count > 256 {
                Text("Notes can be up to 256 characters.").foregroundStyle(Palette.bad)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(line.isTransfer ? "Delete transfer" : line.isProjection ? "Delete this date" : "Delete transaction", role: .destructive) {
                confirmDelete = true
            }
            .foregroundStyle(Palette.bad)  // kept red under a look's own text colour
        }
    }

    private var readOnlySection: some View {
        Section {
            LabeledContent("Paid", value: line.isPaid ? "Yes" : "Not yet")
            if line.isPaid {
                LabeledContent("Real amount", value: line.amount.formatted)
                if let day = line.actualDate { LabeledContent("Paid on", value: day.short) }
            }
            LabeledContent("Category", value: line.category ?? "None")
            if let tags = line.tags, !tags.isEmpty { LabeledContent("Tags") { TagChips(tags: tags) } }
            if let notes = line.notes, !notes.isEmpty { LabeledContent("Notes", value: notes) }
        } footer: {
            Text(readOnlyReason)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(open.editable ? "Cancel" : "Done", role: .cancel, action: onClose)
        }
        if open.editable {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        open.draft.problem == nil && open.draft.notes.count <= 256 && open.draft != LineDraft(line, today: .today())
    }

    /// Your categories, plus the line's own when it isn't one of them (a
    /// line on an account someone shares with you carries theirs). Keeping
    /// it is allowed; choosing it for another line isn't.
    private var categoryChoices: [TransactionCategory] {
        guard let id = line.categoryId, !categories.contains(where: { $0.id == id }) else { return categories }
        return categories + [TransactionCategory(id: id, name: line.category ?? "This line's category", color: nil)]
    }

    private var readOnlyReason: String {
        if line.isTransfer {
            return model.isLocal ? "A transfer can't be changed on this iPhone. Delete it and move the money again."
                                 : open.canDeleteTransfer ? "Transfers between accounts can be deleted here and changed in the web app."
                                 : "Transfers between accounts are changed in the web app."
        }
        if model.me?.isReadOnly == true { return "This iPhone signed in with a read-only token, so nothing can be changed here." }
        return "You can see this account but not change it."
    }

    private var deleteTitle: String {
        if line.isTransfer { return "Delete this transfer?" }
        return line.isProjection ? "Delete the \(line.plannedDate?.short ?? "") date?" : "Delete this transaction?"
    }

    private var deleteMessage: String {
        if line.isTransfer { return "Both its lines, here and on the other account, are removed. This can't be undone." }
        if line.isProjection {
            return "The repeating bill or paycheck keeps its other dates; only this one is removed."
                + " You can bring deleted dates back from the bill's editor in Bills & income."
        }
        if line.recurringId != nil {
            return "This can't be undone. Its repeating bill or paycheck stays, but this date won't be projected again"
                + " (bring it back from the bill's editor in Bills & income)."
        }
        return "This can't be undone."
    }

    private func dayBinding(_ key: WritableKeyPath<LineDraft, LocalDay>) -> Binding<Date> {
        Binding(get: { open.draft[keyPath: key].date },
                set: { open.draft[keyPath: key] = LocalDay.today(now: $0) })
    }

    private func run(buzz: Bool = false, _ action: (APIClient) async throws -> Void) async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await action(client)
        } catch {
            problem = AppModel.describe(error)
            return
        }
        if buzz { savedCount += 1 }
        await onSaved()
        onClose()
    }
}

/// Add transaction: Spending or Income, the amount, a name, the date and
/// Paid (on, dated today, unless you turn it off to plan one ahead).
struct AddTransactionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account
    /// The accounts it may go on, when the page shows more than one (the
    /// Calendar on all accounts); empty to keep it on `account`.
    var accountChoices: [Account] = []
    let categories: [TransactionCategory]
    @Binding var draft: NewTransactionDraft
    let onSaved: () async -> Void

    @State private var saving = false
    @State private var problem: String?
    @State private var addedCount = 0
    @State private var chosenAccount: Int?
    @FocusState private var amountFocused: Bool

    private var target: Account { accountChoices.first { $0.id == chosenAccount } ?? account }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Picker("Kind", selection: $draft.kind) {
                            ForEach(NewTransactionDraft.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    Section {
                        if accountChoices.count > 1 {
                            Picker("Account", selection: Binding(get: { target.id }, set: { chosenAccount = $0 })) {
                                ForEach(accountChoices) { Text($0.name).tag($0.id) }
                            }
                        }
                        LabeledContent("Amount") {
                            TextField("0.00", text: $draft.amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($amountFocused)
                        }
                        TextField("Name", text: $draft.name)
                            .textInputAutocapitalization(.words)
                        DatePicker("Date", selection: Binding(get: { draft.date.date },
                                                              set: { draft.date = LocalDay.today(now: $0) }),
                                   displayedComponents: .date)
                        Toggle("Paid", isOn: $draft.paid)
                    } footer: {
                        Text(draft.paid ? "Recorded as paid on this date." : "Planned for this date; mark it paid when it clears.")
                    }
                    Section {
                        Picker("Category", selection: $draft.categoryId) {
                            Text("None").tag(Int?.none)
                            ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                        TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(1...4)
                        TagsRow(selected: $draft.tagIds)
                    }
                }
                .listRowBackground(Palette.row)
            }
            .scrollContentBackground(.hidden)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle(accountChoices.count > 1 ? "Add transaction" : "Add to \(account.name)")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .buttonStyle(.glassProminent)
                        .disabled(draft.problem != nil || draft.notes.count > 256)
                }
            }
            .alert("Couldn't add it", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onAppear { amountFocused = draft.amountText.isEmpty }
            .sensoryFeedback(.success, trigger: addedCount)
        }
    }

    private func add() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await client.add(draft, account: target.id)
        } catch {
            problem = AppModel.describe(error)
            return
        }
        addedCount += 1
        draft = NewTransactionDraft(today: .today())
        await onSaved()
        dismiss()
    }
}
