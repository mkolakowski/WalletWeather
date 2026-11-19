import CryptoKit
import Foundation

/// scrypt (RFC 7914), for the server's sealed backups (`backup.py`:
/// scrypt, then AES-256-GCM; Plans/standalone.md, phase 5, #236). CryptoKit
/// has no scrypt, so it's written here, on CryptoKit's HMAC-SHA256.
///
/// It must give Python's answer byte for byte, or a backup can't be opened:
/// `ScryptTests` checks RFC 7914's vectors and ones Python's `cryptography`
/// made at the backups' own cost, which the server's tests check again.
///
/// At the backups' cost (N = 2^17, r = 8, p = 1) it uses 128 MiB and takes
/// a fraction of a second in a Release build.
public enum Scrypt {
    public enum Problem: Error, Equatable {
        /// N must be a power of two above 1; r and p at least 1; the memory
        /// within reach.
        case badParameters
    }

    public static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) throws(Problem) -> Data {
        guard n > 1, n & (n - 1) == 0, r >= 1, p >= 1, length >= 1,
              r * p < 1 << 30, n <= (1 << 30) / (128 * r) else { throw .badParameters }
        let blockWords = 32 * r
        var b = pbkdf2(password: password, salt: salt, length: p * 128 * r)
        var words = [UInt32](repeating: 0, count: blockWords)
        let v = UnsafeMutablePointer<UInt32>.allocate(capacity: n * blockWords)
        defer { v.deallocate() }
        let scratch = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords)
        defer { scratch.deallocate() }
        for chunk in 0..<p {
            let offset = chunk * 128 * r
            b.withUnsafeBytes { raw in
                for i in 0..<blockWords {
                    words[i] = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + i * 4, as: UInt32.self))
                }
            }
            words.withUnsafeMutableBufferPointer { x in
                roMix(x.baseAddress!, r: r, n: n, v: v, scratch: scratch)
            }
            b.withUnsafeMutableBytes { raw in
                for i in 0..<blockWords {
                    raw.storeBytes(of: words[i].littleEndian, toByteOffset: offset + i * 4, as: UInt32.self)
                }
            }
        }
        return pbkdf2(password: password, salt: b, length: length)
    }

    /// PBKDF2-HMAC-SHA256 with one iteration, all scrypt needs.
    static func pbkdf2(password: Data, salt: Data, length: Int) -> Data {
        let key = SymmetricKey(data: password)
        var out = Data(capacity: length + 32)
        var block: UInt32 = 1
        while out.count < length {
            var message = salt
            withUnsafeBytes(of: block.bigEndian) { message.append(contentsOf: $0) }
            out.append(contentsOf: HMAC<SHA256>.authenticationCode(for: message, using: key))
            block += 1
        }
        return out.prefix(length)
    }

    /// ROMix over `x` (32·r words), with `v` room for N blocks.
    private static func roMix(_ x: UnsafeMutablePointer<UInt32>, r: Int, n: Int,
                              v: UnsafeMutablePointer<UInt32>, scratch: UnsafeMutablePointer<UInt32>) {
        let words = 32 * r
        for i in 0..<n {
            (v + i * words).update(from: x, count: words)
            blockMix(x, r: r, scratch: scratch)
        }
        for _ in 0..<n {
            // Integerify: the first word of the last 64-byte block, mod N.
            let j = Int(x[(2 * r - 1) * 16]) & (n - 1)
            let vj = v + j * words
            for k in 0..<words { x[k] ^= vj[k] }
            blockMix(x, r: r, scratch: scratch)
        }
    }

    /// BlockMix with Salsa20/8, in place: the even blocks first, then the odd.
    private static func blockMix(_ b: UnsafeMutablePointer<UInt32>, r: Int, scratch y: UnsafeMutablePointer<UInt32>) {
        // Loaded and stored unaligned: SIMD16 wants more alignment than the
        // buffers promise.
        var t = UnsafeRawPointer(b + (2 * r - 1) * 16).loadUnaligned(as: SIMD16<UInt32>.self)
        for i in 0..<(2 * r) {
            t = salsa8(t ^ UnsafeRawPointer(b + i * 16).loadUnaligned(as: SIMD16<UInt32>.self))
            let place = (i % 2 == 0 ? i / 2 : r + i / 2) * 16
            UnsafeMutableRawPointer(y + place).storeBytes(of: t, as: SIMD16<UInt32>.self)
        }
        b.update(from: y, count: 32 * r)
    }

    @inline(__always)
    private static func rotl(_ a: UInt32, _ s: UInt32) -> UInt32 { (a << s) | (a >> (32 - s)) }

    /// The Salsa20/8 core.
    private static func salsa8(_ input: SIMD16<UInt32>) -> SIMD16<UInt32> {
        var x0 = input[0], x1 = input[1], x2 = input[2], x3 = input[3]
        var x4 = input[4], x5 = input[5], x6 = input[6], x7 = input[7]
        var x8 = input[8], x9 = input[9], x10 = input[10], x11 = input[11]
        var x12 = input[12], x13 = input[13], x14 = input[14], x15 = input[15]
        for _ in 0..<4 {
            x4 ^= rotl(x0 &+ x12, 7); x8 ^= rotl(x4 &+ x0, 9)
            x12 ^= rotl(x8 &+ x4, 13); x0 ^= rotl(x12 &+ x8, 18)
            x9 ^= rotl(x5 &+ x1, 7); x13 ^= rotl(x9 &+ x5, 9)
            x1 ^= rotl(x13 &+ x9, 13); x5 ^= rotl(x1 &+ x13, 18)
            x14 ^= rotl(x10 &+ x6, 7); x2 ^= rotl(x14 &+ x10, 9)
            x6 ^= rotl(x2 &+ x14, 13); x10 ^= rotl(x6 &+ x2, 18)
            x3 ^= rotl(x15 &+ x11, 7); x7 ^= rotl(x3 &+ x15, 9)
            x11 ^= rotl(x7 &+ x3, 13); x15 ^= rotl(x11 &+ x7, 18)
            x1 ^= rotl(x0 &+ x3, 7); x2 ^= rotl(x1 &+ x0, 9)
            x3 ^= rotl(x2 &+ x1, 13); x0 ^= rotl(x3 &+ x2, 18)
            x6 ^= rotl(x5 &+ x4, 7); x7 ^= rotl(x6 &+ x5, 9)
            x4 ^= rotl(x7 &+ x6, 13); x5 ^= rotl(x4 &+ x7, 18)
            x11 ^= rotl(x10 &+ x9, 7); x8 ^= rotl(x11 &+ x10, 9)
            x9 ^= rotl(x8 &+ x11, 13); x10 ^= rotl(x9 &+ x8, 18)
            x12 ^= rotl(x15 &+ x14, 7); x13 ^= rotl(x12 &+ x15, 9)
            x14 ^= rotl(x13 &+ x12, 13); x15 ^= rotl(x14 &+ x13, 18)
        }
        return input &+ SIMD16(x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15)
    }
}
