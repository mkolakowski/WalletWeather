import SwiftUI
import WalletWeatherKit

/// The Dashboard, read-only: "rest of this month", a card per account, the
/// charts with the Month / 30 days / 90 days switch, and pinned reports.
/// One column on any iPhone and on the Duo closed; on the open Duo the
/// accounts take the left half and the charts the right, meeting at the fold
/// with nothing to read or tap on it.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("dashboard.window") private var window: ChartWindow = .month

    @State private var summary: Loadable<Dashboard> = .loading
    @State private var charts: Loadable<DashboardCharts> = .loading
    @State private var pinned: [PinnedReport] = []
    @State private var kept = KeptTracker()

    struct PinnedReport: Identifiable {
        let report: SavedReport
        var run: Loadable<ReportRun>
        var id: Int { report.id }
    }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                }
            }
        }
        .task(id: model.generation) { await load() }
        .task(id: window) { await loadCharts() }
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

    /// Two halves; each keeps clear of the fold in the middle.
    private func twoPanes(_ dashboard: Dashboard) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) { accountsColumn(dashboard) }
                    .padding(.leading, 16).padding(.trailing, 28).padding(.bottom, 24)
            }
            .refreshable { await load() }
            .frame(maxWidth: .infinity)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) { chartsColumn }
                    .padding(.leading, 28).padding(.trailing, 16).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func accountsColumn(_ dashboard: Dashboard) -> some View {
        if dashboard.cards.isEmpty {
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
        let end = LocalDay.today().endOfMonth.date.formatted(.dateTime.month(.wide).day())
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
