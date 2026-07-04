import Foundation
import Observation

/// App-level identity state: whether onboarding is complete and the active
/// identity loaded from the Keychain vault. Supports several stored identities.
@Observable
final class IdentityStore {
    private static let onboardedKey = "kenni.onboarded"
    private static let activeIDKey = "kenni.activeIdentity"

    private(set) var identity: KenniIdentity?

    /// Stored (not computed) so `@Observable` tracks it — views that switch on
    /// onboarding state must re-render the moment it flips, even while `identity`
    /// is still nil (e.g. right after a reset). Persisted to UserDefaults.
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedKey) }
    }

    /// The active identity's id (Ed25519 pubkey, base64url).
    private var activeID: String? {
        get { UserDefaults.standard.string(forKey: Self.activeIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.activeIDKey) }
    }

    init() {
        isOnboarded = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        if isOnboarded {
            loadFromVault()
        }
    }

    func loadFromVault() {
        // Prefer the explicitly active identity; fall back to the most recent.
        let record = activeID.flatMap { SeedVault.identity(id: $0) } ?? SeedVault.allIdentities().first
        guard let record, let identity = try? KenniIdentity(entropy: record.entropy) else { return }
        self.identity = identity
        activeID = record.id
        SeedVault.touch(id: record.id)
    }

    /// True once the vault holds at least one identity (used to skip migration work).
    var hasStoredIdentity: Bool { !SeedVault.allIdentities().isEmpty }

    var iCloudEnabledForActive: Bool {
        guard let id = identity?.idString else { return false }
        return SeedVault.isICloudEnabled(id: id)
    }

    /// Persists a freshly created or restored identity and marks onboarding done.
    func adopt(_ identity: KenniIdentity, name: String, iCloudBackup: Bool) throws {
        let existing = SeedVault.identity(id: identity.idString)
        let record = StoredIdentity(
            id: identity.idString,
            entropy: identity.entropy,
            name: name,
            createdAt: existing?.createdAt ?? .now,
            lastUsedAt: .now)
        try SeedVault.save(record, iCloud: iCloudBackup)
        self.identity = identity
        activeID = identity.idString
        isOnboarded = true
    }

    func setICloudBackupForActive(_ enabled: Bool) {
        guard let id = identity?.idString else { return }
        try? SeedVault.setICloud(enabled, id: id)
    }

    /// Keeps the stored display name in step with edits to the profile.
    func updateStoredName(_ name: String) {
        guard let id = identity?.idString, var record = SeedVault.identity(id: id) else { return }
        record.name = name
        try? SeedVault.save(record, iCloud: SeedVault.isICloudEnabled(id: id))
    }

    /// Full reset: forget the active identity from memory and clear onboarding.
    /// `wipeKeychain` also erases every stored identity (local + iCloud).
    func reset(wipeKeychain: Bool) {
        if wipeKeychain { try? SeedVault.wipeAll() }
        identity = nil
        activeID = nil
        isOnboarded = false
    }
}
