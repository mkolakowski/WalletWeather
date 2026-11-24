import Foundation

/// What an address handed to the app is (#326): a `walletweather://` link,
/// a CSV opened from Files, Mail or a share sheet's Open in…, or something
/// the app has nothing to do with.
public enum OpenedURL: Sendable, Equatable {
    case link(AppLink)
    case csv
    case other

    /// File extensions of a bank's CSV export.
    static let csvExtensions: Set<String> = ["csv"]

    public init(_ url: URL) {
        if let link = AppLink(url) {
            self = .link(link)
        } else if url.isFileURL, Self.csvExtensions.contains(url.pathExtension.lowercased()) {
            self = .csv
        } else {
            self = .other
        }
    }

    /// The name the import sheet shows for an opened file.
    public static func fileName(_ url: URL) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? CSVDrop.fileName(nil) : name
    }
}

/// Whether an opened CSV can go to the import sheet (#326).
public enum OpenedCSV: Sendable, Equatable {
    /// The import sheet opens on the file (once the app has finished
    /// starting and is unlocked).
    case importIt
    /// Not signed in: Import a CSV needs a connection.
    case needsConnection
    /// The connection's token is read-only: nothing can be imported.
    case readOnly

    /// `signedIn` is false on the Connect screen; `readOnly` is the token's
    /// access once known. While the app is still starting it's the file
    /// that waits, not this answer, so pass `signedIn: true`.
    public static func decide(signedIn: Bool, readOnly: Bool) -> OpenedCSV {
        if !signedIn { return .needsConnection }
        return readOnly ? .readOnly : .importIt
    }

    /// The alert's text for a refusal.
    public var refusal: (title: String, message: String)? {
        switch self {
        case .importIt:
            nil
        case .needsConnection:
            ("Connect first", "Import a CSV needs a connection. Connect to your server, or use WalletWeather on this iPhone, then open the file again.")
        case .readOnly:
            ("Can't import here", "This connection is read-only, so a CSV can't be imported into it. Use a connection that can make changes.")
        }
    }
}
