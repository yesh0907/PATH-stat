import CoreLocation
import Foundation

/// How a widget picks its trip, mirroring the widget's configuration options.
public enum WidgetTripChoice: Sendable, Hashable {
    /// A saved trip (favourite); nil when none was chosen or it no longer exists.
    case savedTrip(Trip?)
    /// Any origin/destination pair; either may be unset in the configuration.
    case custom(from: StationCode?, to: StationCode?)
    /// The smart trip from the rider's location (`TripPlanner.smartTrip`).
    case smart
}

/// Resolves a widget's configured trip. Pure: the caller supplies the location, if any.
public enum WidgetTripResolver {
    public struct Resolution: Sendable, Hashable {
        public let trip: Trip
        /// `.smart` was requested but no location or last nearest station was available;
        /// `trip` is the fallback.
        public let locationUnavailable: Bool
        /// The nearest station a fresh location fix produced, so the caller can persist it.
        /// Nil when no location was involved.
        public let nearestStation: StationCode?

        public init(trip: Trip, locationUnavailable: Bool = false, nearestStation: StationCode? = nil) {
            self.trip = trip
            self.locationUnavailable = locationUnavailable
            self.nearestStation = nearestStation
        }
    }

    public static let fallback: Trip = .groveTo33rd

    /// - `savedTrip`: the trip, else `fallback`.
    /// - `custom`: `Trip.route(from:to:)` when one line serves the pair, else `fallback`.
    /// - `smart`: `TripPlanner.smartTrip` for the nearest station with a location (reporting
    ///   it in `nearestStation`); without one but with a `lastNearestStation`, the smart trip
    ///   for it; with neither, `fallback` with `locationUnavailable`.
    public static func resolve(_ choice: WidgetTripChoice, location: CLLocation?, lastNearestStation: StationCode? = nil) -> Resolution {
        switch choice {
        case .savedTrip(let trip):
            return Resolution(trip: trip ?? fallback)
        case .custom(let from, let to):
            guard let from, let to, !StationCatalog.lines(serving: from, to: to).isEmpty else {
                return Resolution(trip: fallback)
            }
            return Resolution(trip: Trip.route(from: from, to: to))
        case .smart:
            if let location {
                let nearest = TripPlanner.nearestStation(to: location)
                return Resolution(trip: TripPlanner.smartTrip(nearest: nearest), nearestStation: nearest)
            }
            if let lastNearestStation {
                return Resolution(trip: TripPlanner.smartTrip(nearest: lastNearestStation))
            }
            return Resolution(trip: fallback, locationUnavailable: true)
        }
    }
}
