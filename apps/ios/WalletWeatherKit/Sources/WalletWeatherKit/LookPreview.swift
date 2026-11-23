import Foundation

/// The colours of the looks that aren't the web app's own themes, in one
/// place: the app's `Palette` reads them for the look in use, and the
/// Appearance page's previews read them to draw every look without
/// switching to it, so the two can't drift (#296). AMOLED black and Sepia
/// are the mockups' colours (decided 2026-11-14); Light and Dark are the web
/// app's default themes, with the page, card and text colours the system
/// draws them in (`systemGroupedBackground`, `secondarySystemGroupedBackground`
/// and `label`, which the app itself doesn't set; they're here for the
/// previews only).
public enum BuiltInLook: String, CaseIterable, Sendable {
    case light, dark, amoled, sepia

    public var colors: WebTheme.Colors {
        switch self {
        case .light:
            WebTheme.Colors(page: 0xF2F2F7, panel: 0xFFFFFF, border: 0xD1D1D6, text: 0x000000,
                            accent: 0x0969DA, good: 0x1A7F37, bad: 0xCF222E, warn: 0x9A6700, isDark: false)
        case .dark:
            WebTheme.Colors(page: 0x000000, panel: 0x1C1C1E, border: 0x38383A, text: 0xFFFFFF,
                            accent: 0x58A6FF, good: 0x3FB950, bad: 0xF85149, warn: 0xD29922, isDark: true)
        case .amoled:
            WebTheme.Colors(page: 0x000000, panel: 0x101317, border: 0x2A3038, text: 0xFFFFFF,
                            accent: 0x58A6FF, good: 0x3FB950, bad: 0xFF7B72, warn: 0xF0883E, isDark: true)
        case .sepia:
            WebTheme.Colors(page: 0xEAD5B3, panel: 0xFDF3E3, border: 0xCFAE82, text: 0x3D2B1C,
                            accent: 0x9C4410, good: 0x2F6B2F, bad: 0xA32A1C, warn: 0x8A6D00, isDark: false)
        }
    }
}

/// What a tile of the Appearance page draws for a look: a tiny screen in
/// the look's own colours (#296).
public enum LookPreview {
    /// One screen's colours, as `0xRRGGBB`.
    public struct Swatch: Sendable, Equatable {
        public let page, card, text, accent, good, bad: UInt32

        public init(_ colors: WebTheme.Colors) {
            page = colors.page; card = colors.panel; text = colors.text
            accent = colors.accent; good = colors.good; bad = colors.bad
        }
    }

    /// Every look's stored value, in the order the page lists them: Match
    /// this iPhone, Match the web app, Light, Dark, AMOLED black, Sepia, then
    /// the web app's eight themes.
    public static let rawValues: [String] =
        ["system", "web"] + BuiltInLook.allCases.map(\.rawValue) + WebTheme.allCases.map(\.rawValue)

    /// The screen or screens a look is drawn as: one, or two (Light, then
    /// Dark) for Match this iPhone, which is split down the middle, and for
    /// Match the web app when the server has no theme of its own saved.
    /// `server` is the theme saved on the server. Nil for a value that is
    /// no look.
    public static func swatches(for rawValue: String, server: ServerTheme = .system) -> [Swatch]? {
        func one(_ look: BuiltInLook) -> [Swatch] { [Swatch(look.colors)] }
        let split = [Swatch(BuiltInLook.light.colors), Swatch(BuiltInLook.dark.colors)]
        if let built = BuiltInLook(rawValue: rawValue) { return one(built) }
        if let theme = WebTheme(rawValue: rawValue) { return [Swatch(theme.colors)] }
        switch rawValue {
        case "system": return split
        case "web":
            switch server {
            case .system: return split
            case .light: return one(.light)
            case .dark: return one(.dark)
            case let .web(theme): return [Swatch(theme.colors)]
            }
        default: return nil
        }
    }
}
