import Foundation
import PATHKit

/// Fixed Live Activity states built with `TrainActivityPlanner` from PATHKit's sample
/// snapshots (trip Grove St → 33rd St), for the app's `-LiveActivityGallery` mode and previews.
enum TrainActivitySampleState: String, CaseIterable, Sendable {
    /// Fresh data, not stale.
    case live
    /// Planned when the first train was 355 s from departing; now it has departed, the
    /// content is stale (`staleAt` was its departure) and the views show the following train.
    case rolledOver
    /// Fetched 12 minutes ago: past `staleAfter`.
    case stale
    /// The latest fetch failed; trains from a 3-minute-old snapshot.
    case offline
    /// Past `endsAt`.
    case ended

    func make(now: Date) -> (trip: Trip, state: TrainActivityState, isStale: Bool) {
        let trip = Trip.groveTo33rd
        let duration = TrainActivityPlanner.defaultDuration
        switch self {
        case .live:
            let state = TrainActivityPlanner.state(
                trip: trip, snapshot: .sampleTrains(now: now), fetchFailed: false, now: now,
                endsAt: now.addingTimeInterval(duration)
            )
            return (trip, state, false)
        case .rolledOver:
            // The sample's first Grove St → 33rd St train arrives 295 s after the snapshot.
            let planned = now.addingTimeInterval(-(295 + DepartureBoard.departedGrace))
            let state = TrainActivityPlanner.state(
                trip: trip, snapshot: .sampleTrains(now: planned), fetchFailed: false, now: planned,
                endsAt: planned.addingTimeInterval(duration)
            )
            return (trip, state, true)
        case .stale:
            let fetchedAt = now.addingTimeInterval(-12 * 60)
            let snapshot = PATHSnapshot(fetchedAt: fetchedAt, boards: PATHSnapshot.sampleTrains(now: now).boards)
            let state = TrainActivityPlanner.state(
                trip: trip, snapshot: snapshot, fetchFailed: false, now: now,
                endsAt: fetchedAt.addingTimeInterval(duration)
            )
            return (trip, state, true)
        case .offline:
            let snapshot = PATHSnapshot(
                fetchedAt: now.addingTimeInterval(-3 * 60), boards: PATHSnapshot.sampleTrains(now: now).boards
            )
            let state = TrainActivityPlanner.state(
                trip: trip, snapshot: snapshot, fetchFailed: true, now: now,
                endsAt: now.addingTimeInterval(duration / 2)
            )
            return (trip, state, false)
        case .ended:
            let state = TrainActivityPlanner.state(
                trip: trip, snapshot: .sampleTrains(now: now), fetchFailed: false, now: now, endsAt: now
            )
            return (trip, state, false)
        }
    }
}
