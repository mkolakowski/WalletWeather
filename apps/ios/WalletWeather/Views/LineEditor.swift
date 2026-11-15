import SwiftUI
import WalletWeatherKit

/// A line open in the editor, with what's been typed. It lives in the page
/// that opened it, not in the editor, so closing or opening the Duo
/// mid-edit keeps it: a sheet on the front screen, the right half open.
struct OpenLine: Identifiable, Equatable {
    let line: ForecastLine
    let account: Account
    let editable: Bool
    var draft: LineDraft
    var id: String { line.id }

    init(_ line: ForecastLine, account: Account, editable: Bool, today: LocalDay = .today()) {
        self.line = line
        self.account = account
        self.editable = editable && line.canEdit(onEditableAccount: true)
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

    @State private var saving = false
    @State private var problem: String?
    @State private var confirmDelete = false

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
        .padding(.leading, 28).padding(.trailing, 16).padding(.vertical, 8)
    }

    private func save() {
        Task { await run { try await $0.save(line, draft: open.draft, account: open.account.id) } }
    }

    private var form: some View {
            Form {
                aboutSection
                if open.editable {
                    paidSection
                    detailsSection
                    deleteSection
                } else {
                    readOnlySection
                }
            }
            .scrollContentBackground(.hidden)
            .background { if !embedded { PageBackground().ignoresSafeArea() } }
            .contentMargins(.leading, embedded ? 12 : 0, for: .scrollContent)
            .disabled(saving)
            .alert("Couldn't save", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(line.isProjection ? "Delete this date" : "Delete", role: .destructive) {
                    Task { await run { try await $0.delete(line) } }
                }
            } message: {
                Text(deleteMessage)
            }
    }

    // MARK: - Sections

    private var aboutSection: some View {
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

    private var paidSection: some View {
        Section {
            Toggle("Paid", isOn: $open.draft.paid.animation())
            if open.draft.paid {
                LabeledContent(line.plannedAmount.isNegative ? "Real amount spent" : "Real amount received") {
                    TextField("0.00", text: $open.draft.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel("Real amount")
                }
                DatePicker("Paid on", selection: dayBinding(\.paidOn), displayedComponents: .date)
            }
        } footer: {
            if open.draft.paid, let problem = open.draft.problem {
                Text(problem).foregroundStyle(Palette.bad)
            } else if !open.draft.paid && line.isPaid {
                Text("Saving marks it not paid: it goes back to its planned amount and date.")
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
        } footer: {
            if open.draft.notes.count > 256 {
                Text("Notes can be up to 256 characters.").foregroundStyle(Palette.bad)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(line.isProjection ? "Delete this date" : "Delete transaction", role: .destructive) {
                confirmDelete = true
            }
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
        if line.isTransfer { return "Transfers between accounts are changed in the web app." }
        if model.me?.isReadOnly == true { return "This phone signed in with a read-only token, so nothing can be changed here." }
        return "You can see this account but not change it."
    }

    private var deleteTitle: String {
        line.isProjection ? "Delete the \(line.plannedDate?.short ?? "") date?" : "Delete this transaction?"
    }

    private var deleteMessage: String {
        if line.isProjection {
            return "The repeating bill or paycheck keeps its other dates; only this one is removed. You can restore deleted dates in the web app's Bills & income."
        }
        if line.recurringId != nil {
            return "This can't be undone. Its repeating bill or paycheck stays, but this date won't be projected again (restore it in the web app's Bills & income)."
        }
        return "This can't be undone."
    }

    private func dayBinding(_ key: WritableKeyPath<LineDraft, LocalDay>) -> Binding<Date> {
        Binding(get: { open.draft[keyPath: key].date },
                set: { open.draft[keyPath: key] = LocalDay.today(now: $0) })
    }

    private func run(_ action: (APIClient) async throws -> Void) async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await action(client)
        } catch {
            problem = AppModel.describe(error)
            return
        }
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
    let categories: [TransactionCategory]
    @Binding var draft: NewTransactionDraft
    let onSaved: () async -> Void

    @State private var saving = false
    @State private var problem: String?
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(NewTransactionDraft.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
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
                }
            }
            .scrollContentBackground(.hidden)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Add to \(account.name)")
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
        }
    }

    private func add() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await client.add(draft, account: account.id)
        } catch {
            problem = AppModel.describe(error)
            return
        }
        draft = NewTransactionDraft(today: .today())
        await onSaved()
        dismiss()
    }
}
