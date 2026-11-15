import SwiftUI
import WalletWeatherKit

/// A page's data: loading, loaded, or why it couldn't be.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case let .loaded(v) = self { return v }
        return nil
    }
}

/// Why a page couldn't load, in plain words, with the way forward: Try
/// again, Sign in to Cloudflare, or Sign in again.
struct ProblemView: View {
    @Environment(AppModel.self) private var model
    let error: APIError
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: symbol)
        } description: {
            Text(error.message)
        } actions: {
            switch error {
            case .cloudflareSignInNeeded:
                Button("Sign in to Cloudflare") {
                    Task { if await model.renewCloudflare() { retry() } }
                }
                .buttonStyle(.glassProminent)
            case .tokenExpired, .tokenRevoked:
                Button("Sign in again") { model.signOut(keepAddress: true) }
                    .buttonStyle(.glassProminent)
            default:
                Button("Try again", action: retry)
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var symbol: String {
        switch error {
        case .offline: "wifi.slash"
        case .slowServer: "hourglass"
        case .cloudflareSignInNeeded, .tokenExpired, .tokenRevoked: "person.badge.key"
        case .serverTooOld: "arrow.up.circle"
        default: "exclamationmark.triangle"
        }
    }
}
