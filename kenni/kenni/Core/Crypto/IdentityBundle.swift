import Foundation
import CryptoKit

enum BundleError: Error {
    case malformed
    case badSignature
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}

/// The signed identity card exchanged via QR code or link.
/// Self-contained and verifiable offline: the signature covers the keys and name,
/// so nobody can swap a name onto someone else's keys.
struct IdentityBundle: Codable, Equatable {
    static let qrPrefix = "KENNI1:"
    private static let context = "kenni/v1/bundle"

    let v: Int
    let id: Data   // Ed25519 public key (32 bytes)
    let ka: Data   // X25519 public key (32 bytes)
    let name: String
    let sig: Data  // Ed25519 signature over context ‖ id ‖ ka ‖ name

    init(v: Int, id: Data, ka: Data, name: String, sig: Data) {
        self.v = v
        self.id = id
        self.ka = ka
        self.name = name
        self.sig = sig
    }

    static func make(identity: KenniIdentity, name: String) throws -> IdentityBundle {
        let id = identity.signingKey.publicKey.rawRepresentation
        let ka = identity.agreementKey.publicKey.rawRepresentation
        let sig = try identity.signingKey.signature(for: message(id: id, ka: ka, name: name))
        return IdentityBundle(v: 1, id: id, ka: ka, name: name, sig: sig)
    }

    var isValid: Bool {
        guard v == 1, id.count == 32, ka.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: id) else {
            return false
        }
        return key.isValidSignature(sig, for: Self.message(id: id, ka: ka, name: name))
    }

    var fingerprint: String { KenniIdentity.fingerprint(of: id) }

    // MARK: QR / link encoding

    var qrString: String {
        guard let json = try? JSONEncoder().encode(self) else { return "" }
        return Self.qrPrefix + json.base64URLEncodedString()
    }

    init?(qrString: String) {
        guard qrString.hasPrefix(Self.qrPrefix),
              let data = Data(base64URLEncoded: String(qrString.dropFirst(Self.qrPrefix.count))),
              let bundle = try? JSONDecoder().decode(IdentityBundle.self, from: data),
              bundle.isValid else {
            return nil
        }
        self = bundle
    }

    // MARK: Shareable link (fully offline)
    //
    // The bundle is public identity data — the same thing the QR shows — so it can
    // ride *inside* the link. We use the app's own `kenni://` URL scheme, so a link
    // opens the app directly with no server, no website, and no connectivity.

    static let urlScheme = "kenni"

    /// base64url of the bundle JSON (the `?b=` value, without the QR prefix).
    var linkParam: String {
        (try? JSONEncoder().encode(self))?.base64URLEncodedString() ?? ""
    }

    var shareURL: URL? {
        URL(string: "\(Self.urlScheme)://x?b=\(linkParam)")
    }

    init?(linkParam: String) {
        guard let data = Data(base64URLEncoded: linkParam),
              let bundle = try? JSONDecoder().decode(IdentityBundle.self, from: data),
              bundle.isValid else {
            return nil
        }
        self = bundle
    }

    private static func message(id: Data, ka: Data, name: String) -> Data {
        Data(context.utf8) + id + ka + Data(name.utf8)
    }
}

/// Shared secret between two users, derived on exchange. Identical on both sides,
/// never transmitted. Powers the offline verification codes.
enum Pairwise {
    static func secret(myAgreementKey: Curve25519.KeyAgreement.PrivateKey,
                       theirAgreementKey: Data) throws -> Data {
        let theirKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirAgreementKey)
        let shared = try myAgreementKey.sharedSecretFromKeyAgreement(with: theirKey)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("kenni/v1/pair".utf8),
            outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }
}

// MARK: - In-person live verification

/// A shows this QR; B signs it; A checks the signature against B's *stored* key.
struct VerifyChallenge: Codable {
    static let qrPrefix = "KENNIC1:"

    let n: Data // 32-byte nonce

    static func make() throws -> VerifyChallenge {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw IdentityError.randomFailure
        }
        return VerifyChallenge(n: Data(bytes))
    }

    var qrString: String {
        guard let json = try? JSONEncoder().encode(self) else { return "" }
        return Self.qrPrefix + json.base64URLEncodedString()
    }

    init?(qrString: String) {
        guard qrString.hasPrefix(Self.qrPrefix),
              let data = Data(base64URLEncoded: String(qrString.dropFirst(Self.qrPrefix.count))),
              let challenge = try? JSONDecoder().decode(VerifyChallenge.self, from: data),
              challenge.n.count == 32 else {
            return nil
        }
        self = challenge
    }

    private init(n: Data) { self.n = n }
}

struct VerifyResponse: Codable {
    static let qrPrefix = "KENNIR1:"
    private static let context = "kenni/v1/challenge-response"

    let id: Data  // responder's Ed25519 public key
    let n: Data   // echoed nonce
    let sig: Data

    static func make(challenge: VerifyChallenge, identity: KenniIdentity) throws -> VerifyResponse {
        let id = identity.signingKey.publicKey.rawRepresentation
        let sig = try identity.signingKey.signature(for: message(nonce: challenge.n, responder: id))
        return VerifyResponse(id: id, n: challenge.n, sig: sig)
    }

    /// Valid only if signed by `expectedKey` (the contact's stored key) over `challenge`'s nonce.
    func isValid(challenge: VerifyChallenge, expectedKey: Data) -> Bool {
        guard n == challenge.n, id == expectedKey,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: id) else {
            return false
        }
        return key.isValidSignature(sig, for: Self.message(nonce: n, responder: id))
    }

    var qrString: String {
        guard let json = try? JSONEncoder().encode(self) else { return "" }
        return Self.qrPrefix + json.base64URLEncodedString()
    }

    init?(qrString: String) {
        guard qrString.hasPrefix(Self.qrPrefix),
              let data = Data(base64URLEncoded: String(qrString.dropFirst(Self.qrPrefix.count))),
              let response = try? JSONDecoder().decode(VerifyResponse.self, from: data) else {
            return nil
        }
        self = response
    }

    private init(id: Data, n: Data, sig: Data) {
        self.id = id
        self.n = n
        self.sig = sig
    }

    private static func message(nonce: Data, responder: Data) -> Data {
        Data(context.utf8) + nonce + responder
    }
}
