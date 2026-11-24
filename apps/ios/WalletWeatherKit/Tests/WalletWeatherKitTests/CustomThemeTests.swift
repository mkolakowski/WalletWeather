import Foundation
import Testing
@testable import WalletWeatherKit

/// Themes people make themselves (ios-settings phase 4, #297).
struct CustomThemeTests {
    // MARK: - Contrast

    @Test func contrastOfKnownPairs() {
        #expect(abs(Contrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(Contrast.ratio(0xFFFFFF, 0x000000) - 21) < 0.001)
        #expect(Contrast.ratio(0x777777, 0xFFFFFF) < 4.5)
        #expect(abs(Contrast.ratio(0x777777, 0xFFFFFF) - 4.48) < 0.01)
        #expect(Contrast.ratio(0x767676, 0xFFFFFF) >= 4.5)
        #expect(abs(Contrast.ratio(0x123456, 0x123456) - 1) < 0.0001)
        // Pure red on white is 4.0:1, pure blue on white 8.6:1.
        #expect(abs(Contrast.ratio(0xFF0000, 0xFFFFFF) - 4.0) < 0.01)
        #expect(abs(Contrast.ratio(0x0000FF, 0xFFFFFF) - 8.59) < 0.01)
    }

    @Test func faintPairsAreNamed() {
        #expect(CustomThemeStore.sampleLight.faintPairs == [.moneyInOnCard])
        #expect(CustomThemeStore.sampleDark.faintPairs.isEmpty)
        let grey = CustomTheme(name: "Grey", page: 0xFFFFFF, card: 0xFFFFFF, text: 0x777777,
                               accent: 0xEEEEEE, moneyIn: 0x000000, moneyOut: 0x000000)
        #expect(grey.faintPairs == [.textOnCard, .accentOnPage])
        #expect(CustomTheme.Pair.textOnCard.title == "text on card")
        // Every built-in look's and web theme's text reads on its card as a theme.
        for colors in BuiltInLook.allCases.map(\.colors) + WebTheme.allCases.map(\.colors) {
            #expect(!CustomTheme(name: "Copy", copying: colors).faintPairs.contains(.textOnCard))
        }
    }

    // MARK: - Light or dark

    @Test func lightOrDarkFromThePage() {
        func theme(page: UInt32) -> CustomTheme {
            CustomTheme(name: "T", page: page, card: page, text: 0x808080, accent: 0x808080,
                        moneyIn: 0x808080, moneyOut: 0x808080)
        }
        #expect(theme(page: 0x000000).isDark)
        #expect(!theme(page: 0xFFFFFF).isDark)
        #expect(!theme(page: 0xEAD5B3).isDark)   // Sepia's page
        #expect(theme(page: 0x2E3440).isDark)    // Nord's page
        #expect(theme(page: 0x666666).isDark)
        #expect(!theme(page: 0x777777).isDark)
        // A copy of every look is light or dark as that look is.
        for colors in BuiltInLook.allCases.map(\.colors) + WebTheme.allCases.map(\.colors) {
            #expect(CustomTheme(name: "Copy", copying: colors).isDark == colors.isDark)
        }
    }

    @Test func workedOutColours() {
        let dark = CustomTheme(copying: BuiltInLook.dark.colors)
        // The outline sits between the card and the text, near the card.
        #expect(dark.outline == CustomTheme.mix(0x1C1C1E, 0xFFFFFF, 0.18))
        #expect(CustomTheme.mix(0x000000, 0xFFFFFF, 0.5) == 0x808080)
        #expect(CustomTheme.mix(0x102030, 0x102030, 0.7) == 0x102030)
        // The warning is the amber that reads on the card.
        #expect(dark.warn == 0xD29922)
        #expect(CustomTheme(copying: BuiltInLook.light.colors).warn == 0x9A6700)
        let colors = CustomThemeStore.sampleDark.colors
        #expect(colors.page == 0x0B1A2B && colors.panel == 0x13263B && colors.good == 0x66D9A0)
        #expect(colors.isDark)
    }

    // MARK: - Storage

    @Test func themesComeBackFromStorageTheSame() throws {
        let themes = CustomThemeStore.samples + [CustomTheme(name: "Émilie’s “blue” 🌊", page: 0x010203, card: 0xFFFFFE,
                                                             text: 0, accent: 0xABCDEF, moneyIn: 0x00FF00, moneyOut: 0xFF0000)]
        let data = CustomThemeStore.encode(themes)
        #expect(CustomThemeStore.decode(data) == themes)
        // Names and colours only, the colours as #rrggbb.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"#0b1a2b\""))
        #expect(text.contains("\"version\":1"))
        #expect(CustomThemeStore.decode(CustomThemeStore.encode([])) == [])
    }

    @Test func unreadableStorageIsNoThemes() {
        #expect(CustomThemeStore.decode(nil) == [])
        #expect(CustomThemeStore.decode(Data("nonsense".utf8)) == [])
        let badColour = ##"{"version":1,"themes":[{"id":"00000000-0000-4000-8000-000000000001","name":"X","page":"red","card":"#000000","text":"#ffffff","accent":"#ffffff","moneyIn":"#ffffff","moneyOut":"#ffffff"}]}"##
        #expect(CustomThemeStore.decode(Data(badColour.utf8)) == [])
    }

    @Test func hexStrings() {
        #expect(CustomTheme.hex(0x0A0B0C) == "#0a0b0c")
        #expect(CustomTheme.hex("#0A0b0C") == 0x0A0B0C)
        #expect(CustomTheme.hex("0a0b0c") == nil)
        #expect(CustomTheme.hex("#0a0b0") == nil)
        #expect(CustomTheme.hex("#0a0b0g") == nil)
        #expect(CustomTheme.cleanName("  Ocean \n") == "Ocean")
        #expect(CustomTheme.cleanName("   ") == nil)
    }

    @Test func iCloudsCopyComingIn() {
        let (a, b, c) = (CustomTheme(name: "A", copying: BuiltInLook.light.colors),
                         CustomTheme(name: "B", copying: BuiltInLook.dark.colors),
                         CustomTheme(name: "C", copying: WebTheme.nord.colors))
        var renamed = a
        renamed.name = "A2"
        // Another iPhone's change wins, deletions included.
        #expect(CustomThemeStore.incoming(cloud: [renamed], local: [a, b], replacing: true) == [renamed])
        // The first copy keeps this iPhone's themes that iCloud doesn't have.
        #expect(CustomThemeStore.incoming(cloud: [renamed, c], local: [a, b], replacing: false) == [renamed, c, b])
        #expect(CustomThemeStore.incoming(cloud: [], local: [a], replacing: false) == [a])
    }

    // MARK: - The saved look

    @Test func aCustomLookHasItsOwnStableValue() {
        let theme = CustomThemeStore.sampleDark
        #expect(theme.rawValue == "custom:00000000-0000-4000-8000-0000000000d1")
        var edited = theme
        edited.name = "Renamed"
        edited.page = 0xFFFFFF
        #expect(edited.rawValue == theme.rawValue)
        #expect(!LookPreview.rawValues.contains(theme.rawValue))
    }

    @Test func anUnknownSavedLookFallsBack() {
        let themes = CustomThemeStore.samples
        for raw in LookPreview.rawValues {
            #expect(CustomThemeStore.resolve(saved: raw, themes: []) == raw)
        }
        #expect(CustomThemeStore.resolve(saved: themes[1].rawValue, themes: themes) == themes[1].rawValue)
        #expect(CustomThemeStore.resolve(saved: themes[1].rawValue, themes: [themes[0]]) == "system")
        #expect(CustomThemeStore.resolve(saved: "custom:not-a-theme", themes: themes) == "system")
        #expect(CustomThemeStore.resolve(saved: "no-such-look", themes: themes) == "system")
        #expect(CustomThemeStore.resolve(saved: nil, themes: themes) == "system")
    }

    @Test func debugSamples() {
        #expect(CustomThemeStore.sample(named: "custom-light") == CustomThemeStore.sampleLight)
        #expect(CustomThemeStore.sample(named: "custom-dark")?.isDark == true)
        #expect(CustomThemeStore.sampleLight.isDark == false)
        #expect(CustomThemeStore.sample(named: "nord") == nil)
    }
}

private extension CustomTheme {
    init(copying colors: WebTheme.Colors) { self.init(name: "Copy", copying: colors) }
}
