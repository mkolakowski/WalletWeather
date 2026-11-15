import CryptoKit
import Foundation
import Testing
@testable import WalletWeatherKit

struct ServerAddressTests {
    @Test func noSchemeMeansHTTPS() throws {
        let a = try ServerAddress.parse("  WW.Example.com/#dashboard ")
        #expect(a.url.absoluteString == "https://ww.example.com")
        #expect(!a.isPlainHTTP)
    }

    @Test func keepsThePort() throws {
        #expect(try ServerAddress.parse("https://ww.example.com:8443/").url.absoluteString == "https://ww.example.com:8443")
    }

    @Test(arguments: ["http://192.168.1.20:8300", "http://10.0.0.5", "http://172.20.1.1", "http://localhost:8300",
                      "http://nas.local:8300", "http://nas", "http://127.0.0.1", "http://[fd00::1]:8300"])
    func plainHTTPAtHome(_ typed: String) throws {
        #expect(try ServerAddress.parse(typed).isPlainHTTP)
    }

    @Test(arguments: ["http://ww.example.com", "http://8.8.8.8", "http://172.32.0.1", "http://nas.lan"])
    func plainHTTPElsewhereIsRefused(_ typed: String) {
        #expect(throws: ServerAddress.Problem.plainHTTPOutsideHome) { try ServerAddress.parse(typed) }
    }

    @Test func refusesNonsense() {
        #expect(throws: ServerAddress.Problem.empty) { try ServerAddress.parse("   ") }
        #expect(throws: ServerAddress.Problem.unsupportedScheme) { try ServerAddress.parse("ftp://ww.example.com") }
        #expect(throws: ServerAddress.Problem.notAnAddress) { try ServerAddress.parse("https://") }
    }
}

struct SignInTests {
    @Test func challengeIsTheVerifiersSHA256() {
        // RFC 7636, appendix B.
        let r = SignInRequest(state: "abcdefgh", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(r.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomValuesSuitTheServer() {
        let r = SignInRequest()
        #expect(r.state.count >= 8 && r.state.count <= 128)
        #expect(r.codeChallenge.count == 43)
        #expect(r.state.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(SignInRequest().state != r.state)
    }

    @Test func signInPageAddress() throws {
        let server = try ServerAddress.parse("ww.example.com")
        let r = SignInRequest(state: "state1234", codeVerifier: "v")
        let url = r.signInURL(server: server, deviceName: "Matt's iPhone")
        let q = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value!) })
        #expect(url.path() == "/app-sign-in")
        #expect(q == ["name": "Matt's iPhone", "access": "full", "state": "state1234", "code_challenge": r.codeChallenge])
        #expect(r.cloudflareURL(server: server).absoluteString == "https://ww.example.com/app-sign-in/cloudflare?state=state1234")
    }

    @Test func sheetAnswers() {
        let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJleHAiOjE4MDAwMDAwMDB9.c2ln"
        #expect(AppLink(URL(string: "walletweather://signed-in?code=abc&state=s1234567&cf=\(jwt)")!)
            == .signedIn(code: "abc", state: "s1234567", cloudflare: jwt))
        #expect(AppLink(URL(string: "walletweather://signed-in?code=abc&state=s1234567")!)
            == .signedIn(code: "abc", state: "s1234567", cloudflare: nil))
        #expect(AppLink(URL(string: "walletweather://signed-in?state=s1234567&error=cancelled")!)
            == .cancelled(state: "s1234567"))
        #expect(AppLink(URL(string: "walletweather://cloudflare?state=s1234567&cf=\(jwt)")!)
            == .cloudflare(state: "s1234567", token: jwt))
        #expect(AppLink(URL(string: "walletweather://cloudflare?state=s1234567&error=no-cloudflare")!)
            == .noCloudflare(state: "s1234567"))
        #expect(AppLink(URL(string: "walletweather://connect?server=https%3A%2F%2Fww.example.com&token=ww_x")!)
            == .connect(server: "https://ww.example.com", token: "ww_x"))
        #expect(AppLink(URL(string: "walletweather://signed-in?state=s1234567")!) == nil)
        #expect(AppLink(URL(string: "https://signed-in?code=a&state=b")!) == nil)
        #expect(AppLink(URL(string: "walletweather://elsewhere")!) == nil)
    }
}

struct CloudflareTests {
    func response(_ status: Int, _ headers: [String: String] = [:], url: String = "https://ww.example.com/api/me") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    @Test func redirectToTheTeamLoginIsAChallenge() {
        #expect(CloudflareAccess.isChallenge(response(302, ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/ww.example.com?kid=abc"]), body: nil))
        #expect(CloudflareAccess.isChallenge(response(302, ["Location": "/cdn-cgi/access/login/ww.example.com"]), body: nil))
    }

    @Test func accessRefusingIsAChallenge() {
        let body = Data("<html><title>Forbidden</title>Cloudflare Access</html>".utf8)
        #expect(CloudflareAccess.isChallenge(response(403, ["Server": "cloudflare"]), body: body))
    }

    @Test func theServersOwnAnswersAreNot() {
        #expect(!CloudflareAccess.isChallenge(response(401, ["Server": "uvicorn"]), body: Data(#"{"detail":"Not authenticated"}"#.utf8)))
        #expect(!CloudflareAccess.isChallenge(response(200, ["Server": "cloudflare"]), body: Data("{}".utf8)))
        #expect(!CloudflareAccess.isChallenge(response(302, ["Location": "https://ww.example.com/"]), body: nil))
    }

    @Test func challengeBecomesItsOwnError() {
        let r = response(302, ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login/x"])
        #expect(throws: APIError.cloudflareSignInNeeded) {
            let _: Me = try APIClient.decode(Me.self, data: Data(), response: r, path: "/api/me")
        }
    }

    @Test func headers() {
        #expect(CloudflareCredential.session(token: "jwt").headers == ["cf-access-token": "jwt"])
        #expect(CloudflareCredential.serviceToken(clientID: "id.access", secret: "s").headers
            == ["CF-Access-Client-Id": "id.access", "CF-Access-Client-Secret": "s"])
    }

    @Test func expiryIsReadFromTheToken() {
        let token = "eyJhbGciOiJSUzI1NiJ9.eyJleHAiOjE4MDAwMDAwMDB9.c2ln"  // exp 1800000000
        #expect(CloudflareCredential.session(token: token).expires == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(CloudflareCredential.serviceToken(clientID: "a", secret: "b").expires == nil)
    }
}

struct ErrorTests {
    func decodeError(_ status: Int, _ body: String) -> APIError? {
        let r = HTTPURLResponse(url: URL(string: "https://ww.example.com/api/me")!, statusCode: status,
                                httpVersion: nil, headerFields: nil)!
        do {
            let _: Me = try APIClient.decode(Me.self, data: Data(body.utf8), response: r, path: "/api/me")
            return nil
        } catch {
            return error
        }
    }

    @Test func eachKindHasItsOwnError() {
        #expect(decodeError(401, #"{"detail":"API token expired"}"#) == .tokenExpired)
        #expect(decodeError(401, #"{"detail":"Invalid or revoked API token"}"#) == .tokenRevoked)
        #expect(decodeError(403, #"{"detail":"This API token is read-only"}"#)
            == .server(status: 403, detail: "This API token is read-only"))
        #expect(decodeError(200, "<!doctype html><html></html>") == .notWalletWeather)
        #expect(decodeError(404, "Not here") == .notWalletWeather)
        #expect(decodeError(200, #"{"unexpected": true}"#) == .unexpectedResponse("/api/me"))
    }

    @Test func networkErrors() {
        #expect(APIError.from(URLError(.notConnectedToInternet), host: "h") == .offline)
        #expect(APIError.from(URLError(.timedOut), host: "h") == .slowServer)
        #expect(APIError.from(URLError(.cannotFindHost), host: "h") == .cannotReach("h"))
        #expect(APIError.from(URLError(.serverCertificateUntrusted), host: "h") == .insecure)
    }

    @Test func versions() {
        #expect(isVersion("1.49.0", atLeast: "1.49.0") == true)
        #expect(isVersion("1.50.2", atLeast: "1.49.0") == true)
        #expect(isVersion("1.48.9", atLeast: "1.49.0") == false)
        #expect(isVersion("2.0", atLeast: "1.49.0") == true)
        #expect(isVersion("dev", atLeast: "1.49.0") == nil)
    }
}

struct FormattingTests {
    @Test func money() {
        #expect(Money(0.1).amount == Decimal(string: "0.1"))
        #expect(Money(-1234.5).formatted == "-$1,234.50")
        #expect(Money(18500.0).short == "$18.5K")
        #expect(Money(1260.0).short == "$1.3K")
        #expect(Money(-950.0).short == "-$950")
    }

    @Test func days() {
        let d = LocalDay("2026-02-10")!
        #expect(d.description == "2026-02-10")
        #expect(d.endOfMonth == LocalDay("2026-02-28"))
        #expect(LocalDay("2026-2-10") == nil)
        #expect(LocalDay("2026-11-01")! < LocalDay("2026-11-02")!)
    }
}
