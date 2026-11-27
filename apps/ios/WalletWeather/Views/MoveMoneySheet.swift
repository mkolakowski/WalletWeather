import SwiftUI
import WalletWeatherKit

/// The + button's menu on Forecast, Bills & income and Calendar: the page's
/// own Add, and Move money (decided 2026-11-15). Move money shows only
/// when there are two accounts this person may edit.
struct AddMenu: ToolbarContent {
    let addTitle: String
    let canMove: Bool
    let onAdd: () -> Void
    let onMove: () -> Void
    /// Import a CSV (#243), where the page offers it.
    var onImport: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(addTitle, systemImage: "plus.circle", action: onAdd)
                if canMove {
                    Button("Move money", systemImage: "arrow.left.arrow.right", action: onMove)
                }
                if let onImport {
                    Button("Import a CSV…", systemImage: "doc.text", action: onImport)
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }
}

/// The sort button beside + (#350), where the page shows a list that can be
/// sorted: by date, amount or name, either way round. The choice is kept by
/// the page (`stored`, a `ListSort.rawValue`); empty is the list's own order.
struct SortMenu: ToolbarContent {
    @Binding var stored: String
    let fallback: ListSort
    /// The list's dates are still to come (Bills) rather than gone by (To confirm).
    var future = false

    var body: some ToolbarContent {
        let current = ListSort.stored(stored, default: fallback)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: Binding(get: { current }, set: { stored = $0.rawValue })) {
                    ForEach(ListSort.Key.allCases, id: \.self) { key in
                        Section(key.title) {
                            ForEach(ListSort.choices.filter { $0.key == key }, id: \.self) {
                                Text($0.title(future: future)).tag($0)
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityValue(current.spoken(future: future))
        }
    }
}

/// Move money between two accounts you may edit. It's recorded as paid on
/// the day you pick, on both accounts. Given `changing`, the id of a
/// transfer, it's Change transfer instead: the same form filled in, and
/// saving changes both of the transfer's lines together (#324).
struct MoveMoneySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    @Binding var draft: MoveMoneyDraft
    var changing: Int?
    let onMoved: () async -> Void

    @State private var saving = false
    @State private var problem: FormProblem?
    @State private var movedCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Picker("From", selection: $draft.fromAccountId) {
                            Text("Choose").tag(Int?.none)
                            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Picker("To", selection: $draft.toAccountId) {
                            Text("Choose").tag(Int?.none)
                            ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                        LabeledContent("Amount") {
                            TextField("0.00", text: $draft.amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        DatePicker("Date", selection: Binding(get: { draft.date.date },
                                                              set: { draft.date = LocalDay.today(now: $0) }),
                                   displayedComponents: .date)
                    } footer: {
                        if let problem = draft.problem, !draft.amountText.isEmpty || draft.fromAccountId != nil {
                            Text(problem).foregroundStyle(Palette.bad)
                        } else {
                            Text(changing == nil ? "Recorded as paid on this date, on both accounts."
                                                 : "Both of the transfer's lines change together, on both accounts.")
                        }
                    }
                    Section {
                        TextField("Description", text: $draft.description)
                        TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(1...4)
                    }
                }
                .listRowBackground(Palette.row)
            }
            .scrollContentBackground(.hidden)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle(changing == nil ? "Move money" : "Change transfer")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .problemBanner($problem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.keyShortcut(.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(changing == nil ? "Move" : "Save") { Task { await move() } }
                        .prominentButton()
                        .keyShortcut(.save)
                        .disabled(draft.problem != nil)
                }
            }
            .sensoryFeedback(.success, trigger: movedCount)
        }
    }

    private func move() async {
        guard let client = model.client, let body = TransferBody(draft) else { return }
        saving = true
        problem = nil
        defer { saving = false }
        do {
            try FormProblem.failIfAsked()
            if let changing {
                try await client.updateTransfer(changing, body)
            } else {
                try await client.moveMoney(body)
            }
        } catch {
            problem = FormProblem(error) { Task { await move() } }
            return
        }
        movedCount += 1
        await onMoved()
        dismiss()
    }
}
