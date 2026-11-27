import SwiftUI
import UIKit

extension View {
    /// A prominent glass button whose label reads on its colour in every look
    /// (#389). A look with a text colour of its own (Sepia, the web themes,
    /// your own) paints every label in it, which turned a prominent button's
    /// white label dark on the accent; there the label is white or black,
    /// whichever has more contrast with the button's colour. Other looks keep
    /// the system's label. `tint` is the button's colour when it isn't the
    /// accent.
    func prominentButton(tint: Color? = nil) -> some View {
        modifier(ProminentButton(tint: tint))
    }
}

private struct ProminentButton: ViewModifier {
    let tint: Color?
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let button = content.buttonStyle(.glassProminent)
        let tinted = tint.map { AnyView(button.tint($0)) } ?? AnyView(button)
        if Palette.text != nil { tinted.foregroundStyle(label) } else { tinted }
    }

    /// White or black, by contrast with the button's colour (WCAG's relative luminance).
    private var label: Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let colour = UIColor(tint ?? Palette.accent).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05) >= (luminance + 0.05) / 0.05 ? .white : .black
    }
}
