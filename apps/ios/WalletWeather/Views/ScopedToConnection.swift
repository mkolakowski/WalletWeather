import SwiftUI
import WalletWeatherKit

/// Keeps a page's choice in a window (its account, in `@SceneStorage`) with
/// the connection it was made on (Plans/connections.md, #299): when another
/// connection comes in front, the value is put away in `memo` (a second
/// scene-storage key beside the page's own) and that connection's own comes
/// back, or none. So one server's account id is never read as another's,
/// and a window coming back to a connection finds its choice again.
struct ScopedToConnection: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var value: Int
    @Binding var memo: String

    func body(content: Content) -> some View {
        content.onChange(of: model.connectionKey, initial: true) { _, key in
            var choice = ChoicePerConnection(memo)
            var moved = value
            choice.move(&moved, to: key)
            if moved != value { value = moved }
            if choice.text != memo { memo = choice.text }
        }
    }
}

extension View {
    func scopedToConnection(_ value: Binding<Int>, memo: Binding<String>) -> some View {
        modifier(ScopedToConnection(value: value, memo: memo))
    }
}
