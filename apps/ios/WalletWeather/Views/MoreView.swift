import SwiftUI
import WalletWeatherKit

/// Settings, the tab that was More until #174: the pages not in the tab bar
/// (#158; Calendar, Net worth, Budgets and Reports as it comes), and nothing
/// that's already in the bar; this phone's settings (the look, the lock,
/// what it keeps and the tab bar); and the server: who's signed in, the web
/// app for everything set up there, the Important notice, the versions and
/// Sign out. Its sections are cards like the other pages' (#159). An admin
/// sees nothing extra here: the Admin pages stay on the web.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.barOnSide) private var barOnSide
    @State private var confirmSignOut = false
    @State private var showingNotice = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let pages = TabPage.notIn(TabPage.shown(settings.tabs, onSide: barOnSide))
                    if !pages.isEmpty {
                        SectionTitle("Other pages")
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                                if index > 0 { Divider() }
                                NavigationLink { page.view(embedded: true) } label: {
                                    MoreRow { Label(page.title, systemImage: page.symbol) } trailing: { Chevron() }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card()
                    }

                    SectionTitle("This phone")
                    VStack(alignment: .leading, spacing: 0) {
                        MoreRow { Text("Appearance") } trailing: {
                            Picker("Appearance", selection: $settings.look) {
                                ForEach(Look.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        if let biometry = settings.biometryName {
                            Divider()
                            Toggle("Lock with \(biometry)", isOn: Binding(
                                get: { settings.lockEnabled },
                                set: { on in Task { await settings.setLock(on) } }))
                                .padding(.vertical, 8)
                        }
                        Divider()
                        MoreRow { Text("Keep on this phone") } trailing: {
                            Picker("Keep on this phone", selection: Binding(get: { model.keep }, set: { model.setKeep($0) })) {
                                ForEach(KeepChoice.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Divider()
                        NavigationLink { TabBarSettingsView() } label: {
                            MoreRow { Text("Tab bar") } trailing: {
                                Text(settings.tabs == TabPage.defaultBar ? "Usual" : settings.tabs.map(\.title).joined(separator: ", "))
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                Chevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 6) {
                        if settings.biometryName != nil {
                            Text("With the lock on, WalletWeather asks when it opens and when you come back after a minute away. The numbers are hidden in the app switcher either way.")
                        } else {
                            Text("The numbers are hidden in the app switcher. Set up Face ID or Touch ID in the phone's Settings to lock the app too.")
                        }
                        switch model.keep {
                        case .nothing:
                            Text("No numbers are kept on this phone, so the app needs a connection to your server.")
                        case .lastKnown:
                            Text("The pages you last loaded are kept on this phone, so they still open, marked with their age, when your server can't be reached. They can't be read while the phone is locked, stay out of iCloud and computer backups, and are deleted when you sign out or choose Nothing.")
                        }
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    SectionTitle("Your server")
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.connection?.host ?? "")
                            if let me = model.me {
                                Text("Signed in as \(me.email), \(me.isReadOnly ? "read-only" : "full access")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        if let cf = model.connection?.cloudflare {
                            Divider()
                            MoreRow { Text("Cloudflare") } trailing: { Text(cloudflareText(cf)).foregroundStyle(.secondary) }
                        }
                        if let server = model.connection?.server {
                            Divider()
                            Link(destination: server) {
                                MoreRow { Text("Open the web app").foregroundStyle(Palette.accent) } trailing: {
                                    Text("accounts, categories, import").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                        Button { showingNotice = true } label: {
                            MoreRow { Text("Important notice").foregroundStyle(Palette.accent) } trailing: { EmptyView() }
                        }
                        Divider()
                        Button(role: .destructive) { confirmSignOut = true } label: {
                            MoreRow { Text("Sign out").foregroundStyle(Palette.bad) } trailing: { EmptyView() }
                        }
                        .disabled(model.busy)
                    }
                    .card()
                    Text("WalletWeather \(AppInfo.version), server \(model.serverVersion?.appVersion ?? "…"). Accounts, categories, budgets, sharing, imports, building reports and backups are set up in the web app. Signing out ends this phone's token on your server, then removes it, the server's address and any kept numbers from the phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar { NewWindowItem(place: .more) }
            .confirmationDialog("Sign out of WalletWeather on this phone?", isPresented: $confirmSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await model.signOutEndingToken() } }
            }
            .sheet(isPresented: $showingNotice) { NoticeReader() }
        }
    }

    private func cloudflareText(_ cf: CloudflareCredential) -> String {
        if cf.isServiceToken { return "Service token" }
        guard let expires = cf.expires else { return "Signed in" }
        return expires < .now ? "Sign-in ended" : "Signed in until \(expires.formatted(date: .omitted, time: .shortened))"
    }
}

/// The Important notice to read again, already agreed to.
struct NoticeReader: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(NoticeView.paragraphs.indices, id: \.self) { Text(NoticeView.paragraphs[$0]) }
                }
                .card()
                .padding(20)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Important notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

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
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { summary(data).padding(.leading, 16).padding(.trailing, 28) }.frame(maxWidth: .infinity)
                        ScrollView { accounts(data).padding(.leading, 28).padding(.trailing, 16) }.frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) { summary(data); accounts(data) }.padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
        }
        .refreshable { await load() }
        .keptBar(kept)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Net worth")
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
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let change = data.change(through: today) {
                    Text("\(change.isNegative ? "" : "+")\(change.formatted) since \(data.start.short)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(change.isNegative ? Palette.bad : Palette.good)
                }
                BalanceChart(points: data.trend)
                if data.window == .month {
                    HStack {
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
                HStack(alignment: .firstTextBaseline) {
                    Text(account.accountName)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(account.actualEnd.formatted).monospacedDigit()
                            .foregroundStyle(Palette.amount(account.actualEnd.isNegative))
                        Text("from \(account.openingBalance.formatted)").font(.caption).foregroundStyle(.secondary)
                    }
                }
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
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { budgeted(data).padding(.leading, 16).padding(.trailing, 28) }.frame(maxWidth: .infinity)
                        ScrollView { unbudgeted(data).padding(.leading, 28).padding(.trailing, 16) }.frame(maxWidth: .infinity)
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
        .task(id: model.generation) { await load() }
    }

    private func budgeted(_ data: BudgetProgress) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Caption(data.label)
                if data.budgeted.isEmpty {
                    Text("No budgets yet. Set them in the web app's Budgets page, and they show here.").font(.callout)
                } else {
                    HStack {
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
                .minimumScaleFactor(0.7).lineLimit(1)
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
            HStack(alignment: .firstTextBaseline) {
                Text(row.categoryName).font(.body.weight(.medium))
                Spacer()
                Text("\(row.spend.formatted) of \(row.budget.formatted)").font(.subheadline.monospacedDigit())
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
                    HStack(spacing: 0) {
                        reportList(list).frame(maxWidth: .infinity)
                        Group {
                            if let chosen {
                                ScrollView { ReportResult(report: chosen).padding(.leading, 28).padding(.trailing, 16) }
                                    .id(chosen.id)
                            } else {
                                ContentUnavailableView("Pick a report", systemImage: "hand.tap",
                                                       description: Text("It runs here."))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    reportList(list)
                }
            }
        }
        .keptBar(kept)
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Reports")
        .task(id: model.generation) { await load() }
    }

    private func reportList(_ list: [SavedReport]) -> some View {
        List(list) { report in
            if sizeClass == .regular {
                Button { chosen = report } label: { row(report) }
                    .listRowBackground(chosen?.id == report.id ? Palette.accent.opacity(0.15) : Color.clear)
            } else {
                NavigationLink {
                    ScrollView { ReportResult(report: report).padding(.horizontal, 16) }
                        .background(PageBackground().ignoresSafeArea())
                        .navigationTitle(report.name)
                        .navigationBarTitleDisplayMode(.inline)
                } label: { row(report) }
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ report: SavedReport) -> some View {
        HStack {
            Text(report.name)
            Spacer()
            if report.pinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned to the Dashboard")
            }
        }
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
                    HStack {
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
        .task(id: model.generation) { await load() }
    }

    private func figure(_ label: String, _ value: Money, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let client = model.client(kept) else { return }
        do { run = .loaded(try await client.runReport(report.id)) } catch { run = .failed(error); kept.clear() }
    }
}

// MARK: - More's rows

/// One row of a More card: what it is on the left, its value or action on
/// the right, tall enough to tap.
private struct MoreRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
    }
}

/// A heading over a Settings card.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.headline).padding(.horizontal, 4).padding(.top, 6)
    }
}
