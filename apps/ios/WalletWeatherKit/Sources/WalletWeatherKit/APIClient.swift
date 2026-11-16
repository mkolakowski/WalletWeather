import Foundation

/// The app's version and the oldest server it works with.
public enum AppInfo {
    /// The iOS app's own version (CHANGELOG.md tracks it beside the app,
    /// web and schema versions). Keep it equal to MARKETING_VERSION in the
    /// Xcode project.
    public static let version = "0.8.0"
    /// The first server version with what the app's pages need: the
    /// phone's date on Net worth, Budgets and Reports (#91), on top of each
    /// bill's next dates (#89) and the Forecast's (#88).
    public static let minimumServerVersion = "1.54.0"
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
/// this device only (never in iCloud). The numbers are kept only when the
/// person chose Last-known numbers (`KeptResponses`).
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
///
/// With a `keeper` (Last-known numbers), the pages' read requests keep the
/// server's answer, and answer from that copy when the server can't be
/// reached, telling the `observer` how old it is. Editing is never kept.
public final class APIClient: Sendable {
    public let connection: Connection
    private let session: URLSession
    private let keeper: KeptResponses?
    private let observer: KeptObserver?
    /// How long a request may take before the server counts as slow.
    public static let timeout: TimeInterval = 20

    public init(connection: Connection, session: URLSession = APIClient.makeSession(),
                keeper: KeptResponses? = nil, observer: KeptObserver? = nil) {
        self.connection = connection
        self.session = session
        self.keeper = keeper
        self.observer = observer
    }

    /// No cookies and no URL cache: what the phone keeps is only what
    /// `KeptResponses` keeps, when the person chose it.
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
        try await get("/api/accounts", query: ["today": today.description], keep: true)
    }

    public func dashboard(today: LocalDay = .today()) async throws(APIError) -> Dashboard {
        try await get("/api/dashboard", query: ["today": today.description], keep: true)
    }

    public func charts(_ window: ChartWindow, today: LocalDay = .today()) async throws(APIError) -> DashboardCharts {
        try await get("/api/dashboard/charts", query: ["window": window.rawValue, "today": today.description], keep: true)
    }

    public func savedReports() async throws(APIError) -> [SavedReport] {
        try await get("/api/saved-reports", keep: true)
    }

    public func runReport(_ id: Int, today: LocalDay = .today()) async throws(APIError) -> ReportRun {
        try await send("POST", "/api/saved-reports/\(id)/run", query: ["today": today.description], body: [String: String](), keep: true)
    }

    // MARK: More (#91)

    public func netWorth(_ window: ChartWindow, today: LocalDay = .today()) async throws(APIError) -> NetWorth {
        try await get("/api/networth", query: ["window": window.rawValue, "today": today.description], keep: true)
    }

    public func budgets(today: LocalDay = .today()) async throws(APIError) -> BudgetProgress {
        try await get("/api/budgets/progress", query: ["window": "month", "today": today.description], keep: true)
    }

    // MARK: Forecast (#88)

    /// One account's month of lines.
    public func forecast(account: Int, month: YearMonth, today: LocalDay = .today()) async throws(APIError) -> ForecastMonth {
        try await get("/api/accounts/\(account)/forecast",
                      query: ["start": month.start.description, "end": month.end.description, "today": today.description], keep: true)
    }

    /// The signed-in person's own categories.
    public func categories() async throws(APIError) -> [TransactionCategory] {
        try await get("/api/categories", keep: true)
    }

    /// Saves a line: a new transaction for a projected line, the whole line
    /// again for one that's saved already. The web app's editor does the same.
    public func save(_ line: ForecastLine, draft: LineDraft, account: Int) async throws(APIError) {
        let body = TransactionBody(line: line, draft: draft)
        if let id = line.transactionId {
            let _: EmptyAnswer = try await send("PATCH", "/api/transactions/\(id)", body: body)
        } else {
            let _: EmptyAnswer = try await send("POST", "/api/accounts/\(account)/transactions", body: body)
        }
    }

    /// Adds a one-off transaction.
    public func add(_ draft: NewTransactionDraft, account: Int) async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/accounts/\(account)/transactions", body: TransactionBody(new: draft))
    }

    /// Deletes a line. A saved transaction is deleted (one from a repeating
    /// item also stops that date being projected again); a projected date
    /// is skipped, leaving the repeating item and its other dates alone.
    public func delete(_ line: ForecastLine) async throws(APIError) {
        if let id = line.transactionId {
            let _: EmptyAnswer = try await send("DELETE", "/api/transactions/\(id)", body: Optional<[String: String]>.none)
        } else if let rec = line.recurringId, let day = line.plannedDate {
            let _: EmptyAnswer = try await send("POST", "/api/recurring/\(rec)/skip", body: ["skip_date": day.description])
        }
    }

    /// Transactions whose name or notes contain `text`, on every account
    /// you can see, newest first.
    public func searchTransactions(_ text: String, limit: Int = 100) async throws(APIError) -> TransactionSearch {
        try await get("/api/transactions/search", query: ["q": text, "limit": String(limit)])
    }

    // MARK: Bills & income, Calendar, moving money (#89)

    /// Bills and paychecks on every account you can see, or one; the ended
    /// ones with `ended`.
    public func recurring(account: Int? = nil, ended: Bool = false, today: LocalDay = .today()) async throws(APIError) -> RecurringList {
        var query = ["today": today.description, "archived": ended ? "true" : "false"]
        if let account { query["account_id"] = String(account) }
        return try await get("/api/recurring", query: query, keep: true)
    }

    public func addRecurring(_ draft: BillDraft, account: Int) async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/accounts/\(account)/recurring", body: RecurringBody(draft))
    }

    /// Saves a bill: the whole item again, as a PATCH replaces it.
    public func updateRecurring(_ id: Int, _ body: RecurringBody) async throws(APIError) {
        let _: EmptyAnswer = try await send("PATCH", "/api/recurring/\(id)", body: body)
    }

    /// Skips one date, leaving the bill and its other dates alone.
    public func skip(_ item: RecurringItem, on day: LocalDay) async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/recurring/\(item.id)/skip", body: ["skip_date": day.description])
    }

    /// The Calendar's month, on every account or one.
    public func calendar(_ month: YearMonth, account: Int? = nil) async throws(APIError) -> CalendarMonth {
        var query = ["start": month.start.description, "end": month.end.description]
        if let account { query["account_id"] = String(account) }
        return try await get("/api/calendar", query: query, keep: true)
    }

    /// Moves money between two accounts you may edit, recorded as paid.
    @discardableResult
    public func moveMoney(_ body: TransferBody) async throws(APIError) -> Transfer {
        try await send("POST", "/api/transfers", body: body)
    }

    /// Ends this phone's token on the server, for Sign out (#145). A token
    /// may revoke itself and nothing else.
    public func endToken() async throws(APIError) {
        let _: EmptyAnswer = try await send("DELETE", "/api/tokens/current", body: Optional<[String: String]>.none)
    }

    /// Swaps the sign-in sheet's one-time code for this phone's token.
    public func swapSignInCode(_ code: String, verifier: String) async throws(APIError) -> IssuedToken {
        try await send("POST", "/api/app-sign-in/token", body: ["code": code, "code_verifier": verifier])
    }

    // MARK: - Requests

    /// `keep`: a page's read request, kept with Last-known numbers.
    func get<T: Decodable>(_ path: String, query: [String: String] = [:], keep: Bool = false) async throws(APIError) -> T {
        try await send("GET", path, query: query, body: Optional<[String: String]>.none, keep: keep)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String] = [:],
                                          body: B?, keep: Bool = false) async throws(APIError) -> T {
        let key = keep ? KeptResponses.key(server: connection.server, method: method, path: path, query: query) : nil
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
        } catch {
            let problem = (error as? URLError).map { APIError.from($0, host: connection.host) } ?? .cannotReach(connection.host)
            if let kept: T = await keptAnswer(key: key, after: problem) { return kept }
            throw problem
        }
        guard let http = response as? HTTPURLResponse else { throw .unexpectedResponse(path) }
        let value = try Self.decode(T.self, data: data, response: http, path: path)
        if let key {
            keeper?.save(data, for: key)
            await observer?(nil)
        }
        return value
    }

    /// The kept copy, when the server can't be reached and there is one.
    private func keptAnswer<T: Decodable>(key: String?, after problem: APIError) async -> T? {
        guard let key, let keeper, problem.serverUnreachable, let found = keeper.load(key),
              let value = try? Self.decoder().decode(T.self, from: found.data) else { return nil }
        await observer?(found.keptAt)
        return value
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
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
        do {
            return try decoder().decode(T.self, from: data)
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
