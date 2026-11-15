import SwiftUI
import WalletWeatherKit

/// Search, behind the round button beside the pages bar. In this version it
/// finds transactions by name or notes on every account you can see,
/// through the server's existing search; a later version widens it to
/// bills, accounts, categories and reports (#111, phase 10). Tapping a
/// result opens its editor right there: a sheet closed, the right half
/// open (decided 2026-11-15).
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("search.text") private var text = ""

    @State private var found: Loadable<TransactionSearch>?
    @State private var accounts: [Account] = []
    @State private var categories: [TransactionCategory] = []
    @State private var open: OpenLine?

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        results.frame(maxWidth: .infinity)
                        Group {
                            if let binding = Binding($open) {
                                LineEditor(open: binding, categories: categories, embedded: true, onClose: { open = nil }) { await search() }
                                    .id(binding.wrappedValue.id)
                            } else {
                                ContentUnavailableView("Tap a result", systemImage: "hand.tap",
                                                       description: Text("It opens here, to mark it paid or change it."))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    results
                }
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Search")
        }
        .searchable(text: $text, prompt: "Transactions by name or notes")
        .lineEditorSheet($open, categories: categories) { await search() }
        .task(id: model.generation) {
            if let debug = AppModel.debugSetting("WW_DEBUG_SEARCH") { text = debug }
            await loadLists()
        }
        .task(id: text) {
            // A short pause, so a search runs when typing stops.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    @ViewBuilder
    private var results: some View {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            ContentUnavailableView {
                Label("Search transactions", systemImage: "magnifyingglass")
            } description: {
                Text("Find a transaction by its name or notes, on every account you can see. Bills, accounts, categories and reports come in a later version.")
            }
        } else {
            switch found {
            case nil, .loading?:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error)?:
                ProblemView(error: error) { Task { await search() } }
            case let .loaded(data)?:
                if data.results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        Group {
                            Section {
                                ForEach(data.results) { hit in
                                    Button { openHit(hit) } label: {
                                        SearchHitRow(hit: hit, selected: open?.line.transactionId == hit.id)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Color.clear)
                                }
                            } footer: {
                                if data.total > data.results.count {
                                    Text("Showing the newest \(data.results.count) of \(data.total). Add a word to narrow it down.")
                                }
                            }
                        }
                        .listRowBackground(Palette.row)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private func openHit(_ hit: TransactionSearch.Hit) {
        guard let account = accounts.first(where: { $0.id == hit.accountId }) else { return }
        open = OpenLine(hit.line, account: account, editable: model.canEdit(account))
    }

    private func loadLists() async {
        guard let client = model.client else { return }
        accounts = (try? await client.accounts()) ?? []
        categories = (try? await client.categories()) ?? []
    }

    private func search() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard let client = model.client, !query.isEmpty else {
            found = nil
            return
        }
        if found?.value == nil { found = .loading }
        do {
            found = .loaded(try await client.searchTransactions(query))
        } catch {
            found = .failed(error)
        }
    }
}

/// One result: name and amount, the account and the date, the category.
struct SearchHitRow: View {
    let hit: TransactionSearch.Hit
    let selected: Bool

    var body: some View {
        let line = hit.line
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            PaidMark(line: line, today: .today())
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.description).font(.body.weight(.medium)).lineLimit(2)
                Text([hit.accountName, line.plannedDate.map { ($0 == line.actualDate || !line.isPaid) ? $0.short : "paid \(line.actualDate?.short ?? "")" },
                      hit.categoryName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let notes = hit.notes, !notes.isEmpty {
                    Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(hit.amount.formatted).font(.body.monospacedDigit())
                .foregroundStyle(hit.amount.isNegative ? Palette.bad : Palette.good)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
