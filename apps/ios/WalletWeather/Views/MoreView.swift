import SwiftUI
import WalletWeatherKit

/// More: who's signed in to which server, the versions, the web app, and
/// Sign out. The other pages and the app's settings come in phase 5.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in") {
                    LabeledContent("Server", value: model.connection?.host ?? "")
                    if let me = model.me {
                        LabeledContent("Account", value: me.email)
                    }
                    if let cf = model.connection?.cloudflare {
                        LabeledContent("Cloudflare", value: cloudflareText(cf))
                    }
                }
                Section {
                    if let server = model.connection?.server {
                        Link("Open the web app", destination: server)
                    }
                } footer: {
                    Text("Accounts, categories, budgets, sharing, imports, reports and backups are set up in the web app.")
                }
                Section("Versions") {
                    LabeledContent("App", value: AppInfo.version)
                    LabeledContent("Server", value: model.serverVersion?.appVersion ?? "…")
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Signing out removes this phone's token and server from the phone. The token stays listed in the web app's Settings → API tokens until it runs out; revoke it there to end it now.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("More")
            .confirmationDialog("Sign out of WalletWeather on this phone?", isPresented: $confirmSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
            }
        }
    }

    private func cloudflareText(_ cf: CloudflareCredential) -> String {
        if cf.isServiceToken { return "Service token" }
        guard let expires = cf.expires else { return "Signed in" }
        return expires < .now ? "Sign-in ended" : "Signed in until \(expires.formatted(date: .omitted, time: .shortened))"
    }
}
