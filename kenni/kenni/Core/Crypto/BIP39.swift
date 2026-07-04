import Foundation
import CryptoKit

enum BIP39Error: Error, Equatable {
    case invalidEntropySize
    case invalidWordCount
    case unknownWord(String)
    case checksumMismatch
    case wordlistMissing
}

/// BIP39 mnemonic encoding for the 128-bit master seed (12 English words).
/// The recovery phrase alone deterministically restores the full identity — offline.
enum BIP39 {
    static let wordlist: [String] = {
        guard let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }()

    private static let wordIndex: [String: Int] = {
        Dictionary(uniqueKeysWithValues: wordlist.enumerated().map { ($1, $0) })
    }()

    static func generateEntropy() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BIP39Error.invalidEntropySize
        }
        return Data(bytes)
    }

    /// 128-bit entropy → 12 words (entropy bits + 4 checksum bits = 132 bits = 12 × 11).
    static func mnemonic(from entropy: Data) throws -> [String] {
        guard entropy.count == 16 else { throw BIP39Error.invalidEntropySize }
        guard wordlist.count == 2048 else { throw BIP39Error.wordlistMissing }

        var bits: [Bool] = []
        bits.reserveCapacity(132)
        for byte in entropy {
            for i in (0..<8).reversed() { bits.append((byte >> i) & 1 == 1) }
        }
        let checksumByte = Data(SHA256.hash(data: entropy))[0]
        for i in (4..<8).reversed() { bits.append((checksumByte >> i) & 1 == 1) }

        return stride(from: 0, to: 132, by: 11).map { start in
            var index = 0
            for bit in bits[start..<(start + 11)] { index = index << 1 | (bit ? 1 : 0) }
            return wordlist[index]
        }
    }

    /// 12 words → 128-bit entropy, validating the checksum.
    static func entropy(from words: [String]) throws -> Data {
        guard words.count == 12 else { throw BIP39Error.invalidWordCount }
        guard wordlist.count == 2048 else { throw BIP39Error.wordlistMissing }

        var bits: [Bool] = []
        bits.reserveCapacity(132)
        for word in words {
            let normalized = word.lowercased().trimmingCharacters(in: .whitespaces)
            guard let index = wordIndex[normalized] else { throw BIP39Error.unknownWord(word) }
            for i in (0..<11).reversed() { bits.append((index >> i) & 1 == 1) }
        }

        var entropy = Data(capacity: 16)
        for start in stride(from: 0, to: 128, by: 8) {
            var byte: UInt8 = 0
            for bit in bits[start..<(start + 8)] { byte = byte << 1 | (bit ? 1 : 0) }
            entropy.append(byte)
        }

        var checksum = 0
        for bit in bits[128..<132] { checksum = checksum << 1 | (bit ? 1 : 0) }
        let expected = Int(Data(SHA256.hash(data: entropy))[0] >> 4)
        guard checksum == expected else { throw BIP39Error.checksumMismatch }

        return entropy
    }

    /// True if `word` is in the wordlist (for live validation while typing a phrase).
    static func isValidWord(_ word: String) -> Bool {
        wordIndex[word.lowercased().trimmingCharacters(in: .whitespaces)] != nil
    }
}
