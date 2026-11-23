import Foundation
import Testing
@testable import WalletWeatherKit

/// The way forward a problem banner offers (#311).
struct ProblemTests {
    @Test(arguments: [APIError.offline, .slowServer, .cannotReach("ww.example.com"), .insecure,
                      .serverTooOld(found: "1.0.0", needed: "1.40.0"), .unexpectedResponse("odd"),
                      .server(status: 500, detail: "Internal error"), .server(status: 503, detail: "Starting")])
    func aNetworkOrServerFaultOffersTryAgain(_ error: APIError) {
        #expect(error.wayForward == .tryAgain)
    }

    @Test func signInsOfferTheirOwnWay() {
        #expect(APIError.cloudflareSignInNeeded.wayForward == .signInToCloudflare)
        #expect(APIError.tokenExpired.wayForward == .signInAgain)
        #expect(APIError.tokenRevoked.wayForward == .signInAgain)
    }

    /// Sending the same thing again wouldn't help: nothing to tap, only
    /// the reason.
    @Test(arguments: [APIError.server(status: 400, detail: "Amount must be more than zero"),
                      .server(status: 404, detail: "Not found"), .server(status: 409, detail: "Changed elsewhere"),
                      .server(status: 422, detail: "csv_text is required"), .demoReadOnly, .wrongPassword,
                      .twoFactorCodeNeeded("Enter the code"), .notWalletWeather])
    func aRefusalOffersNothingToTap(_ error: APIError) {
        #expect(error.wayForward == nil)
    }

    @Test func anAPIErrorIsKeptAsItIs() {
        let thrown: any Error = APIError.server(status: 400, detail: "No")
        #expect(APIError(thrown) == .server(status: 400, detail: "No"))
        #expect(APIError(APIError.demoReadOnly) == .demoReadOnly)
    }

    @Test func anythingElseIsSomethingWentWrong() {
        struct Odd: Error {}
        let error = APIError(Odd())
        guard case .unexpectedResponse = error else {
            Issue.record("expected unexpectedResponse, got \(error)")
            return
        }
        #expect(error.title == "Something went wrong")
        #expect(error.wayForward == .tryAgain)
    }

    /// The demo's refusal reads as the banner shows it.
    @Test func theDemosRefusal() {
        #expect(APIError.demoReadOnly.title == "This is the demo")
        #expect(APIError.demoReadOnly.message == "The demo doesn't save changes. Connect your server to edit.")
    }
}
