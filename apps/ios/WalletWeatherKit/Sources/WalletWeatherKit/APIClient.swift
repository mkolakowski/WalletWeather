import Foundation

/// The app's version and the oldest server it works with.
public enum AppInfo {
    /// The iOS app's own version (CHANGELOG.md tracks it beside the app,
    /// web and schema versions). Keep it equal to MARKETING_VERSION in the
    /// Xcode project.
    public static let version = "0.1.0"
    /// The first server version with the "sign in an app" page (#87).
    public static let minimumServerVersion = "1.50.0"
}

/// Compares `1.49.0`-style versions; nil for text that isn't one.
public func isVersion(_ found: String, atLeast needed: String) -> Bool? {
    func parts(_ v: String) -> [Int]? {
        let p = v.split(separator: ".").map { Int($0) }
        return p.contains(nil) || p.isEmpty ? nil : p.compactMap { $0 }
    }
    guard let a = parts(found), let b = parts(needed) else { return nil }
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return true
}

/// Where the app is signed in to, and with what. Kept in the Keychain on
/// this device only (never in iCloud); nothing else is kept on the phone.
public struct Connection: Sendable, Codable, Equatable {
    public var server: URL
    /// The WalletWeather API token, sent as `Authorization: Bearer`.
    public var token: String?
    /// How the app gets past Cloudflare Access, when it's in front.
    public var cloudflare: CloudflareCredential?

    public init(server: URL, token: String? = nil, cloudflare: CloudflareCredential? = nil) {
        self.server = server
        self.token = token
        self.cloudflare = cloudflare
    }

    public var host: String { server.host() ?? server.absoluteString }
}

/// The WalletWeather API, as the app calls it. Redirects aren't followed:
/// the API never redirects, so a redirect is Cloudflare Access sending the
/// request to its sign-in page.
public final class APIClient: Sendable {
    public let connection: Connection
    private let session: URLSession
    /// How long a request may take before the server counts as slow.
    public static let timeout: TimeInterval = 20

    public init(connection: Connection, session: URLSession = APIClient.makeSession()) {
        self.connection = connection
        self.session = session
    }

    /// No cookies and no cache: nothing about the server is kept on the phone.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: - Endpoints

    public func version() async throws(APIError) -> ServerVersion {
        try await get("/api/version")
    }

    /// The version check made on connecting: a server older than the app
    /// needs gets a plain message, not a broken screen.
    @discardableResult
    public func checkServer() async throws(APIError) -> ServerVersion {
        let found: ServerVersion
        do {
            found = try await version()
        } catch .unexpectedResponse {
            throw .notWalletWeather
        }
        if isVersion(found.appVersion, atLeast: AppInfo.minimumServerVersion) == false {
            throw .serverTooOld(found: found.appVersion, needed: AppInfo.minimumServerVersion)
        }
        return found
    }

    public func me() async throws(APIError) -> Me {
        try await get("/api/me")
    }

    public func acknowledgeNotice() async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/me/acknowledge-notice", body: [String: String]())
    }

    public func accounts(today: LocalDay = .today()) async throws(APIError) -> [Account] {
        try await get("/api/accounts", query: ["today": today.description])
    }

    public func dashboard(today: LocalDay = .today()) async throws(APIError) -> Dashboard {
        try await get("/api/dashboard", query: ["today": today.description])
    }

    public func charts(_ window: ChartWindow, today: LocalDay = .today()) async throws(APIError) -> DashboardCharts {
        try await get("/api/dashboard/charts", query: ["window": window.rawValue, "today": today.description])
    }

    public func savedReports() async throws(APIError) -> [SavedReport] {
        try await get("/api/saved-reports")
    }

    public func runReport(_ id: Int) async throws(APIError) -> ReportRun {
        try await send("POST", "/api/saved-reports/\(id)/run", body: [String: String]())
    }

    /// Swaps the sign-in sheet's one-time code for this phone's token.
    public func swapSignInCode(_ code: String, verifier: String) async throws(APIError) -> IssuedToken {
        try await send("POST", "/api/app-sign-in/token", body: ["code": code, "code_verifier": verifier])
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws(APIError) -> T {
        try await send("GET", path, query: query, body: Optional<[String: String]>.none)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String] = [:],
                                          body: B?) async throws(APIError) -> T {
        var request = URLRequest(url: ServerAddress.url(connection.server, path, query: query),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = connection.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in connection.cloudflare?.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirects())
        } catch let error as URLError {
            throw APIError.from(error, host: connection.host)
        } catch {
            throw .cannotReach(connection.host)
        }
        guard let http = response as? HTTPURLResponse else { throw .unexpectedResponse(path) }
        return try Self.decode(T.self, data: data, response: http, path: path)
    }

    /// Turns an answer into `T`, or into the error it stands for.
    static func decode<T: Decodable>(_ type: T.Type, data: Data, response: HTTPURLResponse,
                                     path: String) throws(APIError) -> T {
        if CloudflareAccess.isChallenge(response, body: data) { throw .cloudflareSignInNeeded }
        let detail = (try? JSONDecoder().decode(ServerError.self, from: data))?.detail
        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            switch detail {
            case "API token expired": throw .tokenExpired
            default: throw .tokenRevoked
            }
        case 300..<400:
            throw .notWalletWeather
        default:
            if let detail { throw .server(status: response.statusCode, detail: detail) }
            if response.statusCode == 404 { throw .notWalletWeather }
            throw .server(status: response.statusCode, detail: "The server answered with an error (\(response.statusCode))")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let looksLikePage = String(data: data.prefix(200), encoding: .utf8)?
                .trimmingCharacters(in: .whitespaces).hasPrefix("<") ?? false
            throw looksLikePage ? .notWalletWeather : .unexpectedResponse(path)
        }
    }
}

struct EmptyAnswer: Decodable {}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
