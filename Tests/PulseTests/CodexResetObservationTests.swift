import Foundation
import Testing
@testable import Pulse

struct CodexResetHealthTests {
    @Test func freshnessUsesSuccessfulCheckNotAttempt() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(CodexResetFeed.Health().isStale(at: now))
        #expect(!CodexResetFeed.Health(lastSucceededAt: now).isStale(at: now))
        #expect(CodexResetFeed.Health(lastSucceededAt: now, lastAttemptFailed: true).isStale(at: now))
        #expect(CodexResetFeed.Health(lastSucceededAt: now.addingTimeInterval(-1801)).isStale(at: now))
    }
}

struct CodexResetObservationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func event(id: String = "today", kind: CodexResetEvent.Kind = .directReset,
               status: CodexResetEvent.Status = .announced) -> CodexResetEvent {
        .init(id: id, kind: kind, status: status, title: "", scope: "",
              createdAt: now.addingTimeInterval(-600), updatedAt: now, confirmedAt: nil,
              schedule: .init(precision: .window, from: now.addingTimeInterval(-600),
                              through: now.addingTimeInterval(3600), label: ""),
              posts: [], url: URL(string: "https://aihot.news/codex-reset")!)
    }

    func reading(_ fraction: Double, at: Date, identity: String? = "account-a", slot: String = "",
                 plan: String = "Plus", reset: Date? = nil, state: ProviderUsage.State = .live,
                 cached: Bool = false, scope: String? = nil) -> ProviderUsage {
        var result = ProviderUsage(account: AccountKey(.codex, slot: slot),
                                   windows: [.init(id: "codex-week", kind: .weekly, scope: scope,
                                                   usedFraction: fraction, windowSeconds: 604800,
                                                   resetsAt: reset ?? now.addingTimeInterval(86400))],
                                   observedAt: at, state: state, plan: plan, creditBalance: nil)
        result.codexAccountFingerprint = identity
        result.isCached = cached
        return result
    }

    @Test func liveIncreaseIsLocalAndBoundToAnnouncement() {
        var observer = CodexResetObservation()
        observer.observe(reading(0.75, at: now.addingTimeInterval(-60)), event: event(), now: now)
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now) == nil)
        observer.observe(reading(0.1, at: now), event: event(), now: now)
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now)?.at == now)
        #expect(observer.increase(for: AccountKey(.codex, slot: "second"), event: event(), at: now) == nil)
        #expect(observer.increase(for: AccountKey(.codex), event: event(id: "tomorrow"), at: now) == nil)
        #expect(observer.increase(for: AccountKey(.codex), event: event(status: .confirmed), at: now) == nil)
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now.addingTimeInterval(86401)) == nil)
        #expect(event().status == .announced)
    }

    @Test(arguments: ["identity", "plan", "normal-reset", "long-gap", "stale", "cached", "unknown", "scope", "credit", "increase-used", "noise", "future", "old", "nan"])
    func unrelatedReadingsDoNotClaimRecovery(_ scenario: String) {
        var observer = CodexResetObservation()
        let baselineAt = now.addingTimeInterval(scenario == "long-gap" ? -1900 : -60)
        let expired = scenario == "normal-reset" ? now.addingTimeInterval(-1) : nil
        let news = event(kind: scenario == "credit" ? .resetCredit : .directReset)
        observer.observe(reading(0.75, at: baselineAt, reset: expired), event: news, now: baselineAt)
        let at = scenario == "future" ? now.addingTimeInterval(1) : scenario == "old" ? now.addingTimeInterval(-181) : now
        let fraction = scenario == "increase-used" ? 0.8 : scenario == "noise" ? 0.749 : scenario == "nan" ? Double.nan : 0.1
        observer.observe(reading(fraction, at: at,
                                 identity: scenario == "identity" ? "account-b" : scenario == "unknown" ? nil : "account-a",
                                 plan: scenario == "plan" ? "Pro" : "Plus",
                                 state: scenario == "stale" ? .stale : .live,
                                 cached: scenario == "cached", scope: scenario == "scope" ? "model" : nil), event: news, now: now)
        #expect(observer.increase(for: AccountKey(.codex), event: news, at: now) == nil)
    }

    @Test func failureBreaksComparisonAndAccountSwitchClearsNote() {
        var observer = CodexResetObservation()
        observer.observe(reading(0.75, at: now.addingTimeInterval(-60)), event: event(), now: now)
        observer.observe(.unavailable(.codex, reason: .unreachable), event: event(), now: now)
        observer.observe(reading(0.1, at: now), event: event(), now: now)
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now) == nil)
        observer.observe(reading(0, at: now.addingTimeInterval(60)), event: event(), now: now.addingTimeInterval(60))
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now.addingTimeInterval(60)) != nil)
        observer.observe(reading(0, at: now.addingTimeInterval(120), identity: "account-b"), event: event(), now: now.addingTimeInterval(120))
        #expect(observer.increase(for: AccountKey(.codex), event: event(), at: now.addingTimeInterval(120)) == nil)
    }
}
