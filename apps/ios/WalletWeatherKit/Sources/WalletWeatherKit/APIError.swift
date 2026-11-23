import Foundation

/// Why a request didn't work, in words for the person holding the phone.
/// Each kind gets its own plain message and a way forward (plan, phase 1:
/// no connection, a slow server, an expired token and an expired Cloudflare
/// session each get their own message with a retry).
public enum APIError: Error, Sendable, Equatable {
    /// The phone has no connection.
    case offline
    /// The server didn't answer in time.
    case slowServer
    /// Nothing answered at that address.
    case cannotReach(String)
    /// The HTTPS connection couldn't be trusted (a bad certificate).
    case insecure
    /// Cloudflare Access wants a sign-in (none yet, or it ran out).
    case cloudflareSignInNeeded
    /// The token has run out (tokens from the sign-in sheet last 90 days).
    case tokenExpired
    /// The token was revoked in Settings, or isn't known.
    case tokenRevoked
    /// Signing in with an email and password was refused: the email or
    /// password is wrong, or the account signs in only with Google.
    case wrongPassword
    /// The email and password were right, and the account has two-factor
    /// sign-in on: a code is needed, or the one sent was wrong. Carries the
    /// server's sentence (#166).
    case twoFactorCodeNeeded(String)
    /// The server is older than this app needs.
    case serverTooOld(found: String, needed: String)
    /// Something answered, but not a WalletWeather server.
    case notWalletWeather
    /// The server said no, with its reason.
    case server(status: Int, detail: String)
    /// The server's answer wasn't what the app expected.
    case unexpectedResponse(String)
    /// A change tried in the demo, which saves nothing (#92).
    case demoReadOnly

    public var title: String {
        switch self {
        case .offline: "You're offline"
        case .slowServer: "The server is slow to answer"
        case .cannotReach: "Can't reach the server"
        case .insecure: "The connection isn't secure"
        case .cloudflareSignInNeeded: "Sign in to Cloudflare"
        case .tokenExpired: "Your sign-in has ended"
        case .tokenRevoked: "You've been signed out"
        case .wrongPassword: "That didn't sign in"
        case .twoFactorCodeNeeded: "A code is needed"
        case .serverTooOld: "Your server needs an update"
        case .notWalletWeather: "That isn't a WalletWeather server"
        case .server: "The server said no"
        case .unexpectedResponse: "Something went wrong"
        case .demoReadOnly: "This is the demo"
        }
    }

    public var message: String {
        switch self {
        case .offline:
            "This page isn't kept on this iPhone, so it'll show once you're connected again."
        case .slowServer:
            "WalletWeather didn't answer in time. It may be busy or starting up."
        case let .cannotReach(host):
            "Nothing answered at \(host). Check the address, and that the server is running."
        case .insecure:
            "The server's certificate couldn't be checked, so the app won't send anything to it."
        case .cloudflareSignInNeeded:
            "Your server is behind Cloudflare Access, and your Cloudflare sign-in has ended. Sign in again to carry on."
        case .tokenExpired:
            "This iPhone's sign-in has run out. Sign in again to carry on."
        case .tokenRevoked:
            "This iPhone's token was revoked in Settings, or no longer works. Sign in again to carry on."
        case .wrongPassword:
            "The email or password isn't right. If you sign in with Google, use the Sign in button above instead."
        case let .serverTooOld(found, needed):
            "This app needs WalletWeather \(needed) or later, and your server runs \(found). Update the server, then try again."
        case .notWalletWeather:
            "Something answered at that address, but it isn't WalletWeather. Check the address."
        case let .server(_, detail), let .twoFactorCodeNeeded(detail):
            detail.hasSuffix(".") ? detail : detail + "."
        case .unexpectedResponse:
            "The server's answer wasn't what this app expected. Check that the server is up to date, then try again."
        case .demoReadOnly:
            "The demo doesn't save changes. Connect your server to edit."
        }
    }

    /// The server couldn't be reached at all, so a kept copy may stand in.
    public var serverUnreachable: Bool {
        switch self {
        case .offline, .slowServer, .cannotReach: true
        default: false
        }
    }

    /// Whether the way forward is signing in again rather than retrying.
    public var needsSignIn: Bool {
        switch self {
        case .tokenExpired, .tokenRevoked: true
        default: false
        }
    }

    static func from(_ error: URLError, host: String) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive:
            .offline
        case .timedOut:
            .slowServer
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .secureConnectionFailed, .clientCertificateRejected:
            .insecure
        default:
            .cannotReach(host)
        }
    }
}
