// ActionUsageStore.swift
// OpenClip
//
// Tracks how recently each action was used, MRU style (VS Code command-palette pattern):
// each `record` bumps a monotonically increasing counter per action ID, so a higher counter
// always means "used more recently". Persisted through `SettingsStore` so history survives
// launches. Search ranking consumes it only as a tie-break below match quality — a hot action
// can never outrank a better fuzzy match.
import Foundation

@MainActor
public final class ActionUsageStore {
    public static let shared = ActionUsageStore()

    private let settingsStore: SettingsStore
    private var cached: [String: Int]

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        self.cached = settingsStore.get(.actionUsageRecency)
    }

    /// The current recency map: action ID → counter (higher = more recent). Empty when unused.
    public var recency: [String: Int] { cached }

    /// Records one use of `actionID`, bumping its counter above every other action's.
    public func record(_ actionID: String, selection: SelectionContext? = nil) {
        if let selection, settingsStore.get(.adaptiveActionBar) {
            let key = AdaptiveActionBar(selection: selection).usageKey
            var history = settingsStore.get(.adaptiveActionHistory)
            let recent = history[key, default: []] + [actionID]
            history[key] = Array(recent.suffix(24))
            settingsStore.set(.adaptiveActionHistory, value: history)
        }
        let highest = cached.values.max() ?? 0
        let (next, overflow) = highest.addingReportingOverflow(1)
        if overflow {
            // Persisted counter was at Int.max (e.g. corrupted/edited prefs) — a naive +1 would trap.
            // Reset the map with the recorded action at the lowest counter.
            cached = [actionID: 1]
        } else {
            cached[actionID] = next
        }
        settingsStore.set(.actionUsageRecency, value: cached)
    }

    public func recentUses(for selection: SelectionContext) -> [String] {
        settingsStore.get(.adaptiveActionHistory)[AdaptiveActionBar(selection: selection).usageKey] ?? []
    }

    /// Clears all usage history.
    public func reset() {
        cached = [:]
        settingsStore.set(.actionUsageRecency, value: cached)
        settingsStore.set(.adaptiveActionHistory, value: [:])
    }
}
