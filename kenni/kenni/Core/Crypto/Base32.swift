import Foundation

/// RFC 4648 Base32 (uppercase, unpadded) — used for human-readable fingerprints.
enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var result = ""
        var buffer = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                result.append(alphabet[(buffer >> bitsLeft) & 0x1F])
            }
        }
        if bitsLeft > 0 {
            result.append(alphabet[(buffer << (5 - bitsLeft)) & 0x1F])
        }
        return result
    }
}
