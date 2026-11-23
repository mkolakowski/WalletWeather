import Foundation

// The Unmatched list in the app (Plans/standalone.md, phase 8, #239): bank
// lines that paid no planned line, with Match… and Leave, in the server's
// shapes (`/api/accounts/{id}/bank-unmatched...`). A phone without a server
// answers them itself (`LocalBank.swift`).

/// `GET /api/accounts/{id}/bank-unmatched`: newest first.
public struct BankUnmatched: Sendable, Codable, Equatable {
    public let count: Int
    public let lines: [Line]

    public struct Line: Sendable, Codable, Equatable, Identifiable {
        public let id: Int
        public let date: LocalDay
        public let description: String
        public let amount: Money
        public let notes: String?
        /// `bank`, or `alert` (an email alert's line, on a server).
        public let source: String
    }
}

/// `GET .../bank-unmatched/{line}/candidates`: the line, and the planned
/// lines and bill dates it could pay as the match pop-in shows them: one
/// choice per bill, at its nearest open date, going the line's way first.
public struct BankCandidates: Sendable, Codable, Equatable {
    public let line: Line
    public let choices: [Choice]

    public struct Line: Sendable, Codable, Equatable {
        public let id: Int
        public let date: LocalDay
        public let description: String
        public let amount: Money
        /// The bank's full text when the name was shortened from it.
        public let bankText: String?
        /// The name a bill learns with "remember".
        public let learnName: String
    }

    public struct Choice: Sendable, Codable, Equatable, Identifiable {
        public let transactionId: Int?
        public let recurringId: Int?
        public let forecastDate: LocalDay
        public let amount: Money
        public let description: String
        public let daysApart: Int
        /// The bank's date minus the planned date: negative is early.
        public let daysAfter: Int
        /// The bank's amount minus the planned amount.
        public let amountDiff: Money
        public let sameDirection: Bool
        /// Inside the bill's bank-match days.
        public let withinDays: Bool

        public var id: String {
            if let transactionId { return "t\(transactionId)" }
            return "r\(recurringId ?? 0)-\(forecastDate.description)"
        }
    }
}

/// `POST .../bank-unmatched/{line}/match`'s answer.
public struct BankMatchResult: Sendable, Codable, Equatable {
    public let transactionId: Int
    /// The name the bill learned, with "remember".
    public let learned: String?
    /// Lines already on the list that the learned name matched too.
    public let alsoMatched: Int
}

extension APIClient {
    public func bankUnmatched(account: Int) async throws(APIError) -> BankUnmatched {
        try await get("/api/accounts/\(account)/bank-unmatched")
    }

    public func bankCandidates(account: Int, line: Int) async throws(APIError) -> BankCandidates {
        try await get("/api/accounts/\(account)/bank-unmatched/\(line)/candidates")
    }

    /// Pays the choice with the line; `remember` teaches its bill the line's name.
    public func bankMatch(account: Int, line: Int, to choice: BankCandidates.Choice,
                          remember: Bool) async throws(APIError) -> BankMatchResult {
        struct Body: Encodable {
            let transaction_id: Int?
            let recurring_id: Int?
            let forecast_date: String?
            let remember: Bool
        }
        let body = choice.transactionId != nil
            ? Body(transaction_id: choice.transactionId, recurring_id: nil, forecast_date: nil, remember: remember)
            : Body(transaction_id: nil, recurring_id: choice.recurringId, forecast_date: choice.forecastDate.description, remember: remember)
        return try await send("POST", "/api/accounts/\(account)/bank-unmatched/\(line)/match", body: body)
    }

    /// "Leave as its own line": off the Unmatched list.
    public func bankLeave(account: Int, line: Int) async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/accounts/\(account)/bank-unmatched/\(line)/leave",
                                            body: [String: String]())
    }
}
