import SwiftUI
import WalletWeatherKit

/// Every look as a tile: a tiny screen in the look's own colours with its
/// name under it, the chosen one ringed in the accent colour. Tapping one
/// applies it at once (which ticks Getting started's look task). Used by
/// Settings → Appearance and Getting started's Choose a look (#296,
/// finding R19). Three across on a phone, more on a wider width.
struct LookGrid: View {
    @Environment(AppSettings.self) private var settings

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(Look.allCases) { look in
                LookTile(look: look, selected: settings.look == look,
                         swatches: look.swatches(server: settings.serverTheme)) {
                    settings.look = look
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One look: one button, named for the look, "selected" when chosen.
private struct LookTile: View {
    let look: Look
    let selected: Bool
    let swatches: [LookPreview.Swatch]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                LookMiniature(swatches: swatches)
                    .aspectRatio(1.3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                    .padding(3)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 3)
                        }
                    }
                Text(look.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.accent : (Palette.text ?? Color.primary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The tiny screens of a look: one, or two split down the middle (Light on
/// the left, Dark on the right).
private struct LookMiniature: View {
    let swatches: [LookPreview.Swatch]

    var body: some View {
        ZStack {
            if let first = swatches.first { MiniScreen(swatch: first) }
            if swatches.count > 1 {
                MiniScreen(swatch: swatches[1])
                    .mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }
}

/// A page-coloured screen holding a card with a short text bar, a green and
/// a red bar side by side, and an accent bar.
private struct MiniScreen: View {
    let swatch: LookPreview.Swatch

    var body: some View {
        GeometryReader { box in
            let inner = box.size.width * 0.78
            ZStack {
                Color(UIColor(hex: swatch.page))
                VStack(alignment: .leading, spacing: box.size.height * 0.07) {
                    bar(swatch.text, width: inner * 0.5, height: box.size.height * 0.07)
                    HStack(spacing: 4) {
                        bar(swatch.good, width: inner * 0.34, height: box.size.height * 0.07)
                        bar(swatch.bad, width: inner * 0.34, height: box.size.height * 0.07)
                    }
                    bar(swatch.accent, width: inner * 0.62, height: box.size.height * 0.09)
                }
                .padding(box.size.width * 0.09)
                .frame(width: inner, alignment: .leading)
                .background(Color(UIColor(hex: swatch.card)), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func bar(_ hex: UInt32, width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Color(UIColor(hex: hex))).frame(width: width, height: height)
    }
}
