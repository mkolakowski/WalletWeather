import Foundation
import Testing
@testable import WalletWeatherKit

/// The Appearance page's previews (ios-settings phase 3, #296, finding R19).
struct LookPreviewTests {
    @Test func everyLookHasAPreview() {
        #expect(LookPreview.rawValues.count == 14)
        #expect(Set(LookPreview.rawValues).count == 14)
        for raw in LookPreview.rawValues {
            #expect(LookPreview.swatches(for: raw)?.isEmpty == false, "\(raw)")
        }
        #expect(LookPreview.swatches(for: "no-such-look") == nil)
    }

    @Test func matchThisIPhoneIsLightAndDark() throws {
        let halves = try #require(LookPreview.swatches(for: "system"))
        #expect(halves == [LookPreview.Swatch(BuiltInLook.light.colors), LookPreview.Swatch(BuiltInLook.dark.colors)])
    }

    @Test func matchTheWebAppShowsTheServersTheme() throws {
        let split = try #require(LookPreview.swatches(for: "web"))
        #expect(split.count == 2)
        #expect(LookPreview.swatches(for: "web", server: .system) == split)
        #expect(LookPreview.swatches(for: "web", server: .dark) == [LookPreview.Swatch(BuiltInLook.dark.colors)])
        #expect(LookPreview.swatches(for: "web", server: .light) == [LookPreview.Swatch(BuiltInLook.light.colors)])
        #expect(LookPreview.swatches(for: "web", server: .web(.nord)) == [LookPreview.Swatch(WebTheme.nord.colors)])
    }

    /// Each look's text reads on its page and its card (WCAG AA, 4.5:1).
    @Test(arguments: LookPreview.rawValues)
    func textReadsOnTheCard(_ raw: String) throws {
        for swatch in try #require(LookPreview.swatches(for: raw)) {
            #expect(WebThemeTests().contrast(swatch.text, swatch.card) >= 4.5, "\(raw) on its card")
            #expect(WebThemeTests().contrast(swatch.text, swatch.page) >= 4.5, "\(raw) on its page")
        }
    }

    @Test func webThemesComeFromTheirOwnColours() throws {
        for theme in WebTheme.allCases {
            #expect(LookPreview.swatches(for: theme.rawValue) == [LookPreview.Swatch(theme.colors)])
        }
    }
}
