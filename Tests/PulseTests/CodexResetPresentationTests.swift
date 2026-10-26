import AppKit
import Foundation
import Testing
@testable import Pulse

struct CodexResetPresentationTests {
    private func post(original: String? = "Source post", full: String? = nil, text: String = "中文译文") -> CodexResetEvent.Post {
        .init(publishedAt: .distantPast, text: text, originalText: original,
              fullOriginalText: full, url: URL(string: "https://x.com/example/status/1")!)
    }

    @Test(arguments: ["en_US", "zh_Hant", "zh_TW", "zh_HK", "ja_JP", "ko_KR", "ru_RU"])
    func usesAttributedOriginalOutsideSimplifiedChinese(locale: String) {
        #expect(post().content(for: Locale(identifier: locale)) == .init(text: "Source post", isOriginal: true))
    }

    @Test(arguments: ["zh_Hans", "zh_CN", "zh_SG"])
    func usesChineseTranslation(locale: String) {
        #expect(post().content(for: Locale(identifier: locale)) == .init(text: "中文译文", isOriginal: false))
    }

    @Test func handlesMissingAndBlankSourceFields() {
        let english = Locale(identifier: "en_US")
        #expect(post(original: "  ", full: " Full source \n").content(for: english) == .init(text: "Full source", isOriginal: true))
        #expect(post(original: nil).content(for: english) == .init(text: "中文译文", isOriginal: false))
        #expect(post(original: nil, text: " \n").content(for: english) == nil)
        #expect(post(text: " ").content(for: Locale(identifier: "zh_CN"))?.isOriginal == true)
    }

    @Test func keepsBothLinksIndependentOfLocation() {
        #expect(Locale(identifier: "zh_CN").prefersAIhotResetLink)
        #expect(Locale(identifier: "zh_Hant").prefersAIhotResetLink)
        #expect(!Locale(identifier: "en_CN").prefersAIhotResetLink)
        #expect(!Locale(identifier: "ja_JP").prefersAIhotResetLink)
    }

    @Test @MainActor func nativeLinkAcceptsFirstClickAndOpensItsOwnDestination() throws {
        _ = NSApplication.shared
        let button = PanelLinkButton()
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        button.updateTrackingAreas()
        #expect(button.trackingAreas.contains { $0.options.contains([.activeAlways, .mouseEnteredAndExited, .inVisibleRect]) })
        var opened: [URL] = []
        button.open = { opened.append($0) }
        #expect(button.acceptsFirstMouse(for: nil))
        for source in ["https://aihot.news/codex-reset", "https://x.com/example/status/1"] {
            let url = try #require(URL(string: source))
            button.destination = url
            button.performClick(nil)
            #expect(opened.last == url)
        }
        button.destination = URL(fileURLWithPath: "/tmp/not-a-source")
        button.performClick(nil)
        #expect(opened.count == 2)
    }
}

extension PanelGlobalsSuite {
    @Suite(.serialized)
    struct CodexResetLocalizedTitleTests {
        @Test @MainActor func usesSelectedLanguageInsteadOfFeedTitle() {
            let previous = LocalizationSource.language
            defer { LocalizationSource.use(previous) }
            let cases: [(AppLanguage, String)] = [
                (.english, "Limit reset announced"),
                (.chineseSimplified, "额度重置预告"),
                (.chineseTraditional, "額度重置預告"),
                (.japanese, "利用上限リセットの予告"),
                (.korean, "사용 한도 초기화 예고"),
                (.russian, "Объявлен сброс лимита")
            ]
            let event = CodexResetEvent(
                id: "title", kind: .directReset, status: .announced,
                title: "Feed title must not leak into other languages", scope: "all",
                createdAt: .distantPast, updatedAt: .distantPast, confirmedAt: nil,
                schedule: nil, posts: [], url: URL(string: "https://aihot.news/codex-reset")!
            )
            for (language, expected) in cases {
                LocalizationSource.use(language)
                #expect(event.localizedTitle == expected)
            }
        }
    }
}

struct CodexResetTimeZoneTests {
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func oneInstantHasDifferentLocalClockTimes() {
        let date = instant("2026-10-25T07:00:00Z")
        let locale = Locale(identifier: "en_GB")
        let china = CodexResetTime.local(date, locale: locale, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let japan = CodexResetTime.local(date, locale: locale, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let california = CodexResetTime.local(date, locale: locale, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(china.contains("15:00") && china.contains("UTC+08:00"))
        #expect(japan.contains("16:00") && japan.contains("UTC+09:00"))
        #expect(california.contains("00:00") && california.contains("UTC−07:00"))
    }

    @Test func daylightSavingOffsetBelongsToEventDate() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let locale = Locale(identifier: "en_GB")
        let before = CodexResetTime.local(instant("2026-11-01T08:30:00Z"), locale: locale, timeZone: zone)
        let after = CodexResetTime.local(instant("2026-11-01T09:30:00Z"), locale: locale, timeZone: zone)
        #expect(before.contains("01:30") && before.contains("UTC−07:00"))
        #expect(after.contains("01:30") && after.contains("UTC−08:00"))
    }

    @Test func languageDoesNotChooseTimeZone() {
        let date = instant("2026-10-25T07:00:00Z")
        let china = TimeZone(identifier: "Asia/Shanghai")!
        #expect(CodexResetTime.local(date, locale: Locale(identifier: "ja_JP"), timeZone: china).contains("UTC+08:00"))
        #expect(CodexResetTime.local(date, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "Asia/Kathmandu")!).contains("UTC+05:45"))
    }
}

extension PanelGlobalsSuite {
    @Suite(.serialized)
    struct CodexResetTimingCopyTests {
        @Test @MainActor func deadlineAndWindowKeepTheirMeaning() {
            let previous = LocalizationSource.language
            defer { LocalizationSource.use(previous) }
            LocalizationSource.use(.english)
            let from = Date(timeIntervalSince1970: 1_800_000_000)
            let through = from.addingTimeInterval(3600)
            let locale = Locale(identifier: "en_GB")
            let zone = TimeZone(secondsFromGMT: 0)!
            func event(_ precision: CodexResetEvent.Schedule.Precision) -> CodexResetEvent {
                .init(id: "timing", kind: .directReset, status: .announced, title: "", scope: "", createdAt: from, updatedAt: from,
                      confirmedAt: nil, schedule: .init(precision: precision, from: from, through: through, label: "北京时间"), posts: [],
                      url: URL(string: "https://aihot.news/codex-reset")!)
            }
            let deadline = event(.deadline)
            #expect(deadline.timingDescription(locale: locale, timeZone: zone) == "Expected by " + CodexResetTime.local(through, locale: locale, timeZone: zone))
            let dateOnly = event(.date)
            #expect(!dateOnly.timingDescription(locale: locale, timeZone: zone).components(separatedBy: " · ")[0].contains(":"))
            #expect(dateOnly.relativeTiming(at: from.addingTimeInterval(-3600), locale: locale, timeZone: zone) == nil)
            #expect(event(.window).timingDescription(locale: locale, timeZone: zone).contains(" and "))
            #expect(deadline.relativeTiming(at: from, locale: locale, timeZone: zone)?.hasPrefix("Deadline") == true)
            #expect(deadline.relativeTiming(at: through.addingTimeInterval(1), locale: locale, timeZone: zone) == "Awaiting confirmation")
        }
    }
}
