import Foundation

// Email alerts in the iPhone app (Plans/bank-alert-emails.md, phase 6, #211):
// the mailbox's state and Check now, on Settings → Bank sync under the bank
// cards (decided 2026-11-24: both bring lines in, so one place). Connecting a
// mailbox and teaching senders stay in the web app. A server only: the
// household on this iPhone has no email alerts, and the demo shows a sample.

/// `GET /api/mail/status` (server 1.74.0 or later): what an app needs to
/// show the mailbox's state; never its address, folder or senders.
public struct MailStatus: Sendable, Codable, Equatable {
    /// Whether an admin has email alerts switched on on this server.
    public let enabled: Bool
    public let connected: Bool
    public let checkMinutes: Int?
    public let lastCheckAt: String?
    public let lastCheckOk: Bool?
    /// The last check in the server's words: "2 new lines, 1 matched".
    public let lastCheckStatus: String?
    public let lastOkAt: String?
    public let needsReconnect: Bool?
    public let paused: Bool?
    public let failingSince: String?
    public let failingOverADay: Bool?
    public let nextCheckAt: String?
    /// Alerts from taught senders that didn't become lines.
    public let unreadCount: Int?

    public init(enabled: Bool, connected: Bool, checkMinutes: Int? = nil, lastCheckAt: String? = nil,
                lastCheckOk: Bool? = nil, lastCheckStatus: String? = nil, lastOkAt: String? = nil,
                needsReconnect: Bool? = nil, paused: Bool? = nil, failingSince: String? = nil,
                failingOverADay: Bool? = nil, nextCheckAt: String? = nil, unreadCount: Int? = nil) {
        self.enabled = enabled
        self.connected = connected
        self.checkMinutes = checkMinutes
        self.lastCheckAt = lastCheckAt
        self.lastCheckOk = lastCheckOk
        self.lastCheckStatus = lastCheckStatus
        self.lastOkAt = lastOkAt
        self.needsReconnect = needsReconnect
        self.paused = paused
        self.failingSince = failingSince
        self.failingOverADay = failingOverADay
        self.nextCheckAt = nextCheckAt
        self.unreadCount = unreadCount
    }

    /// Where a mailbox is connected and its alerts are read.
    public static let webAppPlace = "the web app's Settings → Email alerts"

    /// The Email alerts card, in plain words. `when` writes a time the way
    /// the app shows times ("today at 3:12 PM").
    public func summary(now: Date = .now, when: (Date) -> String) -> MailSummary {
        guard enabled else {
            return MailSummary(tone: .neutral, headline: "Email alerts are switched off on this server",
                               lines: ["An admin can switch them on in Admin."])
        }
        guard connected else {
            return MailSummary(tone: .neutral, headline: "No mailbox connected",
                               lines: ["Connect one in \(Self.webAppPlace), and your bank's alert emails become lines here."])
        }
        var lines: [String] = []
        let unread = unreadCount ?? 0
        if unread > 0 {
            lines.append("\(unread) alert\(unread == 1 ? "" : "s") couldn't be read: see \(unread == 1 ? "it" : "them") in \(Self.webAppPlace).")
        }
        if needsReconnect == true {
            return MailSummary(tone: .warning, headline: "Needs reconnecting",
                               lines: ["The mailbox's sign-in has ended. Reconnect it in \(Self.webAppPlace)."] + lines)
        }
        if paused == true {
            return MailSummary(tone: .warning, headline: "Paused",
                               lines: ["An admin has paused email alerts for you."] + lines)
        }
        let next = BankStatus.date(nextCheckAt).map { "Next check \(when($0))." }
        if lastCheckOk == false {
            var why = ["The last check didn't work" + (lastCheckStatus.map { ": \($0)" } ?? ".")]
            if failingOverADay == true, let since = BankStatus.date(failingSince) { why.append("Failing since \(when(since)).") }
            return MailSummary(tone: .warning, headline: "Last check failed", lines: why + lines, next: next, canCheck: true)
        }
        guard let last = BankStatus.date(lastCheckAt) else {
            return MailSummary(tone: .neutral, headline: "Not checked yet", lines: lines, next: next, canCheck: true)
        }
        let status = lastCheckStatus.flatMap { $0.isEmpty ? nil : $0 }
        return MailSummary(tone: unread > 0 ? .warning : .ok, headline: "Checked \(when(last))",
                           lines: (status.map { [$0] } ?? []) + lines, next: next, canCheck: true)
    }

    /// What the Bank sync row on Settings' root list says for the mailbox
    /// when it needs a look; nil when all's well (the banks' value shows).
    public var rowAttention: String? {
        guard enabled, connected else { return nil }
        if needsReconnect == true { return "Alerts: reconnect" }
        if lastCheckOk == false { return "Alerts: check failed" }
        let unread = unreadCount ?? 0
        return unread > 0 ? "\(unread) alert\(unread == 1 ? "" : "s") unread" : nil
    }
}

/// The Email alerts card's words.
public struct MailSummary: Sendable, Equatable {
    public let tone: BankSyncSummary.Tone
    public let headline: String
    public let lines: [String]
    public let next: String?
    /// Whether Check now is offered (never to a read-only sign-in, which the
    /// card hides on its own).
    public let canCheck: Bool

    public init(tone: BankSyncSummary.Tone, headline: String, lines: [String] = [], next: String? = nil,
                canCheck: Bool = false) {
        self.tone = tone
        self.headline = headline
        self.lines = lines
        self.next = next
        self.canCheck = canCheck
    }
}

/// `POST /api/mail/check`: what Check now did.
public struct MailCheckResult: Sendable, Decodable, Equatable {
    public let added: Int
    public let matched: Int?
    public let skipped: Int?
    public let unread: Int?

    /// "2 new lines, 1 paid a bill", or that nothing was new.
    public var said: String {
        guard added > 0 else {
            let unread = unread ?? 0
            return unread > 0 ? "No new lines; \(unread) alert\(unread == 1 ? "" : "s") couldn't be read." : "No new alerts."
        }
        var text = "\(added) new line\(added == 1 ? "" : "s")"
        if let matched, matched > 0 { text += ", \(matched) paid a planned bill" }
        return text + "."
    }
}

extension BankStatus {
    /// The Bank sync row's value with email alerts too (#211): the banks'
    /// own trouble first, then the mailbox's, then the banks' usual value.
    public func settingsValue(unmatched: Int = 0, mail: MailStatus?, when: (Date) -> String) -> String {
        let banks = settingsValue(unmatched: unmatched, when: when)
        let banksNeedALook = ["Needs reconnecting", "Last sync failed"].contains(banks) || unmatched > 0
        if !banksNeedALook, let mail = mail?.rowAttention { return mail }
        return banks
    }
}

extension APIClient {
    /// The mailbox's state; nil on a server without email alerts' status
    /// (older than 1.74.0).
    public func mailStatus() async throws(APIError) -> MailStatus? {
        do {
            return try await get("/api/mail/status")
        } catch .notWalletWeather, .server(status: 404, detail: _) {
            return nil
        }
    }

    /// Check now: reads new alerts from the mailbox's folder. A read-only
    /// token is refused; the server answers 409 while a check is running.
    /// The phone's offset from UTC makes "today" the person's own.
    public func checkMailNow(utcOffsetMinutes: Int = TimeZone.current.secondsFromGMT() / 60)
        async throws(APIError) -> MailCheckResult {
        try await send("POST", "/api/mail/check", body: ["utc_offset_minutes": utcOffsetMinutes])
    }
}
