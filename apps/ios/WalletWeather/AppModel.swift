import BackgroundTasks
import CoreData
import Observation
import SwiftUI
import UIKit
import WalletWeatherKit
import WidgetKit

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
    /// A CSV opened from Files, Mail or a share sheet's Open in… (#326): the
    /// import sheet opens on it once the app is showing a household and
    /// isn't locked.
    var openedCSV: CSVFile?
    /// Why an opened CSV wasn't imported (#326): not signed in, a read-only
    /// token, or a file that couldn't be read.
    var openedCSVAlert: OpenedCSVAlert?
    /// The last line dragged onto a Calendar day (#308), in any window: the
    /// pages showing lines read them again, and an editor open on that line
    /// closes, since what it holds is out of date.
    var lastLineMove: LineMove?
    /// Names used on the last months' lines, for Add transaction's
    /// suggestions (#325): kept in memory for the connection in front, for
    /// a few minutes, never on disk. See `NameHistory.swift`.
    @ObservationIgnored var nameHistory: (connection: Connection, at: Date, names: [NameSuggestion])?
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
    /// With `forecastRequest`: open it on the To confirm list (#305).
    var forecastToConfirm = false
    /// A Settings page to open, asked for by the demo's chip (Manage
    /// connections…, #301); Settings takes it and clears it.
    var settingsRequest: SettingsPage?

    private let sheet = SignInSheet()

    // MARK: - The saved connections (Plans/connections.md, #299)

    /// The connections the phone keeps, each in its own Keychain item.
    let store: ConnectionStore
    /// The connection in front, when it's saved (not the demo, and not a
    /// Debug launch's server).
    private(set) var saved: SavedConnection?
    /// Every saved connection, oldest first, for Settings → Connections
    /// (phase 2, #300): read again from the store after each change.
    private(set) var connections: [SavedConnection] = []
    /// What Connections says after signing out of one, when the server
    /// couldn't be reached to end its token.
    var connectionsNotice: String?
    /// Counts sign-ins that went through, so the Add a server sheet closes
    /// on one (and the sign-in screen clears its password).
    private(set) var signIns = 0
    /// Add a server sheets open in any window: the "Connect to …?" question
    /// for a link is asked in the sheet then, not over it.
    var signInSheets = 0
    /// Why a link from the web app couldn't be used, when it was opened
    /// with the app already in use (no sign-in screen to say it on).
    var linkProblem: String?
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
        self.store = store ?? Self.debugConnections()
            ?? ConnectionStore(secrets: KeychainConnectionSecrets(), defaults: defaults, summaries: SummaryStore.shared)
    }

    /// Debug only: `WW_DEBUG_CONNECTIONS=sample` keeps the connections in
    /// memory (never the Keychain) and in a throwaway settings suite and
    /// folder, with two sample servers, "Home" and "Mum & Dad" (whose
    /// sign-in has ended, so it carries the mark), and the
    /// household on this iPhone when there is one, for pictures of
    /// Settings → Connections. Nothing contacts the sample servers unless
    /// one is switched to.
    private static func debugConnections() -> ConnectionStore? {
        #if DEBUG
        guard debugSetting("WW_DEBUG_CONNECTIONS") == "sample" else { return nil }
        let suite = "ww-debug-connections"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let root = FileManager.default.temporaryDirectory.appending(path: "ww-debug-connections", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults, keptRoot: root)
        let home = store.add(Connection(server: URL(string: "https://home.example.com")!, token: "ww_sample_home"),
                             name: "Home", keep: .lastKnown, account: "you@example.com")
        let parents = store.add(Connection(server: URL(string: "https://ww.parents.example")!, token: "ww_sample_parents"),
                                name: "Mum & Dad", keep: .lastKnown, account: "you@example.com")
        // Sample totals beside them (#329): each keeps a Dashboard of sample
        // balances, "Home" loaded two hours ago and "Mum & Dad" two days ago.
        for (saved, balances, hoursAgo) in [(home, [4854.97, 12_310.40], 2.0), (parents, [-1_182.55, 940.0], 50.0)] {
            if let saved { Self.keepSampleDashboard(in: store.kept(for: saved.id), server: saved.connection.server,
                                               balances: balances, hoursAgo: hoursAgo) }
        }
        let phone = LocalStore.exists ? store.add(LocalServer.connection) : nil
        // "Mum & Dad" has had its sign-in end, for pictures of the mark (#302).
        if let parents { store.markSignInEnded(parents.id, token: "ww_sample_parents") }
        // Used most recently last: the household on this iPhone, else Home.
        for saved in [parents, home, phone].compactMap({ $0 }) { store.activate(saved.id) }
        return store
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// A kept Dashboard of sample accounts, dated `hoursAgo`, so the sample
    /// connections show a total and its age (#329). In the throwaway folder.
    private static func keepSampleDashboard(in keeper: KeptResponses, server: URL, balances: [Double], hoursAgo: Double) {
        let cards: [[String: Any]] = balances.enumerated().map { index, balance in
            ["id": index + 1, "name": "Account \(index + 1)", "month_label": "November 2026", "opening_balance": balance,
             "forecast_end": balance, "actual_end": balance, "forecast_high": balance, "forecast_high_date": NSNull(),
             "forecast_low": balance, "forecast_low_date": NSNull(), "actual_high": balance, "actual_low": balance,
             "upcoming_count": 0, "upcoming_net": 0, "current_balance": balance]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["cards": cards]) else { return }
        keeper.save(data, for: KeptResponses.key(server: server, method: "GET", path: "/api/dashboard", query: [:]))
        let when = Date().addingTimeInterval(-hoursAgo * 3600)
        let files = (try? FileManager.default.contentsOfDirectory(at: keeper.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: file.path) }
    }
    #endif

    // MARK: - The widgets' summary (Plans/outside-the-app.md, phase 1, #318)

    /// A widget tapped: the page to open, on its connection. A window's
    /// pages take it (`RootView`) and clear it.
    var widgetOpen: WidgetOpen?
    /// The last summary written: for which connection and load, and when, so
    /// coming back to the app doesn't ask the server again every time.
    @ObservationIgnored private var lastSummary: (key: String, at: Date)?
    @ObservationIgnored private var summaryTask: Task<Void, Never>?

    /// Writes the summary of the connection in front for the widgets, after
    /// its pages load (a new connection, a reload, someone signed in) and
    /// when the app opens or leaves; `force` skips the wait between two.
    /// Only a saved connection has one; never the demo. A server set to
    /// Nothing gets its name alone, and nothing is asked of it.
    func refreshSummary(force: Bool = false, within: TimeInterval = 120) {
        guard store.summaries != nil, let saved, connection == saved.connection, !isDemo, phase == .ready else { return }
        // Who's signed in says whether the token may confirm lines: wait for it.
        if ConnectionSummary.keepsNumbers(saved), me == nil { return }
        let key = "\(saved.id)/\(generation)/\(me?.id ?? -1)"
        if !force, let lastSummary, lastSummary.key == key, Date.now.timeIntervalSince(lastSummary.at) < within { return }
        lastSummary = (key, .now)
        summaryTask?.cancel()
        // Leaving the app is when the widgets matter: a little background
        // time to finish.
        let time = BackgroundTime()
        time.id = UIApplication.shared.beginBackgroundTask(withName: "Widgets' summary") { time.end() }
        summaryTask = Task {
            await writeSummary()
            time.end()
        }
    }

    /// Loads and writes the summary now (see `refreshSummary`). The numbers
    /// come from the connection's own client, not a kept copy, so the
    /// summary says when they were really loaded; if they can't be loaded,
    /// the summary before stays.
    func writeSummary() async {
        guard let summaries = store.summaries, let front = saved, connection == front.connection, !isDemo else { return }
        var summary = ConnectionSummary.nameOnly(front)
        if ConnectionSummary.keepsNumbers(front) {
            // A locked phone can't read the household, and wouldn't let the
            // widgets read what's written.
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            guard let loaded = try? await ConnectionSummary.fetch(front, client: APIClient(connection: front.connection),
                                                                  readOnly: me?.isReadOnly == true) else { return }
            summary = loaded
        }
        // Signed out, switched or set to Nothing while it loaded: it's not
        // written, or only the name is.
        guard !Task.isCancelled, saved?.id == front.id, let current = store.load(front.id) else { return }
        if !ConnectionSummary.keepsNumbers(current) { summary = .nameOnly(current) }
        if summaries.write(summary) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Summaries of connections no longer saved go (a crash between signing
    /// out and the file going). Only while the Keychain can be read: a
    /// locked phone would make every connection look gone.
    private func pruneSummaries() {
        guard let summaries = store.summaries, UIApplication.shared.isProtectedDataAvailable else { return }
        summaries.prune(keeping: Set(store.all().map(\.id)))
    }

    /// Follows a widget's tap: its connection comes in front (asking first
    /// while the lock has the demo in front; on cancel the demo stays and
    /// nothing opens), then the page it showed. Returns the place to open,
    /// or nil to stay.
    func follow(_ open: WidgetOpen) async -> RootView.Place? {
        if let id = open.connection, id != saved?.id || isDemo {
            guard store.load(id) != nil else { return .dashboard }   // signed out since: the page in front
            await choose(.saved(id))
            guard saved?.id == id, !isDemo else { return nil }
        }
        switch open.page {
        case .dashboard:
            return .dashboard
        case .bills:
            return .bills
        case .toConfirm:
            if let account = open.account {
                forecastRequest = account
                forecastToConfirm = true
            }
            return .forecast
        }
    }

    /// Choosing Nothing deletes what's kept straight away.
    func setKeep(_ choice: KeepChoice) {
        askKeep = false
        keep = choice
        if var saved, saved.keep != choice {
            saved.keep = choice
            if store.update(saved) { self.saved = saved }
            reloadConnections()
        } else if legacy {
            store.legacyKeep = choice
        }
        if choice == .nothing { deleteKept() }
        // The widgets' summary follows (#318): Nothing leaves only the name.
        refreshSummary(force: true)
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
        reloadConnections()
        // Where a new widget starts (#318); a server set to Nothing has only
        // its name in its summary, whatever was there before.
        if let front {
            OutsideSettings.shared.front = front.id
            if let saved, !ConnectionSummary.keepsNumbers(saved), store.summaries?.write(.nameOnly(saved)) == true {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Reads the saved connections again, for Connections.
    func reloadConnections() {
        connections = store.all()
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

    /// Saves a sign-in and puts it in front (phase 2, #300): the same server
    /// and person renews the connection already saved (its name, keep
    /// choice and kept numbers stay); anything else is added beside the
    /// others, which stay signed in. Returns whether it renewed one. If the
    /// Keychain won't take it, it's still in front for this launch.
    @discardableResult
    private func saveAndBringForward(_ connection: Connection, account: String?) -> Bool {
        guard let result = store.save(signIn: connection, account: account),
              let front = store.activate(result.saved.id) else {
            // A single sign-in still in its old item stays the one in use.
            let stillLegacy = legacy && store.legacy == connection
            bringForward(nil)
            legacy = stillLegacy
            if stillLegacy { keep = store.legacyKeep }
            return false
        }
        // A single sign-in that couldn't be carried over is replaced by a new
        // sign-in to its own server; another server's leaves it, to be
        // carried over at the next start.
        if legacy, let old = store.legacy, SavedConnection.sameServer(old.server, connection.server) {
            store.removeLegacy()
        }
        bringForward(front)
        return result.renewed
    }

    /// The household on this iPhone in front: the one saved, or saved now.
    /// The servers saved beside it stay.
    private func bringHouseholdForward() {
        if let household = store.all().first(where: { $0.kind == .thisPhone }), let front = store.activate(household.id) {
            bringForward(front)
            return
        }
        guard let front = store.add(LocalServer.connection).flatMap({ store.activate($0.id) }) else {
            bringForward(nil)
            return
        }
        bringForward(front)
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
        // A sign-in that ended is marked on the connection that made the
        // request, even if another is in front by the time it's answered (#302).
        var ended: SignInEndedObserver?
        if let saved, saved.kind == .server {
            let id = saved.id, token = saved.connection.token
            ended = { [weak self] in self?.markSignInEnded(id, token: token) }
        }
        return APIClient(connection: connection, keeper: keep == .lastKnown ? kept : nil, observer: observer,
                         signInEnded: ended)
    }

    /// A request answered that a server's sign-in has ended: the connection
    /// is marked, in the chip's menu and Connections, until a sign-in
    /// renews it (#302). Changes nothing on the pages: no reload.
    func markSignInEnded(_ id: UUID, token: String?) {
        guard let marked = store.markSignInEnded(id, token: token) else { return }
        if saved?.id == id { saved = marked }
        reloadConnections()
    }

    /// "Try the demo" (#92): the app on its built-in sample numbers.
    var isDemo: Bool { connection?.isDemo == true }

    // MARK: - The demo and the lock (connections phase 3, #301)

    /// What was in front before the demo: what leaving it goes back to, and
    /// what a lock that sent the app to the demo remembers.
    private(set) var beforeDemo: LockGate.Front?
    /// Asks Face ID first while the app is locked in the demo; true when a
    /// real connection may open (`AppSettings.mayOpenYourNumbers`). Set by
    /// the app before it starts.
    var authenticateToLeaveDemo: (@MainActor () async -> Bool)?

    /// What's in front, as the lock sees it.
    var lockFront: LockGate.Front {
        if isDemo { return .demo }
        guard connection != nil else { return .nothing }
        if let saved { return .saved(saved.id) }
        return isLocal ? .household : .unsaved
    }

    /// What the connection chip says, or nil when it doesn't show: under
    /// the Dashboard's title and at the top of Settings (#302).
    func connectionChip(locked: Bool) -> ConnectionChipState? {
        ConnectionChipState.make(saved: connections, front: lockFront, householdExists: hasHousehold,
                                 visibility: ConnectionsVisibility(locked: locked))
    }

    /// The household's iCloud Drive backup and bank sync may run now,
    /// whatever is in front: a server, the demo or nothing (#302).
    var householdMayRun: Bool {
        HouseholdRuns.mayRun(householdExists: LocalStore.exists,
                             protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable, front: lockFront)
    }

    /// Whether a household is on this iPhone already, saved or not:
    /// Connections offers Use on this iPhone and Restore until there is.
    var hasHousehold: Bool { LocalStore.exists || connections.contains { $0.kind == .thisPhone } }

    /// Every way out of the demo to someone's numbers passes here: locked in
    /// the demo, it asks first; on failure or cancel the demo stays.
    func mayLeaveDemo() async -> Bool {
        await authenticateToLeaveDemo?() ?? true
    }

    /// A row of Connections, or of the demo chip's menu, chosen: a real
    /// connection asks first while locked in the demo, then opens; the demo
    /// opens at once. The one in front stays.
    func choose(_ target: ConnectionRow.Target) async {
        switch target {
        case .demo:
            if !isDemo { tryDemo() }
        case let .saved(id):
            guard isDemo || saved?.id != id else { return }
            guard await mayLeaveDemo() else { return }
            switchTo(id)
        case .thisIPhone:
            guard isDemo || !isLocal else { return }
            guard await mayLeaveDemo() else { return }
            useOnThisPhone()
        }
    }

    /// The lock fell due with the demo shown when locked: the demo comes in
    /// front, remembering what was (already in the demo, it stays). Nothing
    /// is signed out or deleted.
    func lockIntoDemo(remember: LockGate.Front?) {
        if !isDemo { tryDemo() }
        if let remember { beforeDemo = remember }
    }

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
            bringHouseholdForward()
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

    // MARK: - Switching (phase 2, #300)

    /// Puts another saved connection in front, signing out of nothing: its
    /// keep choice and saved web theme come with it, and every page loads
    /// again. A connection whose token has ended still switches; its pages
    /// then say Sign in again. The household on this iPhone opens as On
    /// this iPhone does.
    func switchTo(_ id: UUID) {
        connectError = nil
        connectNotice = nil
        connectionsNotice = nil
        guard let target = store.load(id) else {
            reloadConnections()
            return
        }
        if target.kind == .thisPhone {
            useOnThisPhone()
            return
        }
        guard let front = store.activate(id) else { return }
        askKeep = false
        bringForward(front)
        connection = front.connection
        me = nil
        serverVersion = nil
        generation += 1
        phase = .ready
        Task { await refreshMe() }
    }

    /// Renames a saved connection; an empty name goes back to its host (or
    /// On this iPhone).
    func rename(_ id: UUID, to name: String) {
        guard var target = store.load(id) else { return }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = typed.isEmpty ? SavedConnection.defaultName(for: target.connection) : typed
        guard new != target.name else { return }
        target.name = new
        guard store.update(target) else { return }
        if saved?.id == id { saved = target }
        reloadConnections()
    }

    /// Sign out of one connection (phase 2, #300): its token is ended on its
    /// server when it can be reached (as Sign out always did), then only it,
    /// its kept numbers and its keep choice are removed. If it was in front,
    /// the one used most recently comes in front; with none left, back to
    /// the sign-in screen as before.
    func signOut(of id: UUID) async {
        guard let target = store.load(id), target.kind == .server else { return }
        connectionsNotice = nil
        var notice: String?
        if target.connection.token != nil {
            busy = true
            do {
                // Its own client, from its saved sign-in: it may not be in front.
                try await APIClient(connection: target.connection).endToken()
            } catch .tokenExpired, .tokenRevoked {
                // Already ended.
            } catch {
                notice = "Signed out of \(target.name) on this iPhone. Its server couldn't be reached, so this iPhone's token is still listed in that web app's Settings → API tokens until you revoke it there."
            }
            busy = false
        }
        guard saved?.id == id else {
            store.remove(id)
            WidgetCenter.shared.reloadAllTimelines()
            reloadConnections()
            connectionsNotice = notice
            return
        }
        store.remove(id)
        WidgetCenter.shared.reloadAllTimelines()
        if let next = store.mostRecentlyUsed {
            switchTo(next.id)
            connectionsNotice = notice
        } else {
            signOut()
            connectNotice = notice
        }
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
        // Behind a server or the demo too (#301, #302): what it lands never
        // reloads the pages unless the household is what's in front.
        guard householdMayRun, phase == .ready else { return }
        if let result = await phoneBank.syncIfDue(), result.added + result.matched > 0, isLocal { generation += 1 }
        scheduleBankRefresh()
    }

    /// iOS's background time (BGAppRefreshTask): the same sync, when the
    /// household on this iPhone is in use and can be read (not while a
    /// locked phone keeps it closed).
    func backgroundBankSync() async {
        guard phoneBank.connected, householdMayRun else { return }
        if let result = await phoneBank.syncIfDue(), result.added + result.matched > 0, isLocal {
            generation += 1
            // New lines change the widgets' numbers (#318).
            await writeSummary()
        }
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
    /// lock). What was in front is remembered for leaving it (#301).
    func tryDemo() {
        if !isDemo {
            beforeDemo = lockFront
        }
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

    /// Leaves the demo for what was in front before it (#301), or the
    /// first screen when there was nothing, keeping what was typed there.
    /// Nothing in Settings calls it now: choosing another connection is the
    /// way out. A caller asks `mayLeaveDemo` first.
    func leaveDemo() {
        guard isDemo else { return }
        switch beforeDemo {
        case let .saved(id)? where store.load(id) != nil:
            switchTo(id)
            return
        case .household?:
            useOnThisPhone()
            return
        default:
            break
        }
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
    /// `WW_DEBUG_KEEP` (what the phone keeps), `WW_DEBUG_LOOK` (the look), `WW_DEBUG_DATES` (iso or short),
    /// and `WW_DEBUG_CONFIRM`, `WW_DEBUG_COMPARE` and `WW_DEBUG_NEW_WINDOW`
    /// (Forecast's To confirm, Compare, and a second window on a page), and
    /// `WW_DEBUG_ADD_NAME=<text>` (Forecast opens Add transaction with it typed as the name, #325),
    /// `WW_DEBUG_COPY=sample` or `replace` (Copy to a server open, the first server chosen, or Replace
    /// chosen with its confirmation; nothing is checked or sent, #328),
    /// `WW_DEBUG_DEMO=1` (open in the demo), and `WW_DEBUG_CLOUDKIT_SCHEMA=1`
    /// (write the CloudKit schema to Development, #270), and
    /// `WW_DEBUG_CONNECTIONS=sample` (sample connections in memory, #300),
    /// `WW_DEBUG_WIDGETS=amounts|applock|locked|nothing` (the widgets' faces, #318),
    /// and `WW_DEBUG_LOCKED_DEMO=1` (start as if the lock had just sent the
    /// app to the demo) and `WW_DEBUG_CHIP_MENU=1` (the demo chip's choices
    /// as a sheet, #301), and `WW_DEBUG_DROP=csv` or `day` (a drop
    /// highlight with nothing dragged, #308), and
    /// `WW_DEBUG_CUSTOM_THEMES=sample` (two sample custom themes in memory,
    /// which `WW_DEBUG_LOOK=custom-light` or `custom-dark` shows) and
    /// `WW_DEBUG_THEME_EDITOR` (the theme editor on one, over Settings →
    /// Appearance, #297).
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

    /// `lock` is asked once what's in front is known (`AppSettings.lockAtLaunch`):
    /// with the demo shown when locked, the app opens in the demo (#301).
    func start(lock: (LockGate.Front) -> LockGate.Decision = { _ in LockGate.Decision(show: .asItIs) }) {
        guard phase == .starting else { return }
        // The single sign-in kept before becomes the first saved connection,
        // once; if it can't be, it stays in its old item and is used as is.
        let carried = store.carryOver()
        pruneSummaries()
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
        #if DEBUG
        // `WW_DEBUG_CONNECTIONS=sample` with no household on this iPhone:
        // the demo, so no sample server is contacted. With
        // `WW_DEBUG_LOCKED_DEMO=1` the lock sends it there instead (below).
        if env["WW_DEBUG_CONNECTIONS"] == "sample", env["WW_DEBUG_LOCKED_DEMO"] != "1", store.active?.kind != .thisPhone {
            reloadConnections()
            tryDemo()
            return
        }
        #endif
        reloadConnections()
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
        // The lock (#301): the demo in front, the connection remembered
        // behind it and not opened, so none of its numbers load.
        let decision = lock(lockFront(starting: front))
        if decision.show == .demo {
            tryDemo()
            beforeDemo = decision.remember
            runHouseholdIfDue()
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
        // The household keeps working behind a server (#302).
        runHouseholdIfDue()
    }

    /// The household's backup and bank sync, when due, with something else
    /// in front: nothing on screen changes (#302).
    private func runHouseholdIfDue() {
        guard householdMayRun else { return }
        Task { await backup.runIfDue() }
        Task { await syncBankIfDue() }
    }

    /// What the lock sees in front at the start, before it's opened.
    private func lockFront(starting front: Connection) -> LockGate.Front {
        if let saved { return .saved(saved.id) }
        return front.isLocal ? .household : .unsaved
    }

    /// Who's signed in; shows the Important notice until it's agreed to.
    func refreshMe() async {
        guard let client else { return }
        if let found = try? await client.me() {
            me = found
            // Match the web app's theme, kept with this connection.
            // And who's signed in, which tells a new sign-in of the same
            // person from another's (#300).
            if var saved, saved.connection == connection,
               saved.webTheme != found.themePreference || saved.account != found.email {
                saved.webTheme = found.themePreference
                saved.account = found.email
                if store.update(saved) {
                    self.saved = saved
                    reloadConnections()
                }
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

    /// The "Open in WalletWeather" button or a scanned QR code, once
    /// confirmed: adds the server, or renews the one already saved for the
    /// same person, and puts it in front. The others stay signed in (#300).
    func connect(link: PendingLink) async {
        pendingLink = nil
        linkProblem = nil
        typedAddress = link.address.url.absoluteString
        connectNotice = nil
        connectError = nil
        // A Cloudflare sign-in already saved for that server is tried first.
        let cloudflare = store.all().first {
            $0.kind == .server && SavedConnection.sameServer($0.connection.server, link.address.url)
        }?.connection.cloudflare
        let before = signIns
        await connect(Connection(server: link.address.url, token: link.token, cloudflare: cloudflare))
        if signIns == before, phase != .connect, signInSheets == 0, let error = connectError {
            linkProblem = error
            connectError = nil
        }
    }

    /// What the "Connect to …?" question says about a link.
    func linkMessage(_ link: PendingLink) -> String {
        let sameServer = connections.contains {
            $0.kind == .server && SavedConnection.sameServer($0.connection.server, link.address.url)
        }
        if sameServer { return "Signs in to \(link.host) again with this token." }
        if connection == nil && connections.isEmpty { return "Sign in with the token from the web app's Settings." }
        return "Adds \(link.host) to your connections and switches to it. Your other sign-ins stay."
    }

    private func connect(_ candidate: Connection) async {
        busy = true
        defer { busy = false }
        var candidate = candidate
        let who: Me
        do {
            do {
                try await APIClient(connection: candidate).checkServer()
            } catch .cloudflareSignInNeeded {
                guard let cf = await signInToCloudflare(server: candidate.server) else { return }
                candidate.cloudflare = .session(token: cf)
                try await APIClient(connection: candidate).checkServer()
            }
            who = try await APIClient(connection: candidate).me()
        } catch {
            connectError = Self.describe(error)
            return
        }
        await finishSignIn(candidate, who: who)
    }

    /// A sign-in that went through: saved beside the others (or renewing
    /// the same person's on the same server), and put in front.
    private func finishSignIn(_ signedIn: Connection, who: Me? = nil) async {
        connectError = nil
        connectionsNotice = nil
        // Who signed in tells a new sign-in of the same person from another's.
        var who = who
        if who == nil { who = try? await APIClient(connection: signedIn).me() }
        let renewed = saveAndBringForward(signedIn, account: who?.email)
        // A new connection starts with nothing kept, and asks what to keep; a
        // renewed one keeps its choice.
        askKeep = !renewed
        connection = signedIn
        me = nil
        serverVersion = nil
        generation += 1
        phase = .ready
        signIns += 1
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
        switch OpenedURL(url) {
        case .csv:
            openCSV(url)
        case let .link(.open(page, connection, account)):
            // A widget tapped (#318): the window's pages follow it.
            widgetOpen = WidgetOpen(page: page, connection: connection, account: account)
        case let .link(link):
            // The sheet's own answers go to the sheet; only connect links land here.
            guard case let .connect(server, token) = link,
                  let address = try? ServerAddress.parse(server) else { return }
            pendingLink = PendingLink(address: address, token: token)
        case .other:
            return
        }
    }

    /// A CSV from Files, Mail or Open in… (#326): read at once (the copy
    /// iOS made for the app is removed after), then Import a CSV opens on
    /// it. On the Connect screen, or with a read-only token, an alert says
    /// why not. While the app is still starting, or locked, the file waits.
    private func openCSV(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        // Open in… hands over a copy in the app's Inbox folder: no longer needed.
        if url.deletingLastPathComponent().lastPathComponent == "Inbox" { try? FileManager.default.removeItem(at: url) }
        let decision = OpenedCSV.decide(signedIn: phase != .connect, readOnly: me?.isReadOnly == true)
        if let refusal = decision.refusal {
            openedCSVAlert = OpenedCSVAlert(title: refusal.title, message: refusal.message)
        } else if let data, let file = CSVFile.read(data, name: OpenedURL.fileName(url)) {
            openedCSV = file
        } else {
            openedCSVAlert = OpenedCSVAlert(title: "Couldn't open the file", message: "That file couldn't be read.")
        }
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
                connectNotice = "Signed out on this iPhone. The server couldn't be reached, so this iPhone's token is still listed in the web app's Settings → API tokens until you revoke it there."
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
        openedCSV = nil
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
            // Its widgets' summary goes with it (#318), on sign-out, leaving
            // the household and Delete everywhere.
            store.remove(saved.id)
            WidgetCenter.shared.reloadAllTimelines()
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

/// An alert about a CSV that was opened but not imported (#326).
struct OpenedCSVAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A widget's tap (#318): the page it shows, on its connection, at an account.
struct WidgetOpen: Equatable {
    let page: AppLink.OpenPage
    let connection: UUID?
    let account: Int?
}

/// The background time asked for while a summary is written.
@MainActor private final class BackgroundTime {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
