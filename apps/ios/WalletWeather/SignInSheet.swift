import AuthenticationServices
import UIKit
import WalletWeatherKit

/// The system's sign-in sheet (`ASWebAuthenticationSession`), sharing
/// Safari's sign-ins, so passkeys, password managers, Google and Cloudflare
/// Access work as they do in Safari (a web view inside the app has none of
/// that, and Google refuses to sign in there). What the sheet signs in to
/// stays in the sheet: it comes back to the app only as a `walletweather://`
/// address. Adapted from mkplus's `SystemSignInSheet`.
@MainActor
final class SignInSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Opens `url` and waits for the `walletweather://` answer; nil when the
    /// sheet was closed by hand or the answer wasn't one the app knows.
    func open(_ url: URL) async -> AppLink? {
        session?.cancel()
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(AppLink.scheme)) { callback, _ in
                continuation.resume(returning: callback.flatMap(AppLink.init))
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(returning: nil)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            return ASPresentationAnchor(windowScene: scenes.first!)
        }
    }
}
