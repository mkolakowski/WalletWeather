import SwiftUI
import WalletWeatherKit

/// Settings, the tab that was More until #174, as a short list whose rows
/// open their own pages (Plans/ios-settings.md, phase 1, #294): the
/// connection card (which household, who's signed in, its state), More pages
/// (the pages not in the tab bar, #158, as tiles), Your household, This
/// iPhone and About. What each household shows is `SettingsLayout`, in the
/// Kit, which its tests check row by row. An admin sees nothing extra here:
/// the Admin pages stay on the web.
///
/// On a regular width (the open Duo, phase 2, #295) the list becomes a
/// sidebar about a third of the width, with the chosen page beside it under
/// a header card, as in the Duo's own Settings: the page crosses the fold
/// rather than splitting at it. Which page is open is kept per window
/// (`settings.page`) and drives both layouts, so closing the Duo on a page
/// shows it pushed on the list, and opening it shows that page chosen. The
/// layout follows the window's width, so there is no setting for it.
extension EnvironmentValues {
    /// True inside the wide window's detail pane, whose size class is forced
    /// to compact: a page there that wants the whole window (the Unmatched
    /// list's two panes, #306) presents itself over it.
    @Entry var settingsIsWide = false
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.barOnSide) private var barOnSide
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The open page's `SettingsEntry` raw value; empty for the list itself.
    @SceneStorage("settings.page") private var openPage = ""
    /// Debug builds: `WW_DEBUG_SETTINGS=<page>` opens that page,
    /// `WW_DEBUG_TAGS=1` Tags and `WW_DEBUG_BANK` or `WW_DEBUG_UNMATCHED`
    /// Bank sync (the latter also opens its Unmatched list), for screenshots.
    @State private var path = NavigationPath(SettingsView.debugPath())
    /// What's pushed inside the open Duo's pane, past the chosen page.
    @State private var panePath = NavigationPath(SettingsView.debugPanePath())
    @State private var started = false
    @State private var addingAccount = false
    @State private var importingCSV = false
    @State private var bankStatus: BankStatus?
    /// Lines waiting on the Unmatched lists, for Bank sync's value (#306).
    @State private var bankUnmatched = 0
    /// Email alerts' state, for the Bank sync row's value (#211).
    @State private var mailStatus: MailStatus?
    @State private var tagCount: Int?
    @State private var accountCount: Int?

    var body: some View {
        let layout = layout
        Group {
            if sizeClass == .regular {
                split(layout)
            } else {
                stack(layout)
            }
        }
        .sheet(isPresented: $addingAccount) { NewAccountSheet { model.accountAdded() } }
        .csvImporter(isPresented: $importingCSV, account: nil) { model.reload() }
        .task(id: model.generation) { await loadValues() }
        .onAppear { start() }
        // The account picker's Manage connections… on another page (#301, #379).
        .onChange(of: model.settingsRequest) { _, page in takeRequest(page) }
        .onChange(of: sizeClass) { old, _ in if old != nil { follow() } }
        // Back on the list (a compact width): no page is open.
        .onChange(of: path.count) { _, count in
            if count == 0, sizeClass != .regular { openPage = "" }
        }
    }

    // MARK: - Closed: the list, each row pushing its page

    private func stack(_ layout: SettingsLayout) -> some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(layout.groups) { group in
                        if let title = group.section.title { SectionTitle(title) }
                        switch group.section {
                        case .connection:
                            ConnectionCard(layout: layout, accounts: accountCount) { open(.page(.connections)) }
                        case .morePages:
                            PageTiles(pages: layout.morePages) { open(.app($0)) }
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
            // Who's in front, and the way to switch: last at the top right, or above a side bar (#379, #391).
            .accountPickerItem { open(.page(.connections)) }
            .toolbar { NewWindowItem(place: .more, besideAccount: true) }
            .navigationDestination(for: SettingsPage.self) { SettingsPageView(page: $0) }
            .navigationDestination(for: ConnectionRoute.self) { ConnectionPage(id: $0.id) }
            .navigationDestination(for: TabPage.self) { $0.view(embedded: true) }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SettingsRow, household: SettingsHousehold) -> some View {
        switch row.kind {
        case .page:
            if let page = row.opens {
                Button { open(.page(page)) } label: {
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
                Text(versions).foregroundStyle(.secondary)
            } trailing: { EmptyView() }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Open: a sidebar and the chosen page

    private func split(_ layout: SettingsLayout) -> some View {
        let chosen = layout.chosen(openPage)
        // The tab bar down the Duo's side is a trailing safe-area inset. It
        // belongs to the pane, which is beside it, not to the sidebar at the
        // other edge (which it squeezed by its width): the row spans the
        // whole window and only the pane keeps clear of the bar.
        return GeometryReader { window in
            let bar = window.safeAreaInsets.trailing
            HStack(spacing: 0) {
                // A plain column, not a navigation stack: a stack here kept
                // the tab bar's inset although it's at the other edge.
                VStack(alignment: .leading, spacing: 0) {
                    // The account picker was at the right of this line; it's with the pane's
                    // buttons now, or above a side bar (#391).
                    Text("Settings").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 12)  // level with the pane's title
                    SettingsSidebar(layout: layout, chosen: chosen, accounts: accountCount, versions: versions,
                                    value: { value(of: $0) }, open: { open($0) }, act: { act($0) })
                }
                .frame(width: min(max((window.size.width + bar) / 3, 250), 340))
                .background {
                    ZStack {
                        PageBackground()
                        Palette.panel.opacity(0.55)
                    }
                    .ignoresSafeArea()
                }
                NavigationStack(path: $panePath) {
                    SettingsPane(entry: chosen)
                        .id(chosen)
                        .accountPickerItem { open(.page(.connections)) }
                        .toolbar { NewWindowItem(place: .more, wideWindow: true, besideAccount: true) }
                        .navigationDestination(for: SettingsPage.self) { SettingsPageView(page: $0) }
                        .navigationDestination(for: ConnectionRoute.self) { ConnectionPage(id: $0.id) }
                        .navigationDestination(for: TabPage.self) { $0.view(embedded: true) }
                }
                // One column in the pane: it's too narrow for a page's two
                // panes, so the pages in it lay out as on a closed phone.
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.settingsIsWide, true)
                .frame(maxWidth: .infinity)
                .safeAreaPadding(.trailing, bar)
            }
            .ignoresSafeArea(.container, edges: .trailing)
        }
        .background(PageBackground().ignoresSafeArea())
    }

    // MARK: - The open page, shared by both

    private func open(_ entry: SettingsEntry) {
        openPage = entry.rawValue
        panePath = NavigationPath()
        path = Self.path(to: entry)
    }

    /// The width changed (the Duo opened or closed): the other layout shows
    /// the same page.
    private func follow() {
        panePath = NavigationPath()
        path = Self.path(to: layout.entry(openPage))
    }

    /// The first time Settings shows: the page `WW_DEBUG_SETTINGS` names, or
    /// the one this window kept, pushed on the list.
    private func start() {
        guard !started else { return }
        started = true
        if let page = model.settingsRequest {
            takeRequest(page)
        } else if let first = Self.debugPath().first {
            openPage = SettingsEntry.page(first).rawValue
        } else if path.isEmpty, let entry = layout.entry(openPage) {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { path = Self.path(to: entry) }
        }
    }

    /// A page asked for from elsewhere (the account picker's Manage
    /// connections…): opened, and the request cleared.
    private func takeRequest(_ page: SettingsPage?) {
        guard let page else { return }
        model.settingsRequest = nil
        open(.page(page))
    }

    private static func path(to entry: SettingsEntry?) -> NavigationPath {
        var path = NavigationPath()
        switch entry {
        case let .page(page)?: path.append(page)
        case let .app(page)?: path.append(page)
        case nil: break
        }
        return path
    }

    private var layout: SettingsLayout {
        SettingsLayout(household: model.settingsHousehold,
                       canWrite: model.me?.isReadOnly != true,
                       morePages: TabPage.notIn(TabPage.shown(settings.tabs, onSide: barOnSide)),
                       hasBiometry: settings.biometryName != nil,
                       hasCloudflare: model.connection?.cloudflare != nil,
                       hasHousehold: model.hasHousehold,
                       lockOn: settings.lockEnabled,
                       visibility: ConnectionsVisibility(locked: settings.lockedInDemo))
    }

    private var versions: String {
        SettingsLayout.versions(app: AppInfo.version, server: model.serverVersion?.appVersion, household: model.settingsHousehold)
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
            return bankStatus?.settingsValue(unmatched: bankUnmatched, mail: mailStatus, when: Self.short)
        case .appearance:
            return settings.look.title
        case .tabBar:
            return settings.tabs == TabPage.defaultBar ? "Usual" : settings.tabs.map(\.title).joined(separator: ", ")
        case .privacyLock:
            return SettingsLayout.privacyValue(biometry: settings.biometryName, lockOn: settings.lockEnabled)
        case .reminders:
            let on = model.reminders.settings
            let count = [on.billsOn, on.balanceOn, on.bankLinesOn].filter { $0 }.count
            return count == 0 ? "Off" : "\(count) on"
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
            bankUnmatched = 0
            mailStatus = nil
        } else {
            mailStatus = try? await client.mailStatus()
            accountCount = nil
            bankStatus = try? await client.bankStatus()
            if let status = bankStatus {
                bankUnmatched = await client.unmatchedCounts(for: status).values.reduce(0, +)
            } else {
                bankUnmatched = 0
            }
        }
    }

    /// A time short enough for a row: "7:22 AM" today, else "Nov 12".
    static func short(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : LocalDay.display(of: date)
    }

    /// What the open Duo's pane pushes past its page for `WW_DEBUG_SETTINGS`:
    /// a connection's page (and Keep under it) sits under Connections, the
    /// pane's page, so all of it; otherwise what's past the first.
    private static func debugPanePath() -> [SettingsPage] {
        let path = debugPath()
        return path.first == .connection ? path : Array(path.dropFirst())
    }

    private static func debugPath() -> [SettingsPage] {
        let named = SettingsPage.debugPath(AppModel.debugSetting("WW_DEBUG_SETTINGS"))
        if !named.isEmpty { return named }
        if AppModel.debugSetting("WW_DEBUG_TAGS") == "1" { return [.tags] }
        if AppModel.debugSetting("WW_DEBUG_COPY") != nil { return [.move] }
        if AppModel.debugSetting("WW_DEBUG_BANK") != nil || AppModel.debugSetting("WW_DEBUG_UNMATCHED") != nil { return [.bank] }
        return []
    }
}

extension AppModel {
    /// Which household Settings is for.
    var settingsHousehold: SettingsHousehold {
        isDemo ? .demo : isLocal ? .thisIPhone : .server
    }

    /// The connection card's name: the server's, On this iPhone, or Demo.
    var settingsHouseholdName: String {
        switch settingsHousehold {
        case .server: saved?.name ?? connection?.host ?? "Your server"
        case .thisIPhone: "On this iPhone"
        case .demo: "Demo"
        }
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
/// state, opening Connections (#300). In the open Duo's sidebar it's
/// compact (a line of detail, no state) and marked when chosen.
private struct ConnectionCard: View {
    @Environment(AppModel.self) private var model
    let layout: SettingsLayout
    let accounts: Int?
    var compact = false
    var chosen = false
    let action: () -> Void
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .title3) private var compactTile: CGFloat = 36
    @ScaledMetric(relativeTo: .title2) private var fullTile: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            HStack(spacing: compact ? 10 : 14) {
                Image(systemName: layout.symbol(of: .connection))
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(Palette.accent)
                    .frame(width: compact ? compactTile : fullTile, height: compact ? compactTile : fullTile)
                    .background(Palette.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.settingsHouseholdName).font(.headline).lineLimit(compact ? 1 : nil)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                    if !compact, let state {
                        Text(state.text).font(.footnote.weight(.semibold)).foregroundStyle(state.good ? Palette.good : Color.secondary)
                    }
                }
                Spacer(minLength: compact ? 0 : 8)
                if !compact { Chevron() }
            }
            .contentShape(Rectangle())
            .card()
            .background { if chosen { shape.fill(Palette.accent.opacity(0.18)) } }
            .overlay { if chosen { shape.strokeBorder(Palette.accent.opacity(0.6), lineWidth: 1.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var detail: String {
        switch layout.household {
        case .server: SettingsLayout.serverDetail(host: model.connection?.host ?? "", email: model.me?.email)
        case .thisIPhone: SettingsLayout.thisIPhoneDetail(accounts: accounts, syncOn: LocalStore.syncOn)
        case .demo: "Sample numbers"
        }
    }

    private var state: (text: String, good: Bool)? {
        switch layout.household {
        case .server:
            guard let me = model.me else { return nil }
            return ("Connected · \(me.isReadOnly ? "read-only" : "full access")", true)
        case .thisIPhone: return nil
        case .demo: return ("Nothing you change is saved", false)
        }
    }
}

// MARK: - The open Duo's sidebar and pane (#295)

/// The root list as a sidebar: the connection card, then every row in the
/// list's order under small section names, each with a tinted symbol tile
/// and its value in small grey text; the chosen row marked. It scrolls on
/// its own.
private struct SettingsSidebar: View {
    @Environment(AppModel.self) private var model
    let layout: SettingsLayout
    let chosen: SettingsEntry
    let accounts: Int?
    let versions: String
    let value: (SettingsRow) -> String?
    let open: (SettingsEntry) -> Void
    let act: (SettingsRow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(layout.sidebar) { group in
                    if group.section == .connection {
                        ConnectionCard(layout: layout, accounts: accounts, compact: true,
                                       chosen: chosen == .page(.connections)) { open(.page(.connections)) }
                            .padding(.bottom, 6)
                    } else {
                        if let title = group.section.title {
                            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.items) { item($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func item(_ item: SettingsSidebarItem) -> some View {
        switch item {
        case let .open(.page(page)):
            let row = layout.groups.flatMap(\.rows).first { $0.opens == page }
            SidebarRow(symbol: layout.symbol(of: page), title: row?.title ?? page.title,
                       detail: row.flatMap(value), chosen: chosen == .page(page)) { open(.page(page)) }
        case let .open(.app(page)):
            let greyed = model.isLocal && page.needsServer
            SidebarRow(symbol: page.symbol, title: page.title, detail: greyed ? "Needs a server" : nil,
                       chosen: chosen == .app(page), greyed: greyed) { open(.app(page)) }
        case let .act(row):
            SidebarRow(symbol: row.symbol ?? "plus.circle", title: row.title, isAction: true) { act(row) }
        case .info:
            Text(versions).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One row of the sidebar: a small rounded tile with the symbol, tinted
/// with the accent, the name and its value under it; a rounded highlight
/// when chosen. An action's name is in the accent, as on the list.
private struct SidebarRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var chosen = false
    var greyed = false
    var isAction = false
    let action: () -> Void
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .subheadline) private var tile: CGFloat = 30

    var body: some View {
        let tint = greyed ? Color.secondary : Palette.accent
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: tile, height: tile)
                    .background(tint.opacity(0.16), in: .rect(cornerRadius: Radius.tile, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(isAction ? Palette.accent : greyed ? Color.secondary : (Palette.text ?? Color.primary))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minHeight: 44)
            .background {
                if chosen { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.accent.opacity(0.18)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The chosen row's page beside the sidebar: a Settings page under its
/// header card, or one of More pages' app pages, with the small title.
private struct SettingsPane: View {
    let entry: SettingsEntry

    var body: some View {
        switch entry {
        case let .page(page):
            SettingsPageView(page: page).environment(\.settingsHeader, page)
        case let .app(page):
            page.view(embedded: true).navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// More pages: the pages not in the tab bar, two across. On this iPhone
/// the ones that need a server stay greyed and marked, opening the note.
private struct PageTiles: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let pages: [TabPage]
    let open: (TabPage) -> Void

    /// Two across; one to a row at the accessibility sizes, where a name
    /// would otherwise break in the middle of a word (#362).
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(pages) { page in
                let greyed = model.isLocal && page.needsServer
                Button { open(page) } label: {
                    // The symbol beside the name, so four pages take two short
                    // rows and the rest of Settings stays on the first screen.
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .foregroundStyle(greyed ? Color.secondary : Palette.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title).font(.subheadline.weight(.semibold)).wrapsAboveLarge().minimumScaleFactor(0.8)
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
    /// Nil: the look's caption colour (`Palette.caption`).
    var color: Color?
    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(color ?? Palette.caption).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
