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

/// Move money between two accounts you may edit. It's recorded as paid on
/// the day you pick, on both accounts.
struct MoveMoneySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let accounts: [Account]
    @Binding var draft: MoveMoneyDraft
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
                            Text("Recorded as paid on this date, on both accounts.")
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
            .navigationTitle("Move money")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .problemBanner($problem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { await move() } }
                        .buttonStyle(.glassProminent)
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
            try await client.moveMoney(body)
        } catch {
            problem = FormProblem(error) { Task { await move() } }
            return
        }
        movedCount += 1
        await onMoved()
        dismiss()
    }
}
