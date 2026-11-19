import Foundation
import Testing
@testable import WalletWeatherKit

/// scrypt gives Python's answer byte for byte (#236): RFC 7914's vectors
/// and two at the backups' own cost, made by Python's `cryptography`
/// (`Samples/moves/vectors.json`, checked again by the server's
/// tests), one with a passphrase beyond ASCII.
struct ScryptTests {
    struct Vector: Decodable {
        let name, passphrase, salt, key: String
        let n, r, p, length: Int
    }

    static func vectors() throws -> [Vector] {
        struct File: Decodable { let vectors: [Vector] }
        let url = try #require(Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Samples/moves"))
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).vectors
    }

    @Test func everyVectorMatchesPython() throws {
        for v in try Self.vectors() {
            let start = Date.now
            let key = try Scrypt.derive(password: Data(v.passphrase.utf8), salt: try #require(Data(base64Encoded: v.salt)),
                                        n: v.n, r: v.r, p: v.p, length: v.length)
            #expect(key.map { String(format: "%02x", $0) }.joined() == v.key, "\(v.name)")
            print("scrypt \(v.name): \(Int(Date.now.timeIntervalSince(start) * 1000)) ms")
        }
    }

    @Test func badParametersAreRefused() {
        #expect(throws: Scrypt.Problem.badParameters) { try Scrypt.derive(password: Data(), salt: Data(), n: 1000, r: 8, p: 1, length: 32) }
        #expect(throws: Scrypt.Problem.badParameters) { try Scrypt.derive(password: Data(), salt: Data(), n: 1 << 24, r: 16, p: 1, length: 32) }
    }
}
