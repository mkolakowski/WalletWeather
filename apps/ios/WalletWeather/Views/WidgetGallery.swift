import SwiftUI
import WalletWeatherKit
import WidgetKit

#if DEBUG
/// Debug only (#318): the widgets' own faces (`Widgets/Views.swift`, built
/// into the app for this) at each size, for pictures from the command line,
/// since nothing there can add a widget to the Home Screen.
/// `WW_DEBUG_WIDGETS=amounts|applock|locked|nothing` picks what they show:
/// the connection in front's summary as written (or made-up numbers when it
/// has none), with the app lock on, as a locked phone redacts them, or as a
/// server set to keep Nothing.
struct WidgetGallery: View {
    let mode: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var summary: ConnectionSummary {
        if let id = model.saved?.id, case let .found(found)? = SummaryStore.shared?.read(id), found.keepsNumbers {
            return found
        }
        return SummaryEntry.sampleSummary
    }

    private var entry: SummaryEntry {
        let content: WidgetContent
        switch mode {
        case "applock": content = .summary(summary, amountsHidden: true)
        case "nothing": content = .keepsNothing(name: "Mum & Dad")
        default: content = .summary(summary, amountsHidden: false)
        }
        return SummaryEntry(date: .appNow, connection: summary.id, content: content, account: summary.accounts.first?.id)
    }

    private var title: String {
        switch mode {
        case "applock": "With the app lock on"
        case "locked": "On a locked phone"
        case "nothing": "A server set to keep Nothing"
        default: "With amounts"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kind("Balance") { BalanceView(entry: entry, shownFamily: $0) }
                    kind("Next bills") { NextBillsView(entry: entry, shownFamily: $0) }
                    kind("To confirm") { ToConfirmView(entry: entry, shownFamily: $0) }
                }
                .padding()
                // A locked phone redacts what's privacy-sensitive.
                .redacted(reason: mode == "locked" ? .privacy : [])
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func kind(_ name: String, @ViewBuilder face: @escaping (WidgetFamily) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            HStack(alignment: .top, spacing: 12) {
                home(face(.systemSmall), width: 170)
                home(face(.systemMedium), width: 364)
            }
            HStack(alignment: .top, spacing: 12) {
                lock(face(.accessoryRectangular), width: 172, height: 76)
                lock(face(.accessoryCircular), width: 76, height: 76).clipShape(Circle())
                lock(face(.accessoryInline), width: 257, height: 26)
            }
        }
    }

    private func home(_ face: some View, width: CGFloat) -> some View {
        face.padding(16).frame(width: width, height: 170)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func lock(_ face: some View, width: CGFloat, height: CGFloat) -> some View {
        face.padding(4).frame(width: width, height: height)
            .foregroundStyle(.white)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
#endif
