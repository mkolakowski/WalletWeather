import SwiftUI
import WalletWeatherKit

/// Settings, the tab that was More until #174, as a short list whose rows
/// open their own pages (Plans/ios-settings.md, phase 1, #294): the
/// connection card (which household, who's signed in, its state), More pages
/// (the pages not in the tab bar, #158, as tiles), Your household, This
/// iPhone and About. What each household shows is `SettingsLayout`, in the
/// Kit, which its tests check row by row. An admin sees nothing extra here:
/// the Admin pages stay on the web.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.barOnSide) private var barOnSide
    /// Debug builds: `WW_DEBUG_SETTINGS=<page>` opens that page,
    /// `WW_DEBUG_TAGS=1` Tags and `WW_DEBUG_BANK` Bank sync, for screenshots.
    @State private var path = NavigationPath(SettingsView.debugPath())
    @State private var addingAccount = false
    @State private var importingCSV = false
    @State private var bankStatus: BankStatus?
    @State private var tagCount: Int?
    @State private var accountCount: Int?

    var body: some View {
        let layout = layout
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(layout.groups) { group in
                        if let title = group.section.title { SectionTitle(title) }
                        switch group.section {
                        case .connection:
                            ConnectionCard(household: layout.household, accounts: accountCount)
                        case .morePages:
                            PageTiles(pages: layout.morePages)
                        default:
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(group.rows.enumerated()), id: \.element) { index, row in
                                    if index > 0 { Divider() }
                                    rowView(row, household: layout.household)
                                }
                            }
                            .card()
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar { NewWindowItem(place: .more) }
            .navigationDestination(for: SettingsPage.self) { SettingsPageView(page: $0) }
            .navigationDestination(for: TabPage.self) { $0.view(embedded: true) }
            .sheet(isPresented: $addingAccount) { NewAccountSheet { model.accountAdded() } }
            .csvImporter(isPresented: $importingCSV, account: nil) { model.reload() }
            .task(id: model.generation) { await loadValues() }
        }
    }

    private var household: SettingsHousehold {
        model.isDemo ? .demo : model.isLocal ? .thisIPhone : .server
    }

    private var layout: SettingsLayout {
        SettingsLayout(household: household,
                       canWrite: model.me?.isReadOnly != true,
                       morePages: TabPage.notIn(TabPage.shown(settings.tabs, onSide: barOnSide)),
                       hasBiometry: settings.biometryName != nil,
                       hasCloudflare: model.connection?.cloudflare != nil)
    }

    @ViewBuilder
    private func rowView(_ row: SettingsRow, household: SettingsHousehold) -> some View {
        switch row.kind {
        case .page:
            if let page = row.opens {
                NavigationLink(value: page) {
                    MoreRow { RowLabel(row: row) } trailing: {
                        if let value = value(of: row) {
                            Text(value).lineLimit(1).foregroundStyle(.secondary)
                        }
                        Chevron()
                    }
                }
                .buttonStyle(.plain)
            }
        case .action:
            Button { act(row) } label: {
                MoreRow { RowLabel(row: row).foregroundStyle(Palette.accent) } trailing: { EmptyView() }
            }
            .buttonStyle(.plain)
        default:
            // The versions, as plain text.
            MoreRow {
                Text(SettingsLayout.versions(app: AppInfo.version, server: model.serverVersion?.appVersion, household: household))
                    .foregroundStyle(.secondary)
            } trailing: { EmptyView() }
            .accessibilityElement(children: .combine)
        }
    }

    private func act(_ row: SettingsRow) {
        switch row {
        case .addAccount: addingAccount = true
        case .importCSV: importingCSV = true
        default: break
        }
    }

    /// A row's value on the right: how many tags, bank sync's state, the
    /// look, the tab bar, the lock.
    private func value(of row: SettingsRow) -> String? {
        switch row {
        case .tags:
            return tagCount.map(String.init)
        case .bankSync:
            if model.isLocal {
                return model.phoneBank.state.settingsValue(connected: model.phoneBank.connected, when: Self.short)
            }
            return bankStatus?.settingsValue(when: Self.short)
        case .appearance:
            return settings.look.title
        case .tabBar:
            return settings.tabs == TabPage.defaultBar ? "Usual" : settings.tabs.map(\.title).joined(separator: ", ")
        case .privacyLock:
            return SettingsLayout.privacyValue(biometry: settings.biometryName, lockOn: settings.lockEnabled)
        default:
            return nil
        }
    }

    /// The values the rows show, loaded quietly: a value that can't be
    /// loaded is left off its row.
    private func loadValues() async {
        guard let client = model.client else { return }
        tagCount = (try? await client.tags())?.count
        if model.isLocal {
            accountCount = (try? await client.accounts())?.count
            bankStatus = nil
        } else {
            accountCount = nil
            bankStatus = try? await client.bankStatus()
        }
    }

    /// A time short enough for a row: "7:22 AM" today, else "Nov 12".
    static func short(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func debugPath() -> [SettingsPage] {
        let named = SettingsPage.debugPath(AppModel.debugSetting("WW_DEBUG_SETTINGS"))
        if !named.isEmpty { return named }
        if AppModel.debugSetting("WW_DEBUG_TAGS") == "1" { return [.tags] }
        if AppModel.debugSetting("WW_DEBUG_BANK") != nil { return [.bank] }
        return []
    }
}

/// A root row's name, with its symbol.
private struct RowLabel: View {
    let row: SettingsRow

    var body: some View {
        if let symbol = row.symbol {
            Label(row.title, systemImage: symbol)
        } else {
            Text(row.title)
        }
    }
}

/// The top of Settings: which household this is, a line of detail and its
/// state, opening the connection's page.
private struct ConnectionCard: View {
    @Environment(AppModel.self) private var model
    let household: SettingsHousehold
    let accounts: Int?

    var body: some View {
        NavigationLink(value: SettingsPage.connection) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    if let state {
                        Text(state.text).font(.footnote.weight(.semibold)).foregroundStyle(state.good ? Palette.good : Color.secondary)
                    }
                }
                Spacer(minLength: 8)
                Chevron()
            }
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch household {
        case .server: "server.rack"
        case .thisIPhone: "iphone"
        case .demo: "sparkles"
        }
    }

    private var name: String {
        switch household {
        case .server: model.saved?.name ?? model.connection?.host ?? "Your server"
        case .thisIPhone: "On this iPhone"
        case .demo: "Demo"
        }
    }

    private var detail: String {
        switch household {
        case .server: SettingsLayout.serverDetail(host: model.connection?.host ?? "", email: model.me?.email)
        case .thisIPhone: SettingsLayout.thisIPhoneDetail(accounts: accounts, syncOn: LocalStore.syncOn)
        case .demo: "Sample numbers"
        }
    }

    private var state: (text: String, good: Bool)? {
        switch household {
        case .server:
            guard let me = model.me else { return nil }
            return ("Connected · \(me.isReadOnly ? "read-only" : "full access")", true)
        case .thisIPhone: return nil
        case .demo: return ("Nothing you change is saved", false)
        }
    }
}

/// More pages: the pages not in the tab bar, two across. On this iPhone
/// the ones that need a server stay greyed and marked, opening the note.
private struct PageTiles: View {
    @Environment(AppModel.self) private var model
    let pages: [TabPage]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(pages) { page in
                let greyed = model.isLocal && page.needsServer
                NavigationLink(value: page) {
                    // The symbol beside the name, so four pages take two short
                    // rows and the rest of Settings stays on the first screen.
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .foregroundStyle(greyed ? Color.secondary : Palette.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            if greyed {
                                Text("Needs a server").font(.caption2)
                            }
                        }
                    }
                    .foregroundStyle(greyed ? Color.secondary : (Palette.text ?? Color.primary))
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Settings' rows

/// One row of a Settings card: what it is on the left, its value or action
/// on the right, tall enough to tap.
struct MoreRow<Leading: View, Trailing: View>: View {
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

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// ↗ beside a row that leaves the app.
struct LeavesApp: View {
    var body: some View {
        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
            .accessibilityHidden(true)
    }
}

/// A heading over a Settings card.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.headline).padding(.horizontal, 4).padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A note directly under the setting it explains (finding R21).
struct SettingNote: View {
    let text: String
    var color: Color = .secondary
    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(color).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
