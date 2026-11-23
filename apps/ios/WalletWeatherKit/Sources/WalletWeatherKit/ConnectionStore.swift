import Foundation
import Security

/// A connection the phone keeps (Plans/connections.md, phase 1, #299): a
/// server signed in to, or the household on this iPhone. The demo is never
/// saved.
///
/// All of it, the server's address and the sign-in included, is one Keychain
/// item (`KeychainConnectionSecrets`): on this device only, readable only
/// while the phone is unlocked, never synced to iCloud.
public struct SavedConnection: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case server
        case thisPhone
    }

    public let id: UUID
    public var kind: Kind
    /// The name shown for it: the server's host, or "On this iPhone".
    public var name: String
    public var added: Date
    public var lastUsed: Date
    public var connection: Connection
    /// What the phone keeps for this connection (Nothing or Last-known
    /// numbers).
    public var keep: KeepChoice
    /// The theme saved in this server's web app, for Match the web app.
    public var webTheme: String?
    /// Who's signed in (their email), from `/api/me` while it's in front
    /// (phase 2, #300): what tells a second person on the same server from
    /// a new sign-in of the same one. Nil until known, and in items saved
    /// before it was kept.
    public var account: String?

    public init(id: UUID = UUID(), connection: Connection, name: String? = nil, added: Date = .now,
                lastUsed: Date? = nil, keep: KeepChoice = .nothing, webTheme: String? = nil,
                account: String? = nil) {
        self.id = id
        kind = connection.isLocal ? .thisPhone : .server
        self.name = name ?? Self.defaultName(for: connection)
        self.added = added
        self.lastUsed = lastUsed ?? added
        self.connection = connection
        self.keep = keep
        self.webTheme = webTheme
        self.account = account
    }

    /// The name a connection starts with: the server's host, or "On this
    /// iPhone". A name cleared by hand goes back to it.
    public static func defaultName(for connection: Connection) -> String {
        connection.isLocal ? "On this iPhone" : connection.host
    }
}

// MARK: - A sign-in: a new connection, or one already saved

/// What a sign-in does to the saved connections (phase 2, #300).
public enum SignInTarget: Equatable, Sendable {
    /// The same server and person: this connection's sign-in is replaced.
    case renew(UUID)
    /// A server not saved yet, or another person on one that is.
    case add
}

extension SavedConnection {
    /// Whether two addresses are the same server: the scheme, host (in any
    /// case), port and path, a trailing slash aside.
    public static func sameServer(_ a: URL, _ b: URL) -> Bool {
        func parts(_ url: URL) -> [String] {
            var path = url.path(percentEncoded: false)
            while path.hasSuffix("/") { path.removeLast() }
            let scheme = (url.scheme ?? "").lowercased()
            let port = url.port ?? (scheme == "http" ? 80 : 443)
            return [scheme, (url.host() ?? "").lowercased(), String(port), path]
        }
        return parts(a) == parts(b)
    }

    /// Which saved connection a sign-in to `server` as `account` (the
    /// signed-in person's email, when `/api/me` said) belongs to:
    ///
    /// - the one on that server signed in as the same person: renewed;
    /// - with the person known, one on that server whose person isn't
    ///   known yet (saved before it was kept): taken to be the same person
    ///   and renewed;
    /// - another person on that server, or a server not saved: added;
    /// - with the person not known, a new connection is added rather than
    ///   another's sign-in replaced, since it may be someone else's.
    public static func signInTarget(server: URL, account: String?, among saved: [SavedConnection]) -> SignInTarget {
        let onServer = saved.filter { $0.kind == .server && sameServer($0.connection.server, server) }
            .sorted { $0.lastUsed > $1.lastUsed }
        guard let account = account?.trimmingCharacters(in: .whitespaces).lowercased(), !account.isEmpty else {
            return .add
        }
        if let same = onServer.first(where: { $0.account?.lowercased() == account }) { return .renew(same.id) }
        if let unknown = onServer.first(where: { $0.account == nil }) { return .renew(unknown.id) }
        return .add
    }
}

// MARK: - Where the items live

/// The Keychain, as the connection store uses it: one generic-password item
/// per account name under one service. Tests use `MemoryConnectionSecrets`,
/// so they never touch a real Keychain.
public protocol ConnectionSecretStore: AnyObject, Sendable {
    /// Every account name the service holds.
    func accounts() -> [String]
    func read(_ account: String) -> Data?
    @discardableResult func write(_ data: Data, account: String) -> Bool
    func delete(_ account: String)
}

/// The connections in the Keychain, under the service the single sign-in
/// has always used: on this device only (never synced to iCloud Keychain,
/// never moved to another phone by a backup), readable only while the phone
/// is unlocked.
public final class KeychainConnectionSecrets: ConnectionSecretStore, @unchecked Sendable {
    /// Stable: the sign-in has always been kept under it.
    public static let service = "net.iptater.walletweather"

    public init() {}

    /// What finds an item; with no account, every item of the service.
    public static func query(account: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    /// What an item is saved with, besides its data: the same protection the
    /// single sign-in always had.
    public static func attributes(account: String) -> [String: Any] {
        var q = query(account: account)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return q
    }

    public func accounts() -> [String] {
        var q = Self.query(account: nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]] else { return [] }
        return list.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    public func read(_ account: String) -> Data? {
        var q = Self.query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Adds the item, or replaces its data when it's there: an existing item
    /// is never deleted first, so a failed write leaves it as it was.
    @discardableResult
    public func write(_ data: Data, account: String) -> Bool {
        var add = Self.attributes(account: account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let change = [kSecValueData as String: data]
            return SecItemUpdate(Self.query(account: account) as CFDictionary, change as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }

    public func delete(_ account: String) {
        SecItemDelete(Self.query(account: account) as CFDictionary)
    }
}

/// The items in memory, for tests and screenshots. `refusesWrites` makes
/// every write fail; `losesWrites` makes writes say they worked but keep
/// nothing, so reading back fails.
public final class MemoryConnectionSecrets: ConnectionSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data]
    private var refusing = false
    private var losing = false

    public init(_ items: [String: Data] = [:]) { self.items = items }

    public var refusesWrites: Bool {
        get { lock.withLock { refusing } }
        set { lock.withLock { refusing = newValue } }
    }

    public var losesWrites: Bool {
        get { lock.withLock { losing } }
        set { lock.withLock { losing = newValue } }
    }

    public func accounts() -> [String] { lock.withLock { Array(items.keys) } }
    public func read(_ account: String) -> Data? { lock.withLock { items[account] } }

    @discardableResult
    public func write(_ data: Data, account: String) -> Bool {
        lock.withLock {
            if refusing { return false }
            if !losing { items[account] = data }
            return true
        }
    }

    public func delete(_ account: String) { lock.withLock { _ = items.removeValue(forKey: account) } }
}

// MARK: - The store

/// The connections this phone keeps, and which one is in front.
///
/// - Each connection is its own Keychain item, account `connection.<id>`.
/// - Only the id of the one in front is in the app's settings
///   (`connections.active`); nothing else about a connection is.
/// - Its last-known numbers are in a folder of its own,
///   `Application Support/Kept/<id>/`, deleted when it's removed.
/// - The single sign-in kept before (account `connection`, with
///   `keep.choice` and `appearance.web` in the settings) is carried over
///   once by `carryOver()`, and removed only once its copy reads back.
public final class ConnectionStore: @unchecked Sendable {
    public enum CarryOver: Equatable, Sendable {
        /// There was no earlier sign-in (or it was already carried over).
        case nothingToCarry
        /// It's now this saved connection, and the old item is gone.
        case carried(SavedConnection)
        /// Its copy couldn't be written or read back: the old item stays,
        /// and is still the sign-in.
        case leftInPlace(Connection)
    }

    public let secrets: ConnectionSecretStore
    public let keptRoot: URL
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    public static let activeKey = "connections.active"
    /// Where the single sign-in was kept before (stable: read once, then
    /// removed).
    public static let legacyAccount = "connection"
    public static let legacyKeepKey = "keep.choice"
    /// The saved web theme; it stays as the theme in use (`AppSettings`).
    public static let webThemeKey = "appearance.web"
    static let prefix = "connection."

    public static func account(for id: UUID) -> String { prefix + id.uuidString.lowercased() }

    /// `Application Support/Kept`, inside the app's container.
    public static var standardKeptRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Kept", directoryHint: .isDirectory)
    }

    public init(secrets: ConnectionSecretStore, defaults: UserDefaults = .standard,
                keptRoot: URL = ConnectionStore.standardKeptRoot, now: @escaping @Sendable () -> Date = { Date() }) {
        self.secrets = secrets
        self.defaults = defaults
        self.keptRoot = keptRoot
        self.now = now
    }

    // MARK: Reading

    /// Every saved connection, oldest first.
    public func all() -> [SavedConnection] {
        secrets.accounts().filter { $0.hasPrefix(Self.prefix) }
            .compactMap { secrets.read($0).flatMap { try? JSONDecoder().decode(SavedConnection.self, from: $0) } }
            .sorted { ($0.added, $0.id.uuidString) < ($1.added, $1.id.uuidString) }
    }

    public func load(_ id: UUID) -> SavedConnection? {
        secrets.read(Self.account(for: id)).flatMap { try? JSONDecoder().decode(SavedConnection.self, from: $0) }
    }

    /// The id of the connection in front, as last recorded.
    public var activeID: UUID? {
        defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
    }

    /// The connection in front: the one recorded, or, when that's gone (the
    /// app's settings start empty after reinstalling, while the Keychain
    /// keeps its items), the one used last.
    public var active: SavedConnection? {
        if let id = activeID, let found = load(id) { return found }
        return mostRecentlyUsed
    }

    /// The connection used last: the one that comes in front when the one
    /// in front is signed out of.
    public var mostRecentlyUsed: SavedConnection? {
        all().max { ($0.lastUsed, $0.added) < ($1.lastUsed, $1.added) }
    }

    /// The last-known numbers of a connection, in its own folder.
    public func kept(for id: UUID) -> KeptResponses {
        KeptResponses(directory: keptRoot.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory))
    }

    // MARK: Changing

    /// Saves a new connection. The demo is never saved: nil, as when the
    /// Keychain refuses it.
    @discardableResult
    public func add(_ connection: Connection, name: String? = nil, keep: KeepChoice = .nothing,
                    webTheme: String? = nil, account: String? = nil) -> SavedConnection? {
        guard !connection.isDemo else { return nil }
        let date = now()
        let saved = SavedConnection(connection: connection, name: name, added: date, keep: keep,
                                    webTheme: webTheme, account: account)
        return write(saved) ? saved : nil
    }

    /// A new sign-in to a connection already saved (the same server and
    /// person): its token and Cloudflare sign-in are replaced; its name,
    /// keep choice, kept numbers and web theme stay. One whose person wasn't
    /// known until now starts with no kept numbers.
    @discardableResult
    public func renew(_ id: UUID, with connection: Connection, account: String? = nil) -> SavedConnection? {
        guard !connection.isDemo, var saved = load(id) else { return nil }
        // A connection saved before its person was known may have been
        // someone else's: its kept numbers aren't shown to this sign-in.
        if saved.account == nil, account != nil { kept(for: id).deleteAll() }
        saved.connection = connection
        if let account { saved.account = account }
        return write(saved) ? saved : nil
    }

    /// Renews the saved connection a sign-in belongs to, or adds it
    /// (`SavedConnection.signInTarget`). Nil when the Keychain refuses it.
    @discardableResult
    public func save(signIn connection: Connection, account: String?) -> (saved: SavedConnection, renewed: Bool)? {
        switch SavedConnection.signInTarget(server: connection.server, account: account, among: all()) {
        case let .renew(id):
            return renew(id, with: connection, account: account).map { ($0, true) }
        case .add:
            return add(connection, account: account).map { ($0, false) }
        }
    }

    /// Saves a change to a connection already saved.
    @discardableResult
    public func update(_ saved: SavedConnection) -> Bool {
        guard !saved.connection.isDemo else { return false }
        return write(saved)
    }

    /// Removes a connection: its last-known numbers, then its Keychain item.
    public func remove(_ id: UUID) {
        kept(for: id).deleteAll()
        secrets.delete(Self.account(for: id))
        if activeID == id { defaults.removeObject(forKey: Self.activeKey) }
    }

    /// Puts a connection in front, noting when it was last used. Nil puts
    /// none in front.
    @discardableResult
    public func activate(_ id: UUID?) -> SavedConnection? {
        guard let id else {
            defaults.removeObject(forKey: Self.activeKey)
            return nil
        }
        guard var saved = load(id) else { return nil }
        defaults.set(id.uuidString, forKey: Self.activeKey)
        saved.lastUsed = now()
        write(saved)
        return saved
    }

    private func write(_ saved: SavedConnection) -> Bool {
        guard let data = try? JSONEncoder().encode(saved) else { return false }
        return secrets.write(data, account: Self.account(for: saved.id))
    }

    // MARK: Carrying over the single sign-in

    /// The single sign-in kept before, while it's still there.
    public var legacy: Connection? {
        secrets.read(Self.legacyAccount).flatMap { try? JSONDecoder().decode(Connection.self, from: $0) }
    }

    /// Carries the single sign-in over, once: it's written as a saved
    /// connection with its keep choice and web theme, read back, its
    /// last-known numbers moved into its folder, and only then is the old
    /// item (and `keep.choice`) removed. If the copy can't be written or
    /// read back, the old item stays and is still the sign-in; the next
    /// start tries again. Nobody is signed out by updating.
    @discardableResult
    public func carryOver() -> CarryOver {
        guard let old = legacy else { return .nothingToCarry }
        // A copy made before the app stopped short of removing the old item.
        if let copy = all().first(where: { $0.connection == old }) {
            return finishCarryOver(copy)
        }
        let keep = legacyKeep
        let date = now()
        let copy = SavedConnection(connection: old, added: date, keep: keep,
                                   webTheme: defaults.string(forKey: Self.webThemeKey))
        guard write(copy), let back = load(copy.id), back.id == copy.id, back.connection == old else {
            secrets.delete(Self.account(for: copy.id))
            return .leftInPlace(old)
        }
        return finishCarryOver(copy)
    }

    private func finishCarryOver(_ copy: SavedConnection) -> CarryOver {
        if activeID.flatMap(load) == nil {
            defaults.set(copy.id.uuidString, forKey: Self.activeKey)
        }
        moveLegacyKept(to: copy.id)
        secrets.delete(Self.legacyAccount)
        defaults.removeObject(forKey: Self.legacyKeepKey)
        return .carried(copy)
    }

    /// The files kept before, straight in `Kept/`, go into the connection's
    /// folder; their names stay valid, since each is a hash that includes
    /// the server. One that can't be moved is deleted, so nothing is left
    /// behind that signing out wouldn't reach.
    private func moveLegacyKept(to id: UUID) {
        let fm = FileManager.default
        let files = legacyKeptFiles()
        guard !files.isEmpty else { return }
        let folder = kept(for: id).directory
        if !fm.fileExists(atPath: folder.path(percentEncoded: false)) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = folder
            try? url.setResourceValues(values)
        }
        for file in files {
            let target = folder.appending(path: file.lastPathComponent, directoryHint: .notDirectory)
            do {
                if fm.fileExists(atPath: target.path(percentEncoded: false)) { try fm.removeItem(at: target) }
                try fm.moveItem(at: file, to: target)
            } catch {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func legacyKeptFiles() -> [URL] {
        let list = (try? FileManager.default.contentsOfDirectory(
            at: keptRoot, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return list.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    /// While the single sign-in couldn't be carried over: its keep choice,
    /// still in `keep.choice`.
    public var legacyKeep: KeepChoice {
        get { KeepChoice(rawValue: defaults.string(forKey: Self.legacyKeepKey) ?? "") ?? .nothing }
        set { defaults.set(newValue.rawValue, forKey: Self.legacyKeepKey) }
    }

    /// While the single sign-in couldn't be carried over: its kept numbers,
    /// still straight in `Kept/`.
    public var legacyKept: KeptResponses { KeptResponses(directory: keptRoot) }

    /// Deletes the numbers kept straight in `Kept/`, leaving the
    /// connections' folders.
    public func deleteLegacyKept() {
        for file in legacyKeptFiles() { try? FileManager.default.removeItem(at: file) }
    }

    /// Saves the single sign-in again where it was (a new Cloudflare
    /// sign-in), while it couldn't be carried over.
    @discardableResult
    public func updateLegacy(_ connection: Connection) -> Bool {
        guard let data = try? JSONEncoder().encode(connection) else { return false }
        return secrets.write(data, account: Self.legacyAccount)
    }

    /// Signs out of the single sign-in that couldn't be carried over: the
    /// item, its keep choice and its kept numbers.
    public func removeLegacy() {
        deleteLegacyKept()
        secrets.delete(Self.legacyAccount)
        defaults.removeObject(forKey: Self.legacyKeepKey)
    }
}

// MARK: - A window's choice, per connection

/// A page's choice in one window (its account, kept with `@SceneStorage`)
/// belongs to the connection it was made on. The page's own key holds the
/// value for `owner`; this, kept in a second key beside it, remembers the
/// other connections' values, so a window coming back to a connection finds
/// its choice again and never reads another connection's id as one of its
/// own.
///
/// Written as `owner;key=value,key=value`. Empty text has no owner yet: the
/// value already in the page's key (from before connections were kept
/// apart) is taken as the connection in front's.
public struct ChoicePerConnection: Equatable, Sendable {
    public var owner: String?
    public var others: [String: Int]

    public init(_ text: String) {
        let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let first = parts.first.map(String.init) ?? ""
        owner = first.isEmpty ? nil : first
        var others: [String: Int] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: ",") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, let value = Int(kv[1]) { others[String(kv[0])] = value }
            }
        }
        self.others = others
    }

    public var text: String {
        guard let owner else { return "" }
        return owner + ";" + others.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// The connection in front is now `key`: `value` (the page's key) is put
    /// away for the one it belonged to, and becomes `key`'s own, or 0 (none
    /// chosen) when that has none.
    public mutating func move(_ value: inout Int, to key: String) {
        guard let owner else {
            self.owner = key
            return
        }
        guard owner != key else { return }
        if value != 0 { others[owner] = value } else { others.removeValue(forKey: owner) }
        value = others.removeValue(forKey: key) ?? 0
        self.owner = key
    }
}
