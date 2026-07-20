import Foundation

@MainActor
final class NotificationPreferences {
    private enum Key {
        static let enabled = "notifications.expiry.enabled"
        static let leadHours = "notifications.expiry.leadHours"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var leadHours: Int {
        get {
            let value = defaults.integer(forKey: Key.leadHours)
            return value > 0 ? value : 24
        }
        set { defaults.set(max(1, newValue), forKey: Key.leadHours) }
    }
}
