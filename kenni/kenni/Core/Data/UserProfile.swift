import Foundation
import SwiftData

/// The user's own card. Exactly one instance exists after onboarding.
@Model
final class UserProfile {
    var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
