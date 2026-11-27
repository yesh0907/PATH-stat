import CoreLocation
import Foundation
import PATHKit

/// Deterministic app states for UI tests, screenshots and previews.
///
/// Launch with `-UITestScenario <loading|trains|noTrains|offline|locationDenied|offlineWithData>`
/// and optionally `-UITestLocation <lat>,<lon>`. Scenario mode uses a throwaway `TripStore`, a
/// stub feed, and fixed location state; the real `CLLocationManager` is never created.
enum Scenario: String, CaseIterable, Sendable {
    case loading
    case trains
    case noTrains
    case offline
    case locationDenied
    /// Starts with a 3-minute-old snapshot and every fetch fails, so the "Can't update —
    /// showing data from … ago" banner appears after the first refresh.
    case offlineWithData

    static let scenarioArgument = "-UITestScenario"
    static let locationArgument = "-UITestLocation"

    /// The scenario requested on the command line, if any. `-UITestLocation` alone implies `.trains`.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> (scenario: Scenario, location: CLLocation?)? {
        let scenario = value(after: scenarioArgument, in: arguments).flatMap(Scenario.init(rawValue:))
        let location = value(after: locationArgument, in: arguments).flatMap(parseLocation)
        guard scenario != nil || location != nil else { return nil }
        return (scenario ?? .trains, location)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// "40.7190,-74.0430" → CLLocation.
    static func parseLocation(_ text: String) -> CLLocation? {
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let lat = parts[0], let lon = parts[1],
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: Environment

    @MainActor
    func makeEnvironment(location override: CLLocation? = nil) -> AppEnvironment {
        let suite = "com.yesh0907.PATHStat.scenario.\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let store = TripStore(suiteName: suite)

        let location: LocationService
        if self == .locationDenied {
            location = .fixed(authorization: .denied, location: nil)
        } else {
            location = .fixed(
                authorization: .authorized,
                location: override ?? StationCatalog.station(.groveStreet).location
            )
        }
        let initialSnapshot = self == .offlineWithData
            ? Scenario.trainsSnapshot(now: .now.addingTimeInterval(-180))
            : nil
        return AppEnvironment(
            model: BoardModel(store: store, initialSnapshot: initialSnapshot, fetch: fetch),
            location: location
        )
    }

    var fetch: BoardModel.Fetch {
        switch self {
        case .loading:
            return {
                // Never returns, but stays cancellable.
                try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
                throw CancellationError()
            }
        case .trains, .locationDenied:
            return { Scenario.trainsSnapshot(now: .now) }
        case .noTrains:
            return { Scenario.noTrainsSnapshot(now: .now) }
        case .offline, .offlineWithData:
            return { throw URLError(.notConnectedToInternet) }
        }
    }

    // MARK: Stub snapshots

    /// A plausible board at every station: each line runs every 10 minutes in both directions,
    /// staggered per line and station, with feed timestamps a few seconds old.
    static func trainsSnapshot(now: Date) -> PATHSnapshot {
        let lastUpdated = now.addingTimeInterval(-4)
        let lineOffset: [PATHLine: TimeInterval] = [
            .newarkWTC: 95, .hobokenWTC: 185, .journalSquare33rd: 252, .hoboken33rd: 330,
            .journalSquare33rdViaHoboken: 545,
        ]
        var boards: [StationCode: [Direction: [TrainArrival]]] = [:]
        for line in PATHLine.allCases {
            for (index, station) in line.stops.enumerated() {
                let stagger = TimeInterval((index * 47) % 120)
                for direction in Direction.allCases {
                    let terminus = direction == .toNY ? line.stops.last! : line.stops.first!
                    guard terminus != station else { continue }
                    let base = lineOffset[line, default: 120] + stagger + (direction == .toNJ ? 70 : 0)
                    let trains = (0..<3).map { run in
                        TrainArrival(
                            station: station,
                            direction: direction,
                            target: terminus,
                            headsign: headsign(line: line, terminus: terminus),
                            line: line,
                            lineColors: line.colorHexes,
                            arrival: lastUpdated.addingTimeInterval(base + TimeInterval(run) * 600),
                            arrivalTimeMessage: "",
                            lastUpdated: lastUpdated
                        )
                    }
                    boards[station, default: [:]][direction, default: []].append(contentsOf: trains)
                }
            }
        }
        for (station, directions) in boards {
            for (direction, trains) in directions {
                boards[station]?[direction] = trains.sorted { $0.arrival < $1.arrival }
            }
        }
        return PATHSnapshot(fetchedAt: now, boards: boards)
    }

    /// Every board empty of upcoming trains, but with a fresh `lastUpdated` (only departed
    /// trains are listed, as when service is suspended).
    static func noTrainsSnapshot(now: Date) -> PATHSnapshot {
        let lastUpdated = now.addingTimeInterval(-3)
        var boards: [StationCode: [Direction: [TrainArrival]]] = [:]
        for station in StationCode.allCases {
            for direction in StationCatalog.station(station).directions {
                boards[station, default: [:]][direction] = [
                    TrainArrival(
                        station: station, direction: direction, target: nil, headsign: "Not in service",
                        line: nil, lineColors: [], arrival: now.addingTimeInterval(-600),
                        arrivalTimeMessage: "", lastUpdated: lastUpdated
                    ),
                ]
            }
        }
        return PATHSnapshot(fetchedAt: now, boards: boards)
    }

    private static func headsign(line: PATHLine, terminus: StationCode) -> String {
        let name = StationCatalog.station(terminus).name
        return line == .journalSquare33rdViaHoboken ? "\(name) via Hoboken" : name
    }
}

/// The objects the main screen needs.
@MainActor
struct AppEnvironment {
    let model: BoardModel
    let location: LocationService

    /// Scenario environment when launched with `-UITestScenario` / `-UITestLocation`, else live.
    static func launch() -> AppEnvironment {
        if let requested = Scenario.fromLaunchArguments() {
            return requested.scenario.makeEnvironment(location: requested.location)
        }
        return AppEnvironment(model: BoardModel(), location: LocationService())
    }
}
