import Foundation
import Testing
@testable import WalletWeatherKit

/// Settings on the iPhone (ios-settings phase 1, #294): every setting and
/// action that was in Settings before still has a place, with a server, on
/// this iPhone and in the demo, and the rows keep one grammar (R20).
struct SettingsLayoutTests {
    let more = TabPage.notIn(TabPage.defaultBar)

    @Test func withAServerEveryRowIsReachable() {
        let layout = SettingsLayout(household: .server, canWrite: true, morePages: more, hasBiometry: true, hasCloudflare: true)
        #expect(layout.groups.map(\.section) == [.connection, .morePages, .household, .thisIPhone, .about])
        #expect(layout.groups.map(\.rows) == [
            [.connection], [.morePages], [.tags, .bankSync, .importCSV],
            [.appearance, .tabBar, .privacyLock, .datesDisplay, .reminders], [.notice, .help, .versions],
        ])
        #expect(layout.rows(on: .connections) == [.savedConnection, .demoConnection, .addServer])
        #expect(layout.rows(on: .connection) == [.connectionName, .address, .signedInAs, .cloudflare, .keep, .openWebApp, .signOut])
        #expect(layout.rows(on: .keep) == [.keepNothing, .keepLastKnown])
        #expect(layout.rows(on: .privacy) == [.lock, .appSwitcher])
        #expect(layout.rows(on: .display) == [.dateFormat, .followAccount])
        #expect(layout.rows(on: .help) == [.showGettingStarted, .privacyPolicy])
        #expect(Set(layout.reachablePages) == [.connections, .connection, .keep, .tags, .bank, .appearance, .tabBar, .privacy, .display, .reminders, .notice, .help])
        #expect(Set(layout.reachableRows) == [
            .connection, .morePages, .tags, .bankSync, .importCSV, .appearance, .tabBar, .privacyLock, .datesDisplay, .reminders,
            .notice, .help, .versions, .savedConnection, .demoConnection, .addServer,
            .connectionName, .address, .signedInAs, .cloudflare, .keep, .openWebApp, .signOut,
            .keepNothing, .keepLastKnown, .bankCard, .looks, .lock, .appSwitcher, .dateFormat, .followAccount, .billsDueTomorrow, .balanceUnder, .newBankLines, .showGettingStarted, .privacyPolicy,
        ])
    }

    @Test func onThisIPhoneEveryRowIsReachable() {
        let layout = SettingsLayout(household: .thisIPhone, canWrite: true, morePages: more, hasBiometry: true)
        #expect(layout.groups.map(\.rows) == [
            [.connection], [.morePages],
            [.tags, .bankSync, .iCloudBackup, .moveToServer, .addAccount, .importCSV],
            [.appearance, .tabBar, .privacyLock, .datesDisplay, .reminders], [.notice, .help, .versions],
        ])
        #expect(layout.rows(on: .connection) == [.aboutThisIPhone, .deleteEverything])
        #expect(layout.rows(on: .backup) == [.syncWithICloud, .backupToICloudDrive, .backupPassphrase])
        #expect(layout.rows(on: .move) == [.copyToServer, .exportForServer, .importServerBackup])
        #expect(layout.rows(on: .display) == [.dateFormat, .followAccount])
        #expect(layout.rows(on: .help) == [.showGettingStarted, .privacyPolicy, .setupGuide])
        #expect(layout.rows(on: .connections) == [.savedConnection, .demoConnection, .addServer])
        #expect(Set(layout.reachablePages) == [.connections, .connection, .tags, .bank, .backup, .move, .appearance, .tabBar, .privacy, .display, .reminders, .notice, .help])
        #expect(Set(layout.reachableRows) == [
            .connection, .morePages, .tags, .bankSync, .iCloudBackup, .moveToServer, .addAccount, .importCSV,
            .appearance, .tabBar, .privacyLock, .datesDisplay, .reminders, .notice, .help, .versions, .savedConnection, .demoConnection, .addServer,
            .aboutThisIPhone, .deleteEverything, .bankCard, .looks, .lock, .appSwitcher, .dateFormat, .followAccount, .billsDueTomorrow, .balanceUnder, .newBankLines,
            .syncWithICloud, .backupToICloudDrive, .backupPassphrase, .copyToServer, .exportForServer, .importServerBackup,
            .showGettingStarted, .privacyPolicy, .setupGuide,
        ])
    }

    @Test func inTheDemoEveryRowIsReachable() {
        let layout = SettingsLayout(household: .demo, canWrite: true, morePages: more, hasBiometry: true)
        #expect(layout.groups.map(\.rows) == [
            [.connection], [.morePages], [.tags, .bankSync, .importCSV],
            [.appearance, .tabBar, .privacyLock, .datesDisplay, .reminders], [.notice, .help, .versions],
        ])
        #expect(layout.rows(on: .connection) == [.aboutDemo])
        // The demo is a row of the list, last (#301): choosing another
        // connection leaves it, so its card and Leave the demo went.
        #expect(layout.rows(on: .connections) == [.savedConnection, .demoConnection, .addServer])
        #expect(layout.rows(on: .display) == [.dateFormat, .followAccount])
        #expect(Set(layout.reachablePages) == [.connections, .connection, .tags, .bank, .appearance, .tabBar, .privacy, .display, .reminders, .notice, .help])
        #expect(Set(layout.reachableRows) == [
            .connection, .morePages, .tags, .bankSync, .importCSV, .appearance, .tabBar, .privacyLock, .datesDisplay, .reminders,
            .notice, .help, .versions, .aboutDemo, .savedConnection, .demoConnection, .addServer, .bankCard, .looks, .lock, .appSwitcher, .dateFormat, .followAccount, .billsDueTomorrow, .balanceUnder, .newBankLines,
            .showGettingStarted, .privacyPolicy,
        ])
    }

    /// What depends on the person and the phone: a read-only token has no
    /// Import a CSV, a phone without Face ID or Touch ID no lock, a server
    /// without Cloudflare no Cloudflare row, and a full tab bar no More pages.
    @Test func rowsComeAndGoWithWhatThePhoneAndTokenCanDo() {
        let readOnly = SettingsLayout(household: .server, canWrite: false, morePages: [], hasBiometry: false)
        #expect(readOnly.groups.map(\.section) == [.connection, .household, .thisIPhone, .about])
        #expect(!readOnly.reachableRows.contains(.importCSV))
        #expect(readOnly.rows(on: .privacy) == [.appSwitcher])
        #expect(!readOnly.rows(on: .connection).contains(.cloudflare))
        // On this iPhone the household is always the person's own.
        #expect(SettingsLayout(household: .thisIPhone, canWrite: false).reachableRows.contains(.importCSV))
    }

    /// R20: a chevron opens a page, red comes last on its page, and no
    /// heading sits over a card of one row with the same name.
    @Test func everyRowKeepsTheGrammar() {
        for row in SettingsRow.allCases where row.kind == .page && row != .morePages {
            #expect(row.opens != nil, "\(row) has a chevron but opens nothing")
        }
        for row in SettingsRow.allCases where row.kind != .page {
            #expect(row.opens == nil, "\(row) opens a page without a chevron")
        }
        for household in SettingsHousehold.allCases {
            let layout = SettingsLayout(household: household, morePages: more, hasCloudflare: true)
            for page in SettingsPage.allCases {
                let rows = layout.rows(on: page)
                if let red = rows.firstIndex(where: { $0.kind == .destructive }) {
                    #expect(rows[red...].allSatisfy { $0.kind == .destructive }, "\(page) has a row after its red one")
                }
            }
            // More pages is a grid of tiles, one for each page, under its heading.
            for group in layout.groups where group.rows.count == 1 && group.rows[0] != .morePages {
                #expect(group.section.title != group.rows[0].title, "\(group.section) heads one row of the same name")
            }
        }
    }

    @Test func debugPathsOpenEachPage() {
        #expect(SettingsPage.debugPath("bank") == [.bank])
        #expect(SettingsPage.debugPath("keep") == [.connection, .keep])
        #expect(SettingsPage.debugPath("connections") == [.connections])
        #expect(SettingsPage.debugPath("connection") == [.connection])
        #expect(SettingsPage.debugPath("weather") == [])
        #expect(SettingsPage.debugPath(nil) == [])
        for name in ["connections", "connection", "bank", "appearance", "privacy", "display", "backup", "move", "help", "keep"] {
            #expect(!SettingsPage.debugPath(name).isEmpty, "\(name)")
        }
    }

    @Test func rowValuesInAFewWords() {
        #expect(SettingsLayout.privacyValue(biometry: "Face ID", lockOn: true) == "Face ID on")
        #expect(SettingsLayout.privacyValue(biometry: "Touch ID", lockOn: false) == "Off")
        #expect(SettingsLayout.privacyValue(biometry: nil, lockOn: false) == "Hidden in the app switcher")
        #expect(SettingsLayout.versions(app: "0.36.0", server: "1.98.0", household: .server) == "WalletWeather 0.36.0, server 1.98.0")
        #expect(SettingsLayout.versions(app: "0.36.0", server: nil, household: .thisIPhone) == "WalletWeather 0.36.0, with no server")
        #expect(SettingsLayout.thisIPhoneDetail(accounts: 1, syncOn: true) == "1 account · iCloud sync on")
        #expect(SettingsLayout.thisIPhoneDetail(accounts: 3, syncOn: false) == "3 accounts · iCloud sync off")
        #expect(SettingsLayout.serverDetail(host: "home.example", email: "a@b.c") == "home.example · a@b.c")
    }

    @Test func bankSyncRowSaysTheStateInAFewWords() {
        let when: (Date) -> String = { _ in "7:22 AM" }
        #expect(BankStatus(enabled: false, connected: false).settingsValue(when: when) == "Off")
        #expect(BankStatus(enabled: true, connected: false).settingsValue(when: when) == "No bank connected")
        #expect(BankStatus(enabled: true, connected: true, needsReconnect: true).settingsValue(when: when) == "Needs reconnecting")
        #expect(BankStatus(enabled: true, connected: true, lastSyncAt: "2026-11-23T12:22:00Z", lastSyncOk: true)
            .settingsValue(when: when) == "1 bank · synced 7:22 AM")
        let two = BankStatus(enabled: true, connected: true, connections: [
            BankConnection(id: 1, provider: "simplefin", providerName: "SimpleFIN", name: "Bank A",
                           lastSyncAt: "2026-11-23T12:22:00Z", lastSyncOk: true),
            BankConnection(id: 2, provider: "teller", providerName: "Teller", name: "Bank B",
                           lastSyncAt: "2026-11-23T11:00:00Z", lastSyncOk: true),
        ])
        #expect(two.settingsValue(when: when) == "2 banks · synced 7:22 AM")
        #expect(BankStatus(enabled: true, connected: true).settingsValue(when: when) == "1 bank · not synced yet")

        var phone = PhoneBankState()
        #expect(phone.settingsValue(connected: false, when: when) == "No bank connected")
        #expect(phone.settingsValue(connected: true, when: when) == "1 bank · not synced yet")
        phone.lastSyncAt = .now
        phone.lastSyncOk = true
        #expect(phone.settingsValue(connected: true, when: when) == "1 bank · synced 7:22 AM")
        phone.needsReconnect = true
        #expect(phone.settingsValue(connected: true, when: when) == "Needs reconnecting")
    }

    // MARK: - The sidebar when the Duo is open (phase 2, #295)

    @Test func everyPageHasASymbolAndALineAboutIt() {
        for household in SettingsHousehold.allCases {
            let layout = SettingsLayout(household: household, morePages: more)
            for page in SettingsPage.allCases {
                #expect(!layout.symbol(of: page).isEmpty, "\(household): \(page) has no symbol")
                let summary = layout.summary(of: page)
                #expect(summary.count > 20 && summary.hasSuffix("."), "\(household): \(page) has no line about it")
            }
        }
        // The connection's page says which household it is.
        let households = SettingsHousehold.allCases.map { SettingsLayout(household: $0) }
        #expect(Set(households.map { $0.symbol(of: .connection) }).count == 3)
        #expect(Set(households.map { $0.summary(of: .connection) }).count == 3)
    }

    @Test func theConnectionsPageIsChosenWhenNoneIs() {
        for household in SettingsHousehold.allCases {
            let layout = SettingsLayout(household: household, morePages: more)
            #expect(layout.defaultEntry == .page(.connections))
            #expect(layout.chosen("") == .page(.connections))
            #expect(layout.chosen("nonsense") == .page(.connections))
            #expect(layout.chosen("appearance") == .page(.appearance))
            #expect(layout.chosen("app.calendar") == .app(.calendar))
            // A connection's page, and Keep on this iPhone under it, are
            // under Connections; a window that kept "connection" before
            // #300 finds Connections.
            #expect(layout.chosen("keep") == .page(.connections))
            #expect(layout.chosen("connection") == .page(.connections))
        }
        // A page this household doesn't have, or an app page now in the tab bar.
        #expect(SettingsLayout(household: .server, morePages: more).chosen("backup") == .page(.connections))
        #expect(SettingsLayout(household: .thisIPhone, morePages: more).chosen("backup") == .page(.backup))
        #expect(SettingsLayout(household: .server, morePages: []).chosen("app.calendar") == .page(.connections))
        #expect(SettingsLayout(household: .server, morePages: []).entry("") == nil)
    }

    @Test func theSidebarHoldsEveryRowOfTheRootList() {
        let layout = SettingsLayout(household: .thisIPhone, canWrite: true, morePages: more)
        #expect(layout.sidebar.map(\.section) == layout.groups.map(\.section))
        #expect(layout.sidebar.map(\.items) == [
            [.open(.page(.connections))],
            more.map { .open(.app($0)) },
            [.open(.page(.tags)), .open(.page(.bank)), .open(.page(.backup)), .open(.page(.move)), .act(.addAccount), .act(.importCSV)],
            [.open(.page(.appearance)), .open(.page(.tabBar)), .open(.page(.privacy)), .open(.page(.display)), .open(.page(.reminders))],
            [.open(.page(.notice)), .open(.page(.help)), .info(.versions)],
        ])
        for household in SettingsHousehold.allCases {
            let layout = SettingsLayout(household: household, canWrite: true, morePages: more)
            // Every page the root list opens is a sidebar row, and each entry
            // comes back from what the window keeps.
            let pages = layout.sidebarEntries.compactMap { entry -> SettingsPage? in
                if case let .page(page) = entry { return page }
                return nil
            }
            #expect(pages == layout.groups.flatMap(\.rows).compactMap(\.opens))
            for entry in layout.sidebarEntries {
                #expect(SettingsEntry(rawValue: entry.rawValue) == entry)
            }
        }
    }

    // MARK: - Connections (connections phase 2, #300)

    /// The card opens Connections, whose saved connections each open their
    /// own page; a server's page has its name, and Keep on this iPhone only
    /// when it's in front.
    @Test func theCardOpensConnectionsAndEachConnectionItsPage() {
        #expect(SettingsRow.connection.opens == .connections)
        #expect(SettingsRow.savedConnection.opens == .connection)
        #expect(SettingsRow.addServer.kind == .action)
        #expect(SettingsRow.connectionName.kind == .field)
        #expect(SettingsLayout.rows(forConnection: .server, inFront: true, hasCloudflare: true)
                == [.connectionName, .address, .signedInAs, .cloudflare, .keep, .openWebApp, .signOut])
        #expect(SettingsLayout.rows(forConnection: .server, inFront: false, hasCloudflare: true)
                == [.connectionName, .address, .signedInAs, .cloudflare, .openWebApp, .signOut])
        #expect(SettingsLayout.rows(forConnection: .server, inFront: false)
                == [.connectionName, .address, .signedInAs, .openWebApp, .signOut])
        #expect(SettingsLayout.rows(forConnection: .thisPhone, inFront: true) == [.aboutThisIPhone, .deleteEverything])
        #expect(SettingsLayout.rows(forConnection: .thisPhone, inFront: false) == [.aboutThisIPhone])
        // The page for the one in front is the connection's page as it was.
        let server = SettingsLayout(household: .server, hasCloudflare: true)
        #expect(server.rows(on: .connection) == SettingsLayout.rows(forConnection: .server, inFront: true, hasCloudflare: true))
        for household in SettingsHousehold.allCases {
            let layout = SettingsLayout(household: household)
            #expect(layout.rows(on: .connections).suffix(2) == [.demoConnection, .addServer])
            #expect(layout.reachablePages.first == .connections)
            #expect(layout.symbol(of: .connections) == "arrow.left.arrow.right.circle")
        }
        // Red comes last on a connection's page, in front or not.
        for front in [true, false] {
            let rows = SettingsLayout.rows(forConnection: .server, inFront: front)
            #expect(rows.last == .signOut)
        }
    }

    @Test func aConnectionsLineSaysWhereAndWho() {
        let home = SavedConnection(connection: Connection(server: URL(string: "https://home.example.com")!, token: "t"),
                                   name: "Home", account: "me@example.com")
        #expect(SettingsLayout.connectionDetail(home) == "home.example.com · me@example.com")
        #expect(SettingsLayout.connectionDetail(home, email: "now@example.com") == "home.example.com · now@example.com")
        var unknown = home
        unknown.account = nil
        #expect(SettingsLayout.connectionDetail(unknown) == "home.example.com")
        let phone = SavedConnection(connection: LocalServer.connection)
        #expect(SettingsLayout.connectionDetail(phone) == "Your household, with no server")
    }
    // MARK: - This iPhone, the demo and the lock (connections phase 3, #301)

    /// Until a household is on the phone, Use on this iPhone and Restore
    /// from an iCloud backup are actions beside Add a server, not a row of
    /// the list (#373); the demo is the last row, with a server, this iPhone
    /// or the demo in front.
    @Test func connectionsListThisIPhoneAndTheDemo() {
        let noHousehold = SettingsLayout(household: .server, hasHousehold: false)
        #expect(noHousehold.rows(on: .connections) == [.savedConnection, .demoConnection, .addServer, .useOnThisPhone, .restoreFromICloud])
        #expect(SettingsLayout(household: .demo, hasHousehold: false).rows(on: .connections)
                == [.savedConnection, .demoConnection, .addServer, .useOnThisPhone, .restoreFromICloud])
        // The household in front is one, whatever was passed.
        #expect(SettingsLayout(household: .thisIPhone, hasHousehold: false).rows(on: .connections)
                == [.savedConnection, .demoConnection, .addServer])
        for household in SettingsHousehold.allCases {
            let rows = SettingsLayout(household: household).rows(on: .connections)
            #expect(rows == [.savedConnection, .demoConnection, .addServer], "\(household)")
            #expect(!rows.contains(.aboutDemo))
        }
        #expect(SettingsRow.useOnThisPhone.kind == .action)
        #expect(SettingsRow.restoreFromICloud.kind == .action)
        #expect(SettingsRow.demoConnection.kind == .choice)
        #expect(SettingsRow.demoConnection.opens == nil)
        #expect(SettingsRow.restoreFromICloud.title == "Restore from an iCloud backup")
    }

    /// When locked, show the demo sits under the lock, only while the lock
    /// is on, with a server, on this iPhone and in the demo.
    @Test func privacyAndLockHasTheDemoSwitchWhileTheLockIsOn() {
        for household in SettingsHousehold.allCases {
            #expect(SettingsLayout(household: household, lockOn: true).rows(on: .privacy) == [.lock, .lockShowsDemo, .appSwitcher])
            #expect(SettingsLayout(household: household, lockOn: false).rows(on: .privacy) == [.lock, .appSwitcher])
            #expect(SettingsLayout(household: household, hasBiometry: false, lockOn: true).rows(on: .privacy) == [.appSwitcher])
            #expect(SettingsLayout(household: household, morePages: more, lockOn: true).reachableRows.contains(.lockShowsDemo))
        }
        #expect(SettingsRow.lockShowsDemo.kind == .toggle)
        #expect(SettingsRow.lockShowsDemo.title == "When locked, show the demo")
    }

    /// Locked in the demo, no connection's own page can be reached.
    @Test func lockedInTheDemoNoConnectionPageOpens() {
        let locked = SettingsLayout(household: .demo, morePages: more, visibility: ConnectionsVisibility(locked: true))
        #expect(locked.reachablePages.contains(.connections))
        #expect(!locked.reachablePages.contains(.connection))
        #expect(!locked.reachablePages.contains(.keep))
        #expect(!locked.reachableRows.contains(.address))
        #expect(!locked.reachableRows.contains(.signOut))
        let open = SettingsLayout(household: .demo, morePages: more)
        #expect(open.reachablePages.contains(.connection))
    }
}
