import Foundation

/// How far apart two colours read: the WCAG relative-luminance contrast
/// ratio, from 1:1 (the same) to 21:1 (black on white). 4.5:1 is the line
/// for text (WCAG AA), which the theme editor's readability line checks
/// (ios-settings phase 4, #297).
public enum Contrast {
    /// The line a pair has to reach to read clearly.
    public static let readable = 4.5

    /// A colour's relative luminance, 0 (black) to 1 (white).
    public static func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let s = Double(value & 0xFF) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    /// The contrast ratio of two colours, whichever way round.
    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// A theme someone made themselves (ios-settings phase 4, #297; decided
/// 2026-11-23): a name and six colours (page, card, text, accent, money in
/// and money out), with the outline and warning colours worked out from
/// them. Kept in the phone's iCloud key-value store, names and colours
/// only, and mirrored in the app's preferences (`CustomThemeStore`).
public struct CustomTheme: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The six colours, as `0xRRGGBB`.
    public var page, card, text, accent, moneyIn, moneyOut: UInt32

    public init(id: UUID = UUID(), name: String, page: UInt32, card: UInt32, text: UInt32,
                accent: UInt32, moneyIn: UInt32, moneyOut: UInt32) {
        self.id = id; self.name = name
        self.page = page; self.card = card; self.text = text
        self.accent = accent; self.moneyIn = moneyIn; self.moneyOut = moneyOut
    }

    /// A new theme that starts as a copy of a look's colours.
    public init(id: UUID = UUID(), name: String, copying colors: WebTheme.Colors) {
        self.init(id: id, name: name, page: colors.page, card: colors.panel, text: colors.text,
                  accent: colors.accent, moneyIn: colors.good, moneyOut: colors.bad)
    }

    /// What the app saves as the look (`appearance`) while this theme is
    /// chosen: distinct from every built-in look's value, and the same for
    /// as long as the theme lasts, however it's renamed or recoloured.
    public var rawValue: String { CustomTheme.prefix + id.uuidString.lowercased() }

    public static let prefix = "custom:"

    /// Drawn on a dark page (system bars and sheets go dark): the page is
    /// nearer black than white, judged by contrast. The line is where black
    /// and white text would read equally well on it.
    public var isDark: Bool { Contrast.luminance(page) < CustomTheme.darkBelow }

    /// sqrt(1.05 × 0.05) − 0.05: the luminance where contrast with black
    /// equals contrast with white.
    static let darkBelow = (1.05 * 0.05).squareRoot() - 0.05

    /// The outline: the card moved 18% of the way toward the text, so it
    /// shows on the card in both light and dark themes.
    public var outline: UInt32 { CustomTheme.mix(card, text, 0.18) }

    /// The warning colour: the web app's light or dark amber, whichever
    /// reads better on the card.
    public var warn: UInt32 {
        let (light, dark): (UInt32, UInt32) = (0x9A6700, 0xD29922)
        return Contrast.ratio(light, card) >= Contrast.ratio(dark, card) ? light : dark
    }

    /// All the colours the app draws with, in the web themes' shape.
    public var colors: WebTheme.Colors {
        WebTheme.Colors(page: page, panel: card, border: outline, text: text, accent: accent,
                        good: moneyIn, bad: moneyOut, warn: warn, isDark: isDark)
    }

    /// `a` moved `amount` (0…1) of the way toward `b`, channel by channel.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * amount).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    // MARK: - Readability

    /// A pair of colours the editor's readability line checks.
    public enum Pair: String, CaseIterable, Sendable {
        case textOnCard, moneyInOnCard, moneyOutOnCard, accentOnPage

        /// How the warning names it.
        public var title: String {
            switch self {
            case .textOnCard: "text on card"
            case .moneyInOnCard: "money in on card"
            case .moneyOutOnCard: "money out on card"
            case .accentOnPage: "accent on page"
            }
        }
    }

    /// A pair's contrast ratio in this theme.
    public func ratio(_ pair: Pair) -> Double {
        switch pair {
        case .textOnCard: Contrast.ratio(text, card)
        case .moneyInOnCard: Contrast.ratio(moneyIn, card)
        case .moneyOutOnCard: Contrast.ratio(moneyOut, card)
        case .accentOnPage: Contrast.ratio(accent, page)
        }
    }

    /// The pairs under 4.5:1, in the order the editor lists them. A theme
    /// with faint pairs still saves; the editor only warns.
    public var faintPairs: [Pair] { Pair.allCases.filter { ratio($0) < Contrast.readable } }

    // MARK: - Storage

    /// How a theme is written down: hex strings, so the stored value reads
    /// as what it is.
    private enum CodingKeys: String, CodingKey { case id, name, page, card, text, accent, moneyIn, moneyOut }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func color(_ key: CodingKeys) throws -> UInt32 {
            let raw = try c.decode(String.self, forKey: key)
            guard let value = CustomTheme.hex(raw) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not #rrggbb: \(raw)")
            }
            return value
        }
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  page: try color(.page), card: try color(.card), text: try color(.text),
                  accent: try color(.accent), moneyIn: try color(.moneyIn), moneyOut: try color(.moneyOut))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        for (key, value) in [(CodingKeys.page, page), (.card, card), (.text, text),
                             (.accent, accent), (.moneyIn, moneyIn), (.moneyOut, moneyOut)] {
            try c.encode(CustomTheme.hex(value), forKey: key)
        }
    }

    /// `0xRRGGBB` as `#rrggbb`.
    public static func hex(_ value: UInt32) -> String { String(format: "#%06x", value & 0xFFFFFF) }

    /// `#rrggbb` as `0xRRGGBB`; nil for anything else.
    public static func hex(_ string: String) -> UInt32? {
        guard string.count == 7, string.hasPrefix("#"),
              string.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(string.dropFirst(), radix: 16)
    }

    /// The name, trimmed, or nil when it's blank (the editor won't save then).
    public static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The themes as they're stored: under one key in the iCloud key-value
/// store and, as a mirror, in the app's preferences, so with iCloud off they
/// stay on this iPhone. Names and colours only, never a number.
public enum CustomThemeStore {
    /// The key in both stores.
    public static let key = "themes.custom"

    private struct Stored: Codable {
        var version = 1
        var themes: [CustomTheme]
    }

    public static func encode(_ themes: [CustomTheme]) -> Data {
        (try? JSONEncoder().encode(Stored(themes: themes))) ?? Data()
    }

    /// The themes in `data`; none for nothing stored or anything unreadable.
    public static func decode(_ data: Data?) -> [CustomTheme] {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return [] }
        return stored.themes
    }

    /// What to keep when iCloud's copy arrives. A change made on another
    /// iPhone (`replacing`) wins outright, deletions included. The first
    /// copy after the iCloud account appears or the first download keeps
    /// both: iCloud's themes, then this iPhone's that iCloud doesn't have,
    /// so a theme made while iCloud was off isn't lost.
    public static func incoming(cloud: [CustomTheme], local: [CustomTheme], replacing: Bool) -> [CustomTheme] {
        if replacing { return cloud }
        let known = Set(cloud.map(\.id))
        return cloud + local.filter { !known.contains($0.id) }
    }

    /// The look to show for a saved `appearance` value: the value itself
    /// when it's a built-in look or one of `themes`, otherwise Match this
    /// iPhone (`system`), so a deleted theme or an unknown value never
    /// leaves the app without a look.
    public static func resolve(saved: String?, themes: [CustomTheme]) -> String {
        guard let saved else { return "system" }
        if LookPreview.rawValues.contains(saved) { return saved }
        if themes.contains(where: { $0.rawValue == saved }) { return saved }
        return "system"
    }

    // MARK: - Debug samples

    /// Two sample themes for pictures (`WW_DEBUG_CUSTOM_THEMES=sample`), kept
    /// in memory only: "Paper" (light, with its money in faint on the card,
    /// so the readability warning shows) and "Deep sea" (dark, all clear).
    public static let samples: [CustomTheme] = [sampleLight, sampleDark]

    public static let sampleLight = CustomTheme(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000a1")!, name: "Paper",
        page: 0xF4F1EA, card: 0xFFFDF8, text: 0x2B2A27, accent: 0x7B4BB7,
        moneyIn: 0x5DB075, moneyOut: 0xB3261E)

    public static let sampleDark = CustomTheme(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000d1")!, name: "Deep sea",
        page: 0x0B1A2B, card: 0x13263B, text: 0xE6F0FA, accent: 0x4FC3F7,
        moneyIn: 0x66D9A0, moneyOut: 0xFF8A80)

    /// The sample a debug alias names (`custom-light`, `custom-dark`).
    public static func sample(named alias: String?) -> CustomTheme? {
        switch alias {
        case "custom-light": sampleLight
        case "custom-dark": sampleDark
        default: nil
        }
    }
}
