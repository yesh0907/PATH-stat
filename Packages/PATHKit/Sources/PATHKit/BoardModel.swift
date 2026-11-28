import CoreLocation
import Foundation
import Observation
import os

/// State for the main screen: the selected trip, the latest feed snapshot, and favourites.
@MainActor
@Observable
public final class BoardModel {
    public typealias Fetch = @Sendable () async throws -> PATHSnapshot

    public private(set) var trip: Trip
    public private(set) var snapshot: PATHSnapshot?
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false
    /// When the current `snapshot` was fetched.
    public private(set) var lastFetchAt: Date?
    public private(set) var favorites: [Trip]

    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let store: TripStore
    /// Set once the user picks a trip/station/destination this session.
    @ObservationIgnored private var hasManualSelection = false
    /// The fetch every concurrent `refresh()` caller shares.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.yesh0907.PATHStat", category: "feed")

    /// - Parameter initialSnapshot: shown before the first fetch (e.g. data from an earlier
    ///   session); sets `lastFetchAt` to its `fetchedAt`.
    public init(
        store: TripStore = TripStore(),
        initialSnapshot: PATHSnapshot? = nil,
        fetch: @escaping Fetch = { try await PATHClient().fetchSnapshot() }
    ) {
        self.store = store
        self.fetch = fetch
        favorites = store.favorites
        trip = TripPlanner.defaultTrip(location: nil, lastTrip: store.lastTrip)
        snapshot = initialSnapshot
        lastFetchAt = initialSnapshot?.fetchedAt
    }

    // MARK: Board

    public func board(now: Date) -> DepartureBoard? {
        snapshot?.departures(at: trip.origin, toward: trip.destination, now: now)
    }

    public var destinationOptions: (termini: [DestinationOption], otherStops: [DestinationOption]) {
        StationCatalog.destinationOptions(from: trip.origin)
    }

    /// The two one-tap destinations for the direction control on the main screen.
    public var quickDestinations: [StationCode] {
        TripPlanner.quickDestinations(from: trip.origin)
    }

    /// Fetches the feed. The fetch is trip-independent, so concurrent callers (refresh loop,
    /// pull-to-refresh, Retry) share one in-flight fetch. Cancelling a caller doesn't cancel
    /// the shared fetch; its result still lands.
    public func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        isLoading = true
        let task = Task { @MainActor in
            await self.performFetch()
            // Cleared here, not by the caller, so only the completed fetch resets the state.
            self.inFlight = nil
            self.isLoading = false
        }
        inFlight = task
        await task.value
    }

    private func performFetch() async {
        do {
            let result = try await fetch()
            snapshot = result
            lastFetchAt = result.fetchedAt
            errorMessage = nil
        } catch is CancellationError {
            // A cancelled fetch is not a feed error.
        } catch {
            // Keep the previous snapshot visible; the offline banner flags its age.
            let pathError = PATHError.from(error)
            logger.error("Feed fetch failed: \(String(describing: pathError), privacy: .public)")
            errorMessage = pathError.errorDescription ?? "The PATH feed is unavailable."
        }
    }

    // MARK: Trip selection

    /// Shows `trip`. Manual selections are remembered as the last trip and stop the
    /// location-based default from overriding the user's choice this session; non-manual
    /// selections never touch the stored last trip.
    public func select(_ trip: Trip, manual: Bool) {
        self.trip = trip
        if manual {
            hasManualSelection = true
            store.lastTrip = trip
        }
    }

    /// Switches origin, keeping the destination when it's still reachable on one line.
    public func selectStation(_ station: StationCode) {
        let destination = TripPlanner.defaultDestination(from: station, preferring: trip.destination)
        select(namedRoute(from: station, to: destination), manual: true)
    }

    /// Switches destination. Ignores one not reachable on a single line from the origin
    /// (including the origin itself).
    public func selectDestination(_ destination: StationCode) {
        guard !StationCatalog.lines(serving: trip.origin, to: destination).isEmpty else { return }
        select(namedRoute(from: trip.origin, to: destination), manual: true)
    }

    /// Applies the smart default for `location` / `authorization`. Re-applied on every fresh
    /// fix and authorization change until the user makes a manual choice this session. Fixes
    /// come only from one-shot `requestLocation()` calls at launch and on returning to the
    /// foreground, so the trip doesn't thrash while the screen is in use.
    public func locationDidChange(_ location: CLLocation?, authorization: LocationAuthorization) {
        // Remember the nearest station on every fresh fix, even after a manual selection:
        // the widget's smart mode reads it when it can't get a fix of its own.
        if authorization == .authorized, let location {
            store.lastNearestStation = TripPlanner.nearestStation(to: location)
        }
        guard !hasManualSelection else { return }
        switch authorization {
        case .notDetermined:
            return
        case .authorized:
            guard let location else { return }
            select(TripPlanner.defaultTrip(location: location, lastTrip: store.lastTrip), manual: false)
        case .denied:
            select(TripPlanner.defaultTrip(location: nil, lastTrip: store.lastTrip), manual: false)
        }
    }

    /// A favourite or preset with this route (keeping its name), else an unnamed trip.
    private func namedRoute(from origin: StationCode, to destination: StationCode) -> Trip {
        favorites.first { $0.origin == origin && $0.destination == destination }
            ?? Trip.route(from: origin, to: destination)
    }

    // MARK: Favorites

    public var isCurrentTripFavorite: Bool {
        favorites.contains { $0.sameRoute(as: trip) }
    }

    public func toggleFavorite() {
        if isCurrentTripFavorite {
            removeFavorite(trip)
        } else {
            addFavorite(trip)
        }
    }

    public func addFavorite(_ trip: Trip) {
        guard !favorites.contains(where: { $0.sameRoute(as: trip) }) else { return }
        favorites.append(trip)
        store.favorites = favorites
    }

    public func removeFavorite(_ trip: Trip) {
        favorites.removeAll { $0.sameRoute(as: trip) }
        store.favorites = favorites
    }
}
