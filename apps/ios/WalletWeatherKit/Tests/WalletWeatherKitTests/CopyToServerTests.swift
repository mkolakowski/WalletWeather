import Foundation
import Testing
@testable import WalletWeatherKit

/// Copy to a server (#328): the household on this iPhone sent to a saved
/// server under that server's own token, as the backup Export for a server
/// seals, unsealed. The server's side is apps/server/tests/test_backup_moves.py
/// (`test_copy_to_a_server_*`), which imports the same payload (from-phone.json,
/// opened) with mode merge and replace.
@Suite(.serialized) struct CopyToServerTests {
    static let front = Connection(server: URL(string: "https://home.example.com")!, token: "ww_front_token")
    static let chosen = Connection(server: URL(string: "https://ww.parents.example")!, token: "ww_chosen_token")

    static func me(access: String) -> Data {
        Data("""
        {"id": 7, "email": "you@example.com", "name": null, "is_admin": false, "notice_required": false, "token_access": "\(access)"}
        """.utf8)
    }

    static let answer = Data("""
    {"ok": true, "imported": {"categories": 3, "accounts": 2, "recurring": 6, "transactions": 6, "tags": 2, "tag_rules": 1, "transfers": 1}, "encrypted": false}
    """.utf8)

    /// A store with the household in front's neighbours: Home (the one in
    /// front, as far as the store knows) and Mum & Dad (the one chosen).
    static func store() throws -> (ConnectionStore, home: SavedConnection, parents: SavedConnection) {
        let defaults = try #require(UserDefaults(suiteName: "copy-tests-\(UUID().uuidString)"))
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: FileManager.default.temporaryDirectory.appending(path: "copy-\(UUID().uuidString)"))
        let home = try #require(store.add(front, name: "Home"))
        let parents = try #require(store.add(chosen, name: "Mum & Dad", account: "you@example.com"))
        store.activate(home.id)
        return (store, home, parents)
    }

    static func json(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The payload

    @Test func thePayloadIsTheBackupExportForAServerSeals() async throws {
        let household = try await BackupTests.household()
        let now = Date(timeIntervalSince1970: 1_771_000_000)
        let payload = try CopyPayload(household: household, now: now)
        // Counted from the household's own data: the server's counts for the
        // same household (test_backup_moves.py) are 2, 6, 6 and 1.
        #expect(payload.contents == CopyContents(accounts: 2, bills: 6, lines: 6, transfers: 1))
        #expect(payload.contents.summary == "2 accounts, 6 bills and income, 6 lines and 1 transfer")
        // The same backup Export for a server seals, opened.
        let sealed = try BackupFile.seal(try household.backupPayload(now: now), passphrase: BackupTests.passphrase,
                                         kind: "user", cost: BackupTests.quick)
        let opened = try BackupFile.open(sealed, passphrase: BackupTests.passphrase).payload
        #expect(NSDictionary(dictionary: try Self.json(payload.json)) == NSDictionary(dictionary: opened))
    }

    @Test func anEmptyHouseholdCountsNothing() throws {
        let contents = CopyContents(payload: ["version": 5, "accounts": [Any](), "transfers": [Any]()])
        #expect(contents.isEmpty && contents == CopyContents(accounts: 0, bills: 0, lines: 0, transfers: 0))
        #expect(contents.summary == "0 accounts, 0 bills and income and 0 lines")
    }

    // MARK: The request

    @Test(arguments: CopyMode.allCases)
    func theRequestGoesToTheChosenConnectionUnderItsOwnToken(mode: CopyMode) async throws {
        let (store, _, parents) = try Self.store()
        let household = try await BackupTests.household()
        let payload = try CopyPayload(household: household)
        CopyStub.answer([(200, Self.me(access: "full")), (200, Self.answer)])
        let copy = try ServerCopy(to: parents, session: CopyStub.session())
        let answer = try await copy.copy(payload, mode: mode)

        #expect(CopyStub.requests.map { "\($0.httpMethod ?? "") \($0.url?.path() ?? "")" }
            == ["GET /api/me", "POST /api/backup/import"])
        for request in CopyStub.requests {
            #expect(request.url?.host() == "ww.parents.example")
            // The chosen connection's token, never the one in front's.
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ww_chosen_token")
        }
        #expect(store.active?.id != parents.id)
        let post = try #require(CopyStub.requests.last)
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try Self.json(CopyStub.lastBody)
        #expect(Set(body.keys) == ["mode", "payload"])   // no passphrase: not sealed
        #expect(body["mode"] as? String == mode.rawValue)
        let sent = try #require(body["payload"] as? [String: Any])
        #expect(NSDictionary(dictionary: sent) == NSDictionary(dictionary: try Self.json(payload.json)))
        #expect(sent["version"] as? Int == LocalServer.backupVersion)
        #expect((sent["accounts"] as? [[String: Any]])?.map { $0["name"] as? String } == ["Checking", "Épargne 🍕"])
        #expect(sent["walletweather"] == nil)   // not the sealed file's header

        #expect(answer.ok && answer.encrypted == false)
        #expect(answer.imported == CopyAnswer.Imported(accounts: 2, recurring: 6, transactions: 6, transfers: 1,
                                                       categories: 3, tags: 2))
        #expect(answer.summary(to: parents.name) == "Copied 2 accounts, 6 bills and income, 6 lines and 1 transfer to Mum & Dad.")
    }

    @Test func aReadOnlyConnectionIsRefusedAndNothingIsSent() async throws {
        let (_, _, parents) = try Self.store()
        CopyStub.answer([(200, Self.me(access: "read"))])
        let copy = try ServerCopy(to: parents, session: CopyStub.session())
        await #expect(throws: CopyRefusal.readOnly) { try await copy.check() }
        await #expect(throws: CopyRefusal.readOnly) {
            try await copy.copy(try CopyPayload(["version": 5, "accounts": [Any]()]), mode: .merge)
        }
        #expect(CopyStub.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(CopyRefusal.readOnly.problem.wayForward == nil)
    }

    @Test func theServersRefusalComesBackWithItsReason() async throws {
        let (_, _, parents) = try Self.store()
        CopyStub.answer([(200, Self.me(access: "full")),
                         (400, Data(#"{"detail": "Unsupported backup version: 9"}"#.utf8))])
        let copy = try ServerCopy(to: parents, session: CopyStub.session())
        await #expect(throws: APIError.server(status: 400, detail: "Unsupported backup version: 9")) {
            try await copy.copy(try CopyPayload(["version": 9, "accounts": [Any]()]), mode: .replace)
        }
    }

    @MainActor @Test func anEndedSignInIsMarkedOnTheChosenConnection() async throws {
        let (store, _, parents) = try Self.store()
        CopyStub.answer([(401, Data(#"{"detail": "API token expired"}"#.utf8))])
        let id = parents.id, token = parents.connection.token
        let copy = try ServerCopy(to: parents, session: CopyStub.session()) { store.markSignInEnded(id, token: token) }
        await #expect(throws: APIError.tokenExpired) { try await copy.check() }
        let marked = try #require(store.load(parents.id))
        #expect(marked.needsSignIn)
        // Now it can't be picked, nor copied to.
        #expect(throws: CopyRefusal.signInEnded) { try ServerCopy(to: marked) }
        #expect(CopyDestination.list(store.all()).first { $0.id == id }
            == CopyDestination(id: id, name: "Mum & Dad", detail: "Sign in again", pickable: false))
    }

    // MARK: Where to

    @Test func onlySavedServersAreDestinations() throws {
        let (store, home, parents) = try Self.store()
        let phone = try #require(store.add(LocalServer.connection))
        #expect(CopyDestination.list(store.all()) == [
            CopyDestination(id: home.id, name: "Home", detail: nil, pickable: true),
            CopyDestination(id: parents.id, name: "Mum & Dad", detail: "you@example.com", pickable: true),
        ])
        #expect(throws: CopyRefusal.notAServer) { try ServerCopy(to: phone) }
    }

    @Test func copyIsOfferedWithAHouseholdAndAServer() throws {
        let (store, _, _) = try Self.store()
        let servers = store.all()
        let phoneOnly = [SavedConnection(connection: LocalServer.connection)]
        #expect(CopyAvailability.decide(householdExists: true, saved: servers, demoInFront: false) == .available)
        #expect(CopyAvailability.decide(householdExists: true, saved: phoneOnly, demoInFront: false) == .noServer)
        #expect(CopyAvailability.decide(householdExists: false, saved: servers, demoInFront: false) == .noHousehold)
        #expect(CopyAvailability.decide(householdExists: true, saved: servers, demoInFront: true) == .hidden)
        #expect(CopyAvailability.available.footnote == nil && CopyAvailability.noServer.footnote != nil)
    }

    @Test func neitherModeIsTheDestructiveOneByDefault() {
        // The sheet starts with no mode; the order offered is merge first.
        #expect(CopyMode.allCases == [.merge, .replace])
        #expect(CopyMode.merge.title == "Add to what's there" && CopyMode.replace.title == "Replace what's there")
    }
}

/// Answers in turn (the last repeats) and remembers each request and the
/// last body. Its own state, so suites that use `StubServer` don't share it.
final class CopyStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [(status: Int, body: Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var lastBody: Data?

    static func answer(_ list: [(status: Int, body: Data)]) {
        answers = list
        requests = []
        lastBody = nil
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CopyStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.answers.count > 1 ? Self.answers.removeFirst() : (Self.answers.first ?? (200, Data()))
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
