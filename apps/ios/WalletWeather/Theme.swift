import SwiftUI
import UIKit
import WalletWeatherKit

/// The app's looks (Settings → Appearance): Match this iPhone, Match the web app,
/// Light, Dark, two of its own that aren't among the web app's themes
/// (AMOLED black and Sepia, with the colours drawn in the mockups; decided
/// 2026-11-14), and the web app's other eight themes (phase 9, #102). The
/// phone keeps its own choice; Match the web app follows the theme saved on
/// the server, and choosing on the phone never changes the web app (decided
/// 2026-11-15). The raw values are stored in the app's preferences.
enum Look: Hashable, Identifiable {
    case system, web, light, dark, amoled, sepia
    case theme(WebTheme)

    /// In the order the Appearance page lists them (`LookPreview.rawValues`).
    static let allCases: [Look] = LookPreview.rawValues.compactMap { Look(rawValue: $0) }

    /// The screens a tile draws for this look; `server` is the theme saved
    /// on the server, which Match the web app shows (#296).
    func swatches(server: String?) -> [LookPreview.Swatch] {
        LookPreview.swatches(for: rawValue, server: ServerTheme(server)) ?? []
    }

    init?(rawValue: String) {
        switch rawValue {
        case "system": self = .system
        case "web": self = .web
        case "light": self = .light
        case "dark": self = .dark
        case "amoled": self = .amoled
        case "sepia": self = .sepia
        default:
            guard let theme = WebTheme(rawValue: rawValue) else { return nil }
            self = .theme(theme)
        }
    }

    var rawValue: String {
        switch self {
        case .system: "system"
        case .web: "web"
        case .light: "light"
        case .dark: "dark"
        case .amoled: "amoled"
        case .sepia: "sepia"
        case let .theme(theme): theme.rawValue
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match this iPhone"
        case .web: "Match the web app"
        case .light: "Light"
        case .dark: "Dark"
        case .amoled: "AMOLED black"
        case .sepia: "Sepia"
        case let .theme(theme): theme.title
        }
    }

    /// What Match the web app shows for the theme saved on the server.
    static func matching(_ saved: ServerTheme) -> Look {
        switch saved {
        case .system: .system
        case .light: .light
        case .dark: .dark
        case let .web(theme): .theme(theme)
        }
    }

    /// What the system draws its own parts in (bars, sheets, lists).
    var colorScheme: ColorScheme? {
        switch self {
        case .system, .web: nil
        case .light, .sepia: .light
        case .dark, .amoled: .dark
        case let .theme(theme): theme.colors.isDark ? .dark : .light
        }
    }
}

/// WalletWeather's colours: the web app's default dark and light themes,
/// the mockups' AMOLED black and Sepia, and the web app's other themes.
enum Palette {
    /// The look shown (Match the web app already resolved), set by the app
    /// root when it changes (the root rebuilds the pages, so every colour is
    /// read again).
    nonisolated(unsafe) static var look: Look = .system

    /// A web theme's colours, when one is shown.
    private static var theme: WebTheme.Colors? {
        if case let .theme(theme) = look { return theme.colors }
        return nil
    }

    // The literals for the looks that have their own are `BuiltInLook`'s,
    // which the Appearance page's previews read too, so they can't drift.

    private static func dynamic(_ keyPath: KeyPath<WebTheme.Colors, UInt32>) -> Color {
        dynamic(light: BuiltInLook.light.colors[keyPath: keyPath], dark: BuiltInLook.dark.colors[keyPath: keyPath])
    }

    /// One colour for the look in use: a web theme's, AMOLED black's or
    /// Sepia's own, or Light's and Dark's, which follow the phone.
    private static func color(_ keyPath: KeyPath<WebTheme.Colors, UInt32>) -> Color {
        if let theme { return hex(theme[keyPath: keyPath]) }
        switch look {
        case .amoled: return hex(BuiltInLook.amoled.colors[keyPath: keyPath])
        case .sepia: return hex(BuiltInLook.sepia.colors[keyPath: keyPath])
        default: return dynamic(keyPath)
        }
    }

    static var accent: Color { color(\.accent) }
    static var good: Color { color(\.good) }
    static var bad: Color { color(\.bad) }
    static var warn: Color { color(\.warn) }

    /// The text colour for Sepia (brown) and the web themes; nil keeps the
    /// system's.
    static var text: Color? {
        if let theme { return hex(theme.text) }
        return look == .sepia ? hex(BuiltInLook.sepia.colors.text) : nil
    }

    /// Behind everything: black for AMOLED, tan for Sepia, a web theme's own.
    static var page: Color {
        if let theme { return hex(theme.page) }
        switch look {
        case .amoled: return hex(BuiltInLook.amoled.colors.page)
        case .sepia: return hex(BuiltInLook.sepia.colors.page)
        default: return Color(.systemGroupedBackground)
        }
    }

    /// A card's solid colour (Reduce Transparency, Increase Contrast).
    static var panel: Color {
        if let theme { return hex(theme.panel) }
        switch look {
        case .amoled: return hex(BuiltInLook.amoled.colors.panel)
        case .sepia: return hex(BuiltInLook.sepia.colors.panel)
        default: return Color(.secondarySystemGroupedBackground)
        }
    }

    /// Behind each row of a list or form: the card colour in AMOLED black,
    /// Sepia and the web themes; nil keeps the system's in Light and Dark.
    static var row: Color? {
        switch look {
        case .system, .web, .light, .dark: nil
        default: panel
        }
    }

    /// A card's outline: AMOLED's, Sepia's and the web themes'; none for
    /// light and dark.
    static var outline: Color {
        if let theme { return hex(theme.border) }
        switch look {
        case .amoled: return hex(BuiltInLook.amoled.colors.border)
        case .sepia: return hex(BuiltInLook.sepia.colors.border)
        default: return .clear
        }
    }

    static func hex(_ value: UInt32) -> Color { Color(UIColor(hex: value)) }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// A category's `#rrggbb`, or a steady colour picked from its name.
    static func category(_ hex: String?, name: String) -> Color {
        if let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) {
            return Color(UIColor(hex: value))
        }
        let fallback: [UInt32] = [0x58A6FF, 0x3FB950, 0xD29922, 0xA371F7, 0xF778BA, 0x56D4DD, 0xFF7B72, 0x8B949E]
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % fallback.count
        return name == "Other" ? .secondary : Color(UIColor(hex: fallback[index]))
    }

    /// Green for money in hand, red below zero, as the web app shows them.
    static func amount(_ negative: Bool) -> Color { negative ? bad : (text ?? .primary) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Behind every page: the look's page colour with a soft tint of its accent
/// fading down from the top, so the glass has something to show.
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Palette.page
            LinearGradient(colors: [Palette.accent.opacity(tint), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
        }
    }

    private var tint: Double {
        switch Palette.look {
        case .amoled: 0.18
        case .sepia: 0.24
        case .theme: 0.20
        default: scheme == .dark ? 0.30 : 0.22
        }
    }
}

/// A card: Liquid Glass, solid when the phone asks for less transparency
/// (Reduce Transparency) or more contrast (Increase Contrast), so the
/// numbers on it stay easy to read in every case. AMOLED black's cards carry
/// a thin outline on the black; Sepia's are cream with an outline and a
/// soft shadow, as drawn in the mockups.
struct Card: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let padded = content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if reduceTransparency || contrast == .increased {
                padded
                    .background(solidFill, in: shape)
                    .overlay(shape.strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : outline, lineWidth: 1))
            } else {
                switch Palette.look {
                case .amoled:
                    padded.glassEffect(.regular, in: shape)
                        .overlay(shape.strokeBorder(Palette.outline, lineWidth: 1))
                case .sepia:
                    padded.glassEffect(.regular.tint(Palette.panel.opacity(0.7)), in: shape)
                        .overlay(shape.strokeBorder(Palette.outline, lineWidth: 1))
                        .shadow(color: Palette.hex(BuiltInLook.sepia.colors.text).opacity(0.14), radius: 3, y: 2)
                case .theme:
                    // The theme's panel colour under the glass, so text in
                    // the theme's colour stays on the colour it was made for.
                    padded.glassEffect(.regular.tint(Palette.panel.opacity(0.85)), in: shape)
                        .overlay(shape.strokeBorder(Palette.outline, lineWidth: 1))
                default:
                    padded.glassEffect(.regular, in: shape)
                }
            }
        }
    }

    private var solidFill: Color { Palette.panel }
    private var outline: Color { Palette.outline }
}

extension View {
    func card() -> some View { modifier(Card()) }
}

/// A small grey label over a number, in sentence case like the labels beside it.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
