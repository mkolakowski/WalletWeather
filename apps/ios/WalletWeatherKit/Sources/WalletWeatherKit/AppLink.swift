import CryptoKit
import Foundation

/// The `walletweather://` addresses the app is sent to.
///
/// - `signed-in?code=…&state=…[&cf=…]`: the sign-in sheet's answer, from the
///   server's "sign in an app" page (`error=cancelled` when Cancel was tapped).
/// - `cloudflare?state=…&cf=…`: the sheet's answer from
///   `/app-sign-in/cloudflare`, the Cloudflare sign-in alone
///   (`error=no-cloudflare` when no Cloudflare is in front).
/// - `connect?server=…&token=…`: the "Open in WalletWeather" button beside a
///   new token in the web app's Settings. The app asks before using it.
public enum AppLink: Sendable, Equatable {
    case signedIn(code: String, state: String, cloudflare: String?)
    case cloudflare(state: String, token: String)
    case noCloudflare(state: String)
    case cancelled(state: String)
    case connect(server: String, token: String)

    public static let scheme = "walletweather"

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var q: [String: String] = [:]
        for item in parts.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let state = q["state"] ?? ""
        let cf = q["cf"].flatMap { $0.isEmpty ? nil : $0 }
        switch parts.host?.lowercased() {
        case "signed-in":
            if q["error"] != nil { self = .cancelled(state: state); return }
            guard let code = q["code"], !code.isEmpty, !state.isEmpty else { return nil }
            self = .signedIn(code: code, state: state, cloudflare: cf)
        case "cloudflare":
            if q["error"] == "no-cloudflare" { self = .noCloudflare(state: state); return }
            guard let cf, !state.isEmpty else { return nil }
            self = .cloudflare(state: state, token: cf)
        case "connect":
            guard let server = q["server"], !server.isEmpty,
                  let token = q["token"], !token.isEmpty else { return nil }
            self = .connect(server: server, token: token)
        default:
            return nil
        }
    }

    /// The `state` the app sent, to check the answer is to its own request.
    public var state: String? {
        switch self {
        case let .signedIn(_, state, _), let .cloudflare(state, _),
             let .noCloudflare(state), let .cancelled(state): state
        case .connect: nil
        }
    }
}

/// What the app sends when it opens the sign-in sheet, and keeps to finish:
/// a random `state` (the answer must carry it back) and a PKCE verifier,
/// whose SHA-256 goes to the server as the code challenge, so only this app
/// can swap the code the sheet hands back (RFC 7636, S256).
public struct SignInRequest: Sendable, Equatable {
    public let state: String
    public let codeVerifier: String

    public init(state: String = SignInRequest.random(16), codeVerifier: String = SignInRequest.random(48)) {
        self.state = state
        self.codeVerifier = codeVerifier
    }

    public var codeChallenge: String {
        Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64URLEncoded
    }

    /// The server's "sign in an app" page, set up for this request.
    public func signInURL(server: ServerAddress, deviceName: String, access: String = "full") -> URL {
        server.url("/app-sign-in", query: [
            "name": String(deviceName.prefix(80)), "access": access,
            "state": state, "code_challenge": codeChallenge,
        ])
    }

    /// The page that hands back only the Cloudflare sign-in.
    public func cloudflareURL(server: ServerAddress) -> URL {
        server.url("/app-sign-in/cloudflare", query: ["state": state])
    }

    /// `count` random bytes as base64url text.
    public static func random(_ count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
