import ActivityKit
import Foundation
import os
import PATHKit

/// The only code that talks to ActivityKit: starts, updates and ends the "Next PATH train"
/// Live Activity. Shared by the app (controller, background refresh) and the Live Activity
/// intents (which run in the app's process). Content comes from `TrainActivityPlanner`.
@MainActor
enum TrainActivities {
    /// `UserDefaults.standard` key (also settable as the `-LiveActivityDuration <seconds>`
    /// launch argument) overriding `TrainActivityPlanner.defaultDuration`.
    nonisolated static let durationDefaultsKey = "LiveActivityDuration"
    /// A cached snapshot younger than this is used instead of fetching (matches the app's
    /// foreground refresh cadence).
    nonisolated static let cacheFreshness: TimeInterval = 20

    /// Called after an activity starts (live app only: schedules a background refresh).
    static var didStart: (@MainActor () -> Void)?

    nonisolated private static let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "liveactivity")

    static var duration: TimeInterval {
        let value = UserDefaults.standard.double(forKey: durationDefaultsKey)
        return value > 0 ? value : TrainActivityPlanner.defaultDuration
    }

    static var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    nonisolated private static var running: [Activity<TrainActivityAttributes>] {
        Activity<TrainActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// The first activity that is still on screen and updatable.
    static var current: Activity<TrainActivityAttributes>? { running.first }

    /// Ends any existing activity immediately, then starts one for `trip` running `duration`.
    @discardableResult
    static func start(trip: Trip, snapshot: PATHSnapshot?, fetchFailed: Bool) async throws -> Activity<TrainActivityAttributes> {
        await endAll()
        let now = Date.now
        let state = TrainActivityPlanner.state(
            trip: trip, snapshot: snapshot, fetchFailed: fetchFailed, now: now, endsAt: now.addingTimeInterval(duration)
        )
        do {
            let activity = try Activity.request(
                attributes: TrainActivityAttributes(trip: trip),
                content: ActivityContent(state: state, staleDate: state.staleAt, relevanceScore: 100),
                pushType: nil
            )
            logger.info("Started Live Activity \(activity.id, privacy: .public) (\(state.trains.count) trains, \(state.status.rawValue, privacy: .public))")
            didStart?()
            return activity
        } catch {
            logger.error("Live Activity start failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Re-plans every running activity from `snapshot`. Past its `endsAt` an activity ends
    /// with `.ended` content and stays on screen for `dismissAfterEnd`; unchanged content is skipped.
    nonisolated static func update(snapshot: PATHSnapshot?, fetchFailed: Bool, now: Date = .now) async {
        for activity in running {
            let old = activity.content.state
            let state = TrainActivityPlanner.state(
                trip: activity.attributes.trip, snapshot: snapshot, fetchFailed: fetchFailed, now: now, endsAt: old.endsAt
            )
            if now >= old.endsAt {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .after(now.addingTimeInterval(TrainActivityPlanner.dismissAfterEnd))
                )
                logger.info("Ended Live Activity \(activity.id, privacy: .public) at its end time")
            } else if state != old {
                await activity.update(ActivityContent(state: state, staleDate: state.staleAt, relevanceScore: 100))
                logger.info("Updated Live Activity \(activity.id, privacy: .public) (\(state.trains.count) trains, \(state.status.rawValue, privacy: .public))")
            }
        }
    }

    /// Fetches (or reuses a very recent cached snapshot) and updates running activities.
    nonisolated static func refresh() async {
        let result = await SnapshotCache.shared.loadOrFetch(maxAge: cacheFreshness) {
            try await PATHClient().fetchSnapshot()
        }
        if let error = result.error {
            logger.error("Live Activity feed fetch failed: \(String(describing: error), privacy: .public)")
        }
        await update(snapshot: result.snapshot, fetchFailed: result.error != nil)
    }

    /// Ends every activity immediately.
    nonisolated static func endAll() async {
        for activity in Activity<TrainActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            logger.info("Ended Live Activity \(activity.id, privacy: .public)")
        }
    }
}
