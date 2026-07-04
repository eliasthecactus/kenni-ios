import Foundation
import CryptoKit

enum IdentityError: Error {
    case invalidEntropy
    case randomFailure
}

/// The user's cryptographic identity. Everything derives deterministically from
/// 128-bit entropy (= the 12-word recovery phrase), so restore works fully offline.
struct KenniIdentity {
    /// The master seed. Lives in the Keychain via `SeedVault`, never leaves the device
    /// except as the recovery phrase or the optional iCloud Keychain item.
    let entropy: Data
    /// Ed25519 — signs verification requests/responses and identity bundles. The public key is the KENNI ID.
    let signingKey: Curve25519.Signing.PrivateKey
    /// X25519 — pairwise shared secrets with contacts (offline verification codes).
    let agreementKey: Curve25519.KeyAgreement.PrivateKey
    /// Symmetric key for the optional encrypted contacts backup.
    let backupKey: SymmetricKey

    init(entropy: Data) throws {
        guard entropy.count == 16 else { throw IdentityError.invalidEntropy }
        self.entropy = entropy
        self.signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Self.derive("kenni/v1/id", from: entropy))
        self.agreementKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: Self.derive("kenni/v1/ka", from: entropy))
        self.backupKey = SymmetricKey(data: Self.derive("kenni/v1/backup", from: entropy))
    }

    init(mnemonic: [String]) throws {
        try self.init(entropy: BIP39.entropy(from: mnemonic))
    }

    static func generate() throws -> KenniIdentity {
        try KenniIdentity(entropy: BIP39.generateEntropy())
    }

    var mnemonic: [String] {
        (try? BIP39.mnemonic(from: entropy)) ?? []
    }

    /// Stable public identifier used for API routing (base64url of the Ed25519 public key).
    var idString: String {
        signingKey.publicKey.rawRepresentation.base64URLEncodedString()
    }

    /// Human-comparable fingerprint, e.g. "R7KQ-2MXA-9F4T".
    var fingerprint: String {
        Self.fingerprint(of: signingKey.publicKey.rawRepresentation)
    }

    static func fingerprint(of publicKey: Data) -> String {
        let digest = Data(SHA256.hash(data: publicKey))
        let encoded = Base32.encode(digest.prefix(8)).prefix(12)
        return stride(from: 0, to: 12, by: 4)
            .map { String(Array(encoded)[$0..<($0 + 4)]) }
            .joined(separator: "-")
    }

    private static func derive(_ info: String, from entropy: Data) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: entropy),
            info: Data(info.utf8),
            outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
