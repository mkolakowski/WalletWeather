import Foundation
import Testing
@testable import WalletWeatherKit

/// Against a real server, only when one is given (a demo server is fine):
///   WW_LIVE_SERVER=http://localhost:8300 WW_LIVE_TOKEN=ww_… swift test
/// The token is ended by the test, so give it a throwaway one.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WW_LIVE_TOKEN"] != nil))
struct LiveServerTests {
    @Test func signingOutEndsTheToken() async throws {
        let env = ProcessInfo.processInfo.environment
        let server = try #require(env["WW_LIVE_SERVER"].flatMap(URL.init(string:)))
        let client = APIClient(connection: Connection(server: server, token: env["WW_LIVE_TOKEN"]))
        _ = try await client.me()
        try await client.endToken()
        await #expect(throws: APIError.tokenRevoked) { _ = try await client.me() }
    }
}
