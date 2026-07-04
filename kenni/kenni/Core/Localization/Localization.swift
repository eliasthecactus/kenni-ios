import Foundation
import Observation

/// Supported app languages. Auto-picked from the device, overridable in onboarding/settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }

    /// English name — shown as a secondary label so the list is searchable
    /// even when the user can't read the native script.
    var englishName: String {
        switch self {
        case .english: "English"
        case .german: "German"
        case .spanish: "Spanish"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .german: "🇩🇪"
        case .spanish: "🇪🇸"
        }
    }

    static var deviceDefault: AppLanguage {
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2)).lowercased()
            if let match = AppLanguage(rawValue: code) { return match }
        }
        return .english
    }
}

@Observable
final class LanguageStore {
    static let shared = LanguageStore()
    private static let defaultsKey = "kenni.language"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            // Also steer the system per-app language (permission dialogs, plurals)
            // from the next launch on.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            language = .deviceDefault
        }
    }

    /// English source strings double as keys; missing translations fall back to English.
    func localized(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Shorthand used throughout the UI. Reading it inside a view body makes SwiftUI
/// re-render when the language changes.
func L(_ key: String) -> String {
    LanguageStore.shared.localized(key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: LanguageStore.shared.localized(key), arguments: args)
}
