import SwiftUI
import Combine

@MainActor
final class Localization: ObservableObject {
    @AppStorage("language") var language = "system" {
        didSet { objectWillChange.send() }
    }

    var isEnglish: Bool {
        LocalizationPreference.isEnglish(for: language)
    }

    func s(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
}

enum LocalizationPreference {
    nonisolated static func isEnglish(for language: String) -> Bool {
        switch language {
        case "en": return true
        case "zh": return false
        default: return !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
        }
    }
}
