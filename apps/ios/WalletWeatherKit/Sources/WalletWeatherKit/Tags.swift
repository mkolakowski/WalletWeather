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
}
