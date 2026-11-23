import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import WalletWeatherKit

/// Moving between a server and this iPhone (Plans/standalone.md, phase 5,
/// #236): **Export for a server** saves the household as the server's own
/// sealed backup, which the web app's Settings → Restore takes; **Import a
/// server backup** replaces the household with one a server made, after
/// asking (decided 2026-11-18). The passphrase is chosen the first time and
/// kept in iCloud Keychain (open question 4).
struct MoveRows: View {
    @Environment(AppModel.self) private var model
    @State private var choosingPassphrase = false
    @State private var exportFile: BackupDocument?
    @State private var exporting = false
    @State private var working = false
    @State private var importing = false
    @State private var outcome: String?
    @State private var outcomeFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { startExport() } label: {
                row("Export for a server", symbol: "square.and.arrow.up")
            }
            .disabled(working)
            Divider()
            Button { importing = true } label: {
                row("Import a server backup", symbol: "square.and.arrow.down")
            }
            .disabled(working)
            if working {
                Divider()
                HStack(spacing: 8) { ProgressView(); Text("Working…").foregroundStyle(.secondary) }.frame(minHeight: 44)
            }
            if let outcome {
                Divider()
                Text(outcome).font(.footnote).foregroundStyle(outcomeFailed ? Palette.bad : .secondary).padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $choosingPassphrase) {
            ChoosePassphraseSheet { export() }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json,
                      defaultFilename: "walletweather-backup-\(LocalDay.today().description).json") { result in
            switch result {
            case .success:
                report("Saved. On your server, open the web app's Settings → Restore, pick the file and enter your backup passphrase.")
            case let .failure(error):
                report("Not saved: \(error.localizedDescription)", failed: true)
            }
        }
        .backupImporter(isPresented: $importing) { message, failed in report(message, failed: failed) }
    }

    private func row(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func report(_ message: String, failed: Bool = false) {
        outcome = message
        outcomeFailed = failed
    }

    private func startExport() {
        outcome = nil
        if BackupPassphrase.load() == nil { choosingPassphrase = true } else { export() }
    }

    /// Seals the household with the passphrase (scrypt takes a moment), then
    /// asks where to save it.
    private func export() {
        guard let passphrase = BackupPassphrase.load() else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try BackupFile.seal(try LocalServer.openShared().backupPayload(), passphrase: passphrase)
                }.value
                exportFile = BackupDocument(data: data)
                exporting = true
            } catch {
                report("The backup couldn't be made: \(AppModel.describe(error))", failed: true)
            }
        }
    }
}

/// Settings → iCloud & backup → Backup passphrase (#294; in Move to or
/// from a server before): whether one is chosen, opening it to show or
/// change after Face ID, Touch ID or the passcode.
struct PassphraseRow: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack {
                Text("Backup passphrase").foregroundStyle(Palette.accent)
                Spacer()
                Text(BackupPassphrase.load() == nil ? "Not chosen yet" : "In iCloud Keychain")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { PassphraseSheet() }
    }
}

/// The sealed backup, for the system's Save to Files.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - The passphrase

/// Choosing the backup passphrase, once (open question 4): typed twice, at
/// least 12 characters, with a plain warning that nobody can recover it.
struct ChoosePassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title = "Backup passphrase"
    /// Why it's asked, above the warning (the iCloud Drive backup's offer).
    var intro: String?
    var cancelTitle = "Cancel"
    var onCancel: () -> Void = {}
    let onChosen: () -> Void
    @State private var first = ""
    @State private var second = ""

    private var problem: String? {
        if let problem = BackupFile.passphraseProblem(first) { return problem }
        if first != second { return "The two passphrases don't match." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let intro { Section { Text(intro).font(.callout) } }
                Section {
                    SecureField("Passphrase", text: $first).textContentType(.newPassword)
                    SecureField("Again", text: $second).textContentType(.newPassword)
                } footer: {
                    if !first.isEmpty, let problem { Text(problem) }
                }
                Section {
                    Label("Nobody can recover this passphrase, not even WalletWeather's authors. Without it, your backups can't be opened.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warn)
                    Text("It's kept in your iCloud Keychain, so your other Apple devices know it. You'll type it on your server to open the backup there; Settings → iCloud & backup → Backup passphrase shows it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(cancelTitle) { dismiss(); onCancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard BackupPassphrase.save(first) else { return }
                        dismiss()
                        onChosen()
                    }
                    .disabled(problem != nil)
                }
            }
        }
    }
}

/// Settings → iCloud & backup → Backup passphrase: shown after Face ID, Touch ID or the
/// phone's passcode, so it can be typed on a server; or changed. Backups
/// already made keep the passphrase they were made with.
struct PassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shown: String?
    @State private var changing = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                if let saved = BackupPassphrase.load() {
                    Section {
                        if let shown {
                            Text(shown).font(.body.monospaced()).textSelection(.enabled)
                        } else {
                            Button("Show passphrase") { Task { await reveal(saved) } }
                        }
                        Button("Change passphrase") { changing = true }
                    } footer: {
                        Text(problem ?? "Backups you've already made keep the passphrase they were made with. Nobody can recover a passphrase that's lost.")
                    }
                } else {
                    Section {
                        Text("No passphrase yet. You choose one the first time you export for a server.")
                    }
                }
            }
            .navigationTitle("Backup passphrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $changing) { ChoosePassphraseSheet { shown = nil } }
        }
    }

    private func reveal(_ saved: String) async {
        let context = LAContext()
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show your backup passphrase") {
                shown = saved
            }
        } catch {
            problem = "The passphrase stays hidden until this iPhone knows it's you."
        }
    }
}

// MARK: - Importing

extension View {
    /// Import a server backup: pick the file, open it (with the passphrase
    /// in iCloud Keychain, or one typed), confirm replacing the household,
    /// then import. `report` says how it went.
    func backupImporter(isPresented: Binding<Bool>, report: @escaping (String, Bool) -> Void) -> some View {
        modifier(BackupImporter(isPresented: isPresented, report: report))
    }
}

/// A backup's JSON, handed to and from the work done off the main thread.
/// Only one side holds it at a time.
nonisolated private struct Payload: @unchecked Sendable {
    let value: [String: Any]
}

private struct BackupImporter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    let report: (String, Bool) -> Void

    @State private var file: Data?
    @State private var askingPassphrase = false
    @State private var typed = ""
    @State private var opened: [String: Any]?
    @State private var confirming = false
    @State private var working = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                switch result {
                case let .success(url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return report("That file couldn't be read.", true) }
                    file = data
                    typed = ""
                    open(passphrase: BackupPassphrase.load(), asked: false)
                case let .failure(error):
                    report(error.localizedDescription, true)
                }
            }
            .alert("This backup's passphrase", isPresented: $askingPassphrase) {
                SecureField("Passphrase", text: $typed)
                Button("Open") { open(passphrase: typed, asked: true) }
                Button("Cancel", role: .cancel) { file = nil }
            } message: {
                Text("The passphrase it was made with, on your server or another iPhone.")
            }
            .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button("Replace everything", role: .destructive) { importOpened() }
                Button("Cancel", role: .cancel) { opened = nil }
            } message: {
                Text("Every account, bill and line on this iPhone is replaced with the backup's \(accountList). This can't be undone.")
            }
    }

    private var accountNames: [String] {
        (opened?["accounts"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }

    private var accountList: String {
        let names = accountNames
        return names.isEmpty ? "(no accounts)" : names.count == 1 ? "account, \(names[0])" : "\(names.count) accounts: \(names.joined(separator: ", "))"
    }

    private var confirmTitle: String { "Replace what's on this iPhone?" }

    /// Opens the file: a sealed one with `passphrase` (scrypt takes a
    /// moment), asking for one when it's missing or wrong.
    private func open(passphrase: String?, asked: Bool) {
        guard let file else { return }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Payload, BackupFile.Problem> in
                do throws(BackupFile.Problem) {
                    return .success(Payload(value: try BackupFile.open(file, passphrase: passphrase).payload))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case let .success(payload):
                opened = payload.value
                confirming = true
            case .failure(.locked) where !asked:
                askingPassphrase = true
            case .failure(.wrongPassphrase):
                // The one in iCloud Keychain didn't open it, or the one typed.
                if asked { report(BackupFile.Problem.wrongPassphrase.message, true) }
                typed = ""
                askingPassphrase = true
            case let .failure(problem):
                self.file = nil
                report(problem.message, true)
            }
        }
    }

    private func importOpened() {
        guard let opened else { return }
        let payload = Payload(value: opened)
        self.opened = nil
        file = nil
        Task {
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try LocalServer.openShared().importBackup(payload.value)
                }.value
                model.reload()
                report("Imported \(summary.accounts) account\(summary.accounts == 1 ? "" : "s"), \(summary.recurring) bills and income, \(summary.transactions) lines and \(summary.transfers) transfer\(summary.transfers == 1 ? "" : "s"). Tags and bank links stay on the server.", false)
            } catch {
                report("Nothing was changed: \(AppModel.describe(error))", true)
            }
        }
    }
}
