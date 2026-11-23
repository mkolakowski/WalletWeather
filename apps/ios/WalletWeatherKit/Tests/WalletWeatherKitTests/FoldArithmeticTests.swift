import Foundation
import Testing
@testable import WalletWeatherKit

/// The open Duo's two panes (#304), with the numbers the Duo simulator
/// reported on 2026-11-23: open on its side the page is 867 x 495 (the tab
/// bar down the right), open upright 669 x 660.
struct FoldArithmeticTests {
    @Test func theRegionIsUprightOrAcross() {
        #expect(FoldBand(region: nil) == .flat)
        #expect(FoldBand(region: .zero) == .flat)
        let book = CGRect(x: 455.5, y: -140, width: 40, height: 669)
        #expect(FoldBand(region: book) == .upright(book))
        #expect(FoldBand(region: book).isUpright)
        let laptop = CGRect(x: 0, y: 247.5, width: 669, height: 40)
        #expect(FoldBand(region: laptop) == .across(laptop))
        #expect(!FoldBand(region: laptop).isUpright && !FoldBand.flat.isUpright)
    }

    @Test func flatIsTwoHalvesAsBefore() {
        let panes = FoldPanes.layout(size: CGSize(width: 867, height: 495), band: .flat)
        #expect(panes.arrangement == .sideBySide)
        #expect(panes.leading == CGRect(x: 0, y: 0, width: 433.5, height: 495))
        #expect(panes.trailing == CGRect(x: 433.5, y: 0, width: 433.5, height: 495))
        // 16 at the page's edges, 28 either side of the middle: today's paddings.
        #expect(panes.leadingEdges == FoldPanes.Edges(leading: 16, trailing: 28))
        #expect(panes.trailingEdges == FoldPanes.Edges(leading: 28, trailing: 16))
        #expect(panes.gap == 56)
        // Which pane stands up only matters when stacked.
        #expect(FoldPanes.layout(size: CGSize(width: 867, height: 495), band: .flat, upright: .trailing) == panes)
    }

    @Test func halfOpenLikeABookKeepsOffTheBand() {
        let band = FoldBand(region: CGRect(x: 455.5, y: -140, width: 40, height: 669))
        let panes = FoldPanes.layout(size: CGSize(width: 867, height: 495), band: band)
        #expect(panes.arrangement == .sideBySide)
        #expect(panes.leading == CGRect(x: 0, y: 0, width: 455.5, height: 495))
        #expect(panes.trailing == CGRect(x: 495.5, y: 0, width: 371.5, height: 495))
        #expect(panes.leading.maxX == 455.5 && panes.trailing.minX == 495.5)
        #expect(panes.leadingEdges.trailing == FoldPanes.besideBand)
        #expect(panes.trailingEdges.leading == FoldPanes.besideBand)
        #expect(panes.gap == 64)
    }

    @Test func halfOpenLikeALaptopStacks() {
        let band = FoldBand(region: CGRect(x: 0, y: 247.5, width: 669, height: 40))
        let size = CGSize(width: 669, height: 660)
        let panes = FoldPanes.layout(size: size, band: band)
        #expect(panes.arrangement == .stacked)
        #expect(panes.leading == CGRect(x: 0, y: 0, width: 669, height: 247.5))
        #expect(panes.trailing == CGRect(x: 0, y: 287.5, width: 669, height: 372.5))
        #expect(panes.leadingEdges == .plain && panes.trailingEdges == .plain)

        // The Dashboard: its right pane (the charts) stands up.
        let dashboard = FoldPanes.layout(size: size, band: band, upright: .trailing)
        #expect(dashboard.trailing == CGRect(x: 0, y: 0, width: 669, height: 247.5))
        #expect(dashboard.leading == CGRect(x: 0, y: 287.5, width: 669, height: 372.5))
    }

    /// A page inside one pane (Search's right half) finds the band at or past
    /// its edge, and lays out as if flat.
    @Test func aBandOutsideThePageIsIgnored() {
        let size = CGSize(width: 371.5, height: 495)
        let flat = FoldPanes.layout(size: size, band: .flat)
        #expect(FoldPanes.layout(size: size, band: .upright(CGRect(x: -40, y: -140, width: 40, height: 669))) == flat)
        let below = CGSize(width: 669, height: 372.5)
        #expect(FoldPanes.layout(size: below, band: .across(CGRect(x: 0, y: -40, width: 669, height: 40)))
                == FoldPanes.layout(size: below, band: .flat))
    }
}
