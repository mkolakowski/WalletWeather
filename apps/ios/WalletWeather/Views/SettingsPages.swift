import SwiftUI
import WalletWeatherKit

// The pages Settings' rows open (Plans/ios-settings.md, phase 1, #294).
// Each note sits directly under the setting it explains (finding R21), and
// the rows keep one grammar (R20): a chevron opens a page, blue does
// something now (↗ when it leaves the app), a switch is a switch, and red
// comes last in its card.

extension EnvironmentValues {
    /// The page the open Duo's Settings pane shows a header card above
    /// (#295); nil on a closed phone and on the pages pushed inside the pane.
    @Entry var settingsHeader: SettingsPage? = nil
}

/// The page for a `SettingsPage`.
struct SettingsPageView: View {
    let page: SettingsPage
    @Environment(\.settingsHeader) private var header

    var body: some View {
        let header = self.header == page ? page : nil
        Group {
            switch page {
            case .connections: ConnectionsPage()
            case .connection: ConnectionPage(id: nil)
            case .keep: KeepPage()
            case .bank: BankSyncPage()
            case .appearance: AppearancePage()
            case .privacy: PrivacyPage()
            case .display: DatesDisplayPage()
            case .reminders: RemindersPage()
            case .backup: BackupPage()
            case .move: MovePage()
            case .help: HelpPage()
            case .tags: TagsPage().modifier(ListHeader(page: header))
            case .tabBar: TabBarSettingsView().modifier(ListHeader(page: header))
            case .notice: NoticePage()
            }
        }
        // Only this page's own frame draws it, not a page pushed from it.
        .environment(\.settingsHeader, header)
    }
}

/// The open Duo's header card at the top of a Settings page (#295): the
/// page's symbol in a larger tile, its name and a line about it, as the
/// Duo's own Settings starts each page.
struct SettingsHeaderCard: View {
    @Environment(AppModel.self) private var model
    let page: SettingsPage
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .title2) private var tile: CGFloat = 52

    var body: some View {
        let layout = SettingsLayout(household: model.settingsHousehold)
        HStack(spacing: 14) {
            Image(systemName: layout.symbol(of: page))
                .font(.title2)
                .foregroundStyle(Palette.accent)
                .frame(width: tile, height: tile)
                .background(Palette.accent.opacity(0.16), in: .rect(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(page == .connection ? model.settingsHouseholdName : page.title)
                    .font(.title3.weight(.semibold))
                Text(layout.summary(of: page))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// The header card above a page that is a list (Tags, Tab bar), held at
/// the top while the list scrolls under it.
private struct ListHeader: ViewModifier {
    let page: SettingsPage?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let page {
                SettingsHeaderCard(page: page).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            }
        }
    }
}

/// A Settings page: cards on the page's background, scrolling, with a
/// small title; under a header card in the open Duo's pane.
private struct SettingsPageFrame<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.settingsHeader) private var header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let header {
                    SettingsHeaderCard(page: header)
                    Gap()
                }
                content
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .debugScrollAnchor()
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// `WW_DEBUG_SCROLL=bottom` (Debug) opens a Settings page or the theme
    /// editor scrolled to its end, for pictures of what's below the first
    /// screen (#297). Nothing in a Release build.
    func debugScrollAnchor() -> some View {
        defaultScrollAnchor(AppModel.debugSetting("WW_DEBUG_SCROLL") == "bottom" ? .bottom : nil)
    }
}

/// A gap between one setting (its card and note) and the next.
private struct Gap: View {
    var body: some View { Color.clear.frame(height: 10).accessibilityHidden(true) }
}

// MARK: - Connections (connections phase 2, #300)

/// A saved connection's own page, pushed from Connections.
struct ConnectionRoute: Hashable {
    let id: UUID
}

/// Connections, opened by the card at the top of Settings: every saved
/// connection, On this iPhone until it's set up, and the demo last, with a
/// tick on the one in front (#301). Tapping another switches to it, signing
/// out of nothing; the ⓘ opens a saved one's own page. Add a server opens
/// the sign-in screen as a sheet; Restore from an iCloud backup sits beside
/// it until a household is on the phone. Locked in the demo, the rows show
/// names and icons only, no connection's page opens, and anything that
/// leaves the demo asks for Face ID first.
private struct ConnectionsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var adding = false
    @State private var restoring = false
    /// A total for each row that has one (#329), read when the page opens.
    @State private var readings: [ConnectionRow.Target: ConnectionTotals.Reading] = [:]

    private var visibility: ConnectionsVisibility { ConnectionsVisibility(locked: settings.lockedInDemo) }

    /// What the totals are read again for: another connection in front, a
    /// change to what's saved, or the lock.
    private struct TotalsKey: Equatable {
        let saved: [SavedConnection]
        let front: LockGate.Front
        let locked: Bool
    }

    private var totalsKey: TotalsKey {
        TotalsKey(saved: model.connections, front: model.lockFront, locked: visibility.locked)
    }

    /// Each connection's total today, as the Dashboard would show it (#329):
    /// a server's from its own kept Dashboard (read the way the pages read
    /// it, only when it keeps Last-known numbers; the one in front too, whose
    /// kept copy is written at each load), the household's and the demo's
    /// worked out on the phone. Nothing is requested from another server,
    /// and while locked in the demo nothing is read at all.
    private func loadTotals() async {
        guard visibility.showsTotals else { readings = [:]; return }
        let saved = model.connections, store = model.store
        let kept = await Task.detached(priority: .utility) {
            var found: [UUID: (total: Money, keptAt: Date)] = [:]
            for connection in saved where connection.kind == .server && connection.keep == .lastKnown {
                if let total = ConnectionTotals.kept(in: store.kept(for: connection.id), server: connection.connection.server) {
                    found[connection.id] = total
                }
            }
            return found
        }.value
        let household = LocalStore.exists || saved.contains { $0.kind == .thisPhone }
            ? await Self.total(of: LocalServer.connection) : nil
        let demo = await Self.total(of: Demo.connection)
        readings = ConnectionTotals.readings(saved: saved, keptTotal: { kept[$0.id] }, household: household, demo: demo)
    }

    private static func total(of connection: Connection) async -> Money? {
        guard let dashboard = try? await APIClient(connection: connection).dashboard() else { return nil }
        return ConnectionTotals.total(of: dashboard)
    }

    private var layoutRows: [SettingsRow] {
        SettingsLayout(household: model.settingsHousehold, hasHousehold: model.hasHousehold,
                       visibility: visibility).rows(on: .connections)
    }

    private var rows: [ConnectionRow] {
        ConnectionRow.rows(saved: model.connections, front: model.lockFront, householdExists: model.hasHousehold,
                           email: model.me?.email, visibility: visibility)
    }

    var body: some View {
        SettingsPageFrame(title: SettingsPage.connections.title) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    ConnectionListRow(row: row, figure: ConnectionTotals.figure(for: row, among: readings,
                                                                                visibility: visibility))
                }
            }
            .card()
            SettingNote(note)
            if let notice = model.connectionsNotice {
                SettingNote(notice)
            }
            if let error = model.connectError, model.phase == .ready {
                SettingNote(error, color: Palette.bad)
            }
            Gap()
            VStack(alignment: .leading, spacing: 0) {
                Button { leaveDemoThen { adding = true } } label: {
                    MoreRow {
                        Label(SettingsRow.addServer.title, systemImage: SettingsRow.addServer.symbol ?? "plus.circle")
                            .foregroundStyle(Palette.accent)
                    } trailing: { EmptyView() }
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                if layoutRows.contains(.restoreFromICloud) {
                    Divider()
                    Button { leaveDemoThen { restoring = true } } label: {
                        MoreRow {
                            Label(SettingsRow.restoreFromICloud.title,
                                  systemImage: SettingsRow.restoreFromICloud.symbol ?? "icloud.and.arrow.down")
                                .foregroundStyle(Palette.accent)
                        } trailing: { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            }
            .card()
            SettingNote(layoutRows.contains(.restoreFromICloud)
                        ? "Add a server signs in to a WalletWeather server and puts it in front. Restore brings back the numbers another iPhone backed up to iCloud Drive, kept on this iPhone."
                        : "Signs in to another WalletWeather server, or to the same one as someone else, and puts it in front.")
        }
        .sheet(isPresented: $adding) { AddServerSheet() }
        .sheet(isPresented: $restoring) { RestoreFromICloudSheet { model.useOnThisPhone() } }
        .onAppear { model.reloadConnections() }
        .task(id: totalsKey) { await loadTotals() }
    }

    private var note: String {
        if visibility.locked {
            return "Choosing one asks for \(settings.biometryName ?? "your passcode") first, then opens it. Its details show once it's open."
        }
        return "Tap one to switch to it. Each keeps its own sign-in, so switching signs you out of nothing."
    }

    /// Adding or restoring leaves the demo: locked there, it asks first.
    private func leaveDemoThen(_ action: @escaping () -> Void) {
        Task { if await model.mayLeaveDemo() { action() } }
    }
}

/// One row of Connections: its icon, name and a line of detail (none for a
/// server while locked in the demo), a tick when it's in front, and for a
/// saved one, the ⓘ to its own page. Tapping the rest switches to it (or,
/// for the saved one in front, opens its page).
private struct ConnectionListRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.settingsIsWide) private var settingsIsWide
    let row: ConnectionRow
    /// Its total today and how old that is; nil when it has none, or while
    /// locked in the demo (#329).
    let figure: ConnectionTotals.Figure?
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .title3) private var infoWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .title3) private var infoHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 34

    private var savedID: UUID? {
        if case let .saved(id) = row.target { return id }
        return nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if row.ticked, row.opensPage, let savedID {
                    NavigationLink(value: ConnectionRoute(id: savedID)) { label }
                } else if row.ticked {
                    label
                } else {
                    Button { Task { await model.choose(row.target) } } label: { label }
                        .disabled(model.busy)
                        .accessibilityHint("Switches to \(row.name)")
                }
            }
            .buttonStyle(.plain)
            if row.opensPage, let savedID {
                NavigationLink(value: ConnectionRoute(id: savedID)) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Palette.accent)
                        .frame(width: infoWidth, height: infoHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(row.name)")
            }
        }
    }

    private var label: some View {
        // Beside the name in the open Duo's wide pane; under it on a closed
        // phone, where the name, the tick and ⓘ leave it too little room, and
        // at large text.
        Group {
            if settingsIsWide {
                FitsAcross {
                    labelRow(totalBelow: false)
                } stacked: {
                    labelRow(totalBelow: true)
                }
            } else {
                labelRow(totalBelow: true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.ticked ? .isSelected : [])
    }

    private func labelRow(totalBelow: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: tile, height: tile)
                .background(Palette.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(totalBelow ? nil : 1)
                    // The sign-in ended: "Sign in again" is the detail below (#302).
                    if row.warning {
                        Image(systemName: ConnectionRow.warningSymbol).font(.footnote).foregroundStyle(Palette.warn)
                            .accessibilityHidden(true)
                    }
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(.footnote).foregroundStyle(row.warning ? Palette.warn : .secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if totalBelow, let figure { totalView(figure, alignment: .leading) }
            }
            Spacer(minLength: 4)
            if !totalBelow, let figure { totalView(figure, alignment: .trailing) }
            if row.ticked {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The total in the money colours, the caption under it (#329).
    private func totalView(_ figure: ConnectionTotals.Figure, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(figure.total.formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.amount(figure.total.isNegative))
            Text(figure.caption).font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
    }
}

// MARK: - The connection

/// A connection's own page: the one in front (`id` nil, or its id), or
/// another saved one, opened from Connections. A server's name (yours to
/// change), address, who's signed in, Cloudflare, Keep on this iPhone (in
/// front only), Open the web app and Sign out of it; the household on this
/// iPhone with Delete everything when it's in front; or the demo. Choosing
/// another connection is how to leave one (#301). Locked in the demo, a
/// saved connection's page shows nothing of it.
struct ConnectionPage: View {
    let id: UUID?
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var confirmErase = false
    @State private var name = ""
    @FocusState private var naming: Bool

    /// The saved connection this page is for, if it's saved.
    private var target: SavedConnection? {
        guard let id else { return model.isDemo ? nil : model.saved }
        return model.connections.first { $0.id == id }
    }

    private var inFront: Bool {
        guard let id else { return true }
        return !model.isDemo && model.saved?.id == id
    }

    /// The front connection's own page when it isn't saved (the demo, a
    /// single sign-in not carried over yet, a Debug launch's server).
    private var unsavedFront: Bool { id == nil && target == nil }

    private var rows: [SettingsRow] {
        if inFront || unsavedFront {
            return SettingsLayout(household: model.settingsHousehold,
                                  hasCloudflare: model.connection?.cloudflare != nil).rows(on: .connection)
                .filter { $0 != .connectionName || target != nil }
        }
        guard let target else { return [] }
        return SettingsLayout.rows(forConnection: target.kind, inFront: false,
                                   hasCloudflare: target.connection.cloudflare != nil)
    }

    var body: some View {
        SettingsPageFrame(title: title) {
            if inFront && model.isDemo {
                demo
            } else if settings.lockedInDemo {
                // A window that had it open when the lock fell due.
                Text("Choose it in Connections to open it. Its details show once it's open.")
                    .foregroundStyle(.secondary).card()
            } else if rows.contains(.aboutThisIPhone) {
                thisIPhone
            } else if rows.contains(.address) {
                server
            } else {
                // Signed out of on another page or window.
                Text("This connection is no longer on this iPhone.").foregroundStyle(.secondary).card()
            }
        }
        .confirmationDialog(signOutTitle, isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(signOutButton, role: .destructive) { signOut() }
        }
        .confirmationDialog("Delete everything on this iPhone?", isPresented: $confirmErase,
                            titleVisibility: .visible) {
            if LocalStore.syncing {
                Button("Delete on this iPhone only", role: .destructive) { model.eraseLocal() }
                Button("Delete everywhere", role: .destructive) { Task { await model.eraseEverywhere() } }
            } else {
                Button("Delete everything", role: .destructive) { model.eraseLocal() }
            }
        } message: {
            Text(LocalStore.syncing
                 ? "On this iPhone only: the synced copy stays in your iCloud and on your other devices, and comes back if you choose On this iPhone again. Everywhere: every account, bill and line is deleted in your iCloud and on every device. Either way your backups stay in iCloud Drive (Files → iCloud Drive → WalletWeather). This can't be undone."
                 : "Every account, bill and line kept on this iPhone is deleted. This can't be undone.")
        }
        .onAppear { name = target?.name ?? "" }
        .onChange(of: target?.name) { _, new in if !naming, let new { name = new } }
        .onChange(of: naming) { _, focused in if !focused { saveName() } }
        .onDisappear { saveName() }
    }

    private var title: String {
        if inFront && model.isDemo { return "Demo" }
        if settings.lockedInDemo { return "Connection" }
        if let target { return target.name }
        if model.isLocal { return "On this iPhone" }
        return model.connection?.host ?? "Your server"
    }

    /// The server this page is for: the saved one's, or the front's.
    private var connection: Connection? { target?.connection ?? (inFront ? model.connection : nil) }

    private var shownName: String { target?.name ?? connection?.host ?? "this server" }

    private var signOutTitle: String { "Sign out of \(shownName) on this iPhone?" }
    private var signOutButton: String { "Sign out of \(shownName)" }

    private func saveName() {
        guard let target, name != target.name else { return }
        model.rename(target.id, to: name)
        if let renamed = model.connections.first(where: { $0.id == target.id }) { name = renamed.name }
    }

    private func signOut() {
        guard let target, target.kind == .server else {
            // Not saved (a single sign-in not carried over, a Debug launch's
            // server): as Sign out always did.
            Task { await model.signOutEndingToken() }
            return
        }
        Task {
            await model.signOut(of: target.id)
            // Back to Connections, where it's gone from the list.
            if model.phase == .ready { dismiss() }
        }
    }

    /// Who's signed in: in front, with what the token may do; otherwise as
    /// last seen in front, when known.
    private var signedIn: String? {
        if inFront, let me = model.me { return "Signed in as \(me.email), \(me.isReadOnly ? "read-only" : "full access")" }
        if !inFront, let account = target?.account { return "Signed in as \(account)" }
        return nil
    }

    @ViewBuilder private var server: some View {
        if rows.contains(.connectionName), target != nil {
            VStack(alignment: .leading, spacing: 0) {
                MoreRow {
                    Text(SettingsRow.connectionName.title)
                } trailing: {
                    TextField(connection.map(SavedConnection.defaultName(for:)) ?? "Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($naming)
                        .onSubmit { saveName() }
                        .accessibilityLabel("Name of this connection")
                }
            }
            .card()
            SettingNote("Shown in Connections and at the top of Settings. Leave it empty for the server's address.")
            Gap()
        }
        VStack(alignment: .leading, spacing: 0) {
            MoreRow { Text("Address") } trailing: {
                Text(connection?.host ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            if let signedIn {
                Divider()
                MoreRow { Text(signedIn) } trailing: { EmptyView() }
            }
            if rows.contains(.cloudflare), let cf = connection?.cloudflare {
                Divider()
                MoreRow { Text("Cloudflare") } trailing: { Text(cloudflareText(cf)).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
            }
            if rows.contains(.keep) {
                Divider()
                NavigationLink(value: SettingsPage.keep) {
                    MoreRow { Text("Keep on this iPhone") } trailing: {
                        Text(model.keep.title).foregroundStyle(.secondary)
                        Chevron()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        if !inFront {
            SettingNote("Keep on this iPhone is set while it's in front: tap it in Connections to switch to it.")
        }
        if let server = connection?.server {
            Gap()
            Link(destination: server) {
                MoreRow { Text("Open the web app").foregroundStyle(Palette.accent) } trailing: { LeavesApp() }
            }
            .card()
            SettingNote("Accounts, categories, budgets, sharing, imports, building reports and backups are set up in the web app.")
        }
        Gap()
        Button(role: .destructive) { confirmSignOut = true } label: {
            MoreRow { Text(target == nil ? "Sign out" : "Sign out of \(shownName)").foregroundStyle(Palette.bad) } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .card()
        SettingNote(target == nil
                    ? "Signing out ends this iPhone's token on your server, then removes it, the server's address and any kept numbers from this iPhone."
                    : "Ends this iPhone's token on that server, then removes its sign-in and any numbers kept for it from this iPhone. Your other connections stay.")
    }

    @ViewBuilder private var thisIPhone: some View {
        Text("Your household lives on this iPhone, with no server to run, and is included in this iPhone's iCloud or computer backup. Net worth, Budgets, Reports and sharing need a server.")
            .card()
        SettingNote(inFront
                    ? "Choosing another connection in Connections keeps your numbers on this iPhone, to open again from there."
                    : "Tap it in Connections to switch to it.")
        if rows.contains(.deleteEverything) {
            Gap()
            Button(role: .destructive) { confirmErase = true } label: {
                MoreRow { Text("Delete everything on this iPhone").foregroundStyle(Palette.bad) } trailing: { EmptyView() }
            }
            .buttonStyle(.plain)
            .card()
        }
    }

    @ViewBuilder private var demo: some View {
        Text("Sample numbers built into the app. Nothing you change is saved.")
            .card()
        SettingNote("Choose another connection in Connections to leave it.")
    }

    private func cloudflareText(_ cf: CloudflareCredential) -> String {
        if cf.isServiceToken { return "Service token" }
        guard let expires = cf.expires else { return "Signed in" }
        return expires < .now ? "Sign-in ended" : "Signed in until \(expires.formatted(date: .omitted, time: .shortened))"
    }
}

/// Keep on this iPhone: Nothing or Last-known numbers for the server in
/// front, each with what it means. Choosing Nothing deletes what's kept.
private struct KeepPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPageFrame(title: "Keep on this iPhone") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(KeepChoice.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { Divider() }
                    Button { model.setKeep(choice) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(choice.title)
                                Spacer()
                                if model.keep == choice {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                }
                            }
                            Text(note(choice)).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(model.keep == choice ? .isSelected : [])
                }
            }
            .card()
        }
    }

    private func note(_ choice: KeepChoice) -> String {
        switch choice {
        case .nothing:
            "No numbers are kept on this iPhone, so the app needs a connection to your server."
        case .lastKnown:
            "The pages you last loaded are kept on this iPhone, so they still open, marked with their age, when your server can't be reached. They can't be read while this iPhone is locked, stay out of iCloud and computer backups, and are deleted when you sign out or choose Nothing."
        }
    }
}

// MARK: - Your household

/// Bank sync: the card that was in Settings, as it was: the server's, or
/// SimpleFIN on this iPhone.
private struct BankSyncPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPageFrame(title: "Bank sync") {
            if model.isLocal {
                // SimpleFIN on this iPhone (#239).
                PhoneBankCard()
            } else {
                BankSyncCard()
                // Email alerts, under the banks (#211).
                MailAlertsCard()
            }
        }
    }
}

/// iCloud & backup, for the household on this iPhone: Sync with iCloud,
/// the iCloud Drive backup and the backup passphrase.
private struct BackupPage: View {
    var body: some View {
        SettingsPageFrame(title: "iCloud & backup") {
            SyncRow().card()
            SettingNote("Sync with iCloud keeps these numbers the same on your iPhones signed in to the same Apple ID, through your own private iCloud, also in the background, so while it's on they stay readable after this iPhone's first unlock; off, they're readable only while it's unlocked, and stay on this iPhone.")
            Gap()
            CloudBackupRows().card()
            SettingNote("Your numbers live only on this iPhone, so WalletWeather keeps a sealed copy in your iCloud Drive (the Files app, WalletWeather folder): at most one a day, when something changed, and the last 14. Restore brings one back on a new iPhone.")
            Gap()
            PassphraseRow().card()
            SettingNote("Backups open with your backup passphrase, which iCloud Keychain keeps for your other devices.")
        }
    }
}

/// Move to a server, for the household on this iPhone: Copy to a server
/// (#328), Export for a server and Import a server backup.
private struct MovePage: View {
    var body: some View {
        SettingsPageFrame(title: "Move to a server") {
            MoveRows().card()
            SettingNote("Copy to a server sends your numbers to a server you're signed in to, adding to what's there or replacing it; this iPhone keeps its copy. Export for a server saves your numbers as your server's own encrypted backup, for its Settings → Restore. Import a server backup replaces what's on this iPhone with a backup your server made. Tags and bank links aren't kept on this iPhone.")
        }
    }
}

// MARK: - This iPhone

/// Appearance: every look as a tile of previews, the chosen one ringed
/// (#296), then My themes (#297).
private struct AppearancePage: View {
    var body: some View {
        SettingsPageFrame(title: "Appearance") {
            LookGrid()
            SettingNote("Pick one and the app changes straight away. Match the web app uses the theme you chose in the web app's Settings.")
            Gap()
            // Themes the person made, under the built-in looks (#297).
            MyThemes()
        }
    }
}

/// Privacy & lock: the lock (with Face ID, Touch ID or Optic ID set up),
/// and the numbers hidden in the app switcher.
private struct PrivacyPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        SettingsPageFrame(title: "Privacy & lock") {
            if let biometry = settings.biometryName {
                Toggle("Lock with \(biometry)", isOn: Binding(
                    get: { settings.lockEnabled },
                    set: { on in Task { await settings.setLock(on) } }))
                    .frame(minHeight: 44)
                    .card()
                SettingNote("With the lock on, WalletWeather asks when it opens and when you come back after a minute away.")
                Gap()
                // Under the lock, while it's on (#301): on by default.
                if settings.lockEnabled {
                    Toggle(SettingsRow.lockShowsDemo.title, isOn: Binding(
                        get: { settings.lockShowsDemo },
                        set: { on in Task { await settings.setLockShowsDemo(on) } }))
                        .frame(minHeight: 44)
                        .card()
                    SettingNote("WalletWeather opens on sample numbers, and your own numbers need \(biometry) to open. Off, it shows a lock screen instead.")
                    Gap()
                }
            }
            MoreRow { Text("In the app switcher") } trailing: { Text("Numbers hidden").foregroundStyle(.secondary) }
                .accessibilityElement(children: .combine)
                .card()
            SettingNote(settings.biometryName != nil
                        ? "The numbers are hidden in the app switcher either way, lock on or off."
                        : "The numbers are hidden in the app switcher. Set up Face ID or Touch ID in the Settings app to lock WalletWeather too.")
        }
    }
}

/// Dates & display: Date format (Follow the web app, Nov 12 or 2026-11-12)
/// and whether the pages that keep an account follow the one picked on any
/// of them (#317). Date pickers and typed dates don't change (#296).
private struct DatesDisplayPage: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private var hasServer: Bool { model.settingsHousehold == .server }

    /// The choice ticked: Follow the web app reads as Nov 12 with no server.
    private var shown: DateFormatChoice {
        !hasServer && settings.dateChoice == .follow ? .short : settings.dateChoice
    }

    var body: some View {
        SettingsPageFrame(title: "Dates & display") {
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsRow.dateFormat.title).font(.headline).padding(.top, 4).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(DateFormatChoice.offered(hasServer: hasServer).enumerated()), id: \.element) { index, choice in
                    if index > 0 { Divider() }
                    Button { settings.dateChoice = choice } label: {
                        HStack {
                            Text(choice.title)
                            Spacer()
                            if shown == choice {
                                Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(shown == choice ? .isSelected : [])
                }
            }
            .card()
            SettingNote(hasServer
                        ? "Follow the web app writes dates the way the web app's Settings does, Nov 12 or 2026-11-12, and Nov 12 when your server is older than 1.98.0. Nov 12 adds the year for other years. Date pickers and the dates you type don't change."
                        : "Pick how dates are written. Nov 12 adds the year for other years. Date pickers and the dates you type don't change.")
            Gap()
            Toggle(SettingsRow.followAccount.title, isOn: Binding(
                get: { settings.pagesFollowAccount },
                set: { settings.pagesFollowAccount = $0 }))
                .frame(minHeight: 44)
                .card()
            SettingNote("Picking an account on Forecast, Bills & income or Calendar shows it on the other two. Off, each page keeps its own.")
        }
    }
}

// MARK: - About

/// Help & Getting started: the Getting started card back on the Dashboard,
/// the privacy policy, and on this iPhone how to set up a server.
private struct HelpPage: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var broughtBack = false

    static let privacyPolicy = URL(string: "https://mkolakowski.github.io/WalletWeather/privacy")!

    var body: some View {
        SettingsPageFrame(title: "Help & Getting started") {
            Button {
                settings.start = GettingStarted()
                broughtBack = true
            } label: {
                MoreRow { Text("Show Getting started again").foregroundStyle(Palette.accent) } trailing: { EmptyView() }
            }
            .buttonStyle(.plain)
            .card()
            SettingNote(broughtBack
                        ? "Getting started is back at the top of the Dashboard."
                        : "Brings the Getting started card back to the top of the Dashboard, with its tasks to do again.")
            Gap()
            VStack(alignment: .leading, spacing: 0) {
                Link(destination: Self.privacyPolicy) {
                    MoreRow { Text("Privacy policy").foregroundStyle(Palette.accent) } trailing: { LeavesApp() }
                }
                if model.isLocal {
                    Divider()
                    Link(destination: Standalone.setupGuide) {
                        MoreRow { Text("How to set up a server").foregroundStyle(Palette.accent) } trailing: { LeavesApp() }
                    }
                }
            }
            .card()
        }
    }
}

/// The Important notice to read again, already agreed to.
struct NoticePage: View {
    @Environment(\.settingsHeader) private var header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let header { SettingsHeaderCard(page: header) }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(NoticeView.paragraphs.indices, id: \.self) { Text(NoticeView.paragraphs[$0]) }
                }
                .card()
            }
            .padding(20)
        }
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Important notice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reminders (#319): three switches, all off to start, each with its note.
/// Turning the first on asks iOS for permission. Bill due tomorrow has its
/// time under it, Balance heading under its account and amount. Reminders
/// are worked out on this iPhone for the connection in front, and their text
/// never carries an amount.
private struct RemindersPage: View {
    @Environment(AppModel.self) private var model
    @State private var accounts: [Account] = []
    @State private var amount: Decimal = ReminderSettings.startAmount.amount

    private var reminders: ReminderCenter { model.reminders }
    private var settings: ReminderSettings { reminders.settings }

    private func toggle(_ row: SettingsRow, _ value: Bool, _ set: @escaping (inout ReminderSettings, Bool) -> Void) -> some View {
        Toggle(row.title, isOn: Binding(get: { value }, set: { on in Task { await reminders.change { set(&$0, on) } } }))
            .frame(minHeight: 44)
    }

    /// The time Bill due tomorrow arrives, as a date today.
    private var billTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: settings.billHour, minute: settings.billMinute, second: 0, of: .now) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            Task { await reminders.change { $0.billHour = parts.hour ?? 9; $0.billMinute = parts.minute ?? 0 } }
        })
    }

    /// The account watched on the connection in front: the one picked, else the first.
    private var watched: Binding<Int> {
        Binding(get: {
            guard let id = model.saved?.id else { return 0 }
            let picked = settings.balanceAccount(for: id)
            return accounts.contains { $0.id == picked } ? picked ?? 0 : accounts.first?.id ?? 0
        }, set: { account in
            guard let id = model.saved?.id else { return }
            Task { await reminders.change { $0.setBalanceAccount(account, for: id) } }
        })
    }

    var body: some View {
        SettingsPageFrame(title: "Reminders") {
            if reminders.denied {
                Text("Notifications are off for WalletWeather. Turn them on in the Settings app → Notifications → WalletWeather, then come back.")
                    .font(.callout).card()
                Gap()
            }
            VStack(spacing: 0) {
                toggle(.billsDueTomorrow, settings.billsOn) { $0.billsOn = $1 }
                if settings.billsOn {
                    Divider()
                    DatePicker("At", selection: billTime, displayedComponents: .hourAndMinute).frame(minHeight: 44)
                }
            }
            .card()
            SettingNote("The day before each bill is due, at this time: \"Rent is due tomorrow\".")
            Gap()
            VStack(spacing: 0) {
                toggle(.balanceUnder, settings.balanceOn) { $0.balanceOn = $1 }
                if settings.balanceOn {
                    if model.saved != nil, !accounts.isEmpty {
                        Divider()
                        Picker("Account", selection: watched) {
                            ForEach(accounts) { Text($0.name).tag($0.id) }
                        }
                        .frame(minHeight: 44)
                    }
                    Divider()
                    HStack {
                        Text("Under")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .onSubmit(saveAmount)
                    }
                    .frame(minHeight: 44)
                }
            }
            .card()
            SettingNote("When this account's forecast first goes under the amount in the next 7 days. Once for each dip.")
            Gap()
            toggle(.newBankLines, settings.bankLinesOn) { $0.bankLinesOn = $1 }.card()
            SettingNote("When bank sync on this iPhone brings in lines that wait to be matched.")
            Gap()
            SettingNote("Reminders are worked out on this iPhone for the connection in front, and none for the demo or a server set to keep Nothing. They name the bill or account, never an amount: press and hold one to see the amount, which stays hidden while your iPhone or WalletWeather is locked.")
        }
        .task(id: model.generation) {
            amount = settings.balanceAmount.amount
            accounts = model.saved == nil ? [] : (try? await model.client?.accounts()) ?? []
        }
        .task { await reminders.refreshPermission() }
        .onChange(of: amount) { _, _ in saveAmount() }
    }

    private func saveAmount() {
        let typed = Money(amount)
        guard typed != settings.balanceAmount else { return }
        Task { await reminders.change { $0.balanceAmount = typed } }
    }
}
