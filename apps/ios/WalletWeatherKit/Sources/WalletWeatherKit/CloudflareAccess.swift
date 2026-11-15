import Foundation

/// Getting past Cloudflare Access, when the server sits behind it.
///
/// Two ways in (decided 2026-11-14, `docs/dev/decisions/ios-app.md`):
/// - **The person's own Cloudflare sign-in**, made in the sign-in sheet. The
///   sheet keeps its cookies to itself, so the server hands the Access token
///   it was sent (`Cf-Access-Jwt-Assertion`) back to the app in the sheet's
///   answer, and the app sends it as `cf-access-token`. It lasts as long as
///   the Access application's session (24 hours unless changed).
/// - **A service token** (Client ID and Secret, made in the Zero Trust
///   dashboard), sent as `CF-Access-Client-Id` / `-Secret`.
///
/// Telling Access's sign-in page from the server's own answer follows the
/// `CloudflareAccess` gateway in mkplus (`Apple/Shared/Services/Gateway/
/// AccessGateway.swift`), where it's been tried on a real iPhone.
public enum CloudflareCredential: Sendable, Codable, Equatable {
    case session(token: String)
    case serviceToken(clientID: String, secret: String)

    var headers: [String: String] {
        switch self {
        case let .session(token): ["cf-access-token": token]
        case let .serviceToken(id, secret): ["CF-Access-Client-Id": id, "CF-Access-Client-Secret": secret]
        }
    }

    /// When a Cloudflare sign-in runs out (from the token's `exp`), or nil
    /// for a service token or a token that doesn't say.
    public var expires: Date? {
        guard case let .session(token) = self,
              let exp = CloudflareAccess.claims(ofJWT: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    public var isServiceToken: Bool {
        if case .serviceToken = self { return true }
        return false
    }
}

public enum CloudflareAccess {
    static let teamDomainSuffix = ".cloudflareaccess.com"
    static let loginPathPrefix = "/cdn-cgi/access/"

    /// Whether this answer is Cloudflare Access asking for a sign-in (or
    /// refusing one), rather than the server answering. Redirects aren't
    /// followed, so a request without a sign-in comes back as a redirect to
    /// the team's login page.
    public static func isChallenge(_ response: HTTPURLResponse, body: Data?) -> Bool {
        if (300..<400).contains(response.statusCode),
           let location = response.value(forHTTPHeaderField: "Location"),
           let target = URL(string: location, relativeTo: response.url) {
            let host = target.host()?.lowercased() ?? ""
            if host.hasSuffix(teamDomainSuffix) { return true }
            if target.path.hasPrefix(loginPathPrefix + "login") { return true }
        }
        if let landed = response.url?.host()?.lowercased(), landed.hasSuffix(teamDomainSuffix) {
            return true
        }
        // Turned away by Access itself: a sign-in it doesn't take.
        if [401, 403].contains(response.statusCode),
           response.value(forHTTPHeaderField: "Server")?.lowercased() == "cloudflare",
           let body, let text = String(data: body.prefix(64_000), encoding: .utf8)?.lowercased(),
           text.contains("cloudflare access") || text.contains("cloudflareaccess.com") || text.contains(loginPathPrefix) {
            return true
        }
        return false
    }

    /// A JWT's claims (its middle part), unverified: only to read when it
    /// runs out.
    public static func claims(ofJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
