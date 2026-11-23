import SwiftUI
import WalletWeatherKit

// One fold layout for every two-pane page of the open Duo (duo-more phase 1,
// #304). Lying flat, the two halves stay as they were; half open like a book,
// the panes sit either side of the fold's band; half open like a laptop, one
// pane stands above the band and the other lies below it. The panes move from
// one arrangement to the other as the Duo folds, or cross-fade with Reduce
// Motion on. The arithmetic is `FoldPanes` in the Kit, tested there. The
// layout follows the device's pose, so there is no setting for it.

extension EnvironmentValues {
    /// How far a pane's content keeps from the pane's sides: read by views
    /// that stand in a pane on their own (the embedded editors).
    @Entry var paneEdges = FoldPanes.Edges(leading: FoldPanes.middle, trailing: FoldPanes.outer)
}

extension FoldPanes.Edges {
    /// An embedded editor's form margin on its leading side: 12 lying flat,
    /// as before #304 (the form's rows then sit as they always have), and the
    /// form's own margin beside the band or stacked.
    var formMargin: CGFloat? { leading > FoldPanes.outer ? leading - FoldPanes.outer : nil }
}

/// Two panes, laid out for the Duo's pose. Each pane is handed the edges its
/// content keeps from its own sides (16 at the page's edge; 28 from the
/// middle lying flat, as before; 12 from the band half open). `upright` says
/// which pane goes on top when they stack: the left one unless a page says
/// otherwise.
struct FoldLayout<Leading: View, Trailing: View>: View {
    var upright: FoldPanes.Upright = .leading
    @ViewBuilder let leading: (FoldPanes.Edges) -> Leading
    @ViewBuilder let trailing: (FoldPanes.Edges) -> Trailing

    var body: some View {
        FoldReader { size, band in
            let panes = FoldPanes.layout(size: size, band: band, upright: upright)
            PanesLayout(frames: [panes.leading, panes.trailing]) {
                leading(panes.leadingEdges)
                    .environment(\.paneEdges, panes.leadingEdges)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                trailing(panes.trailingEdges)
                    .environment(\.paneEdges, panes.trailingEdges)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The page's size and the fold's band, for a page that lays itself out
/// round the fold. When the band comes or goes the change is animated: the
/// content moves (it is handed the new band inside an animation), or with
/// Reduce Motion on it fades out and back in at its new place.
struct FoldReader<Content: View>: View {
    @ViewBuilder let content: (CGSize, FoldBand) -> Content

    var body: some View {
        GeometryReader { proxy in
            FoldFollower(live: Self.band(proxy)) { band in content(proxy.size, band) }
        }
    }

    /// The fold's band when iOS asks for it to be kept clear (the Duo half
    /// open), in this view's space (iOS 27.1's division region); `.flat` lying
    /// flat or before iOS 27.1.
    static func band(_ proxy: GeometryProxy) -> FoldBand {
        if #available(iOS 27.1, *) {
            return FoldBand(region: proxy.reservedRegions(kind: .division).first { $0.isActive }?.frame)
        }
        return .flat
    }
}

/// Holds the band the content was last laid out for, so a change can be
/// animated rather than jump in the pass that notices it.
private struct FoldFollower<Content: View>: View {
    let live: FoldBand
    @ViewBuilder let content: (FoldBand) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: FoldBand?
    @State private var hidden = false

    var body: some View {
        content(shown ?? live)
            .opacity(hidden ? 0 : 1)
            .onAppear { shown = live }
            .onChange(of: live) { _, band in
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.15)) {
                        hidden = true
                    } completion: {
                        var still = Transaction()
                        still.disablesAnimations = true
                        withTransaction(still) { shown = band }
                        withAnimation(.easeIn(duration: 0.2)) { hidden = false }
                    }
                } else {
                    withAnimation(.smooth(duration: 0.45)) { shown = band }
                }
            }
    }
}

/// Places each subview at its frame (in the container's own space). As real
/// layout, a pane at the page's bottom still scrolls clear of the tab bar,
/// and a change of frames inside an animation moves the panes smoothly.
private struct PanesLayout: Layout {
    var frames: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
