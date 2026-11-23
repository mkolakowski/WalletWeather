import SwiftUI
import WalletWeatherKit

/// A page's month, as its name with a small chevron: tap for a menu that
/// jumps straight to This month, the months either side of the one shown, or
/// any of the six ahead and behind (#313). The arrows beside it stay.
struct MonthMenu: View {
    let month: YearMonth
    var font: Font = .headline
    let onPick: (YearMonth) -> Void

    var body: some View {
        let today = LocalDay.today()
        let isThisMonth = month == YearMonth(today)
        let choices = MonthMenuChoices(shown: month, today: today)
        Menu {
            Button {
                onPick(YearMonth(today))
            } label: {
                if isThisMonth {
                    Label("This month", systemImage: "checkmark")
                } else {
                    Text("This month")
                }
            }
            .disabled(isThisMonth)
            Section {
                ForEach(choices.neighbours, id: \.self) { item($0) }
            }
            Section {
                ForEach(choices.ahead, id: \.self) { item($0) }
            }
            Section {
                ForEach(choices.behind, id: \.self) { item($0) }
            }
        } label: {
            HStack(spacing: 4) {
                // Past the default sizes it wraps between the month and the
                // year, never inside a word (#311).
                Text(month.label).font(font)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("\(month.label). Choose a month")
    }

    private func item(_ target: YearMonth) -> some View {
        Button(target.label) { onPick(target) }
    }
}

/// The month with Previous and Next either side, as Forecast, the Calendar
/// and Compare show it. At the accessibility text sizes the arrows move to a
/// row of their own under the month, so the month has the whole width and
/// its name never breaks inside a word (#311).
struct MonthBar: View {
    let month: YearMonth
    var font: Font = .headline
    let onMove: (Int) -> Void
    let onPick: (YearMonth) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    MonthMenu(month: month, font: font, onPick: onPick)
                        .frame(maxWidth: .infinity)
                    HStack {
                        previous
                        Spacer()
                        next
                    }
                }
            } else {
                HStack {
                    previous
                    Spacer()
                    MonthMenu(month: month, font: font, onPick: onPick)
                    Spacer()
                    next
                }
            }
        }
        .buttonStyle(.glass)
    }

    private var previous: some View {
        Button("Previous month", systemImage: "chevron.left") { onMove(-1) }
            .labelStyle(.iconOnly)
    }

    private var next: some View {
        Button("Next month", systemImage: "chevron.right") { onMove(1) }
            .labelStyle(.iconOnly)
    }
}
