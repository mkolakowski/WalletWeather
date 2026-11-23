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
                Text(month.label).font(font)
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
