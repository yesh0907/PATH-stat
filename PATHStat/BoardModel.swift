import CoreLocation
import Foundation
import Observation
import os
import PATHKit

/// State for the main screen: the selected trip, the latest feed snapshot, and favourites.
@MainActor
@Observable
final class BoardModel {
    typealias Fetch = @Sendable () async throws -> PATHSnapshot

    private(set) var trip: Trip
    private(set) var snapshot: PATHSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// When the current `snapshot` was fetched.
    private(set) var lastFetchAt: Date?
    private(set) var favorites: [Trip]

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let store: TripStore
    /// Set once the user picks a trip/station/destination this session.
    @ObservationIgnored private var hasManualSelection = false
    /// Set once the smart default has been re-resolved from location (or its denial).
    @ObservationIgnored private var hasResolvedLocationDefault = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "feed")

    init(
        store: TripStore = TripStore(),
        fetch: @escaping Fetch = { try await PATHClient().fetchSnapshot() }
    ) {
        self.store = store
        self.fetch = fetch
        favorites = store.favorites
        trip = TripPlanner.defaultTrip(location: nil, lastTrip: store.lastTrip)
    }

    // MARK: Board

    func board(now: Date) -> DepartureBoard? {
        snapshot?.departures(at: trip.origin, toward: trip.destination, now: now)
    }

    var destinationOptions: (termini: [DestinationOption], otherStops: [DestinationOption]) {
        StationCatalog.destinationOptions(from: trip.origin)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await fetch()
            snapshot = result
            lastFetchAt = result.fetchedAt
            errorMessage = nil
        } catch is CancellationError {
            // A cancelled refresh (view went away, trip changed, app backgrounded) is not a feed error.
        } catch {
            // Keep the previous snapshot visible; the offline banner flags its age.
            let pathError = PATHError.from(error)
            logger.error("Feed fetch failed: \(String(describing: pathError), privacy: .public)")
            errorMessage = pathError.errorDescription ?? "The PATH feed is unavailable."
        }
    }

    // MARK: Trip selection

    /// Shows `trip`. Manual selections are remembered as the last trip and stop the
    /// location-based default from overriding the user's choice this session.
    func select(_ trip: Trip, manual: Bool) {
        self.trip = trip
        if manual {
            hasManualSelection = true
            store.lastTrip = trip
        }
    }

    /// Switches origin, keeping the destination when it's still reachable on one line.
    func selectStation(_ station: StationCode) {
        let destination = TripPlanner.defaultDestination(from: station, preferring: trip.destination)
        select(namedRoute(from: station, to: destination), manual: true)
    }

    func selectDestination(_ destination: StationCode) {
        guard destination != trip.origin else { return }
        select(namedRoute(from: trip.origin, to: destination), manual: true)
    }

    /// Applies the smart default once, when location first becomes known (or is denied),
    /// unless the user already chose something.
    func locationDidChange(_ location: CLLocation?, authorization: LocationService.Authorization) {
        guard !hasResolvedLocationDefault else { return }
        switch authorization {
        case .notDetermined:
            return
        case .authorized:
            guard let location else { return }
            hasResolvedLocationDefault = true
            if !hasManualSelection {
                select(TripPlanner.defaultTrip(location: location, lastTrip: store.lastTrip), manual: false)
            }
        case .denied:
            hasResolvedLocationDefault = true
            if !hasManualSelection {
                select(TripPlanner.defaultTrip(location: nil, lastTrip: store.lastTrip), manual: false)
            }
        }
    }

    /// A favourite or preset with this route (keeping its name), else an unnamed trip.
    private func namedRoute(from origin: StationCode, to destination: StationCode) -> Trip {
        favorites.first { $0.origin == origin && $0.destination == destination }
            ?? Trip.route(from: origin, to: destination)
    }

    // MARK: Favorites

    var isCurrentTripFavorite: Bool {
        favorites.contains { $0.sameRoute(as: trip) }
    }

    func toggleFavorite() {
        if isCurrentTripFavorite {
            removeFavorite(trip)
        } else {
            addFavorite(trip)
        }
    }

    func addFavorite(_ trip: Trip) {
        guard !favorites.contains(where: { $0.sameRoute(as: trip) }) else { return }
        favorites.append(trip)
        store.favorites = favorites
    }

    func removeFavorite(_ trip: Trip) {
        favorites.removeAll { $0.sameRoute(as: trip) }
        store.favorites = favorites
    }
}
