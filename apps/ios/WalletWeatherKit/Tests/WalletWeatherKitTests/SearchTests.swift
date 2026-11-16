import Foundation
import Testing
@testable import WalletWeatherKit

/// Search across everything (ios-app phase 10, #112, on the server's
/// `/api/search` from #111): the recorded answer decodes into the types the
/// app's editors open, and an older server falls back to its transaction
/// search. Requests go to a stand-in server, never the network.
extension StubServerSuites {
    @Suite struct SearchTests {
        let client = APIClient(connection: Connection(server: URL(string: "https://ww.example.com")!),
                               session: StubServer.session())

        func sample(_ name: String) throws -> Data {
            try Data(contentsOf: try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples")))
        }

        @Test func decodesEveryGroup() async throws {
            StubServer.answer(200, try sample("search-everything"))
            let found = try await client.search("e")
            #expect(found.query == "e")
            #expect(!found.transactionsOnly && !found.isEmpty)
            let request = try #require(StubServer.lastRequest?.url)
            let query = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(request.path == "/api/search")
            #expect(query.contains(URLQueryItem(name: "q", value: "e")))
            #expect(query.contains { $0.name == "today" })

            for group in [found.transactions.total, found.recurring.total, found.accounts.total,
                          found.categories.total, found.reports.total] {
                #expect(group > 0)
            }
            // A transaction opens in the line editor, a bill in the bill editor.
            let hit = try #require(found.transactions.results.first)
            #expect(hit.line.transactionId == hit.id)
            let bill = try #require(found.recurring.results.first)
            #expect(!bill.nextDates.isEmpty || bill.expired)
            #expect(found.accounts.results.allSatisfy { !$0.name.isEmpty })
            #expect(found.categories.results.allSatisfy { $0.transactionCount >= 0 })
            #expect(found.tags.total == found.tags.results.count)
        }

        @Test func anOlderServerSearchesTransactionsOnly() async throws {
            StubServer.answer([(404, Data(#"{"detail":"Not Found"}"#.utf8)),
                               (200, Data(#"{"total":0,"results":[],"limit":100,"offset":0}"#.utf8))])
            let found = try await client.search("rent")
            #expect(found.transactionsOnly && found.isEmpty)
            #expect(StubServer.requests.map { $0.url?.path } == ["/api/search", "/api/transactions/search"])
        }

        @Test func otherProblemsAreNotHidden() async {
            StubServer.answer(401, Data(#"{"detail":"API token revoked"}"#.utf8))
            await #expect(throws: APIError.tokenRevoked) { _ = try await client.search("rent") }
            #expect(StubServer.requests.count == 1)
        }

        @Test func aCategoryOrTagListsItsTransactions() async throws {
            StubServer.answer(200, Data(#"{"total":0,"results":[],"limit":200,"offset":0}"#.utf8))
            _ = try await client.transactions(.category(7))
            #expect(StubServer.lastRequest?.url?.query?.contains("category_id=7") == true)
            _ = try await client.transactions(.tag(3))
            #expect(StubServer.lastRequest?.url?.query?.contains("tag_id=3") == true)
        }

        @Test func searchIsNeverKept() throws {
            // Only a page's read requests are kept (`keep: true`); the search
            // calls never pass it, so nothing about a search is written.
            let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/WalletWeatherKit/Search.swift"), encoding: .utf8)
            #expect(!source.contains("keep: true"))
        }
    }
}
