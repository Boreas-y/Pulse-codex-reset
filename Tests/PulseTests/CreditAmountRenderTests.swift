import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Pulse

/// Opt-in visual check of Qoder's credit amounts beside each row's name (#88):
/// PULSE_CREDIT_AMOUNTS_PREVIEW=/tmp/credit-amounts swift test --filter CreditAmountRenderTests
@Suite("Credit amount render", .serialized)
@MainActor
struct CreditAmountRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_CREDIT_AMOUNTS_PREVIEW"] != nil))
    func renderQoderParts() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_CREDIT_AMOUNTS_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { LocalizationSource.use(.system) }

        // The issue's own account: the parts add up to the total.
        func window(_ id: String, _ kind: UsageWindow.Kind, used: Double, limit: Double) -> UsageWindow {
            UsageWindow(id: id, kind: kind, scope: nil, usedFraction: used / limit,
                        windowSeconds: 30 * 86_400, resetsAt: nil, reportsLength: false,
                        amounts: .init(used: used, remaining: limit - used, limit: limit))
        }
        var usage = ProviderUsage(
            account: AccountKey(.qoder),
            windows: [
                window("qoder.credits", .credits, used: 6_119, limit: 14_700),
                window("qoder.plan", .planCredits, used: 157, limit: 6_000),
                window("qoder.pack", .topUp, used: 1_951, limit: 2_700),
                window("qoder.dedicated", .dedicatedCredits, used: 4_011, limit: 6_000),
            ],
            observedAt: Date(), state: .live, plan: "Pro", creditBalance: nil
        )
        // The week's two rows (`FloatingUsagePanelContent.withQoderWeek`), with
        // the issue's own figures.
        func addWeek() {
            usage.metrics = [
                UsageMetric(id: "qoder.week.used", label: String.localized("Credits used, last 7 days"), value: 1_341.21, unit: nil),
                UsageMetric(id: "qoder.week.charged", label: String.localized("Credits charged, last 7 days"), value: 51.37, unit: nil),
            ]
        }

        let languages: [(String, AppLanguage)] = [
            ("en", .english), ("zh-Hans", .chineseSimplified), ("zh-Hant", .chineseTraditional),
            ("ja", .japanese), ("ko", .korean), ("ru", .russian),
        ]
        for (name, language) in languages {
            LocalizationSource.use(language)
            addWeek()
            for remaining in [true, false] {
                let view = UsageDetailCard(
                    usage: usage, edge: .right, showsRemaining: remaining, showsAmounts: true,
                    pointerCenter: DetailCardLayout.estimatedHeight / 2
                )
                .padding(20)
                .background(.gray)
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let url = folder.appendingPathComponent("\(name)-\(remaining ? "left" : "used").png")
                let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                #expect(CGImageDestinationFinalize(destination))
            }
        }
    }
}
