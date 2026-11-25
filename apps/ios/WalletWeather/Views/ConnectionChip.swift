import SwiftUI
import WalletWeatherKit

/// The connection chip (Plans/connections.md, phase 4, #302; the demo's chip
/// of phase 3, #301, made general; finding R24), under the Dashboard's title
/// and at the top of Settings only: the connection in front by name with a
/// small icon ("Home", "On this iPhone", "Demo · sample numbers") and a ▾, a
/// capsule in the accent tint. It opens a menu of the connections (the saved
/// ones, On this iPhone and the demo, ticked as on Connections; one whose
/// sign-in has ended carries a warning symbol and "Sign in again"), then
/// Manage connections…, which opens Settings → Connections. Locked in the
/// demo, a real connection asks for Face ID first (`AppModel.choose`), and a
/// server named after its address shows as "Server"
/// (`ConnectionsVisibility`). It shows only with something to switch between
/// (`ConnectionChipState.make`); there is no setting for it.
struct ConnectionChip: View {
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

    private var chip: ConnectionChipState? { model.connectionChip(locked: settings.lockedInDemo) }

    var body: some View {
        if let chip {
            Menu {
                ForEach(rows) { row in
                    Button { choose(row) } label: {
                        Text(row.name)
                        if row.warning { Text(ConnectionRow.signInAgainDetail) }
                        Image(systemName: Self.menuSymbol(row))
                    }
                    .accessibilityAddTraits(row.ticked ? .isSelected : [])
                }
                Divider()
                Button("Manage connections…", systemImage: "arrow.left.arrow.right.circle") { manageConnections() }
            } label: {
                ChipLabel(chip: chip)
            }
            .accessibilityLabel(chip.title == ConnectionChipState.demoTitle ? "Demo, sample numbers" : chip.title)
            .accessibilityValue(chip.warning ? "Sign in again" : "")
            .accessibilityHint(chip.title == ConnectionChipState.demoTitle
                               ? "Shows your connections, to leave the demo" : "Shows your connections, to switch")
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                model.reloadConnections()
                if debugSheet, AppModel.debugSetting("WW_DEBUG_CHIP_MENU") == "1" { showingChoices = true }
            }
            .sheet(isPresented: $showingChoices) {
                DebugChoices(title: chip.title, rows: rows, choose: choose, manage: manageConnections)
            }
        }
    }

    /// A menu row's one icon: a tick when it's in front, else the warning
    /// when its sign-in ended, else its own.
    fileprivate static func menuSymbol(_ row: ConnectionRow) -> String {
        if row.ticked { return "checkmark" }
        return row.warning ? ConnectionRow.warningSymbol : row.symbol
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

/// The capsule: icon, name, the warning when its sign-in ended, and ▾.
private struct ChipLabel: View {
    let chip: ConnectionChipState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: chip.symbol).imageScale(.small)
            Text(chip.title).wrapsAboveLarge()
            if chip.warning {
                Image(systemName: ConnectionRow.warningSymbol).imageScale(.small).foregroundStyle(Palette.warn)
            }
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
    let title: String
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
                                if row.warning {
                                    Image(systemName: ConnectionRow.warningSymbol).foregroundStyle(Palette.warn)
                                    Text(ConnectionRow.signInAgainDetail).font(.footnote).foregroundStyle(.secondary)
                                }
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
