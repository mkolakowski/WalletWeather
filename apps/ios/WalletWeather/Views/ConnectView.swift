import SwiftUI
import WalletWeatherKit

/// Your own server, from the first screen (`WelcomeView`, #235): the
/// server's address, then Sign in (the sheet). Under
/// "Other ways": email and password, scanning the web app's QR code, its
/// "Open in WalletWeather" button and pasting a token (#100); under
/// "Advanced", a Cloudflare service token.
///
/// The same screen is Settings → Connections → Add a server, and Sign in
/// again, as a sheet (`AddServerSheet`, #300): `inSheet` leaves out the way
/// back to the first screen.
struct ConnectView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 40
    var inSheet = false
    @Environment(AppModel.self) private var model
    @State private var pastedToken = ""
    @State private var email = ""
    @State private var password = ""
    /// The two-factor code, asked for once the server says it's needed (#166).
    @State private var code = ""
    @FocusState private var codeFocused: Bool
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
                        .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                        .accessibilityLabel("Server address")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name for this iPhone", text: $model.phoneName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                            .accessibilityLabel("Name for this iPhone")
                        Text("Shown beside this iPhone's sign-in in the web app's Settings → API tokens.")
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
                    .prominentButton()
                    .disabled(model.busy)
                    Text("Opens your server's sign-in page: Cloudflare first if it's in front, then your email and password or Google.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let notice = model.connectNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                    }
                    problem(for: .sheet)
                }
                .card()

                DisclosureGroup(isExpanded: $showOtherWays) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Email and password").font(.subheadline.weight(.semibold))
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { signInWithPassword() }
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                        if model.needsTwoFactorCode {
                            TextField("Code", text: $code)
                                .textContentType(.oneTimeCode)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($codeFocused)
                                .submitLabel(.go)
                                .onSubmit { signInWithPassword() }
                                .padding(12)
                                .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                                .accessibilityLabel("Two-factor code")
                            Text("This account has two-factor sign-in on. Type the code from your authenticator app, or one of your recovery codes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Sign in with email and password", action: signInWithPassword)
                            .buttonStyle(.glass)
                            .controlSize(.large)
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
                        Text("In the web app on this iPhone, open **Settings → API tokens**, make a token and tap **Open in WalletWeather**.")
                            .font(.callout)
                        Divider()
                        Text("Or paste a token").font(.subheadline.weight(.semibold))
                        SecureField("ww_…", text: $pastedToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
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
                } label: {
                    // The whole row opens it, at least 44 points tall (#361).
                    Text("Other ways to sign in").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                }
                .card()

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A Cloudflare service token, if your server is behind Cloudflare Access and you'd rather not sign in to Cloudflare on this iPhone.")
                            .font(.callout)
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
                        SecureField("Client secret", text: $clientSecret)
                            .padding(12)
                            .background(Palette.row ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Radius.row))
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
        // In a sheet the "Connect to …?" question is asked here: the app's
        // own can't show over it.
        .modifier(ConnectLinkQuestion(active: inSheet))
        // Another account: the code field goes until the server asks again.
        .onChange(of: email) {
            model.needsTwoFactorCode = false
            code = ""
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

    @ViewBuilder private var header: some View {
        if inSheet {
            Text("Sign in to a WalletWeather server. The ones you're signed in to stay, and you can switch between them in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    model.connectError = nil
                    model.choseServer = false
                } label: {
                    Label("Other ways to use WalletWeather", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tapTarget()
                .disabled(model.busy)
                .padding(.bottom, 6)
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: symbolSize))
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text("WalletWeather").font(.largeTitle.bold())
                Text("Sign in to your own WalletWeather server.").foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
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
        let before = model.signIns
        Task {
            await model.signIn(email: email, password: password,
                               code: model.needsTwoFactorCode ? code : nil, serviceToken: serviceToken)
            if model.signIns != before {
                password = ""
                code = ""
            } else if model.needsTwoFactorCode {
                codeFocused = true
            }
        }
    }

    private func signIn() {
        lastWay = .sheet
        addressFocused = false
        Task { await model.signIn(serviceToken: serviceToken) }
    }
}

/// Settings → Connections → Add a server, and a page's Sign in again (#300):
/// the sign-in screen with all its ways, as a sheet with Cancel. It closes
/// once a sign-in goes through, with that connection in front. `server`
/// fills the address (Sign in again).
struct AddServerSheet: View {
    var server: URL?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectView(inSheet: true)
                .navigationTitle(server == nil ? "Add a server" : "Sign in again")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Not while a sign-in is on its way: it would put a
                        // connection in front after the sheet had gone.
                        Button("Cancel") { dismiss() }.disabled(model.busy)
                    }
                }
        }
        .interactiveDismissDisabled(model.busy)
        .onAppear {
            model.signInSheets += 1
            model.connectError = nil
            model.connectNotice = nil
            model.needsTwoFactorCode = false
            model.typedAddress = server?.absoluteString ?? ""
        }
        .onDisappear {
            model.signInSheets = max(model.signInSheets - 1, 0)
            model.connectError = nil
            model.needsTwoFactorCode = false
        }
        .onChange(of: model.signIns) { dismiss() }
    }
}

/// The "Connect to …?" question for a link from the web app's Settings
/// (its Open in WalletWeather button or QR code): asked by the app, or by
/// an Add a server sheet while one is open.
struct ConnectLinkQuestion: ViewModifier {
    let active: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(model.pendingLink.map { "Connect to \($0.host)?" } ?? "",  // ui-check: allow alert — a question: whether to sign in to the server a link names
                      isPresented: Binding(get: { active && model.pendingLink != nil },
                                           set: { if !$0 { model.pendingLink = nil } }),
                      presenting: model.pendingLink) { link in
            // Locked in the demo, it asks first (#301).
            Button("Connect") { Task { if await model.mayLeaveDemo() { await model.connect(link: link) } } }
            Button("Cancel", role: .cancel) { model.pendingLink = nil }
        } message: { link in
            Text(model.linkMessage(link))
        }
    }
}
