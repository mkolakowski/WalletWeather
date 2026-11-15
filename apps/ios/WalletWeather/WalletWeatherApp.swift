import SwiftUI
import WalletWeatherKit

@main
struct WalletWeatherApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(model)
                .tint(Palette.accent)
                .onOpenURL { model.open($0) }
                .task { model.start() }
        }
    }
}

/// Connect, the Important notice, or the app, by where sign-in has got to.
struct AppRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .starting:
                PageBackground().ignoresSafeArea()
            case .connect:
                ConnectView()
            case .notice:
                NoticeView()
            case .ready:
                RootView()
            }
        }
        .animation(.default, value: model.phase)
        .alert(model.pendingLink.map { "Connect to \($0.host)?" } ?? "",
               isPresented: Binding(get: { model.pendingLink != nil }, set: { if !$0 { model.pendingLink = nil } }),
               presenting: model.pendingLink) { link in
            Button("Connect") { Task { await model.connect(link: link) } }
            Button("Cancel", role: .cancel) { model.pendingLink = nil }
        } message: { _ in
            Text(model.connection == nil
                 ? "Sign in with the token from the web app's Settings."
                 : "Sign in with the token from the web app's Settings. This replaces the server you're signed in to.")
        }
    }
}
