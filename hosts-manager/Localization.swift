import SwiftUI
import Combine

@MainActor
final class Localization: ObservableObject {
    @AppStorage("language") var language = "system" {
        didSet {
            objectWillChange.send()
            LocalizationPreference.applyAppleLanguages(for: language)
        }
    }

    var isEnglish: Bool {
        LocalizationPreference.isEnglish(for: language)
    }

    func s(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
}

nonisolated enum LocalizationPreference {
    nonisolated static func isEnglish(for language: String) -> Bool {
        switch language {
        case "en": return true
        case "zh": return false
        default: return !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
        }
    }

    static func applyAppleLanguages(for language: String) {
        let defaults = UserDefaults.standard
        switch language {
        case "zh":
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case "en":
            defaults.set(["en"], forKey: "AppleLanguages")
        default:
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}
