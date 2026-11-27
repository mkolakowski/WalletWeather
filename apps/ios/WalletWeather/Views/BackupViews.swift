import SwiftUI
import WalletWeatherKit

/// Settings → iCloud & backup → Back up to iCloud Drive (Plans/standalone.md,
/// phase 6, #237): the switch, when it last ran, Back up now, and Restore.
struct CloudBackupRows: View {
    @Environment(AppModel.self) private var model
    @State private var choosingPassphrase = false
    @State private var restoring = false

    var body: some View {
        let backup = model.backup
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(get: { backup.on == true }, set: { turn($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Back up to iCloud Drive")
                    Text(status(backup)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            if backup.on == true {
                Divider()
                Button { Task { await backup.backUpNow() } } label: {
                    Label("Back up now", systemImage: "icloud.and.arrow.up")
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(backup.working)
            }
            Divider()
            Button { restoring = true } label: {
                Label("Restore from a backup…", systemImage: "icloud.and.arrow.down")
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            if backup.working {
                Divider()
                HStack(spacing: 8) { ProgressView(); Text("Backing up…").foregroundStyle(.secondary) }.frame(minHeight: 44)
            }
            if let message = backup.message {
                Divider()
                Text(message).font(.footnote).foregroundStyle(backup.failed ? Palette.bad : .secondary).padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .onAppear { backup.refresh() }
        .sheet(isPresented: $choosingPassphrase) {
            ChoosePassphraseSheet(intro: "WalletWeather seals each backup with this passphrase before it goes to iCloud Drive.") {
                backup.setOn(true)
            }
        }
        .sheet(isPresented: $restoring) {
            RestoreFromICloudSheet { model.reload() }
        }
    }

    private func turn(_ on: Bool) {
        if on, BackupPassphrase.load() == nil { choosingPassphrase = true } else { model.backup.setOn(on) }
    }

    private func status(_ backup: CloudBackupModel) -> String {
        guard backup.on == true else { return backup.on == false ? "Off" : "Not set up yet" }
        guard let last = backup.lastDay else { return "On, no backup yet" }
        return "On, last backup \(last.short)"
    }
}

/// After the first account (decided 2026-11-20: backup is on from the first
/// account): asks for the backup passphrase, once, and turns the backup on.
/// "Not now" leaves it off; Settings turns it on later.
struct BackupOfferSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ChoosePassphraseSheet(title: "Back up to iCloud Drive",
                              intro: "Your numbers live only on this iPhone, so WalletWeather backs them up to your iCloud Drive: at most once a day, when something changed, keeping the last 14. Choose a passphrase to seal them with.",
                              cancelTitle: "Not now",
                              onCancel: { model.backup.setOn(false) }) {
            model.backup.setOn(true)
        }
    }
}

/// Restore from the iCloud Drive backups (Plans/standalone.md, phase 6,
/// #237): the first screen's choice on a new phone, and Settings'. Lists the
/// backups newest first, asks before replacing what's on the phone, opens
/// the file with the passphrase in iCloud Keychain (or one typed), imports
/// it and turns the backup on.
struct RestoreFromICloudSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called after a restore: the screens load again.
    let onRestored: () -> Void

    private enum Loaded { case loading, found([CloudBackup.Entry]), problem(String) }
    @State private var loaded: Loaded = .loading
    @State private var chosen: CloudBackup.Entry?
    @State private var confirming = false
    @State private var working = false
    @State private var file: Data?
    @State private var asking = false
    @State private var typed = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                switch loaded {
                case .loading:
                    Section { HStack(spacing: 8) { ProgressView(); Text("Looking in iCloud Drive…").foregroundStyle(.secondary) } }
                case let .problem(text):
                    Section {
                        Text(text).foregroundStyle(Palette.bad)
                        Button("Try again") { Task { await load() } }
                    }
                case let .found(entries) where entries.isEmpty:
                    Section {
                        Text("No backups yet. WalletWeather's backups appear here once iCloud Drive has them, which can take a few minutes on a new iPhone.")
                        Button("Look again") { Task { await load() } }
                    }
                case let .found(entries):
                    Section {
                        ForEach(entries) { entry in
                            Button { chosen = entry; confirming = true } label: {
                                HStack {
                                    Text(entry.day.written(width: .wide, withYear: true))
                                    Spacer()
                                    if !entry.downloaded { Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(working)
                        }
                    } header: {
                        Text("Choose a backup")
                    } footer: {
                        Text("Restoring replaces every account, bill and line on this iPhone with the backup's.")
                    }
                }
                if working { Section { HStack(spacing: 8) { ProgressView(); Text("Restoring…").foregroundStyle(.secondary) } } }
                if let problem { Section { Text(problem).foregroundStyle(Palette.bad) } }
            }
            .navigationTitle("Restore from iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
            .confirmationDialog("Replace what's on this iPhone?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Restore this backup", role: .destructive) { Task { await restore(passphrase: BackupPassphrase.load()) } }
                Button("Cancel", role: .cancel) { chosen = nil }
            } message: {
                Text("Every account, bill and line on this iPhone is replaced with the backup's. This can't be undone.")
            }
            .alert("This backup's passphrase", isPresented: $asking) {  // ui-check: allow alert — a question: only the person has the passphrase
                SecureField("Passphrase", text: $typed)
                Button("Open") { Task { await restore(passphrase: typed, typed: true) } }
                Button("Cancel", role: .cancel) { file = nil }
            } message: {
                Text("The passphrase it was made with. iCloud Keychain didn't have it, or it didn't open this backup.")
            }
        }
    }

    private func load() async {
        loaded = .loading
        do { loaded = .found(try await CloudBackupModel.backups()) } catch { loaded = .problem(AppModel.describe(error)) }
    }

    private func restore(passphrase: String?, typed wasTyped: Bool = false) async {
        guard let chosen else { return }
        problem = nil
        working = true
        defer { working = false }
        do {
            if file == nil { file = try await CloudBackup.read(chosen) }
            guard let data = file else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SendablePayload, BackupFile.Problem> in
                do throws(BackupFile.Problem) {
                    return .success(SendablePayload(value: try BackupFile.open(data, passphrase: passphrase).payload))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case let .success(payload):
                try await Task.detached(priority: .userInitiated) { try LocalServer.openShared().importBackup(payload.value) }.value
                if wasTyped, let passphrase { BackupPassphrase.save(passphrase) }
                file = nil
                try? LocalServer.openShared().setCloudBackup(true)
                model.backup.refresh()
                onRestored()
                dismiss()
            case .failure(.locked), .failure(.wrongPassphrase):
                typed = ""
                asking = true
            case let .failure(other):
                file = nil
                problem = other.message
            }
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

/// A backup's JSON handed out of work done off the main thread; only one
/// side holds it at a time.
nonisolated private struct SendablePayload: @unchecked Sendable {
    let value: [String: Any]
}

/// Settings → iCloud & backup → Sync with iCloud (Plans/standalone.md, phase
/// 7, #238): on by default (decided 2026-11-20). Off keeps every number on
/// this phone and stops sending changes; on joins them with iCloud's.
struct SyncRow: View {
    @Environment(AppModel.self) private var model
    @State private var on = LocalStore.syncOn
    @State private var syncing = LocalStore.syncing
    @State private var problem: String?

    var body: some View {
        Toggle(isOn: Binding(get: { on }, set: { turn($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync with iCloud")
                Text(status).font(.footnote).foregroundStyle(problem == nil ? Color.secondary : Palette.bad)
            }
        }
        .frame(minHeight: 44)
    }

    private var status: String {
        if let problem { return problem }
        if !on { return "Off: these numbers are on this iPhone only" }
        if FileManager.default.ubiquityIdentityToken == nil { return "Waiting for iCloud: sign in to iCloud in the Settings app" }
        return syncing ? "On: your devices with this Apple ID share these numbers" : "Waiting for iCloud"
    }

    private func turn(_ value: Bool) {
        do {
            try LocalStore.setSync(value)
            on = value
            syncing = LocalStore.syncing
            problem = nil
            model.reload()
        } catch {
            problem = "Couldn't switch: \(error.localizedDescription)"
        }
    }
}
