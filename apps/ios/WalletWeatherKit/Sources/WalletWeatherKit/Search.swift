import Foundation

/// `GET /api/search` (server 1.56.0, #111): everything matching a search,
/// grouped by kind, each group with its full count (ios-app phase 10,
/// #112). Transactions and bills come in the same shape as their own lists,
/// so a result opens in the same editor. Nothing about a search is kept on
/// the phone.
public struct SearchResults: Sendable, Codable, Equatable {
    public let query: String
    public let transactions: Group<TransactionSearch.Hit>
    public let recurring: Group<RecurringItem>
    public let accounts: Group<Account>
    public let categories: Group<Named>
    public let tags: Group<Named>
    public let reports: Group<SavedReport>
    /// Set when the server is older than 1.56.0 and only transactions were
    /// searched (its transaction search stands in).
    public var transactionsOnly = false

    enum CodingKeys: String, CodingKey { case query, transactions, recurring, accounts, categories, tags, reports }

    public struct Group<Item: Sendable & Codable & Equatable>: Sendable, Codable, Equatable {
        public let total: Int
        public let results: [Item]

        public init(total: Int, results: [Item]) {
            self.total = total
            self.results = results
        }

        public static var none: Group { Group(total: 0, results: []) }
    }

    /// A category or tag, with how many transactions you can see carry it.
    public struct Named: Sendable, Codable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let color: String?
        public let transactionCount: Int

        public var countText: String { transactionCount == 1 ? "1 transaction" : "\(transactionCount) transactions" }
    }

    public var isEmpty: Bool {
        transactions.total + recurring.total + accounts.total + categories.total + tags.total + reports.total == 0
    }

    /// An older server's transaction search, as search results.
    public init(query: String, transactionsOnly found: TransactionSearch) {
        self.query = query
        transactions = Group(total: found.total, results: found.results)
        recurring = .none
        accounts = .none
        categories = .none
        tags = .none
        reports = .none
        transactionsOnly = true
    }
}

/// What a list of transactions is filtered by: a category's or a tag's own.
public enum TransactionFilter: Sendable, Equatable, Hashable {
    case category(Int)
    case tag(Int)
}

extension APIClient {
    /// Everything matching `text`. On a server older than 1.56.0, which has
    /// no `/api/search`, its transaction search stands in.
    public func search(_ text: String, limit: Int = 20) async throws(APIError) -> SearchResults {
        do {
            return try await get("/api/search", query: ["q": text, "limit": String(limit), "today": LocalDay.today().description])
        } catch .notWalletWeather, .server(status: 404, detail: _) {
            return SearchResults(query: text, transactionsOnly: try await searchTransactions(text))
        }
    }

    /// The transactions carrying a category or a tag, newest first.
    public func transactions(_ filter: TransactionFilter, limit: Int = 200) async throws(APIError) -> TransactionSearch {
        var query = ["limit": String(limit)]
        switch filter {
        case let .category(id): query["category_id"] = String(id)
        case let .tag(id): query["tag_id"] = String(id)
        }
        return try await get("/api/transactions/search", query: query)
    }
}
