import Foundation

/// What a widget shows at one moment: the trip, its next trains, and how trustworthy they are.
public struct WidgetEntryState: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// Recent data from a successful fetch.
        case live
        /// Data from a successful fetch, but older than `WidgetTimeline.staleAfter`.
        case stale
        /// The latest fetch failed; trains come from an older cached snapshot.
        case offline
        /// No data at all.
        case unavailable
    }

    public let date: Date
    public let trip: Trip
    public let trains: [TrainArrival]
    public let fetchedAt: Date?
    public let status: Status

    public init(date: Date, trip: Trip, trains: [TrainArrival], fetchedAt: Date?, status: Status) {
        self.date = date
        self.trip = trip
        self.trains = trains
        self.fetchedAt = fetchedAt
        self.status = status
    }
}

/// Builds widget timelines from one snapshot: entries roll forward as trains arrive and depart,
/// so the widget stays correct between reloads without a network fetch per minute.
public enum WidgetTimeline {
    public static let staleAfter: TimeInterval = 10 * 60
    public static let refreshInterval: TimeInterval = 15 * 60
    public static let retryInterval: TimeInterval = 5 * 60
    public static let idleInterval: TimeInterval = 30 * 60

    /// - Entries at `now`, each train's arrival, each train's `arrival + departedGrace`, and
    ///   `fetchedAt + staleAfter`; only dates ≥ `now`, deduplicated and sorted.
    /// - Each entry lists up to `maxTrains` trains with `arrival + departedGrace` after its date.
    /// - Status: no snapshot → one `.unavailable` entry. Otherwise, per entry with `shown` trains:
    ///   `fetchFailed` → `.offline` (`.unavailable` when no trains remain at that date);
    ///   else `.stale` from `fetchedAt + staleAfter` or when a live snapshot's trains have all
    ///   departed by that date but the snapshot originally had upcoming trains; `.live` before.
    /// - `reloadAt`: no snapshot or failed fetch → `now + retryInterval`; no upcoming trains →
    ///   `now + idleInterval`; else the earlier of `now + refreshInterval` and the last train's
    ///   `arrival + departedGrace`, but no earlier than `now + retryInterval`.
    public static func make(
        trip: Trip,
        snapshot: PATHSnapshot?,
        fetchFailed: Bool,
        now: Date,
        maxTrains: Int = 3
    ) -> (entries: [WidgetEntryState], reloadAt: Date) {
        guard let snapshot else {
            let entry = WidgetEntryState(date: now, trip: trip, trains: [], fetchedAt: nil, status: .unavailable)
            return ([entry], now.addingTimeInterval(retryInterval))
        }
        let grace = DepartureBoard.departedGrace
        let trains = snapshot.departures(at: trip.origin, toward: trip.destination, now: now).trains
        let staleAt = snapshot.fetchedAt.addingTimeInterval(staleAfter)

        var dates: Set<Date> = [now, staleAt]
        for train in trains {
            dates.insert(train.arrival)
            dates.insert(train.arrival.addingTimeInterval(grace))
        }
        let upcoming = trains.filter { $0.arrival.addingTimeInterval(grace) > now }
        let entries = dates.filter { $0 >= now }.sorted().map { date in
            let shown = Array(trains.filter { $0.arrival.addingTimeInterval(grace) > date }.prefix(maxTrains))
            let status: WidgetEntryState.Status
            if fetchFailed {
                status = shown.isEmpty ? .unavailable : .offline
            } else if date >= staleAt || (shown.isEmpty && !upcoming.isEmpty) {
                status = .stale
            } else {
                status = .live
            }
            return WidgetEntryState(
                date: date,
                trip: trip,
                trains: shown,
                fetchedAt: snapshot.fetchedAt,
                status: status
            )
        }

        let reloadAt: Date
        if fetchFailed {
            reloadAt = now.addingTimeInterval(retryInterval)
        } else if let last = upcoming.last {
            let soonest = min(now.addingTimeInterval(refreshInterval), last.arrival.addingTimeInterval(grace))
            reloadAt = max(soonest, now.addingTimeInterval(retryInterval))
        } else {
            reloadAt = now.addingTimeInterval(idleInterval)
        }
        return (entries, reloadAt)
    }
}
