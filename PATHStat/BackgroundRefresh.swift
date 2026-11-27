import BackgroundTasks
import Foundation
import os
import PATHKit
import WidgetKit

/// Best-effort background app refresh while a Live Activity runs (live mode only; never in
/// scenario or gallery modes). iOS decides if and when it actually runs.
@MainActor
enum BackgroundRefresh {
    /// Also listed in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let identifier = "com.yesh0907.PATHStat.refresh"

    private static let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "liveactivity")

    /// False with any UI-test / gallery launch argument.
    nonisolated static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return ![Scenario.scenarioArgument, Scenario.locationArgument,
                 LaunchMode.widgetGalleryArgument, LaunchMode.liveActivityGalleryArgument]
            .contains(where: arguments.contains)
    }

    /// Submits a refresh request for the running activity (`TrainActivityPlanner.nextBackgroundRefresh`).
    static func schedule() {
        guard isEnabled, let activity = TrainActivities.current,
              let date = TrainActivityPlanner.nextBackgroundRefresh(for: activity.content.state, now: .now) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background refresh")
        } catch {
            logger.error("Background refresh not scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    /// The `.appRefresh` task: fetch (or reuse a fresh cache, saved on success), reload widgets,
    /// update the Live Activity, and ask again while it runs.
    static func perform() async {
        guard isEnabled else { return }
        let result = await SnapshotCache.shared.loadOrFetch(maxAge: TrainActivities.cacheFreshness) {
            try await PATHClient().fetchSnapshot()
        }
        if let error = result.error {
            logger.error("Background feed fetch failed: \(String(describing: error), privacy: .public)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        await TrainActivities.update(snapshot: result.snapshot, fetchFailed: result.error != nil)
        if TrainActivities.current != nil { schedule() }
    }
}
