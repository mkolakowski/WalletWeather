import Foundation

/// Each saved server's profile picture, kept on the phone with that
/// connection (Plans/account-picker.md, phase 3, #379), for the account
/// picker and its menu: `Application Support/Pictures/<id>.picture`, with
/// what the server said about it (when it last changed, its ETag) beside it
/// in `<id>.json`. Deleted with the connection (`ConnectionStore.remove`).
/// Never in the phone's backup: the server has the picture.
///
/// Only the connection in front fetches its picture, and only when `/api/me`
/// says it changed (`PictureRefresh`): nothing is requested from a server
/// that isn't in front.
public final class ProfilePictureStore: @unchecked Sendable {
    /// One kept picture.
    public struct Kept: Equatable, Sendable {
        public let data: Data
        /// `picture_updated_at` from `/api/me` when it was fetched.
        public let updatedAt: String
        /// The server's ETag for it, sent back as `If-None-Match`.
        public let etag: String?
    }

    private struct About: Codable {
        let updatedAt: String
        let etag: String?
    }

    public let root: URL

    public init(root: URL = ProfilePictureStore.standardRoot) {
        self.root = root
    }

    /// `Application Support/Pictures`, inside the app's container.
    public static var standardRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Pictures", directoryHint: .isDirectory)
    }

    private func file(_ id: UUID, _ ext: String) -> URL {
        root.appending(path: "\(id.uuidString.lowercased()).\(ext)")
    }

    public func load(_ id: UUID) -> Kept? {
        guard let data = try? Data(contentsOf: file(id, "picture")),
              let aboutData = try? Data(contentsOf: file(id, "json")),
              let about = try? JSONDecoder().decode(About.self, from: aboutData) else { return nil }
        return Kept(data: data, updatedAt: about.updatedAt, etag: about.etag)
    }

    /// Keeps a picture, replacing the one kept before.
    @discardableResult
    public func save(_ id: UUID, data: Data, updatedAt: String, etag: String?) -> Bool {
        do {
            var folder = root
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            try data.write(to: file(id, "picture"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try JSONEncoder().encode(About(updatedAt: updatedAt, etag: etag))
                .write(to: file(id, "json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            delete(id)
            return false
        }
    }

    /// The server said the kept picture is still current under a new date
    /// (`304 Not Modified`): only the date changes.
    @discardableResult
    public func touch(_ id: UUID, updatedAt: String) -> Bool {
        guard let kept = load(id) else { return false }
        return save(id, data: kept.data, updatedAt: updatedAt, etag: kept.etag)
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id, "picture"))
        try? FileManager.default.removeItem(at: file(id, "json"))
    }
}

/// What to do about the picture of the connection in front, once `/api/me`
/// has answered with its `picture_updated_at` (#379).
public enum PictureRefresh: Equatable, Sendable {
    /// The kept picture is current, or there's none either side.
    case nothing
    /// The server has none any more: delete the kept one.
    case delete
    /// Fetch it, sending the kept one's ETag when there is one.
    case fetch(etag: String?)

    public static func decide(kept: ProfilePictureStore.Kept?, updatedAt: String?) -> PictureRefresh {
        guard let updatedAt else { return kept == nil ? .nothing : .delete }
        if let kept, kept.updatedAt == updatedAt { return .nothing }
        return .fetch(etag: kept?.etag)
    }
}

/// `GET /api/me/picture` (server 1.99.0, #377).
public enum PictureAnswer: Equatable, Sendable {
    case picture(Data, etag: String?)
    /// `304`: the picture sent as `If-None-Match` is still the one.
    case unchanged
    /// `404`: there is none.
    case none
}
