import AppIntents
import PATHKit

/// Siri / Shortcuts / Spotlight / Action Button entry points for the Live Activity.
/// ("Home to 33rd" uses `StartHomeTo33rdIntent`, not `StartTrainActivityIntent(trip:)`: the
/// extracted shortcut metadata drops preset parameter values.)
struct PATHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSmartTrainActivityIntent(),
            phrases: [
                "\(.applicationName) next train",
                "Next train with \(.applicationName)",
            ],
            shortTitle: "Next PATH train",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: StartHomeTo33rdIntent(),
            phrases: [
                "\(.applicationName) home to 33rd",
                "Start \(.applicationName) Grove Street to 33rd",
            ],
            shortTitle: "Home to 33rd",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: StartTrainActivityIntent(),
            phrases: [
                "Track my \(.applicationName) train",
                "Start \(.applicationName) Live Activity",
            ],
            shortTitle: "Track a PATH trip",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: StopTrainActivityIntent(),
            phrases: ["Stop \(.applicationName) Live Activity"],
            shortTitle: "Stop Live Activity",
            systemImageName: "stop.circle"
        )
    }
}
