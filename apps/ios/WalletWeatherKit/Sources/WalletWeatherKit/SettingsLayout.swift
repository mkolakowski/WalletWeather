import Foundation

// Settings on the iPhone (Plans/ios-settings.md, phase 1, #294): a short
// root list (the connection card, More pages, Your household, This iPhone,
// About) whose rows open their own pages. The views draw what this model
// lists, and `SettingsLayoutTests` lists the rows each household shows, so a
// row that goes missing fails a test. On a regular width (the open Duo,
// phase 2, #295) the same rows make a sidebar (`sidebar`) and the chosen
// page stands beside it under a header card (`symbol(of:)`, `summary(of:)`).

/// Which household Settings is for: a server, the one kept on this iPhone,
/// or the demo.
public enum SettingsHousehold: String, CaseIterable, Sendable {
    case server, thisIPhone, demo
}

/// A heading on the root list, in its order. The connection card has none.
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case connection, morePages, household, thisIPhone, about

    public var id: String { rawValue }

    public var title: String? {
        switch self {
        case .connection: nil
        case .morePages: "More pages"
        case .household: "Your household"
        case .thisIPhone: "This iPhone"
        case .about: "About"
        }
    }
}

/// A page a row opens. The raw values are what `WW_DEBUG_SETTINGS` takes
/// (Debug builds).
public enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// `connections` is the list the connection card opens (connections
    /// phase 2, #300); `connection` is one connection's own page, the one
    /// in front's when nothing says which.
    case connections, connection, bank, appearance, privacy, display, backup, move, help, keep, tags, tabBar, notice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .connections: "Connections"
        case .connection: "Connection"
        case .bank: "Bank sync"
        case .appearance: "Appearance"
        case .privacy: "Privacy & lock"
        case .display: "Dates & display"
        case .backup: "iCloud & backup"
        case .move: "Move to a server"
        case .help: "Help & Getting started"
        case .keep: "Keep on this iPhone"
        case .tags: "Tags"
        case .tabBar: "Tab bar"
        case .notice: "Important notice"
        }
    }

    /// The pages to push for `WW_DEBUG_SETTINGS=<page>`: Keep on this
    /// iPhone sits under the connection's page. `connection` opens the one
    /// in front's page, `connections` the list.
    public static func debugPath(_ name: String?) -> [SettingsPage] {
        guard let page = name.flatMap(SettingsPage.init(rawValue:)) else { return [] }
        return page == .keep ? [.connection, .keep] : [page]
    }
}

/// One row of Settings, on the root list or on a page.
public enum SettingsRow: String, CaseIterable, Identifiable, Sendable {
    /// How a row looks and what tapping it does (finding R20): a chevron
    /// opens a page; blue does something now (with ↗ when it leaves the
    /// app); a switch is a switch; a field is typed in; red comes last in
    /// its card.
    public enum Kind: Sendable, Equatable {
        case page, action, link, toggle, choice, field, destructive, info
    }

    // The root list.
    case connection, morePages
    case tags, bankSync, iCloudBackup, moveToServer, addAccount, importCSV
    case appearance, tabBar, privacyLock, datesDisplay
    case notice, help, versions
    // Connections (#300): one row per saved connection, opening its page;
    // On this iPhone before the household is set up, and the demo, last
    // (#301); then Add a server, and Restore from an iCloud backup before
    // the household is set up.
    case savedConnection, useOnThisPhone, demoConnection, addServer, restoreFromICloud
    // The connection's page: a server, this iPhone, the demo. Back to the
    // first screen and Leave the demo went in #301: choosing another
    // connection replaces them.
    case connectionName, address, signedInAs, cloudflare, keep, openWebApp, signOut
    case aboutThisIPhone, deleteEverything
    case aboutDemo
    // Keep on this iPhone.
    case keepNothing, keepLastKnown
    // Bank sync: today's card, as it was.
    case bankCard
    // Appearance.
    case looks
    // Privacy & lock.
    // When locked, show the demo (#301): under the lock, while it's on.
    case lock, lockShowsDemo, appSwitcher
    // Dates & display.
    case dateFormat, followAccount
    // iCloud & backup.
    case syncWithICloud, backupToICloudDrive, backupPassphrase
    // Move to a server.
    case exportForServer, importServerBackup
    // Help & Getting started.
    case showGettingStarted, privacyPolicy, setupGuide

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .connection: "Connection"
        case .morePages: "More pages"
        case .tags: "Tags"
        case .bankSync: "Bank sync"
        case .iCloudBackup: "iCloud & backup"
        case .moveToServer: "Move to a server"
        case .addAccount: "Add an account"
        case .importCSV: "Import a CSV…"
        case .appearance: "Appearance"
        case .tabBar: "Tab bar"
        case .privacyLock: "Privacy & lock"
        case .datesDisplay: "Dates & display"
        case .notice: "Important notice"
        case .help: "Help & Getting started"
        case .versions: "Versions"
        case .savedConnection: "A saved connection"
        case .useOnThisPhone: "Use on this iPhone"
        case .demoConnection: "Demo"
        case .addServer: "Add a server"
        case .restoreFromICloud: "Restore from an iCloud backup"
        case .connectionName: "Name"
        case .address: "Address"
        case .signedInAs: "Signed in as"
        case .cloudflare: "Cloudflare"
        case .keep: "Keep on this iPhone"
        case .openWebApp: "Open the web app"
        case .signOut: "Sign out"
        case .aboutThisIPhone: "On this iPhone"
        case .deleteEverything: "Delete everything on this iPhone"
        case .aboutDemo: "Demo"
        case .keepNothing: "Nothing"
        case .keepLastKnown: "Last-known numbers"
        case .bankCard: "Bank sync"
        case .looks: "Looks"
        case .lock: "Lock with Face ID or Touch ID"
        case .lockShowsDemo: "When locked, show the demo"
        case .appSwitcher: "In the app switcher"
        case .dateFormat: "Date format"
        case .followAccount: "Pages follow the same account"
        case .syncWithICloud: "Sync with iCloud"
        case .backupToICloudDrive: "Back up to iCloud Drive"
        case .backupPassphrase: "Backup passphrase"
        case .exportForServer: "Export for a server"
        case .importServerBackup: "Import a server backup"
        case .showGettingStarted: "Show Getting started again"
        case .privacyPolicy: "Privacy policy"
        case .setupGuide: "How to set up a server"
        }
    }

    public var kind: Kind {
        switch self {
        case .connection, .morePages, .tags, .bankSync, .iCloudBackup, .moveToServer,
             .appearance, .tabBar, .privacyLock, .datesDisplay, .notice, .help, .keep, .savedConnection:
            .page
        case .addServer, .useOnThisPhone, .restoreFromICloud, .addAccount, .importCSV, .showGettingStarted,
             .backupPassphrase, .exportForServer, .importServerBackup:
            .action
        case .openWebApp, .privacyPolicy, .setupGuide:
            .link
        case .lock, .lockShowsDemo, .followAccount, .syncWithICloud, .backupToICloudDrive:
            .toggle
        case .keepNothing, .keepLastKnown, .looks, .dateFormat, .demoConnection:
            .choice
        case .connectionName:
            .field
        case .signOut, .deleteEverything:
            .destructive
        case .versions, .address, .signedInAs, .cloudflare, .aboutThisIPhone, .aboutDemo,
             .bankCard, .appSwitcher:
            .info
        }
    }

    /// The page a chevron row opens. More pages' tiles open the pages
    /// themselves (`TabPage`), so that row has none.
    public var opens: SettingsPage? {
        switch self {
        case .connection: .connections
        case .savedConnection: .connection
        case .tags: .tags
        case .bankSync: .bank
        case .iCloudBackup: .backup
        case .moveToServer: .move
        case .appearance: .appearance
        case .tabBar: .tabBar
        case .privacyLock: .privacy
        case .datesDisplay: .display
        case .notice: .notice
        case .help: .help
        case .keep: .keep
        default: nil
        }
    }

    /// The SF Symbol beside a row of the root list.
    public var symbol: String? {
        switch self {
        case .tags: "tag"
        case .bankSync: "building.columns"
        case .iCloudBackup: "icloud"
        case .moveToServer: "arrow.left.arrow.right.square"
        case .addServer: "plus.circle"
        case .useOnThisPhone: "iphone"
        case .demoConnection: "sparkles"
        case .restoreFromICloud: "icloud.and.arrow.down"
        case .addAccount: "plus.circle"
        case .importCSV: "doc.text"
        case .appearance: "paintpalette"
        case .tabBar: "dock.rectangle"
        case .privacyLock: "lock"
        case .datesDisplay: "calendar"
        case .notice: "doc.plaintext"
        case .help: "questionmark.circle"
        default: nil
        }
    }
}

/// One card of the root list: its section and its rows.
public struct SettingsGroup: Identifiable, Equatable, Sendable {
    public let section: SettingsSection
    public let rows: [SettingsRow]
    public var id: SettingsSection { section }
}

/// What the open Duo's Settings pane shows (phase 2, #295): a Settings page,
/// or one of More pages' app pages. Its raw value is what the window keeps
/// (`settings.page`): the page's own for a Settings page, `app.` and the
/// page's for an app page.
public enum SettingsEntry: Hashable, Identifiable, Sendable {
    case page(SettingsPage)
    case app(TabPage)

    public var id: String { rawValue }

    public var rawValue: String {
        switch self {
        case let .page(page): page.rawValue
        case let .app(page): "app.\(page.rawValue)"
        }
    }

    public init?(rawValue: String) {
        if rawValue.hasPrefix("app.") {
            guard let page = TabPage(rawValue: String(rawValue.dropFirst(4))) else { return nil }
            self = .app(page)
        } else {
            guard let page = SettingsPage(rawValue: rawValue) else { return nil }
            self = .page(page)
        }
    }
}

/// One row of the sidebar: it opens something in the pane, runs an action
/// (Import a CSV, Add an account), or only says something (the versions).
public enum SettingsSidebarItem: Hashable, Identifiable, Sendable {
    case open(SettingsEntry)
    case act(SettingsRow)
    case info(SettingsRow)

    public var id: String {
        switch self {
        case let .open(entry): "open.\(entry.rawValue)"
        case let .act(row): "act.\(row.rawValue)"
        case let .info(row): "info.\(row.rawValue)"
        }
    }

    /// What the row opens in the pane, if anything.
    public var entry: SettingsEntry? {
        if case let .open(entry) = self { return entry }
        return nil
    }
}

/// One section of the sidebar, in the root list's order.
public struct SettingsSidebarGroup: Identifiable, Equatable, Sendable {
    public let section: SettingsSection
    public let items: [SettingsSidebarItem]
    public var id: SettingsSection { section }
}

/// What Settings shows for one household: the root list's cards and each
/// page's rows. Nothing here is stored; the views build it each time.
public struct SettingsLayout: Equatable, Sendable {
    public var household: SettingsHousehold
    /// The person may change things (not a read-only token).
    public var canWrite: Bool
    /// The pages not in the tab bar, for More pages.
    public var morePages: [TabPage]
    /// Face ID, Touch ID or Optic ID is set up, so the lock can be offered.
    public var hasBiometry: Bool
    /// The server is behind Cloudflare Access.
    public var hasCloudflare: Bool
    /// A household is on this iPhone already (#301): without one,
    /// Connections offers Use on this iPhone and Restore from an iCloud
    /// backup.
    public var hasHousehold: Bool
    /// The lock is on: Privacy & lock shows When locked, show the demo.
    public var lockOn: Bool
    /// Locked in the demo (#301): what Connections may reveal.
    public var visibility: ConnectionsVisibility

    public init(household: SettingsHousehold, canWrite: Bool = true, morePages: [TabPage] = [],
                hasBiometry: Bool = true, hasCloudflare: Bool = false, hasHousehold: Bool = true,
                lockOn: Bool = false, visibility: ConnectionsVisibility = ConnectionsVisibility(locked: false)) {
        self.household = household
        self.canWrite = canWrite
        self.morePages = morePages
        self.hasBiometry = hasBiometry
        self.hasCloudflare = hasCloudflare
        // The household on this iPhone in front is one.
        self.hasHousehold = hasHousehold || household == .thisIPhone
        self.lockOn = lockOn
        self.visibility = visibility
    }

    /// The root list, top to bottom. More pages is left out when every page
    /// is in the tab bar.
    public var groups: [SettingsGroup] {
        var groups = [SettingsGroup(section: .connection, rows: [.connection])]
        if !morePages.isEmpty { groups.append(SettingsGroup(section: .morePages, rows: [.morePages])) }
        var household: [SettingsRow] = [.tags, .bankSync]
        switch self.household {
        case .thisIPhone:
            household += [.iCloudBackup, .moveToServer, .addAccount, .importCSV]
        case .server, .demo:
            if canWrite { household.append(.importCSV) }
        }
        groups.append(SettingsGroup(section: .household, rows: household))
        groups.append(SettingsGroup(section: .thisIPhone, rows: [.appearance, .tabBar, .privacyLock, .datesDisplay]))
        groups.append(SettingsGroup(section: .about, rows: [.notice, .help, .versions]))
        return groups
    }

    /// A page's own rows, in order. Tags, Tab bar and the Important notice
    /// are pages of their own, with none listed here.
    public func rows(on page: SettingsPage) -> [SettingsRow] {
        switch page {
        case .connections:
            // The list (#301): the saved connections, On this iPhone until
            // it's set up, the demo last; then the ways to add one.
            return [.savedConnection] + (hasHousehold ? [] : [.useOnThisPhone]) + [.demoConnection, .addServer]
                + (hasHousehold ? [] : [.restoreFromICloud])
        case .connection:
            switch household {
            case .server: return Self.rows(forConnection: .server, inFront: true, hasCloudflare: hasCloudflare)
            case .thisIPhone: return Self.rows(forConnection: .thisPhone, inFront: true)
            case .demo: return [.aboutDemo]
            }
        case .keep: return household == .server ? [.keepNothing, .keepLastKnown] : []
        case .bank: return [.bankCard]
        case .appearance: return [.looks]
        case .display: return [.dateFormat, .followAccount]
        case .privacy: return (hasBiometry ? [.lock] + (lockOn ? [.lockShowsDemo] : []) : []) + [.appSwitcher]
        case .backup: return household == .thisIPhone ? [.syncWithICloud, .backupToICloudDrive, .backupPassphrase] : []
        case .move: return household == .thisIPhone ? [.exportForServer, .importServerBackup] : []
        case .help: return [.showGettingStarted, .privacyPolicy] + (household == .thisIPhone ? [.setupGuide] : [])
        case .tags, .tabBar, .notice: return []
        }
    }

    /// A saved connection's own page, opened from Connections (#300). Its
    /// name and the server's details show for every server; Keep on this
    /// iPhone only for the one in front, whose loading it changes. The
    /// household on this iPhone, when it isn't in front, only says what it
    /// is: Delete everything acts on it in front. Choosing another
    /// connection is how to leave it (#301).
    public static func rows(forConnection kind: SavedConnection.Kind, inFront: Bool,
                            hasCloudflare: Bool = false) -> [SettingsRow] {
        switch kind {
        case .server:
            return [.connectionName, .address, .signedInAs] + (hasCloudflare ? [.cloudflare] : [])
                + (inFront ? [.keep] : []) + [.openWebApp, .signOut]
        case .thisPhone:
            return inFront ? [.aboutThisIPhone, .deleteEverything] : [.aboutThisIPhone]
        }
    }

    // MARK: - The sidebar (phase 2, #295)

    /// The root list as a sidebar, for a regular width (the open Duo): each
    /// card's rows in the same order, More pages' tiles as rows of their
    /// own, a page's row choosing what the pane beside it shows, an action
    /// running as it does on the list.
    public var sidebar: [SettingsSidebarGroup] {
        groups.map { group in
            let items: [SettingsSidebarItem] = group.section == .morePages
                ? morePages.map { .open(.app($0)) }
                : group.rows.map { row in
                    switch row.kind {
                    case .page: row.opens.map { .open(.page($0)) } ?? .info(row)
                    case .action: .act(row)
                    default: .info(row)
                    }
                }
            return SettingsSidebarGroup(section: group.section, items: items)
        }
    }

    /// Everything the sidebar can choose, top to bottom.
    public var sidebarEntries: [SettingsEntry] {
        sidebar.flatMap(\.items).compactMap(\.entry)
    }

    /// What the pane shows when nothing is chosen yet: the first page,
    /// Connections.
    public var defaultEntry: SettingsEntry { sidebarEntries.first ?? .page(.connections) }

    /// The entry a stored value names, when this household's sidebar has it.
    /// A page under another (a connection's page, and Keep on this iPhone
    /// under it) names the one it's under, Connections.
    public func entry(_ stored: String) -> SettingsEntry? {
        guard var entry = SettingsEntry(rawValue: stored) else { return nil }
        if entry == .page(.keep) || entry == .page(.connection) { entry = .page(.connections) }
        return sidebarEntries.contains(entry) ? entry : nil
    }

    /// The entry the pane shows: the stored one, or the first.
    public func chosen(_ stored: String) -> SettingsEntry { entry(stored) ?? defaultEntry }

    /// A page's symbol, on its sidebar row and in its header card.
    public func symbol(of page: SettingsPage) -> String {
        switch page {
        case .connections: "arrow.left.arrow.right.circle"
        case .connection:
            switch household {
            case .server: "server.rack"
            case .thisIPhone: "iphone"
            case .demo: "sparkles"
            }
        case .keep: "tray.and.arrow.down"
        case .bank: "building.columns"
        case .appearance: "paintpalette"
        case .privacy: "lock"
        case .display: "calendar"
        case .backup: "icloud"
        case .move: "arrow.left.arrow.right.square"
        case .help: "questionmark.circle"
        case .tags: "tag"
        case .tabBar: "dock.rectangle"
        case .notice: "doc.plaintext"
        }
    }

    /// One line about a page, under its name in the header card the open
    /// Duo shows above it.
    public func summary(of page: SettingsPage) -> String {
        switch page {
        case .connections: "The servers you're signed in to, this iPhone and the demo, and the one in front. Tap one to switch to it."
        case .connection:
            switch household {
            case .server: "Your server's address, who's signed in, and signing out."
            case .thisIPhone: "Your household, kept on this iPhone with no server to run."
            case .demo: "Sample numbers to try the app with. Nothing you change is saved."
            }
        case .keep: "What this iPhone keeps from your server for when it can't be reached."
        case .bank: "Your bank's lines coming in on their own, and how the last sync went."
        case .appearance: "The app's colours, light or dark, or a theme from the web app."
        case .privacy: "Locking the app, and the numbers hidden in the app switcher."
        case .display: "How dates are written, and whether the pages that pick an account all follow the same one."
        case .backup: "Syncing with iCloud, and the copies kept in iCloud Drive."
        case .move: "Taking your numbers to a server of your own, or bringing them back."
        case .help: "The Getting started card again, and the privacy policy."
        case .tags: "Marks for lines and bills across categories, such as a trip."
        case .tabBar: "Which pages sit in the tab bar, and in what order."
        case .notice: "The notice you agreed to when you started, to read again."
        }
    }

    /// Every page that can be reached from the root list, in the order
    /// they're first met. Locked in the demo, no connection's own page.
    public var reachablePages: [SettingsPage] {
        var pages: [SettingsPage] = []
        var queue = groups.flatMap(\.rows).compactMap(\.opens)
        while !queue.isEmpty {
            let page = queue.removeFirst()
            guard !pages.contains(page) else { continue }
            if page == .connection && !visibility.opensConnectionPages { continue }
            pages.append(page)
            queue += rows(on: page).compactMap(\.opens)
        }
        return pages
    }

    /// Every row that can be reached: the root list's, then each reachable
    /// page's.
    public var reachableRows: [SettingsRow] {
        groups.flatMap(\.rows) + reachablePages.flatMap { rows(on: $0) }
    }

    // MARK: - The words on the rows

    /// Privacy & lock's value on the root list.
    public static func privacyValue(biometry: String?, lockOn: Bool) -> String {
        guard let biometry else { return "Hidden in the app switcher" }
        return lockOn ? "\(biometry) on" : "Off"
    }

    /// The versions line in About.
    public static func versions(app: String, server: String?, household: SettingsHousehold) -> String {
        switch household {
        case .server: "WalletWeather \(app), server \(server ?? "…")"
        case .thisIPhone: "WalletWeather \(app), with no server"
        case .demo: "WalletWeather \(app), in the demo"
        }
    }

    /// The connection card's line under the name for the household on this
    /// iPhone: how many accounts, and whether iCloud sync is on.
    public static func thisIPhoneDetail(accounts: Int?, syncOn: Bool) -> String {
        let sync = syncOn ? "iCloud sync on" : "iCloud sync off"
        guard let accounts else { return sync }
        return "\(accounts) account\(accounts == 1 ? "" : "s") · \(sync)"
    }

    /// The connection card's line under the name for a server: its address
    /// and who's signed in.
    public static func serverDetail(host: String, email: String?) -> String {
        guard let email else { return host }
        return "\(host) · \(email)"
    }

    /// A row's line under its name on Connections (#300): the host and who's
    /// signed in when known; a few words for the household on this iPhone.
    public static func connectionDetail(_ saved: SavedConnection, email: String? = nil) -> String {
        switch saved.kind {
        case .server: serverDetail(host: saved.connection.host, email: email ?? saved.account)
        case .thisPhone: "Your household, with no server"
        }
    }
}

// MARK: - Bank sync's row

extension BankStatus {
    /// Bank sync's value on Settings' root list, in a few words: "2 banks ·
    /// synced 7:22 AM", "Needs reconnecting", "Off", "No bank connected".
    /// `when` writes a time short ("7:22 AM", "Nov 12"). With lines waiting
    /// on the Unmatched list (`unmatched`, from `APIClient.unmatchedCounts`)
    /// it says so instead of the banks and the sync time: "3 to match"; a
    /// bank that needs reconnecting or failed to sync still comes first.
    public func settingsValue(unmatched: Int = 0, when: (Date) -> String) -> String {
        guard enabled else { return "Off" }
        let list = connections ?? []
        guard connected else {
            let shared = shared?.count ?? 0
            if unmatched > 0 { return "\(unmatched) to match" }
            return shared > 0 ? "\(shared) shared account\(shared == 1 ? "" : "s")" : "No bank connected"
        }
        if needsReconnect == true || list.contains(where: { $0.needsReconnect == true }) { return "Needs reconnecting" }
        if list.isEmpty ? lastSyncOk == false : list.contains(where: { $0.lastSyncOk == false }) { return "Last sync failed" }
        if unmatched > 0 { return "\(unmatched) to match" }
        let count = max(list.count, 1)
        let banks = "\(count) bank\(count == 1 ? "" : "s")"
        let times = list.isEmpty ? [lastSyncAt] : list.map(\.lastSyncAt)
        guard let last = times.compactMap({ BankStatus.date($0) }).max() else { return "\(banks) · not synced yet" }
        return "\(banks) · synced \(when(last))"
    }
}

extension PhoneBankState {
    /// Bank sync's value on Settings' root list for the household on this
    /// iPhone (SimpleFIN): its banks counted by name, or "3 to match" with
    /// lines waiting on the Unmatched list.
    public func settingsValue(connected: Bool, when: (Date) -> String) -> String {
        guard connected else { return "No bank connected" }
        if needsReconnect { return "Needs reconnecting" }
        if lastSyncOk == false { return "Last sync failed" }
        if unmatched > 0 { return "\(unmatched) to match" }
        let count = max(Set(bankAccounts.map(\.org).filter { !$0.isEmpty }).count, 1)
        let banks = "\(count) bank\(count == 1 ? "" : "s")"
        guard let lastSyncAt else { return "\(banks) · not synced yet" }
        return "\(banks) · synced \(when(lastSyncAt))"
    }
}
