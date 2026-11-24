import Foundation

/// Quick add with remembered names (#325): as a name is typed in Add
/// transaction, names used on past lines are offered, each with the
/// category it was last given; and a note says when a tag rule will tag
/// the line. Both are worked out here from what the app already loads
/// (the last months of lines, and the tag rules); nothing is kept.

/// One use of a name: a past line's name, its category and its day.
public struct NameUse: Sendable, Equatable {
    public let name: String
    public let categoryId: Int?
    public let categoryName: String?
    public let day: LocalDay?

    public init(name: String, categoryId: Int? = nil, categoryName: String? = nil, day: LocalDay? = nil) {
        self.name = name
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.day = day
    }
}

/// A name offered while typing, one per name however it's capitalised.
public struct NameSuggestion: Sendable, Equatable, Identifiable {
    /// The name as it was last written.
    public let name: String
    /// The category it was last used with (nil when it never had one).
    public let categoryId: Int?
    public let categoryName: String?
    /// How many past lines carry the name.
    public let count: Int
    public let lastUsed: LocalDay?

    public var id: String { NameSuggestions.key(name) }
}

public enum NameSuggestions {
    /// The fewest letters typed before names are offered.
    public static let minimumLetters = 2
    /// The most names offered at once.
    public static let defaultLimit = 4
    /// How far back the app looks for names, in days (about six months).
    public static let lookbackDays = 183
    /// The most past lines asked for.
    public static let lineLimit = 500

    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Past lines as uses of a name: transfers are left out (their names
    /// are made by the app, not typed).
    public static func uses(_ hits: [TransactionSearch.Hit]) -> [NameUse] {
        hits.filter { $0.transferId == nil }.map {
            NameUse(name: $0.description, categoryId: $0.categoryId, categoryName: $0.categoryName,
                    day: $0.actualDate ?? $0.forecastDate)
        }
    }

    /// One entry per name (case-insensitive): how often it was used, when
    /// last, how it was last written and the category of its latest line
    /// that had one.
    public static func index(_ uses: [NameUse]) -> [NameSuggestion] {
        struct Tally {
            var name: String
            var nameDay: LocalDay?
            var category: (id: Int?, name: String?, day: LocalDay?)?
            var count = 0
            var last: LocalDay?
        }
        func newer(_ a: LocalDay?, than b: LocalDay?) -> Bool {
            guard let a else { return false }
            guard let b else { return true }
            return a >= b
        }
        var tallies: [String: Tally] = [:]
        for use in uses {
            let shown = use.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = key(shown)
            guard !key.isEmpty else { continue }
            var tally = tallies[key] ?? Tally(name: shown, nameDay: use.day)
            tally.count += 1
            if newer(use.day, than: tally.last) { tally.last = use.day }
            if newer(use.day, than: tally.nameDay) { tally.name = shown; tally.nameDay = use.day }
            if use.categoryId != nil, tally.category == nil || newer(use.day, than: tally.category?.day) {
                tally.category = (use.categoryId, use.categoryName, use.day)
            }
            tallies[key] = tally
        }
        return tallies.values.map {
            NameSuggestion(name: $0.name, categoryId: $0.category?.id, categoryName: $0.category?.name,
                           count: $0.count, lastUsed: $0.last)
        }
    }

    /// Up to `limit` names for what's been typed: none under two letters;
    /// names starting with it before names containing it, then the most
    /// used, then the most recent, then A to Z. Case doesn't matter, and a
    /// name already typed in full isn't offered back.
    public static func suggest(_ typed: String, in entries: [NameSuggestion], limit: Int = defaultLimit) -> [NameSuggestion] {
        let needle = key(typed)
        guard needle.count >= minimumLetters, limit > 0 else { return [] }
        let shown = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = entries.compactMap { entry -> (NameSuggestion, Bool)? in
            let name = key(entry.name)
            guard name.contains(needle), entry.name != shown else { return nil }
            return (entry, name.hasPrefix(needle))
        }
        return found.sorted { a, b in
            if a.1 != b.1 { return a.1 }
            if a.0.count != b.0.count { return a.0.count > b.0.count }
            if a.0.lastUsed != b.0.lastUsed {
                guard let x = a.0.lastUsed else { return false }
                guard let y = b.0.lastUsed else { return true }
                return x > y
            }
            return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
        }
        .prefix(limit).map(\.0)
    }
}

extension APIClient {
    /// The last months' lines, newest first, for the names to offer. The
    /// server (and the household on this iPhone) answer it as the
    /// Transactions search.
    public func nameHistory(today: LocalDay = .today()) async throws(APIError) -> [NameUse] {
        let found: TransactionSearch = try await get("/api/transactions/search", query: [
            "limit": String(NameSuggestions.lineLimit),
            "date_from": today.adding(days: -NameSuggestions.lookbackDays).description,
            "include_transfers": "false"])
        return NameSuggestions.uses(found.results)
    }
}

// MARK: - The tag rule note

extension TagRule {
    /// Whether the server would tag a new line with this rule: the rule is
    /// on, the line's name (as typed, lowercased) contains the rule's
    /// pattern, and, when the rule names a category, the line is in it.
    /// The server's `_apply_tag_rules`, which matches the stored (already
    /// lowercased) pattern as a substring of the lowercased name.
    public func applies(toName name: String, categoryId line: Int?) -> Bool {
        guard active else { return false }
        if let categoryId, categoryId != line { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .contains(descriptionPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

public enum TagRuleNote {
    /// "Will be tagged Work" (or "Will be tagged Work and Trips", or a
    /// list), for the tags rules would add to a line with this name and
    /// category that it doesn't already carry; nil when none would.
    public static func text(rules: [TagRule], name: String, categoryId: Int?, alreadyTagged: [Int] = []) -> String? {
        var seen = Set<Int>(alreadyTagged)
        var names: [String] = []
        // Oldest rule first, as the server walks them.
        for rule in rules.sorted(by: { $0.id < $1.id }) where rule.applies(toName: name, categoryId: categoryId) {
            guard seen.insert(rule.tagId).inserted, let tag = rule.tagName, !tag.isEmpty else { continue }
            names.append(tag)
        }
        guard !names.isEmpty else { return nil }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "Will be tagged \(list)"
    }
}
