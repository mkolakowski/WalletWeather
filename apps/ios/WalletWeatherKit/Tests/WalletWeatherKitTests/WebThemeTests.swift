import Foundation
import Testing
@testable import WalletWeatherKit

/// The web app's themes in the iPhone app (#102).
struct WebThemeTests {
    /// The web app's stylesheet, from this checkout.
    static func stylesheet() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appending(path: "apps/web/index.html"), encoding: .utf8)
    }

    /// One `--name:#rrggbb` from a theme's block.
    static func value(_ name: String, in block: Substring) -> UInt32? {
        guard let range = block.range(of: "--\(name):#") else { return nil }
        return UInt32(block[range.upperBound...].prefix(6), radix: 16)
    }

    @Test(arguments: WebTheme.allCases)
    func matchesTheWebApp(_ theme: WebTheme) throws {
        let css = try Self.stylesheet()
        let start = try #require(css.range(of: ":root[data-theme=\"\(theme.rawValue)\"] {"))
        let end = try #require(css[start.upperBound...].range(of: "}"))
        let block = css[start.upperBound..<end.lowerBound]
        let c = theme.colors
        #expect(Self.value("bg", in: block) == c.page)
        #expect(Self.value("panel", in: block) == c.panel)
        #expect(Self.value("border", in: block) == c.border)
        #expect(Self.value("text", in: block) == c.text)
        #expect(Self.value("accent", in: block) == c.accent)
        #expect(Self.value("good", in: block) == c.good)
        #expect(Self.value("bad", in: block) == c.bad)
        #expect(Self.value("warn", in: block) == c.warn)
        #expect(block.contains("color-scheme:\(c.isDark ? "dark" : "light")"))
    }

    @Test func everyServerThemeIsKnown() {
        // The server's ALLOWED_THEMES (apps/server/app/main.py).
        #expect(ServerTheme(nil) == .system)
        #expect(ServerTheme("system") == .system)
        #expect(ServerTheme("light") == .light)
        #expect(ServerTheme("dark") == .dark)
        for theme in WebTheme.allCases { #expect(ServerTheme(theme.rawValue) == .web(theme)) }
        #expect(ServerTheme("something-new") == .system)
    }

    /// Body text and amounts stay readable on each theme's page and cards
    /// (WCAG AA for normal text, 4.5:1), as the web app draws them.
    @Test(arguments: WebTheme.allCases)
    func textIsReadable(_ theme: WebTheme) {
        let c = theme.colors
        for background in [c.page, c.panel] {
            #expect(contrast(c.text, background) >= 4.5, "text on \(String(background, radix: 16))")
        }
    }

    func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ v: UInt32) -> Double {
                let s = Double(v & 0xFF) / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
