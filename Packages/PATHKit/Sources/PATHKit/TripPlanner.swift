import CoreLocation
import Foundation

/// Picks which trip to show when the app opens.
public enum TripPlanner {
    public static let homeStation: StationCode = .groveStreet
    public static let workStation: StationCode = .twentyThirdStreet

    /// The smart trip for a rider whose nearest station is `nearest`: at (or without) Grove St
    /// the commute preset Grove St → 33rd St; everywhere else the way home — every station
    /// reaches Grove St on one line. 23rd St → Grove St keeps the "Going home" preset name.
    public static func smartTrip(nearest: StationCode?) -> Trip {
        guard let nearest, nearest != homeStation else { return .groveTo33rd }
        return Trip.route(from: nearest, to: homeStation)
    }

    /// The closest station to `location`.
    public static func nearestStation(to location: CLLocation) -> StationCode? {
        StationCatalog.stations(nearest: location).first?.station.code
    }

    /// The default trip: the smart trip for the nearest station with a location;
    /// without one, `lastTrip`, else Grove St → 33rd St.
    public static func defaultTrip(location: CLLocation?, lastTrip: Trip?) -> Trip {
        guard let location else { return lastTrip ?? .groveTo33rd }
        return smartTrip(nearest: nearestStation(to: location))
    }

    /// The two one-tap destinations for the direction control: at Grove St, 33rd St and WTC;
    /// elsewhere Grove St (the way home) plus 33rd St or WTC when reachable on one line,
    /// else the first terminus option. Always exactly two distinct stations ≠ `origin`.
    public static func quickDestinations(from origin: StationCode) -> [StationCode] {
        if origin == homeStation { return [.thirtyThirdStreet, .worldTradeCenter] }
        var result: [StationCode] = [homeStation]
        let preferred: [StationCode] = [.thirtyThirdStreet, .worldTradeCenter]
        if let extra = preferred.first(where: {
            $0 != origin && !StationCatalog.lines(serving: origin, to: $0).isEmpty
        }) {
            result.append(extra)
        } else if let fallback = StationCatalog.destinationOptions(from: origin).termini
            .map(\.destination)
            .first(where: { !result.contains($0) && $0 != origin }) {
            result.append(fallback)
        }
        return result
    }

    /// `preferring` if it is reachable on one line from `origin`, else the first terminus option
    /// (`toNY` ends first, in `PATHLine.allCases` order).
    public static func defaultDestination(from origin: StationCode, preferring: StationCode? = nil) -> StationCode {
        if let preferring, !StationCatalog.lines(serving: origin, to: preferring).isEmpty {
            return preferring
        }
        let options = StationCatalog.destinationOptions(from: origin)
        // Every station is on at least one line with another station; enforced by tests.
        return (options.termini.first ?? options.otherStops.first)!.destination
    }
}
