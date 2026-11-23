import SwiftUI

// The phone's text size (#311, finding R25). Sizes that hold text grow with
// it (`@ScaledMetric`, which is exactly the old number at the default
// Large), and figures that share a row stack one to a row once they no
// longer fit whole. Up to Large every page is as it was; following the
// phone's text size is not something anyone would want switched off, so
// there's no setting for it.

/// Two layouts of the same things: `across` (side by side, as at the
/// default size) and `stacked` (one to a row). Up to Large it's always
/// `across`, as before; at the accessibility sizes always `stacked`; in
/// between, `across` while it fits whole and `stacked` once it doesn't.
struct FitsAcross<Across: View, Stacked: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let across: Across
    @ViewBuilder let stacked: Stacked

    var body: some View {
        if typeSize <= .large {
            across
        } else if typeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                across
                stacked
            }
        }
    }
}

/// Figures that share a row, each a label over its value: in an `HStack`
/// while they fit, one under the other past that (`FitsAcross`).
struct FigureRow<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        FitsAcross {
            HStack(spacing: spacing) { content }
        } stacked: {
            VStack(alignment: .leading, spacing: 10) { content }
        }
    }
}

/// A label and its value on one line, the value to the right; on a line
/// too narrow for both, the value under the label.
struct LabeledLine<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                value
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                value
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A money figure: up to Large exactly as it was (`defaultScale` is the
    /// shrink it already had there, nil for none: no line limit, no
    /// shrinking). Past Large it stays on one line, never wrapping inside
    /// itself, and shrinks no further than 0.8 (#311).
    func wholeFigure(defaultScale: CGFloat? = nil) -> some View {
        modifier(WholeFigure(defaultScale: defaultScale))
    }
}

private struct WholeFigure: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let defaultScale: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if typeSize <= .large {
            if let defaultScale {
                content.minimumScaleFactor(defaultScale).lineLimit(1)
            } else {
                content
            }
        } else {
            content
                .lineLimit(1)
                .minimumScaleFactor(max(defaultScale ?? 0.8, 0.8))
        }
    }
}
