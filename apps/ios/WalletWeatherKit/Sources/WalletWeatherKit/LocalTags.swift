import Foundation
import SwiftData

/// Tags in the household on this iPhone (Plans/phone-tags.md, phase 1,
/// #250): the server's tag routes and checks, the tags every row carries,
/// and setting a line's or a bill's tags.
extension LocalServer {
    static let tagNameMax = 60

    /// Every tag's row, by id, and the tags of each line and bill, read
    /// once for a request.
    struct TagIndex {
        var tags: [Int: [String: Any]] = [:]
        var lines: [Int: [[String: Any]]] = [:]
        var bills: [Int: [[String: Any]]] = [:]

        func line(_ id: Int) -> [[String: Any]] { lines[id] ?? [] }
        func bill(_ id: Int) -> [[String: Any]] { bills[id] ?? [] }
    }

    static func tagRow(_ tag: LocalTag) -> [String: Any] {
        ["id": tag.id, "name": tag.name, "color": tag.color as Any? ?? NSNull()]
    }

    func tagIndex(_ context: ModelContext) throws -> TagIndex {
        var index = TagIndex()
        for tag in try context.fetch(FetchDescriptor<LocalTag>()) { index.tags[tag.id] = Self.tagRow(tag) }
        for link in try context.fetch(FetchDescriptor<LocalTagLink>()) {
            guard let row = index.tags[link.tagID] else { continue }
            if let t = link.transactionID { index.lines[t, default: []].append(row) }
            if let r = link.recurringID { index.bills[r, default: []].append(row) }
        }
        return index
    }

    /// The tags in name order (as the server's `order_by(Tag.name)`).
    func tagList(_ context: ModelContext) throws -> [[String: Any]] {
        try context.fetch(FetchDescriptor<LocalTag>())
            .sorted { $0.name.unicodeScalars.lexicographicallyPrecedes($1.name.unicodeScalars) }
            .map(Self.tagRow)
    }

    /// The server's clean_color: a hex colour or none.
    static func cleanColor(_ value: Any?) throws -> String? {
        let text = ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.range(of: "^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$", options: .regularExpression) != nil else {
            throw Problem.invalid("A colour must be a hex colour, like #58a6ff")
        }
        return text
    }

    private func tagName(_ body: [String: Any]) throws -> String {
        let raw = body["name"] as? String ?? ""
        guard raw.count <= 200 else { throw Problem(status: 422, detail: "name is too long") }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Problem.invalid("Name is required") }
        guard name.count <= Self.tagNameMax else { throw Problem.invalid("Name must be <= \(Self.tagNameMax) characters") }
        return name
    }

    func tag(_ id: Int?, _ context: ModelContext) throws -> LocalTag {
        guard let id, let found = try context.fetch(FetchDescriptor<LocalTag>(predicate: #Predicate { $0.id == id })).first else {
            throw Problem.notFound("Tag not found")
        }
        return found
    }

    func createTag(_ body: [String: Any], _ context: ModelContext) throws -> Any {
        let name = try tagName(body)
        let color = try Self.cleanColor(body["color"])
        guard try context.fetch(FetchDescriptor<LocalTag>(predicate: #Predicate { $0.name == name })).isEmpty else {
            throw Problem(status: 409, detail: "A tag with that name already exists")
        }
        let tag = LocalTag(name: name, color: color)
        context.insert(tag)
        return Self.tagRow(tag)
    }

    func updateTag(_ id: Int?, _ body: [String: Any], _ context: ModelContext) throws -> Any {
        let found = try tag(id, context)
        let name = try tagName(body)
        let color = try Self.cleanColor(body["color"])
        let me = found.id
        guard try context.fetch(FetchDescriptor<LocalTag>(predicate: #Predicate { $0.name == name && $0.id != me })).isEmpty else {
            throw Problem(status: 409, detail: "A tag with that name already exists")
        }
        found.name = name
        found.color = color
        return ["ok": true, "id": found.id, "name": found.name, "color": found.color as Any? ?? NSNull()]
    }

    /// Deletes a tag with its links and its rules, as the server's cascade.
    func deleteTag(_ id: Int?, _ context: ModelContext) throws -> Any {
        let found = try tag(id, context)
        let me = found.id
        for link in try context.fetch(FetchDescriptor<LocalTagLink>(predicate: #Predicate { $0.tagID == me })) { context.delete(link) }
        for rule in try context.fetch(FetchDescriptor<LocalTagRule>(predicate: #Predicate { $0.tagID == me })) { context.delete(rule) }
        context.delete(found)
        return ["ok": true]
    }

    /// `tag_ids` from a body: nil when absent (leave the tags alone), each
    /// id checked as the server's `_own_tag`, each kept once.
    func tagIDs(_ body: [String: Any], _ context: ModelContext) throws -> [Int]? {
        guard let raw = body["tag_ids"], !(raw is NSNull) else { return nil }
        guard let list = raw as? [Any], list.count <= 200 else { throw Problem(status: 422, detail: "tag_ids must be a list") }
        var out: [Int] = []
        for item in list {
            guard let id = item as? Int else { throw Problem(status: 422, detail: "tag_ids must be whole numbers") }
            _ = try tag(id, context)
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// Replaces a line's tags.
    func setTags(_ ids: [Int], line: Int, _ context: ModelContext) throws {
        for link in try context.fetch(FetchDescriptor<LocalTagLink>(predicate: #Predicate { $0.transactionID == line })) { context.delete(link) }
        for id in ids { context.insert(LocalTagLink(tagID: id, transactionID: line)) }
    }

    /// Replaces a bill's tags.
    func setTags(_ ids: [Int], bill: Int, _ context: ModelContext) throws {
        for link in try context.fetch(FetchDescriptor<LocalTagLink>(predicate: #Predicate { $0.recurringID == bill })) { context.delete(link) }
        for id in ids { context.insert(LocalTagLink(tagID: id, recurringID: bill)) }
    }

    /// A bill's tag ids, for a line saved from it (#118).
    func billTagIDs(_ bill: Int, _ context: ModelContext) throws -> [Int] {
        try context.fetch(FetchDescriptor<LocalTagLink>(predicate: #Predicate { $0.recurringID == bill })).map(\.tagID)
    }

    /// Drops a deleted line's links.
    func dropLinks(line: Int, _ context: ModelContext) throws {
        for link in try context.fetch(FetchDescriptor<LocalTagLink>(predicate: #Predicate { $0.transactionID == line })) { context.delete(link) }
    }
}
