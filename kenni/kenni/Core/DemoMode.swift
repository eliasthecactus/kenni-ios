#if DEBUG
import Foundation
import SwiftData

/// Screenshot/e2e support, DEBUG builds only.
///
///   --demo               seed a deterministic identity, profile and contacts
///   --screen <name>      render one screen directly: home | contact | business |
///                        offline | mycode | livecheck | incoming
///   --request <id>       request id for the incoming screen
///
/// Everything is deterministic: the own identity and all demo contacts derive from
/// fixed entropy, so external test scripts can sign as "Ladina" and the app will
/// recognize her.
enum DemoMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
    }

    static var screen: String? {
        argumentValue(after: "--screen")
    }

    static var requestID: String? {
        argumentValue(after: "--request")
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static let ownEntropy = Data(repeating: 0xAA, count: 16)

    static func contactIdentity(_ seed: UInt8) throws -> KenniIdentity {
        try KenniIdentity(entropy: Data(repeating: seed, count: 16))
    }

    static func seed(identityStore: IdentityStore, container: ModelContainer) {
        guard isActive else { return }
        do {
            if !identityStore.isOnboarded {
                try identityStore.adopt(KenniIdentity(entropy: ownEntropy), name: "Elias", iCloudBackup: false)
            }
            if identityStore.identity == nil {
                identityStore.loadFromVault()
            }

            let context = container.mainContext
            if try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
                context.insert(UserProfile(name: "Elias"))
            }
            if try context.fetch(FetchDescriptor<Contact>()).isEmpty,
               let me = identityStore.identity {
                let demo: [(String, UInt8, TrustLevel, ExchangeMethod)] = [
                    ("Ladina Frehner", 0x01, .verified, .qr),
                    ("Marco Keller", 0x02, .exchanged, .qr),
                    ("Sara Bianchi", 0x03, .exchanged, .link),
                ]
                for (name, seed, trust, method) in demo {
                    let identity = try contactIdentity(seed)
                    let contact = Contact(
                        idKey: identity.signingKey.publicKey.rawRepresentation,
                        kaKey: identity.agreementKey.publicKey.rawRepresentation,
                        name: name,
                        pairwiseSecret: try Pairwise.secret(
                            myAgreementKey: me.agreementKey,
                            theirAgreementKey: identity.agreementKey.publicKey.rawRepresentation),
                        trustLevel: trust,
                        method: method,
                        addedAt: Date().addingTimeInterval(-Double.random(in: 3...40) * 86_400))
                    if trust == .verified {
                        contact.verifiedAt = Date().addingTimeInterval(-2 * 86_400)
                        context.insert(VerificationRecord(
                            contactIdKey: contact.idKey, kind: .inPerson, succeeded: true,
                            date: Date().addingTimeInterval(-2 * 86_400)))
                        context.insert(VerificationRecord(
                            contactIdKey: contact.idKey, kind: .call, succeeded: true,
                            date: Date().addingTimeInterval(-3_600)))
                    }
                    context.insert(contact)
                }
            }
            try context.save()
        } catch {
            assertionFailure("demo seeding failed: \(error)")
        }
    }
}

import SwiftUI
import CryptoKit

/// Renders one screen directly for screenshots — bypasses navigation.
struct DemoScreenHost: View {
    let screen: String
    @Query(sort: \Contact.name) private var contacts: [Contact]

    var body: some View {
        switch screen {
        case "contact":
            if let first = contacts.first {
                NavigationStack { ContactDetailView(contact: first) }
                    .tint(.kenniBlue)
            }
        case "offline":
            if let first = contacts.first {
                OfflineVerifyView(contact: first)
            }
        case "livecheck":
            if let first = contacts.first {
                VerifyCallView(contact: first)
            }
        case "mycode":
            ExchangeView()
        case "business":
            BusinessIdentificationView()
        case "settings":
            SettingsView()
        case "reset":
            ResetView()
        case "incoming":
            if let requestID = DemoMode.requestID {
                IncomingRequestView(requestID: requestID)
            }
        default:
            HomeView()
        }
    }
}
#endif
