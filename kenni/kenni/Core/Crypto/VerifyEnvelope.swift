import Foundation
import CryptoKit

/// A signed call-verification request. The server relays it blindly; the target
/// phone validates the signature against the *stored* contact key.
struct VerifyRequestEnvelope: Codable {
    private static let context = "kenni/v1/verify-req"
    static let ttl: TimeInterval = 90

    let reqID: String
    let nonce: Data   // 32 bytes, single use
    let from: Data    // requester Ed25519 public key
    let to: Data      // target Ed25519 public key
    let ts: Double    // unix seconds
    let sig: Data

    static func make(identity: KenniIdentity, to: Data) throws -> VerifyRequestEnvelope {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw IdentityError.randomFailure
        }
        let reqID = UUID().uuidString
        let nonce = Data(bytes)
        let from = identity.signingKey.publicKey.rawRepresentation
        let ts = Date().timeIntervalSince1970
        let sig = try identity.signingKey.signature(
            for: message(reqID: reqID, nonce: nonce, from: from, to: to, ts: ts))
        return VerifyRequestEnvelope(reqID: reqID, nonce: nonce, from: from, to: to, ts: ts, sig: sig)
    }

    /// `expectedFrom` is the stored key of the contact this claims to come from.
    func isValid(expectedFrom: Data?) -> Bool {
        if let expectedFrom, from != expectedFrom { return false }
        guard nonce.count == 32,
              abs(Date().timeIntervalSince1970 - ts) <= Self.ttl,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: from) else {
            return false
        }
        return key.isValidSignature(
            sig, for: Self.message(reqID: reqID, nonce: nonce, from: from, to: to, ts: ts))
    }

    var payloadString: String {
        (try? JSONEncoder().encode(self))?.base64URLEncodedString() ?? ""
    }

    init?(payloadString: String) {
        guard let data = Data(base64URLEncoded: payloadString),
              let envelope = try? JSONDecoder().decode(VerifyRequestEnvelope.self, from: data) else {
            return nil
        }
        self = envelope
    }

    init(reqID: String, nonce: Data, from: Data, to: Data, ts: Double, sig: Data) {
        self.reqID = reqID
        self.nonce = nonce
        self.from = from
        self.to = to
        self.ts = ts
        self.sig = sig
    }

    private static func message(reqID: String, nonce: Data, from: Data, to: Data, ts: Double) -> Data {
        Data(context.utf8) + Data(reqID.utf8) + nonce + from + to + Data(String(Int(ts)).utf8)
    }
}

/// The signed answer: "yes, I'm on this call" or "no, I am NOT".
struct VerifyAnswerEnvelope: Codable {
    private static let context = "kenni/v1/verify-ans"

    let reqID: String
    let nonce: Data   // echoed from the request — binds the answer to it
    let answer: Bool
    let ts: Double
    let sig: Data

    static func make(request: VerifyRequestEnvelope, answer: Bool,
                     identity: KenniIdentity) throws -> VerifyAnswerEnvelope {
        let ts = Date().timeIntervalSince1970
        let sig = try identity.signingKey.signature(
            for: message(reqID: request.reqID, nonce: request.nonce, answer: answer, ts: ts))
        return VerifyAnswerEnvelope(reqID: request.reqID, nonce: request.nonce,
                                    answer: answer, ts: ts, sig: sig)
    }

    /// Valid only if signed by the contact's stored key over *this* request's nonce.
    func isValid(request: VerifyRequestEnvelope, responderKey: Data) -> Bool {
        guard reqID == request.reqID, nonce == request.nonce,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: responderKey) else {
            return false
        }
        return key.isValidSignature(
            sig, for: Self.message(reqID: reqID, nonce: nonce, answer: answer, ts: ts))
    }

    var payloadString: String {
        (try? JSONEncoder().encode(self))?.base64URLEncodedString() ?? ""
    }

    init?(payloadString: String) {
        guard let data = Data(base64URLEncoded: payloadString),
              let envelope = try? JSONDecoder().decode(VerifyAnswerEnvelope.self, from: data) else {
            return nil
        }
        self = envelope
    }

    init(reqID: String, nonce: Data, answer: Bool, ts: Double, sig: Data) {
        self.reqID = reqID
        self.nonce = nonce
        self.answer = answer
        self.ts = ts
        self.sig = sig
    }

    private static func message(reqID: String, nonce: Data, answer: Bool, ts: Double) -> Data {
        Data(context.utf8) + Data(reqID.utf8) + nonce
            + Data([answer ? 1 : 0]) + Data(String(Int(ts)).utf8)
    }
}

/// Spoken 6-digit codes for verification without any internet — powered by the
/// pairwise secret both phones derived at exchange time.
enum OfflineCodes {
    static func randomChallenge() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// Response = first 6 digits of HMAC-SHA256(pairwise secret, context ‖ challenge).
    /// The direction tag prevents echoing a code back as an answer.
    static func response(secret: Data, challenge: String) -> String {
        let message = Data("kenni/v1/offline".utf8) + Data(challenge.utf8) + Data("response".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        let bytes = Data(mac)
        // RFC 4226-style dynamic truncation → 6 decimal digits.
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let value = (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return String(format: "%06d", value % 1_000_000)
    }
}
