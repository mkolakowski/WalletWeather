import Foundation
import Testing
@testable import WalletWeatherKit

/// Last-known numbers (#101): what's kept, when it answers, and that nothing
/// is left behind.
struct KeptTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "kept-tests-\(UUID().uuidString)")
    var keeper: KeptResponses { KeptResponses(directory: folder) }
    let host = "kept-\(UUID().uuidString.lowercased()).test"
    var server: URL { URL(string: "https://\(host)")! }

    func sampleData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
        return try Data(contentsOf: url)
    }

    /// A client whose requests go to `Stub` instead of the network.
    func client(keeper: KeptResponses?, seen: Seen? = nil) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        var observer: KeptObserver?
        if let seen {
            observer = { @MainActor (date: Date?) in seen.dates.append(date) }
        }
        return APIClient(connection: Connection(server: server, token: "t"),
                         session: URLSession(configuration: config), keeper: keeper, observer: observer)
    }

    @Test func keyLeavesOutTodayAndSortsTheQuery() {
        let a = KeptResponses.key(server: server, method: "GET", path: "/api/accounts/1/forecast",
                                  query: ["start": "2026-11-01", "end": "2026-11-30", "today": "2026-11-15"])
        let b = KeptResponses.key(server: server, method: "GET", path: "/api/accounts/1/forecast",
                                  query: ["end": "2026-11-30", "today": "2026-11-16", "start": "2026-11-01"])
        #expect(a == b)
        let other = KeptResponses.key(server: URL(string: "https://elsewhere.test")!, method: "GET",
                                      path: "/api/accounts/1/forecast", query: ["start": "2026-11-01", "end": "2026-11-30"])
        #expect(a != other)
    }

    @Test func savesLoadsAndDeletesEverything() throws {
        defer { keeper.deleteAll() }
        keeper.save(Data("{}".utf8), for: "a")
        keeper.save(Data("[1]".utf8), for: "b")
        #expect(keeper.count == 2)
        let found = try #require(keeper.load("b"))
        #expect(found.data == Data("[1]".utf8))
        #expect(abs(found.keptAt.timeIntervalSinceNow) < 60)
        keeper.deleteAll()
        #expect(keeper.count == 0)
        #expect(keeper.load("a") == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func leftOutOfBackups() throws {
        defer { keeper.deleteAll() }
        keeper.save(Data("{}".utf8), for: "a")
        let folderValues = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(folderValues.isExcludedFromBackup == true)
        let file = try #require(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func keepsNoMoreThanItsLimit() throws {
        let small = KeptResponses(directory: folder, limit: 3)
        defer { small.deleteAll() }
        for i in 0..<5 { small.save(Data("\(i)".utf8), for: "k\(i)") }
        #expect(small.count == 3)
    }

    @MainActor @Test func answersFromTheKeptCopyWhenOffline() async throws {
        defer { keeper.deleteAll(); Stub.clear(host) }
        let seen = Seen()
        let api = client(keeper: keeper, seen: seen)

        Stub.answer(host, try sampleData("dashboard"))
        let fresh = try await api.dashboard()
        #expect(seen.dates.count == 1 && seen.dates[0] == nil)
        #expect(keeper.count == 1)

        Stub.fail(host, .notConnectedToInternet)
        let kept = try await api.dashboard(today: LocalDay(year: 2026, month: 11, day: 16))
        #expect(kept.cards.count == fresh.cards.count)
        #expect(seen.dates.count == 2 && seen.dates[1] != nil)

        // A page that was never loaded still says it's offline.
        await #expect(throws: APIError.offline) { try await api.budgets() }
    }

    @MainActor @Test func aSlowOrMissingServerUsesTheCopyToo() async throws {
        defer { keeper.deleteAll(); Stub.clear(host) }
        let api = client(keeper: keeper)
        Stub.answer(host, try sampleData("accounts"))
        _ = try await api.accounts()
        for failure in [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost] {
            Stub.fail(host, failure)
            #expect(try await api.accounts().isEmpty == false)
        }
    }

    @MainActor @Test func otherProblemsAreNotHidden() async throws {
        defer { keeper.deleteAll(); Stub.clear(host) }
        let api = client(keeper: keeper)
        Stub.answer(host, try sampleData("accounts"))
        _ = try await api.accounts()
        Stub.answer(host, try sampleData("error-revoked"), status: 401)
        await #expect(throws: APIError.tokenRevoked) { try await api.accounts() }
        Stub.fail(host, .serverCertificateUntrusted)
        await #expect(throws: APIError.insecure) { try await api.accounts() }
    }

    @MainActor @Test func nothingIsKeptWithoutAKeeper() async throws {
        defer { keeper.deleteAll(); Stub.clear(host) }
        let api = client(keeper: nil)
        Stub.answer(host, try sampleData("dashboard"))
        _ = try await api.dashboard()
        #expect(keeper.count == 0)
        Stub.fail(host, .notConnectedToInternet)
        await #expect(throws: APIError.offline) { try await api.dashboard() }
    }

    @MainActor @Test func searchAndEditsAreNeverKept() async throws {
        defer { keeper.deleteAll(); Stub.clear(host) }
        let api = client(keeper: keeper)
        Stub.answer(host, try sampleData("search"))
        _ = try await api.searchTransactions("rent")
        Stub.answer(host, Data("{}".utf8))
        try await api.acknowledgeNotice()
        Stub.answer(host, try sampleData("me"))
        _ = try await api.me()
        #expect(keeper.count == 0)
    }
}

/// What the observer was told, in order.
@MainActor final class Seen {
    var dates: [Date?] = []
}

/// Answers requests by host, so tests running side by side don't meet.
final class Stub: URLProtocol, @unchecked Sendable {
    enum Reply { case data(Data, Int), failure(URLError.Code) }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]

    static func answer(_ host: String, _ data: Data, status: Int = 200) { set(host, .data(data, status)) }
    static func fail(_ host: String, _ code: URLError.Code) { set(host, .failure(code)) }
    static func clear(_ host: String) { lock.withLock { replies[host] = nil } }
    private static func set(_ host: String, _ reply: Reply) { lock.withLock { replies[host] = reply } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.lock.withLock { Self.replies[request.url?.host() ?? ""] }
        switch reply {
        case let .data(data, status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {}
}
