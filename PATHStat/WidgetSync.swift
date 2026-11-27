import PATHKit
import WidgetKit

/// Shares the app's fetched snapshots with the widget: saves each to `SnapshotCache.shared`
/// and reloads widget timelines at most once a minute, plus once on going to the background.
/// Live mode only; scenario/UI-test environments have no `WidgetSync`.
@MainActor
final class WidgetSync {
    private var throttle = ReloadThrottle(minInterval: 60)

    /// After a successful fetch.
    func didFetch(_ snapshot: PATHSnapshot) {
        SnapshotCache.shared.save(snapshot)
        if throttle.shouldReload(at: .now) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// When the app goes to the background (unthrottled).
    func didEnterBackground() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
