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
            case .connection: ConnectionPage()
            case .keep: KeepPage()
            case .bank: BankSyncPage()
            case .appearance: AppearancePage()
            case .privacy: PrivacyPage()
            case .display: DatesDisplayPage()
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

    var body: some View {
        let layout = SettingsLayout(household: model.settingsHousehold)
        HStack(spacing: 14) {
            Image(systemName: layout.symbol(of: page))
                .font(.title2)
                .foregroundStyle(Palette.accent)
                .frame(width: 52, height: 52)
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
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A gap between one setting (its card and note) and the next.
private struct Gap: View {
    var body: some View { Color.clear.frame(height: 10).accessibilityHidden(true) }
}

// MARK: - The connection

/// The connection card's page: a server's address, who's signed in,
/// Cloudflare, Keep on this iPhone, Open the web app and Sign out; the
/// household on this iPhone with Back to the first screen and Delete
/// everything; or the demo with Leave the demo.
private struct ConnectionPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var confirmErase = false

    var body: some View {
        SettingsPageFrame(title: title) {
            if model.isDemo {
                demo
            } else if model.isLocal {
                thisIPhone
            } else {
                server
            }
        }
        .confirmationDialog("Sign out of WalletWeather on this iPhone?", isPresented: $confirmSignOut,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOutEndingToken() } }
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
    }

    private var title: String {
        if model.isDemo { return "Demo" }
        if model.isLocal { return "On this iPhone" }
        return model.saved?.name ?? model.connection?.host ?? "Your server"
    }

    @ViewBuilder private var server: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoreRow { Text("Address") } trailing: {
                Text(model.connection?.host ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            if let me = model.me {
                Divider()
                MoreRow { Text("Signed in as \(me.email), \(me.isReadOnly ? "read-only" : "full access")") } trailing: { EmptyView() }
            }
            if let cf = model.connection?.cloudflare {
                Divider()
                MoreRow { Text("Cloudflare") } trailing: { Text(cloudflareText(cf)).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
            }
            Divider()
            NavigationLink(value: SettingsPage.keep) {
                MoreRow { Text("Keep on this iPhone") } trailing: {
                    Text(model.keep.title).foregroundStyle(.secondary)
                    Chevron()
                }
            }
            .buttonStyle(.plain)
        }
        .card()
        if let server = model.connection?.server {
            Gap()
            Link(destination: server) {
                MoreRow { Text("Open the web app").foregroundStyle(Palette.accent) } trailing: { LeavesApp() }
            }
            .card()
            SettingNote("Accounts, categories, budgets, sharing, imports, building reports and backups are set up in the web app.")
        }
        Gap()
        Button(role: .destructive) { confirmSignOut = true } label: {
            MoreRow { Text("Sign out").foregroundStyle(Palette.bad) } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
        .card()
        SettingNote("Signing out ends this iPhone's token on your server, then removes it, the server's address and any kept numbers from this iPhone.")
    }

    @ViewBuilder private var thisIPhone: some View {
        Text("Your household lives on this iPhone, with no server to run, and is included in this iPhone's iCloud or computer backup. Net worth, Budgets, Reports and sharing need a server.")
            .card()
        Gap()
        Button { model.leaveLocal() } label: {
            MoreRow { Text("Back to the first screen").foregroundStyle(Palette.accent) } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .card()
        SettingNote("Back to the first screen keeps your numbers on this iPhone: choose On this iPhone there to open them again.")
        Gap()
        Button(role: .destructive) { confirmErase = true } label: {
            MoreRow { Text("Delete everything on this iPhone").foregroundStyle(Palette.bad) } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .card()
    }

    @ViewBuilder private var demo: some View {
        Text("Sample numbers built into the app. Nothing you change is saved.")
            .card()
        Gap()
        Button { model.leaveDemo() } label: {
            MoreRow { Text("Leave the demo").foregroundStyle(Palette.accent) } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Goes back to the first screen")
        .card()
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

/// Move to a server, for the household on this iPhone: Export for a server
/// and Import a server backup.
private struct MovePage: View {
    var body: some View {
        SettingsPageFrame(title: "Move to a server") {
            MoveRows().card()
            SettingNote("Export for a server saves your numbers as your server's own encrypted backup, for its Settings → Restore. Import a server backup replaces what's on this iPhone with a backup your server made. Tags and bank links aren't kept on this iPhone.")
        }
    }
}

// MARK: - This iPhone

/// Appearance: every look as a tile of previews, the chosen one ringed (#296).
private struct AppearancePage: View {
    var body: some View {
        SettingsPageFrame(title: "Appearance") {
            LookGrid()
            SettingNote("Pick one and the app changes straight away. Match the web app uses the theme you chose in the web app's Settings.")
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
