import SwiftUI

@main
@MainActor
struct SealApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootTabView(
                appsViewModel: container.appsViewModel,
                settingsViewModel: container.settingsViewModel
            )
        }
    }
}
