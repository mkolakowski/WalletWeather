import SwiftUI
import WalletWeatherKit

// MARK: - Net worth

/// Net worth: every account added up, with the Month / 30 days / 90 days
/// switch, its chart, and each account. Open, the chart and total sit on the
/// left and the accounts on the right.
struct NetWorthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @SceneStorage("networth.window") private var window: ChartWindow = .month
    @State private var worth: Loadable<NetWorth> = .loading
    @State private var kept = KeptTracker()

    var body: some View {
        Group {
            switch worth {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                if sizeClass == .regular {
                    // Half open like a laptop (#304): the total and chart above, the accounts below.
                    FoldLayout { edges in
                        ScrollView { summary(data).padding(.leading, edges.leading).padding(.trailing, edges.trailing) }
                    } trailing: { edges in
                        ScrollView { accounts(data).padding(.leading, edges.leading).padding(.trailing, edges.trailing) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) { summary(data); accounts(data) }.padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
        }
        .opensForecast()
        .refreshable { await load() }
        .keptBar(kept)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Net worth")
        // One title size on the open Duo (#304), as Dashboard and Forecast.
        .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
        .task(id: "\(model.generation)/\(window.rawValue)") { await load() }
    }

    private func summary(_ data: NetWorth) -> some View {
        let today = LocalDay.today()
        return VStack(alignment: .leading, spacing: 14) {
            Picker("Covers", selection: $window) {
                ForEach(ChartWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                Caption("Net worth today")
                let total = data.total(on: today) ?? data.actualEndTotal
                Text(total.formatted)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.amount(total.isNegative))
                    .wholeFigure(defaultScale: 0.6)
                    // Already the biggest text on the page: it stops growing
                    // where a whole total still fits the card (#311).
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                if let change = data.change(through: today) {
                    Text("\(change.isNegative ? "" : "+")\(change.formatted) since \(data.start.short)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(change.isNegative ? Palette.bad : Palette.good)
                }
                BalanceChart(points: data.trend)
                if data.window == .month {
                    FigureRow {
                        figure("Month-end forecast", data.forecastEndTotal)
                        figure("Month-end actual", data.actualEndTotal)
                    }
                }
                Text("\(data.label) · \(data.start.short) – \(data.end.short)").font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func accounts(_ data: NetWorth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Each account")
            ForEach(data.accounts) { account in
                // Each account opens in Forecast (#305).
                OpenInForecastButton(account: account.accountId) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.accountName)
                            ForecastHint()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(account.actualEnd.formatted).monospacedDigit()
                                .foregroundStyle(Palette.amount(account.actualEnd.isNegative))
                                .wholeFigure()
                            Text("from \(account.openingBalance.formatted)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in Forecast")
                if account.id != data.accounts.last?.id { Divider() }
            }
            Text(data.window == .month ? "At month end, with the month's bills and paychecks as planned." : "At the end of the window.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func figure(_ label: String, _ value: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(value.isNegative))
                .wholeFigure()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        if worth.value?.window != window { worth = .loading }
        do { worth = .loaded(try await client.netWorth(window)) } catch { worth = .failed(error); kept.clear() }
    }
}

// MARK: - Budgets

/// Budgets: this month's spending against each budget, then the categories
/// with spending and no budget. Budgets are set in the web app.
struct BudgetsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var progress: Loadable<BudgetProgress> = .loading
    @State private var kept = KeptTracker()

    var body: some View {
        Group {
            switch progress {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                if sizeClass == .regular {
                    // Half open like a laptop (#304): the budgets above, the unbudgeted list below.
                    FoldLayout { edges in
                        ScrollView { budgeted(data).padding(.leading, edges.leading).padding(.trailing, edges.trailing) }
                    } trailing: { edges in
                        ScrollView { unbudgeted(data).padding(.leading, edges.leading).padding(.trailing, edges.trailing) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) { budgeted(data); unbudgeted(data) }.padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
        }
        .refreshable { await load() }
        .keptBar(kept)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
        .task(id: model.generation) { await load() }
    }

    private func budgeted(_ data: BudgetProgress) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Caption(data.label)
                if data.budgeted.isEmpty {
                    Text("No budgets yet. Set them in the web app's Budgets page, and they show here.").font(.callout)
                } else {
                    FigureRow {
                        figure("Budgeted", data.totals.budget, Palette.text ?? .primary)
                        figure("Spent", data.budgetedSpend, Palette.text ?? .primary)
                        figure(data.budgetedLeft.isNegative ? "Over" : "Left", Money(abs(data.budgetedLeft.amount)),
                               data.budgetedLeft.isNegative ? Palette.bad : Palette.good)
                    }
                }
            }
            .card()
            if !data.budgeted.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(data.budgeted) { BudgetRow(row: $0) }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private func unbudgeted(_ data: BudgetProgress) -> some View {
        if !data.unbudgeted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caption("No budget")
                    Spacer()
                    Text(data.unbudgetedSpend.formatted).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                ForEach(data.unbudgeted) { row in
                    HStack {
                        Circle().fill(Palette.category(row.categoryColor, name: row.categoryName)).frame(width: 8, height: 8)
                        Text(row.categoryName)
                        Spacer()
                        Text(row.spend.formatted).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            .card()
        }
    }

    private func figure(_ label: String, _ value: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                .wholeFigure(defaultScale: 0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do { progress = .loaded(try await client.budgets()) } catch { progress = .failed(error); kept.clear() }
    }
}

/// One budget: spent of budget, a bar, and what's left or how far over.
struct BudgetRow: View {
    let row: BudgetProgress.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let spent = Text("\(row.spend.formatted) of \(row.budget.formatted)").font(.subheadline.monospacedDigit())
            FitsAcross {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.categoryName).font(.body.weight(.medium))
                    Spacer()
                    spent.wholeFigure()
                }
            } stacked: {
                // The larger text sizes: the figures under the name (#311).
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.categoryName).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    spent.fixedSize(horizontal: false, vertical: true)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(row.over ? Palette.bad : Palette.category(row.categoryColor, name: row.categoryName))
                        .frame(width: max(6, geo.size.width * row.fraction))
                }
            }
            .frame(height: 8)
            Text(row.over ? "Over by \(Money(abs(row.remaining.amount)).formatted)" : "\(row.remaining.formatted) left")
                .font(.caption.monospacedDigit())
                .foregroundStyle(row.over ? Palette.bad : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reports

/// Reports: your saved reports, each run for this month (or the range it
/// was saved with). Building or changing one stays on the web. Open, the
/// list stays on the left and the tapped report runs on the right.
struct ReportsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var reports: Loadable<[SavedReport]> = .loading
    @State private var kept = KeptTracker()
    @State private var chosen: SavedReport?
    /// Counts pulls to refresh, so the open report runs again.
    @State private var refreshes = 0

    var body: some View {
        Group {
            switch reports {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(list):
                if list.isEmpty {
                    ContentUnavailableView("No saved reports", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Build and save a report in the web app's Reports page, and it shows here."))
                } else if sizeClass == .regular {
                    // Half open like a laptop (#304): the list above, the report below.
                    FoldLayout { _ in
                        reportList(list)
                    } trailing: { edges in
                        if let chosen {
                            ScrollView {
                                ReportResult(report: chosen, refreshes: refreshes)
                                    .padding(.leading, edges.leading).padding(.trailing, edges.trailing)
                            }
                            .id(chosen.id)
                        } else {
                            ContentUnavailableView("Pick a report", systemImage: "hand.tap",
                                                   description: Text("It runs here."))
                        }
                    }
                } else {
                    reportList(list)
                }
            }
        }
        // Either half, and the list on any iPhone (#304): the list again, and
        // the open report run again.
        .refreshable {
            await load()
            refreshes += 1
        }
        .keptBar(kept)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
        .task(id: model.generation) { await load() }
    }

    /// Plain rows like Bills & income and Search: the page's text colour, a
    /// chevron at the right, and on the open Duo the open report tinted.
    private func reportList(_ list: [SavedReport]) -> some View {
        List(list) { report in
            Group {
                if sizeClass == .regular {
                    Button { chosen = report } label: { row(report, selected: chosen?.id == report.id, chevron: true) }
                        .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        ScrollView { ReportResult(report: report).padding(.horizontal, 16) }
                            .background(PageBackground().ignoresSafeArea())
                            .navigationTitle(report.name)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: { row(report, selected: false, chevron: false) }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// The system draws the chevron of a pushed link itself; the open Duo's
    /// rows are buttons, so they draw their own.
    private func row(_ report: SavedReport, selected: Bool, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Text(report.name).font(.body.weight(.medium)).lineLimit(2)
            Spacer(minLength: 8)
            if report.pinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned to the Dashboard")
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do { reports = .loaded(try await client.savedReports()) } catch { reports = .failed(error); kept.clear() }
    }
}

/// One report, run: its range, income, spending and net, and each group
/// with its bar and count.
struct ReportResult: View {
    @Environment(AppModel.self) private var model
    let report: SavedReport
    /// Runs the report again when it changes (a pull to refresh, #304).
    var refreshes = 0
    @State private var run: Loadable<ReportRun> = .loading
    @State private var kept = KeptTracker()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let keptAt = kept.keptAt { KeptBar(keptAt: keptAt) }
            switch run {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(40)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(data):
                VStack(alignment: .leading, spacing: 8) {
                    Caption(data.rangeLabel)
                    FigureRow {
                        figure("Income", data.totals.actualIncome, Palette.good)
                        figure("Spending", data.totals.actualSpending, Palette.bad)
                        figure("Net", data.totals.actualNet, Palette.amount(data.totals.actualNet.isNegative))
                    }
                    Text("\(data.itemCount) line\(data.itemCount == 1 ? "" : "s") paid so far").font(.caption).foregroundStyle(.secondary)
                }
                .card()
                VStack(alignment: .leading, spacing: 12) {
                    if data.groups.isEmpty { Text("Nothing in this range.").font(.callout) }
                    let biggest = data.groups.map { abs(($0.actualTotal.amount as NSDecimalNumber).doubleValue) }.max() ?? 1
                    ForEach(data.groups) { group in
                        let size = abs((group.actualTotal.amount as NSDecimalNumber).doubleValue)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.name).lineLimit(1)
                                Spacer()
                                Text(group.actualTotal.formatted).monospacedDigit()
                                    .foregroundStyle(group.actualTotal.isNegative ? Palette.bad : Palette.good)
                            }
                            .font(.callout)
                            GeometryReader { geo in
                                Capsule().fill(Palette.category(group.color, name: group.name))
                                    .frame(width: max(4, geo.size.width * (biggest > 0 ? size / biggest : 0)))
                            }
                            .frame(height: 6)
                            Text("\(group.actualCount) paid · \(group.forecastTotal.formatted) planned")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
        .padding(.bottom, 24)
        .task(id: "\(model.generation)/\(refreshes)") { await load() }
    }

    private func figure(_ label: String, _ value: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                .wholeFigure(defaultScale: 0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do { run = .loaded(try await client.runReport(report.id)) } catch { run = .failed(error); kept.clear() }
    }
}

// MARK: - Bank sync

/// Bank sync's state and Sync now (bank-sync phase 5, #197), with each bank
/// connection listed on its own (bank-providers phase 4, #257), and Connect a
/// bank through Teller or Plaid in the sign-in sheet (phase 5, #258), shown
/// only to someone ticked for one of them, and the accounts shared with the
/// person that sync from someone else's connection, each with its own Sync
/// now (sync-access phase 4, #267), and which of Teller and Plaid have the
/// person's own keys, with the server's keys page in the sign-in sheet to add,
/// replace or remove them (own-bank-keys phase 3, #278). Matching accounts, the sync log and the Unmatched list are in the web app.
struct BankSyncCard: View {
    @Environment(AppModel.self) private var model
    private enum Load { case loading, unavailable, failed(String), shown(BankStatus) }
    @State private var load = Load.loading
    /// The connection being synced (0 for the one button of a server that
    /// lists none), so only its button shows the spinner.
    @State private var syncing: Int?
    /// What the last Sync now said, or why it didn't work.
    @State private var outcome: String?
    @State private var outcomeFailed = false
    @State private var connecting = false
    @State private var editingKeys = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch load {
            case .loading:
                HStack(spacing: 8) { ProgressView(); Text("Checking bank sync…").foregroundStyle(.secondary) }
            case .unavailable:
                Text("Bank sync shows here from server \(BankStatus.minimumServer). Update your server, then come back.")
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Text(message).foregroundStyle(.secondary)
                Button("Try again") { Task { await refresh() } }.buttonStyle(.glass)
            case let .shown(status):
                shown(status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task(id: model.generation) { await refresh() }
    }

    @ViewBuilder
    private func shown(_ status: BankStatus) -> some View {
        let rows = status.connectionRows(when: { KeptBar.when($0) })
        let shared = status.shared ?? []
        if rows.isEmpty {
            // Nothing connected, switched off, or a server from before the
            // list (1.70.0 to 1.85.0): one row for the whole. Someone who
            // only has shared accounts to sync skips "No bank connected".
            if status.connected || !status.enabled || shared.isEmpty {
                let summary = status.summary(when: { KeptBar.when($0) })
                summaryView(summary)
                syncButton(summary, connection: nil)
            }
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(row.provider).font(.caption).foregroundStyle(.secondary)
                    }
                    summaryView(row.summary)
                    syncButton(row.summary, connection: row.id)
                }
            }
        }
        if !shared.isEmpty {
            if status.connected || !rows.isEmpty { Divider() }
            Text("Shared accounts that sync").font(.subheadline.weight(.semibold))
            Text("These accounts take lines from someone else's bank connection. You can sync them; only that person can reconnect or disconnect it.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(shared) { account in
                Divider()
                sharedRow(account, enabled: status.enabled)
            }
        }
        let version = model.isDemo ? BankConnect.minimumServer : model.serverVersion?.appVersion
        if BankConnect.offered(status, serverVersion: version, readOnly: model.me?.isReadOnly == true) {
            Button { Task { await connectBank() } } label: {
                HStack(spacing: 8) {
                    if connecting { ProgressView() } else { Image(systemName: "plus") }
                    Text("Connect a bank").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .disabled(connecting || syncing != nil || editingKeys)
        }
        let keyVersion = model.isDemo ? BankKeys.minimumServer : model.serverVersion?.appVersion
        if BankKeys.offered(status, serverVersion: keyVersion, readOnly: model.me?.isReadOnly == true) {
            keysSection(status)
        }
        if let outcome {
            Text(outcome).font(.footnote).foregroundStyle(outcomeFailed ? Palette.bad : .secondary)
        }
    }

    /// One shared account: where its lines come from, how its last sync went,
    /// and Sync now (off while paused, needing a reconnect, its person can't
    /// sign in, or over the day's limit).
    private func sharedRow(_ account: SharedBankAccount, enabled: Bool) -> some View {
        let summary = account.summary(enabled: enabled, when: { KeptBar.when($0) })
        return VStack(alignment: .leading, spacing: 6) {
            Text(account.archived == true ? "\(account.accountName) (archived)" : account.accountName)
                .font(.subheadline.weight(.semibold))
            Text(account.from).font(.caption).foregroundStyle(.secondary)
            summaryView(summary)
            if let count = account.unmatchedCount, count > 0 {
                Text("\(count) line\(count == 1 ? " waits" : "s wait") to be matched, in the web app: Settings → Bank sync.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.me?.isReadOnly != true, summary.canSync || summary.waitText != nil {
                Button { Task { await syncShared(account.accountId) } } label: {
                    HStack(spacing: 8) {
                        if syncing == -account.accountId { ProgressView() }
                        Text("Sync now").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .disabled(syncing != nil || !summary.canSync)
                if let wait = summary.waitText {
                    Text(wait).font(.footnote).foregroundStyle(Palette.warn)
                }
            }
        }
    }

    /// Which of Teller and Plaid have your own keys (never the keys), and the
    /// server's keys page to add, replace or remove them (#278).
    @ViewBuilder
    private func keysSection(_ status: BankStatus) -> some View {
        Divider()
        Text("Your Teller and Plaid keys").font(.subheadline.weight(.semibold))
        ForEach(BankKeys.rows(status)) { row in
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(row.name)
                } icon: {
                    Image(systemName: row.hasKeys ? "key.fill" : "key")
                        .foregroundStyle(row.hasKeys ? Palette.good : .secondary)
                }
                .font(.subheadline)
                Spacer(minLength: 8)
                Text(row.text).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        Text("Each needs keys from a developer account of your own. They're added on your server's page, signed in with a fresh code, and never kept on this iPhone.")
            .font(.footnote).foregroundStyle(.secondary)
        Button { Task { await editKeys() } } label: {
            HStack(spacing: 8) {
                if editingKeys { ProgressView() } else { Image(systemName: "key") }
                Text(BankKeys.buttonTitle(status)).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glass)
        .disabled(editingKeys || connecting || syncing != nil)
    }

    /// The server's keys page in the sign-in sheet (#278); what it hands back
    /// is only whether anything changed.
    private func editKeys() async {
        outcome = nil
        if model.isDemo {
            outcome = "The demo can't save bank keys: it saves nothing."
            outcomeFailed = false
            return
        }
        editingKeys = true
        defer { editingKeys = false }
        let answer = await model.editBankKeys()
        await refresh()
        if let said = BankKeys.outcome(answer) {
            outcome = said.text
            outcomeFailed = said.failed
        }
    }

    /// The server's connect page in the sign-in sheet (#258); what it hands
    /// back is only whether a connection was made, and its number.
    private func connectBank() async {
        outcome = nil
        if model.isDemo {
            outcome = "The demo can't connect a bank: it saves nothing."
            outcomeFailed = false
            return
        }
        connecting = true
        defer { connecting = false }
        let answer = await model.connectBank()
        await refresh()
        var status: BankStatus?
        if case let .shown(now) = load { status = now }
        if let said = BankConnect.outcome(answer, status: status) {
            outcome = said.text
            outcomeFailed = said.failed
        }
    }

    @ViewBuilder
    private func summaryView(_ summary: BankSyncSummary) -> some View {
        Label {
            Text(summary.headline).font(.subheadline.weight(.semibold))
        } icon: {
            switch summary.tone {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
            case .neutral: Image(systemName: "building.columns")
            }
        }
        if let detail = summary.detail {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        if let next = summary.next {
            Text(next).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Sync now for one connection, or for all of a server that lists none.
    @ViewBuilder
    private func syncButton(_ summary: BankSyncSummary, connection: Int?) -> some View {
        if model.me?.isReadOnly != true, summary.canSync || summary.waitText != nil {
            let key = connection ?? 0
            Button { Task { await syncNow(connection) } } label: {
                HStack(spacing: 8) {
                    if syncing == key { ProgressView() }
                    Text("Sync now").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .disabled(syncing != nil || !summary.canSync)
            if let wait = summary.waitText {
                Text(wait).font(.footnote).foregroundStyle(Palette.warn)
            }
        }
    }

    private func refresh() async {
        guard let client = model.client else { return }
        do {
            if let status = try await client.bankStatus() {
                load = .shown(status)
            } else {
                load = .unavailable
            }
        } catch {
            load = .failed(AppModel.describe(error))
        }
    }

    /// Sync now for a shared account; its spinner is keyed by the negative
    /// of its number, so it never clashes with a connection's.
    private func syncShared(_ accountId: Int) async {
        guard let client = model.client else { return }
        syncing = -accountId
        outcome = nil
        defer { syncing = nil }
        do {
            let result = try await client.syncBankNow(account: accountId)
            load = .shown(result.status)
            outcome = "Synced: \(result.account?.lastSyncStatus ?? "done")."
            outcomeFailed = false
        } catch {
            // The server names the person when it's paused or can't sign in.
            if case let .server(_, detail) = error { outcome = detail } else { outcome = AppModel.describe(error) }
            outcomeFailed = true
            await refresh()
        }
    }

    private func syncNow(_ connection: Int?) async {
        guard let client = model.client else { return }
        syncing = connection ?? 0
        outcome = nil
        defer { syncing = nil }
        do {
            let result: BankSyncResult
            if let connection { result = try await client.syncBankNow(connection: connection) } else { result = try await client.syncBankNow() }
            load = .shown(result.status)
            // A connection's own words when one was synced, else the whole's.
            let own = connection.flatMap { id in result.status.connections?.first { $0.id == id }?.lastSyncStatus }
            outcome = "Synced: \(own ?? result.status.lastSyncStatus ?? "done")."
            outcomeFailed = false
        } catch {
            // The server's own words say what went wrong (the limit, a read-only token, the provider down).
            if case let .server(_, detail) = error { outcome = detail } else { outcome = AppModel.describe(error) }
            outcomeFailed = true
            await refresh()
        }
    }
}
