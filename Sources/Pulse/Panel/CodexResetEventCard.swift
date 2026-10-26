import SwiftUI

enum ResetEventCardLayout {
    /// The section has no outer padding or surface of its own; both belong to
    /// the usage bubble that contains it. This is only the conservative space
    /// the fixed AppKit panel reserves for its variable text.
    static var maximumHeight: CGFloat { 420 * PanelMetrics.scale }
}

/// Public reset news inside the Codex usage bubble. The divider supplied by
/// `UsageDetailCard` keeps this third-party announcement distinct from the
/// provider-reported quota without making it look like a detached popover.
struct CodexResetEventSection: View {
    let event: CodexResetEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12 * PanelMetrics.scale) {
                HStack(spacing: 8 * PanelMetrics.scale) {
                    Image(systemName: event.kind == .resetCredit ? "ticket" : "arrow.clockwise")
                        .font(.system(size: 14 * PanelMetrics.scale, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(event.kind == .resetCredit
                         ? String.localized("Reset credit")
                         : String.localized("Limit reset"))
                        .font(.system(size: 13 * PanelMetrics.scale, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(event.status == .confirmed
                         ? String.localized("Confirmed")
                         : String.localized("Announced"))
                        .font(.system(size: 10.5 * PanelMetrics.scale, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4 * PanelMetrics.scale) {
                    Text(event.localizedTitle)
                        .font(.system(size: 13 * PanelMetrics.scale, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.timingDescription(locale: LocalizationSource.locale, timeZone: .autoupdatingCurrent))
                        .font(.system(size: 12 * PanelMetrics.scale, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let relative = event.relativeTiming(at: context.date, locale: LocalizationSource.locale, timeZone: .autoupdatingCurrent) {
                        Text(relative)
                            .font(.system(size: DetailCardLayout.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                    if event.status == .announced, event.schedule != nil {
                        Text(localized: "Local time · AI Hot News estimate")
                            .font(.system(size: DetailCardLayout.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                }

                if let content = event.posts.first?.content(for: LocalizationSource.locale) {
                    Text(content.isOriginal
                         ? String.localized("Original post")
                         : String.localized("AI Hot News Chinese translation"))
                        .font(.system(size: DetailCardLayout.footnoteFontSize))
                        .foregroundStyle(.secondary)
                    if let post = event.posts.first {
                        let posted = CodexResetTime.local(post.publishedAt, locale: LocalizationSource.locale, timeZone: .autoupdatingCurrent)
                        Text(String.localized("Posted \(posted)"))
                            .font(.system(size: DetailCardLayout.footnoteFontSize))
                            .foregroundStyle(.secondary)
                    }
                    Text(content.text)
                        .font(.system(size: 11 * PanelMetrics.scale, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12 * PanelMetrics.scale) {
                    if LocalizationSource.locale.prefersAIhotResetLink {
                        aihotLink
                        originalLink
                    } else {
                        originalLink
                        aihotLink
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String.localized("Codex reset announcement"))
        }
    }

    private var aihotLink: some View {
        PanelLink(title: "AI Hot News", destination: event.url).fixedSize()
    }

    @ViewBuilder private var originalLink: some View {
        if let post = event.posts.first {
            PanelLink(title: String.localized("Open original post") + " (X)", destination: post.url)
                .fixedSize()
        }
    }

    private var accent: Color {
        event.status == .confirmed ? .green : .orange
    }

}
