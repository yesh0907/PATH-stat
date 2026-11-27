import Foundation

/// Rate-limits an action (e.g. `WidgetCenter.reloadAllTimelines()` after each refresh):
/// allows the first call, then at most one per `minInterval`.
public struct ReloadThrottle: Sendable {
    public let minInterval: TimeInterval
    private var lastAllowed: Date?

    public init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// True the first time, then only once `minInterval` has passed since the last true.
    public mutating func shouldReload(at date: Date) -> Bool {
        if let lastAllowed, date.timeIntervalSince(lastAllowed) < minInterval { return false }
        lastAllowed = date
        return true
    }
}
