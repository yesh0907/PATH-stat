import CoreLocation
import Foundation

/// How a widget picks its trip, mirroring the widget's configuration options.
public enum WidgetTripChoice: Sendable, Hashable {
    /// A saved trip (favourite); nil when none was chosen or it no longer exists.
    case savedTrip(Trip?)
    /// Any origin/destination pair; either may be unset in the configuration.
    case custom(from: StationCode?, to: StationCode?)
    /// The smart default from the rider's location (`TripPlanner.defaultTrip`).
    case nearest
}

/// Resolves a widget's configured trip. Pure: the caller supplies the location, if any.
public enum WidgetTripResolver {
    public struct Resolution: Sendable, Hashable {
        public let trip: Trip
        /// `.nearest` was requested but no location was available; `trip` is the fallback.
        public let locationUnavailable: Bool

        public init(trip: Trip, locationUnavailable: Bool = false) {
            self.trip = trip
            self.locationUnavailable = locationUnavailable
        }
    }

    public static let fallback: Trip = .groveTo33rd

    /// - `savedTrip`: the trip, else `fallback`.
    /// - `custom`: `Trip.route(from:to:)` when one line serves the pair, else `fallback`.
    /// - `nearest`: `TripPlanner.defaultTrip(location:lastTrip:)` with a location; without
    ///   one, `fallback` with `locationUnavailable`.
    public static func resolve(_ choice: WidgetTripChoice, location: CLLocation?, lastTrip: Trip? = nil) -> Resolution {
        switch choice {
        case .savedTrip(let trip):
            return Resolution(trip: trip ?? fallback)
        case .custom(let from, let to):
            guard let from, let to, !StationCatalog.lines(serving: from, to: to).isEmpty else {
                return Resolution(trip: fallback)
            }
            return Resolution(trip: Trip.route(from: from, to: to))
        case .nearest:
            guard let location else { return Resolution(trip: fallback, locationUnavailable: true) }
            return Resolution(trip: TripPlanner.defaultTrip(location: location, lastTrip: lastTrip))
        }
    }
}
