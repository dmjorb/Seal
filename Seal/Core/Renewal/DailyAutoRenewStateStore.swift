import Foundation

@MainActor
final class DailyAutoRenewStateStore {
    private enum Key {
        static let lastAutoRenewDate = "lastAutoRenewDate"
        static let pendingSelfRenewDate = "autoRenew.pendingSelfRenewDate"
        static let pendingSelfPreviousExpiry = "autoRenew.pendingSelfPreviousExpiry"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func shouldRun(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        defaults.string(forKey: Key.lastAutoRenewDate) != dayKey(for: date, calendar: calendar)
    }

    func markCompleted(dayKey: String) {
        defaults.set(dayKey, forKey: Key.lastAutoRenewDate)
        clearPendingSelfRenewal()
    }

    func markPendingSelfRenewal(dayKey: String, previousExpiry: Date?) {
        defaults.set(dayKey, forKey: Key.pendingSelfRenewDate)
        if let previousExpiry {
            defaults.set(previousExpiry.timeIntervalSince1970, forKey: Key.pendingSelfPreviousExpiry)
        } else {
            defaults.removeObject(forKey: Key.pendingSelfPreviousExpiry)
        }
    }

    func reconcilePendingSelfRenewal(currentExpiry: Date?) {
        guard let pendingDay = defaults.string(forKey: Key.pendingSelfRenewDate) else { return }
        let oldTimestamp = defaults.double(forKey: Key.pendingSelfPreviousExpiry)
        let oldExpiry = oldTimestamp > 0 ? Date(timeIntervalSince1970: oldTimestamp) : nil
        guard let currentExpiry else { return }
        if let oldExpiry, currentExpiry <= oldExpiry { return }
        markCompleted(dayKey: pendingDay)
    }

    private func clearPendingSelfRenewal() {
        defaults.removeObject(forKey: Key.pendingSelfRenewDate)
        defaults.removeObject(forKey: Key.pendingSelfPreviousExpiry)
    }
}
