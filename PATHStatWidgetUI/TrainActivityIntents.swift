import ActivityKit
import AppIntents
import PATHKit

// Live Activity intents. As `LiveActivityIntent`s compiled into both the app and the widget
// extension, they always perform in the app's process (also for the Refresh button on the
// Lock Screen), where ActivityKit can start and update activities.

enum TrainActivityIntentError: Error, CustomLocalizedStringResourceConvertible {
    case activitiesDisabled

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .activitiesDisabled:
            "Live Activities are turned off for PATH Stat. Turn them on in Settings › PATH Stat."
        }
    }
}

struct StartTrainActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Start PATH Live Activity" }
    static var description: IntentDescription {
        "Shows the next PATH trains for a trip on the Lock Screen and in the Dynamic Island."
    }

    @Parameter(title: "Trip")
    var trip: TripEntity

    init() {}

    init(trip: Trip) {
        self.trip = TripEntity(trip)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await startTrainActivity(trip: trip.trip)
    }
}

/// "Home to 33rd": Grove St → 33rd St without asking. A dedicated intent because the App
/// Intents metadata for an `AppShortcut` doesn't keep a preset `StartTrainActivityIntent(trip:)`
/// parameter value (the extracted shortcut would be the same action as "Track my PATH train").
struct StartHomeTo33rdIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Start Grove St → 33rd St Live Activity" }
    static var description: IntentDescription {
        "Shows the next PATH trains from Grove St to 33rd St on the Lock Screen."
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await startTrainActivity(trip: .groveTo33rd)
    }
}

/// "Next PATH train": the smart trip for the rider's last known nearest station.
struct StartSmartTrainActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Start Next PATH Train Live Activity" }
    static var description: IntentDescription {
        "Shows the next PATH trains for your trip on the Lock Screen and in the Dynamic Island."
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await startTrainActivity(trip: TripPlanner.smartTrip(nearest: TripStore.shared.lastNearestStation))
    }
}

@MainActor
private func startTrainActivity(trip: Trip) async throws -> some IntentResult & ProvidesDialog {
    guard TrainActivities.areActivitiesEnabled else { throw TrainActivityIntentError.activitiesDisabled }
    let result = await SnapshotCache.shared.loadOrFetch(maxAge: TrainActivities.cacheFreshness) {
        try await PATHClient().fetchSnapshot()
    }
    try await TrainActivities.start(trip: trip, snapshot: result.snapshot, fetchFailed: result.error != nil)
    return .result(dialog: "Tracking \(trip.title) on your Lock Screen.")
}

struct StopTrainActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop PATH Live Activity" }
    static var description: IntentDescription { "Ends the PATH Live Activity." }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TrainActivities.endAll()
        return .result()
    }
}

struct RefreshTrainActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Refresh PATH Live Activity" }
    static var description: IntentDescription { "Fetches the latest PATH times for the Live Activity." }
    static var isDiscoverable: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TrainActivities.refresh()
        return .result()
    }
}
