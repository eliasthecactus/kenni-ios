import Foundation
import Security

enum SeedVaultError: Error {
    case keychain(OSStatus)
    case encoding
}

/// One stored identity. `id` is the Ed25519 public key (base64url) — stable and
/// unique per identity. `name`/`lastUsedAt` power the restore chooser.
struct StoredIdentity: Codable, Identifiable, Equatable {
    let id: String
    var entropy: Data
    var name: String
    var createdAt: Date
    var lastUsedAt: Date
}

/// Keychain storage for identities. Supports several identities on one device.
///
/// - Every identity is stored device-local (`ThisDeviceOnly`) so the app works
///   with no iCloud at all.
/// - If the user opts in (asked during onboarding, before anything is written),
///   a second `kSecAttrSynchronizable` copy is stored → iCloud Keychain syncs and
///   backs it up. Toggling it off deletes only that synced copy.
enum SeedVault {
    private static let service = "ch.benavo.kenni.identity"
    private static let accountPrefix = "identity."

    // v1 single-identity accounts, migrated on first v2 launch.
    private static let legacyLocalAccount = "master-seed"
    private static let legacyICloudAccount = "master-seed-icloud"

    // MARK: Read

    /// All identities across local + iCloud, newest-used first, de-duplicated by id.
    static func allIdentities() -> [StoredIdentity] {
        var merged: [String: StoredIdentity] = [:]
        for record in loadAllRecords() {
            if let existing = merged[record.id], existing.lastUsedAt >= record.lastUsedAt {
                continue
            }
            merged[record.id] = record
        }
        return merged.values.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    static func identity(id: String) -> StoredIdentity? {
        allIdentities().first { $0.id == id }
    }

    /// True if a synchronizable (iCloud) copy exists for this identity.
    static func isICloudEnabled(id: String) -> Bool {
        loadData(account: accountPrefix + id, synchronizable: true) != nil
    }

    // MARK: Write

    static func save(_ record: StoredIdentity, iCloud: Bool) throws {
        guard let data = try? JSONEncoder().encode(record) else { throw SeedVaultError.encoding }
        try upsert(account: accountPrefix + record.id, data: data,
                   synchronizable: false, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        if iCloud {
            try upsert(account: accountPrefix + record.id, data: data,
                       synchronizable: true, accessible: kSecAttrAccessibleWhenUnlocked)
        } else {
            try delete(account: accountPrefix + record.id, synchronizable: true)
        }
    }

    /// Marks an identity as the most recently used one.
    static func touch(id: String) {
        guard var record = identity(id: id) else { return }
        record.lastUsedAt = .now
        try? save(record, iCloud: isICloudEnabled(id: id))
    }

    static func setICloud(_ enabled: Bool, id: String) throws {
        guard let record = identity(id: id) else { return }
        try save(record, iCloud: enabled)
    }

    static func remove(id: String) throws {
        try delete(account: accountPrefix + id, synchronizable: false)
        try delete(account: accountPrefix + id, synchronizable: true)
    }

    /// Removes every identity KENNI stored, on this device and in iCloud Keychain.
    static func wipeAll() throws {
        for record in allIdentities() { try remove(id: record.id) }
        try delete(account: legacyLocalAccount, synchronizable: false)
        try delete(account: legacyICloudAccount, synchronizable: true)
    }

    // MARK: Legacy migration (v1 → v2)

    /// Wraps a v1 single-seed install into the new per-identity format.
    /// `name` is used as the display name for the migrated identity.
    /// Returns the migrated identity's id, if any.
    @discardableResult
    static func migrateLegacyIfNeeded(name: @autoclosure () -> String) -> String? {
        let icloud = loadData(account: legacyICloudAccount, synchronizable: true)
        guard let entropy = loadData(account: legacyLocalAccount, synchronizable: false) ?? icloud,
              let identity = try? KenniIdentity(entropy: entropy) else {
            return nil
        }
        let record = StoredIdentity(id: identity.idString, entropy: entropy,
                                    name: name(), createdAt: .now, lastUsedAt: .now)
        try? save(record, iCloud: icloud != nil)
        try? delete(account: legacyLocalAccount, synchronizable: false)
        try? delete(account: legacyICloudAccount, synchronizable: true)
        return record.id
    }

    // MARK: Keychain plumbing

    private static func loadAllRecords() -> [StoredIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(accountPrefix),
                  let data = item[kSecValueData as String] as? Data,
                  let record = try? JSONDecoder().decode(StoredIdentity.self, from: data) else {
                return nil
            }
            return record
        }
    }

    private static func upsert(account: String, data: Data, synchronizable: Bool,
                               accessible: CFString) throws {
        try delete(account: account, synchronizable: synchronizable)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SeedVaultError.keychain(status) }
    }

    private static func loadData(account: String, synchronizable: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(account: String, synchronizable: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        query[kSecAttrSynchronizable as String] = synchronizable
            ? (kCFBooleanTrue as Any) : (kCFBooleanFalse as Any)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SeedVaultError.keychain(status)
        }
    }
}
