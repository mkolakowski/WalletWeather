import SwiftUI
import WalletWeatherKit

/// Registers for CloudKit's silent pushes, which bring another device's
/// changes in, also while the app is in the background (#238).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}

@main
struct WalletWeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var settings = AppSettings()

    var body: some Scene {
        // Each window opens on a page of its own: nil for the first, the page
        // asked for by "Open in new window" (#90).
        WindowGroup(for: RootView.Place.self) { $start in
            AppRoot(start: start)
                // Every page reads its colours and its dates again.
                .id("\(settings.shownLook.rawValue)/\(settings.dateStyle.rawValue)")
                .environment(model)
                .environment(settings)
                .tint(Palette.accent)
                .preferredColorScheme(settings.shownLook.colorScheme)
                // Match the web app follows the theme saved on the server.
                .onChange(of: model.me) { _, me in
                    if let me {
                        settings.serverTheme = me.themePreference
                        // Follow the web app's date format, with a server only (#296).
                        settings.serverDateFormat = model.settingsHousehold == .server ? me.dateFormat : nil
                    }
                }
                .onChange(of: model.settingsHousehold) { _, household in
                    if household != .server { settings.serverDateFormat = nil }
                }
                // The theme kept with the connection now in front (#299), until
                // its server answers.
                .onChange(of: model.saved?.id) { _, _ in
                    if let theme = model.saved?.webTheme { settings.serverTheme = theme }
                }
                .onOpenURL { model.open($0) }
                .task { model.start() }
        }
        // Bank sync on this iPhone (#239), when iOS gives it background time.
        .backgroundTask(.appRefresh(PhoneBank.taskID)) { await model.backgroundBankSync() }
    }
}

/// Connect, the Important notice, or the app, by where sign-in has got to;
/// the lock screen over it when locked, and a cover whenever the app isn't
/// in front, so the app switcher shows no numbers.
struct AppRoot: View {
    var start: RootView.Place?
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
                if model.choseServer { ConnectView() } else { WelcomeView() }
            case .notice:
                NoticeView()
            case .ready:
                // Stacked above the app, not inset over it: an inset leaves the
                // navigation bar where it was, and the bar covered the page title (#261).
                VStack(spacing: 0) {
                    if model.isDemo { DemoBar().padding(.horizontal, 16).padding(.bottom, 6) }
                    RootView(start: start)
                }
                .background { if model.isDemo { PageBackground().ignoresSafeArea() } }
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
        .onChange(of: scenePhase) { _, phase in
            settings.scenePhaseChanged(to: phase)
            // The iCloud Drive backup runs when the app opens or leaves (#237).
            if model.isLocal, model.phase == .ready, phase != .inactive { Task { await model.backup.runIfDue() } }
            // Bank sync when the app opens, at most once every 23½ hours (#239).
            if phase == .active { Task { await model.syncBankIfDue() } }
        }
        .sheet(isPresented: $model.offeringBackup) { BackupOfferSheet() }
        .sheet(item: Binding(get: { model.phase == .ready ? model.debugCSV : nil }, set: { model.debugCSV = $0 })) {
            CSVImportSheet(file: $0, startAccount: nil) { model.reload() }
        }
        // After a sign-in: what this phone keeps (asked at each sign-in),
        // then the lock (offered once: at first sign-in, or after updating
        // for someone already signed in).
        .task(id: model.me?.id) {
            guard model.phase == .ready, model.me != nil, !model.isDemo else { return }
            if model.askKeep {
                askingKeep = true
            } else if settings.shouldOfferLock {
                offeringLock = true
            }
        }
        .alert("What should this iPhone keep?", isPresented: $askingKeep) {
            Button("Last-known numbers") { answerKeep(.lastKnown) }
            Button("Nothing", role: .cancel) { answerKeep(.nothing) }
        } message: {
            Text("With last-known numbers, WalletWeather still opens when your server can't be reached, showing the pages you last loaded and when they were loaded. They can't be read while this iPhone is locked, stay out of backups, and are deleted when you sign out. With nothing, the app needs a connection. You can change this in Settings.")
        }
        .alert("Lock WalletWeather with \(settings.biometryName ?? "Face ID")?", isPresented: $offeringLock) {
            Button("Lock with \(settings.biometryName ?? "Face ID")") { Task { await settings.setLock(true) } }
            Button("Not now", role: .cancel) { settings.lockOffered = true }
        } message: {
            Text("It asks when you open the app, and when you come back after a minute away. You can change this in Settings.")
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
