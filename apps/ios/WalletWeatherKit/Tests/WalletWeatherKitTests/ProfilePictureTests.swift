import Foundation
import Testing
@testable import WalletWeatherKit

/// Each saved server's profile picture on the phone (account-picker phase
/// 3, #379): kept with the connection, fetched again only when `/api/me`
/// says it changed, deleted with the connection.
struct ProfilePictureTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ww-pictures-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    // MARK: - Keeping them

    @Test func aPictureIsKeptAndReadBack() throws {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfilePictureStore(root: root)
        let id = UUID()
        #expect(store.load(id) == nil)
        #expect(store.save(id, data: png, updatedAt: "2026-11-25T10:00:00", etag: "\"abc\""))
        #expect(store.load(id) == .init(data: png, updatedAt: "2026-11-25T10:00:00", etag: "\"abc\""))
        // Never in the phone's backup.
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        // A 304 under a new date changes only the date.
        #expect(store.touch(id, updatedAt: "2026-11-26T09:00:00"))
        #expect(store.load(id) == .init(data: png, updatedAt: "2026-11-26T09:00:00", etag: "\"abc\""))
        #expect(!store.touch(UUID(), updatedAt: "x"))
        store.delete(id)
        #expect(store.load(id) == nil)
    }

    @Test func removingAConnectionDeletesItsPicture() throws {
        let suite = "ww-pictures-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pictures = ProfilePictureStore(root: root.appending(path: "Pictures"))
        let store = ConnectionStore(secrets: MemoryConnectionSecrets(), defaults: defaults,
                                    keptRoot: root.appending(path: "Kept"), pictures: pictures)
        let home = try #require(store.add(Connection(server: URL(string: "https://home.example.com")!, token: "t")))
        let other = try #require(store.add(Connection(server: URL(string: "https://ww.parents.example")!, token: "u")))
        pictures.save(home.id, data: png, updatedAt: "1", etag: nil)
        pictures.save(other.id, data: png, updatedAt: "1", etag: nil)
        store.remove(home.id)
        #expect(pictures.load(home.id) == nil)
        #expect(pictures.load(other.id) != nil)
    }

    // MARK: - When to fetch

    @Test func itsFetchedOnlyWhenTheDateChanges() {
        let kept = ProfilePictureStore.Kept(data: png, updatedAt: "2026-11-25T10:00:00", etag: "\"abc\"")
        #expect(PictureRefresh.decide(kept: nil, updatedAt: nil) == .nothing)
        #expect(PictureRefresh.decide(kept: kept, updatedAt: "2026-11-25T10:00:00") == .nothing)
        #expect(PictureRefresh.decide(kept: kept, updatedAt: "2026-11-26T08:00:00") == .fetch(etag: "\"abc\""))
        #expect(PictureRefresh.decide(kept: nil, updatedAt: "2026-11-25T10:00:00") == .fetch(etag: nil))
        // Removed in the web app: the kept one goes.
        #expect(PictureRefresh.decide(kept: kept, updatedAt: nil) == .delete)
    }

    // MARK: - What the server answers

    private func answer(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:]) throws(APIError) -> PictureAnswer {
        let response = HTTPURLResponse(url: URL(string: "https://home.example.com/api/me/picture")!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        return try APIClient.pictureAnswer(data: body, response: response, path: "/api/me/picture")
    }

    @Test func theServersAnswersBecomePictures() throws {
        #expect(try answer(200, png, headers: ["Content-Type": "image/png", "ETag": "\"abc\""]) == .picture(png, etag: "\"abc\""))
        #expect(try answer(304) == .unchanged)
        #expect(try answer(404, Data(#"{"detail":"No picture"}"#.utf8)) == .none)
        // A server older than 1.99.0 has no such page: none either.
        #expect(try answer(404, Data(#"{"detail":"Not Found"}"#.utf8)) == .none)
    }

    @Test func anythingElseIsAProblem() {
        #expect(throws: APIError.unexpectedResponse("/api/me/picture")) {
            try answer(200, Data("<html>".utf8), headers: ["Content-Type": "text/html"])
        }
        #expect(throws: APIError.unexpectedResponse("/api/me/picture")) {
            try answer(200, Data(), headers: ["Content-Type": "image/png"])
        }
        #expect(throws: APIError.tokenRevoked) { try answer(401, Data(#"{"detail":"Invalid token"}"#.utf8)) }
    }

    @Test func theDemoAndTheHouseholdAskNothing() async throws {
        #expect(try await APIClient(connection: Demo.connection).picture() == .none)
        #expect(try await APIClient(connection: LocalServer.connection).picture() == .none)
    }

    // MARK: - What's decoded

    @Test func meCarriesWhenThePictureChanged() throws {
        let json = #"{"id":1,"email":"a@b.c","name":"A","is_admin":false,"notice_required":false,"picture_updated_at":"2026-11-25T10:00:00"}"#
        let me = try APIClient.decoder().decode(Me.self, from: Data(json.utf8))
        #expect(me.pictureUpdatedAt == "2026-11-25T10:00:00")
        let sample: Me = try DecodingTests().sample("me")
        #expect(sample.pictureUpdatedAt == nil)
    }

    @Test func savedConnectionsWithoutTheNameStillDecode() throws {
        let id = UUID()
        let old = """
        {"id":"\(id.uuidString)","kind":"server","name":"Home","added":800000000,"lastUsed":800000000,\
        "connection":{"server":"https:\\/\\/home.example.com","token":"t"},"keep":"nothing","account":"pat@example.com"}
        """
        let saved = try JSONDecoder().decode(SavedConnection.self, from: Data(old.utf8))
        #expect(saved.personName == nil)
        #expect(Initials.of(saved.person) == "P")
    }
}
