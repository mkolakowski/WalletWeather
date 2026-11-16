import SwiftUI
import WalletWeatherKit

/// Search, behind the round button beside the pages bar (ios-app phase 10,
/// #112): transactions, bills and income, accounts, categories, tags and
/// saved reports at once, through the server's `/api/search` (#111), grouped
/// by kind. A result opens where it lives: a transaction or a bill in its
/// editor, an account in Forecast, a category or a tag as its transactions,
/// a report run. Closed, editors are sheets and lists push; on the open Duo
/// the results stay on the left and the tapped result opens on the right.
/// A server older than 1.56.0 searches transactions only. Nothing about a
/// search is kept on the phone.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openPlace) private var openPlace
    @SceneStorage("search.text") private var text = ""

    @State private var found: Loadable<SearchResults>?
    @State private var accounts: [Account] = []
    @State private var categories: [TransactionCategory] = []
    @State private var openLine: OpenLine?
    @State private var openBill: OpenBill?
    @State private var shown: Shown?
    @State private var path: [Shown] = []
    @State private var skipping: RecurringItem?
    @State private var ending: RecurringItem?

    /// What a tapped result shows when it isn't an editor.
    enum Shown: Hashable {
        case report(SavedReport)
        case transactions(TransactionFilter, title: String)
        case forecast

        var title: String {
            switch self {
            case let .report(report): report.name
            case let .transactions(_, title): title
            case .forecast: "Forecast"
            }
        }
    }

    private var regular: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if regular {
                    HStack(spacing: 0) {
                        results.frame(maxWidth: .infinity)
                        detail.frame(maxWidth: .infinity)
                    }
                } else {
                    results
                }
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Search")
            .navigationDestination(for: Shown.self) { page($0, embedded: false) }
        }
        .searchable(text: $text, prompt: "Transactions, bills, accounts…")
        .lineEditorSheet($openLine, categories: categories) { await search() }
        .billEditorSheet($openBill, categories: categories) { await search() }
        .sheet(item: $skipping) { SkipDateSheet(item: $0) { await search() }.presentationDetents([.medium, .large]) }
        .sheet(item: $ending) { EndBillSheet(item: $0) { await search() }.presentationDetents([.medium]) }
        .task(id: model.generation) {
            if let debug = AppModel.debugSetting("WW_DEBUG_SEARCH") { text = debug }
            await loadLists()
        }
        .task(id: text) {
            // A short pause, so a search runs when typing stops.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
            debugOpen()
        }
    }

    // MARK: - The right half on the open Duo

    @ViewBuilder
    private var detail: some View {
        if let binding = Binding($openLine) {
            LineEditor(open: binding, categories: categories, embedded: true, onClose: { openLine = nil }) { await search() }
                .id(binding.wrappedValue.id)
        } else if let binding = Binding($openBill) {
            BillEditor(open: binding, accounts: accounts.filter(model.canEdit), categories: categories, embedded: true,
                       onClose: { openBill = nil }, onSkip: { skipping = $0 }, onEnd: { ending = $0 }) { await search() }
                .id(binding.wrappedValue.id)
        } else if let shown {
            // Its own header, so the window's title stays "Search".
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("Done") { self.shown = nil }.buttonStyle(.glass)
                    Spacer(minLength: 0)
                    Text(shown.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28).padding(.trailing, 16).padding(.vertical, 8)
                page(shown, embedded: true)
            }
            .id(shown)
        } else {
            ContentUnavailableView("Tap a result", systemImage: "hand.tap",
                                   description: Text("It opens here: a transaction or a bill to change, a category's transactions, a report."))
        }
    }

    /// A tapped result's page: pushed when closed, or in the right half
    /// (`embedded`, with no title of its own) on the open Duo.
    @ViewBuilder
    private func page(_ shown: Shown, embedded: Bool) -> some View {
        switch shown {
        case let .report(report):
            let result = ScrollView {
                ReportResult(report: report)
                    .padding(.leading, embedded ? 28 : 16).padding(.trailing, 16)
            }
            .background(PageBackground().ignoresSafeArea())
            if embedded {
                result
            } else {
                result.navigationTitle(report.name).navigationBarTitleDisplayMode(.inline)
            }
        case let .transactions(filter, title):
            FilteredTransactions(filter: filter, title: title, embedded: embedded, accounts: accounts, categories: categories)
        case .forecast:
            TabPage.forecast.view(embedded: true)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            ContentUnavailableView {
                Label("Search everything", systemImage: "magnifyingglass")
            } description: {
                Text("Find transactions, bills and income, accounts, categories, tags and saved reports, on every account you can see.")
            }
        } else {
            switch found {
            case nil, .loading?:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error)?:
                ProblemView(error: error) { Task { await search() } }
            case let .loaded(data)?:
                if data.isEmpty && !data.transactionsOnly {
                    ContentUnavailableView.search(text: query)
                } else {
                    list(data)
                }
            }
        }
    }

    private func list(_ data: SearchResults) -> some View {
        List {
            Group {
                group("Transactions", data.transactions) { hit in
                    Button { open(hit) } label: { SearchHitRow(hit: hit, selected: openLine?.line.transactionId == hit.id) }
                } footer: {
                    if data.transactions.total > data.transactions.results.count {
                        Text("Showing the newest \(data.transactions.results.count) of \(data.transactions.total). Add a word to narrow it down.")
                    }
                }
                group("Bills & income", data.recurring) { item in
                    Button { open(item) } label: {
                        SearchRow(title: item.description, detail: billDetail(item), trailing: item.amount.formatted,
                                  trailingColor: item.isIncome ? Palette.good : Palette.bad,
                                  selected: openBill?.item?.id == item.id)
                    }
                }
                group("Accounts", data.accounts) { account in
                    Button { open(account) } label: {
                        SearchRow(title: account.name, detail: account.level == "read" ? "Shared with you, read-only" : nil,
                                  trailing: account.currentBalance.formatted,
                                  trailingColor: account.currentBalance.isNegative ? Palette.bad : nil, selected: false)
                    }
                }
                group("Categories", data.categories) { category in
                    Button { show(.transactions(.category(category.id), title: category.name)) } label: {
                        SearchRow(title: category.name, detail: nil, trailing: category.countText,
                                  dot: Palette.category(category.color, name: category.name),
                                  selected: shown == .transactions(.category(category.id), title: category.name))
                    }
                }
                group("Tags", data.tags) { tag in
                    Button { show(.transactions(.tag(tag.id), title: tag.name)) } label: {
                        SearchRow(title: tag.name, detail: nil, trailing: tag.countText,
                                  dot: Palette.category(tag.color, name: tag.name),
                                  selected: shown == .transactions(.tag(tag.id), title: tag.name))
                    }
                }
                group("Reports", data.reports) { report in
                    Button { show(.report(report)) } label: {
                        SearchRow(title: report.name, detail: nil, trailing: nil, selected: shown == .report(report))
                    }
                }
                if data.transactionsOnly {
                    Section {
                        Text("Your server searches transactions only. Update it to WalletWeather 1.56.0 or later to find bills, accounts, categories, tags and reports too.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func group<Item: Identifiable, Row: View, Footer: View>(
        _ title: String, _ group: SearchResults.Group<Item>, @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder footer: () -> Footer = { EmptyView() }) -> some View {
        if group.total > 0 {
            Section {
                ForEach(group.results) { row($0) }
            } header: {
                Text("\(title) (\(group.total))")
            } footer: {
                footer()
            }
        }
    }

    private func billDetail(_ item: RecurringItem) -> String {
        let when = item.expired ? "Ended" : item.nextDate.map { "Next \($0.short)" }
        return [when, item.accountName].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Opening a result

    private func clear() {
        openLine = nil
        openBill = nil
        shown = nil
    }

    private func open(_ hit: TransactionSearch.Hit) {
        guard let account = accounts.first(where: { $0.id == hit.accountId }) else { return }
        clear()
        openLine = OpenLine(hit.line, account: account, editable: model.canEdit(account))
    }

    private func open(_ item: RecurringItem) {
        clear()
        openBill = OpenBill(item: item, editable: item.canEdit)
    }

    /// An account opens in Forecast: its tab when it's in the bar, or pushed
    /// here when it isn't.
    private func open(_ account: Account) {
        model.forecastRequest = account.id
        if settings.tabs.contains(.forecast) {
            openPlace(.forecast)
        } else {
            show(.forecast)
        }
    }

    private func show(_ page: Shown) {
        clear()
        if regular && page != .forecast { shown = page } else { path.append(page) }
    }

    // MARK: - Loading

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
            found = .loaded(try await client.search(query))
            settings.start.done.insert(.search)  // Getting started (#177)
        } catch {
            found = .failed(error)
        }
    }

    /// Debug builds only, for simulator screenshots: `WW_DEBUG_SEARCH_OPEN`
    /// opens the first result of a kind (transaction, bill, category, report,
    /// account).
    private func debugOpen() {
        guard let kind = AppModel.debugSetting("WW_DEBUG_SEARCH_OPEN"), let data = found?.value,
              openLine == nil, openBill == nil, shown == nil, path.isEmpty else { return }
        switch kind {
        case "transaction": if let hit = data.transactions.results.first { open(hit) }
        case "bill": if let item = data.recurring.results.first { open(item) }
        case "category":
            if let c = data.categories.results.first { show(.transactions(.category(c.id), title: c.name)) }
        case "report": if let r = data.reports.results.first { show(.report(r)) }
        case "account": if let a = data.accounts.results.first { open(a) }
        default: break
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

/// One result that isn't a transaction: its name and one detail, and on the
/// right an amount, a balance or a count.
struct SearchRow: View {
    let title: String
    let detail: String?
    let trailing: String?
    var trailingColor: Color?
    var dot: Color?
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let dot {
                Circle().fill(dot).frame(width: 9, height: 9).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).lineLimit(2)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.body.monospacedDigit()).foregroundStyle(trailingColor ?? .secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A category's or a tag's transactions, newest first; tapping one opens
/// it in the line editor (a sheet).
struct FilteredTransactions: View {
    @Environment(AppModel.self) private var model
    let filter: TransactionFilter
    let title: String
    /// In Search's right half on the open Duo, which shows the title itself.
    var embedded = false
    let accounts: [Account]
    let categories: [TransactionCategory]
    @State private var found: Loadable<TransactionSearch> = .loading
    @State private var open: OpenLine?

    var body: some View {
        Group {
            switch found {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                if data.results.isEmpty {
                    ContentUnavailableView("No transactions", systemImage: "tray",
                                           description: Text("Nothing on the accounts you can see carries \(title) yet."))
                } else {
                    List {
                        Section {
                            ForEach(data.results) { hit in
                                Button { open(hit) } label: { SearchHitRow(hit: hit, selected: open?.line.transactionId == hit.id) }
                                    .buttonStyle(.plain)
                            }
                        } footer: {
                            if data.total > data.results.count {
                                Text("Showing the newest \(data.results.count) of \(data.total).")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(PageBackground().ignoresSafeArea())
        .modifier(PushedTitle(title: embedded ? nil : title))
        .sheet(item: $open) { _ in
            if let binding = Binding($open) {
                LineEditor(open: binding, categories: categories, embedded: false, onClose: { open = nil }) { await load() }
            }
        }
        .task(id: model.generation) { await load() }
    }

    private func open(_ hit: TransactionSearch.Hit) {
        guard let account = accounts.first(where: { $0.id == hit.accountId }) else { return }
        open = OpenLine(hit.line, account: account, editable: model.canEdit(account))
    }

    private func load() async {
        guard let client = model.client else { return }
        do { found = .loaded(try await client.transactions(filter)) } catch { found = .failed(error) }
    }
}

/// A pushed page's title; none in Search's right half, where the window's
/// title stays "Search".
private struct PushedTitle: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
