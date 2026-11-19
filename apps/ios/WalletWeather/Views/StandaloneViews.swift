import SwiftUI
import WalletWeatherKit

/// The first screen (Plans/standalone.md, phase 4, #235; open question 7,
/// decided 2026-11-18): how to use the app, On this iPhone or Your own
/// server, each with what it gives and what it costs, and Try the demo,
/// smaller, under both. Your own server goes on to the sign-in screen.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                    Text("WalletWeather").font(.largeTitle.bold())
                    Text("How would you like to use it?").foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                WayCard(way: Standalone.onThisPhone, symbol: "iphone",
                        button: LocalStore.exists ? "Open on this iPhone" : "Use on this iPhone",
                        prominent: true) { model.useOnThisPhone() }
                if let problem = model.connectError, !model.choseServer {
                    Text(problem).font(.callout).foregroundStyle(Palette.bad)
                }
                WayCard(way: Standalone.ownServer, symbol: "server.rack", button: "Connect to my server",
                        prominent: false) {
                    model.connectError = nil
                    model.choseServer = true
                }

                VStack(spacing: 6) {
                    Button(action: model.tryDemo) {
                        Label("Try the demo", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    Text("Sample numbers built into the app. Nothing you change is saved.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(PageBackground().ignoresSafeArea())
    }
}

/// One way to use the app: its name, a line on it, what it gives and what
/// it costs, and its button.
private struct WayCard: View {
    let way: Standalone.Way
    let symbol: String
    let button: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(way.title, systemImage: symbol).font(.title3.weight(.semibold))
            Text(way.summary).font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(way.pros, id: \.self) { point($0, good: true) }
                ForEach(way.cons, id: \.self) { point($0, good: false) }
            }
            .padding(.vertical, 2)
            Group {
                if prominent {
                    Button(action: action) { Text(button).frame(maxWidth: .infinity).padding(.vertical, 4) }
                        .buttonStyle(.glassProminent)
                } else {
                    Button(action: action) { Text(button).frame(maxWidth: .infinity).padding(.vertical, 4) }
                        .buttonStyle(.glass)
                }
            }
            .font(.headline)
        }
        .card()
    }

    private func point(_ text: String, good: Bool) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: good ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(good ? Palette.good : .secondary)
        }
        .accessibilityLabel((good ? "Yes: " : "No: ") + text)
    }
}

// MARK: - Needs a server

/// What standalone can't do stays in place, greyed and marked "Needs a
/// server", and opens this note (open question 2, decided 2026-11-18).
struct NeedsServerNote: View {
    let what: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("\(what) needs a server", systemImage: "server.rack").font(.title3.weight(.semibold))
                    Text("Your numbers are on this iPhone, so \(what) isn't available here.")
                    Text(Standalone.serverAdds)
                    Link(destination: Standalone.setupGuide) {
                        Label("How to set up a server", systemImage: "arrow.up.right.square")
                    }
                    .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .padding(16)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Needs a server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A page that needs a server, opened on this iPhone's household: the note
/// in its place.
struct NeedsServerPage: View {
    let page: TabPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Needs a server", systemImage: "server.rack").font(.headline).foregroundStyle(.secondary)
                Text("Your numbers are on this iPhone, so \(page.title) isn't available here.")
                Text(Standalone.serverAdds).foregroundStyle(.secondary)
                Link(destination: Standalone.setupGuide) {
                    Label("How to set up a server", systemImage: "arrow.up.right.square")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(16)
        }
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle(page.title)
    }
}

/// Shows `content`, or the note when the household is on this iPhone and
/// the page needs a server.
struct ServerOnly<Content: View>: View {
    @Environment(AppModel.self) private var model
    let page: TabPage
    @ViewBuilder let content: () -> Content

    var body: some View {
        if model.isLocal && page.needsServer { NeedsServerPage(page: page) } else { content() }
    }
}

/// A greyed card for something that needs a server, opening the note.
struct NeedsServerCard: View {
    let what: String
    let symbol: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 8) {
                Label(what, systemImage: symbol)
                Spacer(minLength: 8)
                Text("Needs a server").font(.footnote)
                Image(systemName: "info.circle")
            }
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
        .sheet(isPresented: $showing) { NeedsServerNote(what: what) }
    }
}

// MARK: - New account

/// Adds an account to this iPhone's household (#235): the web app's
/// fields, a name, a starting balance and the date it starts from.
struct NewAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onAdded: () async -> Void

    @State private var draft = AccountDraft(today: .today())
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, such as Checking", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                    LabeledContent("Starting balance") {
                        TextField("0.00", text: $draft.balanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    DatePicker("Starting on", selection: Binding(get: { draft.startingDate.date },
                                                                set: { draft.startingDate = LocalDay.today(now: $0) }),
                               displayedComponents: .date)
                } footer: {
                    if let problem = problem ?? (draft.name.isEmpty && draft.balanceText.isEmpty ? nil : draft.problem) {
                        Text(problem).foregroundStyle(Palette.bad)
                    } else {
                        Text("The balance on the starting date. For money owed, such as a credit card, start it with a minus: -300.")
                    }
                }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }.disabled(draft.body == nil || saving)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func add() async {
        guard let body = draft.body, let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            try await client.createAccount(body)
            await onAdded()
            dismiss()
        } catch {
            problem = AppModel.describe(error)
        }
    }
}
