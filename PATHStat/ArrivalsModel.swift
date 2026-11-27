import Foundation
import Observation
import PATHKit

/// Placeholder phase-1 model: fetches the feed and exposes Grove St boards for both directions.
@MainActor
@Observable
final class ArrivalsModel {
    let station: StationCode
    private let client: PATHClient

    private(set) var snapshot: PATHSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    init(station: StationCode = .groveStreet, client: PATHClient = PATHClient()) {
        self.station = station
        self.client = client
    }

    var stationInfo: Station { StationCatalog.station(station) }

    var directions: [Direction] {
        Direction.allCases.filter { stationInfo.directions.contains($0) }
    }

    func board(_ direction: Direction, now: Date) -> DepartureBoard? {
        snapshot?.departures(at: station, direction: direction, now: now)
    }

    /// Freshness of the newest data across this station's boards.
    func freshness(now: Date) -> Freshness {
        let boards = directions.compactMap { board($0, now: now) }
        guard let newest = boards.max(by: { ($0.lastUpdated ?? .distantPast) < ($1.lastUpdated ?? .distantPast) }) else {
            return .unknown
        }
        return newest.freshness(at: now)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchSnapshot()
            errorMessage = nil
        } catch {
            // Keep the previous snapshot visible; the stale line will flag its age.
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
