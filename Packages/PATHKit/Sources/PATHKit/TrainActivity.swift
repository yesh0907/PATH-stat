import Foundation

/// The content of the "Next PATH train" Live Activity (its ActivityKit `ContentState`).
///
/// A Live Activity can only change when the app (or a push) updates it, but the system
/// re-renders it at `staleAt` (the content's `staleDate`) with `isStale == true`. `staleAt` is
/// at the latest the first train's departure, so at that moment the views can drop it and show
/// the next one (`visibleTrains(isStale:)`) without any app code running.
public struct TrainActivityState: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// From a successful fetch.
        case live
        /// The latest fetch failed (or there is no data); trains are from an older snapshot.
        case offline
        /// Past `endsAt`: the activity has ended and is about to be dismissed.
        case ended
    }

    /// Upcoming trains (departure after the state's `now`), soonest first, at most
    /// `TrainActivityPlanner.maxTrains`.
    public let trains: [TrainArrival]
    public let fetchedAt: Date?
    public let status: Status
    /// When this content goes stale (ActivityKit `staleDate`); never later than `endsAt`.
    public let staleAt: Date
    /// When the activity ends on its own.
    public let endsAt: Date

    public init(trains: [TrainArrival], fetchedAt: Date?, status: Status, staleAt: Date, endsAt: Date) {
        self.trains = trains
        self.fetchedAt = fetchedAt
        self.status = status
        self.staleAt = staleAt
        self.endsAt = endsAt
    }

    /// `trains`; once stale, only trains still to depart (`arrival + departedGrace`) after
    /// `staleAt`, so the view rolls over to the following train when the first one leaves.
    public func visibleTrains(isStale: Bool) -> [TrainArrival] {
        guard isStale else { return trains }
        return trains.filter { $0.arrival.addingTimeInterval(DepartureBoard.departedGrace) > staleAt }
    }

    /// Whether to flag the data as possibly out of date: stale, offline/ended, or never fetched.
    public func showsStaleWarning(isStale: Bool) -> Bool {
        isStale || status != .live || fetchedAt == nil
    }
}

/// Builds Live Activity content from a feed snapshot. Pure; ActivityKit lives in the app/widget.
public enum TrainActivityPlanner {
    /// How long a Live Activity runs before ending on its own.
    public static let defaultDuration: TimeInterval = 60 * 60
    public static let staleAfter: TimeInterval = WidgetTimeline.staleAfter
    public static let maxTrains = 4
    /// How long an ended activity stays on the Lock Screen.
    public static let dismissAfterEnd: TimeInterval = 120

    /// - `trains`: `snapshot.departures(at: trip.origin, toward: trip.destination, now:)` with
    ///   departure (`arrival + departedGrace`) after `now`, first `maxTrains`.
    /// - `status`: `.ended` from `endsAt`; else `.offline` without a snapshot or when
    ///   `fetchFailed`; else `.live`.
    /// - `staleAt`: the earliest of the first train's departure, `fetchedAt + staleAfter` and
    ///   `endsAt`; `now` (capped at `endsAt`) without a snapshot.
    public static func state(
        trip: Trip,
        snapshot: PATHSnapshot?,
        fetchFailed: Bool,
        now: Date,
        endsAt: Date
    ) -> TrainActivityState {
        let grace = DepartureBoard.departedGrace
        let trains = snapshot.map { snapshot in
            Array(
                snapshot.departures(at: trip.origin, toward: trip.destination, now: now).trains
                    .filter { $0.arrival.addingTimeInterval(grace) > now }
                    .prefix(maxTrains)
            )
        } ?? []

        let status: TrainActivityState.Status = if now >= endsAt {
            .ended
        } else if snapshot == nil || fetchFailed {
            .offline
        } else {
            .live
        }

        let staleAt: Date
        if let snapshot {
            var candidates = [snapshot.fetchedAt.addingTimeInterval(staleAfter), endsAt]
            if let first = trains.first { candidates.append(first.arrival.addingTimeInterval(grace)) }
            staleAt = candidates.min()!
        } else {
            staleAt = min(now, endsAt)
        }

        return TrainActivityState(
            trains: trains,
            fetchedAt: snapshot?.fetchedAt,
            status: status,
            staleAt: staleAt,
            endsAt: endsAt
        )
    }

    /// When to ask for a background refresh: nil once ended, else the earlier of `staleAt` and
    /// `endsAt`, but no sooner than a minute from `now`.
    public static func nextBackgroundRefresh(for state: TrainActivityState, now: Date) -> Date? {
        guard state.status != .ended else { return nil }
        return max(now.addingTimeInterval(60), min(state.staleAt, state.endsAt))
    }
}
