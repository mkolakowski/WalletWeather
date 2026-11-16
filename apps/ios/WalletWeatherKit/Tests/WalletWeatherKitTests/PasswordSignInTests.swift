import Foundation
import Testing
@testable import WalletWeatherKit

/// Every suite that uses `StubServer` sits in here, so they run one test at
/// a time and never share the stand-in server.
@Suite(.serialized) enum StubServerSuites {}

extension StubServerSuites {
    /// Signing in with an email and password (ios-app phase 7, #100): what
    /// the app sends to `POST /api/auth/token`, and how the server's answers
    /// read. Requests go to a stand-in server, never the network.
    @Suite struct PasswordSignInTests {
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

        // Two-factor sign-in (#166).
        @Test func anAccountWithTwoFactorAsksForACode() async {
            let said = "This account has two-factor sign-in on. Type the code from your authenticator app, or sign in through the browser."
            StubServer.answer(403, Data(#"{"detail":"\#(said)","two_factor_required":true}"#.utf8))
            await #expect(throws: APIError.twoFactorCodeNeeded(said)) {
                _ = try await client.signIn(email: "me@example.com", password: "right", deviceName: "iPhone")
            }
            #expect(APIError.twoFactorCodeNeeded(said).message == said)
            // No code was typed, so none is sent: not even an empty one.
            let body = try? #require(StubServer.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            #expect(body?["code"] == nil)
        }

        @Test func theCodeGoesWithTheEmailAndPassword() async throws {
            let sample = try Data(contentsOf: try #require(Bundle.module.url(forResource: "token", withExtension: "json",
                                                                             subdirectory: "Samples")))
            StubServer.answer(200, sample)
            let issued = try await client.signIn(email: "me@example.com", password: "right",
                                                 deviceName: "iPhone", code: " 123456\n")
            #expect(issued.token == "ww_sample-token-not-real")
            let body = try #require(StubServer.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
            #expect(body["code"] == "123456")
            #expect(body["email"] == "me@example.com" && body["password"] == "right")
        }

        @Test func aWrongCodeAsksAgainWithTheServersWords() async {
            let said = "That code isn't right. Check your authenticator app and try again."
            StubServer.answer(403, Data(#"{"detail":"\#(said)","two_factor_required":true}"#.utf8))
            await #expect(throws: APIError.twoFactorCodeNeeded(said)) {
                _ = try await client.signIn(email: "me@example.com", password: "right", deviceName: "iPhone", code: "000000")
            }
        }

        @Test func anOlderServersRefusalIsShownAsItIs() async {
            // Server 1.57.0 had no code here and said so, without the flag.
            let said = "This account has two-factor sign-in on. Sign in through the browser instead."
            StubServer.answer(403, Data(#"{"detail":"\#(said)"}"#.utf8))
            await #expect(throws: APIError.server(status: 403, detail: said)) {
                _ = try await client.signIn(email: "me@example.com", password: "right", deviceName: "iPhone")
            }
        }

        @Test func aDisabledAccountSaysSo() async {
            StubServer.answer(403, Data(#"{"detail":"Account disabled"}"#.utf8))
            await #expect(throws: APIError.server(status: 403, detail: "Account disabled")) {
                _ = try await client.signIn(email: "me@example.com", password: "right", deviceName: "iPhone")
            }
        }
    }
}

/// Answers requests with the answers set, in turn (the last one repeats),
/// and remembers every request. Only for suites that run one test at a time.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [(status: Int, body: Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var lastBody: Data?
    static var lastRequest: URLRequest? { requests.last }

    static func answer(_ status: Int, _ body: Data) { answer([(status, body)]) }

    static func answer(_ list: [(status: Int, body: Data)]) {
        answers = list
        requests = []
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
        Self.requests.append(request)
        let (status, body) = Self.answers.count > 1 ? Self.answers.removeFirst() : (Self.answers.first ?? (200, Data()))
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
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
