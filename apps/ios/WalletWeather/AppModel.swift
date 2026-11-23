import BackgroundTasks
import CoreData
import Observation
import SwiftUI
import UIKit
import WalletWeatherKit

/// Where sign-in has got to, and the connection the pages use.
///
/// Three ways in (Plans/ios-app.md, phase 1):
/// - **Sign in:** the server's "sign in an app" page in the system's sign-in
///   sheet, which shares Safari's sign-ins, so Cloudflare Access, Google and
///   passkeys work there. The sheet comes back with a one-time code (and the
///   Cloudflare sign-in, when Cloudflare is in front), swapped for a token.
/// - **The "Open in WalletWeather" button** beside a new token in the web
///   app's Settings, which opens `walletweather://connect`.
/// - **Pasting a token.**
/// A Cloudflare service token, under Advanced, can stand in for signing in
/// to Cloudflare.
///
/// Or no server at all (Plans/standalone.md, phase 4, #235): the first
/// screen offers **On this iPhone**, where the household lives in a store on
/// the phone and a local connection (`LocalServer`) answers the pages.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case starting, connect, notice, ready }

    struct PendingLink: Equatable {
        let address: ServerAddress
        let token: String
        var host: String { address.url.host() ?? address.url.absoluteString }
    }

    private(set) var phase: Phase = .starting
    private(set) var connection: Connection?
    private(set) var me: Me?
    private(set) var serverVersion: ServerVersion?
    /// Bumped when the connection changes (a new Cloudflare sign-in), so
    /// pages load again.
    private(set) var generation = 0
    /// The iCloud Drive backup of the household on this iPhone (#237).
    let backup = CloudBackupModel()
    /// Bank sync on this iPhone, without a server (#239): SimpleFIN, its
    /// access address in the Keychain only.
    let phoneBank = AppModel.makePhoneBank()
    /// A CSV to import, from `WW_DEBUG_CSV` (debug builds only).
    var debugCSV: CSVFile?
    /// The first account was just added and the backup isn't decided yet:
    /// the app offers it.
    var offeringBackup = false

    /// What the Connect screen shows while it works, or why it stopped.
    var busy = false
    var connectError: String?
    /// Something the Connect screen should say that isn't a problem (why a
    /// token may still be listed after signing out).
    var connectNotice: String?
    /// The email and password sign-in found two-factor sign-in on: the
    /// Connect screen shows a code field until the sign-in is through (#166).
    var needsTwoFactorCode = false
    /// The server address typed last, kept in memory only.
    var typedAddress = ""
    /// The first screen's choice was Your own server: the sign-in screen
    /// shows. Signing out of a server comes back to it.
    var choseServer = false
    var pendingLink: PendingLink?
    /// An account Search asked Forecast to show (#112); Forecast takes it
    /// and clears it.
    var forecastRequest: Int?

    private let sheet = SignInSheet()

    // MARK: - The saved connections (Plans/connections.md, #299)

    /// The connections the phone keeps, each in its own Keychain item.
    let store: ConnectionStore
    /// The connection in front, when it's saved (not the demo, and not a
    /// Debug launch's server).
    private(set) var saved: SavedConnection?
    /// The single sign-in kept before couldn't be carried over to the store
    /// (its copy didn't write or read back): it's still the one in front,
    /// in its old item, and the next start tries again.
    private var legacy = false

    /// What each window's pages key their choices by (`ScopedToConnection`):
    /// the saved connection's id, `demo`, or `unsaved`.
    var connectionKey: String {
        if let saved { return saved.id.uuidString }
        return isDemo ? "demo" : "unsaved"
    }

    // MARK: - What the phone keeps (#101)

    /// Nothing (the default) or Last-known numbers, per connection. Asked
    /// once at each sign-in; signing out removes it with the connection
    /// (decided 2026-11-15).
    private(set) var keep: KeepChoice = .nothing
    /// The set-up question is due: set by a fresh sign-in.
    var askKeep = false
    /// The connection in front's last-known numbers: its own folder.
    var kept: KeptResponses? {
        if let saved { return store.kept(for: saved.id) }
        if legacy { return store.legacyKept }
        #if DEBUG
        if connection != nil, !isDemo, !isLocal { return Self.debugKept }
        #endif
        return nil
    }

    #if DEBUG
    /// A Debug launch's server (`WW_DEBUG_SERVER`) keeps its numbers in a
    /// temporary folder, not among the saved connections'.
    private static var debugKept: KeptResponses {
        KeptResponses(directory: FileManager.default.temporaryDirectory.appending(path: "ww-debug-kept", directoryHint: .isDirectory))
    }
    #endif

    init(defaults: UserDefaults = .standard, store: ConnectionStore? = nil) {
        self.store = store ?? ConnectionStore(secrets: KeychainConnectionSecrets(), defaults: defaults)
    }

    /// Choosing Nothing deletes what's kept straight away.
    func setKeep(_ choice: KeepChoice) {
        askKeep = false
        keep = choice
        if var saved, saved.keep != choice {
            saved.keep = choice
            if store.update(saved) { self.saved = saved }
        } else if legacy {
            store.legacyKeep = choice
        }
        if choice == .nothing { deleteKept() }
    }

    /// The connection in front's kept numbers, and only its.
    private func deleteKept() {
        if legacy { store.deleteLegacyKept() } else { kept?.deleteAll() }
    }

    /// Puts a saved connection in front (or none), with its keep choice.
    /// Nothing should be on the phone under Nothing: tidies up after a crash
    /// between choosing Nothing and the files going.
    private func bringForward(_ front: SavedConnection?) {
        saved = front
        legacy = false
        keep = front?.keep ?? .nothing
        applyDebugKeep()
        if keep == .nothing { deleteKept() }
    }

    /// Debug only: `WW_DEBUG_KEEP=lastKnown|nothing` sets the choice of the
    /// connection in front, for checking kept numbers from the command line.
    private func applyDebugKeep() {
        guard let debug = Self.debugSetting("WW_DEBUG_KEEP").flatMap(KeepChoice.init(rawValue:)), debug != keep else { return }
        keep = debug
        if var saved {
            saved.keep = debug
            if store.update(saved) { self.saved = saved }
        }
    }

    /// Saves a new connection and puts it in front. Until the connections
    /// can be seen and switched between (phase 2), the phone keeps one at a
    /// time, as before: the others are removed once the new one is saved.
    /// If the Keychain won't take it, it's still in front for this launch.
    private func saveAndBringForward(_ connection: Connection) {
        guard let added = store.add(connection).flatMap({ store.activate($0.id) }) else {
            // A single sign-in still in its old item stays the one in use.
            let stillLegacy = legacy && store.legacy == connection
            bringForward(nil)
            legacy = stillLegacy
            if stillLegacy { keep = store.legacyKeep }
            return
        }
        for other in store.all() where other.id != added.id { store.remove(other.id) }
        if legacy { store.removeLegacy() }
        bringForward(added)
    }

    /// The pages' client for edits and anything not kept. With Last-known
    /// numbers its read requests still keep what they load.
    var client: APIClient? { client(nil) }

    /// A page's client: with Last-known numbers it keeps what it loads, and
    /// answers from that copy when the server can't be reached, telling
    /// `tracker` how old it is.
    func client(_ tracker: KeptTracker?) -> APIClient? {
        guard let connection else { return nil }
        let observer: KeptObserver? = tracker.map { tracker in { @MainActor (date: Date?) in tracker.record(date) } }
        return APIClient(connection: connection, keeper: keep == .lastKnown ? kept : nil, observer: observer)
    }

    /// "Try the demo" (#92): the app on its built-in sample numbers.
    var isDemo: Bool { connection?.isDemo == true }

    /// The household on this iPhone, with no server (#235).
    var isLocal: Bool { connection?.isLocal == true }

    /// On this iPhone: opens the household kept on the phone, setting it up
    /// (with the server's default categories) the first time. Nothing to
    /// sign in to; the Important notice and the lock are offered as after a
    /// first sign-in, and nothing is "kept", since the store is the data.
    func useOnThisPhone() {
        connectError = nil
        connectNotice = nil
        askKeep = false
        do {
            try LocalServer.openShared()
        } catch {
            connectError = "WalletWeather couldn't set up its numbers on this iPhone. \(error.localizedDescription)"
            return
        }
        if saved?.kind != .thisPhone {
            saveAndBringForward(LocalServer.connection)
        }
        connection = LocalServer.connection
        me = nil
        serverVersion = nil
        generation += 1
        phase = .ready
        backup.refresh()
        Task { await refreshMe() }
        Task { await backup.runIfDue() }
        Task { await syncBankIfDue() }
        watchOtherDevices()
    }

    // MARK: Bank sync on this iPhone (#239)

    private static func makePhoneBank() -> PhoneBank {
        #if DEBUG
        // `WW_DEBUG_BANK=1`: a stand-in SimpleFIN and nothing in the
        // Keychain, for screenshots (DebugBridge).
        if debugSetting("WW_DEBUG_BANK") != nil {
            let defaults = UserDefaults(suiteName: "ww-debug-bank")!
            defaults.removePersistentDomain(forName: "ww-debug-bank")
            return PhoneBank(secrets: MemoryBankSecret(), defaults: defaults, session: DebugBridge.session())
        }
        #endif
        return PhoneBank(secrets: KeychainBankSecret())
    }

    /// Syncs the bank when one is due (23½ hours since the last), as the
    /// app opens; the pages load again when lines came in. Then asks iOS for
    /// background time when the next one is due.
    func syncBankIfDue() async {
        guard isLocal, phase == .ready else { return }
        if let result = await phoneBank.syncIfDue(), result.added + result.matched > 0 { generation += 1 }
        scheduleBankRefresh()
    }

    /// iOS's background time (BGAppRefreshTask): the same sync, when the
    /// household on this iPhone is in use and can be read (not while a
    /// locked phone keeps it closed).
    func backgroundBankSync() async {
        guard LocalStore.exists, phoneBank.connected, connection == nil || isLocal,
              UIApplication.shared.isProtectedDataAvailable else { return }
        if let result = await phoneBank.syncIfDue(), result.added + result.matched > 0, isLocal { generation += 1 }
        scheduleBankRefresh()
    }

    /// Asks iOS to wake the app when the next sync is due. iOS decides when.
    func scheduleBankRefresh() {
        guard let next = phoneBank.nextSyncAt() else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: PhoneBank.taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: PhoneBank.taskID)
        request.earliestBeginDate = max(next, .now.addingTimeInterval(15 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    private var otherDevices: Task<Void, Never>?
    private var settling: Task<Void, Never>?

    /// Sync with iCloud (#238): when another device's changes land, join
    /// what both made apart (`reconcile`), then load the pages again. A
    /// burst of changes is waited out first.
    private func watchOtherDevices() {
        guard otherDevices == nil else { return }
        otherDevices = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard let self, self.isLocal else { continue }
                self.settling?.cancel()
                self.settling = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await Task.detached(priority: .utility) { _ = try? LocalServer.openShared().reconcile() }.value
                    self?.reload()
                }
            }
        }
    }

    /// Loads every page again, after a change made outside them (a new
    /// account).
    func reload() { generation += 1 }

    /// An account was added on this iPhone. The first one turns the iCloud
    /// Drive backup on (decided 2026-11-20, #237): at once when a backup
    /// passphrase is already chosen, otherwise by asking for one.
    func accountAdded() {
        reload()
        guard isLocal else { return }
        backup.refresh()
        guard backup.on == nil else { return }
        if BackupPassphrase.load() != nil { backup.setOn(true) } else { offeringBackup = true }
    }

    /// Back to the first screen, leaving the household on the phone: On this
    /// iPhone opens it again.
    func leaveLocal() {
        guard isLocal else { return }
        forgetFront()
        connection = nil
        me = nil
        serverVersion = nil
        choseServer = false
        generation += 1
        phase = .connect
    }

    /// Delete everywhere (#249): the household is emptied in iCloud and on
    /// every device, then on this phone; back to the first screen, which
    /// says how it went.
    func eraseEverywhere() async {
        guard isLocal else { return }
        busy = true
        defer { busy = false }
        let result: Bool?
        do {
            result = try await LocalStore.eraseEverywhere()
        } catch {
            result = nil
        }
        if result != nil { phoneBank.disconnect() }
        leaveLocal()
        switch result {
        case true?: connectNotice = "Deleted everywhere: in your iCloud, on your other devices and on this iPhone. Your backups are still in iCloud Drive."
        case false?: connectNotice = "Deleted on this iPhone. iCloud hasn't confirmed yet: open WalletWeather while connected and the rest is deleted too."
        case nil: connectError = "Nothing could be deleted. Try again."
        }
    }

    /// Deletes everything on this iPhone: the household's store is erased.
    func eraseLocal() {
        guard isLocal else { return }
        leaveLocal()
        LocalStore.erase()
        phoneBank.disconnect()
    }

    /// Opens the demo: no server, nothing saved in the Keychain and nothing
    /// kept, and none of a sign-in's set-up (the notice, what to keep, the
    /// lock).
    func tryDemo() {
        connectError = nil
        connectNotice = nil
        askKeep = false
        saved = nil
        connection = Demo.connection
        me = nil
        generation += 1
        phase = .ready
        Task { await refreshMe() }
    }

    /// Leaves the demo for the Connect screen, keeping what was typed there.
    func leaveDemo() {
        guard isDemo else { return }
        connection = nil
        me = nil
        serverVersion = nil
        generation += 1
        phase = .connect
    }

    /// Whether this person may change lines on `account`: an account they
    /// own or may edit, under a token that isn't read-only. Until `/api/me`
    /// has said what the token may do, nothing is editable.
    func canEdit(_ account: Account) -> Bool {
        guard let me else { return false }
        return account.canEdit && !me.isReadOnly
    }

    /// A Debug-only launch setting, for screenshots from the command line
    /// (`SIMCTL_CHILD_<name>=…`): `WW_DEBUG_PLACE` (forecast, search, …),
    /// `WW_DEBUG_OPEN_LINE` (a Forecast line's or a bill's name, opened in
    /// the editor), `WW_DEBUG_SEARCH` (search text), and `WW_DEBUG_ACCOUNT`
    /// and `WW_DEBUG_DAY` (the Calendar's account and day), and
    /// `WW_DEBUG_KEEP` (what the phone keeps), `WW_DEBUG_LOOK` (the look),
    /// and `WW_DEBUG_CONFIRM`, `WW_DEBUG_COMPARE` and `WW_DEBUG_NEW_WINDOW`
    /// (Forecast's To confirm, Compare, and a second window on a page), and
    /// `WW_DEBUG_DEMO=1` (open in the demo), and `WW_DEBUG_CLOUDKIT_SCHEMA=1`
    /// (write the CloudKit schema to Development, #270).
    /// Always nil in a
    /// Release build.
    static func debugSetting(_ name: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// `WW_DEBUG_IMPORT` and `WW_DEBUG_EXPORT`: what Import a server backup
    /// and Export for a server do, without the file pickers. What happened
    /// is written to `debug-import.txt` beside the files.
    private static func debugImport(_ file: String, export: String?, passphrase: String?) async {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var log = ""
        LocalStore.erase()
        do {
            let server = try LocalServer.openShared()
            try? await APIClient(connection: LocalServer.connection).acknowledgeNotice()
            let data = try Data(contentsOf: documents.appending(path: file))
            let opened = try BackupFile.open(data, passphrase: passphrase)
            let summary = try server.importBackup(opened.payload)
            log += "imported \(summary) encrypted=\(opened.encrypted)\n"
            if let export, let passphrase {
                try BackupFile.seal(try server.backupPayload(), passphrase: passphrase).write(to: documents.appending(path: export))
                log += "exported \(export)\n"
            }
        } catch {
            log += "failed: \(error)\n"
        }
        try? Data(log.utf8).write(to: documents.appending(path: "debug-import.txt"))
    }

    /// A fresh household for screenshots (`WW_DEBUG_LOCAL`), made through
    /// the same calls the pages make.
    private static func debugHousehold(sample: Bool) async {
        LocalStore.erase()
        guard (try? LocalServer.openShared()) != nil else { return }
        let client = APIClient(connection: LocalServer.connection)
        try? await client.acknowledgeNotice()
        guard sample else { return }
        let today = LocalDay.today()
        guard let checking = try? await client.createAccount(AccountBody(name: "Checking", startingBalance: 2450, startingDate: YearMonth(today).start)).id,
              let savings = try? await client.createAccount(AccountBody(name: "Savings", startingBalance: 8000, startingDate: YearMonth(today).start)).id
        else { return }
        let categories = (try? await client.categories()) ?? []
        func category(_ name: String) -> Int? { categories.first { $0.name == name }?.id }
        let holiday = try? await client.createTag(name: "Holiday", color: "#d29922")
        let work = try? await client.createTag(name: "Work", color: "#58a6ff")
        for (name, amount, day, income, cat) in [("Rent", "1450", 1, false, "Rent/Mortgage"), ("Paycheck", "2100", 15, true, "Income"),
                                                 ("Phone", "65.43", 21, false, "Utilities"), ("Streaming", "15.99", 8, false, "Subscriptions")] {
            var bill = BillDraft(today: today)
            bill.name = name
            bill.amountText = amount
            bill.kind = income ? .income : .spending
            bill.dayOfMonth = day
            bill.categoryId = category(cat)
            if name == "Phone", let work { bill.tagIds = [work.id] }
            try? await client.addRecurring(bill, account: checking)
        }
        for (name, amount, back) in [("Groceries", "84.20", 2), ("Coffee", "4.75", 1)] {
            var line = NewTransactionDraft(today: today.adding(days: -back))
            line.name = name
            line.amountText = amount
            line.categoryId = category(name == "Coffee" ? "Dining" : "Groceries")
            if name == "Coffee" { line.tagIds = [holiday?.id, work?.id].compactMap { $0 } }
            try? await client.add(line, account: checking)
        }
        if let holiday { try? await client.createTagRule(TagRuleBody(name: "Trips", descriptionPattern: "hotel", tagId: holiday.id)) }
        var move = MoveMoneyDraft(today: today, from: checking, to: savings)
        move.amountText = "200"
        if let body = TransferBody(move) { _ = try? await client.moveMoney(body) }
    }
    #endif

    #if DEBUG
    /// `WW_DEBUG_BANK=connected` or `unmatched` (with `WW_DEBUG_LOCAL`):
    /// connects the stand-in SimpleFIN, matches its checking account to the
    /// first account from 30 days back, and syncs; `unmatched` also opens
    /// the Unmatched list (PhoneBankCard). `WW_DEBUG_BANK=1` only swaps in
    /// the stand-in, for the card before connecting.
    private func debugBank() async {
        guard let mode = Self.debugSetting("WW_DEBUG_BANK"), mode != "1" else { return }
        try? await phoneBank.connect(token: DebugBridge.token)
        guard let first = try? await APIClient(connection: LocalServer.connection).accounts().first else { return }
        phoneBank.link("debug-checking", to: first.id, start: LocalDay.today().adding(days: -30))
        _ = try? await phoneBank.sync()
    }
    #endif

    /// The name this phone's token is given when signing in through the
    /// sheet, shown in the web app's Settings → API tokens (#155). iOS only
    /// tells apps "iPhone" for the name the person gave the phone, so it
    /// starts as the model ("iPhone 16 Pro Max") and can be changed on the
    /// Connect screen. Kept in memory only.
    var phoneName = DeviceModel.current

    var deviceName: String {
        let typed = phoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? DeviceModel.current : typed
    }

    // MARK: - Starting

    func start() {
        guard phase == .starting else { return }
        // The single sign-in kept before becomes the first saved connection,
        // once; if it can't be, it stays in its old item and is used as is.
        let carried = store.carryOver()
        #if DEBUG
        // Screenshots and checks from the command line, in Debug builds only:
        // `SIMCTL_CHILD_WW_DEBUG_SERVER=… SIMCTL_CHILD_WW_DEBUG_TOKEN=… xcrun
        // simctl launch …` opens signed in, keeping nothing in the Keychain.
        let env = ProcessInfo.processInfo.environment
        if let server = env["WW_DEBUG_SERVER"].flatMap(URL.init(string:)), let token = env["WW_DEBUG_TOKEN"] {
            connection = Connection(server: server, token: token)
            applyDebugKeep()
            if keep == .nothing { deleteKept() }
            phase = .ready
            Task { await refreshMe() }
            return
        }
        // `WW_DEBUG_CLOUDKIT_SCHEMA=1` writes the household's CloudKit schema
        // to the container's Development environment (#270), then carries on
        // starting as usual; what happened goes to debug-cloudkit-schema.txt
        // in Documents. Needs the device signed in to iCloud.
        if env["WW_DEBUG_CLOUDKIT_SCHEMA"] == "1" {
            Task.detached {
                let said = CloudKitSchema.initialize()
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? (said + "\n").write(to: documents.appending(path: "debug-cloudkit-schema.txt"),
                                          atomically: true, encoding: .utf8)
                print("WW_DEBUG_CLOUDKIT_SCHEMA: \(said)")
            }
        }
        // `WW_DEBUG_DEMO=1` opens in the demo (#92).
        if env["WW_DEBUG_DEMO"] == "1" {
            tryDemo()
            return
        }
        // `WW_DEBUG_LOCAL=1` opens the household on this phone (#235);
        // `empty` or `sample` starts it again, with the notice agreed to and
        // no accounts or a small household.
        // `WW_DEBUG_IMPORT=<file>` imports a backup from the app's Documents
        // folder onto a fresh household, through the same code as Import a
        // server backup, with `WW_DEBUG_PASSPHRASE`; `WW_DEBUG_EXPORT=<file>`
        // then writes the household back there as Export for a server does
        // (#236). For end-to-end checks from the command line.
        if let file = env["WW_DEBUG_IMPORT"] {
            Task {
                await Self.debugImport(file, export: env["WW_DEBUG_EXPORT"], passphrase: env["WW_DEBUG_PASSPHRASE"])
                useOnThisPhone()
            }
            return
        }
        // `WW_DEBUG_CSV=<file>`: Import a CSV opens on that file from the
        // app's Documents folder, without the Files picker (#243).
        if let name = env["WW_DEBUG_CSV"] {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: name)
            debugCSV = (try? Data(contentsOf: url)).flatMap { CSVFile.read($0, name: name) }
        }
        if let local = env["WW_DEBUG_LOCAL"] {
            if local == "1" {
                useOnThisPhone()
            } else {
                Task {
                    await Self.debugHousehold(sample: local == "sample")
                    await debugBank()
                    useOnThisPhone()
                }
            }
            return
        }
        // `WW_DEBUG_ADDRESS` opens on the Connect screen whatever the Keychain
        // holds (ConnectView's debug settings, #100); `WW_DEBUG_WELCOME=1`
        // on the first screen.
        if env["WW_DEBUG_ADDRESS"] != nil || env["WW_DEBUG_WELCOME"] == "1" {
            choseServer = env["WW_DEBUG_ADDRESS"] != nil
            phase = .connect
            return
        }
        #endif
        let front: Connection
        if case let .leftInPlace(old) = carried {
            saved = nil
            legacy = true
            keep = store.legacyKeep
            applyDebugKeep()
            if keep == .nothing { deleteKept() }
            front = old
        } else if let found = store.active {
            if store.activeID != found.id { store.activate(found.id) }
            bringForward(found)
            front = found.connection
        } else {
            phase = .connect
            return
        }
        if front.isLocal {
            // Set up the store before the pages ask it anything.
            useOnThisPhone()
            return
        }
        connection = front
        phase = .ready
        Task { await refreshMe() }
    }

    /// Who's signed in; shows the Important notice until it's agreed to.
    func refreshMe() async {
        guard let client else { return }
        if let found = try? await client.me() {
            me = found
            // Match the web app's theme, kept with this connection.
            if var saved, saved.connection == connection, saved.webTheme != found.themePreference {
                saved.webTheme = found.themePreference
                if store.update(saved) { self.saved = saved }
            }
            if found.noticeRequired { phase = .notice }
        }
        serverVersion = try? await client.version()
    }

    // MARK: - Signing in through the sheet

    func signIn(serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        busy = true
        defer { busy = false }

        // Is this WalletWeather, and new enough? Behind Cloudflare that can
        // only be asked once signed in to it, which the sheet does.
        var checked = false
        do {
            try await APIClient(connection: Connection(server: address.url, cloudflare: serviceToken)).checkServer()
            checked = true
        } catch .cloudflareSignInNeeded {
            // The sheet signs in to Cloudflare first.
        } catch {
            connectError = Self.describe(error)
            return
        }

        let request = SignInRequest()
        guard let answer = await sheet.open(request.signInURL(server: address, deviceName: deviceName)) else {
            return  // closed by hand
        }
        guard answer.state == request.state else {
            connectError = "The sign-in didn't come back as expected. Try again."
            return
        }
        switch answer {
        case let .signedIn(code, _, cf):
            let cloudflare = cf.map { CloudflareCredential.session(token: $0) } ?? serviceToken
            var candidate = Connection(server: address.url, cloudflare: cloudflare)
            do {
                let issued = try await APIClient(connection: candidate).swapSignInCode(code, verifier: request.codeVerifier)
                candidate.token = issued.token
                if !checked { try await APIClient(connection: candidate).checkServer() }
            } catch {
                connectError = Self.describe(error)
                return
            }
            await finishSignIn(candidate)
        case .cancelled:
            return
        default:
            connectError = "The sign-in didn't come back as expected. Try again."
        }
    }

    // MARK: - Signing in with an email and password (#100)

    /// An email and password, swapped for this phone's token. Behind
    /// Cloudflare Access the sheet signs in to Cloudflare first, unless a
    /// service token is given under Advanced.
    ///
    /// With two-factor sign-in on, the first try comes back asking for a
    /// code (`needsTwoFactorCode`); the next sends it with the same email
    /// and password.
    func signIn(email: String, password: String, code: String? = nil, serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            connectError = "Type the email and password you sign in to the web app with."
            return
        }
        busy = true
        defer { busy = false }
        var candidate = Connection(server: address.url, cloudflare: serviceToken)
        do {
            do {
                try await APIClient(connection: candidate).checkServer()
            } catch .cloudflareSignInNeeded {
                guard let cf = await signInToCloudflare(server: candidate.server) else { return }
                candidate.cloudflare = .session(token: cf)
                try await APIClient(connection: candidate).checkServer()
            }
            let issued = try await APIClient(connection: candidate)
                .signIn(email: email, password: password, deviceName: deviceName, code: code)
            candidate.token = issued.token
        } catch APIError.twoFactorCodeNeeded(let detail) {
            // The first answer only asks for the code; after that it's about
            // the code that was sent.
            if needsTwoFactorCode { connectError = detail }
            needsTwoFactorCode = true
            return
        } catch {
            connectError = Self.describe(error)
            return
        }
        needsTwoFactorCode = false
        await finishSignIn(candidate)
    }

    // MARK: - Signing in with a token

    /// A pasted token.
    func connect(token: String, serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            connectError = "Paste the token you made in the web app's Settings."
            return
        }
        await connect(Connection(server: address.url, token: token, cloudflare: serviceToken))
    }

    /// The "Open in WalletWeather" button, once confirmed.
    func connect(link: PendingLink) async {
        pendingLink = nil
        typedAddress = link.address.url.absoluteString
        if phase != .connect {
            // The old server's token is ended first, as Sign out does.
            await signOutEndingToken()
            typedAddress = link.address.url.absoluteString
        }
        connectNotice = nil
        await connect(Connection(server: link.address.url, token: link.token))
    }

    private func connect(_ candidate: Connection) async {
        busy = true
        defer { busy = false }
        var candidate = candidate
        do {
            do {
                try await APIClient(connection: candidate).checkServer()
            } catch .cloudflareSignInNeeded {
                guard let cf = await signInToCloudflare(server: candidate.server) else { return }
                candidate.cloudflare = .session(token: cf)
                try await APIClient(connection: candidate).checkServer()
            }
            _ = try await APIClient(connection: candidate).me()
        } catch {
            connectError = Self.describe(error)
            return
        }
        await finishSignIn(candidate)
    }

    private func finishSignIn(_ signedIn: Connection) async {
        // A new sign-in starts with nothing kept, and asks what to keep.
        saveAndBringForward(signedIn)
        askKeep = true
        connection = signedIn
        me = nil
        generation += 1
        phase = .ready
        await refreshMe()
    }

    // MARK: - Cloudflare

    /// Signs in to Cloudflare again when the app's Cloudflare sign-in has
    /// run out, keeping the WalletWeather token. Returns whether it worked.
    @discardableResult
    func renewCloudflare() async -> Bool {
        guard var current = connection, let cf = await signInToCloudflare(server: current.server) else { return false }
        current.cloudflare = .session(token: cf)
        if var saved, saved.connection.server == current.server {
            saved.connection = current
            if store.update(saved) { self.saved = saved }
        } else if legacy {
            store.updateLegacy(current)
        }
        connection = current
        generation += 1
        return true
    }

    /// Connect a bank (#258): the server's `/app-connect-bank` page in the
    /// sign-in sheet; nil when it was closed by hand.
    func connectBank() async -> AppLink? {
        guard let server = connection?.server,
              let address = try? ServerAddress.parse(server.absoluteString) else { return nil }
        return await sheet.open(BankConnect.url(server: address))
    }

    /// Your own Teller and Plaid keys (#278): the server's `/app-bank-keys`
    /// page in the sign-in sheet; nil when it was closed by hand. The keys
    /// go in on that page under the browser's sign-in and never reach the app.
    func editBankKeys() async -> AppLink? {
        guard let server = connection?.server,
              let address = try? ServerAddress.parse(server.absoluteString) else { return nil }
        return await sheet.open(BankKeys.url(server: address))
    }

    /// The sheet at `/app-sign-in/cloudflare`: the person's Cloudflare
    /// sign-in, handed back by the server.
    private func signInToCloudflare(server: URL) async -> String? {
        guard let address = try? ServerAddress.parse(server.absoluteString) else { return nil }
        let request = SignInRequest()
        guard let answer = await sheet.open(request.cloudflareURL(server: address)),
              answer.state == request.state else { return nil }
        switch answer {
        case let .cloudflare(_, token):
            return token
        case .noCloudflare:
            connectError = "Cloudflare turned the app away, but the server didn't see a Cloudflare sign-in. If you use a Cloudflare service token, enter it under Advanced."
            return nil
        default:
            return nil
        }
    }

    // MARK: - The notice, links and signing out

    func acknowledgeNotice() async throws(APIError) {
        guard let client else { return }
        try await client.acknowledgeNotice()
        phase = .ready
        await refreshMe()
    }

    func open(_ url: URL) {
        // The sheet's own answers go to the sheet; only connect links land here.
        guard case let .connect(server, token) = AppLink(url),
              let address = try? ServerAddress.parse(server) else { return }
        pendingLink = PendingLink(address: address, token: token)
    }

    /// Sign out: ends this phone's token on the server (#145), then removes
    /// everything from the phone. If the server can't be reached it still
    /// signs out, and the Connect screen says the token is still listed.
    func signOutEndingToken() async {
        if let client, connection?.token != nil {
            busy = true
            do {
                try await client.endToken()
            } catch .tokenExpired, .tokenRevoked {
                // Already ended.
            } catch {
                signOut()
                connectNotice = "Signed out on this phone. The server couldn't be reached, so this phone's token is still listed in the web app's Settings → API tokens until you revoke it there."
                busy = false
                return
            }
            busy = false
        }
        signOut()
    }

    /// Removes the token and everything else from the phone, without asking
    /// the server (for a token that has already ended).
    func signOut(keepAddress: Bool = false) {
        // Back to the sign-in screen, not the first screen's choice.
        choseServer = true
        if keepAddress, let server = connection?.server { typedAddress = server.absoluteString }
        if !keepAddress { typedAddress = "" }
        forgetFront()
        askKeep = false
        connection = nil
        me = nil
        serverVersion = nil
        connectError = nil
        generation += 1
        phase = .connect
    }

    /// Removes the connection in front from the phone: its Keychain item,
    /// its keep choice and its kept numbers.
    private func forgetFront() {
        if let saved {
            store.remove(saved.id)
        } else if legacy {
            store.removeLegacy()
        } else {
            kept?.deleteAll()
        }
        bringForward(nil)
    }

    static func describe(_ error: APIError) -> String {
        error.title + ". " + error.message
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? APIError { return describe(error) }
        return error.localizedDescription
    }
}
