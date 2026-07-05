import Foundation
import Observation

enum OnboardingStep: Hashable {
    case story
    case choice
    case icloudBackup
    case phrase
    case confirmPhrase
    case restore
    case lockSetup
    case profile
    case notifications
    case done
}

/// Drives the onboarding NavigationStack. The iCloud decision is made *before*
/// any key is written, so nothing ever syncs without asking:
/// new:     story → choice → iCloud → phrase → confirm → lock → profile → notifications → done
/// restore: story → choice → restore → iCloud → lock → profile → notifications → done
@Observable
final class OnboardingModel {
    var path: [OnboardingStep] = []
    var draft: KenniIdentity?
    var iCloudBackup = true
    var isRestore = false
    var name = ""

    func startNew() {
        guard let identity = try? KenniIdentity.generate() else { return }
        draft = identity
        isRestore = false
        iCloudBackup = true
        path.append(.icloudBackup)
    }

    func startRestore() {
        isRestore = true
        path.append(.restore)
    }

    func restored(identity: KenniIdentity, record: StoredIdentity? = nil, fromICloud: Bool) {
        draft = identity
        if let record { name = record.name }
        iCloudBackup = fromICloud || SeedVault.isICloudEnabled(id: identity.idString)
        path.append(.icloudBackup)
    }

    /// iCloud choice made — new users still need to see their phrase; returning
    /// users go straight to setting up the lock.
    func backupChosen() {
        path.append(isRestore ? .lockSetup : .phrase)
    }

    func phraseConfirmed() { path.append(.lockSetup) }
    func lockConfigured() { path.append(.profile) }
    func profileDone() { path.append(.notifications) }
    func notificationsDone() { path.append(.done) }
}
