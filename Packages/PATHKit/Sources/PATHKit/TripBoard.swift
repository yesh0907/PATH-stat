import Foundation

/// A destination a rider can pick from a station, e.g. "to 33rd St".
public struct DestinationOption: Hashable, Sendable, Identifiable {
    public let destination: StationCode
    public let direction: Direction
    public let label: String

    public init(destination: StationCode, direction: Direction, label: String? = nil) {
        self.destination = destination
        self.direction = direction
        self.label = label ?? "to \(StationCatalog.station(destination).shortName)"
    }

    public var id: StationCode { destination }
}

extension StationCatalog {
    /// Destinations reachable on one line from `station`.
    ///
    /// - `termini`: the ends of every line serving the station (excluding the station itself),
    ///   `toNY` ends first, then `toNJ` ends, each in `PATHLine.allCases` order, deduplicated.
    /// - `otherStops`: every other station reachable on a single line, in catalog order.
    public static func destinationOptions(
        from station: StationCode
    ) -> (termini: [DestinationOption], otherStops: [DestinationOption]) {
        let lines = PATHLine.allCases.filter { $0.stops.contains(station) }
        var termini: [DestinationOption] = []
        var seen = Set<StationCode>()
        func add(_ code: StationCode?, _ direction: Direction) {
            guard let code, code != station, seen.insert(code).inserted else { return }
            termini.append(DestinationOption(destination: code, direction: direction))
        }
        for line in lines { add(line.stops.last, .toNY) }
        for line in lines { add(line.stops.first, .toNJ) }

        let otherStops = all.compactMap { candidate -> DestinationOption? in
            guard !seen.contains(candidate.code),
                  let direction = direction(from: station, to: candidate.code) else { return nil }
            return DestinationOption(destination: candidate.code, direction: direction)
        }
        return (termini, otherStops)
    }
}

extension PATHSnapshot {
    /// Trains at `station`, in either direction, that stop at `destination` later on their line.
    ///
    /// Merging both directions covers pairs where lines disagree on direction (Newport→Hoboken
    /// is ToNJ on Hoboken–WTC but ToNY on the via-Hoboken service). Departed trains are dropped
    /// with the same `DepartureBoard.departedGrace` cutoff. `direction` is
    /// `StationCatalog.direction(from:to:) ?? .toNY`; `lastUpdated` is the newest across both
    /// directions' unfiltered messages.
    public func departures(at station: StationCode, toward destination: StationCode, now: Date = .now) -> DepartureBoard {
        let all = Direction.allCases.flatMap { boards[station]?[$0] ?? [] }
        let cutoff = now.addingTimeInterval(-DepartureBoard.departedGrace)
        let trains = all
            .filter { $0.arrival >= cutoff && $0.stops(at: destination) }
            .sorted { $0.arrival < $1.arrival }
        return DepartureBoard(
            station: station,
            direction: StationCatalog.direction(from: station, to: destination) ?? .toNY,
            toward: destination,
            trains: trains,
            lastUpdated: all.map(\.lastUpdated).max()
        )
    }
}
