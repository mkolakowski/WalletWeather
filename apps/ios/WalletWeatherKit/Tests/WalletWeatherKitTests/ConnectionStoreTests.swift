import Foundation
import Security
import Testing
@testable import WalletWeatherKit

/// Several saved connections (Plans/connections.md, phase 1, #299): the
/// single sign-in carried over without signing anyone out, adding, removing
/// and switching, kept numbers per connection, and the Keychain item's
/// protection unchanged. In memory and temporary folders only: never the
/// real Keychain, settings or Application Support.
struct ConnectionStoreTests {
    let secrets = MemoryConnectionSecrets()
    let suite = "ww-connections-\(UUID().uuidString)"
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appending(path: "connections-tests-\(UUID().uuidString)")
    static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let store: ConnectionStore

    let server = Connection(server: URL(string: "https://money.example.test")!, token: "ww_token")
    let cloudflared = Connection(server: URL(string: "https://behind.example.test")!, token: "ww_other",
                                 cloudflare: .serviceToken(clientID: "id.access", secret: "shh"))

    init() {
        defaults = UserDefaults(suiteName: suite)!
        store = ConnectionStore(secrets: secrets, defaults: defaults, keptRoot: root, now: { Self.date })
    }

    func tidy() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    /// Today's single item, as `Keychain.saveConnection` wrote it.
    func putLegacy(_ connection: Connection, keep: String? = nil, theme: String? = nil) throws {
        secrets.write(try JSONEncoder().encode(connection), account: "connection")
        if let keep { defaults.set(keep, forKey: "keep.choice") }
        if let theme { defaults.set(theme, forKey: "appearance.web") }
    }

    /// A file straight in `Kept/`, as the single sign-in kept them.
    func putLegacyKept(_ key: String, _ body: String) {
        KeptResponses(directory: root).save(Data(body.utf8), for: key)
    }

    // MARK: Carrying over

    @Test func carriesOverAServerSignIn() throws {
        defer { tidy() }
        try putLegacy(server, keep: "lastKnown", theme: "dark-dimmed")
        guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
        #expect(copy.connection == server)
        #expect(copy.kind == .server)
        #expect(copy.name == "money.example.test")
        #expect(copy.keep == .lastKnown)
        #expect(copy.webTheme == "dark-dimmed")
        #expect(copy.added == Self.date)
        #expect(store.active == copy)
        #expect(store.activeID == copy.id)
        #expect(secrets.read("connection") == nil)
        #expect(defaults.string(forKey: "keep.choice") == nil)
        // The theme in use stays where the app reads it.
        #expect(defaults.string(forKey: "appearance.web") == "dark-dimmed")
        #expect(Set(secrets.accounts()) == ["connection.\(copy.id.uuidString.lowercased())"])
        // Once only.
        #expect(store.carryOver() == .nothingToCarry)
        #expect(store.all().count == 1)
    }

    @Test func carriesOverACloudflareSignIn() throws {
        defer { tidy() }
        let session = Connection(server: URL(string: "https://cf.example.test")!, token: "ww_t",
                                 cloudflare: .session(token: "header.payload.sig"))
        for connection in [cloudflared, session] {
            try putLegacy(connection)
            guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
            #expect(copy.connection == connection)
            #expect(copy.connection.cloudflare == connection.cloudflare)
            #expect(copy.keep == .nothing)
            #expect(copy.webTheme == nil)
            store.remove(copy.id)
        }
    }

    @Test func carriesOverTheHouseholdOnThisPhone() throws {
        defer { tidy() }
        try putLegacy(LocalServer.connection, keep: "nothing")
        guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
        #expect(copy.kind == .thisPhone)
        #expect(copy.name == "On this iPhone")
        #expect(copy.connection.isLocal)
        #expect(store.active?.id == copy.id)
    }

    @Test func nothingSavedCarriesNothing() {
        defer { tidy() }
        defaults.set("lastKnown", forKey: "keep.choice")
        #expect(store.carryOver() == .nothingToCarry)
        #expect(store.all().isEmpty)
        #expect(store.active == nil)
        #expect(secrets.accounts().isEmpty)
        // Not ours to tidy while nothing was carried.
        #expect(defaults.string(forKey: "keep.choice") == "lastKnown")
    }

    @Test func aFailedWriteLeavesTheOldItem() throws {
        defer { tidy() }
        try putLegacy(server, keep: "lastKnown")
        putLegacyKept("a", "{}")
        secrets.refusesWrites = true
        #expect(store.carryOver() == .leftInPlace(server))
        #expect(store.legacy == server)
        #expect(defaults.string(forKey: "keep.choice") == "lastKnown")
        #expect(store.legacyKept.load("a") != nil)
        #expect(store.all().isEmpty)
        // Next start, with the Keychain working again.
        secrets.refusesWrites = false
        guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
        #expect(copy.connection == server)
        #expect(store.kept(for: copy.id).load("a") != nil)
    }

    @Test func aCopyThatDoesntReadBackLeavesTheOldItem() throws {
        defer { tidy() }
        try putLegacy(server, keep: "lastKnown")
        secrets.losesWrites = true
        #expect(store.carryOver() == .leftInPlace(server))
        #expect(store.legacy == server)
        #expect(defaults.string(forKey: "keep.choice") == "lastKnown")
        #expect(store.activeID == nil)
    }

    @Test func aCopyLeftByAnEarlierStartIsReused() throws {
        defer { tidy() }
        try putLegacy(server)
        let earlier = try #require(store.add(server))
        guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
        #expect(copy.id == earlier.id)
        #expect(store.all().count == 1)
        #expect(store.legacy == nil)
    }

    @Test func theOldFlatKeptFilesMove() throws {
        defer { tidy() }
        try putLegacy(server, keep: "lastKnown")
        let key = KeptResponses.key(server: server.server, method: "GET", path: "/api/accounts", query: [:])
        putLegacyKept(key, "[1]")
        putLegacyKept("other", "[2]")
        guard case let .carried(copy) = store.carryOver() else { Issue.record("not carried"); return }
        let kept = store.kept(for: copy.id)
        #expect(kept.count == 2)
        #expect(kept.load(key)?.data == Data("[1]".utf8))
        #expect(kept.directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        // Nothing is left straight in Kept/.
        let left = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(left.map(\.lastPathComponent) == [copy.id.uuidString.lowercased()])
        let values = try kept.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    // MARK: Adding, removing, switching

    @Test func addRemoveAndSwitch() throws {
        defer { tidy() }
        let first = try #require(store.add(server))
        let second = try #require(store.add(cloudflared, name: "Work"))
        #expect(second.name == "Work")
        #expect(Set(store.all().map(\.id)) == [first.id, second.id])
        #expect(store.activate(first.id)?.id == first.id)
        #expect(store.active?.id == first.id)
        #expect(store.activate(second.id)?.id == second.id)
        #expect(store.active?.connection == cloudflared)
        store.remove(second.id)
        #expect(store.load(second.id) == nil)
        #expect(store.activeID == nil)
        // With none recorded, the one used last is in front (as after a
        // reinstall, when the Keychain keeps its items).
        #expect(store.active?.id == first.id)
        store.remove(first.id)
        #expect(store.all().isEmpty)
        #expect(store.active == nil)
        #expect(secrets.accounts().isEmpty)
    }

    @Test func theDemoIsNeverSaved() {
        defer { tidy() }
        #expect(store.add(Demo.connection) == nil)
        #expect(secrets.accounts().isEmpty)
    }

    @Test func updatesAreKept() throws {
        defer { tidy() }
        var saved = try #require(store.add(server))
        saved.connection.cloudflare = .session(token: "new")
        saved.webTheme = "light"
        #expect(store.update(saved))
        #expect(store.load(saved.id)?.connection.cloudflare == .session(token: "new"))
        #expect(store.load(saved.id)?.webTheme == "light")
    }

    // MARK: Kept per connection

    @Test func keptNumbersArePerConnectionAndGoWithIt() throws {
        defer { tidy() }
        let first = try #require(store.add(server))
        let second = try #require(store.add(cloudflared))
        store.kept(for: first.id).save(Data("[1]".utf8), for: "a")
        store.kept(for: second.id).save(Data("[2]".utf8), for: "a")
        #expect(store.kept(for: first.id).load("a")?.data == Data("[1]".utf8))
        #expect(store.kept(for: second.id).load("a")?.data == Data("[2]".utf8))
        store.remove(first.id)
        #expect(store.kept(for: first.id).count == 0)
        #expect(!FileManager.default.fileExists(atPath: store.kept(for: first.id).directory.path(percentEncoded: false)))
        #expect(store.kept(for: second.id).load("a") != nil)
    }

    @Test func theKeepChoiceIsPerConnection() throws {
        defer { tidy() }
        var first = try #require(store.add(server))
        let second = try #require(store.add(cloudflared))
        first.keep = .lastKnown
        store.update(first)
        #expect(store.load(first.id)?.keep == .lastKnown)
        #expect(store.load(second.id)?.keep == .nothing)
        #expect(defaults.string(forKey: "keep.choice") == nil)
    }

    @Test func secretsStayOutOfTheSettings() throws {
        defer { tidy() }
        let saved = try #require(store.add(server))
        store.activate(saved.id)
        let settings = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(Set(settings.keys) == ["connections.active"])
        #expect(!"\(settings)".contains("ww_token"))
    }

    // MARK: The Keychain item

    @Test func theKeychainAttributesAreUnchanged() {
        let attributes = KeychainConnectionSecrets.attributes(account: "connection.abc")
        #expect(attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(attributes[kSecAttrService as String] as? String == "net.iptater.walletweather")
        #expect(attributes[kSecAttrAccount as String] as? String == "connection.abc")
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(attributes.count == 5)
        let query = KeychainConnectionSecrets.query(account: nil)
        #expect(query[kSecAttrAccount as String] == nil)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(ConnectionStore.account(for: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
                == "connection.6f9619ff-8b86-d011-b42d-00c04fc964ff")
    }

    // MARK: A window's choice per connection

    @Test func aWindowsChoiceStaysWithItsConnection() {
        var value = 7
        // Before connections were kept apart: the value is the one in front's.
        var choice = ChoicePerConnection("")
        choice.move(&value, to: "A")
        #expect(value == 7)
        #expect(choice.text == "A;")
        // To B: A's 7 is put away, and B has none yet.
        choice.move(&value, to: "B")
        #expect(value == 0)
        value = 3
        // Back to A finds 7; B's 3 is remembered.
        choice = ChoicePerConnection(choice.text)
        choice.move(&value, to: "A")
        #expect(value == 7)
        #expect(choice.text == "A;B=3")
        choice.move(&value, to: "A")
        #expect(value == 7)
    }
}
