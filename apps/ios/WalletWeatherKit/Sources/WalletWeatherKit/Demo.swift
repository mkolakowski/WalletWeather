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
public enum Demo {
    public static let server = URL(string: "https://demo.walletweather.invalid")!
    public static let connection = Connection(server: server)
    /// The month the samples were recorded in.
    static let recorded = YearMonth(year: 2026, month: 11)
    /// The account the Forecast and Calendar samples were recorded on;
    /// the other accounts' are built from the Calendar's lines.
    static let recordedAccount = 1

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
        let thisMonth = query["today"].flatMap(LocalDay.init).map(YearMonth.init) ?? YearMonth(LocalDay.today())
        let askedMonth = query["start"].flatMap(LocalDay.init).map(YearMonth.init) ?? thisMonth
        let parts = path.split(separator: "/").map(String.init)  // ["api", ...]
        let found: (Data, YearMonth)?
        switch (method, parts.dropFirst().first ?? "", parts.count) {
        case ("GET", "version", _): found = (sample("version"), thisMonth)
        case ("GET", "me", 2): found = (sample("me"), thisMonth)
        case ("GET", "accounts", 2): found = (sample("accounts"), thisMonth)
        case ("GET", "accounts", 4) where parts[3] == "forecast":
            found = Int(parts[2]).map { (forecast(account: $0), askedMonth) }
        case ("GET", "dashboard", 2): found = (sample("dashboard"), thisMonth)
        case ("GET", "dashboard", 3) where parts[2] == "charts":
            found = (sample(query["window"] == ChartWindow.days90.rawValue ? "charts-90d" : "charts-month"), thisMonth)
        case ("GET", "saved-reports", 2): found = (sample("saved-reports"), thisMonth)
        case ("POST", "saved-reports", 4): found = (sample("report-run"), thisMonth)
        case ("GET", "networth", _): found = (sample("networth"), thisMonth)
        case ("GET", "budgets", _): found = (sample("budgets"), thisMonth)
        case ("GET", "categories", 2): found = (sample("categories"), thisMonth)
        case ("GET", "recurring", 2):
            found = (recurring(account: query["account_id"].flatMap(Int.init), ended: query["archived"] == "true"), thisMonth)
        case ("GET", "calendar", 2): found = (calendar(account: query["account_id"].flatMap(Int.init)), askedMonth)
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

    // MARK: Built from the samples

    /// The recorded account's Forecast; another account's built from the
    /// Calendar's lines on it, from the Dashboard's opening balance.
    static func forecast(account: Int) -> Data {
        if account == recordedAccount { return sample("forecast") }
        let lines = events(account: account)
        var forecastBalance = openingBalance(account), actualBalance = forecastBalance
        let opening = forecastBalance
        var rows: [[String: Any]] = []
        for e in lines {
            let planned = e["forecast_amount"] as? Double ?? e["amount"] as? Double ?? 0
            let actual = e["actual_amount"] as? Double ?? e["amount"] as? Double ?? planned
            forecastBalance += planned
            actualBalance += actual
            rows.append([
                "forecast_date": e["date"] ?? NSNull(), "actual_date": e["date"] ?? NSNull(),
                "description": e["description"] ?? "", "category": e["category_name"] ?? NSNull(),
                "category_id": e["category_id"] ?? NSNull(), "notes": e["notes"] ?? NSNull(),
                "forecast_amount": planned, "forecast_balance": forecastBalance,
                "actual_amount": actual, "actual_balance": actualBalance,
                "diff_amount": actual - planned, "diff_balance": actualBalance - forecastBalance,
                "is_actual_real": e["is_actual_real"] ?? false, "recurring_id": e["recurring_id"] ?? NSNull(),
                "transaction_id": e["transaction_id"] ?? NSNull(), "transfer_id": e["transfer_id"] ?? NSNull(),
                "tags": e["tags"] ?? [],
            ])
        }
        let current = (object("accounts") as? [[String: Any]])?
            .first { $0["id"] as? Int == account }?["current_balance"] as? Double ?? actualBalance
        return json([
            "opening_balance": opening, "forecast_ending_balance": forecastBalance,
            "actual_ending_balance": actualBalance, "rows": rows, "current_balance": current,
        ])
    }

    /// The Calendar across accounts, or one account's with each day's
    /// closing balance.
    static func calendar(account: Int?) -> Data {
        guard let account else { return sample("calendar-all") }
        if account == recordedAccount { return sample("calendar-checking") }
        var all = object("calendar-all") as? [String: Any] ?? [:]
        let lines = events(account: account)
        var balances: [String: Double] = [:]
        var balance = openingBalance(account)
        let month = (all["start"] as? String).flatMap(LocalDay.init) ?? recorded.start
        var day = month
        while day <= month.endOfMonth {
            for e in lines where e["date"] as? String == day.description {
                balance += e["amount"] as? Double ?? 0
            }
            balances[day.description] = balance
            day = LocalDay(year: day.year, month: day.month, day: day.day + 1)
        }
        all["events"] = lines
        all["daily_balances"] = balances
        return json(all)
    }

    /// Bills and income on every account or one; nothing has ended in the
    /// demo. The totals are worked out again for what's listed.
    static func recurring(account: Int?, ended: Bool) -> Data {
        var list = object("recurring") as? [String: Any] ?? [:]
        let items = ended ? [] : (list["items"] as? [[String: Any]] ?? []).filter { account == nil || $0["account_id"] as? Int == account }
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
    /// category (the demo has no tags), newest first.
    static func searchTransactions(_ text: String, category: Int? = nil, tag: Int? = nil) -> Data {
        let found = transactions().filter { row in
            if let category { return row["category_id"] as? Int == category }
            if tag != nil { return false }
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
        all["recurring"] = group((object("recurring") as? [String: Any])?["items"] as? [[String: Any]] ?? [], ["description", "notes"])
        all["accounts"] = group(accounts, ["name"])
        for name in ["categories", "tags", "reports"] { all[name] = group(rows(name), ["name"]) }
        return json(all)
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
            if row["tags"] == nil { row["tags"] = [String]() }
            rows.append(row)
        }
        func day(_ r: [String: Any]) -> String { r["actual_date"] as? String ?? r["forecast_date"] as? String ?? "" }
        return rows.sorted { day($0) > day($1) }
    }

    static func events(account: Int) -> [[String: Any]] {
        ((object("calendar-all") as? [String: Any])?["events"] as? [[String: Any]] ?? [])
            .filter { $0["account_id"] as? Int == account }
    }

    static func openingBalance(_ account: Int) -> Double {
        ((object("dashboard") as? [String: Any])?["cards"] as? [[String: Any]])?
            .first { $0["id"] as? Int == account }?["opening_balance"] as? Double ?? 0
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
