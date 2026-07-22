import UIKit

@MainActor
enum SelfReplacementController {
    static func beginInstallationBackgroundTask() -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(
            withName: "Seal Self Replacement",
            expirationHandler: nil
        )
    }

    static func endInstallationBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }

    static func returnToHomeScreen() {
        #if !targetEnvironment(simulator)
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else { return }
        _ = UIApplication.shared.perform(selector)
        #endif
    }
}
