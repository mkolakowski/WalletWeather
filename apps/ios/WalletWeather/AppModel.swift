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
    /// The email and password sign-in found two-factor sign-in on: the
    /// Connect screen shows a code field until the sign-in is through (#166).
    var needsTwoFactorCode = false
    /// The server address typed last, kept in memory only.
    var typedAddress = ""
    var pendingLink: PendingLink?
    /// An account Search asked Forecast to show (#112); Forecast takes it
    /// and clears it.
    var forecastRequest: Int?

    private let sheet = SignInSheet()

    // MARK: - What the phone keeps (#101)

    /// Nothing (the default) or Last-known numbers. Asked once at each
    /// sign-in; signing out sets it back to Nothing (decided 2026-11-15).
    /// Someone already signed in when this arrived stays on Nothing and
    /// isn't asked.
    private(set) var keep: KeepChoice
    /// The set-up question is due: set by a fresh sign-in.
    var askKeep = false
    let kept: KeptResponses
    private let defaults: UserDefaults
    private static let keepKey = "keep.choice"

    init(defaults: UserDefaults = .standard, kept: KeptResponses = .standard) {
        self.defaults = defaults
        self.kept = kept
        keep = KeepChoice(rawValue: defaults.string(forKey: Self.keepKey) ?? "") ?? .nothing
        // Debug only: `WW_DEBUG_KEEP=lastKnown|nothing` sets the choice, for
        // checking kept numbers from the command line.
        if let debug = Self.debugSetting("WW_DEBUG_KEEP").flatMap(KeepChoice.init(rawValue:)) {
            keep = debug
            defaults.set(debug.rawValue, forKey: Self.keepKey)
        }
        // Nothing should be on the phone under Nothing; tidy up after a
        // crash between choosing Nothing and the files going.
        if keep == .nothing { kept.deleteAll() }
    }

    /// Choosing Nothing deletes what's kept straight away.
    func setKeep(_ choice: KeepChoice) {
        askKeep = false
        keep = choice
        defaults.set(choice.rawValue, forKey: Self.keepKey)
        if choice == .nothing { kept.deleteAll() }
    }

    /// The pages' client for edits and anything not kept. With Last-known
    /// numbers its read requests still keep what they load.
    var client: APIClient? { client(nil) }

    /// A page's client: with Last-known numbers it keeps what it loads, and
    /// answers from that copy when the server can't be reached, telling
    /// `tracker` how old it is.
    func client(_ tracker: KeptTracker?) -> APIClient? {
        guard let connection else { return nil }
        let observer: KeptObserver? = tracker.map { tracker in { @MainActor (date: Date?) in tracker.record(date) } }
        return APIClient(connection: connection, keeper: keep == .lastKnown ? kept : nil, observer: observer)
    }

    /// Whether this person may change lines on `account`: an account they
    /// own or may edit, under a token that isn't read-only. Until `/api/me`
    /// has said what the token may do, nothing is editable.
    func canEdit(_ account: Account) -> Bool {
        guard let me else { return false }
        return account.canEdit && !me.isReadOnly
    }

    /// A Debug-only launch setting, for screenshots from the command line
    /// (`SIMCTL_CHILD_<name>=…`): `WW_DEBUG_PLACE` (forecast, search, …),
    /// `WW_DEBUG_OPEN_LINE` (a Forecast line's or a bill's name, opened in
    /// the editor), `WW_DEBUG_SEARCH` (search text), and `WW_DEBUG_ACCOUNT`
    /// and `WW_DEBUG_DAY` (the Calendar's account and day), and
    /// `WW_DEBUG_KEEP` (what the phone keeps), `WW_DEBUG_LOOK` (the look),
    /// and `WW_DEBUG_CONFIRM`, `WW_DEBUG_COMPARE` and `WW_DEBUG_NEW_WINDOW`
    /// (Forecast's To confirm, Compare, and a second window on a page).
    /// Always nil in a
    /// Release build.
    static func debugSetting(_ name: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }

    /// The name this phone's token is given when signing in through the
    /// sheet, shown in the web app's Settings → API tokens (#155). iOS only
    /// tells apps "iPhone" for the name the person gave the phone, so it
    /// starts as the model ("iPhone 16 Pro Max") and can be changed on the
    /// Connect screen. Kept in memory only.
    var phoneName = DeviceModel.current

    var deviceName: String {
        let typed = phoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? DeviceModel.current : typed
    }

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
        // `WW_DEBUG_ADDRESS` opens on the Connect screen whatever the Keychain
        // holds (ConnectView's debug settings, #100).
        if env["WW_DEBUG_ADDRESS"] != nil {
            phase = .connect
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

    // MARK: - Signing in with an email and password (#100)

    /// An email and password, swapped for this phone's token. Behind
    /// Cloudflare Access the sheet signs in to Cloudflare first, unless a
    /// service token is given under Advanced.
    ///
    /// With two-factor sign-in on, the first try comes back asking for a
    /// code (`needsTwoFactorCode`); the next sends it with the same email
    /// and password.
    func signIn(email: String, password: String, code: String? = nil, serviceToken: CloudflareCredential?) async {
        connectError = nil
        connectNotice = nil
        let address: ServerAddress
        do { address = try ServerAddress.parse(typedAddress) } catch {
            connectError = error.localizedDescription
            return
        }
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            connectError = "Type the email and password you sign in to the web app with."
            return
        }
        busy = true
        defer { busy = false }
        var candidate = Connection(server: address.url, cloudflare: serviceToken)
        do {
            do {
                try await APIClient(connection: candidate).checkServer()
            } catch .cloudflareSignInNeeded {
                guard let cf = await signInToCloudflare(server: candidate.server) else { return }
                candidate.cloudflare = .session(token: cf)
                try await APIClient(connection: candidate).checkServer()
            }
            let issued = try await APIClient(connection: candidate)
                .signIn(email: email, password: password, deviceName: deviceName, code: code)
            candidate.token = issued.token
        } catch APIError.twoFactorCodeNeeded(let detail) {
            // The first answer only asks for the code; after that it's about
            // the code that was sent.
            if needsTwoFactorCode { connectError = detail }
            needsTwoFactorCode = true
            return
        } catch {
            connectError = Self.describe(error)
            return
        }
        needsTwoFactorCode = false
        await finishSignIn(candidate)
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
        // A new sign-in starts with nothing kept, and asks what to keep.
        kept.deleteAll()
        askKeep = true
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
        setKeep(.nothing)
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

    static func describe(_ error: any Error) -> String {
        if let error = error as? APIError { return describe(error) }
        return error.localizedDescription
    }
}
