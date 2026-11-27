import SwiftUI

@main
struct PATHStatApp: App {
    @State private var launchMode = LaunchMode.fromLaunchArguments()

    var body: some Scene {
        WindowGroup {
            switch launchMode {
            case .main(let environment):
                MainView(
                    model: environment.model,
                    location: environment.location,
                    widgetSync: environment.widgetSync,
                    liveActivities: environment.liveActivities
                )
            case .widgetGallery(let state):
                WidgetGalleryView(state: state)
            case .liveActivityGallery(let state):
                LiveActivityGalleryView(state: state)
            }
        }
        // Best-effort Live Activity / widget refresh; a no-op in scenario and gallery modes.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.perform()
        }
    }
}
