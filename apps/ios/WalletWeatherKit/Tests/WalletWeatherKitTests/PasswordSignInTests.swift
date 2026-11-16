import Foundation
import Testing
@testable import WalletWeatherKit

/// Signing in with an email and password (ios-app phase 7, #100): what the
/// app sends to `POST /api/auth/token`, and how the server's answers read.
/// Requests go to a stand-in server (`StubServer`), never the network.
@Suite(.serialized)
struct PasswordSignInTests {
    let client = APIClient(connection: Connection(server: URL(string: "https://ww.example.com")!),
                           session: StubServer.session())

    @Test func sendsTheEmailPasswordAndPhoneName() async throws {
        let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "token", withExtension: "json",
                                                                         subdirectory: "Samples")))
        StubServer.answer(200, sample)
        let issued = try await client.signIn(email: "  Me@Example.com \n", password: "pa ss",
                                             deviceName: String(repeating: "x", count: 100))
        #expect(issued.token == "ww_sample-token-not-real")
        let request = try #require(StubServer.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/auth/token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(StubServer.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body["email"] == "Me@Example.com")  // trimmed; the server lowercases
        #expect(body["password"] == "pa ss")          // never trimmed
        #expect(body["name"] == String(repeating: "x", count: 80))
        #expect(body["access"] == "full")
    }

    @Test func aRefusedPasswordIsItsOwnError() async {
        StubServer.answer(401, Data(#"{"detail":"Invalid email or password"}"#.utf8))
        await #expect(throws: APIError.wrongPassword) {
            _ = try await client.signIn(email: "me@example.com", password: "wrong", deviceName: "iPhone")
        }
        #expect(APIError.wrongPassword.message.contains("Google"))
    }

    @Test func tooManyTriesSaysHowLongToWait() async {
        StubServer.answer(429, Data(#"{"detail":"Too many failed sign-ins. Try again in 15 minutes."}"#.utf8))
        await #expect(throws: APIError.server(status: 429, detail: "Too many failed sign-ins. Try again in 15 minutes.")) {
            _ = try await client.signIn(email: "me@example.com", password: "wrong", deviceName: "iPhone")
        }
    }

    @Test func aDisabledAccountSaysSo() async {
        StubServer.answer(403, Data(#"{"detail":"Account disabled"}"#.utf8))
        await #expect(throws: APIError.server(status: 403, detail: "Account disabled")) {
            _ = try await client.signIn(email: "me@example.com", password: "right", deviceName: "iPhone")
        }
    }
}

/// Answers every request with the one answer set last, and remembers the
/// request. Only for suites that run one test at a time.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func answer(_ status: Int, _ body: Data) {
        Self.status = status
        Self.body = body
        lastRequest = nil
        lastBody = nil
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubServer.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession hands a protocol the body as a stream.
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
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
