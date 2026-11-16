import SwiftUI
import WalletWeatherKit

/// The first screen: the server's address, then Sign in. Under "Other ways",
/// the web app's "Open in WalletWeather" button and pasting a token; under
/// "Advanced", a Cloudflare service token.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var pastedToken = ""
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
                    if let error = model.connectError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Palette.bad)
                            .accessibilityLabel("Problem: \(error)")
                    }
                }
                .card()

                DisclosureGroup("Other ways to sign in", isExpanded: $showOtherWays) {
                    VStack(alignment: .leading, spacing: 12) {
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
                            Task { await model.connect(token: pastedToken, serviceToken: serviceToken) }
                        }
                        .buttonStyle(.glass)
                        .disabled(model.busy)
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

    private func signIn() {
        addressFocused = false
        Task { await model.signIn(serviceToken: serviceToken) }
    }
}
