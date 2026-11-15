import SwiftUI
import UIKit

/// WalletWeather's colours: the web app's default dark and light themes.
enum Palette {
    static let accent = dynamic(light: 0x0969DA, dark: 0x58A6FF)
    static let good = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let bad = dynamic(light: 0xCF222E, dark: 0xF85149)
    static let warn = dynamic(light: 0x9A6700, dark: 0xD29922)

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
    static func amount(_ negative: Bool) -> Color { negative ? bad : .primary }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Behind every page: the system background with a soft tint of the accent
/// fading down from the top, so the glass has something to show.
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [Palette.accent.opacity(scheme == .dark ? 0.30 : 0.22), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
        }
    }
}

/// A card: Liquid Glass, solid when the phone asks for less transparency
/// (Reduce Transparency) or more contrast (Increase Contrast), so the
/// numbers on it stay easy to read in every case.
struct Card: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let padded = content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        if reduceTransparency || contrast == .increased {
            padded
                .background(Color(.secondarySystemGroupedBackground), in: shape)
                .overlay(shape.strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : .clear, lineWidth: 1))
        } else {
            padded.glassEffect(.regular, in: shape)
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
