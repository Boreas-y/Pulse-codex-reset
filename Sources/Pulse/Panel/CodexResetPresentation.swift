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

/// Formats absolute feed instants in the user's time zone, independently of UI language.
enum CodexResetTime {
    static func local(_ date: Date, locale: Locale, timeZone: TimeZone, includesTime: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(includesTime ? "MMMdjmm" : "MMMd")
        let offset = timeZone.secondsFromGMT(for: date)
        let magnitude = abs(offset)
        let zone = String(format: "UTC%@%02d:%02d", offset < 0 ? "−" : "+", magnitude / 3600, magnitude % 3600 / 60)
        return "\(formatter.string(from: date)) · \(zone)"
    }

    static func relative(from now: Date, to date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

extension CodexResetEvent {
    func timingDescription(locale: Locale, timeZone: TimeZone) -> String {
        if status == .confirmed {
            guard let confirmedAt else { return String.localized("Confirmed recently") }
            let time = CodexResetTime.local(confirmedAt, locale: locale, timeZone: timeZone)
            return String.localized("Confirmation reported \(time)")
        }
        guard let schedule else { return String.localized("Time not specified") }
        let start = CodexResetTime.local(schedule.from, locale: locale, timeZone: timeZone)
        let end = CodexResetTime.local(schedule.through, locale: locale, timeZone: timeZone)
        switch schedule.precision {
        case .deadline: return String.localized("Expected by \(end)")
        case .exact: return String.localized("Expected at \(start)")
        case .approximate:
            return schedule.from == schedule.through
                ? String.localized("Expected around \(start)")
                : String.localized("Expected between \(start) and \(end)")
        case .date:
            let firstDay = CodexResetTime.local(schedule.from, locale: locale, timeZone: timeZone, includesTime: false)
            let lastDay = CodexResetTime.local(schedule.through, locale: locale, timeZone: timeZone, includesTime: false)
            return firstDay == lastDay
                ? String.localized("Expected around \(firstDay)")
                : String.localized("Expected between \(firstDay) and \(lastDay)")
        case .window: return String.localized("Expected between \(start) and \(end)")
        }
    }

    func relativeTiming(at now: Date, locale: Locale, timeZone: TimeZone) -> String? {
        guard status == .announced, let schedule else { return nil }
        if now > schedule.through { return String.localized("Awaiting confirmation") }
        if schedule.precision == .date { return nil }
        if schedule.precision == .deadline {
            let remaining = CodexResetTime.relative(from: now, to: schedule.through, locale: locale, timeZone: timeZone)
            return String.localized("Deadline · \(remaining)")
        }
        if now < schedule.from {
            let remaining = CodexResetTime.relative(from: now, to: schedule.from, locale: locale, timeZone: timeZone)
            return String.localized("Expected \(remaining)")
        }
        return schedule.precision == .exact
            ? String.localized("Expected now")
            : String.localized("Expected window is open")
    }
}
