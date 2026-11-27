import Foundation

/// Deterministic stub feeds for UI tests, previews, screenshots and widget placeholders.
extension PATHSnapshot {
    /// A plausible board at every station: each line runs every 10 minutes in both directions,
    /// staggered per line and station, with feed timestamps a few seconds old.
    public static func sampleTrains(now: Date) -> PATHSnapshot {
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
                            headsign: sampleHeadsign(line: line, terminus: terminus),
                            line: line,
                            lineColors: line.colorHex.split(separator: ",").map(String.init),
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
    public static func sampleNoTrains(now: Date) -> PATHSnapshot {
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

    private static func sampleHeadsign(line: PATHLine, terminus: StationCode) -> String {
        let name = StationCatalog.station(terminus).name
        return line == .journalSquare33rdViaHoboken ? "\(name) via Hoboken" : name
    }
}
