import SwiftUI
import WalletWeatherKit

// Getting started (#175): a card on the Dashboard with things worth doing
// once, and the guided sheet for its first task, the tab bar.

/// The card at the top of the Dashboard: each task with a tick once done,
/// and a close button. It goes for good once every task is done or it's
/// closed.
struct GettingStartedCard: View {
    @Environment(AppSettings.self) private var settings
    let open: (StartTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Getting started").font(.headline)
                    Text(settings.start.left.count == 1 ? "One thing to try" : "\(settings.start.left.count) things to try")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { settings.start.dismissed = true }
                } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Getting started")
            }
            ForEach(StartTask.allCases) { task in
                let done = settings.start.done.contains(task)
                Button { open(task) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : task.symbol)
                            .font(.title3)
                            .foregroundStyle(done ? Palette.good : Palette.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).strikethrough(done)
                            Text(task.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

/// Make the tab bar yours: what the bar is, a picture of it that follows
/// each swap, and a row per place in it with Swap (or Add for an empty
/// place). Nothing changes until Save, which also ticks the task; Settings
/// → Tab bar does the same and can reorder.
struct TabBarTour: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [TabPage] = []
    @State private var lastChanged: TabPage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The bar at the bottom holds \(TabPage.maxInBar) pages, beside Settings and Search. Put the ones you use most there: swap any of them for Calendar, Net worth, Budgets or Reports.")

                    BarPreview(pages: draft, highlighted: lastChanged)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<TabPage.maxInBar, id: \.self) { place in
                            if place > 0 { Divider() }
                            row(at: place)
                        }
                    }
                    .card()

                    Text("Pages left out stay one tap away, at the top of Settings. You can change the bar again, and its order, in Settings → Tab bar.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle("Your tab bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft != settings.tabs { settings.tabs = draft }
                        settings.start.done.insert(.tabBar)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = settings.tabs }
    }

    /// One place in the bar: its page and Swap, or Add while it's empty.
    @ViewBuilder
    private func row(at place: Int) -> some View {
        let others = TabPage.notIn(draft)
        HStack(spacing: 8) {
            Text("\(place + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
            if place < draft.count {
                let page = draft[place]
                Label(page.title, systemImage: page.symbol)
                Spacer(minLength: 8)
                Menu {
                    ForEach(others) { other in
                        Button(other.title, systemImage: other.symbol) { change { draft = TabPage.swapping(page, for: other, in: draft) }; lastChanged = other }
                    }
                } label: {
                    Text("Swap").foregroundStyle(Palette.accent)
                }
                .accessibilityLabel("Swap \(page.title) for another page")
            } else {
                Text("Empty").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(others) { other in
                        Button(other.title, systemImage: other.symbol) { change { draft.append(other) }; lastChanged = other }
                    }
                } label: {
                    Text("Add").foregroundStyle(Palette.accent)
                }
                .disabled(place != draft.count)
            }
        }
        .frame(minHeight: 44)
    }

    private func change(_ body: () -> Void) {
        withAnimation(.snappy) { body() }
    }
}

/// A picture of the tab bar: the chosen pages, then Settings and Search
/// (always there, so a little fainter). The page just swapped in is lit.
private struct BarPreview: View {
    let pages: [TabPage]
    let highlighted: TabPage?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages) { page in
                item(page.title, page.symbol, lit: page == highlighted)
                    .transition(.scale.combined(with: .opacity))
            }
            item("Settings", "gearshape", lit: false).opacity(0.55)
            item("Search", "magnifyingglass", lit: false).opacity(0.55)
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The tab bar: \((pages.map(\.title) + ["Settings", "Search"]).joined(separator: ", "))")
    }

    private func item(_ title: String, _ symbol: String, lit: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(lit ? Palette.accent : .primary)
        .scaleEffect(lit ? 1.08 : 1)
        .frame(maxWidth: .infinity)
    }
}
