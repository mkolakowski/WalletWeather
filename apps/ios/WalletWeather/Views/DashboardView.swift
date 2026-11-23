import SwiftUI
import WalletWeatherKit

/// The Dashboard, read-only: Getting started while it's due (#175), "rest of
/// this month", a card per account, the charts with the Month / 30 days /
/// 90 days switch, and pinned reports.
/// One column on any iPhone and on the Duo closed; on the open Duo the
/// accounts take the left half and the charts the right, through
/// `FoldLayout`, with nothing to read or tap on the fold.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("dashboard.window") private var window: ChartWindow = .month
    @State private var startTask: StartTask?
    @State private var addingAccount = false
    @State private var importingBackup = false
    @State private var importNote: String?

    @State private var summary: Loadable<Dashboard> = .loading
    @State private var charts: Loadable<DashboardCharts> = .loading
    @State private var pinned: [PinnedReport] = []
    @State private var kept = KeptTracker()
    // For the + menu (#314): the accounts and categories a new transaction needs.
    @State private var accounts: [Account] = []
    @State private var categories: [TransactionCategory] = []
    @State private var adding = false
    @State private var newDraft = NewTransactionDraft(today: .today())
    @State private var moving = false
    @State private var moveDraft = MoveMoneyDraft(today: .today())
    @State private var importingCSV = false

    private var editableAccounts: [Account] { accounts.filter(model.canEdit) }

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
            .keptBar(kept)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Dashboard")
            // Two scroll panes side by side leave a large title nothing to collapse against, so cards
            // slide under it (#260): the open Duo gets the small title.
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
            .toolbar { NewWindowItem(place: .dashboard) }
            .toolbar {
                if !editableAccounts.isEmpty {
                    AddMenu(addTitle: "Add transaction", canMove: editableAccounts.count > 1, onAdd: {
                        newDraft = NewTransactionDraft(today: .today())
                        adding = true
                    }, onMove: {
                        moveDraft = MoveMoneyDraft(today: .today())
                        moving = true
                    }, onImport: { importingCSV = true })
                }
            }
        }
        .task(id: model.generation) { await load() }
        .task(id: model.generation) { await loadChoices() }
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

    // MARK: - Layouts

    private func oneColumn(_ dashboard: Dashboard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                accountsColumn(dashboard)
                chartsColumn
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
                LazyVStack(alignment: .leading, spacing: 14) { chartsColumn }
                    .padding(.leading, edges.leading).padding(.trailing, edges.trailing).padding(.bottom, 24)
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func accountsColumn(_ dashboard: Dashboard) -> some View {
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
            RestOfMonthCard(dashboard: dashboard)
            ForEach(dashboard.cards) { AccountCard(card: $0) }
        }
    }

    @ViewBuilder
    private var chartsColumn: some View {
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
        await loadCharts()
        await loadPinned()
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
                HStack(spacing: 18) {
                    VStack(alignment: .leading) {
                        Text("Net").font(.caption).foregroundStyle(.secondary)
                        Text(rest.net.formatted).font(.headline.monospacedDigit())
                            .foregroundStyle(rest.net.isNegative ? Palette.bad : Palette.good)
                    }
                    VStack(alignment: .leading) {
                        Text("Projected balance").font(.caption).foregroundStyle(.secondary)
                        Text(rest.projected.formatted).font(.headline.monospacedDigit())
                            .foregroundStyle(Palette.amount(rest.projected.isNegative))
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One account: balance today, month-end forecast and actual, and the
/// month's low and high with their dates.
struct AccountCard: View {
    let card: Dashboard.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name).font(.headline)
                Spacer()
                Text(card.monthLabel).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Caption("Balance today")
                Text(card.currentBalance.formatted)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.amount(card.currentBalance.isNegative))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
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
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: Money, on day: LocalDay? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
            if let day {
                Text(day.short).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
