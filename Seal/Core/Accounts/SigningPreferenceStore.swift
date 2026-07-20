import Foundation

actor SigningPreferenceStore {
    private enum Key {
        static let activeAccountID = "signing.activeAccountID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activeAccountID() -> UUID? {
        guard let value = defaults.string(forKey: Key.activeAccountID) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    func setActiveAccountID(_ accountID: UUID?) {
        if let accountID {
            defaults.set(accountID.uuidString, forKey: Key.activeAccountID)
        } else {
            defaults.removeObject(forKey: Key.activeAccountID)
        }
    }
}
