/// The web app's own themes beyond Light and Dark (phase 9, #102), with the
/// colours of its stylesheet (`apps/web/index.html`, `:root[data-theme=…]`).
/// `WebThemeTests` checks they still match it.
public enum WebTheme: String, CaseIterable, Sendable {
    case dracula, solarized, nord, synthwave, forest, mint, monokai, sunset

    /// One theme's colours, as `0xRRGGBB`.
    public struct Colors: Sendable, Equatable {
        public let page, panel, border, text, accent, good, bad, warn: UInt32
        /// Drawn on a dark page: the system's own parts (bars, sheets) go dark.
        public let isDark: Bool

        public init(page: UInt32, panel: UInt32, border: UInt32, text: UInt32, accent: UInt32,
                    good: UInt32, bad: UInt32, warn: UInt32, isDark: Bool) {
            self.page = page; self.panel = panel; self.border = border; self.text = text
            self.accent = accent; self.good = good; self.bad = bad; self.warn = warn
            self.isDark = isDark
        }
    }

    public var title: String {
        switch self {
        case .dracula: "Dracula"
        case .solarized: "Solarized"
        case .nord: "Nord"
        case .synthwave: "Synthwave"
        case .forest: "Forest"
        case .mint: "Mint"
        case .monokai: "Monokai"
        case .sunset: "Sunset"
        }
    }

    public var colors: Colors {
        switch self {
        case .dracula:
            Colors(page: 0x282A36, panel: 0x343746, border: 0x44475A, text: 0xF8F8F2,
                   accent: 0xBD93F9, good: 0x50FA7B, bad: 0xFF7676, warn: 0xF1FA8C, isDark: true)
        case .solarized:
            Colors(page: 0xFDF6E3, panel: 0xEEE8D5, border: 0xCBC4A8, text: 0x073642,
                   accent: 0x1E6DA5, good: 0x5F6E00, bad: 0xCA2522, warn: 0x826200, isDark: false)
        case .nord:
            Colors(page: 0x2E3440, panel: 0x3B4252, border: 0x434C5E, text: 0xECEFF4,
                   accent: 0x88C0D0, good: 0xA3BE8C, bad: 0xD89FA4, warn: 0xEBCB8B, isDark: true)
        case .synthwave:
            Colors(page: 0x2B213A, panel: 0x3A2C4A, border: 0x55456B, text: 0xF9F2E7,
                   accent: 0xFF6AC1, good: 0x00F5D4, bad: 0xFF6386, warn: 0xFEDE1B, isDark: true)
        case .forest:
            Colors(page: 0x1A2421, panel: 0x243330, border: 0x3A5048, text: 0xE4EBE3,
                   accent: 0x5EB583, good: 0x9BD680, bad: 0xE67777, warn: 0xF0C674, isDark: true)
        case .mint:
            Colors(page: 0xF3FAF5, panel: 0xE1F2E5, border: 0xB8D9BF, text: 0x15372A,
                   accent: 0x267955, good: 0x1E7A4C, bad: 0xC23030, warn: 0x8C640E, isDark: false)
        case .monokai:
            Colors(page: 0x272822, panel: 0x34352F, border: 0x49483E, text: 0xF8F8F2,
                   accent: 0xFD971F, good: 0xA6E22E, bad: 0xFB6B9F, warn: 0xE6DB74, isDark: true)
        case .sunset:
            Colors(page: 0x2A1E1A, panel: 0x3A2A25, border: 0x5A3E35, text: 0xFCE8D8,
                   accent: 0xFF7F3F, good: 0x80C26E, bad: 0xF1696F, warn: 0xFFB84A, isDark: true)
        }
    }
}

/// The theme saved on the server (`theme_preference` in `/api/me`), read for
/// the app's "Match the web app" look.
public enum ServerTheme: Equatable, Sendable {
    /// Unset or "system": follow the phone.
    case system
    case light
    case dark
    case web(WebTheme)

    public init(_ saved: String?) {
        switch saved {
        case "light": self = .light
        case "dark": self = .dark
        case let other?: self = WebTheme(rawValue: other).map(ServerTheme.web) ?? .system
        case nil: self = .system
        }
    }
}
