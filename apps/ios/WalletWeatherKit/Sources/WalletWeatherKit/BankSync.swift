import Foundation

// Bank sync in the app (bank-sync phase 5, #197): the status under Settings
// and Sync now. Connecting a bank, the sync log and the Unmatched list stay
// in the web app. Server 1.70.0 or later has `GET /api/bank/status`; an older
// server just doesn't show the row's details.

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

    /// The most syncs the server allows in 24 hours (the web app says the same).
    public static let syncsPerDay = 20
    /// The first server with the status endpoint.
    public static let minimumServer = "1.70.0"

    public init(enabled: Bool, connected: Bool, linkedAccountIds: [Int]? = nil, lastSyncAt: String? = nil,
                lastSyncOk: Bool? = nil, lastSyncStatus: String? = nil, needsReconnect: Bool? = nil,
                failingOverADay: Bool? = nil, nextSyncAt: String? = nil, syncsLeftToday: Int? = nil,
                syncWaitSeconds: Int? = nil) {
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
    /// way the app shows times ("today at 3:12 PM").
    public func summary(now: Date = .now, when: (Date) -> String) -> BankSyncSummary {
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
        if needsReconnect == true {
            return BankSyncSummary(
                tone: .warning, headline: "Needs connecting again",
                detail: "SimpleFIN no longer accepts this connection. Connect again in the web app: Settings → Bank sync.")
        }
        if linkedAccountIds?.isEmpty != false {
            return BankSyncSummary(
                tone: .neutral, headline: "Connected, no account matched",
                detail: "Match a bank account to one of yours in the web app: Settings → Bank sync.")
        }

        var wait: String?
        if let seconds = syncWaitSeconds, seconds > 0 {
            let minutes = (seconds + 59) / 60
            wait = "Bank sync has asked SimpleFIN \(Self.syncsPerDay) times in the last 24 hours, the most it allows without risking your connection. It can run again in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
        var next: String?
        if let due = Self.date(nextSyncAt) {
            next = due > now ? "Syncs by itself again about \(when(due))." : "The next sync by itself is due now."
        }

        guard let last = Self.date(lastSyncAt) else {
            return BankSyncSummary(tone: .neutral, headline: "Connected", detail: "Not synced yet.",
                                   next: next, canSync: wait == nil, waitText: wait)
        }
        if lastSyncOk == false {
            return BankSyncSummary(
                tone: .warning, headline: "Last sync failed",
                detail: "\(when(last)): \(lastSyncStatus ?? "SimpleFIN didn't answer.")",
                next: next, canSync: wait == nil, waitText: wait)
        }
        return BankSyncSummary(tone: .ok, headline: "Synced \(when(last))", detail: lastSyncStatus,
                               next: next, canSync: wait == nil, waitText: wait)
    }
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
}
