import SwiftUI
import UIKit

/// The app's looks (More → Appearance, decided 2026-11-14): Match the phone,
/// Light, Dark, and two of its own that aren't among the web app's themes,
/// AMOLED black and Sepia, with the colours drawn in the mockups.
enum Look: String, CaseIterable, Identifiable {
    case system, light, dark, amoled, sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match the phone"
        case .light: "Light"
        case .dark: "Dark"
        case .amoled: "AMOLED black"
        case .sepia: "Sepia"
        }
    }

    /// What the system draws its own parts in (bars, sheets, lists).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .sepia: .light
        case .dark, .amoled: .dark
        }
    }
}

/// WalletWeather's colours: the web app's default dark and light themes,
/// and the mockups' AMOLED black and Sepia.
enum Palette {
    /// The look in use, set by the app root when the setting changes (the
    /// root rebuilds the pages, so every colour is read again).
    nonisolated(unsafe) static var look: Look = .system

    static var accent: Color {
        switch look {
        case .amoled: hex(0x58A6FF)
        case .sepia: hex(0x9C4410)
        default: dynamic(light: 0x0969DA, dark: 0x58A6FF)
        }
    }

    static var good: Color {
        switch look {
        case .amoled: hex(0x3FB950)
        case .sepia: hex(0x2F6B2F)
        default: dynamic(light: 0x1A7F37, dark: 0x3FB950)
        }
    }

    static var bad: Color {
        switch look {
        case .amoled: hex(0xFF7B72)
        case .sepia: hex(0xA32A1C)
        default: dynamic(light: 0xCF222E, dark: 0xF85149)
        }
    }

    static var warn: Color {
        switch look {
        case .amoled: hex(0xF0883E)
        case .sepia: hex(0x8A6D00)
        default: dynamic(light: 0x9A6700, dark: 0xD29922)
        }
    }

    /// The text colour for Sepia (brown); nil keeps the system's.
    static var text: Color? { look == .sepia ? hex(0x3D2B1C) : nil }

    /// Behind everything: black for AMOLED, tan for Sepia.
    static var page: Color {
        switch look {
        case .amoled: .black
        case .sepia: hex(0xEAD5B3)
        default: Color(.systemGroupedBackground)
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
                        .overlay(shape.strokeBorder(Palette.hex(0x2A3038), lineWidth: 1))
                case .sepia:
                    padded.glassEffect(.regular.tint(Palette.hex(0xFDF3E3).opacity(0.7)), in: shape)
                        .overlay(shape.strokeBorder(Palette.hex(0xCFAE82), lineWidth: 1))
                        .shadow(color: Color(red: 61 / 255, green: 43 / 255, blue: 28 / 255).opacity(0.14), radius: 3, y: 2)
                default:
                    padded.glassEffect(.regular, in: shape)
                }
            }
        }
    }

    private var solidFill: Color {
        switch Palette.look {
        case .amoled: Palette.hex(0x101317)
        case .sepia: Palette.hex(0xFDF3E3)
        default: Color(.secondarySystemGroupedBackground)
        }
    }

    private var outline: Color {
        switch Palette.look {
        case .amoled: Palette.hex(0x2A3038)
        case .sepia: Palette.hex(0xCFAE82)
        default: .clear
        }
    }
}

extension View {
    func card() -> some View { modifier(Card()) }
}

/// A small grey heading over a number.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
    }
}
