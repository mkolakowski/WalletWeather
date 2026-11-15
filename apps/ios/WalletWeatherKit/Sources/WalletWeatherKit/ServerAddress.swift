import Foundation

/// The server's address as typed on the Connect screen, checked.
///
/// HTTPS everywhere; plain `http://` only for an address on the home
/// network (decided 2026-11-14, `docs/dev/decisions/ios-app.md`), with a
/// warning. "Home network" means what iOS itself lets an app reach over
/// plain HTTP (App Transport Security's local networking): `localhost`, a
/// name with no dots, a `.local` name, and a private, loopback or link-local
/// IP address. A name like `nas.lan` isn't on that list, so it needs HTTPS.
public struct ServerAddress: Sendable, Equatable {
    /// The address with no path, query or trailing slash: `https://host[:port]`.
    public let url: URL
    /// True for a plain `http://` address (always a home-network one).
    public let isPlainHTTP: Bool

    public enum Problem: Error, Equatable, LocalizedError {
        case empty
        case notAnAddress
        case plainHTTPOutsideHome
        case unsupportedScheme

        public var errorDescription: String? {
            switch self {
            case .empty: "Type your WalletWeather server's address."
            case .notAnAddress: "That doesn't look like a web address. It should look like walletweather.example.com."
            case .plainHTTPOutsideHome: "Plain http:// only works for an address on your home network. Use https:// for this one."
            case .unsupportedScheme: "The address should start with https://."
            }
        }
    }

    /// Parses what was typed. No scheme means `https://`.
    public static func parse(_ typed: String) throws(Problem) -> ServerAddress {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty, !host.contains(" ") else { throw .notAnAddress }
        guard scheme == "https" || scheme == "http" else { throw .unsupportedScheme }
        if scheme == "http", !isHomeNetwork(host) { throw .plainHTTPOutsideHome }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        // A server isn't served under a sub-path (the web app lives at /), so
        // a pasted page address like …/#dashboard or …/settings is trimmed.
        parts.path = ""
        guard let url = parts.url else { throw .notAnAddress }
        return ServerAddress(url: url, isPlainHTTP: scheme == "http")
    }

    /// Whether `host` is on the home network, as App Transport Security
    /// counts it.
    public static func isHomeNetwork(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h.hasSuffix(".local") { return true }
        if let v4 = ipv4(h) {
            switch (v4[0], v4[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        if h.contains(":") {  // IPv6
            return h == "::1" || h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe80:")
        }
        // A name with no dots (a computer's name on the home network).
        return !h.contains(".") && !h.isEmpty
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
        return numbers.count == 4 ? numbers : nil
    }

    /// `server` + `path` (which starts with `/`), with a query.
    public func url(_ path: String, query: [String: String] = [:]) -> URL {
        Self.url(url, path, query: query)
    }

    static func url(_ base: URL, _ path: String, query: [String: String] = [:]) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        parts.path = path
        if !query.isEmpty {
            parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return parts.url!
    }
}
