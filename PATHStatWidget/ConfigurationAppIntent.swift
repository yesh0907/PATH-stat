import AppIntents
import PATHKit
import WidgetKit

/// How the widget chooses its trip.
enum TripMode: String, AppEnum {
    case savedTrip
    case custom
    case nearest

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Trip" }

    static var caseDisplayRepresentations: [TripMode: DisplayRepresentation] {
        [
            .savedTrip: "Saved trip",
            .custom: "Station & destination",
            .nearest: "Nearest station",
        ]
    }
}

/// Configuration for the "Next PATH train" widget. Only the parameters relevant to `mode`
/// are shown (see `parameterSummary`).
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Next PATH train" }
    static var description: IntentDescription { "Shows the next PATH trains for a trip." }

    @Parameter(title: "Show", default: .savedTrip)
    var mode: TripMode

    @Parameter(title: "Trip")
    var trip: TripEntity?

    @Parameter(title: "Station")
    var origin: StationEntity?

    @Parameter(title: "Destination", optionsProvider: DestinationOptionsProvider())
    var destination: StationEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, .savedTrip) {
            Summary("\(\.$mode): \(\.$trip)")
        } otherwise: {
            When(\.$mode, .equalTo, .custom) {
                Summary("\(\.$mode): \(\.$origin) to \(\.$destination)")
            } otherwise: {
                Summary("\(\.$mode)")
            }
        }
    }

    init() {}

    init(mode: TripMode, trip: Trip? = nil, origin: StationCode? = nil, destination: StationCode? = nil) {
        self.mode = mode
        self.trip = trip.map(TripEntity.init)
        self.origin = origin.map(StationEntity.init)
        self.destination = destination.map(StationEntity.init)
    }

    /// The PATHKit choice this configuration describes.
    var choice: WidgetTripChoice {
        switch mode {
        case .savedTrip: .savedTrip(trip?.trip)
        case .custom: .custom(from: origin?.code, to: destination?.code)
        case .nearest: .nearest
        }
    }
}

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

/// Destinations reachable on one line from the chosen station (all stations until one is chosen).
struct DestinationOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<ConfigurationAppIntent>(\.$origin)
    var intent

    func results() async throws -> [StationEntity] {
        guard let origin = intent?.origin.code else {
            return StationCatalog.all.map { StationEntity($0.code) }
        }
        return StationCatalog.all
            .map(\.code)
            .filter { !StationCatalog.lines(serving: origin, to: $0).isEmpty }
            .map(StationEntity.init)
    }
}
