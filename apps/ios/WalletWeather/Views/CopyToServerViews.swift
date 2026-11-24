import SwiftUI
import WalletWeatherKit

/// Settings → Move to a server → Copy to a server… (#328): the household on
/// this iPhone copied to a saved server, inside the app. Pick a server
/// signed in with full access, see what goes, choose Add to what's there or
/// Replace what's there (neither to start with), then Copy. The server's own
/// import does the work (`ServerCopy`, under that server's token); the
/// connection in front stays, and this iPhone keeps its copy.
///
/// Debug only: `WW_DEBUG_COPY=sample` opens it with the first server
/// chosen, and `replace` with Replace chosen and its confirmation showing.
/// Neither checks the sign-in or sends anything.
struct CopyToServerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Check: Equatable {
        case none
        case checking
        /// Signed in with full access, as this email (when known).
        case ready(String?)
        case refused
    }

    @State private var chosen: UUID?
    @State private var check: Check = .none
    @State private var contents: CopyContents?
    @State private var contentsFailed = false
    @State private var mode: CopyMode?
    @State private var confirmingReplace = false
    @State private var copying = false
    @State private var result: String?
    @State private var problem: APIError?
    @State private var retry: (() -> Void)?
    @State private var debugOpened = false

    private var debug: String? { AppModel.debugSetting("WW_DEBUG_COPY") }
    private var destinations: [CopyDestination] { CopyDestination.list(model.connections) }
    private var chosenSaved: SavedConnection? { model.connections.first { $0.id == chosen } }
    private var chosenName: String { chosenSaved?.name ?? "the server" }

    private var canCopy: Bool {
        guard !copying, result == nil, mode != nil, let contents, !contents.isEmpty,
              case .ready = check, chosenSaved?.needsSignIn == false else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good)
                    } footer: {
                        Text("This iPhone keeps its copy. To see them on \(chosenName), choose it in Settings → Connection.")
                    }
                } else {
                    whereTo
                    whatGoes
                    onTheServer
                    if copying {
                        Section {
                            HStack(spacing: 8) { ProgressView(); Text("Copying to \(chosenName)…").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Copy to a server")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let problem {
                    ProblemBanner(error: problem, retry: retry)
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
                }
            }
            .toolbar {
                if result != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(copying) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Copy") { startCopy() }.disabled(!canCopy)
                    }
                }
            }
            .confirmationDialog("Replace what's on \(chosenName)?", isPresented: $confirmingReplace, titleVisibility: .visible) {
                Button("Replace and copy", role: .destructive) { copy() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every account, category and tag on \(chosenName) is deleted first, with their bills and lines, then this iPhone's numbers are copied there. This can't be undone on the server. This iPhone keeps its copy.")
            }
        }
        .interactiveDismissDisabled(copying)
        .task { await loadContents() }
        .onAppear { openForDebug() }
        .onChange(of: model.connections) {
            // A sign-in that ended while checking: it can't be picked now.
            if chosenSaved?.needsSignIn == true { check = .refused }
        }
    }

    // MARK: Sections

    private var whereTo: some View {
        Section {
            ForEach(destinations) { destination in
                Button { pick(destination) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name).foregroundStyle(destination.pickable ? Color.primary : Color.secondary)
                            if let detail = destination.detail {
                                if destination.pickable {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                                } else {
                                    Label(detail, systemImage: ConnectionRow.warningSymbol)
                                        .font(.footnote).foregroundStyle(Palette.warn)
                                }
                            }
                        }
                        Spacer()
                        if chosen == destination.id {
                            Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!destination.pickable || copying)
                .accessibilityAddTraits(chosen == destination.id ? .isSelected : [])
            }
        } header: {
            Text("Copy to")
        } footer: {
            Text(checkNote)
        }
    }

    private var checkNote: String {
        switch check {
        case .none: "A server you're signed in to with full access. One whose sign-in has ended needs Sign in again first, in Settings → Connection."
        case .checking: "Checking your sign-in on \(chosenName)…"
        case let .ready(email): email.map { "Signed in as \($0), with full access." } ?? "Signed in with full access."
        case .refused: "Nothing can be copied to \(chosenName) for now. Choose another server, or sort out the sign-in in Settings → Connection."
        }
    }

    private var whatGoes: some View {
        Section {
            if let contents {
                Text(contents.isEmpty ? "Nothing yet: add an account first." : contents.summary)
            } else if contentsFailed {
                Text("Your numbers couldn't be read.").foregroundStyle(Palette.bad)
            } else {
                ProgressView()
            }
        } header: {
            Text("What goes")
        } footer: {
            Text("Categories, tags and tag rules go too. This iPhone keeps its copy: nothing here is deleted, and its bank connection stays on this iPhone.")
        }
    }

    private var onTheServer: some View {
        Section {
            ForEach(CopyMode.allCases) { option in
                Button { mode = option } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).foregroundStyle(option == .replace ? Palette.bad : Color.primary)
                            Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mode == option { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(copying)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        } header: {
            Text("On the server")
        } footer: {
            Text("Choose one. Nothing is sent until you tap Copy.")
        }
    }

    // MARK: Doing

    private func loadContents() async {
        let counted = await Task.detached(priority: .userInitiated) { () -> CopyContents? in
            try? CopyPayload(household: LocalServer.openShared()).contents
        }.value
        contents = counted
        contentsFailed = counted == nil
    }

    /// Chooses a server and checks its token: a read-only one is refused
    /// here, before anything is asked.
    private func pick(_ destination: CopyDestination) {
        guard destination.pickable, let saved = model.connections.first(where: { $0.id == destination.id }) else { return }
        chosen = destination.id
        problem = nil
        if debug != nil {
            check = .ready(saved.account)
            return
        }
        check = .checking
        Task {
            do {
                let me = try await ServerCopy(to: saved, signInEnded: ended(saved)).check()
                if chosen == destination.id { check = .ready(me.email) }
            } catch {
                guard chosen == destination.id else { return }
                check = .refused
                show(error) { pick(destination) }
            }
        }
    }

    private func startCopy() {
        guard canCopy else { return }
        if mode == .replace { confirmingReplace = true } else { copy() }
    }

    private func copy() {
        guard let saved = chosenSaved, let mode else { return }
        problem = nil
        if debug != nil {
            // Debug pictures never send anything.
            result = "Debug: nothing was sent to \(saved.name)."
            return
        }
        copying = true
        Task {
            defer { copying = false }
            do {
                let copy = try ServerCopy(to: saved, signInEnded: ended(saved))
                let payload = try await Task.detached(priority: .userInitiated) {
                    try CopyPayload(household: LocalServer.openShared())
                }.value
                let answer = try await copy.copy(payload, mode: mode)
                result = answer.summary(to: saved.name)
            } catch {
                show(error) { startCopy() }
            }
        }
    }

    /// The banner (#311). Only Try again is offered here: signing in again
    /// (to the server or to Cloudflare) would put that server in front, so
    /// it's done from Settings → Connection.
    private func show(_ error: any Error, retry again: @escaping () -> Void) {
        let shown = (error as? CopyRefusal)?.problem ?? APIError(error)
        problem = shown
        retry = shown.wayForward == .tryAgain ? again : nil
    }

    /// Marks the chosen server when it answers that its sign-in has ended
    /// (#302), as the pages' requests do.
    private func ended(_ saved: SavedConnection) -> SignInEndedObserver {
        let id = saved.id, token = saved.connection.token
        return { [model] in model.markSignInEnded(id, token: token) }
    }

    private func openForDebug() {
        guard !debugOpened, let debug else { return }
        debugOpened = true
        if let first = destinations.first(where: \.pickable) { pick(first) }
        if debug == "replace" {
            mode = .replace
            confirmingReplace = true
        }
    }
}
