import SwiftUI

@main
struct PATHStatApp: App {
    @State private var launchMode = LaunchMode.fromLaunchArguments()

    var body: some Scene {
        WindowGroup {
            switch launchMode {
            case .main(let environment):
                MainView(model: environment.model, location: environment.location, widgetSync: environment.widgetSync)
            case .widgetGallery(let state):
                WidgetGalleryView(state: state)
            }
        }
    }
}
