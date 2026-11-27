import SwiftUI
import WalletWeatherKit

// Getting started (#175): a card on the Dashboard with things worth doing
// once, and a sheet for each task: the tab bar (#175), then the lock, the
// look, marking a bill paid and Search (#177).

/// The card at the top of the Dashboard: each task with a tick once done,
/// and a close button. It goes for good once every task is done or it's
/// closed.
struct GettingStartedCard: View {
    @Environment(AppSettings.self) private var settings
    let open: (StartTask) -> Void
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .footnote) private var closeSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Getting started").font(.headline)
                    let left = settings.start.left(among: settings.startTasks, alsoDone: settings.startAlsoDone).count
                    Text(left == 1 ? "One thing to try" : "\(left) things to try")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { settings.start.dismissed = true }
                } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: closeSize, height: closeSize).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Getting started")
            }
            ForEach(settings.startTasks) { task in
                let done = settings.start.isDone(task, alsoDone: settings.startAlsoDone)
                Button { open(task) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : task.symbol)
                            .font(.title3)
                            .foregroundStyle(done ? Palette.good : Palette.accent)
                            .frame(width: symbolWidth)
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
    // Grows with the text size, exactly as before at Large (#311).
    @ScaledMetric(relativeTo: .footnote) private var placeWidth: CGFloat = 18
    @Environment(\.barOnSide) private var barOnSide
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [TabPage] = []
    @State private var lastChanged: TabPage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(barOnSide
                         ? "The tab bar down the side holds \(TabPage.maxInBar) pages here, beside Settings and Search (\(TabPage.maxAtBottom) along the bottom or on a short screen). Put the ones you use most there: swap any of them for another page."
                         : "The bar at the bottom holds \(TabPage.maxAtBottom) pages, beside Settings and Search. Put the ones you use most there: swap any of them for another page.")

                    BarPreview(pages: TabPage.shown(draft, onSide: barOnSide), highlighted: lastChanged)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<max(TabPage.room(onSide: barOnSide), draft.count), id: \.self) { place in
                            if place > 0 { Divider() }
                            row(at: place)
                        }
                    }
                    .card()

                    Text("Pages left out stay one tap away, under More pages in Settings. You can change the bar again, and its order, in Settings → Tab bar.")
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
            Text("\(place + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: placeWidth)
            if place < draft.count {
                let page = draft[place]
                VStack(alignment: .leading, spacing: 2) {
                    Label(page.title, systemImage: page.symbol)
                    if place >= TabPage.room(onSide: barOnSide) {
                        Text("Shows when the bar has room: down the side of a tall screen").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(others) { other in
                        Button(other.title, systemImage: other.symbol) { change { draft = TabPage.swapping(page, for: other, in: draft) }; lastChanged = other }
                    }
                } label: {
                    Text("Swap")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityLabel("Swap \(page.title) for another page")
            } else {
                Text("Empty").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    ForEach(others) { other in
                        Button(other.title, systemImage: other.symbol) { change { draft.append(other) }; lastChanged = other }
                    }
                } label: {
                    Text("Add")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pages: [TabPage]
    let highlighted: TabPage?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages) { page in
                item(page.title, page.symbol, lit: page == highlighted)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
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

/// The sheet for a Getting started task, from its row on the card.
struct StartTaskSheet: View {
    let task: StartTask

    var body: some View {
        switch task {
        case .tabBar: TabBarTour()
        case .lock: LockTaskSheet()
        case .look: LookTaskSheet()
        case .markPaid: MarkPaidTaskSheet()
        case .search: SearchTaskSheet()
        }
    }
}

/// A task's sheet: a few lines of what it's for, then its controls, with
/// Done in the corner.
private struct TaskSheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Lock the app: the same switch as Settings → Privacy & lock. Turning it on
/// asks for Face ID once, and ticks the task.
private struct LockTaskSheet: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let biometry = settings.biometryName ?? "Face ID"
        TaskSheetFrame(title: "Lock the app") {
            Text("With the lock on, WalletWeather asks for \(biometry) when it opens, and when you come back after a minute away. The numbers are hidden in the app switcher either way.")
            Toggle("Lock with \(biometry)", isOn: Binding(
                get: { settings.lockEnabled },
                set: { on in Task { await settings.setLock(on) } }))
                .padding(.vertical, 6)
                .card()
            Text("You can change this any time in Settings.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
}

/// Choose a look: every look as a tile, applied as it's picked. Keep this look
/// ticks the task, Match this iPhone included.
private struct LookTaskSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TaskSheetFrame(title: "Choose a look") {
            Text("Pick one and the app changes straight away. Match the web app uses the theme you chose in the web app's Settings.")
            LookGrid()
            Button {
                settings.start.done.insert(.look)
                dismiss()
            } label: {
                Text("Keep this look").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            Text("You can change it any time in Settings → Appearance.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
}

/// Mark a bill paid: what To confirm is, then Forecast opened on it: in its
/// tab when Forecast is in the bar, otherwise inside this sheet. The task
/// ticks the first time a line is marked paid.
private struct MarkPaidTaskSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.barOnSide) private var barOnSide
    @Environment(\.openPlace) private var openPlace
    @Environment(\.dismiss) private var dismiss
    @SceneStorage("forecast.confirming") private var confirming = false

    var body: some View {
        TaskSheetFrame(title: "Mark a bill paid") {
            Text("Forecast's **To confirm** list holds the bills and income due up to today that haven't been marked yet. When one has gone through your bank:")
            VStack(alignment: .leading, spacing: 10) {
                Label("Tap Paid as planned, or swipe the line to the right.", systemImage: "hand.draw")
                Label("Or type what it really came to beside it, and tap Paid.", systemImage: "keyboard")
            }
            .card()
            if TabPage.shown(settings.tabs, onSide: barOnSide).contains(.forecast) {
                Button {
                    confirming = true
                    dismiss()
                    openPlace(.forecast)
                } label: {
                    Text("Open To confirm").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            } else {
                NavigationLink {
                    TabPage.forecast.view(embedded: true)
                } label: {
                    Text("Open To confirm").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .simultaneousGesture(TapGesture().onEnded { confirming = true })
            }
            Text("Only people who can change an account see To confirm.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
}

/// Try Search: what it finds, then the Search tab.
private struct SearchTaskSheet: View {
    @Environment(\.openPlace) private var openPlace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TaskSheetFrame(title: "Try Search") {
            Text("The magnifying glass at the end of the tab bar searches everything on every account you can see:")
            VStack(alignment: .leading, spacing: 10) {
                Label("Transactions, and bills and income", systemImage: "arrow.left.arrow.right")
                Label("Accounts, categories and tags", systemImage: "tag")
                Label("Saved reports", systemImage: "doc.text.magnifyingglass")
            }
            .card()
            Text("Tap a result to open it: a transaction or bill in its editor, an account in Forecast, a category or tag as its transactions.")
            Button {
                dismiss()
                openPlace(.search)
            } label: {
                Text("Search now").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
    }
}
