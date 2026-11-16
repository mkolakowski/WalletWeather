import SwiftUI
import WalletWeatherKit

/// The first screen: the server's address, then Sign in (the sheet). Under
/// "Other ways": email and password, scanning the web app's QR code, its
/// "Open in WalletWeather" button and pasting a token (#100); under
/// "Advanced", a Cloudflare service token.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var pastedToken = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showScanner = false
    /// The way last tried, so its problem shows beside its own button.
    @State private var lastWay: Way = .sheet
    private enum Way { case sheet, password, scan, token }
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var showOtherWays = false
    @State private var showAdvanced = false
    @FocusState private var addressFocused: Bool

    private var serviceToken: CloudflareCredential? {
        let id = clientID.trimmingCharacters(in: .whitespaces)
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        return id.isEmpty || secret.isEmpty ? nil : .serviceToken(clientID: id, secret: secret)
    }

    /// The typed address, when it's a plain http:// one at home.
    private var homeHTTP: Bool {
        (try? ServerAddress.parse(model.typedAddress))?.isPlainHTTP ?? false
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your server").font(.headline)
                    TextField("walletweather.example.com", text: $model.typedAddress)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($addressFocused)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                        .padding(12)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Server address")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name for this phone", text: $model.phoneName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Name for this phone")
                        Text("Shown beside this phone's sign-in in the web app's Settings → API tokens.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if homeHTTP {
                        Label("This address uses plain http://, so anyone on your home network could read what the app sends. Use https:// if your server has it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.warn)
                    }
                    Button(action: signIn) {
                        HStack {
                            if model.busy { ProgressView() }
                            Text("Sign in").frame(maxWidth: .infinity)
                        }
                        .font(.headline)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.busy)
                    Text("Opens your server's sign-in page: Cloudflare first if it's in front, then your email and password or Google.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let notice = model.connectNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                    }
                    problem(for: .sheet)
                }
                .card()

                DisclosureGroup("Other ways to sign in", isExpanded: $showOtherWays) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Email and password").font(.subheadline.weight(.semibold))
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { signInWithPassword() }
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        Button("Sign in with email and password", action: signInWithPassword)
                            .buttonStyle(.glass)
                            .disabled(model.busy)
                        if lastWay == .password, model.connectError != nil {
                            problem(for: .password)
                        } else {
                            Text("For accounts with a password. If you sign in with Google, use Sign in above.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("Scan a QR code").font(.subheadline.weight(.semibold))
                        Text("In the web app on a computer, open **Settings → API tokens**, make a token and choose **Show QR code**.")
                            .font(.callout)
                        Button {
                            lastWay = .scan
                            showScanner = true
                        } label: {
                            Label("Scan a QR code", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(.glass)
                        .disabled(model.busy)
                        problem(for: .scan)
                        Divider()
                        Text("In the web app on this phone, open **Settings → API tokens**, make a token and tap **Open in WalletWeather**.")
                            .font(.callout)
                        Divider()
                        Text("Or paste a token").font(.subheadline.weight(.semibold))
                        SecureField("ww_…", text: $pastedToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("API token")
                        Button("Connect with this token") {
                            lastWay = .token
                            Task { await model.connect(token: pastedToken, serviceToken: serviceToken) }
                        }
                        .buttonStyle(.glass)
                        .disabled(model.busy)
                        problem(for: .token)
                    }
                    .padding(.top, 10)
                }
                .card()

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A Cloudflare service token, if your server is behind Cloudflare Access and you'd rather not sign in to Cloudflare on this phone.")
                            .font(.callout)
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Client Secret", text: $clientSecret)
                            .padding(12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 10)
                }
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PageBackground().ignoresSafeArea())
        .sheet(isPresented: $showScanner) {
            QRScanSheet { url in model.open(url) }
        }
        .task { debugStart() }
    }

    /// Debug builds only, for simulator checks (#100): `WW_DEBUG_ADDRESS`
    /// fills the address, `WW_DEBUG_OTHER_WAYS` opens Other ways,
    /// `WW_DEBUG_SCAN` opens the scanner, and `WW_DEBUG_EMAIL` with
    /// `WW_DEBUG_PASSWORD` fills the form and signs in with it.
    private func debugStart() {
        if let address = AppModel.debugSetting("WW_DEBUG_ADDRESS") { model.typedAddress = address }
        if AppModel.debugSetting("WW_DEBUG_OTHER_WAYS") != nil { showOtherWays = true }
        if AppModel.debugSetting("WW_DEBUG_SCAN") != nil { showScanner = true }
        if let typedEmail = AppModel.debugSetting("WW_DEBUG_EMAIL"),
           let typedPassword = AppModel.debugSetting("WW_DEBUG_PASSWORD") {
            showOtherWays = true
            email = typedEmail
            password = typedPassword
            signInWithPassword()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)
            Text("WalletWeather").font(.largeTitle.bold())
            Text("Sign in to your own WalletWeather server.").foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    @ViewBuilder private func problem(for way: Way) -> some View {
        if lastWay == way, let error = model.connectError {
            Text(error)
                .font(.callout)
                .foregroundStyle(Palette.bad)
                .accessibilityLabel("Problem: \(error)")
        }
    }

    private func signInWithPassword() {
        lastWay = .password
        Task {
            await model.signIn(email: email, password: password, serviceToken: serviceToken)
            if model.phase != .connect { password = "" }
        }
    }

    private func signIn() {
        lastWay = .sheet
        addressFocused = false
        Task { await model.signIn(serviceToken: serviceToken) }
    }
}
