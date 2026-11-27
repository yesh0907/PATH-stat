import CoreLocation
import Foundation

/// Picks which trip to show when the app opens.
public enum TripPlanner {
    public static let homeStation: StationCode = .groveStreet
    public static let workStation: StationCode = .twentyThirdStreet
    /// How close the rider must be to home/work for the commute presets to apply.
    public static let nearbyRadius: CLLocationDistance = 1000

    /// The smart default trip:
    /// 1. near home (nearest station is Grove St, within `nearbyRadius`) → Grove St → 33rd St;
    /// 2. near work (nearest is 23rd St, within radius) → Going home;
    /// 3. elsewhere with a location → from the nearest station, to `lastTrip`'s destination if
    ///    `lastTrip` started there, else `defaultDestination(from:)`;
    /// 4. no location → `lastTrip`, else Grove St → 33rd St.
    public static func defaultTrip(location: CLLocation?, lastTrip: Trip?) -> Trip {
        guard let location, let nearest = StationCatalog.stations(nearest: location).first else {
            return lastTrip ?? .groveTo33rd
        }
        let origin = nearest.station.code
        if nearest.distance <= nearbyRadius {
            if origin == homeStation { return .groveTo33rd }
            if origin == workStation { return .goingHome }
        }
        if let lastTrip, lastTrip.origin == origin,
           !StationCatalog.lines(serving: origin, to: lastTrip.destination).isEmpty {
            return lastTrip
        }
        return Trip.route(from: origin, to: defaultDestination(from: origin))
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
