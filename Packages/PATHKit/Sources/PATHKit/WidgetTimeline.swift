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

/// Whole-minute countdown text for widgets, rounded down.
public enum MinutesCountdown: Sendable, Hashable {
    /// >= 1 minute remaining.
    case minutes(Int)
    /// 0 < remaining <= `WidgetTimeline.dueThreshold` seconds.
    case due
    /// The arrival time has passed.
    case now

    /// "in 4 min", "due", "now".
    public var text: String {
        switch self {
        case .minutes(let minutes): "in \(minutes) min"
        case .due: "due"
        case .now: "now"
        }
    }

    /// "4m", "due", "now" (for the circular lock-screen widget).
    public var compactText: String {
        switch self {
        case .minutes(let minutes): "\(minutes)m"
        case .due: "due"
        case .now: "now"
        }
    }
}

extension WidgetEntryState {
    /// The countdown for `train` at this entry's date.
    public func countdown(for train: TrainArrival) -> MinutesCountdown {
        WidgetTimeline.countdown(to: train.arrival, at: date)
    }
}

/// Builds widget timelines from one snapshot: entries roll forward as trains arrive and depart,
/// so the widget stays correct between reloads without a network fetch per minute.
public enum WidgetTimeline {
    public static let staleAfter: TimeInterval = 10 * 60
    public static let refreshInterval: TimeInterval = 15 * 60
    public static let retryInterval: TimeInterval = 5 * 60
    public static let idleInterval: TimeInterval = 30 * 60
    /// At most this many seconds remaining shows as "due" instead of minutes.
    public static let dueThreshold: TimeInterval = 60

    /// Countdown valid for the whole span starting at `date`: remaining = arrival - date;
    /// <= 0 → `.now`; <= `dueThreshold` → `.due`; else `.minutes(Int((remaining / 60).rounded(.up)) - 1)`.
    /// (Exact multiples count as the lower minute, so an entry that starts on a minute
    /// boundary is right for its whole span: 4:59 → 4, 5:00 → 4, 5:00.5 → 5, 1:01 → 1.)
    public static func countdown(to arrival: Date, at date: Date) -> MinutesCountdown {
        let remaining = arrival.timeIntervalSince(date)
        if remaining <= 0 { return .now }
        if remaining <= dueThreshold { return .due }
        return .minutes(Int((remaining / 60).rounded(.up)) - 1)
    }

    /// - Entries at `now`, each train's arrival, each train's `arrival + departedGrace`,
    ///   `fetchedAt + staleAfter`, and every minute boundary `arrival - k*60` (k = 1, 2, …)
    ///   of every upcoming train while ≥ `now` — the instants just after which the shown
    ///   whole-minutes countdown drops, so the countdown text stays correct between reloads.
    ///   Only dates ≥ `now`, deduplicated and sorted; entries identical to the previous one in
    ///   (status, trains, countdowns) are dropped (the first entry, at `now`, is always kept).
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
            if train.arrival > now {
                var boundary = train.arrival.addingTimeInterval(-60)
                while boundary >= now {
                    dates.insert(boundary)
                    boundary = boundary.addingTimeInterval(-60)
                }
            }
        }
        let upcoming = trains.filter { $0.arrival.addingTimeInterval(grace) > now }
        let allEntries = dates.filter { $0 >= now }.sorted().map { date in
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
        // Drop entries that change nothing visible (e.g. minute boundaries of trains beyond
        // the `maxTrains` cap): same status, same trains, same countdowns as the previous one.
        var entries: [WidgetEntryState] = []
        for entry in allEntries {
            if let last = entries.last,
               last.status == entry.status,
               last.trains == entry.trains,
               zip(last.trains, entry.trains).allSatisfy({ last.countdown(for: $0) == entry.countdown(for: $1) }) {
                continue
            }
            entries.append(entry)
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
