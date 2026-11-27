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
    @FocusState private var fieldFocused: Bool
    /// The system field's focus on the iPhone (the open Duo draws its own, above), and ⌘F (#307).
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.searchFocusRequest) private var focusRequest
    @State private var hitActions = HitActions()

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

        var title: String {
            switch self {
            case let .report(report): report.name
            case let .transactions(_, title): title
            }
        }
    }

    private var regular: Bool { sizeClass == .regular }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if regular {
                    // Half open like a laptop (#304): the results above, the
                    // opened result below.
                    FoldLayout { _ in
                        // The system puts `.searchable`'s field at the window's top
                        // right, over the half the results are not in, and none of
                        // its placements sits over one half: so on the open Duo the
                        // page draws its own field over the results.
                        VStack(spacing: 0) {
                            searchField
                            results
                        }
                    } trailing: { edges in
                        detail(edges)
                    }
                    // Ready to type on an empty page; with a search already there, the
                    // keyboard stays down so it doesn't cover the results.
                    .onAppear { fieldFocused = text.trimmingCharacters(in: .whitespaces).isEmpty }
                } else {
                    results.searchable(text: $text, prompt: "Lines, bills, accounts…").searchFocused($searchFieldFocused)
                }
            }
            // Pulling down the results (or the opened result) runs the search again (#304).
            .refreshable { await search() }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(regular ? .inline : .automatic)
            .navigationDestination(for: Shown.self) { page($0, embedded: false) }
            .opensForecast()
        }
        .pageShortcuts(.search, [ShortcutHandler(.refresh) { Task { await search() } }])
        // ⌘F: the Search tab opens (`RootView`), then the cursor goes in the field.
        .onChange(of: focusRequest, initial: true) { _, request in
            if request > 0 { fieldFocused = true; searchFieldFocused = true }
        }
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

    // MARK: - The search field on the open Duo

    /// The field over the results (the left half): a rounded field with a
    /// magnifying glass and a clear button, on the same `text` as the
    /// closed iPhone's system field.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Lines, bills, accounts…", text: $text)
                .focused($fieldFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: - The right half on the open Duo

    @ViewBuilder
    private func detail(_ edges: FoldPanes.Edges) -> some View {
        if let binding = lasting($openLine) {
            LineEditor(open: binding, categories: categories, embedded: true, onClose: { openLine = nil }) { await search() }
                .id(binding.wrappedValue.id)
        } else if let binding = lasting($openBill) {
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
                .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.vertical, 8)
                page(shown, embedded: true, edges: edges)
            }
            .id(shown)
        } else {
            ContentUnavailableView("Tap a result", systemImage: "hand.tap",
                                   description: Text("It opens here: a line or a bill to change, a category's lines, a report."))
        }
    }

    /// A tapped result's page: pushed when closed, or in the right half
    /// (`embedded`, with no title of its own) on the open Duo.
    @ViewBuilder
    private func page(_ shown: Shown, embedded: Bool, edges: FoldPanes.Edges = .plain) -> some View {
        switch shown {
        case let .report(report):
            let result = ScrollView {
                ReportResult(report: report)
                    .padding(.leading, edges.leading).padding(.trailing, edges.trailing)
            }
            .background(PageBackground().ignoresSafeArea())
            if embedded {
                result
            } else {
                result.navigationTitle(report.name).navigationBarTitleDisplayMode(.inline)
            }
        case let .transactions(filter, title):
            // Its own `.opensForecast()`: a pushed page doesn't see the one on the stack's content.
            FilteredTransactions(filter: filter, title: title, embedded: embedded, accounts: accounts, categories: categories)
                .opensForecast()
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
                Text("Find lines, bills and income, accounts, categories, tags and saved reports, on every account you can see.")
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
                group("Lines", data.transactions) { hit in
                    Button { open(hit) } label: { SearchHitRow(hit: hit, selected: openLine?.line.transactionId == hit.id) }
                        .pointerRow()
                        .hitMenu(hit, accounts: accounts, state: hitActions, onEdit: { open(hit) }, reload: search)
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
                    .pointerRow()
                    .modifier(BillMenu(item: item, editable: item.canEdit && model.me.map { !$0.isReadOnly } == true,
                                       onEdit: { open($0) }, onSkip: { skipping = $0 }, onEnd: { ending = $0 }))
                }
                group("Accounts", data.accounts) { account in
                    OpenInForecastButton(account: account.id) {
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
                        Text("Your server searches lines only. Update it to WalletWeather 1.56.0 or later to find bills, accounts, categories, tags and reports too.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .hitActionsHost(hitActions, reload: search)
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

    private func show(_ page: Shown) {
        clear()
        if regular { shown = page } else { path.append(page) }
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
        case "account":
            // The row's own route (`OpenInForecastButton`), without its tap: the Forecast tab.
            if let a = data.accounts.results.first { model.forecastRequest = a.id; openPlace(.forecast) }
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
        let detail = [hit.accountName, line.plannedDate.map { ($0 == line.actualDate || !line.isPaid) ? $0.short : "paid \(line.actualDate?.short ?? "")" },
                      hit.categoryName].compactMap { $0 }.joined(separator: " · ")
        let amount = Text(hit.amount.formatted).font(.body.monospacedDigit())
            .foregroundStyle(hit.amount.isNegative ? Palette.bad : Palette.good)
            .wholeFigure()
        FitsAcross {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PaidMark(line: line, today: .today())
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.description).font(.body.weight(.medium)).lineLimit(2)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    TagChips(tags: hit.tags ?? [])
                    if let notes = hit.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                amount
            }
        } stacked: {
            // The larger text sizes: the amount under the words (#311).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PaidMark(line: line, today: .today())
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.description).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TagChips(tags: hit.tags ?? [])
                    if let notes = hit.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    /// The category's dot grows with the text (#311), 9 at Large as before.
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 9

    var body: some View {
        FitsAcross {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let dot {
                    Circle().fill(dot).frame(width: dotSize, height: dotSize).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium)).lineLimit(2)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.body.monospacedDigit()).foregroundStyle(trailingColor ?? .secondary).wholeFigure()
                }
            }
        } stacked: {
            // The larger text sizes: the amount, balance or count under the words (#311).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let dot {
                    Circle().fill(dot).frame(width: dotSize, height: dotSize).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let trailing {
                        Text(trailing).font(.body.monospacedDigit()).foregroundStyle(trailingColor ?? .secondary).wholeFigure()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var hitActions = HitActions()

    var body: some View {
        Group {
            switch found {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                if data.results.isEmpty {
                    ContentUnavailableView("No lines", systemImage: "tray",
                                           description: Text("Nothing on the accounts you can see carries \(title) yet."))
                } else {
                    List {
                        Section {
                            ForEach(data.results) { hit in
                                Button { open(hit) } label: { SearchHitRow(hit: hit, selected: open?.line.transactionId == hit.id) }
                                    .buttonStyle(.plain)
                                    .pointerRow()
                                    .hitMenu(hit, accounts: accounts, state: hitActions, onEdit: { open(hit) }, reload: load)
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
                    .refreshable { await load() }
                    .hitActionsHost(hitActions, reload: load)
                }
            }
        }
        .background(PageBackground().ignoresSafeArea())
        .modifier(PushedTitle(title: embedded ? nil : title))
        .sheet(item: $open) { _ in
            if let binding = lasting($open) {
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
