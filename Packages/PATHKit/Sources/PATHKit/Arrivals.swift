import Foundation

/// A single predicted train at a station, as reported by the realtime feed.
public struct TrainArrival: Identifiable, Hashable, Sendable {
    public let id: String
    public let station: StationCode
    public let direction: Direction
    public let target: StationCode?
    public let headsign: String
    public let line: PATHLine?
    public let lineColors: [String]
    /// `lastUpdated + secondsToArrival`.
    public let arrival: Date
    public let arrivalTimeMessage: String
    public let lastUpdated: Date

    public init(
        id: String? = nil,
        station: StationCode,
        direction: Direction,
        target: StationCode?,
        headsign: String,
        line: PATHLine?,
        lineColors: [String],
        arrival: Date,
        arrivalTimeMessage: String,
        lastUpdated: Date
    ) {
        self.id = id ?? [
            station.rawValue, direction.rawValue, target?.rawValue ?? "?",
            lineColors.joined(separator: "+"), String(arrival.timeIntervalSince1970),
        ].joined(separator: "|")
        self.station = station
        self.direction = direction
        self.target = target
        self.headsign = headsign
        self.line = line
        self.lineColors = lineColors
        self.arrival = arrival
        self.arrivalTimeMessage = arrivalTimeMessage
        self.lastUpdated = lastUpdated
    }

    /// Seconds until arrival at `now`, clamped to ≥ 0.
    public func secondsRemaining(at now: Date) -> TimeInterval {
        max(0, arrival.timeIntervalSince(now))
    }

    /// Whole minutes until arrival, rounded to nearest; any non-zero wait shows at least 1
    /// (matches the feed's own `arrivalTimeMessage` for observed data).
    public func minutesRemaining(at now: Date) -> Int {
        let seconds = secondsRemaining(at: now)
        guard seconds > 0 else { return 0 }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// Whether this train will stop at `station` after leaving its current station.
    /// Uses the identified line's stop order in the train's direction, cut short at `target`
    /// when the train terminates before the end of its line (short-turned); falls back to
    /// `target == station` when the line is unknown or doesn't list the current station.
    public func stops(at station: StationCode) -> Bool {
        guard let line,
              let here = line.stops.firstIndex(of: self.station),
              let there = line.stops.firstIndex(of: station) else {
            return target == station
        }
        let end = target.flatMap { line.stops.firstIndex(of: $0) }
        switch direction {
        case .toNY:
            guard let end, end >= here else { return there > here }
            return there > here && there <= end
        case .toNJ:
            guard let end, end <= here else { return there < here }
            return there < here && there >= end
        }
    }

    func withID(_ id: String) -> TrainArrival {
        TrainArrival(
            id: id, station: station, direction: direction, target: target, headsign: headsign, line: line,
            lineColors: lineColors, arrival: arrival, arrivalTimeMessage: arrivalTimeMessage, lastUpdated: lastUpdated
        )
    }
}

/// How recent the feed data behind a board is.
public enum Freshness: Equatable, Sendable {
    case fresh(age: TimeInterval)
    case stale(age: TimeInterval)
    case unknown
}

/// Upcoming trains at one station in one direction, optionally filtered.
public struct DepartureBoard: Sendable {
    /// Trains whose arrival is further than this in the past are considered departed.
    public static let departedGrace: TimeInterval = 60

    public let station: StationCode
    public let direction: Direction
    public let toward: StationCode?
    /// Sorted by arrival; departed trains dropped.
    public let trains: [TrainArrival]
    /// Most recent `lastUpdated` among the feed messages for this station/direction
    /// (before filtering), or nil if the feed had none.
    public let lastUpdated: Date?

    public init(station: StationCode, direction: Direction, toward: StationCode?, trains: [TrainArrival], lastUpdated: Date?) {
        self.station = station
        self.direction = direction
        self.toward = toward
        self.trains = trains
        self.lastUpdated = lastUpdated
    }

    public func age(at now: Date) -> TimeInterval? {
        lastUpdated.map { max(0, now.timeIntervalSince($0)) }
    }

    public func freshness(at now: Date, staleAfter: TimeInterval = 120) -> Freshness {
        guard let age = age(at: now) else { return .unknown }
        return age > staleAfter ? .stale(age: age) : .fresh(age: age)
    }

    public var next: TrainArrival? { trains.first }
    public var following: TrainArrival? { trains.dropFirst().first }
}

/// A full parsed realtime feed.
public struct PATHSnapshot: Sendable {
    public let fetchedAt: Date
    public let boards: [StationCode: [Direction: [TrainArrival]]]

    public init(fetchedAt: Date, boards: [StationCode: [Direction: [TrainArrival]]]) {
        self.fetchedAt = fetchedAt
        self.boards = boards
    }

    public func departures(
        at station: StationCode,
        direction: Direction,
        toward: StationCode? = nil,
        headsign: String? = nil,
        now: Date = .now
    ) -> DepartureBoard {
        let all = boards[station]?[direction] ?? []
        let cutoff = now.addingTimeInterval(-DepartureBoard.departedGrace)
        let needle = headsign?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trains = all
            .filter { $0.arrival >= cutoff }
            .filter { toward == nil || $0.stops(at: toward!) }
            .filter { needle == nil || needle!.isEmpty || $0.headsign.range(of: needle!, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.arrival < $1.arrival }
        return DepartureBoard(
            station: station,
            direction: direction,
            toward: toward,
            trains: trains,
            lastUpdated: all.map(\.lastUpdated).max()
        )
    }
}
