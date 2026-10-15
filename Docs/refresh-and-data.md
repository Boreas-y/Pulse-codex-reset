# Refresh, cache, activity, history

Pulse shows **figures the provider reported**. It never invents a usage percentage from local token counts; if a provider reports no figure, the UI says so. The only exceptions are labelled on screen as inferred, and each draws **nothing** (not a zero) when its inputs are missing:

- the money estimate ([below](#the-estimate-budgetestimate));
- Command Code's monthly plan grant: the remainder is reported, the size only published on a pricing page ([providers/command-code.md](providers/command-code.md));
- the `BalanceRing` of every API account or extension that reports money and no allowance — DeepSeek's rule first ([providers/deepseek.md](providers/deepseek.md)), then any extension reporting a balance ([extensions.md#a-balance](extensions.md#a-balance)). Its denominator is one Pulse watched, one the user typed, or none; only the provider's own flag marks it spent ([providers/README.md](providers/README.md#subscriptions-and-api-accounts)).

Why: [decisions/reported-figures.md](decisions/reported-figures.md). Per-provider HTTP, cookies and login: [providers/README.md](providers/README.md). Notifications: [notifications.md](notifications.md). Output outside the panel: [json-output.md](json-output.md).

**Every fetched reading is written through `UsageStore.commit(_:raw:for:)`**, which gives alert rules both the raw result and the reconciled display reading. Seeded placeholders and restored cache never enter the rules. An explicit notification-setting change reconsiders valid live snapshots after authorization, and requests a refresh if current readings are stale or expired.

## Refresh loop

`UsageStore` is `@Observable`. The interval is **adaptive by default** (`AdaptiveRefresh`): **2–30 minutes** (`floor` 120 s, `ceiling` 1800 s) — **not** a 60-second repeating timer. Because the wait changes each pass, `scheduleNext` sets a one-shot `Timer.scheduledTimer(..., repeats: false)` after every refresh. Why: [decisions/adaptive-refresh.md](decisions/adaptive-refresh.md).

- **Nothing before a provider choice.** Until the choice is non-empty, the store holds credential-free placeholders, and `start`, full refresh, per-account refresh and settings changes cannot read or fetch. Cache restoration reads only enabled accounts. See [architecture.md](architecture.md#provider-choice-before-monitoring).
- **Disabled providers are not fetched** — not by the loop, by opening their Settings pane, or by a per-account refresh. The pane shows **Not shown** instead of live rows and disables diagnostics Retry until the account is enabled. Automatic history loading is limited to enabled primary accounts; Codex's account-history method checks this before starting its helper.

### One timer, many cadences

- **`.automatic`:** each provider has its own interval; the timer is set for whichever is due soonest, and a pass asks only due accounts (`UsageStore.providersToAsk`). Pacing runs from `askedAt` — *asked*, not answered, or a provider that always refuses reads as permanently due and spins the loop. Accounts not asked keep their reading (the commit loop is gated on the same set).
- **Fixed interval** (Settings group **Refresh**, not Updates — the app has Sparkle) applies to everything equally.
- **Extensions** are asked every pass, side by side in a task group: each program has its own time limit (1–60 s) and one using all of it must not hold the others back ([extensions.md](extensions.md)).
- **Added accounts are deliberately not paced**: every pass asks all of them, whichever primary woke it (the `extras` comment in `UsageStore.refresh`). A per-account cadence (#62) was declined; revisit only on a reported problem.
- A rail with **no primary account** still times itself by the chosen fixed interval (`UsageStore.timerWait`, `RefreshTimerTests`); falling back to the adaptive wait once made "every minute" wait up to half an hour.
- `UsageStore.currentInterval` is **the cadence**, not the countdown: Settings shows it as "Now: X minutes" and `isOverdue` multiplies it (as the wait it once read "Now: 0 minutes").
- **`refresh(dueOnly:)` is true only for the timer.** Every other caller — a setting changed, a window reset, the display woke, the app server pushed, the pointer reached a rail with figures older than the cadence — is a reason to look now. Reversing it makes controls do nothing (switching DeepSeek's ring basis left the old ring on screen). `providersToAsk` is `nonisolated static` and pure, pinned by `RefreshPacingTests`.

### Signals

Every signal is a reason to wait **longer**, never shorter:

- CLI transcript metadata (`AgentActivity.lastWrite`), not a second scan. For ZCode, the newest turn/model/tool event's own stamp, not the file date: its idle heartbeats in the same log held every provider at the floor while ZCode was merely open.
- Whether reported `windows` moved (`observedAt` ignored, or every fetch looks like a change).
- Whether the rail was hovered (`noteLooked`); whether the panel is on screen.
- Low power, thermal, display asleep.

#### Providers this Mac cannot watch

A provider billed on its own servers moves no local signal, so it would always sit at the ceiling — and for prepaid credit draining toward zero (DeepSeek, Command Code), half an hour late costs something. `AdaptiveRefresh.interval(for:isWatched:)` caps those at `unwatchedCeiling` (300 s). The flag is `Provider.spendingIsWatchedLocally`: false when `reportsSpendableBalance`, and false for **V2EX**, which the money test cannot see (allowance in tokens, spent in a browser elsewhere, five-hour window started by a message there — [providers/v2ex.md](providers/v2ex.md)); a profiled provider also answers from its profile's own flag. The cap **only lowers** a wait the ladder chose, and loses to the two short-circuits above it — a constrained Mac and a hidden panel — which are about this machine, not the provider.

### Stalls

`scheduleNext` only runs when a pass **finishes**, so a pass that never returns takes the schedule with it. Guards:

- A pass in flight longer than `passCeiling` (180 s) is treated as gone (full and per-account paths).
- A full pass requested mid-pass is queued once (`queuedFullPass`), not dropped or run alongside.
- `noteLooked` refreshes when the newest reading is older than twice the cadence — but **never-read is not overdue** (no `observedAt`), and a cooldown stops a sweep across the rail firing one request per ring.
- Observe both `NSWorkspace.didWakeNotification` **and** `screensDidWake`; they differ.

Releasing a stalled pass is not ending it: abandoned work still writes when it answers. Every pass is stamped (`generation` / `currentPass`) and must still be current before writing `usage` or clearing flags.

Sort-key lengths never feed the window clock or burn rate: [providers/README.md](providers/README.md#windowseconds-is-not-evidence-of-a-reported-length).

### One path from an account to its fetch

Both the full pass (`refresh(dueOnly:)`) and the per-account refresh (`refresh(_:)`) call `UsageStore.fetch(for:liveKey:)`, which resolves the credential and asks the store's `UsageServiceFactory` (`UsageServices.swift`) for a `UsageFetch` — a `@Sendable () async -> ProviderUsage` built on the main actor at the start of the pass, so settings and keys are read then. The factory is the **only** place that picks a service: an extension by its program (or `.extensionMissing`), an added account by the login Pulse holds (`fetchAdded`), a primary by its hand-written service or `ProviderProfile`. `LiveUsageServices` is production; tests inject a fake.

Shared: `settle` applies the balance ring, then `UsageCache.reconciled`, and hands raw and reconciled readings to `commit`. A full pass reads keys from `apiKeys` (enabled accounts, loaded at launch); a ring click (`liveKey: true`) falls back to the key store, since a pane is reachable while its provider is off.

Different on purpose:

- **Full pass:** primaries side by side in one task group, **then** added accounts one at a time, **then** extensions side by side. Writes wait until the pass is confirmed current; added accounts and extensions commit before primaries, all in `settings.shownAccounts` order (not completion order, which alert rules cannot tell apart). An extension whose program is gone is skipped and keeps its reading.
- **Ring click:** commits one account, holds its feedback for 650 ms, and reports `.extensionMissing` for a vanished extension.

The store also takes a `UsageCache` (scratch file in tests) and a `clock` (watchdog, pacing stamps, `noteLooked`). Pure rules live in `UsageStore+Pacing.swift` (`timerWait`, `providersToAsk`, `passCeiling`, `didAnythingMove`). `UsageStoreSchedulingTests` drives it all with fake services ([testing.md](testing.md)).

## Cache

`UsageCache` keeps the last good reading per account, so a refusal shows dated figures (`.stale`, the card's “as of” line) instead of an empty error.

- A window whose **reset has passed is dropped**, not aged; if every window has reset, report the error. Windows that never state a reset are capped at 24 h (`UsageCache.maximumAge`).
- **These age rules apply to fresh fetches too**: `observedAt` is when the *provider* took its figures, so `reconciled` filters a fetched reading before banking or drawing it. Devin is why — its figures come from a row its app writes at launch ([providers/devin.md](providers/devin.md)).
- **A saved plan is banked even when stale.** Devin's comes from the app's own store, not a repeatable request, so `reconciled` keeps it, date-stamped; `--json` never fetches and reads only what is banked.
- A confirmed empty Qoder allowance (`.qoderNoCredits`) or StepFun's "no Step Plan" (`.stepFunNoPlan`) is a successful answer that deletes the banked reading from memory and disk, so old figures cannot stand in on the panel, next launch or `--json`. Failed requests still fall back ([providers/qoder.md](providers/qoder.md)).
- Missing credentials are **not** papered over: `.apiKeyMissing`, `.ollamaSessionMissing`, `.qoderSessionMissing`, `.stepFunSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn`, `.claudeDesktopKeyRefused`, the profiled `.sessionMissing`, `.localLoginMissing`, `.localAppMissing`, and a gateway with no usable address (`.serverAddressMissing`, `.serverAddressRefused`).
- **No shared fallback across scopes.** `ProviderUsage.requiresScopeMatch` is computed from the provider (no hand-set flag to forget); every fallback, "newer wins" and save then agrees on a `UsageScope` of **route, organization and identity**, and a missing organization or identity is never a wildcard. Devin needs it (endpoint per organization, saved row per user id). sub2api and New API readings carry `GatewayAddress.scope(of:key:)` — deployment root as organization, the key's SHA-256 as identity — so another server or key never inherits old figures.
- `.live` is not "newest": `reconciled` prefers the later `observedAt`, even over a capture a route marked live.
- `UsageStore.start` paints the cache before the first request; cache never undoes a fetch that has landed.

### Connection diagnostics

`UsageStore.commit` also records a `ConnectionDiagnostic` per account, apart from the display reading: latest raw result, completed-check time, route checks, and the newest successful reading's own `observedAt` (re-reading a status-line capture never advances it to the Retry click). Restored cache and seeded placeholders are not completed checks; the UI says none has completed since launch.

`ProviderUsage.origin` records the producing route and is persisted in the cache (old entries: unknown); route attempts are not. `isCached` is set only by cache restoration, so a stale status-line capture shown directly is not called a cache replacement. Single-route providers are labelled at reconciliation and commit; the three multi-route services record their branches ([providers/README.md](providers/README.md#diagnostic-route-checks-and-repair)).

The copied report is a fixed allowlist — app version, provider, primary/added kind, route preference, typed outcomes, timestamps — and omits account ids and labels, plan names, amounts, paths, credentials, headers and bodies. Tests pass results through the real cache before checking diagnostics. UI: [ui/settings.md](ui/settings.md).

## Agent activity

A white arc inside the ring while that provider's agent is working (`AgentActivity`), polled every 2 s on its **own** clock: turns last seconds, usage moves in percent.

- **Scope.** Only providers of enabled accounts with a lifecycle source (`supportsLocalActivity`): Claude Code and Codex transcripts, Kiro Desktop/CLI/ACP sessions, and ZCode telemetry when its configured endpoint identifies the enabled Zhipu or z.ai storefront. None selected: no timer, no scan. Independent of the Token Spend setting. Per provider even when only an added account is enabled (local records do not name the Pulse account). Without a source the mark is omitted, not shown idle; this is separate from `keepsLocalTranscripts`, since lifecycle records lack the token buckets an estimate needs.
- **Cancellation.** Changing the monitored providers cancels the scan and starts a new observation; walks and tail reads check cancellation between files, and a read that finishes late cannot restore activity or overwrite the new scan. Stopping clears `running`, `lastWrite` and `finishedAt` without treating deselection or a hidden panel as a finished turn.
- **Caching.** The reader actor keeps only parsed lifecycle facts keyed by provider, path, size and modification date; grace is still re-evaluated against the record timestamp **on every sample**. Empty, unreadable or cancelled reads are retried, not cached.
- **Discovery** walks the selected roots every two seconds so new and resumed sessions show at once; only recent candidates are sorted, old history contributes its newest stamp. Entries that drop out of a provider's recent candidates are pruned — not those skipped after a busy session was found, and nothing after a cancelled pass.
- ZCode gets its timestamp and verdict from one tail read; tails split with the shared `LogLines` byte scanner. `AgentActivityTests` covers expiry without writes and changed, new and deleted files.

"Working" is not "written to recently": the agents state it in the **tail** of their lifecycle records. ZCode Desktop, native TUI and `zcode-acp` share turn events (overlapping turn ids reconciled independently); Kiro's v1 Prompt/ToolResults/AssistantMessage records and v2 Desktop/ACP turn events distinguish model work, tool work, a user-interaction wait and a finished reply. Rules (measurements: [decisions/reported-figures.md](decisions/reported-figures.md#activity-is-not-mtime)):

- Skip bookkeeping records; an interrupt record ends the turn.
- Grace depends on what the turn waits for (model vs tool), timed from the **record timestamp**, not mtime.
- An unrecognised tail falls back to "written in the last 30 s".
- All live transcripts, not only the newest.
- The monitor stops when the panel is hidden or the display sleeps; the refresh loop reads `lastWrite` rather than scanning.

The arc rides the **empty ring** between icon and usage stroke, in Core Animation, not `TimelineView`; reset `spinning` on disappear. **`AppSettings.animatesRingActivity`** (on by default) gates it together with the refresh mark over the usage arc (`UsageRingView.isRefreshing`, in the provider's colour) — the same cue drawn two ways. Off, `isBusy` / `isRefreshing` are still tracked, but neither mark is drawn and the usage arc is not dimmed during a fetch.

## Countdown, rounding, colour

- `showsRemaining` (off by default) counts the same reading down. The **arc** follows the figure; **colour** still means closeness to the limit. No reading draws an empty track; spent fills the ring either way. Do not invert `usedFraction ?? 0`.
- The card's word ("left" / "used") and accessibility follow the figure.
- `UsageWindow.percentText`: nothing used → 0%; anything used → at least 1%. Both ends round, so used + left need not sum to 100.
- Colour is usage (`UsageTint`), not brand. Per-account `RingTint` is opt-in; spent colour wins; convert through sRGB; no opacity.

## Forecast (`BurnRate`)

Off by default (`showsForecast`). One line under a limit — lasts the window, or a coarse ETA — worded as a **projection**.

- Rate = spent share / elapsed share from **one** reading (trailing samples were dropped: [decisions/reported-figures.md](decisions/reported-figures.md#ledger-and-burn-rate)).
- Needs a reported percentage, a reset and `reportsLength`, so sort-key lengths fall out.
- A time only when it lands before reset **and** within two hours; otherwise the verdict without a time.
- A floor on elapsed share; a barely-open window is not divided into.
- The line is inside `DetailCardLayout`'s budget.

## Spending history and the estimate

`UsageLedger.Origin` names the source: **local transcripts** (Claude Code, Codex) carry input/output/cache counts and can be priced; **provider statistics** (Z.ai, Zhipu) cover every machine but give one token total per model, so the card shows tokens, no money, and says so ([providers/zai.md](providers/zai.md)); `importedRecords` and `providerLogs` serve the Token Spend pane and the OpenCode Go / DeepSeek consoles ([token-spend.md](token-spend.md)). Gates: `keepsLocalTranscripts` (Claude Code, Codex) for the estimate, `Provider.providesHistory` for history (`cardHistory != nil`, so the settings pane and the detailed card agree); everyone else **omits** rather than shows zeroes ([providers/README.md](providers/README.md#transcripts-ledger-forecast)).

The two CLIs report neither money nor per-day history; `UsageLedger` rebuilds both from transcripts at published API prices (`ModelPrices`, `models.dev`, cached a day). A model with no published price is left out, never given a plausible rate.

### Ledger

Re-verify after changing the counting (historical: an independent check agreed to the cent on one machine).

- Claude Code `input_tokens` **excludes** cache tokens; Codex's **includes** them. Normalise before pricing, or cache reads bill at the input rate.
- Codex reports a **running session total**: difference it. Summing per-turn `last_token_usage` double-counts (historical: 6% high on one long session).
- Quarter-hour buckets. Per-file cache key: size + mtime. The **filename carries the format** (`ledger-9-<provider>.json`, `UsageLedgerReader.cacheVersion`); bump it whenever an entry's content changes, or old entries parse as nothing. A transcript deleted since the last scan leaves the cache only after its counted share is kept in `archive-ledger-<provider>.json`, unnumbered and never superseded ([token-spend.md](token-spend.md#history-the-tools-have-deleted)).
- Cost is computed after the cache, from tokens per model.

### The estimate (`BudgetEstimate`)

Shown in its own Settings group with provenance, and as a dimmed "Estimated value …" line (said in words; no "≈" since 2026-10-15) under a limit on the detailed card ([ui/panel-geometry.md](ui/panel-geometry.md#detailed-card)); both format through `BudgetEstimator.approximate`.

- **Withheld** under **5%** used (`BudgetEstimator.minimumUsed`: whole-number percentages move the figure by up to 1/p in a sawtooth — at the old 2% a five-hour window read ≈$129 that could be ≈$200), under $0.20 spent (`minimumSpend`), when logs start after the window opened, for a window scoped to one model, for a reading taken outside the window, and for an unstated length (`reportsLength` false, e.g. Kimi's weekly allowance).
- **Spend runs from the window's opening to when the percentage was read** (`observedAt`), never to now, with edge quarter-hours counted for their share inside (`UsageLedger.cost(from:to:)`). Both earlier errors — counting to now, and `spend(since:)` dropping the opening quarter-hour with its cache writes — were found against a real Max 5x week.
- Nothing before the opening counts, and a window past its reset is dropped (`ProviderUsage.current(at:)`), so cycles never mix. `BudgetEstimateTests`.
- The pane rereads the ledger when the reading's `observedAt` moves (transcript providers only, via `AccountHistoryModel.key`), so an old ledger is never divided by a newer percentage.

**Work off this Mac** (another computer, the website) cannot be counted and makes the figure low. `ElsewhereWatch` (store-owned, app only; previews and tests pass none) compares consecutive live readings of one window in one cycle: a rise of **two points or more** (one can be a rounding tick) while **under $0.05 and under 1,000 tokens** were spent here (an unpriced model spends $0) from fifteen minutes before the first reading to the second marks the cycle in `used-elsewhere.json` until the reset. A marked window keeps its Settings row ("Not estimated", with the reason) and loses its card line. Both machines working at once is undetectable; the caption says so. `ElsewhereWatchTests`.

### Account usage card

`AccountUsageCard` is settings-only, off the panel loop. It reloads on `.task(id: history.key)`; `AccountHistoryModel.key` covers the pane, whether the account is on (so enabling one re-reads), the console revision, the reading's `observedAt` for transcript providers, and DeepSeek's currency. `saveKey` can start a read out of band.

- A grid of money and tokens with the chart, the money note beneath.
- A **separate Models card** (about models, not days) with **one table**, not a section per measure (which named every model three times). A row per model with tokens this month, most first (`modelShares`, grouped by display name); columns **share** and **cache hit** over 31 days (`cacheHitRatesByModel`; a withheld model — a day without per-model splits, or unclassified tokens — shows a faint dash); for Claude Code and Codex **tokens/s**, and for Codex **first token**, over a **rolling 24 hours** (`outputSpeedsByModel(since:)`, `speedSpan`; timings per quarter-hour `Slot`). Empty columns are left out. An **All models** row carries the account's own cache rate (`UsageLedger.cacheHitRate`), weighted by what each model read. The columns are explained once, under the card (`tableNote`).
- **Speed:** output tokens over seconds from the line that sent the request (user message or tool result; for Claude Code never before the previous reply's last line) to the reply's last line, summed per model. Replies under 100 output tokens or over 10 minutes are not timed; a model needs five timed replies; a month-old speed never stands in for a recent one.
- **First token:** Codex's own `time_to_first_token_ms` (first request of each turn, averaged). Claude Code's transcript has no such field — its first line is written once a whole content block is done — so it is said to be missing, not estimated.
- Historical, one machine: Opus 5.5 ≈ 90 tokens/s; GPT-5.6 Sol ≈ 37 tokens/s with a 6.6 s first token.
- Tests: `CacheHitRateTests`, `ReplyTimingTests`; cache-rate withholding: [ui/panel-geometry.md](ui/panel-geometry.md#detailed-card). Codex may also show the account's lifetime total from its API, larger than this Mac's logs.

### History chart hover

Hovering anywhere in the plot height or the gaps selects the nearest bar and shows its date (with year) and a compact localized token count (`TokenCount.short`, e.g. `5.24亿 tokens` / `600万 tokens`). `ChartHoverOverlay` uses the real bar centres; guide and label stay inside the plot, do not resize the card, and take no pointer input (nor does the decorative border). Leaving the plot or changing its data clears the selection; VoiceOver keeps each bar's date and exact count. This uses continuous hover in the activating **Settings** window, not the non-key panel's input path.

## Resets, witnessed twice

`UsageWindow.hasTurnedOver(since:resetsAt:)` is the one test for "this limit turned over": a reset time that moved forward by more than a minute, or a fraction that dropped forty points. Never for `balance` or `topUp`; credit kinds count only a moved reset. Two consumers: the reset notification ([notifications.md](notifications.md)) and `ResetWatch`, which drives the rail's celebration mark ([ui/rings-and-surface.md](ui/rings-and-surface.md)).

They keep **separate memories on purpose**: the alerts' bookkeeping sits behind "notifications are on", and the mark must work with every alert off; sharing the rule but not the record stops them drifting apart. `ResetWatch` takes **live readings only**, like the alert loop — a cached reading can be lower than what was banked, and a falling figure is how a reset is recognised.
