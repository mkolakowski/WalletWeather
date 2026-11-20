import Foundation

/// CSV import (Plans/standalone.md, phase 9, #243): a bank's CSV export,
/// read by the shared core's `csvPreview` and `csvCommit`, the same code the
/// server's `/api/accounts/{id}/import/preview` and `/commit` run. On the
/// iPhone with no server `LocalServer` answers both.

/// Which column holds what: a column's place in the row, or nil.
public struct CSVMapping: Sendable, Codable, Equatable, Hashable {
    public var date: Int?
    public var description: Int?
    public var amount: Int?
    public var debit: Int?
    public var credit: Int?
    public var category: Int?
    public var notes: Int?
    public var tags: Int?
    public var frequency: Int?
    public var endDate: Int?
    public var recurringGroup: Int?

    public init() {}

    // Written out by hand: the API client's decoder turns snake_case keys
    // into camelCase, and the server wants them back as they were.
    enum CodingKeys: String, CodingKey {
        case date, description, amount, debit, credit, category, notes, tags, frequency
        case endDate = "end_date", recurringGroup = "recurring_group"
    }

    public init(from decoder: Decoder) throws {
        // Decoded by the API client (camelCase keys) or from settings saved
        // with this type's own encoder (snake_case): take either.
        let c = try decoder.container(keyedBy: AnyKey.self)
        func value(_ names: String...) -> Int? {
            for name in names { if let v = try? c.decodeIfPresent(Int.self, forKey: AnyKey(name)) { return v } }
            return nil
        }
        date = value("date"); description = value("description"); amount = value("amount")
        debit = value("debit"); credit = value("credit"); category = value("category"); notes = value("notes")
        tags = value("tags"); frequency = value("frequency")
        endDate = value("endDate", "end_date"); recurringGroup = value("recurringGroup", "recurring_group")
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// The columns a person can point somewhere, in the order the picker
    /// lists them.
    public enum Field: String, CaseIterable, Identifiable, Sendable {
        case date, description, amount, debit, credit, category, notes, frequency, endDate, recurringGroup
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .date: "Date"
            case .description: "Description"
            case .amount: "Amount"
            case .debit: "Money out"
            case .credit: "Money in"
            case .category: "Category"
            case .notes: "Notes"
            case .frequency: "Repeats"
            case .endDate: "Repeats until"
            case .recurringGroup: "Series"
            }
        }
    }

    public subscript(field: Field) -> Int? {
        get {
            switch field {
            case .date: date
            case .description: description
            case .amount: amount
            case .debit: debit
            case .credit: credit
            case .category: category
            case .notes: notes
            case .frequency: frequency
            case .endDate: endDate
            case .recurringGroup: recurringGroup
            }
        }
        set {
            switch field {
            case .date: date = newValue
            case .description: description = newValue
            case .amount: amount = newValue
            case .debit: debit = newValue
            case .credit: credit = newValue
            case .category: category = newValue
            case .notes: notes = newValue
            case .frequency: frequency = newValue
            case .endDate: endDate = newValue
            case .recurringGroup: recurringGroup = newValue
            }
        }
    }
}

/// How the file's amounts are signed.
public enum CSVSigns: String, Sendable, Codable, CaseIterable, Identifiable {
    /// One column, money out negative.
    case amount
    /// One column, money out positive.
    case amountInvert = "amount_invert"
    /// Money out and money in in two columns.
    case debitCredit = "debit_credit"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .amount: "Money out is negative"
        case .amountInvert: "Money out is positive"
        case .debitCredit: "Two columns, out and in"
        }
    }
}

/// The body of a preview or an import.
public struct CSVImportBody: Sendable, Encodable, Equatable {
    public var csvText: String
    public var hasHeader = true
    /// nil asks the server to work the columns out (preview only).
    public var mapping: CSVMapping?
    public var signs: CSVSigns = .amount
    public var defaultCategoryId: Int?
    public var skipDuplicates = true

    public init(csvText: String) { self.csvText = csvText }

    enum CodingKeys: String, CodingKey {
        case csvText = "csv_text", hasHeader = "has_header", mapping, signs = "sign_convention"
        case defaultCategoryId = "default_category_id", skipDuplicates = "skip_duplicates"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(csvText, forKey: .csvText)
        try c.encode(hasHeader, forKey: .hasHeader)
        if let mapping { try c.encode(mapping, forKey: .mapping) } else { try c.encodeNil(forKey: .mapping) }
        try c.encode(signs, forKey: .signs)
        try c.encodeIfPresent(defaultCategoryId, forKey: .defaultCategoryId)
        try c.encode(skipDuplicates, forKey: .skipDuplicates)
    }
}

/// What a preview says: the columns found, each row as it would land, and
/// what was left out.
public struct CSVPreview: Sendable, Decodable, Equatable {
    public struct Row: Sendable, Decodable, Equatable, Identifiable {
        public let rowIndex: Int
        public let date: LocalDay
        public let description: String
        public let amount: Money
        public let notes: String?
        public let categoryName: String?
        public let frequency: String?
        public let duplicate: Bool
        public let categoryMatched: Bool
        /// "new" or "existing" for a repeating row, nil otherwise.
        public let recurringTemplate: String?
        public var id: Int { rowIndex }
    }

    public struct Skipped: Sendable, Decodable, Equatable, Identifiable {
        public let rowIndex: Int
        public let row: [String]
        public let reason: String
        public var id: Int { rowIndex }
    }

    public let headers: [String]
    public let mapping: CSVMapping
    /// The first 200.
    public let rows: [Row]
    public let rowCount: Int
    /// The first 50.
    public let skipped: [Skipped]
    public let skippedCount: Int
    public let duplicateCount: Int
    public let recurringCount: Int
}

/// What an import did.
public struct CSVImportResult: Sendable, Decodable, Equatable {
    public let inserted: Int
    public let recurringCreated: Int
    public let recurringLinked: Int
    public let duplicatesSkipped: Int
    public let totalRows: Int
}

extension APIClient {
    /// Reads the file as it would import, adding nothing.
    public func previewImport(_ body: CSVImportBody, account: Int) async throws(APIError) -> CSVPreview {
        try await send("POST", "/api/accounts/\(account)/import/preview", body: body)
    }

    /// Imports the file's rows as paid lines on the account.
    public func commitImport(_ body: CSVImportBody, account: Int) async throws(APIError) -> CSVImportResult {
        try await send("POST", "/api/accounts/\(account)/import/commit", body: body)
    }
}
