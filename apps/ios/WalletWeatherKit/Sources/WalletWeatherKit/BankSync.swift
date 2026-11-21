import Foundation

// Bank sync in the app (bank-sync phase 5, #197): the status under Settings
// and Sync now. Connecting a bank, the sync log and the Unmatched list stay
// in the web app. Server 1.70.0 or later has `GET /api/bank/status`; an older
// server just doesn't show the row's details. From server 1.86.0 the status
// also lists every connection (SimpleFIN, Teller or Plaid, bank-providers
// phase 4, #257), each with its own state and Sync now; before that the
// top-level fields are the one connection's.

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

    /// The most syncs the server allows in 24 hours (the web app says the same).
    public static let syncsPerDay = 20
    /// The first server with the status endpoint.
    public static let minimumServer = "1.70.0"

    public init(enabled: Bool, connected: Bool, linkedAccountIds: [Int]? = nil, lastSyncAt: String? = nil,
                lastSyncOk: Bool? = nil, lastSyncStatus: String? = nil, needsReconnect: Bool? = nil,
                failingOverADay: Bool? = nil, nextSyncAt: String? = nil, syncsLeftToday: Int? = nil,
                syncWaitSeconds: Int? = nil, connections: [BankConnection]? = nil) {
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
    public func summary(now: Date = .now, when: (Date) -> String) -> BankSyncSummary {
        BankSyncSummary.make(
            provider: "SimpleFIN", enabled: enabled, connected: connected,
            matched: linkedAccountIds?.isEmpty == false, needsReconnect: needsReconnect == true,
            lastSyncAt: lastSyncAt, lastSyncOk: lastSyncOk, lastSyncStatus: lastSyncStatus,
            nextSyncAt: nextSyncAt, syncWaitSeconds: syncWaitSeconds, now: now, when: when)
    }

    /// One row for each connection, in the server's order; empty when a
    /// person has none, bank sync is switched off, or the server is older
    /// than 1.86.0 (the row from `summary` stands for the one connection).
    public func connectionRows(now: Date = .now, when: (Date) -> String) -> [BankConnectionRow] {
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
    public func summary(now: Date = .now, when: (Date) -> String) -> BankSyncSummary {
        BankSyncSummary.make(
            provider: providerName, enabled: true, connected: true, matched: !linkedAccountIds.isEmpty,
            needsReconnect: needsReconnect == true, lastSyncAt: lastSyncAt, lastSyncOk: lastSyncOk,
            lastSyncStatus: lastSyncStatus, nextSyncAt: nextSyncAt, syncWaitSeconds: syncWaitSeconds,
            now: now, when: when)
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
                     syncWaitSeconds: Int?, now: Date, when: (Date) -> String) -> BankSyncSummary {
        guard connected else {
            if !enabled {
                return BankSyncSummary(
                    tone: .neutral, headline: "Bank sync is off",
                    detail: "An admin switches it on in the web app's Admin page. Then each person connects their own bank in Settings → Bank sync.")
            }
            return BankSyncSummary(
                tone: .neutral, headline: "No bank connected",
                detail: "Connecting a bank is done in the web app: Settings → Bank sync.")
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
    /// the page, and not a read-only token (the app edits nothing then).
    public static func offered(_ status: BankStatus, serverVersion: String?, readOnly: Bool) -> Bool {
        guard status.enabled, !readOnly, let serverVersion else { return false }
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

/// `POST /api/bank/sync`: what Sync now brought in, and the status after.
public struct BankSyncResult: Sendable, Codable, Equatable {
    public let added: Int
    public let matched: Int?
    public let skipped: Int
    public let messages: [String]
    public let status: BankStatus
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
}
