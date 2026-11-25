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

extension EnvironmentValues {
    /// The page's name, for `FoldLayout` to show at the top of its panes on
    /// the open Duo (#341); nil on the phone and on a page pushed from Settings.
    @Entry var paneTitle: String?
    /// This pane shows the page's title capsule at its top left (#341): its
    /// first lines sit in the soft blur under it unless they keep clear
    /// (#385).
    @Entry var paneUnderTitle = false
}

extension View {
    /// The page's name (#341). On the phone, the large title as before. On
    /// the open Duo, a small glass capsule fixed at the top left, in place of
    /// the navigation bar's title row: that row came and went as the pane it
    /// followed scrolled, and moved the other pane with it (#340). Cards
    /// scroll under the capsule and fade into a soft blur at each pane's own
    /// top edge (`FoldLayout`'s pane tops). A page pushed from Settings keeps
    /// its bar, which holds Back.
    func pageTitle(_ title: String) -> some View { modifier(PageTitle(title: title)) }
}

private struct PageTitle: ViewModifier {
    let title: String
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.embeddedPage) private var embedded
    /// Whether two panes show the capsule themselves; until then (loading,
    /// a problem, no accounts yet) the page shows it over its whole width.
    @State private var panesShowIt = false

    func body(content: Content) -> some View {
        if sizeClass == .regular && !embedded {
            content
                .environment(\.paneTitle, title)
                .onPreferenceChange(PanesShowTitle.self) { panesShowIt = $0 }
                .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                    if !panesShowIt { TitleCapsule(title: title, edges: .plain) }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                // The bar stays: its items (new window, +, …) show in the side
                // bar's top group. Only its title row goes, and its background.
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .automatic)
        }
    }
}

/// Set by `FoldLayout` when its panes show the page's name.
private struct PanesShowTitle: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The page's name in a small Liquid Glass capsule, lined up with the
/// content below it.
private struct TitleCapsule: View {
    let title: String
    let edges: FoldPanes.Edges

    var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, edges.leading)
            .padding(.bottom, 8)
    }
}

/// A pane's own top bar on the open Duo (#341), so the pane's cards fade
/// into a soft blur at its own top edge as they scroll. Every pane at the
/// page's top gets one of the same height, so they start level and neither
/// moves when the other scrolls; the capsule shows in the one at the top
/// left. A pane lower down (half open like a laptop) has nothing above it.
private struct PaneTop: ViewModifier {
    let title: String?
    let frame: CGRect
    let edges: FoldPanes.Edges

    func body(content: Content) -> some View {
        let atTop = title != nil && frame.minY < 1
        content
            .environment(\.paneUnderTitle, atTop && frame.minX < 1)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                if let title, atTop {
                    TitleCapsule(title: title, edges: edges)
                        .opacity(frame.minX < 1 ? 1 : 0)
                        .accessibilityHidden(frame.minX >= 1)
                }
            }
    }
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
    @Environment(\.paneTitle) private var title

    var body: some View {
        FoldReader { size, band in
            let panes = FoldPanes.layout(size: size, band: band, upright: upright)
            PanesLayout(frames: [panes.leading, panes.trailing]) {
                leading(panes.leadingEdges)
                    .environment(\.paneEdges, panes.leadingEdges)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(PaneTop(title: title, frame: panes.leading, edges: panes.leadingEdges))
                trailing(panes.trailingEdges)
                    .environment(\.paneEdges, panes.trailingEdges)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(PaneTop(title: title, frame: panes.trailing, edges: panes.trailingEdges))
            }
        }
        .preference(key: PanesShowTitle.self, value: title != nil)
        #if DEBUG
        .task { await DebugPaneScroll.run() }
        #endif
    }
}

#if DEBUG
/// Debug only: `WW_DEBUG_PANE_SCROLL=leading` (or `trailing`) scrolls that
/// pane down 240 points a moment after the page shows, as a swipe would,
/// since a script can't swipe (#340).
private enum DebugPaneScroll {
    @MainActor static func run() async {
        guard let pane = AppModel.debugSetting("WW_DEBUG_PANE_SCROLL") else { return }
        try? await Task.sleep(for: .seconds(2))
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        let middle = window.bounds.midX
        for scroll in scrollViews(in: window) where scroll.bounds.height > 200 {
            let frame = scroll.convert(scroll.bounds, to: window)
            guard (pane == "leading") == (frame.midX < middle) else { continue }
            var offset = scroll.contentOffset
            offset.y += 240
            scroll.setContentOffset(offset, animated: true)
        }
    }

    @MainActor private static func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}
#endif

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
