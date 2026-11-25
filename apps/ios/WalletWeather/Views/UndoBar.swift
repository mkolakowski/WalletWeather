import SwiftUI

// An Undo for a few seconds after something is done from a list (#315): the
// Forecast's Paid, and the Calendar's (#305).

/// What the bar offers: what was done, and the way to take it back.
struct UndoOffer: Identifiable {
    let id = UUID()
    /// "Rent marked paid".
    let message: String
    /// Takes it back; true when that went through. It reports its own
    /// failure (the page's problem alert), so the bar only needs to
    /// know whether to give the lighter haptic.
    let undo: @MainActor () async -> Bool
    /// Stays until dismissed: a Debug launch setting shows it for a picture.
    var stays = false
}

/// The bar itself: what happened and an Undo button, in glass.
struct UndoBar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        // Side by side up to the default size; at larger sizes the message
        // has the whole width and Undo sits under it, so it's never cut (#362).
        FitsAcross {
            HStack(spacing: 10) {
                what
                Spacer(minLength: 0)
                undo
            }
        } stacked: {
            VStack(alignment: .leading, spacing: 8) {
                what
                undo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var what: some View {
        Label {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text ?? Color.primary)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
        }
    }

    private var undo: some View {
        Button("Undo", action: onUndo)
            .buttonStyle(.glass)
            .tint(Palette.accent)
            .accessibilityHint("Takes it back")
    }
}

extension View {
    /// The Undo bar along the bottom of a page, for as long as `offer` holds
    /// one (about five seconds; fifteen with VoiceOver running). A new offer
    /// replaces the one showing, and the page sets it to nil to dismiss it.
    func undoBar(_ offer: Binding<UndoOffer?>) -> some View {
        modifier(UndoBarModifier(offer: offer))
    }
}

private struct UndoBarModifier: ViewModifier {
    @Binding var offer: UndoOffer?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var undoneCount = 0

    func body(content: Content) -> some View {
        content
            // Clear of a tab bar along the bottom, like the kept bar at the top.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let current = offer {
                    UndoBar(message: current.message) { undo(current) }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: offer?.id)
            .task(id: offer?.id) {
                guard let current = offer, !current.stays else { return }
                try? await Task.sleep(for: .seconds(voiceOver ? 15 : 5))
                if !Task.isCancelled { offer = nil }
            }
            .onChange(of: offer?.id) { _, id in
                guard id != nil, let message = offer?.message else { return }
                AccessibilityNotification.Announcement("\(message). Undo is available.").post()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: undoneCount)
    }

    private func undo(_ current: UndoOffer) {
        offer = nil
        Task {
            if await current.undo() { undoneCount += 1 }
        }
    }
}
