import Foundation

// The open Duo's two panes (duo-more phase 1, #304): where each pane of a
// two-pane page goes, from the page's size and the fold's band. The app reads
// the band from iOS (`reservedRegions(kind: .division)`, iOS 27.1); this is
// only the arithmetic, so it's tested on the Mac.

/// The fold's band, in the page's own coordinates.
public enum FoldBand: Equatable, Sendable {
    /// Lying flat (or no fold at all): iOS asks for nothing to be kept clear.
    case flat
    /// Half open like a book: the band runs top to bottom.
    case upright(CGRect)
    /// Half open like a laptop: the band runs across.
    case across(CGRect)

    /// From the active division region iOS reports, if any: taller than wide
    /// is upright, wider than tall is across.
    public init(region: CGRect?) {
        guard let region, !region.isEmpty else { self = .flat; return }
        self = region.width > region.height ? .across(region) : .upright(region)
    }

    /// Half open like a book.
    public var isUpright: Bool {
        if case .upright = self { return true }
        return false
    }
}

/// The two panes' frames in the page, and the inner edges each pane's content
/// keeps from its own sides.
public struct FoldPanes: Equatable, Sendable {
    public enum Arrangement: Equatable, Sendable {
        case sideBySide
        case stacked
    }

    /// Which pane stands up (goes on top) when the panes stack.
    public enum Upright: Equatable, Sendable {
        case leading
        case trailing
    }

    /// How far a pane's content keeps from the pane's leading and trailing sides.
    public struct Edges: Equatable, Sendable {
        public var leading: CGFloat
        public var trailing: CGFloat

        public init(leading: CGFloat, trailing: CGFloat) {
            self.leading = leading
            self.trailing = trailing
        }

        /// One column, or a pane with the page's edge on both sides.
        public static let plain = Edges(leading: FoldPanes.outer, trailing: FoldPanes.outer)
    }

    /// From the page's own edge.
    public static let outer: CGFloat = 16
    /// Either side of the page's middle when the Duo lies flat (as before #304).
    public static let middle: CGFloat = 28
    /// From the fold's band when the Duo is half open like a book.
    public static let besideBand: CGFloat = 12
    /// A pane narrower (or shorter) than this means the band isn't really in
    /// this page (a page inside one pane): the page lays out as if flat.
    public static let smallestPane: CGFloat = 120

    public var arrangement: Arrangement
    /// The left pane side by side; above or below when stacked, as `Upright` says.
    public var leading: CGRect
    public var trailing: CGRect
    public var leadingEdges: Edges
    public var trailingEdges: Edges

    public init(arrangement: Arrangement, leading: CGRect, trailing: CGRect,
                leadingEdges: Edges, trailingEdges: Edges) {
        self.arrangement = arrangement
        self.leading = leading
        self.trailing = trailing
        self.leadingEdges = leadingEdges
        self.trailingEdges = trailingEdges
    }

    /// Lying flat: two equal halves, 28 points either side of the middle.
    /// Half open like a book: the left pane ends where the band starts and
    /// the right one starts where it ends. Half open like a laptop: stacked,
    /// one pane above the band and the other below it.
    public static func layout(size: CGSize, band: FoldBand, upright: Upright = .leading) -> FoldPanes {
        let width = max(0, size.width), height = max(0, size.height)
        switch band {
        case let .upright(region)
            where region.minX >= smallestPane && width - region.maxX >= smallestPane:
            return FoldPanes(
                arrangement: .sideBySide,
                leading: CGRect(x: 0, y: 0, width: region.minX, height: height),
                trailing: CGRect(x: region.maxX, y: 0, width: width - region.maxX, height: height),
                leadingEdges: Edges(leading: outer, trailing: besideBand),
                trailingEdges: Edges(leading: besideBand, trailing: outer))
        case let .across(region)
            where region.minY >= smallestPane && height - region.maxY >= smallestPane:
            let top = CGRect(x: 0, y: 0, width: width, height: region.minY)
            let bottom = CGRect(x: 0, y: region.maxY, width: width, height: height - region.maxY)
            return FoldPanes(
                arrangement: .stacked,
                leading: upright == .leading ? top : bottom,
                trailing: upright == .leading ? bottom : top,
                leadingEdges: .plain, trailingEdges: .plain)
        default:
            let half = width / 2
            return FoldPanes(
                arrangement: .sideBySide,
                leading: CGRect(x: 0, y: 0, width: half, height: height),
                trailing: CGRect(x: half, y: 0, width: width - half, height: height),
                leadingEdges: Edges(leading: outer, trailing: middle),
                trailingEdges: Edges(leading: middle, trailing: outer))
        }
    }

    /// Side by side: the room between the two panes' content (the band or
    /// the middle, with each pane's inner edge). Compare keeps its two
    /// columns this far apart so they scroll together.
    public var gap: CGFloat {
        leadingEdges.trailing + max(0, trailing.minX - leading.maxX) + trailingEdges.leading
    }
}
