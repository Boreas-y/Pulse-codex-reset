import Foundation

/// A local quota increase is an observation, never global reset confirmation.
/// Kept only for this process and tied to a known account and announcement.
struct CodexResetObservation {
    struct Increase: Equatable {
        let eventID: String
        let at: Date
    }

    private var previous: [String: ProviderUsage] = [:]
    private var increases: [String: Increase] = [:]

    mutating func observe(_ reading: ProviderUsage, event: CodexResetEvent?, now: Date) {
        guard reading.provider == .codex else { return }
        let id = reading.account.id
        guard case .live = reading.state, !reading.isCached,
              let stamp = reading.observedAt, stamp <= now, now.timeIntervalSince(stamp) <= 180,
              let identity = reading.codexAccountFingerprint, !identity.isEmpty else {
            previous[id] = nil
            increases[id] = nil
            return
        }
        let old = previous[id]
        previous[id] = reading
        guard let old, old.codexAccountFingerprint == identity, old.plan == reading.plan,
              let oldStamp = old.observedAt, stamp > oldStamp,
              stamp.timeIntervalSince(oldStamp) <= 30 * 60 else {
            increases[id] = nil
            return
        }
        guard let event, event.kind == .directReset, event.status == .announced,
              event.isDisplayable(at: now), stamp >= event.createdAt else { return }
        let rose = reading.windows.contains { window in
            guard window.scope == nil, window.kind == .fiveHour || window.kind == .weekly,
                  window.usedFraction.isFinite, (0...1).contains(window.usedFraction),
                  let nextReset = window.resetsAt, nextReset > stamp,
                  let before = old.windows.first(where: { $0.id == window.id }),
                  before.kind == window.kind, before.scope == window.scope,
                  before.windowSeconds == window.windowSeconds,
                  before.usedFraction.isFinite, (0...1).contains(before.usedFraction),
                  let oldReset = before.resetsAt, oldReset > stamp else { return false }
            // One percentage point; tolerate floating-point representation only.
            return before.usedFraction - window.usedFraction >= 0.01 - 1e-9
        }
        if rose { increases[id] = Increase(eventID: event.id, at: stamp) }
    }

    func increase(for account: AccountKey, event: CodexResetEvent, at now: Date) -> Increase? {
        guard event.kind == .directReset, event.status == .announced,
              let increase = increases[account.id], increase.eventID == event.id,
              now >= increase.at, now.timeIntervalSince(increase.at) <= 24 * 60 * 60 else { return nil }
        return increase
    }
}
