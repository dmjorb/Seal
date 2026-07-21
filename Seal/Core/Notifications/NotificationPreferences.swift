import Foundation

@MainActor
final class NotificationPreferences {
    private enum Key {
        static let enabled = "notifications.expiry.enabled"
        static let leadHours = "notifications.expiry.leadHours"
    }

    static let fixedLeadHours = 24
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.set(Self.fixedLeadHours, forKey: Key.leadHours)
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var leadHours: Int {
        get { Self.fixedLeadHours }
        set { defaults.set(Self.fixedLeadHours, forKey: Key.leadHours) }
    }
}
