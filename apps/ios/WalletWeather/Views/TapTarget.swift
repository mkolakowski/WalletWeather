import SwiftUI

extension View {
    /// A control whose tappable area is at least 44 × 44 points, whatever its
    /// label measures (Apple's minimum; #361). The look is unchanged: the
    /// label stays where it is, the area around it takes the tap.
    func tapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
    }
}
