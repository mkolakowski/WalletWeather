import SwiftUI
import WalletWeatherKit

// Two rules for problems (#311, finding R16):
// - what the person typed is answered under its field, in `Palette.bad`
//   footnote text (a section's footer);
// - what the server, the household on this iPhone or the demo refused is
//   one banner at the top of the form or sheet (`problemBanner`), with the
//   way forward where there is one.
// A change made from a list with no form open (a swipe, Undo) keeps an
// alert (`problemAlert`), worded the same way.

/// What a form's last attempt was refused with, and how to make that
/// attempt again (the banner's Try again).
struct FormProblem: Identifiable {
    let id = UUID()
    let error: APIError
    let retry: () -> Void

    init(_ error: any Error, retry: @escaping () -> Void) {
        self.error = APIError(error)
        self.retry = retry
    }

    /// Debug only: `WW_DEBUG_FAIL_SAVE` makes every editor and sheet open
    /// already showing the banner, and every save fail, with that problem,
    /// for pictures with no taps. `1` or `offline`, `slow`, `cloudflare`,
    /// `signin`, `server` (a refusal with the server's reason) or `demo`.
    static var debugFailure: APIError? {
        switch AppModel.debugSetting("WW_DEBUG_FAIL_SAVE") {
        case "1", "offline": .offline
        case "slow": .slowServer
        case "cloudflare": .cloudflareSignInNeeded
        case "signin": .tokenExpired
        case "server": .server(status: 409, detail: "This was changed somewhere else. Close it and open it again")
        case "demo": .demoReadOnly
        default: nil
        }
    }

    /// Called at the start of an attempt: throws the debug failure, if set.
    static func failIfAsked() throws {
        if let debugFailure { throw debugFailure }
    }
}

/// The banner at the top of a form: a warning symbol, what was refused and
/// why, and the way forward as a button where there is one.
struct ProblemBanner: View {
    @Environment(AppModel.self) private var model
    let error: APIError
    var retry: (() -> Void)?
    @State private var signingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title).font(.subheadline.weight(.semibold))
                    Text(error.message).font(.footnote).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.bad)
            }
            .accessibilityElement(children: .combine)
            if let way = error.wayForward, let retry {
                WayForwardButton(way: way, signingIn: $signingIn, retry: retry)
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.bar))
        .sheet(isPresented: $signingIn) { AddServerSheet(server: model.connection?.server) }
    }
}

/// Try again, Sign in to Cloudflare or Sign in again: the same buttons on a
/// page that couldn't load (`ProblemView`) and in a form's banner.
struct WayForwardButton: View {
    @Environment(AppModel.self) private var model
    let way: APIError.WayForward
    @Binding var signingIn: Bool
    let retry: () -> Void

    var body: some View {
        switch way {
        case .signInToCloudflare:
            Button("Sign in to Cloudflare") {
                Task { if await model.renewCloudflare() { retry() } }
            }
        case .signInAgain:
            Button("Sign in again") { signingIn = true }
        case .tryAgain:
            Button("Try again", action: retry)
        }
    }
}

extension View {
    /// The banner at the top of a form or sheet while its last attempt was
    /// refused. It stays until the next attempt (which clears `problem`) or
    /// the sheet closes, and VoiceOver reads it out when it appears. In a
    /// pane of the open Duo, `edges` keeps it clear of the fold.
    func problemBanner(_ problem: Binding<FormProblem?>, edges: FoldPanes.Edges = .plain) -> some View {
        modifier(ProblemBannerModifier(problem: problem, edges: edges))
    }

    /// The alert for a change made from a list, with no form open to hold a
    /// banner: the problem's own title and message.
    func problemAlert(_ problem: Binding<ListProblem?>) -> some View {
        alert(problem.wrappedValue?.title ?? "", isPresented: Binding(
            get: { problem.wrappedValue != nil }, set: { if !$0 { problem.wrappedValue = nil } }),
              presenting: problem.wrappedValue) { _ in
            Button("OK", role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }
}

private struct ProblemBannerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var problem: FormProblem?
    let edges: FoldPanes.Edges

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let problem {
                    ProblemBanner(error: problem.error, retry: problem.retry)
                        .padding(.leading, edges.leading).padding(.trailing, edges.trailing)
                        .padding(.top, 8).padding(.bottom, 6)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: problem?.id)
            .onChange(of: problem?.id) {
                guard let problem else { return }
                AccessibilityNotification.Announcement("\(problem.error.title). \(problem.error.message)").post()
            }
            .onAppear {
                // Debug pictures: the banner as if a save had just failed;
                // its button only clears it, as a new attempt would.
                if problem == nil, let failure = FormProblem.debugFailure {
                    problem = FormProblem(failure) { problem = nil }
                }
            }
    }
}

/// What a change made from a list couldn't do, for `problemAlert`.
struct ListProblem: Equatable {
    let title: String
    let message: String

    init(_ error: any Error) {
        let error = APIError(error)
        title = error.title
        message = error.message
    }

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// The line the list showed was gone by the time it was acted on.
    static func gone(_ message: String) -> ListProblem {
        ListProblem(title: "It isn't there any more", message: message)
    }
}
