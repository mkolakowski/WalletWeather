import Foundation

/// A tag as the API sends it: on a line, a bill, or in `GET /api/tags`
/// (Plans/phone-tags.md, phase 2, #251).
public struct TagInfo: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let color: String?

    public init(id: Int, name: String, color: String?) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// The body of `POST /api/tags` and `PATCH /api/tags/{id}`.
struct TagBody: Encodable {
    let name: String
    let color: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(color ?? "", forKey: .color)
    }

    enum CodingKeys: String, CodingKey { case name, color }
}

extension APIClient {
    /// Your tags, in name order.
    public func tags() async throws(APIError) -> [TagInfo] {
        try await get("/api/tags")
    }

    @discardableResult
    public func createTag(name: String, color: String?) async throws(APIError) -> TagInfo {
        try await send("POST", "/api/tags", body: TagBody(name: name, color: color))
    }

    public func updateTag(_ id: Int, name: String, color: String?) async throws(APIError) {
        let _: EmptyAnswer = try await send("PATCH", "/api/tags/\(id)", body: TagBody(name: name, color: color))
    }

    /// Deletes a tag: it comes off every line and bill, and its rules go.
    public func deleteTag(_ id: Int) async throws(APIError) {
        let _: EmptyAnswer = try await send("DELETE", "/api/tags/\(id)", body: Optional<[String: String]>.none)
    }
}

/// The colours offered for a tag, as the web app's.
public enum TagColors {
    public static let all = ["#58a6ff", "#3fb950", "#d29922", "#a371f7", "#f778ba", "#56d4dd", "#ff7b72", "#8b949e"]

    /// What VoiceOver says for each colour, in the order of `all` (#360): a
    /// name, never the hex code.
    private static let names = ["Blue", "Green", "Amber", "Purple", "Pink", "Teal", "Red", "Grey"]

    /// The name of a colour in `all`; "Colour" for any other value.
    public static func name(of hex: String) -> String {
        guard let index = all.firstIndex(of: hex.lowercased()) else { return "Colour" }
        return names[index]
    }
}

/// An auto-tag rule (`GET /api/tag-rules`; phone-tags phase 3, #252): a
/// line whose description contains `descriptionPattern` (and is in
/// `categoryId`, when set) gets the tag.
public struct TagRule: Sendable, Codable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let descriptionPattern: String
    public let categoryId: Int?
    public let categoryName: String?
    public let tagId: Int
    public let tagName: String?
    public let tagColor: String?
    public let active: Bool
}

/// The body of `POST /api/tag-rules` and `PATCH /api/tag-rules/{id}`.
public struct TagRuleBody: Sendable, Encodable, Equatable {
    public var name: String
    public var descriptionPattern: String
    public var categoryId: Int?
    public var tagId: Int?
    public var active: Bool

    public init(name: String = "", descriptionPattern: String = "", categoryId: Int? = nil, tagId: Int? = nil, active: Bool = true) {
        self.name = name
        self.descriptionPattern = descriptionPattern
        self.categoryId = categoryId
        self.tagId = tagId
        self.active = active
    }

    public init(_ rule: TagRule) {
        self.init(name: rule.name ?? "", descriptionPattern: rule.descriptionPattern, categoryId: rule.categoryId,
                  tagId: rule.tagId, active: rule.active)
    }

    /// What's wrong before it can be saved, or nil.
    public var problem: String? {
        let pattern = descriptionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.count < 2 { return "Type at least 2 letters to look for." }
        if descriptionPattern.count > 120 { return "Up to 120 letters." }
        if name.count > 80 { return "A name can be up to 80 letters." }
        if tagId == nil { return "Choose the tag to add." }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case name, active
        case descriptionPattern = "description_pattern", categoryId = "category_id", tagId = "tag_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try c.encodeNil(forKey: .name) } else { try c.encode(trimmed, forKey: .name) }
        try c.encode(descriptionPattern, forKey: .descriptionPattern)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(tagId, forKey: .tagId)
        try c.encode(active, forKey: .active)
    }
}

/// What applying the rules to every line did.
public struct RuleBackfill: Sendable, Decodable, Equatable {
    public let transactionsScanned: Int
    public let tagsAdded: Int
}

extension APIClient {
    /// Your auto-tag rules, newest first.
    public func tagRules() async throws(APIError) -> [TagRule] {
        try await get("/api/tag-rules")
    }

    public func createTagRule(_ body: TagRuleBody) async throws(APIError) {
        let _: EmptyAnswer = try await send("POST", "/api/tag-rules", body: body)
    }

    public func updateTagRule(_ id: Int, _ body: TagRuleBody) async throws(APIError) {
        let _: EmptyAnswer = try await send("PATCH", "/api/tag-rules/\(id)", body: body)
    }

    public func deleteTagRule(_ id: Int) async throws(APIError) {
        let _: EmptyAnswer = try await send("DELETE", "/api/tag-rules/\(id)", body: Optional<[String: String]>.none)
    }

    /// Applies every rule to every line you can change; says how many tags it added.
    public func applyTagRules() async throws(APIError) -> RuleBackfill {
        try await send("POST", "/api/tag-rules/backfill", body: Optional<[String: String]>.none)
    }
}
