import UIKit

@MainActor
enum SelfReplacementController {
    static func returnToHomeScreen() {
        #if !targetEnvironment(simulator)
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else { return }
        _ = UIApplication.shared.perform(selector)
        #endif
    }
}
