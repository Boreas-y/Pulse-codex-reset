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
    var health = CodexResetFeed.Health()
    var observation = CodexResetObservation()
    var account = AccountKey(.codex)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8 * PanelMetrics.scale) {
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

                Text(event.compactTiming(at: context.date, locale: LocalizationSource.locale, timeZone: .autoupdatingCurrent))
                    .font(.system(size: 12 * PanelMetrics.scale, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                if let content = event.posts.first?.content(for: LocalizationSource.locale) {
                    Text(content.isOriginal
                         ? String.localized("Original: \(content.text)")
                         : String.localized("Translation: \(content.text)"))
                        .font(.system(size: 11 * PanelMetrics.scale, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if observation.increase(for: account, event: event, at: context.date) != nil {
                    Text(localized: "Quota increased for this account · global reset unconfirmed")
                        .font(.system(size: DetailCardLayout.footnoteFontSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if health.isStale(at: context.date) {
                    Text(localized: "Announcement data may be out of date")
                        .font(.system(size: DetailCardLayout.footnoteFontSize))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12 * PanelMetrics.scale) {
                    Image(systemName: "link")
                        .font(.system(size: DetailCardLayout.footnoteFontSize))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if LocalizationSource.locale.prefersAIhotResetLink {
                        aihotLink
                        originalLink
                    } else {
                        originalLink
                        aihotLink
                    }
                }
            }
            .help(details(at: context.date))
            .accessibilityHint(details(at: context.date))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String.localized("Codex reset announcement"))
        }
    }

    private func details(at now: Date) -> String {
        let locale = LocalizationSource.locale
        let zone = TimeZone.autoupdatingCurrent
        var lines = [event.status == .confirmed
                     ? String.localized("Reported as confirmed by AI Hot News")
                     : String.localized("AI Hot News has not confirmed this announcement")]
        if let checked = health.lastSucceededAt {
            let time = CodexResetTime.local(checked, locale: locale, timeZone: zone)
            lines.append(String.localized("Last successful check: \(time)"))
        } else {
            lines.append(String.localized("No successful announcement check yet"))
        }
        if let relative = event.relativeTiming(at: now, locale: locale, timeZone: zone) { lines.append(relative) }
        if event.status == .announced, event.schedule != nil {
            lines.append(String.localized("Local time · AI Hot News estimate"))
        }
        if let post = event.posts.first {
            let time = CodexResetTime.local(post.publishedAt, locale: locale, timeZone: zone)
            lines.append(String.localized("Posted \(time)"))
            if post.content(for: locale)?.isOriginal == false {
                lines.append(String.localized("AI Hot News Chinese translation"))
            }
        }
        if let increase = observation.increase(for: account, event: event, at: now) {
            let time = CodexResetTime.local(increase.at, locale: locale, timeZone: zone)
            lines.append(String.localized("This account’s available quota increased at \(time). This does not confirm a global reset."))
        }
        return lines.joined(separator: "\n")
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
