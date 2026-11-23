import SwiftUI
import WalletWeatherKit

/// The demo's chip (Plans/connections.md, phase 3, #301; finding R24),
/// under the Dashboard's title and at the top of Settings: "Demo · sample
/// numbers ▾", a capsule in the accent tint. It's the way out: a menu of the
/// connections (the saved ones, On this iPhone and the demo, ticked as on
/// Connections), then Manage connections…, which opens Settings →
/// Connections. Locked in the demo, a real connection asks for Face ID
/// first (`AppModel.choose`), and a server named after its address shows
/// as "Server" (`ConnectionsVisibility`). Phase 4 (#302) makes it the chip
/// for every connection.
struct DemoChip: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openPlace) private var openPlace
    /// Opens Connections; nil asks Settings for it and switches to it.
    var manage: (() -> Void)?
    /// Debug only: `WW_DEBUG_CHIP_MENU=1` shows the menu's choices as a
    /// sheet, since a script can't open a menu. Only the Dashboard's asks.
    var debugSheet = false
    @State private var showingChoices = false

    private var rows: [ConnectionRow] {
        ConnectionRow.rows(saved: model.connections, front: model.lockFront, householdExists: model.hasHousehold,
                           visibility: ConnectionsVisibility(locked: settings.lockedInDemo))
    }

    var body: some View {
        Menu {
            ForEach(rows) { row in
                Button { choose(row) } label: {
                    Label(row.name, systemImage: row.ticked ? "checkmark" : row.symbol)
                }
                .accessibilityAddTraits(row.ticked ? .isSelected : [])
            }
            Divider()
            Button("Manage connections…", systemImage: "arrow.left.arrow.right.circle") { manageConnections() }
        } label: {
            ChipLabel()
        }
        .accessibilityLabel("Demo, sample numbers")
        .accessibilityHint("Shows your connections, to leave the demo")
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            model.reloadConnections()
            if debugSheet, AppModel.debugSetting("WW_DEBUG_CHIP_MENU") == "1" { showingChoices = true }
        }
        .sheet(isPresented: $showingChoices) { DebugChoices(rows: rows, choose: choose, manage: manageConnections) }
    }

    private func choose(_ row: ConnectionRow) {
        showingChoices = false
        Task { await model.choose(row.target) }
    }

    private func manageConnections() {
        showingChoices = false
        if let manage {
            manage()
        } else {
            model.settingsRequest = .connections
            openPlace(.more)
        }
    }
}

/// The capsule: "Demo · sample numbers ▾" in the accent.
private struct ChipLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").imageScale(.small)
            Text("Demo · sample numbers")
            Image(systemName: "chevron.down").imageScale(.small).fontWeight(.bold)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Palette.accent.opacity(0.15), in: .capsule)
        .overlay { Capsule().strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1) }
        .contentShape(.capsule)
    }
}

/// The menu's choices as a sheet, for pictures (`WW_DEBUG_CHIP_MENU=1`,
/// Debug builds): the same rows, ticks and Manage connections….
private struct DebugChoices: View {
    let rows: [ConnectionRow]
    let choose: (ConnectionRow) -> Void
    let manage: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        Button { choose(row) } label: {
                            HStack {
                                Label(row.name, systemImage: row.symbol)
                                Spacer()
                                if row.ticked { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                            }
                        }
                    }
                }
                Section {
                    Button("Manage connections…", systemImage: "arrow.left.arrow.right.circle", action: manage)
                }
            }
            .navigationTitle("Demo · sample numbers")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
