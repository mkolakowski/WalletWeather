import SwiftUI
import UIKit
import WalletWeatherKit

/// The account picker (Plans/account-picker.md, phase 3, #379): a round
/// button with the picture of whoever is signed in to the server in front
/// (their initials until one is set), among the bar's buttons at the top
/// right of the Dashboard and Settings (#383; in Settings' sidebar on the
/// open Duo, its header), in place of the connection chip of #302
/// (decided 2026-11-25). The household on this iPhone shows its iPhone
/// icon; the demo shows the picture of the server it goes back to with a
/// small sparkles badge, also while locked (`AccountPickerState.make`). It
/// shows whenever something is in front (decided 2026-11-25).
///
/// It opens the chip's menu: the connections (the saved ones, On this
/// iPhone and the demo), each server with its own picture, ticked as on
/// Connections; one whose sign-in has ended carries the warning symbol and
/// "Sign in again". Then Manage connections…, which opens Settings →
/// Connections. Locked in the demo, the menu shows names and icons only, as
/// Connections does, and a real connection asks for Face ID first
/// (`AppModel.choose`).
struct AccountPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openPlace) private var openPlace
    /// Opens Connections; nil asks Settings for it and switches to it.
    var manage: (() -> Void)?
    /// Debug only: `WW_DEBUG_PICKER_MENU=1` shows the menu's choices as a
    /// sheet, since a script can't open a menu. Only the Dashboard's asks.
    var debugSheet = false
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 36
    @State private var showingChoices = false

    private var visibility: ConnectionsVisibility { ConnectionsVisibility(locked: settings.lockedInDemo) }

    private var rows: [ConnectionRow] {
        ConnectionRow.rows(saved: model.connections, front: model.lockFront, householdExists: model.hasHousehold,
                           visibility: visibility)
    }

    var body: some View {
        if let state = model.accountPicker(locked: settings.lockedInDemo) {
            Menu {
                ForEach(rows) { row in
                    Button { choose(row) } label: {
                        Text(row.name)
                        if row.warning { Text(ConnectionRow.signInAgainDetail) }
                        menuImage(row)
                    }
                    .accessibilityAddTraits(row.ticked ? .isSelected : [])
                }
                Divider()
                Button("Manage connections…", systemImage: "arrow.left.arrow.right.circle") { manageConnections() }
            } label: {
                AccountFace(state: state, picture: picture(state), size: size)
                    // At least 44 points to tap wherever it sits (#384).
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.label)
            .accessibilityValue(state.warning ? "Sign in again" : "")
            .accessibilityHint(state.demoBadge || state.face == .symbol("sparkles")
                               ? "Shows your connections, to leave the demo" : "Shows your connections, to switch")
            .onAppear {
                model.reloadConnections()
                if debugSheet, AppModel.debugSetting("WW_DEBUG_PICKER_MENU") == "1" { showingChoices = true }
            }
            .sheet(isPresented: $showingChoices) {
                DebugChoices(rows: rows, image: menuImage, choose: choose, manage: manageConnections)
            }
        }
    }

    private func picture(_ state: AccountPickerState) -> UIImage? {
        guard case let .person(id?, _) = state.face else { return nil }
        return model.pictures[id]
    }

    /// A menu row's one image: a tick when it's in front, else the warning
    /// when its sign-in ended, else a server's own picture (its person's
    /// initials until there is one), or the row's icon. Locked in the demo,
    /// icons only.
    private func menuImage(_ row: ConnectionRow) -> Image {
        if row.ticked { return Image(systemName: "checkmark") }
        if row.warning { return Image(systemName: ConnectionRow.warningSymbol) }
        guard visibility.showsDetail, case let .saved(id) = row.target,
              let saved = model.connections.first(where: { $0.id == id }), saved.kind == .server
        else { return Image(systemName: row.symbol) }
        let face = AccountFaces.menuFace(picture: model.pictures[id], initials: Initials.of(saved.person),
                                         accent: UIColor(Palette.accent))
        return Image(uiImage: face)
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

/// The round face: the picture, the initials on the accent's tint, or an
/// icon; a small sparkles badge in the demo, the warning when the sign-in
/// in front has ended.
struct AccountFace: View {
    let state: AccountPickerState
    let picture: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Palette.accent.opacity(0.15))
            switch state.face {
            case .person:
                if let picture {
                    Image(uiImage: picture).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(.circle)
                } else if case let .person(_, initials) = state.face {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                }
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1) }
        .overlay(alignment: .bottomTrailing) {
            if state.demoBadge {
                Badge(symbol: "sparkles", color: Palette.accent, size: size * 0.46)
            } else if state.warning {
                Badge(symbol: ConnectionRow.warningSymbol, color: Palette.warn, size: size * 0.46)
            }
        }
        .contentShape(.circle)
        .accessibilityHidden(true)
    }

    private struct Badge: View {
        let symbol: String
        let color: Color
        let size: CGFloat

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Palette.panel, in: .circle)
                .overlay { Circle().strokeBorder(color.opacity(0.45), lineWidth: 1) }
                .offset(x: size * 0.22, y: size * 0.18)
        }
    }
}

extension View {
    /// The account picker among the bar's buttons, at the top right of the
    /// Dashboard and Settings (#379), on the phone as on the open Duo. It
    /// was on the large title's line first, as a `.largeTitle` toolbar
    /// item, but that item isn't in the accessibility tree, so VoiceOver
    /// couldn't reach it (#383, decided 2026-11-25). It shows bare, without
    /// the bar's shared glass. Not on a page shown inside another.
    func accountPickerItem(manage: (() -> Void)? = nil, debugSheet: Bool = false) -> some View {
        modifier(AccountPickerItem(manage: manage, debugSheet: debugSheet))
    }
}

private struct AccountPickerItem: ViewModifier {
    let manage: (() -> Void)?
    let debugSheet: Bool
    @Environment(\.embeddedPage) private var embedded

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) { AccountPicker(manage: manage, debugSheet: debugSheet) }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

/// The menu's choices as a sheet, for pictures (`WW_DEBUG_PICKER_MENU=1`,
/// Debug builds): the same rows, images and Manage connections….
private struct DebugChoices: View {
    let rows: [ConnectionRow]
    let image: (ConnectionRow) -> Image
    let choose: (ConnectionRow) -> Void
    let manage: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        Button { choose(row) } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                        if row.warning {
                                            Text(ConnectionRow.signInAgainDetail).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                } icon: {
                                    image(row)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Manage connections…", systemImage: "arrow.left.arrow.right.circle", action: manage)
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

/// The pictures as UIKit images: made small once when read, and round for
/// the menu, which shows a row's image as it's given.
enum AccountFaces {
    /// The server's picture (512 points square at most) made small enough
    /// for the button and the menu.
    static func thumbnail(_ data: Data) -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 144, height: 144))
    }

    /// A menu row's face: the picture cut round, or the initials on the
    /// accent's tint, the size of a menu's icon.
    static func menuFace(picture: UIImage?, initials: String, accent: UIColor) -> UIImage {
        let side: CGFloat = 26
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            let circle = UIBezierPath(ovalIn: bounds)
            circle.addClip()
            if let picture {
                let scale = max(side / picture.size.width, side / picture.size.height)
                let drawn = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
                picture.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                        width: drawn.width, height: drawn.height))
            } else {
                accent.withAlphaComponent(0.18).setFill()
                circle.fill()
                let font = UIFont.systemFont(ofSize: initials.count > 1 ? 10.5 : 12, weight: .semibold)
                let text = NSAttributedString(string: initials, attributes: [.font: font, .foregroundColor: accent])
                let size = text.size()
                text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    #if DEBUG
    /// A stand-in profile picture for `WW_DEBUG_CONNECTIONS=sample`: a
    /// person's outline on a sky gradient, as a PNG.
    static func debugSamplePicture() -> Data? {
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.pngData { context in
            let colors = [UIColor(red: 0.25, green: 0.62, blue: 0.77, alpha: 1).cgColor,
                          UIColor(red: 0.16, green: 0.38, blue: 0.62, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            UIColor(red: 0.98, green: 0.92, blue: 0.86, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: side * 0.32, y: side * 0.2, width: side * 0.36, height: side * 0.36)).fill()
            UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: side * 0.14, y: side * 0.62, width: side * 0.72, height: side * 0.6)).fill()
        }
    }
    #endif
}
