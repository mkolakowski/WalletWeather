#if DEBUG
import SwiftUI

/// Debug only: `WW_DEBUG_FAULTS=1` shows a screen of faults planted on
/// purpose. The simulator walk (`apps/ios/UITests`, #345) has to find every
/// one of them, so a check that has stopped working is noticed rather than
/// trusted. Each line names the check it's for. Never in a Release build.
struct DebugFaults: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Planted faults").font(.headline)
            Text("Optional(\"Rent\")")                                        // leaked-code
            Text("Balance -$0.00")                                           // negative-zero
            Button { } label: { Image(systemName: "chart.bar.doc.horizontal") }  // symbol-name-label
            Button { } label: { Color.gray.frame(width: 20, height: 20) }    // unnamed-control, small-target
            Text("TOTAL DUE THIS MONTH")                                     // all-capitals
            Text("This line hangs off the side of the window").fixedSize()   // off-edge: at the window's
                .frame(maxWidth: .infinity, alignment: .trailing)               // right edge however wide
                .offset(x: 120)                                                 // it is, then past it (#387)
            ZStack(alignment: .leading) {                                    // text-overlap
                Text("One label")
                Text("Another on top of it")
            }
            Text("Paid -$5.00, then $-5.00")                                 // mixed-minus
            Text("Due Nov 12")                                               // mixed-dates
            Text("Due 2026-11-12")
            Text("Too faint to read").foregroundStyle(Color(white: 0.88))    // Apple's audit: contrast
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
#endif
