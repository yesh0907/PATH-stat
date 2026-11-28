import CoreLocation
import Foundation
import PATHKit

/// Deterministic app states for UI tests, screenshots and previews.
///
/// Launch with `-UITestScenario <loading|trains|singleTrain|noTrains|offline|locationDenied|offlineWithData>`
/// and optionally `-UITestLocation <lat>,<lon>`. Scenario mode uses a throwaway `TripStore`, a
/// stub feed, and fixed location state; the real `CLLocationManager` is never created.
enum Scenario: String, CaseIterable, Sendable {
    case loading
    case trains
    /// Like `trains`, but one run per line: Grove St → WTC has exactly one train,
    /// so the following-train and later-trains placeholders show.
    case singleTrain
    case noTrains
    case offline
    case locationDenied
    /// Starts with a 3-minute-old snapshot and every fetch fails, so the "Can't update —
    /// showing data from … ago" banner appears after the first refresh.
    case offlineWithData

    static let scenarioArgument = "-UITestScenario"
    static let locationArgument = "-UITestLocation"

    /// The scenario requested on the command line, if any. `-UITestLocation` or `-UITestFeedback`
    /// alone implies `.trains`.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> (scenario: Scenario, location: CLLocation?)? {
        let scenario = value(after: scenarioArgument, in: arguments).flatMap(Scenario.init(rawValue:))
        let location = value(after: locationArgument, in: arguments).flatMap(parseLocation)
        guard scenario != nil || location != nil || arguments.contains(FeedbackScenario.argument) else { return nil }
        return (scenario ?? .trains, location)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// "40.7190,-74.0430" → CLLocation.
    static func parseLocation(_ text: String) -> CLLocation? {
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let lat = parts[0], let lon = parts[1],
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: Environment

    @MainActor
    func makeEnvironment(location override: CLLocation? = nil) -> AppEnvironment {
        let suite = "com.yesh0907.PATHStat.scenario.\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let store = TripStore(suiteName: suite)

        let location: LocationService
        if self == .locationDenied {
            location = .fixed(authorization: .denied, location: nil)
        } else {
            location = .fixed(
                authorization: .authorized,
                location: override ?? StationCatalog.station(.groveStreet).location
            )
        }
        let initialSnapshot = self == .offlineWithData
            ? PATHSnapshot.sampleTrains(now: .now.addingTimeInterval(-180))
            : nil
        return AppEnvironment(
            model: BoardModel(store: store, initialSnapshot: initialSnapshot, fetch: fetch),
            location: location,
            widgetSync: nil,
            liveActivities: LiveActivityController(backend: Self.liveActivityBackend()),
            feedback: FeedbackScenario.fromLaunchArguments().makeCenter()
        )
    }

    static let liveActivityBackendArgument = "-LiveActivityBackend"

    /// In-memory unless launched with `-LiveActivityBackend real` (manual ActivityKit checks).
    @MainActor
    static func liveActivityBackend(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> any LiveActivityBackend {
        value(after: liveActivityBackendArgument, in: arguments) == "real" ? ActivityKitBackend() : StubLiveActivityBackend()
    }

    var fetch: BoardModel.Fetch {
        switch self {
        case .loading:
            return {
                // Never returns, but stays cancellable.
                try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
                throw CancellationError()
            }
        case .trains, .locationDenied:
            return { PATHSnapshot.sampleTrains(now: .now) }
        case .singleTrain:
            return { PATHSnapshot.sampleTrains(now: .now, runsPerLine: 1) }
        case .noTrains:
            return { PATHSnapshot.sampleNoTrains(now: .now) }
        case .offline, .offlineWithData:
            return { throw URLError(.notConnectedToInternet) }
        }
    }
}

/// The objects the main screen needs.
@MainActor
struct AppEnvironment {
    let model: BoardModel
    let location: LocationService
    /// Shares fetched snapshots with the widget; nil in scenario mode.
    let widgetSync: WidgetSync?
    let liveActivities: LiveActivityController
    /// In-app feedback: GitHub + Keychain live; stub service + in-memory token in scenario mode.
    let feedback: FeedbackCenter

    /// Scenario environment when launched with `-UITestScenario` / `-UITestLocation`, else live.
    static func launch() -> AppEnvironment {
        if let requested = Scenario.fromLaunchArguments() {
            return requested.scenario.makeEnvironment(location: requested.location)
        }
        // Favourites and the last trip live in the App Group so the widget can read them;
        // copy them over once from the pre-widget standard defaults.
        let store = TripStore.shared
        store.migrateIfNeeded(from: TripStore())
        TrainActivities.didStart = BackgroundRefresh.schedule
        let feedback = FeedbackCenter.live()
        BackgroundRefresh.feedback = feedback
        return AppEnvironment(
            model: BoardModel(store: store),
            location: LocationService(),
            widgetSync: WidgetSync(),
            liveActivities: LiveActivityController(
                backend: ActivityKitBackend(),
                scheduleBackgroundRefresh: BackgroundRefresh.schedule
            ),
            feedback: feedback
        )
    }
}

/// What the app shows at launch.
@MainActor
enum LaunchMode {
    case main(AppEnvironment)
    /// `-WidgetGallery <state>`: every widget family rendered for one fixed state.
    case widgetGallery(WidgetSampleState)
    /// `-LiveActivityGallery <state>`: the Live Activity views (Lock Screen, Dynamic Island) for
    /// one fixed sample state. Never touches ActivityKit or the caches.
    case liveActivityGallery(TrainActivitySampleState)

    nonisolated static let widgetGalleryArgument = "-WidgetGallery"
    nonisolated static let liveActivityGalleryArgument = "-LiveActivityGallery"

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchMode {
        if let index = arguments.firstIndex(of: widgetGalleryArgument),
           arguments.indices.contains(index + 1),
           let state = WidgetSampleState(rawValue: arguments[index + 1]) {
            return .widgetGallery(state)
        }
        if let index = arguments.firstIndex(of: liveActivityGalleryArgument),
           arguments.indices.contains(index + 1),
           let state = TrainActivitySampleState(rawValue: arguments[index + 1]) {
            return .liveActivityGallery(state)
        }
        return .main(.launch())
    }
}
