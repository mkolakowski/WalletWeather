import Foundation
import SwiftData

/// Using the app without a server (Plans/standalone.md, phase 4, #235): a
/// `Connection` to an address that can't exist (`.invalid` never resolves),
/// whose requests are answered on the phone from the household in
/// `LocalStore`, through the shared core, in the server's own shapes. The
/// pages don't know the difference, as with the demo (`Demo`).
///
/// - What the server works out (Dashboard, charts, Forecast, Calendar,
///   balances, Bills & income, search) comes from the core, given the rows
///   as the server gives them (apps/server/app/forecast.py).
/// - Saving follows the server's routes: the same checks, the same
///   defaults, a deleted line from a bill skips its date, a transfer is two
///   paid lines.
/// - What needs a server (Net worth, Budgets, Reports, bank sync, sharing,
///   email alerts) answers 404 "Needs a server"; the app shows those places
///   greyed instead of asking (open question 2).
/// - Nothing reaches the network: the session's only handlers are this
///   one and one that refuses every other request (`LocalTests`).
public final class LocalServer: @unchecked Sendable {
    /// The address of the household on this phone.
    public static let host = "this-iphone.walletweather.invalid"
    public static let connection = Connection(server: URL(string: "https://\(host)")!)
    /// The server version whose answers the phone gives.
    public static let answersAs = "1.85.0"

    public let connection: Connection
    let container: ModelContainer
    let lock = NSLock()

    init(container: ModelContainer, host: String) {
        self.container = container
        connection = Connection(server: URL(string: "https://\(host)")!)
    }

    // MARK: - Opening

    nonisolated(unsafe) private static var servers: [String: LocalServer] = [:]
    private static let serversLock = NSLock()

    static func server(for host: String?) -> LocalServer? {
        guard let host else { return nil }
        serversLock.lock()
        defer { serversLock.unlock() }
        if let found = servers[host] { return found }
        guard host == Self.host, let container = try? LocalStore.container(at: LocalStore.folder) else { return nil }
        let server = LocalServer(container: container, host: host)
        servers[host] = server
        return server
    }

    /// The household on this phone, set up (with the server's default
    /// categories) the first time.
    @discardableResult
    public static func openShared() throws -> LocalServer {
        serversLock.lock()
        if let found = servers[host] {
            serversLock.unlock()
            return found
        }
        serversLock.unlock()
        let container = try LocalStore.container(at: LocalStore.folder)
        serversLock.lock()
        let server = servers[host] ?? LocalServer(container: container, host: host)
        servers[host] = server
        serversLock.unlock()
        server.seedIfEmpty()
        server.reconcile()
        return server
    }

    static func closeShared() {
        serversLock.lock()
        servers[host] = nil
        serversLock.unlock()
    }

    /// A household in memory at an address of its own, for the tests;
    /// `seeded: false` leaves out the default categories too.
    static func inMemory(seeded: Bool = true) throws -> LocalServer {
        let host = "t\(UUID().uuidString.lowercased().prefix(8)).\(Self.host)"
        let server = LocalServer(container: try LocalStore.memoryContainer(), host: host)
        serversLock.lock()
        servers[host] = server
        serversLock.unlock()
        if seeded { server.seedIfEmpty() }
        return server
    }

    private func seedIfEmpty() {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        guard (try? context.fetchCount(FetchDescriptor<LocalCategory>())) == 0 else { return }
        let start = Date.now
        for (index, (name, color)) in LocalStore.defaultCategories.enumerated() {
            let category = LocalCategory(name: name, color: color)
            category.added = start.addingTimeInterval(Double(index) / 1000)
            context.insert(category)
        }
        try? context.save()
    }

    /// A session that answers from the household and refuses everything
    /// else.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalProtocol.self, RefuseProtocol.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    // MARK: - Answers

    struct Problem: Error, LocalizedError {
        let status: Int
        let detail: String
        var errorDescription: String? { detail }
        static func notFound(_ what: String = "Not found") -> Problem { Problem(status: 404, detail: what) }
        static func invalid(_ detail: String) -> Problem { Problem(status: 400, detail: detail) }
    }

    static let needsServer = "This needs a server. Using WalletWeather on this iPhone covers Dashboard, Forecast, Bills & income, Calendar and Search."

    /// The answer to a request: a status and a JSON body.
    func answer(method: String, path: String, query: [String: String], body: Data?) -> (status: Int, body: Data) {
        lock.lock()
        defer { lock.unlock() }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let given = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let value = try route(method: method, parts: path.split(separator: "/").map(String.init),
                                  query: query, body: given, context: context)
            if context.hasChanges {
                // iCloud Drive backup (#237) backs up only what changed since.
                markChanged(context)
                try context.save()
            }
            return (200, Self.json(value))
        } catch let problem as Problem {
            return (problem.status, Self.json(["detail": problem.detail]))
        } catch {
            return (500, Self.json(["detail": "Something went wrong on this iPhone: \(error.localizedDescription)"]))
        }
    }

    private func route(method: String, parts: [String], query: [String: String], body: [String: Any],
                       context: ModelContext) throws -> Any {
        guard parts.first == "api" else { throw Problem.notFound() }
        let today = query["today"].flatMap(LocalDay.init) ?? LocalDay.today()
        let rest = Array(parts.dropFirst())
        let id = rest.count > 1 ? Int(rest[1]) : nil
        switch (method, rest.first ?? "", rest.count) {
        case ("GET", "version", 1):
            return ["app_version": Self.answersAs, "schema_version": "on this iPhone"]
        case ("GET", "me", 1):
            return me(context)
        case ("POST", "me", 2) where rest[1] == "acknowledge-notice":
            setFlag("notice_acknowledged", "yes", context)
            return ["ok": true]
        case ("GET", "tags", 1):
            return try tagList(context)
        case ("POST", "tags", 1):
            return try createTag(body, context)
        case ("PATCH", "tags", 2):
            return try updateTag(id, body, context)
        case ("DELETE", "tags", 2):
            return try deleteTag(id, context)
        case ("GET", "categories", 1):
            return try categories(context).map { ["id": $0.id, "name": $0.name, "color": $0.color as Any? ?? NSNull()] }
        case ("GET", "accounts", 1):
            return try accountList(today: today, context)
        case ("POST", "accounts", 1):
            return try createAccount(body, context)
        case ("GET", "accounts", 3) where rest[2] == "forecast":
            return try forecast(account: id, query: query, today: today, context)
        case ("POST", "accounts", 3) where rest[2] == "transactions":
            return try createTransaction(account: id, body, context)
        case ("POST", "accounts", 4) where rest[2] == "import" && (rest[3] == "preview" || rest[3] == "commit"):
            return try csvImport(account: id, body, commit: rest[3] == "commit", context)
        case ("POST", "accounts", 3) where rest[2] == "recurring":
            return try createRecurring(account: id, body, context)
        case ("GET", "dashboard", 1):
            return try run("dashboard", ["today": today.description, "accounts": accountRows(context)])
        case ("GET", "dashboard", 2) where rest[1] == "charts":
            return try run("dashboardCharts", ["window": query["window"] ?? "month", "today": today.description,
                                               "categories": categoryRows(context), "accounts": accountRows(context)])
        case ("GET", "calendar", 1):
            return try calendar(query: query, context)
        case ("GET", "recurring", 1):
            return try recurringList(query: query, today: today, context)
        case ("PATCH", "recurring", 2):
            return try updateRecurring(id, body, context)
        case ("POST", "recurring", 3) where rest[2] == "skip":
            return try skip(id, body, context)
        case ("DELETE", "recurring", 3) where rest[2] == "skips":
            return try restoreSkips(id, context)
        case ("PATCH", "transactions", 2):
            return try updateTransaction(id, body, context)
        case ("DELETE", "transactions", 2):
            return try deleteTransaction(id, context)
        case ("GET", "transactions", 2) where rest[1] == "search":
            return try searchTransactions(query: query, context)
        case ("POST", "transfers", 1):
            return try createTransfer(body, context)
        case ("DELETE", "transfers", 2):
            return try deleteTransfer(id, context)
        case ("GET", "search", 1):
            return try search(query: query, today: today, context)
        default:
            throw Problem.notFound(Self.needsServer)
        }
    }

    // MARK: Who's here

    private func me(_ context: ModelContext) -> [String: Any] {
        ["id": 1, "email": "", "name": NSNull(), "is_admin": false, "token_access": "full",
         "theme_preference": NSNull(), "notice_required": flag("notice_acknowledged", context) == nil,
         "has_password": false]
    }

    /// A setting's value. Two devices may each have made it before syncing
    /// (#238): until `reconcile` joins them, read them as it would.
    func flag(_ name: String, _ context: ModelContext) -> String? {
        let found = (try? context.fetch(FetchDescriptor<LocalFlag>(predicate: #Predicate { $0.name == name }))) ?? []
        return Self.joinedFlag(name, found)
    }

    /// Sets a setting, on every copy of it.
    func setFlag(_ name: String, _ value: String, _ context: ModelContext) {
        let found = (try? context.fetch(FetchDescriptor<LocalFlag>(predicate: #Predicate { $0.name == name }))) ?? []
        if found.isEmpty {
            context.insert(LocalFlag(name: name, value: value))
        } else {
            for row in found where row.value != value { row.value = value }
        }
    }

    // MARK: Reading the rows

    func ordered<T: PersistentModel>(_ type: T.Type, _ context: ModelContext,
                                             added: KeyPath<T, Date>, id: KeyPath<T, Int>) throws -> [T] {
        try context.fetch(FetchDescriptor<T>()).sorted {
            $0[keyPath: added] != $1[keyPath: added] ? $0[keyPath: added] < $1[keyPath: added] : $0[keyPath: id] < $1[keyPath: id]
        }
    }

    private func accounts(_ context: ModelContext) throws -> [LocalAccount] {
        try ordered(LocalAccount.self, context, added: \.added, id: \.id).filter { !$0.archived }
    }

    private func account(_ id: Int?, _ context: ModelContext) throws -> LocalAccount {
        guard let id, let found = try accounts(context).first(where: { $0.id == id }) else {
            throw Problem.notFound("Account not found")
        }
        return found
    }

    /// In name order, as the server's list.
    private func categories(_ context: ModelContext) throws -> [LocalCategory] {
        try ordered(LocalCategory.self, context, added: \.added, id: \.id)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// In the order they were added, as the core takes them.
    private func categoryRows(_ context: ModelContext) throws -> [[String: Any]] {
        try ordered(LocalCategory.self, context, added: \.added, id: \.id)
            .map { ["id": $0.id, "name": $0.name, "color": $0.color as Any? ?? NSNull()] }
    }

    private func categoryNames(_ context: ModelContext) throws -> [Int: LocalCategory] {
        Dictionary(try context.fetch(FetchDescriptor<LocalCategory>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func recurringRow(_ r: LocalRecurring, _ categories: [Int: LocalCategory], forList: Bool = false,
                              skipCounts: [Int: Int] = [:], tags: TagIndex = TagIndex()) -> [String: Any] {
        var row: [String: Any] = [
            "id": r.id, "frequency": r.frequency, "day_of_month": r.dayOfMonth as Any? ?? NSNull(),
            "anchor_date": r.anchorDate as Any? ?? NSNull(), "end_date": r.endDate as Any? ?? NSNull(),
            "active": r.active, "amount": r.amount, "description": r.name, "notes": r.notes as Any? ?? NSNull(),
            "category": r.categoryID.flatMap { categories[$0]?.name } as Any? ?? NSNull(),
            "category_id": r.categoryID as Any? ?? NSNull(), "tags": tags.bill(r.id),
        ]
        if forList {
            row["category_color"] = r.categoryID.flatMap { categories[$0]?.color } as Any? ?? NSNull()
            row["match_days"] = r.matchDays
            row["match_percent"] = r.matchPercent
            row["match_text"] = r.matchText as Any? ?? NSNull()
            row["skipped_count"] = skipCounts[r.id] ?? 0
        }
        return row
    }

    private func lineRow(_ t: LocalTransaction, _ categories: [Int: LocalCategory], tags: TagIndex = TagIndex()) -> [String: Any] {
        [
            "id": t.id, "recurring_id": t.recurringID as Any? ?? NSNull(),
            "category_id": t.categoryID as Any? ?? NSNull(),
            "category": t.categoryID.flatMap { categories[$0]?.name } as Any? ?? NSNull(),
            "transfer_id": t.transferID as Any? ?? NSNull(), "description": t.name,
            "notes": t.notes as Any? ?? NSNull(), "amount": t.amount,
            "forecast_amount": t.forecastAmount as Any? ?? NSNull(),
            "forecast_date": t.forecastDate as Any? ?? NSNull(), "actual_date": t.actualDate as Any? ?? NSNull(),
            "is_actual": t.isActual, "bank_match": NSNull(), "has_bank_ref": false, "has_mail_ref": false,
            "bank_left": false, "tags": tags.line(t.id),
        ]
    }

    /// The core's forecast input for every account (forecast.account_rows).
    private func accountRows(_ context: ModelContext, only: Int? = nil) throws -> [[String: Any]] {
        let categories = try categoryNames(context)
        let tags = try tagIndex(context)
        let lines = try ordered(LocalTransaction.self, context, added: \.added, id: \.id)
        let recs = try ordered(LocalRecurring.self, context, added: \.added, id: \.id)
        let skips = try context.fetch(FetchDescriptor<LocalSkip>()).sorted {
            $0.recurringID != $1.recurringID ? $0.recurringID < $1.recurringID : $0.date < $1.date
        }
        return try accounts(context).filter { only == nil || $0.id == only }.map { account in
            let active = recs.filter { $0.accountID == account.id && $0.active }
            let ids = Set(active.map(\.id))
            return [
                "id": account.id, "name": account.name, "starting_balance": account.startingBalance,
                "transactions": lines.filter { $0.accountID == account.id }.map { lineRow($0, categories, tags: tags) },
                "recurring": active.map { recurringRow($0, categories, tags: tags) },
                "skips": skips.filter { ids.contains($0.recurringID) }.map { ["recurring_id": $0.recurringID, "date": $0.date] },
            ]
        }
    }

    private func run(_ name: String, _ input: [String: Any]) throws -> Any {
        do {
            return try Core.shared.run(name, input)
        } catch {
            throw Problem(status: 500, detail: "The numbers couldn't be worked out: \(error)")
        }
    }

    private func balance(_ row: [String: Any], on day: LocalDay) throws -> Double {
        var input = row
        input["as_of"] = day.description
        return try run("actualBalanceAsOf", input) as? Double ?? 0
    }

    // MARK: Pages

    private func accountList(today: LocalDay, _ context: ModelContext) throws -> [[String: Any]] {
        let rows = try accountRows(context)
        return try zip(try accounts(context), rows).map { account, row in
            ["id": account.id, "name": account.name, "starting_balance": account.startingBalance,
             "starting_date": account.startingDate, "current_balance": try balance(row, on: today),
             "archived": account.archived, "level": "owner"]
        }
    }

    private func forecast(account id: Int?, query: [String: String], today: LocalDay, _ context: ModelContext) throws -> Any {
        let account = try account(id, context)
        guard var input = try accountRows(context, only: account.id).first else { throw Problem.notFound("Account not found") }
        let start = query["start"].flatMap(LocalDay.init) ?? today
        let end = query["end"].flatMap(LocalDay.init) ?? today.adding(days: 90)
        guard start <= end else { throw Problem.invalid("end must be on or after start") }
        let current = try balance(input, on: today)
        input["start"] = start.description
        input["end"] = end.description
        guard var answer = try run("forecast", input) as? [String: Any] else { throw Problem(status: 500, detail: "No forecast") }
        answer["current_balance"] = current
        answer["bank_unmatched_count"] = 0
        return answer
    }

    private func calendar(query: [String: String], _ context: ModelContext) throws -> Any {
        guard let start = query["start"].flatMap(LocalDay.init), let end = query["end"].flatMap(LocalDay.init) else {
            throw Problem.invalid("start and end are needed")
        }
        guard start <= end else { throw Problem.invalid("end must be on or after start") }
        guard end.days(since: start) <= 366 else { throw Problem.invalid("window exceeds 366 days") }
        let only = query["account_id"].flatMap(Int.init)
        if only != nil { _ = try account(only, context) }
        return try run("calendar", ["start": start.description, "end": end.description, "single_account": only != nil,
                                    "categories": categoryRows(context), "accounts": accountRows(context, only: only)])
    }

    /// The core's `accounts` for Bills & income and search
    /// (forecast.recurring_accounts).
    private func recurringAccounts(_ list: [LocalAccount], today: LocalDay, _ context: ModelContext,
                                   keep: (LocalRecurring) -> Bool = { _ in true }) throws -> [[String: Any]] {
        let categories = try categoryNames(context)
        let tags = try tagIndex(context)
        let recs = try ordered(LocalRecurring.self, context, added: \.added, id: \.id).filter(keep)
        let skips = try context.fetch(FetchDescriptor<LocalSkip>())
        let skipCounts = Dictionary(grouping: skips, by: \.recurringID).mapValues(\.count)
        let lines = try context.fetch(FetchDescriptor<LocalTransaction>())
        let from = today.description
        return list.map { account in
            let mine = recs.filter { $0.accountID == account.id }
            let ids = Set(mine.map(\.id))
            return [
                "id": account.id, "name": account.name, "level": "owner",
                "recurring": mine.map { recurringRow($0, categories, forList: true, skipCounts: skipCounts, tags: tags) },
                "skips": skips.filter { ids.contains($0.recurringID) }
                    .sorted { $0.recurringID != $1.recurringID ? $0.recurringID < $1.recurringID : $0.date < $1.date }
                    .map { ["recurring_id": $0.recurringID, "date": $0.date] },
                "paid": lines.compactMap { t -> (Int, String)? in
                    guard let rid = t.recurringID, ids.contains(rid), t.isActual, let day = t.forecastDate, day >= from else { return nil }
                    return (rid, day)
                }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map { ["recurring_id": $0.0, "date": $0.1] },
            ]
        }
    }

    private func recurringList(query: [String: String], today: LocalDay, _ context: ModelContext) throws -> Any {
        var list = try accounts(context)
        if let only = query["account_id"].flatMap(Int.init) {
            list = [try account(only, context)]
        }
        return try run("recurringList", ["today": today.description, "archived": query["archived"] == "true",
                                         "accounts": recurringAccounts(list, today: today, context)])
    }

    private func searchLines(_ context: ModelContext) throws -> [[String: Any]] {
        let categories = try categoryNames(context)
        let tags = try tagIndex(context)
        let visible = Set(try accounts(context).map(\.id))
        return try ordered(LocalTransaction.self, context, added: \.added, id: \.id)
            .filter { visible.contains($0.accountID) }
            .map { t in
                ["id": t.id, "account_id": t.accountID, "description": t.name, "notes": t.notes as Any? ?? NSNull(),
                 "amount": t.amount, "forecast_amount": t.forecastAmount as Any? ?? NSNull(),
                 "actual_date": t.actualDate as Any? ?? NSNull(), "forecast_date": t.forecastDate as Any? ?? NSNull(),
                 "is_actual": t.isActual, "category_id": t.categoryID as Any? ?? NSNull(),
                 "category": t.categoryID.flatMap { categories[$0]?.name } as Any? ?? NSNull(),
                 "recurring_id": t.recurringID as Any? ?? NSNull(), "transfer_id": t.transferID as Any? ?? NSNull(),
                 "tags": tags.line(t.id)]
            }
    }

    private func searchTransactions(query: [String: String], _ context: ModelContext) throws -> Any {
        func int(_ key: String) -> Any { query[key].flatMap(Int.init) as Any? ?? NSNull() }
        func number(_ key: String) -> Any { query[key].flatMap(Double.init) as Any? ?? NSNull() }
        func text(_ key: String) -> Any { query[key] as Any? ?? NSNull() }
        if let only = query["account_id"].flatMap(Int.init) { _ = try account(only, context) }
        if let only = query["tag_id"].flatMap(Int.init) { _ = try tag(only, context) }
        return try run("searchTransactions", [
            "q": text("q"), "account_id": int("account_id"), "category_id": int("category_id"), "tag_id": int("tag_id"),
            "date_from": text("date_from"), "date_to": text("date_to"), "min_amount": number("min_amount"),
            "max_amount": number("max_amount"), "kind": text("kind"),
            "include_transfers": query["include_transfers"].map { $0 != "false" } ?? true,
            "limit": query["limit"].flatMap(Int.init) ?? 100, "offset": query["offset"].flatMap(Int.init) ?? 0,
            "accounts": try accounts(context).map { ["id": $0.id, "name": $0.name] },
            "transactions": searchLines(context),
        ])
    }

    private func search(query: [String: String], today: LocalDay, _ context: ModelContext) throws -> Any {
        let list = try accounts(context)
        var found = try recurringAccounts(list, today: today, context)
        for (index, row) in try accountRows(context).enumerated() where index < found.count {
            found[index]["current_balance"] = try balance(row, on: today)
        }
        return try run("search", ["q": query["q"] ?? "", "limit": query["limit"].flatMap(Int.init) ?? 20,
                                  "today": today.description, "accounts": found,
                                  "transactions": searchLines(context), "categories": categoryRows(context),
                                  "tags": try tagList(context), "reports": [Any]()])
    }

    // MARK: Saving

    private static let nameMax = 120, descriptionMax = 500, notesMax = 256

    private func text(_ body: [String: Any], _ key: String, max: Int, required: Bool = true) throws -> String? {
        guard let value = body[key] as? String else {
            if required { throw Problem.invalid("\(key) is required") }
            return nil
        }
        guard value.count <= max else { throw Problem.invalid("\(key) is longer than \(max) characters") }
        return value
    }

    private func money(_ body: [String: Any], _ key: String, required: Bool = true) throws -> Double? {
        guard let value = body[key], !(value is NSNull) else {
            if required { throw Problem.invalid("\(key) is required") }
            return nil
        }
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite, abs(number) <= 1e12 else {
            throw Problem.invalid("\(key) must be an amount")
        }
        return number
    }

    private func day(_ body: [String: Any], _ key: String) throws -> String? {
        guard let value = body[key], !(value is NSNull) else { return nil }
        guard let text = value as? String, let parsed = LocalDay(text) else { throw Problem.invalid("\(key) must be a date") }
        return parsed.description
    }

    private func int(_ body: [String: Any], _ key: String) -> Int? {
        (body[key] as? NSNumber)?.intValue
    }

    private func category(_ body: [String: Any], _ context: ModelContext) throws -> Int? {
        guard let id = int(body, "category_id") else { return nil }
        guard try categoryNames(context)[id] != nil else { throw Problem.notFound("Category not found") }
        return id
    }

    private func createAccount(_ body: [String: Any], _ context: ModelContext) throws -> Any {
        let name = (try text(body, "name", max: Self.nameMax) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Problem.invalid("Name is required") }
        let balance = try money(body, "starting_balance") ?? 0
        guard let starting = try day(body, "starting_date") else { throw Problem.invalid("starting_date is required") }
        let account = LocalAccount(name: name, startingBalance: balance, startingDate: starting)
        context.insert(account)
        return ["id": account.id]
    }

    private func createTransaction(account id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let account = try account(id, context)
        let line = LocalTransaction(accountID: account.id)
        if let rid = int(body, "recurring_id") {
            // A line belongs to a bill on its own account, or to none (#183).
            guard try context.fetch(FetchDescriptor<LocalRecurring>()).contains(where: { $0.id == rid && $0.accountID == account.id }) else {
                throw Problem.notFound("Recurring item not found")
            }
            line.recurringID = rid
        }
        try fill(line, body, context, creating: true)
        let ids = try tagIDs(body, context)
        context.insert(line)
        // A line saved from a bill starts with its tags (#118).
        if let ids { try setTags(ids, line: line.id, context) }
        else if let rid = line.recurringID { try setTags(try billTagIDs(rid, context), line: line.id, context) }
        return ["id": line.id]
    }

    private func fill(_ line: LocalTransaction, _ body: [String: Any], _ context: ModelContext, creating: Bool) throws {
        line.name = try text(body, "description", max: Self.descriptionMax) ?? ""
        line.amount = try money(body, "amount") ?? 0
        line.forecastDate = try day(body, "forecast_date")
        line.actualDate = try day(body, "actual_date")
        line.isActual = body["is_actual"] as? Bool ?? false
        line.categoryID = try category(body, context)
        line.notes = try text(body, "notes", max: Self.notesMax, required: false)
        // As the server: a missing planned amount leaves the one it had.
        if let planned = try money(body, "forecast_amount", required: false) { line.forecastAmount = planned }
    }

    private func line(_ id: Int?, _ context: ModelContext) throws -> LocalTransaction {
        guard let id, let found = try context.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.id == id })).first else {
            throw Problem.notFound()
        }
        return found
    }

    private func updateTransaction(_ id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let found = try line(id, context)
        try fill(found, body, context, creating: false)
        if let ids = try tagIDs(body, context) { try setTags(ids, line: found.id, context) }
        return ["ok": true]
    }

    private func deleteTransaction(_ id: Int?, _ context: ModelContext) throws -> Any {
        let found = try line(id, context)
        // A line from a bill would be projected again on its date: skip it.
        if let rid = found.recurringID, let day = found.forecastDate { addSkip(rid, day, context) }
        try dropLinks(line: found.id, context)
        context.delete(found)
        return ["ok": true]
    }

    private func recurring(_ id: Int?, _ context: ModelContext) throws -> LocalRecurring {
        guard let id, let found = try context.fetch(FetchDescriptor<LocalRecurring>(predicate: #Predicate { $0.id == id })).first,
              try accounts(context).contains(where: { $0.id == found.accountID }) else {
            throw Problem.notFound()
        }
        return found
    }

    private func fill(_ rec: LocalRecurring, _ body: [String: Any], _ context: ModelContext, creating: Bool) throws {
        let frequency = body["frequency"] as? String ?? ""
        guard ["monthly_day", "weekly", "biweekly"].contains(frequency) else {
            throw Problem.invalid("frequency must be monthly_day, weekly or biweekly")
        }
        let dayOfMonth = int(body, "day_of_month")
        if let dayOfMonth, !(1...31).contains(dayOfMonth) { throw Problem.invalid("day_of_month must be 1 to 31") }
        let anchor = try day(body, "anchor_date")
        if frequency == "monthly_day", dayOfMonth == nil { throw Problem.invalid("a monthly item needs day_of_month") }
        if frequency != "monthly_day", anchor == nil {
            throw Problem.invalid("a weekly or biweekly item needs anchor_date, its first date")
        }
        rec.name = try text(body, "description", max: Self.descriptionMax) ?? ""
        rec.amount = try money(body, "amount") ?? 0
        rec.frequency = frequency
        rec.dayOfMonth = dayOfMonth
        rec.anchorDate = anchor
        rec.endDate = try day(body, "end_date")
        rec.categoryID = try category(body, context)
        rec.notes = try text(body, "notes", max: Self.notesMax, required: false)
        rec.active = body["active"] as? Bool ?? true
        if let days = int(body, "match_days") {
            guard (0...31).contains(days) else { throw Problem.invalid("match_days must be 0 to 31") }
            rec.matchDays = days
        }
        if let percent = int(body, "match_percent") {
            guard (0...100).contains(percent) else { throw Problem.invalid("match_percent must be 0 to 100") }
            rec.matchPercent = percent
        }
    }

    private func createRecurring(account id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let account = try account(id, context)
        let rec = LocalRecurring(accountID: account.id)
        try fill(rec, body, context, creating: true)
        let ids = try tagIDs(body, context)
        context.insert(rec)
        if let ids { try setTags(ids, bill: rec.id, context) }
        return ["id": rec.id]
    }

    private func updateRecurring(_ id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let rec = try recurring(id, context)
        try fill(rec, body, context, creating: false)
        if let ids = try tagIDs(body, context) { try setTags(ids, bill: rec.id, context) }
        return ["ok": true]
    }

    private func addSkip(_ rid: Int, _ day: String, _ context: ModelContext) {
        let exists = (try? context.fetch(FetchDescriptor<LocalSkip>(predicate: #Predicate { $0.recurringID == rid && $0.date == day })))?.isEmpty == false
        if !exists { context.insert(LocalSkip(recurringID: rid, date: day)) }
    }

    private func skip(_ id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let rec = try recurring(id, context)
        guard let day = try day(body, "skip_date") else { throw Problem.invalid("skip_date is required") }
        addSkip(rec.id, day, context)
        return ["ok": true]
    }

    /// Brings back every date deleted from a bill (the server's
    /// `restore_recurring_occurrences`, #246).
    private func restoreSkips(_ id: Int?, _ context: ModelContext) throws -> Any {
        let rec = try recurring(id, context)
        let rid = rec.id
        let skips = try context.fetch(FetchDescriptor<LocalSkip>(predicate: #Predicate { $0.recurringID == rid }))
        for skip in skips { context.delete(skip) }
        return ["restored": skips.count]
    }

    /// Deletes a transfer and its two lines (the server's `delete_transfer`).
    private func deleteTransfer(_ id: Int?, _ context: ModelContext) throws -> Any {
        guard let id,
              let transfer = try context.fetch(FetchDescriptor<LocalTransfer>(predicate: #Predicate { $0.id == id })).first
        else { throw Problem.notFound("Transfer not found") }
        for leg in try context.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.transferID == id })) {
            try dropLinks(line: leg.id, context)
            context.delete(leg)
        }
        context.delete(transfer)
        return ["ok": true]
    }

    private func createTransfer(_ body: [String: Any], _ context: ModelContext) throws -> Any {
        guard let fromID = int(body, "from_account_id"), let toID = int(body, "to_account_id") else {
            throw Problem.invalid("from_account_id and to_account_id are required")
        }
        guard fromID != toID else { throw Problem.invalid("from_account and to_account must differ") }
        let from = try account(fromID, context), to = try account(toID, context)
        guard let amount = try money(body, "amount"), amount > 0 else { throw Problem.invalid("amount must be more than 0") }
        guard let date = try day(body, "transfer_date") else { throw Problem.invalid("transfer_date is required") }
        let typed = (try text(body, "description", max: 120, required: false) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? "Transfer" : typed
        let notes = try text(body, "notes", max: Self.notesMax, required: false)
        let transfer = LocalTransfer(fromAccountID: from.id, toAccountID: to.id, amount: amount, date: date, name: name, notes: notes)
        context.insert(transfer)
        var legs: [Int] = []
        // Two paid lines on the day, as the server's _create_transfer_legs.
        for (account, sign, arrow) in [(from, -1.0, "→"), (to, 1.0, "←")] {
            let leg = LocalTransaction(accountID: account.id)
            leg.transferID = transfer.id
            leg.actualDate = date
            leg.forecastDate = date
            leg.isActual = true
            leg.name = "\(arrow) \(name)"
            leg.amount = sign * amount
            leg.notes = notes
            context.insert(leg)
            legs.append(leg.id)
        }
        return ["id": transfer.id, "from_account_id": from.id, "from_account_name": from.name, "to_account_id": to.id,
                "to_account_name": to.name, "amount": amount, "transfer_date": date, "description": name,
                "notes": notes as Any? ?? NSNull(), "transaction_ids": legs.sorted(),
                "created_at": ISO8601DateFormatter().string(from: transfer.added)]
    }

    // MARK: CSV import (#243)

    /// `/api/accounts/{id}/import/preview` and `/commit`, with the server's
    /// checks: the core reads the file against the account's lines and
    /// bills; an import then makes the bills and lines it plans.
    private func csvImport(account id: Int?, _ body: [String: Any], commit: Bool, _ context: ModelContext) throws -> Any {
        let account = try account(id, context)
        guard let text = body["csv_text"] as? String else { throw Problem(status: 422, detail: "csv_text is required") }
        if !commit, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Problem.invalid("csv_text is empty") }
        let signs = body["sign_convention"] as? String ?? "amount"
        guard ["amount", "amount_invert", "debit_credit"].contains(signs) else { throw Problem.invalid("Invalid sign_convention") }
        var mapping: Any = NSNull()
        if let given = body["mapping"] as? [String: Any] {
            var clean: [String: Any] = [:]
            for (key, value) in given {
                if value is NSNull { clean[key] = NSNull() } else if let n = value as? Int { clean[key] = n } else {
                    throw Problem(status: 422, detail: "mapping.\(key) must be a whole number or null")
                }
            }
            mapping = clean
        } else if commit {
            throw Problem(status: 422, detail: "mapping is required")
        }
        var input: [String: Any] = [
            "csv_text": text, "has_header": body["has_header"] as? Bool ?? true, "mapping": mapping,
            "sign_convention": signs,
        ]
        let fallback = body["default_category_id"] as? Int
        if commit {
            if let fallback, try categories(context).first(where: { $0.id == fallback }) == nil {
                throw Problem.notFound("Category not found")
            }
            input["default_category_id"] = fallback as Any? ?? NSNull()
            input["skip_duplicates"] = body["skip_duplicates"] as? Bool ?? true
        }
        let lines = try ordered(LocalTransaction.self, context, added: \.added, id: \.id).filter { $0.accountID == account.id }
        input["lines"] = lines.compactMap { t -> [String: Any]? in
            guard let day = t.actualDate ?? t.forecastDate else { return nil }
            return ["date": day, "amount": t.amount, "description": t.name]
        }
        let recs = try ordered(LocalRecurring.self, context, added: \.added, id: \.id).filter { $0.accountID == account.id }
        input["recurring"] = recs.map { ["id": $0.id, "frequency": $0.frequency, "description": $0.name] as [String: Any] }
        input["categories"] = try categories(context).map { ["id": $0.id, "name": $0.name] as [String: Any] }
        input["tags"] = try context.fetch(FetchDescriptor<LocalTag>()).sorted { $0.id < $1.id }.map { ["id": $0.id, "name": $0.name] as [String: Any] }

        let answer: Any
        do {
            answer = try Core.shared.run(commit ? "csvCommit" : "csvPreview", input)
        } catch let .failed(message) {
            let said = message.hasPrefix("Error: ") ? String(message.dropFirst(7)) : message
            throw Problem.invalid("That file couldn't be read as CSV: \(said)")
        } catch {
            throw Problem(status: 500, detail: "The file couldn't be read: \(error)")
        }
        guard commit else { return answer }
        guard let plan = answer as? [String: Any], let result = plan["result"] else {
            throw Problem(status: 500, detail: "The import couldn't be worked out.")
        }
        // Rows keep the file's order: each is "added" a moment after the last.
        let start = Date.now
        var step = 0.0
        func next() -> Date { step += 1; return start.addingTimeInterval(step / 1_000_000) }
        func optionalText(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var made: [LocalRecurring] = []
        for case let tpl as [String: Any] in plan["templates"] as? [Any] ?? [] {
            let rec = LocalRecurring(accountID: account.id)
            rec.name = tpl["description"] as? String ?? ""
            rec.amount = (tpl["amount"] as? NSNumber)?.doubleValue ?? 0
            rec.frequency = tpl["frequency"] as? String ?? "monthly_day"
            rec.dayOfMonth = tpl["day_of_month"] as? Int
            rec.anchorDate = tpl["anchor_date"] as? String
            rec.endDate = tpl["end_date"] as? String
            rec.categoryID = tpl["category_id"] as? Int
            rec.notes = optionalText(tpl["notes"])
            rec.added = next()
            context.insert(rec)
            made.append(rec)
        }
        for case let row as [String: Any] in plan["transactions"] as? [Any] ?? [] {
            let line = LocalTransaction(accountID: account.id)
            if let link = row["recurring"] as? [String: Any] {
                if let place = link["new"] as? Int, made.indices.contains(place) { line.recurringID = made[place].id }
                else { line.recurringID = link["id"] as? Int }
            }
            line.categoryID = row["category_id"] as? Int
            line.name = row["description"] as? String ?? ""
            line.amount = (row["amount"] as? NSNumber)?.doubleValue ?? 0
            line.notes = optionalText(row["notes"])
            let day = row["date"] as? String
            line.actualDate = day
            line.forecastDate = day
            line.isActual = true
            line.added = next()
            context.insert(line)
            for case let tag as Int in row["tag_ids"] as? [Any] ?? [] { context.insert(LocalTagLink(tagID: tag, transactionID: line.id)) }
        }
        return result
    }

    static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("{}".utf8)
    }
}

extension Connection {
    /// The household on this phone: answered here, never the network.
    public var isLocal: Bool {
        guard let host = server.host() else { return false }
        return host == LocalServer.host || host.hasSuffix("." + LocalServer.host)
    }
}

/// Answers the household's requests on the phone.
final class LocalProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        LocalServer.server(for: request.url?.host()) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = LocalServer.server(for: url.host()) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in parts?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let (status, body) = server.answer(method: request.httpMethod ?? "GET", path: parts?.path ?? url.path(),
                                           query: query, body: request.httpBody ?? Self.read(request.httpBodyStream))
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A request's body reaches a URLProtocol as a stream.
    static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Fails every request the household's own handler didn't take, so nothing
/// leaves the phone in standalone. `refused` counts them, for the tests.
final class RefuseProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var refused = 0
    private static let countLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.countLock.lock()
        Self.refused += 1
        Self.countLock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
