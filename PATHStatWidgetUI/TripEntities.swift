import AppIntents
import PATHKit

// Shared by the widget configuration and the Live Activity intents (app + widget targets).

// MARK: - Saved trips

struct TripEntity: AppEntity {
    let trip: Trip

    init(_ trip: Trip) {
        self.trip = trip
    }

    var id: String { trip.id }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Saved trip" }
    static var defaultQuery: TripQuery { TripQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(trip.title)")
    }
}

/// Saved trips: `TripStore.shared.favorites` (the presets until favourites are saved).
struct TripQuery: EntityQuery {
    func entities(for identifiers: [TripEntity.ID]) async throws -> [TripEntity] {
        let favorites = TripStore.shared.favorites
        return identifiers.compactMap { id in
            if let trip = favorites.first(where: { $0.id == id }) { return TripEntity(trip) }
            // A trip removed from favourites since it was configured: keep showing its route.
            let parts = id.split(separator: "-").map(String.init)
            guard parts.count == 2,
                  let from = StationCode(rawValue: parts[0]), let to = StationCode(rawValue: parts[1]),
                  !StationCatalog.lines(serving: from, to: to).isEmpty else { return nil }
            return TripEntity(Trip.route(from: from, to: to))
        }
    }

    func suggestedEntities() async throws -> [TripEntity] {
        TripStore.shared.favorites.map(TripEntity.init)
    }

    func defaultResult() async -> TripEntity? {
        TripEntity(.groveTo33rd)
    }
}

// MARK: - Stations

struct StationEntity: AppEntity {
    let code: StationCode

    init(_ code: StationCode) {
        self.code = code
    }

    var id: String { code.rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Station" }
    static var defaultQuery: StationQuery { StationQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(StationCatalog.station(code).name)")
    }
}

struct StationQuery: EntityQuery {
    func entities(for identifiers: [StationEntity.ID]) async throws -> [StationEntity] {
        identifiers.compactMap(StationCode.init(rawValue:)).map(StationEntity.init)
    }

    func suggestedEntities() async throws -> [StationEntity] {
        StationCatalog.all.map { StationEntity($0.code) }
    }
}
