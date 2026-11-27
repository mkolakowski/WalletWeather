import SwiftUI
import UniformTypeIdentifiers
import WalletWeatherKit

/// Drag and drop (#308). A bank's CSV dropped on Forecast or the Dashboard
/// opens Import a CSV on that file, on the account the page shows. A line
/// you added, dragged from Forecast or the Calendar's lists (in this window
/// or another WalletWeather window), dropped on a Calendar day moves its
/// planned date, with Undo. Nothing changes on a page while nothing is
/// being dragged over it.

/// Sent through `AppModel.lastLineMove` when a drop moved a line.
struct LineMove: Equatable {
    let id = UUID()
    let transactionId: Int
}

// MARK: - The highlight

/// What a page or a day shows while something it takes hovers over it: an
/// outlined, tinted overlay. It takes no room and no touches.
struct DropHighlight: View {
    let label: String
    let systemImage: String

    var body: some View {
        ZStack {
            // Frosted, so the outline reads as a drop zone rather than
            // lines drawn through the figures under it.
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.accent.opacity(0.10))
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            Label(label, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
        }
        .padding(8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - A dropped CSV

extension View {
    /// Takes a bank's CSV dropped on the page, when `enabled` (the page's
    /// Import a CSV is offered: an account this person may change), and
    /// opens the import sheet on it, starting on `account`. Anything else is
    /// refused. `WW_DEBUG_DROP=csv` (Debug) shows the highlight with nothing
    /// dragged, for a picture.
    func csvDropTarget(enabled: Bool, account: Int?, onImported: @escaping () async -> Void) -> some View {
        modifier(CSVDropTarget(enabled: enabled, account: account, onImported: onImported))
    }
}

private struct CSVDropTarget: ViewModifier {
    let enabled: Bool
    let account: Int?
    let onImported: () async -> Void
    @State private var targeted = false
    @State private var file: CSVFile?
    @State private var problem: String?

    private var highlighted: Bool { enabled && (targeted || AppModel.debugSetting("WW_DEBUG_DROP") == "csv") }

    func body(content: Content) -> some View {
        content
            // Always attached, so the page's views keep who they are; a page
            // that can't import refuses every drop.
            .onDrop(of: CSVDropDelegate.types,
                    delegate: CSVDropDelegate(enabled: enabled, targeted: $targeted, onFile: { file = $0 },
                                              onProblem: { problem = $0 }))
            .overlay {
                if highlighted { DropHighlight(label: "Drop to import", systemImage: "doc.text") }
            }
            .animation(.snappy, value: highlighted)
            .sheet(item: $file) { CSVImportSheet(file: $0, startAccount: account, onImported: onImported) }
            .alert("Couldn't open the file", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {  // ui-check: allow alert — a dropped file that couldn't be opened, with no editor to show it in
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
    }
}

private struct CSVDropDelegate: DropDelegate {
    /// Wide enough to hear about files and text; `CSVDrop` decides.
    static let types: [UTType] = [.commaSeparatedText, .text, .data]

    let enabled: Bool
    @Binding var targeted: Bool
    let onFile: (CSVFile) -> Void
    let onProblem: (String) -> Void

    /// The first dropped item that is a CSV, and the type to read it as.
    private func csv(_ info: DropInfo) -> (provider: NSItemProvider, type: String)? {
        guard enabled else { return nil }
        for provider in info.itemProviders(for: Self.types) {
            if let type = CSVDrop.typeToRead(provider.registeredTypeIdentifiers, name: provider.suggestedName) {
                return (provider, type)
            }
        }
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool { csv(info) != nil }

    func dropEntered(info: DropInfo) { targeted = csv(info) != nil }

    func dropExited(info: DropInfo) { targeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: csv(info) != nil ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        guard let (provider, type) = csv(info) else { return false }
        let name = CSVDrop.fileName(provider.suggestedName)
        let onFile = onFile, onProblem = onProblem
        Task {
            if let data = await Self.data(provider, type: type), let file = CSVFile.read(data, name: name) {
                onFile(file)
            } else {
                onProblem("That file couldn't be read.")
            }
        }
        return true
    }

    private static func data(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
        }
    }
}

// MARK: - A dragged line

extension View {
    /// The row can be dragged onto a Calendar day when `drag` is a line
    /// whose date can move (`LineDrag`); otherwise it's left as it is.
    @ViewBuilder
    func lineDrag(_ drag: LineDrag?) -> some View {
        if let drag {
            draggable(drag) { LineDragPreview(drag: drag) }
        } else {
            self
        }
    }
}

/// What travels under the finger: the line's name and its date now.
private struct LineDragPreview: View {
    let drag: LineDrag

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(drag.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Planned for \(drag.plannedOn.short)").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "calendar").foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.row ?? Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.bar, style: .continuous))
    }
}

/// A Calendar month that takes dropped lines: what a drop on a day does
/// (true when it's taken), and a day to show highlighted for a picture
/// (`WW_DEBUG_DROP=day`).
struct DayDrop {
    let debugDay: LocalDay?
    let onDrop: (LineDrag, LocalDay) -> Bool
}

/// One day of the month as a drop target; `hovered` is the day a line is
/// over now, which the day's cell highlights.
struct DayDropTarget: ViewModifier {
    let day: LocalDay
    let drop: DayDrop?
    @Binding var hovered: LocalDay?

    func body(content: Content) -> some View {
        if let drop {
            content
                .dropDestination(for: LineDrag.self) { items, _ in
                    hovered = nil
                    guard let item = items.first else { return false }
                    return drop.onDrop(item, day)
                } isTargeted: { over in
                    if over { hovered = day } else if hovered == day { hovered = nil }
                }
        } else {
            content
        }
    }
}
