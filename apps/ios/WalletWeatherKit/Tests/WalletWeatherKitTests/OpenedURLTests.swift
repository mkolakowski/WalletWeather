import Foundation
import Testing
@testable import WalletWeatherKit

/// An address handed to the app (#326): connect links keep working, a CSV
/// opened from Files or Mail goes to Import a CSV, anything else is ignored.
struct OpenedURLTests {
    @Test func aConnectLinkStaysALink() throws {
        let url = try #require(URL(string: "walletweather://connect?server=https://wallet.example.com&token=abc"))
        #expect(OpenedURL(url) == .link(.connect(server: "https://wallet.example.com", token: "abc")))
    }

    @Test func theSignInAnswerStaysALink() throws {
        let url = try #require(URL(string: "walletweather://signed-in?code=c&state=s"))
        #expect(OpenedURL(url) == .link(.signedIn(code: "c", state: "s", cloudflare: nil)))
    }

    @Test func aCSVFileIsACSV() {
        #expect(OpenedURL(URL(fileURLWithPath: "/tmp/Inbox/statement.csv")) == .csv)
        #expect(OpenedURL(URL(fileURLWithPath: "/tmp/Inbox/STATEMENT.CSV")) == .csv, "any case")
    }

    @Test func otherFilesAndAddressesAreOther() throws {
        #expect(OpenedURL(URL(fileURLWithPath: "/tmp/Inbox/photo.png")) == .other)
        #expect(OpenedURL(URL(fileURLWithPath: "/tmp/Inbox/notes.txt")) == .other)
        #expect(OpenedURL(try #require(URL(string: "https://example.com/a.csv"))) == .other, "a web address isn't a file")
        #expect(OpenedURL(try #require(URL(string: "walletweather://nowhere"))) == .other)
        #expect(OpenedURL(try #require(URL(string: "walletweather://connect?server=x"))) == .other, "a connect link missing its token")
    }

    @Test func theSheetShowsTheFileName() {
        #expect(OpenedURL.fileName(URL(fileURLWithPath: "/tmp/Inbox/Chase 2026.csv")) == "Chase 2026.csv")
    }

    @Test func importNeedsAConnectionThatCanChange() {
        #expect(OpenedCSV.decide(signedIn: true, readOnly: false) == .importIt)
        #expect(OpenedCSV.decide(signedIn: false, readOnly: false) == .needsConnection)
        #expect(OpenedCSV.decide(signedIn: false, readOnly: true) == .needsConnection)
        #expect(OpenedCSV.decide(signedIn: true, readOnly: true) == .readOnly)
        #expect(OpenedCSV.importIt.refusal == nil)
        #expect(OpenedCSV.needsConnection.refusal?.title == "Connect first")
        #expect(OpenedCSV.readOnly.refusal?.title == "Can't import here")
    }
}
