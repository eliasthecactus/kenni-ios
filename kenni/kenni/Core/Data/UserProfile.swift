import Foundation
import SwiftData

/// The user's own card. Exactly one instance exists after onboarding.
@Model
final class UserProfile {
    var name: String
    var avatarData: Data?
    var createdAt: Date

    init(name: String, avatarData: Data? = nil, createdAt: Date = .now) {
        self.name = name
        self.avatarData = avatarData
        self.createdAt = createdAt
    }
}
