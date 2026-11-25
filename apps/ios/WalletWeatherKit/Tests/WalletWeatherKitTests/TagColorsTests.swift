import Testing
@testable import WalletWeatherKit

/// The names VoiceOver reads for a tag's colours (#360).
@Suite struct TagColorsTests {
    @Test func everyColourHasItsOwnName() {
        let names = TagColors.all.map(TagColors.name(of:))
        #expect(Set(names).count == TagColors.all.count)
        #expect(!names.contains("Colour"))
        #expect(!names.contains { $0.hasPrefix("#") })
    }

    @Test func aColourIsNamedWhateverItsCase() {
        #expect(TagColors.name(of: "#3FB950") == "Green")
    }

    @Test func anUnknownColourIsStillNamed() {
        #expect(TagColors.name(of: "#123456") == "Colour")
        #expect(TagColors.name(of: "") == "Colour")
    }
}
