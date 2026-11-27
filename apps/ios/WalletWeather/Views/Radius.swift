import SwiftUI

/// The app's four corner radii (decided 2026-11-26, #369): twelve sizes were
/// in use, 6 to 24, where four read as one design. Every rounded shape takes
/// one of these; the source check fails a number written in its place.
enum Radius {
    /// A page's card, and what sits over one at full size (a drop target, a preview of a page).
    static let card: CGFloat = 22
    /// A bar or a banner that floats (Undo, problems, a camera's hint), and a tile in a bar's style.
    static let bar: CGFloat = 14
    /// A row, a field, a chosen row's highlight, a calendar day.
    static let row: CGFloat = 10
    /// A small tile or swatch.
    static let tile: CGFloat = 6
}
