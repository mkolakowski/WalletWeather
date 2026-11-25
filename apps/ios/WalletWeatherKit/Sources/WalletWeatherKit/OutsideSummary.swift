import Foundation

// Outside the app (Plans/outside-the-app.md, phase 1, #318): the small
// summary of each connection that widgets read, in an app group the app and
// its widget extension share. Later phases (reminders, Siri, the phone's
// search) read it too. What it holds and when it goes are in
// docs/privacy.md and apps/ios/README.md ("What's kept on the phone").
//
// Decided 2026-11-23 (docs/dev/decisions/ios-review.md, "what shows outside
// the app while the phone is locked"): amounts are hidden until the phone is
// unlocked, and hidden even then while the app's own lock is on; a server
// set to keep Nothing gets a summary with its name and no numbers.

/// The app group the app and its extensions share. Stable: never rename it.
public enum AppGroup {
    public static let identifier = "group.net.iptater.walletweather"

    /// The group's folder, or nil where the app isn't signed with the group
    /// (`swift test` on the Mac).
    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The group's settings, or nil without the group.
    public static var defaults: UserDefaults? {
        container == nil ? nil : UserDefaults(suiteName: identifier)
    }
}

// MARK: - The summary

/// What a widget, a reminder (and later Siri or the phone's search) may know
/// about one connection: its name and kind, when this was made, and, unless
/// it's a server set to keep Nothing, each account's balance, month's low and
/// lowest forecast balance on each of the next 7 days, the bills and income
/// with their next dates, and how many lines wait to confirm.
public struct ConnectionSummary: Codable, Equatable, Sendable, Identifiable {
    /// Bumped when the file's shape changes in a way an older reader can't
    /// take; a reader skips a file of a newer version.
    public static let currentVersion = 1

    public struct Account: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let balance: Money
        /// The month's lowest forecast balance, and the day it falls on.
        public let monthLow: Money
        public let monthLowDate: LocalDay?
        /// Lines on it due up to today and not confirmed; nil when this
        /// person can't change the account (To confirm doesn't show then).
        public let toConfirm: Int?
        /// The lowest forecast balance on each day from today to 7 days on
        /// that has a line, today always (#319, for Balance heading under).
        /// Nil in a summary written before it was kept.
        public let weekLows: [DayBalance]?

        public init(id: Int, name: String, balance: Money, monthLow: Money, monthLowDate: LocalDay?, toConfirm: Int?,
                    weekLows: [DayBalance]? = nil) {
            self.id = id
            self.name = name
            self.balance = balance
            self.monthLow = monthLow
            self.monthLowDate = monthLowDate
            self.toConfirm = toConfirm
            self.weekLows = weekLows
        }
    }

    /// A day's lowest forecast balance.
    public struct DayBalance: Codable, Equatable, Sendable {
        public let date: LocalDay
        public let low: Money

        public init(date: LocalDay, low: Money) {
            self.date = date
            self.low = low
        }
    }

    /// How far ahead `weekLows` looks, in days after today.
    public static let weekAhead = 7

    /// A repeating bill or paycheck.
    public struct Bill: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let accountId: Int
        public let accountName: String
        /// Signed: negative for a bill, positive for income.
        public let amount: Money
        public let nextDate: LocalDay?

        public var isIncome: Bool { !amount.isNegative }

        public init(id: Int, name: String, accountId: Int, accountName: String, amount: Money, nextDate: LocalDay?) {
            self.id = id
            self.name = name
            self.accountId = accountId
            self.accountName = accountName
            self.amount = amount
            self.nextDate = nextDate
        }
    }

    public let version: Int
    /// The saved connection's id: also the file's name.
    public let id: UUID
    public let name: String
    public let kind: SavedConnection.Kind
    public let madeAt: Date
    /// False for a server set to keep Nothing: no accounts, bills or counts.
    public let keepsNumbers: Bool
    public let accounts: [Account]
    public let bills: [Bill]

    public init(id: UUID, name: String, kind: SavedConnection.Kind, madeAt: Date, keepsNumbers: Bool,
                accounts: [Account], bills: [Bill], version: Int = ConnectionSummary.currentVersion) {
        self.version = version
        self.id = id
        self.name = name
        self.kind = kind
        self.madeAt = madeAt
        self.keepsNumbers = keepsNumbers
        self.accounts = keepsNumbers ? accounts : []
        self.bills = keepsNumbers ? bills : []
    }

    /// Whether a connection's summary carries numbers: the household on this
    /// iPhone always (its numbers are on the phone anyway), a server only
    /// when it keeps Last-known numbers.
    public static func keepsNumbers(_ saved: SavedConnection) -> Bool {
        saved.kind == .thisPhone || saved.keep == .lastKnown
    }

    /// A summary with the connection's name and nothing else, for a server
    /// set to keep Nothing.
    public static func nameOnly(_ saved: SavedConnection, madeAt: Date = .appNow) -> ConnectionSummary {
        ConnectionSummary(id: saved.id, name: saved.name, kind: saved.kind, madeAt: madeAt, keepsNumbers: false,
                          accounts: [], bills: [])
    }

    /// The summary from the pages' own answers: the Dashboard's cards (each
    /// account's balance and month's low), the bills and income, and how
    /// many lines wait on each account this person can change. A server set
    /// to keep Nothing gets `nameOnly`, whatever was loaded.
    public static func make(_ saved: SavedConnection, dashboard: Dashboard, recurring: RecurringList,
                            toConfirm: [Int: Int], weekLows: [Int: [DayBalance]] = [:],
                            madeAt: Date = .appNow) -> ConnectionSummary {
        guard keepsNumbers(saved) else { return nameOnly(saved, madeAt: madeAt) }
        let accounts = dashboard.cards.map { card in
            Account(id: card.id, name: card.name, balance: card.currentBalance, monthLow: card.forecastLow,
                    monthLowDate: card.forecastLowDate, toConfirm: toConfirm[card.id], weekLows: weekLows[card.id])
        }
        let bills = recurring.items.filter { $0.active && !$0.expired }.map { item in
            Bill(id: item.id, name: item.description, accountId: item.accountId, accountName: item.accountName,
                 amount: item.amount, nextDate: item.nextDate)
        }
        return ConnectionSummary(id: saved.id, name: saved.name, kind: saved.kind, madeAt: madeAt, keepsNumbers: true,
                                 accounts: accounts, bills: bills)
    }

    /// Loads what the summary needs through `client` (the connection's own,
    /// with nothing kept or answered from a kept copy, so `madeAt` is when
    /// the numbers came from the server). To confirm is counted only on the
    /// accounts this person can change, under a token that isn't read-only.
    /// A server set to keep Nothing asks nothing.
    public static func fetch(_ saved: SavedConnection, client: APIClient, readOnly: Bool,
                             today: LocalDay = .today(), now: Date = .appNow) async throws(APIError) -> ConnectionSummary {
        guard keepsNumbers(saved) else { return nameOnly(saved, madeAt: now) }
        let dashboard = try await client.dashboard(today: today)
        let recurring = try await client.recurring(today: today)
        let editable = Set(try await client.accounts(today: today).filter(\.canEdit).map(\.id))
        let month = YearMonth(today)
        let lastDay = today.adding(days: weekAhead)
        var toConfirm: [Int: Int] = [:]
        var weekLows: [Int: [DayBalance]] = [:]
        for card in dashboard.cards {
            let here = try await client.forecast(account: card.id, month: month, today: today)
            var rows = here.rows
            if YearMonth(lastDay) != month {
                rows += try await client.forecast(account: card.id, month: month.next, today: today).rows
            }
            if !readOnly, editable.contains(card.id) { toConfirm[card.id] = here.toConfirm(today: today).count }
            weekLows[card.id] = lows(rows, balance: card.currentBalance, today: today)
        }
        return make(saved, dashboard: dashboard, recurring: recurring, toConfirm: toConfirm, weekLows: weekLows,
                    madeAt: now)
    }

    /// Each day's lowest forecast balance from today to `weekAhead` days on:
    /// today starts at the balance now, and each other day with lines has
    /// the lowest balance its lines leave.
    static func lows(_ rows: [ForecastLine], balance: Money, today: LocalDay) -> [DayBalance] {
        let lastDay = today.adding(days: weekAhead)
        var byDay: [LocalDay: Money] = [today: balance]
        for row in rows {
            guard let day = row.plannedDate, day >= today, day <= lastDay else { continue }
            byDay[day] = min(byDay[day] ?? row.forecastBalance, row.forecastBalance)
        }
        return byDay.sorted { $0.key < $1.key }.map { DayBalance(date: $0.key, low: $0.value) }
    }

    // MARK: What the widgets show

    /// The bills (not income) still to come, soonest first.
    public func nextBills(limit: Int = 3, today: LocalDay = .today()) -> [Bill] {
        Array(bills.filter { !$0.isIncome && ($0.nextDate.map { $0 >= today } ?? false) }
            .sorted { ($0.nextDate!, $0.name) < ($1.nextDate!, $1.name) }
            .prefix(limit))
    }

    /// Lines waiting to confirm across the accounts this person can change;
    /// nil when there's none they can change.
    public var toConfirm: Int? {
        let counts = accounts.compactMap(\.toConfirm)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// The account To confirm opens on: the one with the most lines
    /// waiting (the first of them on a tie), else the first that can be
    /// changed.
    public var toConfirmAccount: Int? {
        let editable = accounts.filter { $0.toConfirm != nil }
        return editable.max { ($0.toConfirm ?? 0, -$0.id) < ($1.toConfirm ?? 0, -$1.id) }?.id
    }

    /// The account a Balance widget shows: the one chosen, while it's
    /// still there, else the first.
    public func account(_ id: Int?) -> Account? {
        accounts.first { $0.id == id } ?? accounts.first
    }
}

// MARK: - Where summaries live

/// Reading a summary: found, there but unreadable (the phone is locked and
/// complete file protection keeps it closed), or not there.
public enum SummaryRead: Equatable, Sendable {
    case found(ConnectionSummary)
    case unreadable
    case missing
}

/// The summaries in the app group, one file per saved connection,
/// `Summaries/<connection id>.json` (stable names).
///
/// - Each file is written with complete file protection: nothing reads it
///   while the phone is locked, the widgets included.
/// - The folder and every file are left out of iCloud and computer backups.
/// - A connection's file goes when it's signed out of (`ConnectionStore.remove`,
///   which leaving the household and Delete everywhere also pass through), and
///   choosing Nothing replaces it with one that holds only the name.
/// - In the app (not the extensions), the phone's search follows the files
///   (#331): writing one replaces its connection's entries, deleting one
///   removes them.
public struct SummaryStore: Sendable {
    public let directory: URL
    /// Whether protected files can be read now. The widgets pass nothing and
    /// find out by trying; tests pass false to stand in for a locked phone.
    private let protectedDataAvailable: @Sendable () -> Bool
    /// The phone's search, kept in step with the summaries; nil in the
    /// extensions, which only read.
    public let searchIndex: (any SearchIndexing)?

    public init(directory: URL, protectedDataAvailable: @escaping @Sendable () -> Bool = { true },
                searchIndex: (any SearchIndexing)? = nil) {
        self.directory = directory
        self.protectedDataAvailable = protectedDataAvailable
        self.searchIndex = searchIndex
    }

    /// The same store, keeping `index` in step with what it writes and deletes.
    public func searchable(_ index: any SearchIndexing) -> SummaryStore {
        SummaryStore(directory: directory, protectedDataAvailable: protectedDataAvailable, searchIndex: index)
    }

    /// The group's own, or nil without the group.
    public static var shared: SummaryStore? {
        AppGroup.container.map { SummaryStore(directory: $0.appending(path: "Summaries", directoryHint: .isDirectory)) }
    }

    /// A connection's file name. Stable: never change it.
    public static func fileName(for id: UUID) -> String { id.uuidString.lowercased() + ".json" }

    private func file(for id: UUID) -> URL {
        directory.appending(path: Self.fileName(for: id), directoryHint: .notDirectory)
    }

    /// Writes a connection's summary, replacing the one before. Returns
    /// whether it was written.
    @discardableResult
    public func write(_ summary: ConnectionSummary) -> Bool {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: directory.path(percentEncoded: false)) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                var folder = directory
                try Self.excludeFromBackup(&folder)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(summary)
            var url = file(for: summary.id)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            try Self.excludeFromBackup(&url)
            // Its entries in the phone's search become this summary's: none
            // for a server set to Nothing (#331).
            searchIndex?.replace(connection: summary.id, with: SearchEntry.entries(for: summary))
            return true
        } catch {
            return false
        }
    }

    /// A connection's summary, if it's there and can be read now.
    public func read(_ id: UUID) -> SummaryRead {
        let url = file(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .missing }
        guard protectedDataAvailable(), let data = try? Data(contentsOf: url) else { return .unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summary = try? decoder.decode(ConnectionSummary.self, from: data),
              summary.version <= ConnectionSummary.currentVersion else { return .unreadable }
        return .found(summary)
    }

    /// The connections with a summary, from the file names alone (nothing
    /// is read).
    public func ids() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { UUID(uuidString: String($0.dropLast(5))) }
    }

    /// Every summary that can be read now, by name.
    public func all() -> [ConnectionSummary] {
        ids().compactMap { id -> ConnectionSummary? in
            if case let .found(summary) = read(id) { return summary }
            return nil
        }
        .sorted { ($0.name.localizedLowercase, $0.id.uuidString) < ($1.name.localizedLowercase, $1.id.uuidString) }
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(for: id))
        searchIndex?.remove(connection: id)
    }

    /// Removes the summaries of connections no longer saved (one left
    /// behind by a crash, or by the Keychain losing an item).
    public func prune(keeping saved: Set<UUID>) {
        for id in ids() where !saved.contains(id) { delete(id) }
    }

    /// Every summary, and the folder.
    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        searchIndex?.removeAll()
    }

    /// The phone's search made again from every summary (#331): when the app
    /// starts, so summaries written before an update to the app reach the
    /// search, and anything left by a crash goes. Only while protected files
    /// can be read: a locked phone would make every summary look gone.
    public func reindex() {
        guard let searchIndex, protectedDataAvailable() else { return }
        searchIndex.removeAll()
        for summary in all() { searchIndex.replace(connection: summary.id, with: SearchEntry.entries(for: summary)) }
    }

    private static func excludeFromBackup(_ url: inout URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

// MARK: - What the app tells its extensions

/// The two settings the app copies into the group for its extensions: the
/// app's own lock (on, amounts stay hidden outside the app even on an
/// unlocked phone) and which connection is in front (where a new widget
/// starts). Neither is a number.
public struct OutsideSettings: @unchecked Sendable {  // UserDefaults is thread-safe
    /// Stable keys in the group's settings.
    public static let lockKey = "lock.enabled"
    public static let frontKey = "connections.front"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults?) { self.defaults = defaults }

    /// The group's, or one that holds nothing without the group.
    public static var shared: OutsideSettings { OutsideSettings(defaults: AppGroup.defaults) }

    public var lockOn: Bool {
        get { defaults?.bool(forKey: Self.lockKey) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Self.lockKey) }
    }

    public var front: UUID? {
        get { defaults?.string(forKey: Self.frontKey).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            if let newValue { defaults?.set(newValue.uuidString, forKey: Self.frontKey) }
            else { defaults?.removeObject(forKey: Self.frontKey) }
        }
    }
}

// MARK: - What a widget shows

/// What a widget shows for its connection, worked out with no screen so the
/// tests can check the privacy rules.
public enum WidgetContent: Equatable, Sendable {
    /// No connection chosen, or its summary is gone (signed out): the
    /// widget asks to open the app.
    case noConnection
    /// The summary can't be read (the phone is locked): labels only, every
    /// amount as ••••.
    case locked(name: String?)
    /// A server set to keep Nothing: its name, and how to see numbers.
    case keepsNothing(name: String)
    /// The summary, with amounts hidden when the app's lock is on.
    case summary(ConnectionSummary, amountsHidden: Bool)

    /// `name` is the connection's name as the widget's settings remember it,
    /// for when the summary can't be read.
    public static func decide(_ read: SummaryRead, name: String?, lockOn: Bool) -> WidgetContent {
        switch read {
        case .missing: return .noConnection
        case .unreadable: return .locked(name: name)
        case let .found(summary):
            guard summary.keepsNumbers else { return .keepsNothing(name: summary.name) }
            return .summary(summary, amountsHidden: lockOn)
        }
    }

    /// What stands in for an amount that can't be shown.
    public static let hiddenAmount = "••••"

    /// The line a server set to keep Nothing shows.
    public static let keepsNothingPrompt = "Turn on Last-known numbers to see numbers here"
}
