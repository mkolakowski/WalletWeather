import Foundation

// Bank sync in the app (bank-sync phase 5, #197): the status under Settings
// and Sync now. Connecting a bank and the sync log stay
// in the web app; the Unmatched list is in the app too (duo-more phase 3, #306). Server 1.70.0 or later has `GET /api/bank/status`; an older
// server just doesn't show the row's details. From server 1.86.0 the status
// also lists every connection (SimpleFIN, Teller or Plaid, bank-providers
// phase 4, #257), each with its own state and Sync now; before that the
// top-level fields are the one connection's. From server 1.92.1 the status
// also says which services the person may connect a bank through
// (`providers_allowed`), and from 1.92.0 it lists the accounts shared with
// them that sync from someone else's connection (`shared`; sync-access
// phase 4, #267), each with its own Sync now. From 1.97.0 it also says
// which services the person is ticked for (`providers_ticked`) and which of
// Teller and Plaid have their own keys (`own_keys`, the environment only;
// own-bank-keys phase 3, #278), and the server has a page for adding them.

/// `GET /api/bank/status`: the sync's state, readable with any API token.
/// A person with no bank connected gets only `enabled` and `connected`.
public struct BankStatus: Sendable, Codable, Equatable {
    public let enabled: Bool
    public let connected: Bool
    /// The accounts matched to a bank account.
    public let linkedAccountIds: [Int]?
    /// UTC times as the server writes them (`2026-11-17T05:06:16.123456Z`).
    public let lastSyncAt: String?
    public let lastSyncOk: Bool?
    /// "2 new lines, 1 matched a bill, 3 already here", or the error.
    public let lastSyncStatus: String?
    public let needsReconnect: Bool?
    public let failingOverADay: Bool?
    public let nextSyncAt: String?
    public let syncsLeftToday: Int?
    public let syncWaitSeconds: Int?
    /// Each bank connection with its own state (server 1.86.0 or later);
    /// nil from an older server, whose top-level fields are its one.
    public let connections: [BankConnection]?
    /// Accounts the person owns or edits that sync from someone else's
    /// connection (server 1.92.0 or later); nil from an older server.
    public let shared: [SharedBankAccount]?
    /// The services an admin lets this person connect a bank through
    /// (`simplefin`, `teller`, `plaid`; server 1.92.1 or later); nil from an
    /// older server, which has no way to say.
    public let providersAllowed: [String]?
    /// The services an admin lets this person use, whether or not they've
    /// added keys yet (server 1.97.0 or later); nil from an older server.
    public let providersTicked: [String]?
    /// Which of Teller and Plaid have the person's own keys, and their
    /// environment (server 1.97.0 or later): never the id or the secret.
    public let ownKeys: OwnBankKeys?

    /// The most syncs the server allows in 24 hours (the web app says the same).
    public static let syncsPerDay = 20
    /// The first server with the status endpoint.
    public static let minimumServer = "1.70.0"

    public init(enabled: Bool, connected: Bool, linkedAccountIds: [Int]? = nil, lastSyncAt: String? = nil,
                lastSyncOk: Bool? = nil, lastSyncStatus: String? = nil, needsReconnect: Bool? = nil,
                failingOverADay: Bool? = nil, nextSyncAt: String? = nil, syncsLeftToday: Int? = nil,
                syncWaitSeconds: Int? = nil, connections: [BankConnection]? = nil,
                shared: [SharedBankAccount]? = nil, providersAllowed: [String]? = nil,
                providersTicked: [String]? = nil, ownKeys: OwnBankKeys? = nil) {
        self.enabled = enabled
        self.connected = connected
        self.linkedAccountIds = linkedAccountIds
        self.lastSyncAt = lastSyncAt
        self.lastSyncOk = lastSyncOk
        self.lastSyncStatus = lastSyncStatus
        self.needsReconnect = needsReconnect
        self.failingOverADay = failingOverADay
        self.nextSyncAt = nextSyncAt
        self.syncsLeftToday = syncsLeftToday
        self.syncWaitSeconds = syncWaitSeconds
        self.connections = connections
        self.shared = shared
        self.providersAllowed = providersAllowed
        self.providersTicked = providersTicked
        self.ownKeys = ownKeys
    }

    /// Whether the person may connect a bank at all: false only when the
    /// server says they're ticked for no service. An older server that
    /// doesn't say gets today's behaviour (the card offers it). Someone
    /// ticked for Teller or Plaid who hasn't added keys yet may, once they
    /// do (#278).
    public var mayConnect: Bool { providersAllowed?.isEmpty != true || addKeysFirst }

    /// Ticked for Teller or Plaid, but neither can be used yet because the
    /// person hasn't added their own keys (#276, #278).
    public var addKeysFirst: Bool {
        guard enabled, let providersTicked else { return false }
        let ticked = providersTicked.filter { $0 == "teller" || $0 == "plaid" }
        return !ticked.isEmpty && !ticked.contains { providersAllowed?.contains($0) == true }
    }

    /// Whether the app's own Connect a bank applies: it runs Teller and
    /// Plaid (SimpleFIN is connected in the web app), so someone ticked for
    /// only SimpleFIN doesn't see it.
    public var mayConnectInApp: Bool {
        guard let providersAllowed else { return true }
        return providersAllowed.contains { $0 == "teller" || $0 == "plaid" }
    }

    /// A time as the server writes it, with or without fractions of a second.
    public static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// The server's own text for the time as an ISO string, for the demo.
    public static func text(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// What the Settings row says, in plain words. `when` writes a time the
    /// way the app shows times ("today at 3:12 PM"). With one connection, or
    /// from a server that lists none, this is the whole story; with several,
    /// `connectionRows` has each one's.
    public func summary(now: Date = .appNow, when: (Date) -> String) -> BankSyncSummary {
        BankSyncSummary.make(
            provider: "SimpleFIN", enabled: enabled, connected: connected,
            matched: linkedAccountIds?.isEmpty == false, needsReconnect: needsReconnect == true,
            lastSyncAt: lastSyncAt, lastSyncOk: lastSyncOk, lastSyncStatus: lastSyncStatus,
            nextSyncAt: nextSyncAt, syncWaitSeconds: syncWaitSeconds, mayConnect: mayConnect,
            addKeysFirst: addKeysFirst, now: now, when: when)
    }

    /// One row for each connection, in the server's order; empty when a
    /// person has none, bank sync is switched off, or the server is older
    /// than 1.86.0 (the row from `summary` stands for the one connection).
    public func connectionRows(now: Date = .appNow, when: (Date) -> String) -> [BankConnectionRow] {
        guard enabled, connected else { return [] }
        return (connections ?? []).map { c in
            BankConnectionRow(id: c.id, title: c.name, provider: c.providerName,
                              summary: c.summary(now: now, when: when))
        }
    }
}

/// One bank connection in `GET /api/bank/status`'s `connections`: a login at
/// SimpleFIN, Teller or Plaid, with its own last sync and daily limit.
public struct BankConnection: Sendable, Codable, Equatable, Identifiable {
    public let id: Int
    /// `simplefin`, `teller` or `plaid`; `providerName` is how it's written.
    public let provider: String
    public let providerName: String
    /// Its bank's name(s), or the provider's when it has none yet.
    public let name: String
    public let linkedAccountIds: [Int]
    public let lastSyncAt: String?
    public let lastSyncOk: Bool?
    public let lastSyncStatus: String?
    public let needsReconnect: Bool?
    public let failingOverADay: Bool?
    public let nextSyncAt: String?
    public let syncsLeftToday: Int?
    public let syncWaitSeconds: Int?

    public init(id: Int, provider: String, providerName: String, name: String, linkedAccountIds: [Int] = [],
                lastSyncAt: String? = nil, lastSyncOk: Bool? = nil, lastSyncStatus: String? = nil,
                needsReconnect: Bool? = nil, failingOverADay: Bool? = nil, nextSyncAt: String? = nil,
                syncsLeftToday: Int? = nil, syncWaitSeconds: Int? = nil) {
        self.id = id
        self.provider = provider
        self.providerName = providerName
        self.name = name
        self.linkedAccountIds = linkedAccountIds
        self.lastSyncAt = lastSyncAt
        self.lastSyncOk = lastSyncOk
        self.lastSyncStatus = lastSyncStatus
        self.needsReconnect = needsReconnect
        self.failingOverADay = failingOverADay
        self.nextSyncAt = nextSyncAt
        self.syncsLeftToday = syncsLeftToday
        self.syncWaitSeconds = syncWaitSeconds
    }

    /// This connection's state in plain words, naming its provider.
    public func summary(now: Date = .appNow, when: (Date) -> String) -> BankSyncSummary {
        BankSyncSummary.make(
            provider: providerName, enabled: true, connected: true, matched: !linkedAccountIds.isEmpty,
            needsReconnect: needsReconnect == true, lastSyncAt: lastSyncAt, lastSyncOk: lastSyncOk,
            lastSyncStatus: lastSyncStatus, nextSyncAt: nextSyncAt, syncWaitSeconds: syncWaitSeconds,
            now: now, when: when)
    }
}

/// An account the person owns or edits that takes its lines from someone
/// else's bank connection, in `GET /api/bank/status`'s `shared` (server 1.92.0
/// or later; sync-access phase 2, #265). The server gives the account's own
/// last sync, never the holder's other accounts, and no bank account name.
public struct SharedBankAccount: Sendable, Codable, Equatable, Identifiable {
    public var id: Int { accountId }
    public let accountId: Int
    public let accountName: String
    public let archived: Bool?
    /// `owner` or `edit`.
    public let level: String?
    /// Whose connection it is: their name, or their email.
    public let holderName: String?
    public let provider: String?
    public let providerName: String?
    public let lastSyncAt: String?
    public let lastSyncOk: Bool?
    public let lastSyncStatus: String?
    public let needsReconnect: Bool?
    /// An admin has unticked the holder for this provider.
    public let paused: Bool?
    /// The holder can't sign in, so the account doesn't sync.
    public let holderDisabled: Bool?
    public let nextSyncAt: String?
    public let syncsLeftToday: Int?
    public let syncWaitSeconds: Int?
    /// Lines waiting to be matched, which is done in the web app.
    public let unmatchedCount: Int?

    public init(accountId: Int, accountName: String, archived: Bool? = false, level: String? = "edit",
                holderName: String? = nil, provider: String? = nil, providerName: String? = nil,
                lastSyncAt: String? = nil, lastSyncOk: Bool? = nil, lastSyncStatus: String? = nil,
                needsReconnect: Bool? = false, paused: Bool? = false, holderDisabled: Bool? = false,
                nextSyncAt: String? = nil, syncsLeftToday: Int? = nil, syncWaitSeconds: Int? = 0,
                unmatchedCount: Int? = 0) {
        self.accountId = accountId
        self.accountName = accountName
        self.archived = archived
        self.level = level
        self.holderName = holderName
        self.provider = provider
        self.providerName = providerName
        self.lastSyncAt = lastSyncAt
        self.lastSyncOk = lastSyncOk
        self.lastSyncStatus = lastSyncStatus
        self.needsReconnect = needsReconnect
        self.paused = paused
        self.holderDisabled = holderDisabled
        self.nextSyncAt = nextSyncAt
        self.syncsLeftToday = syncsLeftToday
        self.syncWaitSeconds = syncWaitSeconds
        self.unmatchedCount = unmatchedCount
    }

    private var who: String { holderName ?? "someone" }
    private var service: String { providerName ?? "bank" }

    /// "Synced from Sam's SimpleFIN connection", as the web app says it.
    public var from: String { "Synced from \(who)'s \(service) connection" }

    /// This account's state in plain words. `enabled` is whether an admin
    /// has bank sync switched on for the server.
    public func summary(enabled: Bool = true, now: Date = .appNow, when: (Date) -> String) -> BankSyncSummary {
        if !enabled {
            return BankSyncSummary(
                tone: .neutral, headline: "Bank sync is switched off",
                detail: "An admin switched it off on this server, so nothing syncs until it's switched on again.")
        }
        if holderDisabled == true {
            return BankSyncSummary(
                tone: .warning, headline: "\(who) can't sign in",
                detail: "\(who) can't sign in at the moment, so this account doesn't sync. An admin can turn their sign-in back on, or an owner can match it to their own bank in the web app.")
        }
        if needsReconnect == true {
            return BankSyncSummary(
                tone: .warning, headline: "Needs connecting again",
                detail: "\(service) no longer reaches this bank, so daily syncing has stopped. \(who) needs to connect it again.")
        }
        if paused == true {
            return BankSyncSummary(
                tone: .warning, headline: "Paused by an admin",
                detail: "An admin has paused \(who)'s \(service) connection. This account syncs again once an admin lets \(who) use \(service).")
        }
        var wait: String?
        if let seconds = syncWaitSeconds, seconds > 0 {
            let minutes = (seconds + 59) / 60
            wait = "\(who)'s \(service) connection has asked \(service) \(BankStatus.syncsPerDay) times in the last 24 hours, the most it allows. It can run again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
        var next: String?
        if let due = BankStatus.date(nextSyncAt) {
            next = due > now ? "Syncs by itself again about \(when(due))." : "The next sync by itself is due now."
        }
        guard let last = BankStatus.date(lastSyncAt) else {
            return BankSyncSummary(tone: .neutral, headline: "Not synced yet", next: next,
                                   canSync: wait == nil, waitText: wait)
        }
        if lastSyncOk == false {
            return BankSyncSummary(tone: .warning, headline: "Last sync failed",
                                   detail: "\(when(last)): \(lastSyncStatus ?? "\(service) didn't answer.")",
                                   next: next, canSync: wait == nil, waitText: wait)
        }
        return BankSyncSummary(tone: .ok, headline: "Synced \(when(last))", detail: lastSyncStatus,
                               next: next, canSync: wait == nil, waitText: wait)
    }
}

/// A connection as the Settings card lists it.
public struct BankConnectionRow: Sendable, Equatable, Identifiable {
    public let id: Int
    /// The bank's name, as the server gives it.
    public let title: String
    /// "SimpleFIN", "Teller" or "Plaid".
    public let provider: String
    public let summary: BankSyncSummary
}

/// What the Settings row shows for a `BankStatus`.
public struct BankSyncSummary: Sendable, Equatable {
    public enum Tone: Sendable, Equatable { case ok, warning, neutral }

    public let tone: Tone
    public let headline: String
    public let detail: String?
    /// When it syncs by itself next.
    public let next: String?
    /// Whether Sync now can be pressed: a bank connected and matched, and
    /// under the day's limit. (A read-only token never shows the button.)
    public let canSync: Bool
    /// Why it can't be pressed right now, when the day's limit is reached.
    public let waitText: String?

    init(tone: Tone, headline: String, detail: String? = nil, next: String? = nil,
         canSync: Bool = false, waitText: String? = nil) {
        self.tone = tone
        self.headline = headline
        self.detail = detail
        self.next = next
        self.canSync = canSync
        self.waitText = waitText
    }

    /// The words for one connection's state (or, from a server that doesn't
    /// list connections, for the one the top-level fields describe).
    static func make(provider: String, enabled: Bool, connected: Bool, matched: Bool, needsReconnect: Bool,
                     lastSyncAt: String?, lastSyncOk: Bool?, lastSyncStatus: String?, nextSyncAt: String?,
                     syncWaitSeconds: Int?, mayConnect: Bool = true, addKeysFirst: Bool = false,
                     now: Date, when: (Date) -> String) -> BankSyncSummary {
        guard connected else {
            if !enabled {
                return BankSyncSummary(
                    tone: .neutral, headline: "Bank sync is off",
                    detail: "An admin switches it on in the web app's Admin page. Then each person connects their own bank in Settings → Bank sync.")
            }
            if addKeysFirst {
                return BankSyncSummary(
                    tone: .neutral, headline: "No bank connected",
                    detail: "Teller and Plaid each need keys from a developer account of your own. Add yours below, then connect a bank.")
            }
            return BankSyncSummary(
                tone: .neutral, headline: "No bank connected",
                detail: mayConnect
                    ? "Connecting a bank is done in the web app: Settings → Bank sync."
                    : "An admin chooses who may connect a bank, in the web app's Admin → Users. Accounts shared with you that sync from someone else's bank show below.")
        }
        if !enabled {
            return BankSyncSummary(
                tone: .neutral, headline: "Bank sync is switched off",
                detail: "An admin switched it off on this server, so nothing syncs until it's switched on again.")
        }
        if needsReconnect {
            return BankSyncSummary(
                tone: .warning, headline: "Needs connecting again",
                detail: "\(provider) no longer accepts this connection. Connect again in the web app: Settings → Bank sync.")
        }
        if !matched {
            return BankSyncSummary(
                tone: .neutral, headline: "Connected, no account matched",
                detail: "Match a bank account to one of yours in the web app: Settings → Bank sync.")
        }

        var wait: String?
        if let seconds = syncWaitSeconds, seconds > 0 {
            let minutes = (seconds + 59) / 60
            wait = "Bank sync has asked \(provider) \(BankStatus.syncsPerDay) times in the last 24 hours, the most it allows without risking your connection. It can run again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
        var next: String?
        if let due = BankStatus.date(nextSyncAt) {
            next = due > now ? "Syncs by itself again about \(when(due))." : "The next sync by itself is due now."
        }

        guard let last = BankStatus.date(lastSyncAt) else {
            return BankSyncSummary(tone: .neutral, headline: "Connected", detail: "Not synced yet.",
                                   next: next, canSync: wait == nil, waitText: wait)
        }
        if lastSyncOk == false {
            return BankSyncSummary(
                tone: .warning, headline: "Last sync failed",
                detail: "\(when(last)): \(lastSyncStatus ?? "\(provider) didn't answer.")",
                next: next, canSync: wait == nil, waitText: wait)
        }
        return BankSyncSummary(tone: .ok, headline: "Synced \(when(last))", detail: lastSyncStatus,
                               next: next, canSync: wait == nil, waitText: wait)
    }
}

/// Connecting a bank from the app (bank-providers phase 5, #258; decided
/// 2026-11-21): the server's `/app-connect-bank` page in the sign-in sheet,
/// which shares Safari's sign-in, runs Teller or Plaid under that sign-in and
/// hands back only a `walletweather://bank-connected` address. Matching the
/// new connection's accounts stays in the web app.
public enum BankConnect {
    /// The first server with the page.
    public static let minimumServer = "1.89.0"

    public static func url(server: ServerAddress) -> URL { server.url("/app-connect-bank") }

    /// Whether Settings offers Connect a bank: bank sync on, a server with
    /// the page, not a read-only token (the app edits nothing then), and an
    /// admin has ticked the person for Teller or Plaid (server 1.92.1 or
    /// later says; an older server's status doesn't, so it's offered as
    /// before and the server's own refusal speaks if they aren't ticked).
    public static func offered(_ status: BankStatus, serverVersion: String?, readOnly: Bool) -> Bool {
        guard status.enabled, !readOnly, status.mayConnectInApp, let serverVersion else { return false }
        return isVersion(serverVersion, atLeast: minimumServer) == true
    }

    /// What the card says after the sheet closes; nil when there's nothing
    /// to say (closed by hand, or Cancel on the page). `status` is the one
    /// read afterwards, for the new connection's name.
    public static func outcome(_ link: AppLink?, status: BankStatus?) -> (text: String, failed: Bool)? {
        guard case let .bankConnected(connection, state)? = link else { return nil }
        if let connection {
            let match = "Match its accounts to yours in the web app: Settings → Bank sync."
            if let c = status?.connections?.first(where: { $0.id == connection }) {
                return ("Connected \(c.name) through \(c.providerName). \(match)", false)
            }
            return ("Connected your bank. \(match)", false)
        }
        switch state {
        case "exited": return ("Closed without connecting a bank.", false)
        case "expired": return ("That took too long, so nothing was connected. Try again.", true)
        case "off": return ("This server can't connect a bank right now: bank sync is off, or it has no Teller or Plaid keys.", true)
        case "failed": return ("The bank didn't finish connecting. If it did, it shows here after a moment.", true)
        default: return nil
        }
    }
}

/// `own_keys` in `GET /api/bank/status` (server 1.97.0 or later): which of
/// Teller and Plaid have the person's own keys. Only the environment comes
/// to the app; the id and the secret stay on the server.
public struct OwnBankKeys: Sendable, Codable, Equatable {
    public struct Key: Sendable, Codable, Equatable {
        public let environment: String
        public init(environment: String) { self.environment = environment }
    }
    public let teller: Key?
    public let plaid: Key?

    public init(teller: Key? = nil, plaid: Key? = nil) {
        self.teller = teller
        self.plaid = plaid
    }

    public func key(_ provider: String) -> Key? {
        switch provider {
        case "teller": teller
        case "plaid": plaid
        default: nil
        }
    }
}

/// Your own Teller and Plaid keys from the app (own-bank-keys phase 3, #278;
/// decided 2026-11-23): the server's `/app-bank-keys` page in the sign-in
/// sheet, which shares Safari's sign-in and saves, replaces or removes them
/// through the browser-only routes with a fresh two-factor code. The app
/// never holds the keys; the page hands back only
/// `walletweather://bank-keys?state=changed|closed|off`.
public enum BankKeys {
    /// The first server with the page and `own_keys`.
    public static let minimumServer = "1.97.0"

    public static func url(server: ServerAddress) -> URL { server.url("/app-bank-keys") }

    /// One line of the card: a service and whether it has your keys.
    public struct Row: Sendable, Equatable, Identifiable {
        public let provider: String
        public let name: String
        public let text: String
        public let hasKeys: Bool
        public var id: String { provider }
    }

    /// The services the card lists: those with keys, and those an admin
    /// lets the person use while bank sync is on (they can add keys). Empty
    /// from a server before 1.97.0.
    public static func rows(_ status: BankStatus) -> [Row] {
        guard let own = status.ownKeys else { return [] }
        let ticked = status.enabled ? (status.providersTicked ?? []) : []
        return [("teller", "Teller"), ("plaid", "Plaid")].compactMap { provider, name in
            if let key = own.key(provider) {
                return Row(provider: provider, name: name, text: "Your own keys · \(environmentName(key.environment))",
                           hasKeys: true)
            }
            guard ticked.contains(provider) else { return nil }
            return Row(provider: provider, name: name, text: "No keys yet", hasKeys: false)
        }
    }

    /// "Sandbox", "Development", "Production"; anything else as it came.
    public static func environmentName(_ environment: String) -> String {
        switch environment {
        case "sandbox": "Sandbox"
        case "development": "Development"
        case "production": "Production"
        default: environment
        }
    }

    /// Whether the card offers the keys page: a server with it, not a
    /// read-only token, and a service to list.
    public static func offered(_ status: BankStatus, serverVersion: String?, readOnly: Bool) -> Bool {
        guard !readOnly, let serverVersion, isVersion(serverVersion, atLeast: minimumServer) == true else { return false }
        return !rows(status).isEmpty
    }

    /// The button's words: "Add your keys" while none are saved.
    public static func buttonTitle(_ status: BankStatus) -> String {
        rows(status).contains { $0.hasKeys } ? "Your bank keys" : "Add your bank keys"
    }

    /// What the card says after the sheet closes; nil when there's nothing
    /// to say (closed by hand, or nothing changed).
    public static func outcome(_ link: AppLink?) -> (text: String, failed: Bool)? {
        guard case let .bankKeys(state)? = link else { return nil }
        switch state {
        case "changed": return ("Your bank keys are updated.", false)
        case "off": return ("Keys can't be added right now: bank sync is off, or an admin hasn't let you use Teller or Plaid.", true)
        default: return nil
        }
    }
}

/// `POST /api/bank/sync`: what Sync now brought in, and the status after.
public struct BankSyncResult: Sendable, Codable, Equatable {
    public let added: Int
    public let matched: Int?
    public let skipped: Int
    public let messages: [String]
    public let status: BankStatus
    /// Sync now for one account (`account_id`): that account's own state
    /// afterwards; nil otherwise.
    public let account: SharedBankAccount?
}

extension APIClient {
    /// The sync's state; nil on a server older than 1.70.0, which has no
    /// status endpoint.
    public func bankStatus() async throws(APIError) -> BankStatus? {
        do {
            return try await get("/api/bank/status")
        } catch .notWalletWeather, .server(status: 404, detail: _) {
            return nil
        }
    }

    /// Sync now: brings in the new posted lines from every matched bank
    /// account. A read-only token is refused, and over the day's limit the
    /// server says when it can run again.
    public func syncBankNow() async throws(APIError) -> BankSyncResult {
        try await send("POST", "/api/bank/sync", body: [String: String]())
    }

    /// Sync now for one connection (server 1.86.0 or later), which is what
    /// each row of the list does; the day's limit is that connection's own.
    public func syncBankNow(connection: Int) async throws(APIError) -> BankSyncResult {
        try await send("POST", "/api/bank/sync", body: ["connection_id": connection])
    }

    /// Sync now for a shared account (server 1.92.0 or later): syncs the
    /// connection that feeds it, whoever's it is. The server answers 403
    /// naming the holder when an admin has paused it or they can't sign in,
    /// and 429 over the day's limit.
    public func syncBankNow(account: Int) async throws(APIError) -> BankSyncResult {
        try await send("POST", "/api/bank/sync", body: ["account_id": account])
    }
}
