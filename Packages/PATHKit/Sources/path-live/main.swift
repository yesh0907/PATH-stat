// Debug CLI: fetch live PATH arrivals + alerts and print them.
// Usage: swift run --package-path Packages/PATHKit path-live [STATION=GRV]
import Foundation
import PATHKit

func describe(_ board: DepartureBoard, now: Date, limit: Int = 4) -> String {
    guard !board.trains.isEmpty else { return "    (no trains)" }
    return board.trains.prefix(limit).map { train in
        let minutes = String(format: "%3d", train.minutesRemaining(at: now))
        let line = train.line?.displayName ?? "unknown line [\(train.lineColors.joined(separator: ","))]"
        return "    \(minutes) min  \(train.headsign)  — \(line)"
    }.joined(separator: "\n")
}

func freshnessText(_ board: DepartureBoard, now: Date) -> String {
    switch board.freshness(at: now) {
    case .fresh(let age): "fresh, \(Int(age))s old"
    case .stale(let age): "STALE, \(Int(age))s old"
    case .unknown: "no data"
    }
}

let arguments = CommandLine.arguments.dropFirst()
let stationArg = (arguments.first ?? "GRV").uppercased()
guard let code = StationCode(rawValue: stationArg) else {
    let valid = StationCode.allCases.map(\.rawValue).joined(separator: " ")
    FileHandle.standardError.write(Data("error: unknown station '\(stationArg)'. Valid: \(valid)\n".utf8))
    exit(2)
}

let client = PATHClient()
do {
    let snapshot = try await client.fetchSnapshot()
    let now = Date()
    let station = StationCatalog.station(code)
    let feedUpdated = snapshot.boards.values.flatMap(\.values).flatMap { $0 }.map(\.lastUpdated).max()
    print("PATH live — \(station.name) (\(code.rawValue))")
    print("Fetched \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard)); stations in feed: \(snapshot.boards.count)")
    if let feedUpdated {
        print("Feed age: \(Int(now.timeIntervalSince(feedUpdated)))s (newest lastUpdated \(feedUpdated.formatted(date: .omitted, time: .standard)))")
    } else {
        print("Feed age: unknown (no messages)")
    }

    for direction in Direction.allCases where station.directions.contains(direction) {
        let board = snapshot.departures(at: code, direction: direction, now: now)
        print("\n\(direction.rawValue) [\(freshnessText(board, now: now))]")
        print(describe(board, now: now))
    }

    if code == .groveStreet {
        for toward in [StationCode.thirtyThirdStreet, .worldTradeCenter] {
            let board = snapshot.departures(at: code, direction: .toNY, toward: toward, now: now)
            print("\nToNY toward \(StationCatalog.station(toward).name)")
            print(describe(board, now: now))
        }
    }

    let alerts = try await client.fetchAlerts()
    print("\nAlerts (\(alerts.count))")
    for alert in alerts.prefix(5) {
        let when = alert.modifiedAt.formatted(date: .abbreviated, time: .shortened)
        print("  • [\(when)] \(alert.subject)")
        if !alert.lines.isEmpty { print("    lines: \(alert.lines.joined(separator: ", "))") }
        if !alert.stations.isEmpty { print("    stations: \(alert.stations.map(\.rawValue).joined(separator: ", "))") }
        print("    " + alert.message.replacingOccurrences(of: "\n", with: "\n    "))
    }
} catch {
    let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("error: \(description) (\(error))\n".utf8))
    exit(1)
}
