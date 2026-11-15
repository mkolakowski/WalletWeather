import Observation
import SwiftUI
import UIKit
import WalletWeatherKit

/// Where sign-in has got to, and the connection the pages use.
///
/// Three ways in (Plans/ios-app.md, phase 1):
/// - **Sign in:** the server's "sign in an app" page in the system's sign-in
///   sheet, which shares Safari's sign-ins, so Cloudflare Access, Google and
///   passkeys work there. The sheet comes back with a one-time code (and the
///   Cloudflare sign-in, when Cloudflare is in front), swapped for a token.
/// - **The "Open in WalletWeather" button** beside a new token in the web
///   app's Settings, which opens `walletweather://connect`.
/// - **Pasting a token.**
/// A Cloudflare service token, under Advanced, can stand in for signing in
/// to Cloudflare.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case starting, connect, notice, ready }

    struct PendingLink: Equatable {
        let address: ServerAddress
        let token: String
        var host: String { address.url.host() ?? address.url.absoluteString }
    }

    private(set) var phase: Phase = .starting
    private(set) var connection: Connection?
    private(set) var me: Me?
    private(set) var serverVersion: ServerVersion?
    /// Bumped when the connection changes (a new Cloudflare sign-in), so
    /// pages load again.
    private(set) var generation = 0

    /// What the Connect screen shows while it works, or why it stopped.
    var busy = false
    var connectError: String?
    /// Something the Connect screen should say that isn't a problem (why a
    /// token may still be listed after signing out).
    var connectNotice: String?
    /// The server address typed last, kept in memory only.
    var typedAddress = ""
    var pendingLink: PendingLink?

    private let sheet = SignInSheet()

    var client: APIClient? { connection.map { APIClient(connection: $0) } }

    /// The phone's name for its token ("iPhone" unless iOS shares more).
    var deviceName: String { UIDevice.current.name }

    // MARK: - Starting

    func start() {
        guard phase == .starting else { return }
        #if DEBUG
        // Screenshots and checks from the command line, in Debug builds only:
        // `SIMCTL_CHILD_WW_DEBUG_SERVER=… SIMCTL_CHILD_WW_DEBUG_TOKEN=… xcrun
        // simctl launch …` opens signed in, keeping nothing in the Keychain.
        let env = ProcessInfo.processInfo.environment
        if let server = env["WW_DEBUG_SERVER"].flatMap(URL.init(string:)), let token = env["WW_DEBUG_TOKEN"] {
            connection = Connection(server: server, token: token)
            phase = .ready
            Task { await refreshMe() }
            return
        }
        #endif
        guard let saved = Keychain.loadConnection() else {
            phase = .connect
            return
        }
        connection = saved
        phase = .ready
        Task { await refreshMe() }
    }

    /// Who's signed in; shows the Important notice until it's agreed to.
    func refreshMe() async {
        guard let client else { return }
        if let found = try? await client.me() {
            me = found
            if found.noticeRequired { phase = .notice }
        }
        serverVersion = try? await client.version()
    }

    // MARK: - Signing in through the sheet

    func signIn(serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        busy = true
        defer { busy = false }

        // Is this WalletWeather, and new enough? Behind Cloudflare that can
        // only be asked once signed in to it, which the sheet does.
        var checked = false
        do {
            try await APIClient(connection: Connection(server: address.url, cloudflare: serviceToken)).checkServer()
            checked = true
        } catch .cloudflareSignInNeeded {
            // The sheet signs in to Cloudflare first.
        } catch {
            connectError = Self.describe(error)
            return
        }

        let request = SignInRequest()
        guard let answer = await sheet.open(request.signInURL(server: address, deviceName: deviceName)) else {
            return  // closed by hand
        }
        guard answer.state == request.state else {
            connectError = "The sign-in didn't come back as expected. Try again."
            return
        }
        switch answer {
        case let .signedIn(code, _, cf):
            let cloudflare = cf.map { CloudflareCredential.session(token: $0) } ?? serviceToken
            var candidate = Connection(server: address.url, cloudflare: cloudflare)
            do {
                let issued = try await APIClient(connection: candidate).swapSignInCode(code, verifier: request.codeVerifier)
                candidate.token = issued.token
                if !checked { try await APIClient(connection: candidate).checkServer() }
            } catch {
                connectError = Self.describe(error)
                return
            }
            await finishSignIn(candidate)
        case .cancelled:
            return
        default:
            connectError = "The sign-in didn't come back as expected. Try again."
        }
    }

    // MARK: - Signing in with a token

    /// A pasted token.
    func connect(token: String, serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            connectError = "Paste the token you made in the web app's Settings."
            return
        }
        await connect(Connection(server: address.url, token: token, cloudflare: serviceToken))
    }

    /// The "Open in WalletWeather" button, once confirmed.
    func connect(link: PendingLink) async {
        pendingLink = nil
        typedAddress = link.address.url.absoluteString
        if phase != .connect {
            // The old server's token is ended first, as Sign out does.
            await signOutEndingToken()
            typedAddress = link.address.url.absoluteString
        }
        connectNotice = nil
        await connect(Connection(server: link.address.url, token: link.token))
    }

    private func connect(_ candidate: Connection) async {
        busy = true
        defer { busy = false }
        var candidate = candidate
        do {
            do {
                try await APIClient(connection: candidate).checkServer()
            } catch .cloudflareSignInNeeded {
                guard let cf = await signInToCloudflare(server: candidate.server) else { return }
                candidate.cloudflare = .session(token: cf)
                try await APIClient(connection: candidate).checkServer()
            }
            _ = try await APIClient(connection: candidate).me()
        } catch {
            connectError = Self.describe(error)
            return
        }
        await finishSignIn(candidate)
    }

    private func finishSignIn(_ signedIn: Connection) async {
        Keychain.saveConnection(signedIn)
        connection = signedIn
        me = nil
        generation += 1
        phase = .ready
        await refreshMe()
    }

    // MARK: - Cloudflare

    /// Signs in to Cloudflare again when the app's Cloudflare sign-in has
    /// run out, keeping the WalletWeather token. Returns whether it worked.
    @discardableResult
    func renewCloudflare() async -> Bool {
        guard var current = connection, let cf = await signInToCloudflare(server: current.server) else { return false }
        current.cloudflare = .session(token: cf)
        Keychain.saveConnection(current)
        connection = current
        generation += 1
        return true
    }

    /// The sheet at `/app-sign-in/cloudflare`: the person's Cloudflare
    /// sign-in, handed back by the server.
    private func signInToCloudflare(server: URL) async -> String? {
        guard let address = try? ServerAddress.parse(server.absoluteString) else { return nil }
        let request = SignInRequest()
        guard let answer = await sheet.open(request.cloudflareURL(server: address)),
              answer.state == request.state else { return nil }
        switch answer {
        case let .cloudflare(_, token):
            return token
        case .noCloudflare:
            connectError = "Cloudflare turned the app away, but the server didn't see a Cloudflare sign-in. If you use a Cloudflare service token, enter it under Advanced."
            return nil
        default:
            return nil
        }
    }

    // MARK: - The notice, links and signing out

    func acknowledgeNotice() async throws(APIError) {
        guard let client else { return }
        try await client.acknowledgeNotice()
        phase = .ready
        await refreshMe()
    }

    func open(_ url: URL) {
        // The sheet's own answers go to the sheet; only connect links land here.
        guard case let .connect(server, token) = AppLink(url),
              let address = try? ServerAddress.parse(server) else { return }
        pendingLink = PendingLink(address: address, token: token)
    }

    /// Sign out: ends this phone's token on the server (#145), then removes
    /// everything from the phone. If the server can't be reached it still
    /// signs out, and the Connect screen says the token is still listed.
    func signOutEndingToken() async {
        if let client, connection?.token != nil {
            busy = true
            do {
                try await client.endToken()
            } catch .tokenExpired, .tokenRevoked {
                // Already ended.
            } catch {
                signOut()
                connectNotice = "Signed out on this phone. The server couldn't be reached, so this phone's token is still listed in the web app's Settings → API tokens until you revoke it there."
                busy = false
                return
            }
            busy = false
        }
        signOut()
    }

    /// Removes the token and everything else from the phone, without asking
    /// the server (for a token that has already ended).
    func signOut(keepAddress: Bool = false) {
        if keepAddress, let server = connection?.server { typedAddress = server.absoluteString }
        if !keepAddress { typedAddress = "" }
        Keychain.deleteConnection()
        connection = nil
        me = nil
        serverVersion = nil
        connectError = nil
        generation += 1
        phase = .connect
    }

    static func describe(_ error: APIError) -> String {
        error.title + ". " + error.message
    }
}
