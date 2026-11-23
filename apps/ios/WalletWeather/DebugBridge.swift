#if DEBUG
import Foundation
import WalletWeatherKit

/// Debug builds only: a stand-in SimpleFIN Bridge for screenshots of bank
/// sync on this iPhone (#239), with `WW_DEBUG_BANK`. Nothing reaches the
/// network: the claim answers a made-up access address, and the accounts a
/// checking account with a few lines from the last two weeks.
nonisolated final class DebugBridge: URLProtocol, @unchecked Sendable {
    static let token = Data("https://bridge.simplefin.org/simplefin/claim/debug".utf8).base64EncodedString()

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DebugBridge.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let body: Data
        if url.path().hasPrefix("/simplefin/claim/") {
            body = Data("https://debug:debug@bridge.simplefin.org/simplefin".utf8)
        } else {
            body = Self.accounts()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func accounts() -> Data {
        let today = LocalDay.today()
        func posted(_ day: LocalDay) -> Int {
            Int(day.date.timeIntervalSince1970) + 12 * 3600
        }
        var lines: [[String: Any]] = [
            ["id": "cafe", "posted": posted(max(YearMonth(today).start.adding(days: 1), today.adding(days: -29))), "amount": "-6.25",
             "description": "POS Withdrawal CORNER CAFE / 1234 MAIN ST"],
            ["id": "water", "posted": posted(today.adding(days: -3)), "amount": "-48.12",
             "description": "ACH Withdrawal CITY WATER UTIL / PPD ID 5521"],
        ]
        let rent = YearMonth(today).start.adding(days: 1)
        if rent <= today {
            lines.append(["id": "rent", "posted": posted(rent), "amount": "-1450.00",
                          "description": "ACH Withdrawal OAKWOOD PROPERTIES / PPD ID 77"])
        }
        return try! JSONSerialization.data(withJSONObject: [
            "errors": [],
            "accounts": [
                ["id": "debug-checking", "name": "Everyday Checking", "org": ["name": "Example Bank"],
                 "balance": "2100.00", "transactions": lines],
                ["id": "debug-card", "name": "Rewards Card", "org": ["name": "Example Bank"],
                 "balance": "-320.00", "transactions": []],
            ],
        ])
    }
}
#endif
