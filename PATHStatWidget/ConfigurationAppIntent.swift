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
            .nearest: "Smart (based on location)",
            .savedTrip: "Saved trip",
            .custom: "Station & destination",
        ]
    }
}

/// Configuration for the "Next PATH train" widget. Only the parameters relevant to `mode`
/// are shown (see `parameterSummary`).
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Next PATH train" }
    static var description: IntentDescription { "Shows the next PATH trains for a trip." }

    @Parameter(title: "Show", default: .nearest)
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
        case .nearest: .smart
        }
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
