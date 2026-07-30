import CryptoKit
import Foundation
import Observation
import Security

struct BusinessInstallation: Codable, Equatable {
    enum Status: String, Codable {
        case active
        case revoked
    }

    let deviceID: UUID
    let deviceLabel: String
    var business: BusinessProfile
    var privateKey: Data?
    var status: Status
    var revokedAt: Date?

    var client: BusinessAPIClient? {
        guard status == .active, let privateKey,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey) else {
            return nil
        }
        return BusinessAPIClient(deviceID: deviceID, signingKey: key)
    }
}

enum BusinessEnrollmentError: Error {
    case persistence
}

@MainActor
@Observable
final class BusinessCredentialStore {
    private static let service = "ch.benavo.kenni.business"
    private static let account = "installation"

    private(set) var installation: BusinessInstallation?
    private(set) var isRefreshing = false

    init() {
        installation = Self.load()
    }

    func enroll(link: BusinessEnrollmentLink) async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let claimed = try await BusinessAPIClient.claim(token: link.token, signingKey: signingKey)
        let installation = BusinessInstallation(
            deviceID: claimed.deviceID,
            deviceLabel: claimed.deviceLabel,
            business: claimed.business,
            privateKey: signingKey.rawRepresentation,
            status: .active,
            revokedAt: nil)
        try Self.save(installation)
        self.installation = installation
    }

    func refreshStatus() async {
        guard let client = installation?.client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let status = try await client.status()
            guard var current = installation else { return }
            current.business = status.business
            if status.status == "revoked" {
                current.status = .revoked
                current.revokedAt = status.revokedAt.map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                } ?? .now
                current.privateKey = nil
            }
            try Self.save(current)
            installation = current
        } catch APIError.http(410, _) {
            revokeLocally()
        } catch {
            // Connectivity failures must not destroy the device credential. The
            // confirmation endpoint performs the authoritative active check.
        }
    }

    func handleRevocationPush() async {
        await refreshStatus()
    }

    func logout() {
        Self.delete()
        installation = nil
    }

    private func revokeLocally() {
        guard var current = installation else { return }
        current.status = .revoked
        current.revokedAt = .now
        current.privateKey = nil
        try? Self.save(current)
        installation = current
    }

    private static func save(_ installation: BusinessInstallation) throws {
        let data = try JSONEncoder().encode(installation)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw BusinessEnrollmentError.persistence }
    }

    private static func load() -> BusinessInstallation? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(BusinessInstallation.self, from: data)
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
