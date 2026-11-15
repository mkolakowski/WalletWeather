import SwiftUI
import WalletWeatherKit

@main
struct WalletWeatherApp: App {
    @State private var model = AppModel()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .id(settings.shownLook)  // every page reads its colours again
                .environment(model)
                .environment(settings)
                .tint(Palette.accent)
                .preferredColorScheme(settings.shownLook.colorScheme)
                // Match the web app follows the theme saved on the server.
                .onChange(of: model.me) { _, me in
                    if let me { settings.serverTheme = me.themePreference }
                }
                .onOpenURL { model.open($0) }
                .task { model.start() }
        }
    }
}

/// Connect, the Important notice, or the app, by where sign-in has got to;
/// the lock screen over it when locked, and a cover whenever the app isn't
/// in front, so the app switcher shows no numbers.
struct AppRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var offeringLock = false
    @State private var askingKeep = false

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
        .modifier(SepiaText())
        .overlay {
            if model.phase == .ready && settings.locked {
                LockView()
            } else if scenePhase != .active && model.phase != .connect {
                PrivacyCover()
            }
        }
        .onChange(of: scenePhase) { _, phase in settings.scenePhaseChanged(to: phase) }
        // After a sign-in: what this phone keeps (asked at each sign-in),
        // then the lock (offered once: at first sign-in, or after updating
        // for someone already signed in).
        .task(id: model.me?.id) {
            guard model.phase == .ready, model.me != nil else { return }
            if model.askKeep {
                askingKeep = true
            } else if settings.shouldOfferLock {
                offeringLock = true
            }
        }
        .alert("What should this phone keep?", isPresented: $askingKeep) {
            Button("Last-known numbers") { answerKeep(.lastKnown) }
            Button("Nothing", role: .cancel) { answerKeep(.nothing) }
        } message: {
            Text("With last-known numbers, WalletWeather still opens when your server can't be reached, showing the pages you last loaded and when they were loaded. They can't be read while the phone is locked, stay out of backups, and are deleted when you sign out. With nothing, the app needs a connection. You can change this in More.")
        }
        .alert("Lock WalletWeather with \(settings.biometryName ?? "Face ID")?", isPresented: $offeringLock) {
            Button("Lock with \(settings.biometryName ?? "Face ID")") { Task { await settings.setLock(true) } }
            Button("Not now", role: .cancel) { settings.lockOffered = true }
        } message: {
            Text("It asks when you open the app, and when you come back after a minute away. You can change this in More.")
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

extension AppRoot {
    /// Records the answer, then offers the lock once the question has gone.
    fileprivate func answerKeep(_ choice: KeepChoice) {
        model.setKeep(choice)
        guard settings.shouldOfferLock else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            offeringLock = true
        }
    }
}

/// The text colour of Sepia and the web themes; the system's text colours
/// in every other look.
private struct SepiaText: ViewModifier {
    func body(content: Content) -> some View {
        if let text = Palette.text { content.foregroundStyle(text) } else { content }
    }
}
