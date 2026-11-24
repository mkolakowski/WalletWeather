import Foundation

/// "Try the demo" on the Connect screen (ios-app phase 6, #92): the app on
/// sample numbers built into it, with no server, so Apple's reviewer and
/// anyone curious can get in (decided 2026-11-14).
///
/// The demo is a `Connection` to an address that can't exist (`.invalid`
/// never resolves). An `APIClient` on it answers from `Demo/` (responses
/// recorded from a demo server, the same as the tests' samples) instead of
/// the network, and keeps nothing. Decided 2026-11-16:
/// - **Read-only:** editors open as usual, but saving says the demo doesn't
///   save changes (`APIError.demoReadOnly`).
/// - **Dates follow the calendar:** the samples were recorded in November
///   2026, so every date in an answer moves by whole months, to the month
///   asked for (Forecast, Calendar) or to this month. Each month looks like
///   the recorded one.
///
/// Since phase 3 of Plans/standalone.md (#234), Dashboard, its charts,
/// Forecast, Calendar and the accounts' balances aren't recorded answers:
/// the shared core (`Core`) works them out from the demo household's rows
/// (`Demo/household.json`, recorded by `Scripts/record-household.py`),
/// moved by days so the household's "today" is today. Every account and
/// every month is then worked out as the server would.
public enum Demo {
    public static let server = URL(string: "https://demo.walletweather.invalid")!
    public static let connection = Connection(server: server)
    /// The month the samples were recorded in.
    static let recorded = YearMonth(year: 2026, month: 11)
    /// The day the household was recorded on.
    static let recordedDay = LocalDay(year: 2026, month: 11, day: 15)

    /// A session that answers from the samples.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoProtocol.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    /// Whether a request may go ahead in the demo: reading, and running a
    /// saved report (a POST that changes nothing).
    static func allows(_ method: String, _ path: String) -> Bool {
        method == "GET" || (method == "POST" && path.hasPrefix("/api/saved-reports/") && path.hasSuffix("/run"))
    }

    // MARK: - Answers

    /// The demo's answer to a request: a status and a JSON body.
    static func answer(method: String, path: String, query: [String: String]) -> (status: Int, body: Data) {
        guard allows(method, path) else {
            return (403, json(["detail": APIError.demoReadOnly.message]))
        }
        let today = query["today"].flatMap(LocalDay.init) ?? LocalDay.today()
        let thisMonth = YearMonth(today)
        let start = query["start"].flatMap(LocalDay.init) ?? thisMonth.start
        let end = query["end"].flatMap(LocalDay.init) ?? start.endOfMonth
        let parts = path.split(separator: "/").map(String.init)  // ["api", ...]
        let found: (Data, YearMonth)?
        switch (method, parts.dropFirst().first ?? "", parts.count) {
        case ("GET", "version", _): found = (sample("version"), thisMonth)
        case ("GET", "me", 2): found = (sample("me"), thisMonth)
        // Worked out by the core: already in today's dates, so not moved.
        case ("GET", "accounts", 2): found = computed { try accounts(today: today) }
        case ("GET", "accounts", 4) where parts[3] == "forecast":
            found = Int(parts[2]).flatMap { account in computed { try forecast(account: account, start: start, end: end, today: today) } }
        // The sample Unmatched lines (duo-more phase 3, #306), made from today.
        case ("GET", "accounts", 4) where parts[3] == "bank-unmatched":
            found = Int(parts[2]).map { account in (bankUnmatched(account: account, today: today), recorded) }
        case ("GET", "accounts", 6) where parts[3] == "bank-unmatched" && parts[5] == "candidates":
            found = Int(parts[2]).flatMap { account in
                Int(parts[4]).flatMap { line in bankCandidates(account: account, line: line, today: today).map { ($0, recorded) } }
            }
        case ("GET", "dashboard", 2): found = computed { try dashboard(today: today) }
        case ("GET", "dashboard", 3) where parts[2] == "charts":
            found = computed { try charts(window: query["window"] ?? ChartWindow.month.rawValue, today: today) }
        case ("GET", "saved-reports", 2): found = (sample("saved-reports"), thisMonth)
        case ("POST", "saved-reports", 4): found = (sample("report-run"), thisMonth)
        case ("GET", "networth", _): found = (sample("networth"), thisMonth)
        case ("GET", "budgets", _): found = (sample("budgets"), thisMonth)
        case ("GET", "categories", 2): found = (sample("categories"), thisMonth)
        // Sample tags and auto-tag rules (#293); reading only, like the rest.
        case ("GET", "tags", 2): found = (json(tagList()), thisMonth)
        case ("GET", "tag-rules", 2): found = (json(tagSamples()["rules"] as? [[String: Any]] ?? []), thisMonth)
        // Bank sync's status: times are made from now, so they aren't moved
        // by months like the sample dates are.
        case ("GET", "bank", 3) where parts[2] == "status": found = (bankStatus(), recorded)
        case ("GET", "recurring", 2):
            found = (recurring(account: query["account_id"].flatMap(Int.init), ended: query["archived"] == "true"), thisMonth)
        case ("GET", "calendar", 2):
            found = computed { try calendar(account: query["account_id"].flatMap(Int.init), start: start, end: end, today: today) }
        case ("GET", "transactions", 3) where parts[2] == "search":
            found = (searchTransactions(query["q"] ?? "", category: query["category_id"].flatMap(Int.init),
                                        tag: query["tag_id"].flatMap(Int.init)), thisMonth)
        case ("GET", "search", 2): found = (searchEverything(query["q"] ?? ""), thisMonth)
        default: found = nil
        }
        guard let (body, month) = found else {
            return (404, json(["detail": "The demo doesn't have this page. Connect your server to see it."]))
        }
        return (200, shift(body, by: month.index - recorded.index))
    }

    // MARK: Worked out by the core

    /// An answer worked out by the core, in today's dates (so not moved by
    /// months); nil when the core couldn't, which reads as a missing page.
    static func computed(_ work: () throws -> Data) -> (Data, YearMonth)? {
        (try? work()).map { ($0, recorded) }
    }

    /// The demo household's rows, every date moved by the days from the day
    /// it was recorded to `today`: its accounts (each a forecast input) and
    /// categories.
    static func household(today: LocalDay) -> [String: Any] {
        let moved = shift(sample("household"), days: today.days(since: recordedDay))
        var household = (try? JSONSerialization.jsonObject(with: moved)) as? [String: Any] ?? [:]
        // The sample tags (`Demo/tags.json`) go on its lines and bills.
        household["accounts"] = householdAccounts(household).map { account in
            var account = account
            account["transactions"] = tagged(account["transactions"] as? [[String: Any]] ?? [], "lines")
            account["recurring"] = tagged(account["recurring"] as? [[String: Any]] ?? [], "bills")
            return account
        }
        return household
    }

    // MARK: Sample tags (#293)

    /// `Demo/tags.json`: the tags, the auto-tag rules, and which lines and
    /// bills (by id) carry which tags.
    static func tagSamples() -> [String: Any] { object("tags") as? [String: Any] ?? [:] }

    /// The sample tags in name order, as `GET /api/tags` sends them.
    static func tagList() -> [[String: Any]] {
        (tagSamples()["tags"] as? [[String: Any]] ?? []).sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }

    /// The tag ids a line (`"lines"`) or a bill (`"bills"`) carries.
    static func tagIds(_ kind: String, of id: Int?) -> [Int] {
        guard let id else { return [] }
        return ((tagSamples()[kind] as? [String: Any])?[String(id)] as? [Int]) ?? []
    }

    /// The rows with their `tags` set to the sample tags they carry (id, name, colour), in name order.
    static func tagged(_ rows: [[String: Any]], _ kind: String) -> [[String: Any]] {
        let list = tagList()
        return rows.map { row in
            var row = row
            let ids = tagIds(kind, of: row["id"] as? Int)
            row["tags"] = list.filter { ids.contains($0["id"] as? Int ?? 0) }
            return row
        }
    }

    static func householdAccounts(_ household: [String: Any]) -> [[String: Any]] {
        household["accounts"] as? [[String: Any]] ?? []
    }

    static func run(_ name: String, _ input: [String: Any]) throws -> Data {
        try Core.shared.run(name, json: JSONSerialization.data(withJSONObject: input))
    }

    static func balance(_ account: [String: Any], on day: LocalDay) throws -> Double {
        var input = account
        input["as_of"] = day.description
        return try JSONSerialization.jsonObject(with: run("actualBalanceAsOf", input), options: [.fragmentsAllowed]) as? Double ?? 0
    }

    /// The accounts as recorded, with their start dates moved and today's
    /// balances worked out.
    static func accounts(today: LocalDay) throws -> Data {
        let rows = householdAccounts(household(today: today))
        let moved = shift(sample("accounts"), days: today.days(since: recordedDay))
        var list = (try? JSONSerialization.jsonObject(with: moved)) as? [[String: Any]] ?? []
        for index in list.indices {
            guard let row = rows.first(where: { $0["id"] as? Int == list[index]["id"] as? Int }) else { continue }
            list[index]["current_balance"] = try balance(row, on: today)
        }
        return json(list)
    }

    /// One account's Forecast for the window asked, with today's balance,
    /// as the server's route adds it.
    static func forecast(account: Int, start: LocalDay, end: LocalDay, today: LocalDay) throws -> Data {
        guard var input = householdAccounts(household(today: today)).first(where: { $0["id"] as? Int == account }) else {
            throw Core.Problem.failed("no account \(account)")
        }
        let current = try balance(input, on: today)
        input["start"] = start.description
        input["end"] = end.description
        var answer = try JSONSerialization.jsonObject(with: run("forecast", input)) as? [String: Any] ?? [:]
        answer["current_balance"] = current
        answer["bank_unmatched_count"] = 0
        return json(answer)
    }

    /// The Calendar across accounts, or one account's with each day's
    /// closing balance.
    static func calendar(account: Int?, start: LocalDay, end: LocalDay, today: LocalDay) throws -> Data {
        let household = household(today: today)
        let accounts = householdAccounts(household).filter { account == nil || $0["id"] as? Int == account }
        return try run("calendar", ["start": start.description, "end": end.description, "single_account": account != nil,
                                    "categories": household["categories"] ?? [], "accounts": accounts])
    }

    static func dashboard(today: LocalDay) throws -> Data {
        try run("dashboard", ["today": today.description, "accounts": householdAccounts(household(today: today))])
    }

    static func charts(window: String, today: LocalDay) throws -> Data {
        let household = household(today: today)
        return try run("dashboardCharts", ["window": window, "today": today.description,
                                           "categories": household["categories"] ?? [],
                                           "accounts": householdAccounts(household)])
    }

    // MARK: Built from the samples

    /// Bills and income on every account or one; nothing has ended in the
    /// demo. The totals are worked out again for what's listed.
    static func recurring(account: Int?, ended: Bool) -> Data {
        var list = object("recurring") as? [String: Any] ?? [:]
        let items = ended ? [] : tagged(list["items"] as? [[String: Any]] ?? [], "bills").filter { account == nil || $0["account_id"] as? Int == account }
        let bills = items.filter { ($0["amount"] as? Double ?? 0) < 0 }
        let income = items.filter { ($0["amount"] as? Double ?? 0) > 0 }
        func sum(_ rows: [[String: Any]], _ key: String) -> Double {
            (rows.reduce(0) { $0 + ($1[key] as? Double ?? 0) } * 100).rounded() / 100
        }
        let billsMonthly = sum(bills, "monthly_cost"), billsYearly = sum(bills, "yearly_cost")
        let incomeMonthly = sum(income, "monthly"), incomeYearly = sum(income, "yearly")
        list["items"] = items
        list["totals"] = [
            "bills_count": bills.count, "bills_monthly": billsMonthly, "bills_yearly": billsYearly,
            "income_count": income.count, "income_monthly": incomeMonthly, "income_yearly": incomeYearly,
            "net_monthly": ((incomeMonthly - billsMonthly) * 100).rounded() / 100,
            "net_yearly": ((incomeYearly - billsYearly) * 100).rounded() / 100,
        ]
        return json(list)
    }

    /// Transactions whose name or notes contain `text`, or that carry a
    /// category or a sample tag, newest first.
    static func searchTransactions(_ text: String, category: Int? = nil, tag: Int? = nil) -> Data {
        let found = transactions().filter { row in
            if let category { return row["category_id"] as? Int == category }
            if let tag { return tagIds("lines", of: row["id"] as? Int).contains(tag) }
            return matches(row, text, keys: ["description", "notes"])
        }
        return json(["total": found.count, "results": found])
    }

    /// Search across everything, each group narrowed to what contains `text`.
    static func searchEverything(_ text: String) -> Data {
        var all = object("search-everything") as? [String: Any] ?? [:]
        func group(_ rows: [[String: Any]], _ keys: [String]) -> [String: Any] {
            let found = rows.filter { matches($0, text, keys: keys) }
            return ["total": found.count, "results": found]
        }
        func rows(_ name: String) -> [[String: Any]] {
            (all[name] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        }
        let accounts = object("accounts") as? [[String: Any]] ?? []
        all["query"] = text
        all["transactions"] = group(transactions().map { t in
            var t = t
            t["date"] = t["actual_date"] ?? t["forecast_date"] ?? NSNull()
            return t
        }, ["description", "notes"])
        all["recurring"] = group(tagged((object("recurring") as? [String: Any])?["items"] as? [[String: Any]] ?? [], "bills"), ["description", "notes"])
        all["accounts"] = group(accounts, ["name"])
        for name in ["categories", "reports"] { all[name] = group(rows(name), ["name"]) }
        // Each tag with how many of the demo's lines carry it.
        let lines = transactions()
        all["tags"] = group(tagList().map { tag in
            var tag = tag
            tag["transaction_count"] = lines.filter { tagIds("lines", of: $0["id"] as? Int).contains(tag["id"] as? Int ?? 0) }.count
            return tag
        }, ["name"])
        return json(all)
    }

    /// A sample bank sync status: two banks connected (one through SimpleFIN,
    /// one through Teller) and matched, last synced a few hours ago, with the
    /// next sync due tomorrow (#197, #257), ticked for both, plus one account
    /// shared with the demo that syncs from someone else's connection (#267),
    /// with its own Teller keys and ticked for Plaid without keys yet (#278).
    static func bankStatus(now: Date = .now) -> Data {
        func connection(_ id: Int, _ provider: String, _ providerName: String, _ name: String, account: Int,
                        hoursAgo: Double, status: String, left: Int) -> [String: Any] {
            [
                "id": id, "provider": provider, "provider_name": providerName, "name": name,
                "linked_account_ids": [account],
                "last_sync_at": BankStatus.text(now.addingTimeInterval(-hoursAgo * 3600)), "last_sync_ok": true,
                "last_sync_status": status,
                "last_ok_at": BankStatus.text(now.addingTimeInterval(-hoursAgo * 3600)), "needs_reconnect": false,
                "failing_since": NSNull(), "failing_over_a_day": false,
                "next_sync_at": BankStatus.text(now.addingTimeInterval((24 - hoursAgo) * 3600)),
                "syncs_left_today": left, "sync_wait_seconds": 0,
            ]
        }
        let shared: [String: Any] = [
            "account_id": 3, "account_name": "Credit Card", "archived": false, "level": "edit",
            "holder_name": "Sam", "mine": false, "provider": "plaid", "provider_name": "Plaid",
            "synced_through": NSNull(),
            "last_sync_at": BankStatus.text(now.addingTimeInterval(-4 * 3600)), "last_sync_ok": true,
            "last_sync_status": "1 new line, 8 already here", "needs_reconnect": false, "paused": false,
            "holder_disabled": false, "next_sync_at": BankStatus.text(now.addingTimeInterval(20 * 3600)),
            "syncs_left_today": 18, "sync_wait_seconds": 0, "unmatched_count": 2,
        ]
        return json([
            "enabled": true, "connected": true, "linked_account_ids": [1, 2],
            "providers_allowed": ["simplefin", "teller"], "shared": [shared],
            "providers_ticked": ["simplefin", "teller", "plaid"],
            "own_keys": ["teller": ["environment": "development"], "plaid": NSNull()],
            "last_sync_at": BankStatus.text(now.addingTimeInterval(-3 * 3600)), "last_sync_ok": true,
            "last_sync_status": "Northwind Bank: 2 new lines, 1 matched a bill, 14 already here; Contoso Credit Union: 0 new lines, 6 already here",
            "last_ok_at": BankStatus.text(now.addingTimeInterval(-3 * 3600)), "needs_reconnect": false,
            "failing_since": NSNull(), "failing_over_a_day": false,
            "next_sync_at": BankStatus.text(now.addingTimeInterval(19 * 3600)),
            "syncs_left_today": 19, "sync_wait_seconds": 0,
            "connections": [
                connection(1, "simplefin", "SimpleFIN", "Northwind Bank", account: 1, hoursAgo: 5,
                           status: "2 new lines, 1 matched a bill, 14 already here", left: 19),
                connection(2, "teller", "Teller", "Contoso Credit Union", account: 2, hoursAgo: 3,
                           status: "0 new lines, 6 already here", left: 20),
            ],
        ])
    }

    // MARK: - Helpers

    /// The transactions the samples hold, newest first. (`Demo/search-
    /// everything.json` was recorded a day after the others, and the demo
    /// server's dates follow the day, so its transactions' dates were moved
    /// back a day in this copy to agree with Forecast.)
    static func transactions() -> [[String: Any]] {
        let one = (object("search") as? [String: Any])?["results"] as? [[String: Any]] ?? []
        let everything = ((object("search-everything") as? [String: Any])?["transactions"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        var seen = Set<Int>(), rows: [[String: Any]] = []
        for row in one + everything {
            guard let id = row["id"] as? Int, seen.insert(id).inserted else { continue }
            var row = row
            row.removeValue(forKey: "date")
            rows.append(row)
        }
        rows = tagged(rows, "lines")
        func day(_ r: [String: Any]) -> String { r["actual_date"] as? String ?? r["forecast_date"] as? String ?? "" }
        return rows.sorted { day($0) > day($1) }
    }

    static func matches(_ row: [String: Any], _ text: String, keys: [String]) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        return keys.contains { (row[$0] as? String)?.localizedCaseInsensitiveContains(text) == true }
    }

    static func sample(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Demo"),
              let data = try? Data(contentsOf: url) else { return Data("{}".utf8) }
        return data
    }

    static func object(_ name: String) -> Any? {
        try? JSONSerialization.jsonObject(with: sample(name))
    }

    static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"]

    /// Moves every `YYYY-MM-DD` date in an answer by `days`.
    static func shift(_ data: Data, days: Int) -> Data {
        guard days != 0, var text = String(data: data, encoding: .utf8) else { return data }
        text = text.replacing(/(\d{4})-(\d{2})-(\d{2})/) { m in
            LocalDay(String(m.0))?.adding(days: days).description ?? String(m.0)
        }
        return Data(text.utf8)
    }

    /// Moves every `YYYY-MM-DD` date, and every "November 2026" month
    /// name, in an answer by `months`, keeping the day of the month (or the
    /// month's last day, when it's shorter).
    static func shift(_ data: Data, by months: Int) -> Data {
        guard months != 0, var text = String(data: data, encoding: .utf8) else { return data }
        text = text.replacing(/(\d{4})-(\d{2})-(\d{2})/) { m in
            guard let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) else { return String(m.0) }
            let to = YearMonth(index: YearMonth(year: y, month: mo).index + months)
            let day = min(d, to.start.endOfMonth.day)
            return LocalDay(year: to.year, month: to.month, day: day).description
        }
        text = text.replacing(/(January|February|March|April|May|June|July|August|September|October|November|December) (\d{4})/) { m in
            guard let mo = monthNames.firstIndex(of: String(m.1)), let y = Int(m.2) else { return String(m.0) }
            let to = YearMonth(index: YearMonth(year: y, month: mo + 1).index + months)
            return "\(monthNames[to.month - 1]) \(to.year)"
        }
        return Data(text.utf8)
    }
}

extension Connection {
    /// The demo's connection: answered from the samples, never the network.
    public var isDemo: Bool { server.host() == Demo.server.host() }
}

extension YearMonth {
    /// Months since year 0, for adding months.
    var index: Int { year * 12 + (month - 1) }
    init(index: Int) { self.init(year: index / 12, month: index % 12 + 1) }
}

/// Answers the demo's requests from the samples, in place of the network.
final class DemoProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == Demo.server.host()
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in parts?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let (status, body) = Demo.answer(method: request.httpMethod ?? "GET", path: parts?.path ?? url.path(), query: query)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
