import Foundation

enum SelfRenewalTracker {
    private static let pendingBundleKey = "selfRenewal.pendingBundleIdentifier"
    private static let pendingVersionKey = "selfRenewal.pendingVersion"
    private static let pendingStartedAtKey = "selfRenewal.pendingStartedAt"
    private static let completedAtKey = "selfRenewal.completedAt"

    static func markPending(bundleIdentifier: String, version: String) {
        let defaults = UserDefaults.standard
        defaults.set(bundleIdentifier, forKey: pendingBundleKey)
        defaults.set(version, forKey: pendingVersionKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingStartedAtKey)
    }

    static func markCompletedIfMatches(
        bundleIdentifier: String,
        version: String
    ) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: pendingBundleKey) == bundleIdentifier else { return }
        defaults.removeObject(forKey: pendingBundleKey)
        defaults.removeObject(forKey: pendingVersionKey)
        defaults.removeObject(forKey: pendingStartedAtKey)
        defaults.set(Date().timeIntervalSince1970, forKey: completedAtKey)
    }

    static var pendingBundleIdentifier: String? {
        UserDefaults.standard.string(forKey: pendingBundleKey)
    }
}
