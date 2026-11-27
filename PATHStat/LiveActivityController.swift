import Foundation
import Observation
import PATHKit

/// Where Live Activities actually live: ActivityKit (`ActivityKitBackend`) or in memory for
/// UI tests and previews (`StubLiveActivityBackend`).
@MainActor
protocol LiveActivityBackend: AnyObject {
    /// The running activity's trip and end time, if any.
    var active: (trip: Trip, endsAt: Date)? { get }
    var areActivitiesEnabled: Bool { get }
    func start(trip: Trip, snapshot: PATHSnapshot?, fetchFailed: Bool) async throws
    /// Re-plans the running activity; ends it once past its end time.
    func update(snapshot: PATHSnapshot?, fetchFailed: Bool) async
    func end() async
}

/// The real thing, via `TrainActivities`.
@MainActor
final class ActivityKitBackend: LiveActivityBackend {
    var active: (trip: Trip, endsAt: Date)? {
        TrainActivities.current.map { ($0.attributes.trip, $0.content.state.endsAt) }
    }

    var areActivitiesEnabled: Bool { TrainActivities.areActivitiesEnabled }

    func start(trip: Trip, snapshot: PATHSnapshot?, fetchFailed: Bool) async throws {
        try await TrainActivities.start(trip: trip, snapshot: snapshot, fetchFailed: fetchFailed)
    }

    func update(snapshot: PATHSnapshot?, fetchFailed: Bool) async {
        await TrainActivities.update(snapshot: snapshot, fetchFailed: fetchFailed)
    }

    func end() async {
        await TrainActivities.endAll()
    }
}

/// In-memory activity for scenario mode: honours `TrainActivities.duration` and ends on time.
@MainActor
final class StubLiveActivityBackend: LiveActivityBackend {
    private(set) var active: (trip: Trip, endsAt: Date)?
    var areActivitiesEnabled: Bool

    init(areActivitiesEnabled: Bool = true) {
        self.areActivitiesEnabled = areActivitiesEnabled
    }

    func start(trip: Trip, snapshot: PATHSnapshot?, fetchFailed: Bool) async throws {
        active = (trip, Date.now.addingTimeInterval(TrainActivities.duration))
    }

    func update(snapshot: PATHSnapshot?, fetchFailed: Bool) async {
        if let active, Date.now >= active.endsAt { self.active = nil }
    }

    func end() async {
        active = nil
    }
}

/// The main screen's view of the Live Activity. The activity can also be started (Shortcuts)
/// or dismissed (Lock Screen) outside the app, so call `sync()` on returning to the foreground.
@MainActor
@Observable
final class LiveActivityController {
    private(set) var activeTrip: Trip?
    private(set) var endsAt: Date?
    private(set) var errorMessage: String?
    private(set) var areActivitiesEnabled: Bool

    @ObservationIgnored private let backend: any LiveActivityBackend
    /// Live mode only: asks for a background refresh while an activity runs.
    @ObservationIgnored private let scheduleBackgroundRefresh: (@MainActor () -> Void)?
    @ObservationIgnored private var lastSnapshot: PATHSnapshot?
    @ObservationIgnored private var lastFetchFailed = false
    /// Sleeps until `endsAt`, then updates so the activity ends on time while in the foreground.
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(backend: any LiveActivityBackend, scheduleBackgroundRefresh: (@MainActor () -> Void)? = nil) {
        self.backend = backend
        self.scheduleBackgroundRefresh = scheduleBackgroundRefresh
        areActivitiesEnabled = backend.areActivitiesEnabled
        sync()
    }

    var isActive: Bool { activeTrip != nil }

    func isActive(for trip: Trip) -> Bool {
        activeTrip.map { $0.sameRoute(as: trip) } ?? false
    }

    /// Starts (or switches) the activity to `trip`.
    func start(trip: Trip, snapshot: PATHSnapshot?, fetchFailed: Bool) async {
        remember(snapshot, fetchFailed)
        areActivitiesEnabled = backend.areActivitiesEnabled
        guard areActivitiesEnabled else {
            errorMessage = "Live Activities are turned off for PATH Stat."
            return
        }
        do {
            try await backend.start(trip: trip, snapshot: snapshot, fetchFailed: fetchFailed)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't start the Live Activity: \(error.localizedDescription)"
        }
        sync()
    }

    func stop() async {
        await backend.end()
        errorMessage = nil
        sync()
    }

    /// After each refresh of the main screen (success or failure).
    func update(snapshot: PATHSnapshot?, fetchFailed: Bool) async {
        remember(snapshot, fetchFailed)
        guard backend.active != nil else {
            sync()
            return
        }
        await backend.update(snapshot: snapshot, fetchFailed: fetchFailed)
        sync()
    }

    /// Re-reads the backend's state and re-arms the end-time task.
    func sync() {
        areActivitiesEnabled = backend.areActivitiesEnabled
        let active = backend.active
        activeTrip = active?.trip
        endsAt = active?.endsAt
        armEndTask()
    }

    /// Stops the end-time task and asks for a background refresh if an activity is running.
    func didEnterBackground() {
        endTask?.cancel()
        endTask = nil
        if isActive { scheduleBackgroundRefresh?() }
    }

    private func remember(_ snapshot: PATHSnapshot?, _ fetchFailed: Bool) {
        if let snapshot { lastSnapshot = snapshot }
        lastFetchFailed = fetchFailed
    }

    private func armEndTask() {
        endTask?.cancel()
        endTask = nil
        guard let endsAt else { return }
        endTask = Task { [weak self] in
            let delay = max(0, endsAt.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }
            await self.update(snapshot: self.lastSnapshot, fetchFailed: self.lastFetchFailed)
        }
    }
}
