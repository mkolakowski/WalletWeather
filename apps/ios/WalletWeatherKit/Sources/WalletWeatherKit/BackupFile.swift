import CryptoKit
import Foundation

/// The server's sealed backup file (`backup.py`, bank-sync phase 1, #193),
/// written and opened on the phone to move between a server and the
/// iPhone (Plans/standalone.md, phase 5, #236).
///
/// A sealed file is a JSON object: a readable header saying how it was
/// sealed (scrypt's cost and salt, AES-256-GCM's nonce), then the backup's
/// JSON encrypted under a key scrypt derives from the passphrase. The header
/// is bound to the ciphertext as associated data, as Python writes it:
/// `json.dumps(header, sort_keys=True, separators=(",", ":"))`, so
/// `headerBytes` reproduces that byte for byte. The marker and field names
/// are on people's disks: never rename them.
public enum BackupFile {
    static let marker = "walletweather-encrypted-backup"
    static let format = 1
    public static let passphraseMinimum = 12
    /// The cost the server seals with (OWASP's: 128 MiB).
    static let cost = (n: 1 << 17, r: 8, p: 1)
    /// The most a file may ask for, as the server allows.
    static let costLimit = (n: 1 << 18, r: 16, p: 4)

    public enum Problem: Error, Equatable {
        case passphrase(String)
        case locked
        case wrongPassphrase
        case damaged
        case newer
        case notABackup

        /// The server's own words where it has them.
        public var message: String {
            switch self {
            case let .passphrase(text): text
            case .locked: "This backup is encrypted. Enter its passphrase."
            case .wrongPassphrase: "That passphrase doesn't open this backup. Nothing was changed."
            case .damaged: "This backup file is damaged and can't be opened."
            case .newer: "This backup was made by a newer version of WalletWeather. Update the app, then try again."
            case .notABackup: "This isn't a WalletWeather backup file."
            }
        }
    }

    /// Why a passphrase can't seal a backup, or nil when it can. Counted in
    /// code points, as Python's `len` does.
    public static func passphraseProblem(_ passphrase: String) -> String? {
        if passphrase.isEmpty { return "Enter a passphrase." }
        if passphrase.unicodeScalars.count < passphraseMinimum {
            return "The passphrase must be at least \(passphraseMinimum) characters."
        }
        return nil
    }

    // MARK: - Sealing

    /// The sealed file's bytes for a backup `payload`.
    public static func seal(_ payload: [String: Any], passphrase: String, kind: String = "user") throws(Problem) -> Data {
        try seal(payload, passphrase: passphrase, kind: kind, cost: cost)
    }

    /// The same at another cost: for quick tests only. Files that leave the
    /// phone use the server's.
    static func seal(_ payload: [String: Any], passphrase: String, kind: String,
                     cost: (n: Int, r: Int, p: Int)) throws(Problem) -> Data {
        if let problem = passphraseProblem(passphrase) { throw .passphrase(problem) }
        let salt = randomBytes(16), nonce = randomBytes(12)
        let header: [String: Any] = [
            "walletweather": marker,
            "format": format,
            "kind": kind,
            "exported_at": payload["exported_at"] ?? NSNull(),
            "kdf": ["name": "scrypt", "n": cost.n, "r": cost.r, "p": cost.p, "salt": salt.base64EncodedString()],
            "cipher": ["name": "AES-256-GCM", "nonce": nonce.base64EncodedString()],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes]),
              let aad = headerBytes(header),
              let key = try? Scrypt.derive(password: Data(passphrase.utf8), salt: salt, n: cost.n, r: cost.r, p: cost.p, length: 32),
              let box = try? AES.GCM.seal(body, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce),
                                          authenticating: aad)
        else { throw .damaged }
        var file = header
        file["ciphertext"] = (box.ciphertext + box.tag).base64EncodedString()
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            throw .damaged
        }
        return data
    }

    // MARK: - Opening

    /// The backup in a file as picked: a sealed one opened with
    /// `passphrase`, a plain one (as "Download my data" gives, or an older
    /// server's backup) passed through. `encrypted` says which.
    public static func open(_ file: Data, passphrase: String?) throws(Problem) -> (payload: [String: Any], encrypted: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: file), let dict = object as? [String: Any] else {
            throw .notABackup
        }
        guard dict["walletweather"] as? String == marker else {
            guard dict["accounts"] is [Any] else { throw .notABackup }
            return (dict, false)
        }
        guard (dict["format"] as? NSNumber)?.intValue == format, !isBool(dict["format"]) else { throw .newer }
        guard let passphrase, !passphrase.isEmpty else { throw .locked }
        var header = dict
        header.removeValue(forKey: "ciphertext")
        guard let kdf = dict["kdf"] as? [String: Any], let cipher = dict["cipher"] as? [String: Any],
              kdf["name"] as? String == "scrypt", cipher["name"] as? String == "AES-256-GCM",
              let n = int(kdf["n"]), let r = int(kdf["r"]), let p = int(kdf["p"]),
              (2...costLimit.n).contains(n), n & (n - 1) == 0,
              (1...costLimit.r).contains(r), (1...costLimit.p).contains(p),
              let salt = (kdf["salt"] as? String).flatMap({ Data(base64Encoded: $0) }), salt.count >= 16,
              let nonce = (cipher["nonce"] as? String).flatMap({ Data(base64Encoded: $0) }), nonce.count == 12,
              let sealed = (dict["ciphertext"] as? String).flatMap({ Data(base64Encoded: $0) }), sealed.count >= 16,
              let aad = headerBytes(header)
        else { throw .damaged }
        guard let key = try? Scrypt.derive(password: Data(passphrase.utf8), salt: salt, n: n, r: r, p: p, length: 32),
              let gcmNonce = try? AES.GCM.Nonce(data: nonce),
              let box = try? AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        else { throw .damaged }
        // A wrong passphrase and an edited file look the same to AES-GCM;
        // the passphrase is by far the likelier, as the server says.
        guard let body = try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad) else {
            throw .wrongPassphrase
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { throw .damaged }
        return (payload, true)
    }

    // MARK: - The header as Python writes it

    /// `json.dumps(header, sort_keys=True, separators=(",", ":"))`: keys in
    /// code point order, no spaces, everything outside printable ASCII
    /// escaped (`ensure_ascii`). Nil for a value Python wouldn't write the
    /// same way (a fraction).
    static func headerBytes(_ header: [String: Any]) -> Data? {
        var out = ""
        guard write(header, into: &out) else { return nil }
        return Data(out.utf8)
    }

    private static func write(_ value: Any, into out: inout String) -> Bool {
        switch value {
        case is NSNull:
            out += "null"
        case let text as String:
            writeString(text, into: &out)
        case let number as NSNumber:
            if isBool(number) {
                out += number.boolValue ? "true" : "false"
            } else if let whole = int(number) {
                out += String(whole)
            } else {
                return false
            }
        case let dict as [String: Any]:
            out += "{"
            let keys = dict.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0.value < $1.value } }
            for (i, key) in keys.enumerated() {
                if i > 0 { out += "," }
                writeString(key, into: &out)
                out += ":"
                guard write(dict[key]!, into: &out) else { return false }
            }
            out += "}"
        case let list as [Any]:
            out += "["
            for (i, item) in list.enumerated() {
                if i > 0 { out += "," }
                guard write(item, into: &out) else { return false }
            }
            out += "]"
        default:
            return false
        }
        return true
    }

    private static func writeString(_ text: String, into out: inout String) {
        out += "\""
        for unit in text.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            default: out += String(format: "\\u%04x", unit)
            }
        }
        out += "\""
    }

    // MARK: - Helpers

    static func isBool(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// A whole number as JSON gave it (not a boolean, not a fraction).
    static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        let type = String(cString: number.objCType)
        guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type) else { return nil }
        return number.intValue
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

extension BackupFile.Problem: LocalizedError {
    public var errorDescription: String? { message }
}
