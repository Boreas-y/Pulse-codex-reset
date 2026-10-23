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
