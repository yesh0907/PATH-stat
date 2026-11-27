import SwiftUI

@main
struct PATHStatApp: App {
    @State private var environment = AppEnvironment.launch()

    var body: some Scene {
        WindowGroup {
            MainView(model: environment.model, location: environment.location)
        }
    }
}
