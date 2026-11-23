import CryptoKit
import Foundation
import Observation
import Security

// Bank sync on a phone without a server (Plans/standalone.md, phase 8,
// #239; design calls settled 2026-11-22): SimpleFIN only, since Teller's
// certificate and Plaid's secret must stay on a server. The phone claims a
// setup token as the server does (apps/server/app/simplefin.py), keeps the
// access address in the Keychain only (on this device, never in the
// household's store, a backup or iCloud sync), and pulls posted lines at
// most once every 23½ hours, whether the app opened or iOS gave it
// background time, with Sync now under the server's daily limit. New lines
// land in the household with their bank ref and are matched to bills by the
// shared core, as on the server (`LocalServer.landBankLines`).

/// SimpleFIN Bridge, as the server calls it (`simplefin.py`): a setup token
/// is a base64 address claimed once (POST) for an access address with Basic
/// credentials in it; GET <access>/accounts lists the bank accounts with
/// their posted lines. Every address must be https on SimpleFIN's own hosts,
/// and redirects are never followed.
public enum SimpleFIN {
    public static let hosts: Set<String> = ["bridge.simplefin.org", "beta-bridge.simplefin.org"]
    public static let maxDaysPerRequest = 90
    static let nameMax = 120, descriptionMax = 500, messageMax = 200

    /// What went wrong, in the server's own words. Never carries the access
    /// address. `revoked`: SimpleFIN no longer takes the connection.
    public struct Failure: Error, LocalizedError, Equatable, Sendable {
        public let message: String
        public var revoked = false
        public var errorDescription: String? { message }
    }

    /// A bank account and its posted lines.
    public struct Account: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let org: String
        public let transactions: [Line]

        public init(id: String, name: String, org: String, transactions: [Line] = []) {
            self.id = id
            self.name = name
            self.org = org
            self.transactions = transactions
        }
    }

    /// A posted line: its day (UTC, as the server reads it), its amount as
    /// an exact decimal string to the cent, and the bank's text.
    public struct Line: Codable, Equatable, Sendable {
        public let id: String
        public let date: LocalDay
        public let amount: String
        public let description: String

        public init(id: String, date: LocalDay, amount: String, description: String) {
            self.id = id
            self.date = date
            self.amount = amount
            self.description = description
        }
    }

    public struct AccountSet: Equatable, Sendable {
        public let accounts: [Account]
        public let messages: [String]
    }

    static let notAToken = Failure(message: "That doesn't look like a SimpleFIN setup token. Copy it again from SimpleFIN Bridge.")

    /// The address split, if it's https on SimpleFIN's host and port.
    static func checked(_ text: String) throws(Failure) -> URLComponents {
        guard let parts = URLComponents(string: text) else { throw notAToken }
        let host = (parts.host ?? "").lowercased()
        guard parts.scheme == "https", !host.isEmpty, parts.port == nil || parts.port == 443 else {
            throw Failure(message: "That token doesn't point at SimpleFIN over a secure connection. Nothing was sent.")
        }
        guard hosts.contains(host) else {
            throw Failure(message: "That token points at \(host.prefix(80)), which isn't SimpleFIN. Nothing was sent to it.")
        }
        return parts
    }

    /// Exchanges a setup token for its access address. A token works once.
    public static func claim(_ token: String, session: URLSession) async throws(Failure) -> String {
        let plain = token.filter { !$0.isWhitespace }
        let padded = plain + String(repeating: "=", count: (4 - plain.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), let text = String(data: data, encoding: .ascii) else {
            throw notAToken
        }
        let parts = try checked(text)
        guard parts.user == nil, parts.password == nil, let url = parts.url else { throw notAToken }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        let (body, status) = try await send(request, session: session)
        if status == 403 {
            throw Failure(message: "SimpleFIN says this token was already used or doesn't exist. If you didn't use it yourself, disable it at SimpleFIN Bridge, then make a new one.")
        }
        guard status == 200 else {
            throw Failure(message: "SimpleFIN didn't accept the token (HTTP \(status)). Try again in a while.")
        }
        let access = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try split(access)   // checks the host SimpleFIN sent back, too
        return access
    }

    /// (the access address without its credentials, user, password).
    static func split(_ access: String) throws(Failure) -> (URL, String, String) {
        let parts = try checked(access)
        guard let user = parts.user, let password = parts.password, !user.isEmpty, !password.isEmpty else {
            throw Failure(message: "SimpleFIN sent back something that isn't an access address. Try connecting again with a new token.")
        }
        var base = URLComponents()
        base.scheme = "https"
        base.host = parts.host
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        base.path = path
        guard let url = base.url else { throw notAToken }
        return (url, user.removingPercentEncoding ?? user, password.removingPercentEncoding ?? password)
    }

    /// The bank accounts and, unless `balancesOnly`, their posted lines
    /// since `start`; one request, so the caller keeps `start` within 90 days.
    public static func fetch(access: String, start: LocalDay?, balancesOnly: Bool = false,
                             session: URLSession) async throws(Failure) -> AccountSet {
        let (base, user, password) = try split(access)
        var parts = URLComponents(url: base.appending(path: "accounts"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if balancesOnly { query.append(URLQueryItem(name: "balances-only", value: "1")) }
        if let start { query.append(URLQueryItem(name: "start-date", value: String(epoch(start)))) }
        parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: parts.url!)
        request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (body, status) = try await send(request, session: session)
        switch status {
        case 200: break
        case 402: throw Failure(message: "SimpleFIN says your subscription needs paying. Renew it at SimpleFIN Bridge, then sync again.")
        case 403: throw Failure(message: "SimpleFIN no longer accepts this connection: it may have been disabled there. Disconnect, then connect again with a new token.", revoked: true)
        default: throw Failure(message: "SimpleFIN answered with an error (HTTP \(status)). Try again in a while.")
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["accounts"] is [Any] else {
            throw Failure(message: "SimpleFIN sent something this iPhone can't read. Try again in a while.")
        }
        return parse(object)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws(Failure) -> (Data, Int) {
        var request = request
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request, delegate: NoRedirects())
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure(message: "Couldn't reach SimpleFIN. Try again in a while.")
        }
    }

    static func epoch(_ day: LocalDay) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))!
        return Int(date.timeIntervalSince1970)
    }

    static func day(epoch: Int) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(epoch)))
        return LocalDay(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Bank text cut to size, with control characters as spaces.
    static func text(_ value: Any?, _ limit: Int) -> String {
        let raw: String
        switch value {
        case let s as String: raw = s
        case let n as NSNumber: raw = n.stringValue
        default: raw = ""
        }
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.map {
            $0.value < 0x20 || $0.value == 0x7f ? " " : $0
        }))
        return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// An amount as Python's Decimal(str(value)).quantize(0.01) gives it,
    /// as a decimal string; nil when it isn't a number or is absurd.
    static func amount(_ value: Any?) -> String? {
        let raw: String
        switch value {
        case let s as String: raw = s.trimmingCharacters(in: .whitespaces)
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): raw = n.stringValue
        default: return nil
        }
        guard raw.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              var number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        guard !number.isNaN, abs(number) <= Decimal(string: "1e12")! else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &number, 2, .bankers)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    static func id(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): return n.stringValue
        default: return nil
        }
    }

    /// SimpleFIN's account set, keeping what the app uses. Pending lines are
    /// left out: sync waits until the bank posts them, as on the server.
    static func parse(_ data: [String: Any]) -> AccountSet {
        var orgs: [String: String] = [:]
        for conn in data["connections"] as? [[String: Any]] ?? [] {
            if let cid = id(conn["conn_id"]) { orgs[cid] = conn["name"] as? String }
        }
        var accounts: [Account] = []
        for a in data["accounts"] as? [Any] ?? [] {
            guard let a = a as? [String: Any], let aid = id(a["id"]) else { continue }
            let org = id(a["conn_id"]).flatMap { orgs[$0] } ?? (a["org"] as? [String: Any])?["name"] as? String
            var lines: [Line] = []
            for t in a["transactions"] as? [Any] ?? [] {
                guard let t = t as? [String: Any] else { continue }
                if let pending = t["pending"] as? NSNumber, CFGetTypeID(pending) == CFBooleanGetTypeID(), pending.boolValue { continue }
                guard let tid = id(t["id"]), let posted = t["posted"] as? NSNumber,
                      CFGetTypeID(posted) != CFBooleanGetTypeID(), posted.doubleValue == posted.doubleValue.rounded(),
                      posted.int64Value > 0, let amount = amount(t["amount"]) else { continue }
                let description = text(t["description"], descriptionMax)
                lines.append(Line(id: tid, date: day(epoch: Int(posted.int64Value)), amount: amount,
                                  description: description.isEmpty ? "Bank transaction" : description))
            }
            let name = text(a["name"], nameMax)
            accounts.append(Account(id: aid, name: name.isEmpty ? "Bank account" : name,
                                    org: text(org, nameMax), transactions: lines))
        }
        var messages: [String] = []
        for e in data["errlist"] as? [Any] ?? [] {
            if let e = e as? [String: Any], let msg = e["msg"], !text(msg, messageMax).isEmpty { messages.append(text(msg, messageMax)) }
        }
        for e in data["errors"] as? [Any] ?? [] {
            if let e = e as? String, !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append(text(e, messageMax)) }
        }
        return AccountSet(accounts: accounts, messages: Array(messages.prefix(5)))
    }

    /// The server's bank_account_ref and bank_txn_ref (main.py), so a line
    /// the phone brought in is the same line to a server it moves to.
    public static func accountRef(_ bankAccount: String) -> String { sha256("simplefin-account:\(bankAccount)") }
    public static func lineRef(_ bankAccount: String, _ line: String) -> String { sha256("simplefin:\(bankAccount):\(line)") }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// simplefin.short_name, from the shared core: a synced line's name when
    /// the bank's text carries more than a name; nil when there's nothing to
    /// shorten.
    public static func shortName(_ text: String?) -> String? {
        guard let text, text.contains(" / "),
              let literal = try? JSONSerialization.data(withJSONObject: [text]),
              let answer = try? Core.shared.evaluate("JSON.stringify(WalletWeatherCore._shortName(\(String(decoding: literal, as: UTF8.self))[0]))"),
              let value = try? JSONSerialization.jsonObject(with: Data(answer.utf8), options: .fragmentsAllowed) as? String
        else { return nil }
        return value
    }
}

// MARK: - The access address, in the Keychain only

/// Where the SimpleFIN access address is kept. The app's is the Keychain;
/// the tests and the screenshots use one in memory.
public protocol BankSecretStore: AnyObject, Sendable {
    func read() -> String?
    @discardableResult func write(_ secret: String) -> Bool
    func delete()
}

/// The access address in the Keychain: on this device only (never synced
/// to iCloud Keychain, never moved to another phone by a backup), and
/// readable after the phone's first unlock so a sync in the background can
/// use it. Nothing else holds it: not the household's store, its backups or
/// iCloud sync, and not the app's settings.
public final class KeychainBankSecret: BankSecretStore, @unchecked Sendable {
    public init() {}

    /// What finds the item.
    nonisolated(unsafe) public static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "net.iptater.walletweather.simplefin",
        kSecAttrAccount as String: "access",
        kSecAttrSynchronizable as String: false,
    ]

    /// What it's saved with, besides the address itself.
    public static var saved: [String: Any] {
        var q = query
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecAttrLabel as String] = "WalletWeather SimpleFIN connection"
        return q
    }

    public func read() -> String? {
        var q = Self.query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func write(_ secret: String) -> Bool {
        delete()
        var q = Self.saved
        q[kSecValueData as String] = Data(secret.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        SecItemDelete(Self.query as CFDictionary)
    }
}

/// An access address in memory only, for the tests and the screenshots.
public final class MemoryBankSecret: BankSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public func read() -> String? { lock.withLock { value } }
    @discardableResult public func write(_ secret: String) -> Bool { lock.withLock { value = secret }; return true }
    public func delete() { lock.withLock { value = nil } }
}

// MARK: - The connection's state, on this phone

/// What this phone knows about its SimpleFIN connection, apart from the
/// access address: the bank accounts SimpleFIN listed, which of the phone's
/// accounts each is matched to, when it last asked SimpleFIN and how that
/// went. Kept in this phone's settings (it's this phone's connection, like
/// the Keychain item), never in the household's store.
public struct PhoneBankState: Codable, Equatable, Sendable {
    public struct Link: Codable, Equatable, Sendable {
        public let bankAccount: String
        public var account: Int
        /// Lines from before this day aren't brought in ("Bring in from").
        public var startDate: LocalDay
        public var syncedThrough: LocalDay?

        public init(bankAccount: String, account: Int, startDate: LocalDay, syncedThrough: LocalDay? = nil) {
            self.bankAccount = bankAccount
            self.account = account
            self.startDate = startDate
            self.syncedThrough = syncedThrough
        }
    }

    public var bankAccounts: [SimpleFIN.Account] = []
    public var links: [Link] = []
    /// Every call to SimpleFIN in the last 24 hours (the daily limit).
    public var calls: [Date] = []
    public var lastSyncAt: Date?
    public var lastSyncOk: Bool?
    public var lastSyncStatus: String?
    public var needsReconnect = false
    /// Lines on the Unmatched list after the last sync, all accounts.
    public var unmatched = 0

    public init() {}

    public func link(for bankAccount: String) -> Link? { links.first { $0.bankAccount == bankAccount } }
}

/// The result of a sync, as the server's Sync now gives it.
public struct PhoneBankResult: Equatable, Sendable {
    public let added: Int
    public let matched: Int
    public let skipped: Int
    public let messages: [String]
}

/// Bank sync on a phone without a server: connecting, matching bank
/// accounts, the two guards and the sync itself. One per app; all of it on
/// the main actor, apart from SimpleFIN's answers and the household's lock.
@MainActor @Observable
public final class PhoneBank {
    /// The background task iOS runs it in (project.yml's
    /// BGTaskSchedulerPermittedIdentifiers).
    public static let taskID = "net.iptater.walletweather.banksync"
    /// The server's BANK_SYNC_EVERY: a sync by itself at most this often.
    public static let syncEvery: TimeInterval = 23.5 * 3600
    /// The server's BANK_CALLS_PER_DAY: SimpleFIN Bridge disables a token
    /// that asks much more than 24 times a day.
    public static let callsPerDay = 20
    /// The server's BANK_OVERLAP_DAYS: each sync looks again this far
    /// before the last, for lines a bank posts late.
    public static let overlapDays = 14

    @ObservationIgnored public let secrets: BankSecretStore
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let session: URLSession
    @ObservationIgnored let household: () throws -> LocalServer
    private static let stateKey = "phoneBank.state"

    public private(set) var state: PhoneBankState
    /// Whether a sync is running (only one at a time).
    public private(set) var busy = false

    public init(secrets: BankSecretStore, defaults: UserDefaults = .standard, session: URLSession = .shared,
                household: @escaping () throws -> LocalServer = { try LocalServer.openShared() }) {
        self.secrets = secrets
        self.defaults = defaults
        self.session = session
        self.household = household
        state = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(PhoneBankState.self, from: $0) } ?? PhoneBankState()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.stateKey) }
    }

    /// Connected: the access address is in the Keychain.
    public var connected: Bool { secrets.read() != nil }

    // MARK: Connecting

    /// Claims a setup token, keeps the access address in the Keychain and
    /// lists the bank accounts (a call, as on the server). A listing that
    /// fails keeps the address: the next Sync now lists them again.
    public func connect(token: String, now: Date = .now) async throws(SimpleFIN.Failure) {
        let access = try await SimpleFIN.claim(token, session: session)
        guard secrets.write(access) else {
            throw SimpleFIN.Failure(message: "This iPhone couldn't keep the connection in its Keychain. Nothing was saved; make a new token and try again.")
        }
        state = PhoneBankState()
        note(call: now)
        do {
            state.bankAccounts = try await SimpleFIN.fetch(access: access, start: nil, balancesOnly: true, session: session).accounts
        } catch {
            state.lastSyncAt = now
            state.lastSyncOk = false
            state.lastSyncStatus = error.message
        }
        save()
    }

    /// Forgets the connection: the Keychain item and what this phone knew
    /// about it. Lines already brought in stay.
    public func disconnect() {
        secrets.delete()
        state = PhoneBankState()
        save()
    }

    /// Matches a bank account to one of the phone's accounts (nil: leave it
    /// out), bringing lines in from `start` (today, up to 90 days back).
    public func link(_ bankAccount: String, to account: Int?, start: LocalDay? = nil, today: LocalDay = .today()) {
        let floor = today.adding(days: -SimpleFIN.maxDaysPerRequest)
        let day = min(max(start ?? today, floor), today)
        if let account {
            if let i = state.links.firstIndex(where: { $0.bankAccount == bankAccount }) {
                if state.links[i].account != account { state.links[i].syncedThrough = nil }
                state.links[i].account = account
                if state.links[i].startDate != day { state.links[i].startDate = day; state.links[i].syncedThrough = nil }
            } else {
                state.links.append(PhoneBankState.Link(bankAccount: bankAccount, account: account, startDate: day))
            }
        } else {
            state.links.removeAll { $0.bankAccount == bankAccount }
        }
        save()
    }

    // MARK: The two guards

    private func note(call: Date) {
        state.calls = state.calls.filter { call.timeIntervalSince($0) < 86_400 } + [call]
    }

    /// Seconds until SimpleFIN may be asked again (the server's
    /// _bank_call_wait); 0 when it may.
    public func waitSeconds(now: Date = .now) -> Int {
        let calls = state.calls.filter { now.timeIntervalSince($0) < 86_400 }.sorted()
        guard calls.count >= Self.callsPerDay else { return 0 }
        let free = calls[calls.count - Self.callsPerDay].addingTimeInterval(86_400)
        return max(1, Int(free.timeIntervalSince(now).rounded(.up)))
    }

    /// The server's words when the limit is reached.
    public static func waitText(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        return "Bank sync has asked SimpleFIN \(callsPerDay) times in the last 24 hours, the most it allows without risking your connection. It can run again in \(minutes) minute\(minutes == 1 ? "" : "s")."
    }

    /// Whether a sync by itself is due: connected, an account matched, and
    /// 23½ hours since the last sync (by itself or Sync now, failed or not),
    /// under the daily limit, and not after SimpleFIN stopped taking it.
    public func isDue(now: Date = .now) -> Bool {
        guard connected, !state.links.isEmpty, !state.needsReconnect, waitSeconds(now: now) == 0 else { return false }
        guard let last = state.lastSyncAt else { return true }
        return now.timeIntervalSince(last) >= Self.syncEvery
    }

    /// When a sync by itself is next due, for the card.
    public func nextSyncAt() -> Date? {
        guard connected, !state.links.isEmpty, !state.needsReconnect else { return nil }
        return state.lastSyncAt.map { $0.addingTimeInterval(Self.syncEvery) } ?? .now
    }

    // MARK: Syncing

    /// Syncs if one is due (the app opened, or iOS gave it background time);
    /// nil when none was.
    @discardableResult
    public func syncIfDue(now: Date = .now) async -> PhoneBankResult? {
        guard isDue(now: now), !busy else { return nil }
        return try? await sync(now: now)
    }

    /// Sync now, and the sync by itself: asks SimpleFIN for every matched
    /// bank account's lines since the last sync (less two weeks, for lines
    /// posted late) and lands the new ones.
    @discardableResult
    public func sync(now: Date = .now, today: LocalDay = .today()) async throws(SimpleFIN.Failure) -> PhoneBankResult {
        guard let access = secrets.read() else {
            throw SimpleFIN.Failure(message: "No bank is connected on this iPhone.")
        }
        guard !state.links.isEmpty else {
            throw SimpleFIN.Failure(message: "Match at least one bank account to one of your accounts first.")
        }
        guard !busy else { throw SimpleFIN.Failure(message: "A sync is already running.") }
        let wait = waitSeconds(now: now)
        if wait > 0 { throw SimpleFIN.Failure(message: Self.waitText(wait)) }
        busy = true
        defer { busy = false }
        let floor = today.adding(days: -SimpleFIN.maxDaysPerRequest)
        let links = state.links
        func linkStart(_ l: PhoneBankState.Link) -> LocalDay {
            let since = l.syncedThrough.map { $0.adding(days: -Self.overlapDays) } ?? l.startDate
            return max(l.startDate, since, floor)
        }
        let start = links.map(linkStart).min()!
        note(call: now)   // the call counts even if it fails
        save()
        let fetched: SimpleFIN.AccountSet
        do {
            fetched = try await SimpleFIN.fetch(access: access, start: start, session: session)
        } catch {
            state.lastSyncAt = now
            state.lastSyncOk = false
            state.lastSyncStatus = String(error.message.prefix(300))
            if error.revoked { state.needsReconnect = true }
            save()
            throw error
        }
        if !fetched.accounts.isEmpty {
            state.bankAccounts = fetched.accounts.map { SimpleFIN.Account(id: $0.id, name: $0.name, org: $0.org) }
        }
        let landed: LocalServer.Landed
        do {
            landed = try household().landBankLines(fetched, links: links)
        } catch {
            state.lastSyncAt = now
            state.lastSyncOk = false
            state.lastSyncStatus = "The lines couldn't be saved on this iPhone: \(error.localizedDescription)"
            save()
            throw SimpleFIN.Failure(message: state.lastSyncStatus!)
        }
        for i in state.links.indices where landed.listed.contains(state.links[i].bankAccount) {
            state.links[i].syncedThrough = today
        }
        var status = "\(landed.added) new line\(landed.added == 1 ? "" : "s"), "
            + (landed.matched > 0 ? "\(landed.matched) matched a bill, " : "")
            + "\(landed.skipped) already here"
        if !fetched.messages.isEmpty { status += ". SimpleFIN said: " + fetched.messages.joined(separator: "; ") }
        state.lastSyncAt = now
        state.lastSyncOk = true
        state.lastSyncStatus = String(status.prefix(300))
        state.needsReconnect = false
        state.unmatched = landed.unmatched
        save()
        return PhoneBankResult(added: landed.added, matched: landed.matched, skipped: landed.skipped,
                               messages: fetched.messages)
    }

    /// Counts the Unmatched list again (after matching or leaving lines).
    public func recount() {
        guard let server = try? household() else { return }
        state.unmatched = server.unmatchedTotal(accounts: Set(state.links.map(\.account)))
        save()
    }
}
