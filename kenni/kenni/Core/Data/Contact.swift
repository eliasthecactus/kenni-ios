import Foundation
import SwiftData

enum TrustLevel: String {
    /// Keys exchanged (QR or link) — signature checked, but liveness not proven.
    case exchanged
    /// Passed an in-person live challenge — this human holds this key.
    case verified
}

enum ExchangeMethod: String {
    case qr
    case link
}

@Model
final class Contact {
    @Attribute(.unique) var idKey: Data  // Ed25519 public key — the contact's identity
    var kaKey: Data                       // X25519 public key
    var name: String
    var avatarData: Data?
    /// X25519 shared secret — identical on both phones, never transmitted.
    var pairwiseSecret: Data
    var trustLevelRaw: String
    var methodRaw: String
    var addedAt: Date
    var verifiedAt: Date?

    init(idKey: Data, kaKey: Data, name: String, pairwiseSecret: Data,
         trustLevel: TrustLevel = .exchanged, method: ExchangeMethod = .qr,
         addedAt: Date = .now) {
        self.idKey = idKey
        self.kaKey = kaKey
        self.name = name
        self.pairwiseSecret = pairwiseSecret
        self.trustLevelRaw = trustLevel.rawValue
        self.methodRaw = method.rawValue
        self.addedAt = addedAt
    }

    var trustLevel: TrustLevel {
        get { TrustLevel(rawValue: trustLevelRaw) ?? .exchanged }
        set { trustLevelRaw = newValue.rawValue }
    }

    var fingerprint: String { KenniIdentity.fingerprint(of: idKey) }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
}

enum VerificationKind: String {
    case inPerson
    case call      // M5
    case offline   // M6
}

@Model
final class VerificationRecord {
    var contactIdKey: Data
    var kindRaw: String
    var succeeded: Bool
    var date: Date

    init(contactIdKey: Data, kind: VerificationKind, succeeded: Bool, date: Date = .now) {
        self.contactIdKey = contactIdKey
        self.kindRaw = kind.rawValue
        self.succeeded = succeeded
        self.date = date
    }

    var kind: VerificationKind { VerificationKind(rawValue: kindRaw) ?? .inPerson }
}
