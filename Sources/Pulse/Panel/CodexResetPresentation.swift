import Foundation

extension CodexResetEvent {
    /// The feed's title is Chinese; interface copy follows Pulse's selected language.
    var localizedTitle: String {
        switch (kind, status) {
        case (.resetCredit, .announced): String.localized("Reset credit announced")
        case (.resetCredit, .confirmed): String.localized("Reset credit confirmed")
        case (.directReset, .announced): String.localized("Limit reset announced")
        case (.directReset, .confirmed): String.localized("Limit reset confirmed")
        }
    }
}

extension CodexResetEvent.Post {
    struct Content: Equatable, Sendable {
        let text: String
        let isOriginal: Bool
    }

    /// AIhot supplies a Simplified Chinese translation and the source text, not localized versions for every interface language.
    func content(for locale: Locale) -> Content? {
        let language = locale.language
        let isSimplified = language.languageCode?.identifier == "zh"
            && language.script?.identifier != "Hant"
            && !["TW", "HK", "MO"].contains(language.region?.identifier ?? "")
        let translated = nonempty(text)
        let original = nonempty(originalText) ?? nonempty(fullOriginalText)
        if isSimplified, let translated { return Content(text: translated, isOriginal: false) }
        if let original { return Content(text: original, isOriginal: true) }
        return translated.map { Content(text: $0, isOriginal: false) }
    }

    private func nonempty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// Link order follows the selected language, never IP geolocation.
extension Locale {
    var prefersAIhotResetLink: Bool { language.languageCode?.identifier == "zh" }
}
