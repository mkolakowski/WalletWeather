import SwiftUI
import WalletWeatherKit

/// The Dashboard, read-only: Getting started while it's due (#175), "rest of
/// this month", a card per account, the charts with the Month / 30 days /
/// 90 days switch, and pinned reports.
/// One column on any iPhone and on the Duo closed; on the open Duo the
/// accounts take the left half and the charts the right, through
/// `FoldLayout`, with nothing to read or tap on the fold. An account opens in
/// Forecast when tapped, closed; open, a tap chooses it and the right half
/// shows that account alone: its charts, what's coming up, what to confirm
/// (#305).
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("dashboard.window") private var window: ChartWindow = .month
    /// The account chosen on the open Duo (#305); 0 for none. Kept with the
    /// connection it was chosen on, like the other pages' accounts.
    @SceneStorage("dashboard.account") private var chosenId = 0
    @SceneStorage("dashboard.account.byConnection") private var accountMemo = ""
    @State private var startTask: StartTask?
    @State private var addingAccount = false
    @State private var importingBackup = false
    @State private var importNote: String?

    @State private var summary: Loadable<Dashboard> = .loading
    @State private var charts: Loadable<DashboardCharts> = .loading
    @State private var pinned: [PinnedReport] = []
    @State private var kept = KeptTracker()
    /// Counts loads, so the chosen account's "Coming up" reads again with them.
    @State private var loadCount = 0
    // For the + menu (#314): the accounts and categories a new transaction needs.
    @State private var accounts: [Account] = []
    @State private var categories: [TransactionCategory] = []
    @State private var adding = false
    @State private var newDraft = NewTransactionDraft(today: .today())
    @State private var moving = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())
    @State private var importingCSV = false
    /// What bank sync asks of the person on a server (#321); the iPhone's own
    /// bank is read live from `model.phoneBank`.
    @State private var serverBankLines: [BankCardLine] = []
    /// The Unmatched list the bank card opened.
    @State private var unmatchedRoute: UnmatchedRoute?

    /// The bank card's lines: none while the lock has the demo in front.
    private var bankLines: [BankCardLine] {
        if settings.lockedInDemo { return [] }
        if model.isLocal { return BankCard.lines(phone: model.phoneBank.state, connected: model.phoneBank.connected) }
        return serverBankLines
    }

    private var editableAccounts: [Account] { accounts.filter(model.canEdit) }
    /// The account a dropped CSV starts on (#308): the one chosen on the open
    /// Duo, when this person may change it; else the sheet asks.
    private var droppedCSVAccount: Int? {
        guard sizeClass == .regular, chosenId != 0 else { return nil }
        return editableAccounts.first { $0.id == chosenId }?.id
    }

    struct PinnedReport: Identifiable {
        let report: SavedReport
        var run: Loadable<ReportRun>
        var id: Int { report.id }
    }

    var body: some View {
        PageStack {
            Group {
                switch summary {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(error):
                    ProblemView(error: error) { Task { await load() } }
                case let .loaded(dashboard):
                    if sizeClass == .regular {
                        twoPanes(dashboard)
                    } else {
                        oneColumn(dashboard)
                    }
                }
            }
            // A bank's CSV dropped here imports (#308), where + offers Import a CSV: to the chosen account, if one.
            .csvDropTarget(enabled: !editableAccounts.isEmpty, account: droppedCSVAccount) { await load() }
            .opensForecast()
            .unmatchedList($unmatchedRoute)
            .keptBar(kept)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Dashboard")
            // Two scroll panes side by side leave a large title nothing to collapse against, so cards
            // slide under it (#260): the open Duo gets the small title.
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
            .toolbar { NewWindowItem(place: .dashboard) }
            .toolbar {
                if !editableAccounts.isEmpty {
                    AddMenu(addTitle: "Add transaction", canMove: editableAccounts.count > 1, onAdd: startAdding, onMove: {
                        moveDraft = MoveMoneyDraft(today: .today())
                        moving = true
                    }, onImport: { importingCSV = true })
                }
            }
        }
        .task(id: model.generation) {
            await load()
            // Debug only: `WW_DEBUG_DASH_ACCOUNT=<account name>` chooses that account (#305).
            if let name = AppModel.debugSetting("WW_DEBUG_DASH_ACCOUNT"),
               let card = summary.value?.cards.first(where: { $0.name == name }) { chosenId = card.id }
        }
        .task(id: model.generation) { await loadChoices() }
        // Bank sync's asks, read again with each load and when back from the Unmatched list.
        .task(id: "\(model.generation)/\(loadCount)/\(settings.lockedInDemo)") { await loadBank() }
        .onChange(of: unmatchedRoute) { _, now in
            if now == nil { Task { await loadBank() } }
        }
        .scopedToConnection($chosenId, memo: $accountMemo)
        .sheet(isPresented: $adding) {
            if let target = editableAccounts.first {
                AddTransactionSheet(account: target, accountChoices: editableAccounts,
                                    categories: categories, draft: $newDraft) { await load() }
            }
        }
        .sheet(isPresented: $moving) {
            MoveMoneySheet(accounts: editableAccounts, draft: $moveDraft) { await load() }
        }
        .csvImporter(isPresented: $importingCSV, account: nil) { await load() }
        .pageShortcuts(.dashboard, [ShortcutHandler(.addTransaction, enabled: !editableAccounts.isEmpty) { startAdding() },
                                    ShortcutHandler(.refresh) { Task { await load() } }])
        .task(id: window) { await loadCharts() }
        .sheet(item: $startTask) { StartTaskSheet(task: $0) }
        .sheet(isPresented: $addingAccount) { NewAccountSheet { model.accountAdded() } }
        .backupImporter(isPresented: $importingBackup) { message, _ in importNote = message }
        .onAppear {
            // Debug only: `WW_DEBUG_START=tour` (or a task's name) opens its sheet.
            if let debug = AppModel.debugSetting("WW_DEBUG_START") {
                startTask = debug == "tour" ? .tabBar : StartTask(rawValue: debug)
            }
        }
    }

    private func startAdding() {
        newDraft = NewTransactionDraft(today: .today())
        adding = true
    }

    // MARK: - Layouts

    private func oneColumn(_ dashboard: Dashboard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                accountsColumn(dashboard)
                chartsColumn(chosen: nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    /// The open Duo (#304): the accounts on the left and the charts on the
    /// right, either side of the fold; half open like a laptop, the charts
    /// stand up and the accounts lie below. Either half pulls to refresh.
    private func twoPanes(_ dashboard: Dashboard) -> some View {
        FoldLayout(upright: .trailing) { edges in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) { accountsColumn(dashboard) }
                    .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
            }
        } trailing: { edges in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) { chartsColumn(chosen: chosen(in: dashboard)) }
                    .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func accountsColumn(_ dashboard: Dashboard) -> some View {
        // Under the title: the connection in front, and the way to switch (#301, #302).
        if model.connectionChip(locked: settings.lockedInDemo) != nil {
            ConnectionChip(debugSheet: true)
        }
        if settings.showsStartCard && !model.isDemo {
            GettingStartedCard { startTask = $0 }
        }
        if dashboard.cards.isEmpty && model.isLocal {
            // On this iPhone, accounts are added here and in Settings (#235).
            ContentUnavailableView {
                Label("Add your first account", systemImage: "building.columns")
            } description: {
                Text("Start with the account your pay goes into, with its balance today. Bills, income and spending go on it next.")
            } actions: {
                Button("Add an account") { addingAccount = true }.buttonStyle(.glassProminent)
                // Or bring a household from a server (#236).
                Button("Import a server backup") { importingBackup = true }.buttonStyle(.borderless)
                if let importNote { Text(importNote).font(.footnote).foregroundStyle(.secondary) }
            }
        } else if dashboard.cards.isEmpty {
            ContentUnavailableView("No accounts yet", systemImage: "building.columns",
                                   description: Text("Add an account in the web app's Settings, and it shows here."))
        } else {
            // Only while bank sync has something to do (#321): no card, no gap, otherwise.
            if !bankLines.isEmpty {
                BankStatusCard(lines: bankLines) { open($0) }
            }
            RestOfMonthCard(dashboard: dashboard)
            ForEach(dashboard.cards) { card in
                if sizeClass == .regular {
                    // The open Duo: a tap chooses the account for the right half, and again clears it.
                    let isChosen = card.id == chosenId
                    Button { chosenId = isChosen ? 0 : card.id } label: {
                        AccountCard(card: card, tap: .choose, chosen: isChosen)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isChosen ? "Clears the choice" : "Shows its charts and what's coming up")
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                } else {
                    OpenInForecastButton(account: card.id) { AccountCard(card: card, tap: .forecast, chosen: false) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in Forecast")
                }
            }
        }
    }

    /// The chosen account's card, while the page has two panes and it's still there.
    private func chosen(in dashboard: Dashboard) -> Dashboard.Card? {
        guard sizeClass == .regular, chosenId != 0 else { return nil }
        return dashboard.cards.first { $0.id == chosenId }
    }

    /// The right half with an account chosen: its charts, what's coming up and
    /// to confirm, and the way into Forecast.
    @ViewBuilder
    private func chosenColumn(_ card: Dashboard.Card) -> some View {
        // What's coming and the way into Forecast first: the charts card is
        // taller than the pane, so under it they were out of sight.
        ChosenAccountPane(card: card, editable: accounts.first { $0.id == card.id }.map(model.canEdit) ?? false,
                          reload: loadCount)
            .id(card.id)
        switch charts {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding()
        case let .failed(error):
            ProblemView(error: error) { Task { await loadCharts() } }
        case let .loaded(data):
            if let account = data.accounts.first(where: { $0.accountId == card.id }) {
                AccountChartsCard(account: account)
            }
        }
    }

    @ViewBuilder
    private func chartsColumn(chosen: Dashboard.Card?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Charts cover", selection: $window) {
                ForEach(ChartWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let range = charts.value {
                Text("\(range.label) · \(range.start.short) – \(range.end.short)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        if let chosen {
            chosenColumn(chosen)
        } else {
            switch charts {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding()
            case let .failed(error):
                ProblemView(error: error) { Task { await loadCharts() } }
            case let .loaded(data):
                if data.accounts.isEmpty {
                    Text("No chart data for this window.").foregroundStyle(.secondary)
                }
                ForEach(data.accounts) { AccountChartsCard(account: $0) }
            }
            ForEach(pinned) { PinnedReportCard(report: $0.report, run: $0.run) }
        }
    }

    // MARK: - Loading

    private func load() async {
        guard let client = model.client(kept) else { return }
        do {
            summary = .loaded(try await client.dashboard())
        } catch {
            summary = .failed(error)
            kept.clear()
            return
        }
        loadCount += 1
        await loadCharts()
        await loadPinned()
    }

    /// What a tap on a bank card line opens: the Unmatched list, or the
    /// Settings page where a bank is connected again.
    @Environment(\.openPlace) private var openPlace

    private func open(_ line: BankCardLine) {
        switch line.action {
        case let .unmatched(accounts): unmatchedRoute = UnmatchedRoute(accounts: accounts)
        case .reconnect:
            model.settingsRequest = .bank
            openPlace(.more)
        }
    }

    /// Bank sync's status and Unmatched counts on a server, asked quietly: a
    /// status that can't be read, or a server before bank sync, shows no card.
    private func loadBank() async {
        guard !settings.lockedInDemo, !model.isLocal, let client = model.client(kept) else {
            serverBankLines = []
            return
        }
        var status = try? await client.bankStatus()
        #if DEBUG
        // `WW_DEBUG_BANK_CARD=reconnect` shows the first connection as needing to be connected again.
        if AppModel.debugSetting("WW_DEBUG_BANK_CARD") == "reconnect", let found = status, let first = found.connections?.first {
            var list = found.connections ?? []
            list[0] = BankConnection(id: first.id, provider: first.provider, providerName: first.providerName, name: first.name,
                                     linkedAccountIds: first.linkedAccountIds, needsReconnect: true)
            status = BankStatus(enabled: found.enabled, connected: found.connected, linkedAccountIds: found.linkedAccountIds,
                                connections: list, shared: found.shared)
        }
        #endif
        var counts: [Int: Int] = [:]
        if let status { counts = await client.unmatchedCounts(for: status) }
        serverBankLines = BankCard.lines(status: status, counts: counts)
    }

    /// The accounts and categories the + menu works from.
    private func loadChoices() async {
        guard let client = model.client(kept) else { return }
        accounts = (try? await client.accounts()) ?? []
        categories = (try? await client.categories()) ?? []
    }

    private func loadCharts() async {
        guard let client = model.client(kept) else { return }
        if charts.value?.window != window { charts = .loading }
        do {
            charts = .loaded(try await client.charts(window))
        } catch {
            charts = .failed(error)
        }
    }

    /// Pinned reports, each run on its own, as the web Dashboard does. A
    /// report that can't run says so in its own card.
    private func loadPinned() async {
        guard let client = model.client(kept) else { return }
        guard let saved = try? await client.savedReports() else { return }
        pinned = saved.filter(\.pinned).map { PinnedReport(report: $0, run: .loading) }
        for i in pinned.indices {
            do {
                pinned[i].run = .loaded(try await client.runReport(pinned[i].report.id))
            } catch {
                pinned[i].run = .failed(error)
            }
        }
    }
}

// MARK: - Cards

/// "Rest of this month" across every account.
struct RestOfMonthCard: View {
    let dashboard: Dashboard

    var body: some View {
        let rest = dashboard.restOfMonth
        let end = LocalDay.today().endOfMonth.short
        VStack(alignment: .leading, spacing: 6) {
            Caption("Rest of this month")
            if rest.count == 0 {
                Text("Nothing left pending before \(end): you're all caught up for the rest of the month.")
                    .font(.callout)
            } else {
                Text("**\(rest.count)** upcoming item\(rest.count == 1 ? "" : "s") before \(end)")
                FigureRow(spacing: 18) {
                    VStack(alignment: .leading) {
                        Text("Net").font(.caption).foregroundStyle(.secondary)
                        Text(rest.net.formatted).font(.headline.monospacedDigit())
                            .foregroundStyle(rest.net.isNegative ? Palette.bad : Palette.good)
                            .wholeFigure()
                    }
                    VStack(alignment: .leading) {
                        Text("Projected balance").font(.caption).foregroundStyle(.secondary)
                        Text(rest.projected.formatted).font(.headline.monospacedDigit())
                            .foregroundStyle(Palette.amount(rest.projected.isNegative))
                            .wholeFigure()
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// What bank sync asks of the person (#321): one slim line each, at most two,
/// most urgent first, each opening where it's dealt with. Shown by the
/// Dashboard only when there's a line.
struct BankStatusCard: View {
    let lines: [BankCardLine]
    let open: (BankCardLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                if line.id != lines.first?.id { Divider() }
                Button { open(line) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: line.symbol)
                            .foregroundStyle(line.action == .reconnect ? Palette.warn : Color.secondary)
                            .frame(width: 22)
                        Text(line.text).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(line.action == .reconnect ? "Opens Settings, Bank sync" : "Opens the bank lines that paid no planned line")
            }
        }
        .card()
    }
}

/// One account: balance today, month-end forecast and actual, and the
/// month's low and high with their dates.
struct AccountCard: View {
    let card: Dashboard.Card
    /// What a tap does (#305): nothing, open Forecast, or choose the account
    /// for the right half of the open Duo.
    var tap: Tap = .none
    /// Chosen for the right half: an accent outline and a tick.
    var chosen = false

    enum Tap { case none, forecast, choose }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitsAcross {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) { month }
                }
            } stacked: {
                // The larger text sizes: the month and the hint under the name (#311).
                VStack(alignment: .leading, spacing: 2) {
                    name
                    month
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Caption("Balance today")
                Text(card.currentBalance.formatted)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.amount(card.currentBalance.isNegative))
                    .wholeFigure(defaultScale: 0.6)
                    // Already the biggest text on the page: it stops growing
                    // where a whole balance still fits the card (#311).
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            FitsAcross {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        figure("Month-end forecast", card.forecastEnd)
                        figure("Month-end actual", card.actualEnd)
                    }
                    GridRow {
                        figure("Low", card.forecastLow, on: card.forecastLowDate)
                        figure("High", card.forecastHigh, on: card.forecastHighDate)
                    }
                }
            } stacked: {
                // The larger text sizes: one to a row (#311).
                VStack(alignment: .leading, spacing: 10) {
                    figure("Month-end forecast", card.forecastEnd)
                    figure("Month-end actual", card.actualEnd)
                    figure("Low", card.forecastLow, on: card.forecastLowDate)
                    figure("High", card.forecastHigh, on: card.forecastHighDate)
                }
            }
        }
        .card()
        .overlay {
            if chosen {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.accent, lineWidth: 2.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(card.name).font(.headline)
            if chosen {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Chosen")
            }
        }
    }

    @ViewBuilder
    private var month: some View {
        Text(card.monthLabel).font(.caption).foregroundStyle(.secondary)
        if tap == .forecast { ForecastHint() }
    }

    private func figure(_ label: String, _ value: Money, on day: LocalDay? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
                .wholeFigure()
            if let day {
                Text(day.short).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The chosen account (#305)

/// The right half of the open Duo with an account chosen, above its charts:
/// the next five lines still to be paid, the lines to confirm, and the way
/// into Forecast.
struct ChosenAccountPane: View {
    @Environment(AppModel.self) private var model
    let card: Dashboard.Card
    let editable: Bool
    /// Changes when the page loads again.
    let reload: Int

    @State private var coming: Loadable<Coming> = .loading

    struct Coming {
        let lines: [ForecastLine]
        let toConfirm: Int
    }

    private static let count = 5

    var body: some View {
        Group {
            switch coming {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding()
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                comingUp(data.lines)
                if editable, data.toConfirm > 0 { confirmButton(data.toConfirm) }
            }
            OpenInForecastButton(account: card.id) {
                Label("Open in Forecast", systemImage: "chart.line.uptrend.xyaxis").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .accessibilityHint("Opens in Forecast")
        }
        .task(id: "\(model.generation)/\(card.id)/\(reload)") { await load() }
    }

    private func comingUp(_ lines: [ForecastLine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption("Coming up")
            if lines.isEmpty {
                Text("Nothing left to pay this month or next.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.description).lineLimit(2)
                        Text([line.plannedDate?.short, line.category].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(line.amount.formatted).monospacedDigit()
                        .foregroundStyle(line.isTransfer ? .secondary : (line.amount.isNegative ? Palette.bad : Palette.good))
                        .wholeFigure()
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func confirmButton(_ count: Int) -> some View {
        OpenInForecastButton(account: card.id, toConfirm: true) {
            HStack {
                Label("\(count) to confirm", systemImage: "checkmark.circle")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityHint("Opens To confirm in Forecast")
    }

    /// This month's forecast, and next month's when fewer than five lines are left.
    private func load() async {
        guard let client = model.client else { return }
        let today = LocalDay.today()
        let month = YearMonth(today)
        do {
            let here = try await client.forecast(account: card.id, month: month, today: today)
            var next: ForecastMonth?
            if here.comingUp(today: today, limit: Self.count).count < Self.count {
                next = try await client.forecast(account: card.id, month: month.next, today: today)
            }
            coming = .loaded(Coming(lines: here.comingUp(today: today, following: next, limit: Self.count),
                                    toConfirm: here.toConfirm(today: today).count))
        } catch {
            coming = .failed(error)
        }
    }
}
