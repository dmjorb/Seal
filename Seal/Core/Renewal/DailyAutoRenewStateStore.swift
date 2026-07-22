import Foundation

struct DailyAutoRenewSelfReconciliation: Equatable, Sendable {
    enum Evidence: Equatable, Sendable {
        case embeddedExpiryAdvanced
        case provisioningExpiryAdvanced
        case signedAfterPending
        case installedAfterPending
    }

    let dayKey: String
    let appID: UUID
    let evidence: Evidence
}

@MainActor
final class DailyAutoRenewStateStore {
    private enum Key {
        static let lastAutoRenewDate = "lastAutoRenewDate"
        static let pendingSelfRenewDate = "autoRenew.pendingSelfRenewDate"
        static let pendingSelfAppID = "autoRenew.pendingSelfAppID"
        static let pendingSelfPreviousExpiry = "autoRenew.pendingSelfPreviousExpiry"
        static let pendingSelfPreviousProvisioningExpiry = "autoRenew.pendingSelfPreviousProvisioningExpiry"
        static let pendingSelfPreviousLastSignedAt = "autoRenew.pendingSelfPreviousLastSignedAt"
        static let pendingSelfPreviousLastInstalledAt = "autoRenew.pendingSelfPreviousLastInstalledAt"
        static let pendingSelfStartedAt = "autoRenew.pendingSelfStartedAt"
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

    func markPendingSelfRenewal(
        dayKey: String,
        appID: UUID,
        previousExpiry: Date?,
        previousProvisioningExpiry: Date? = nil,
        previousLastSignedAt: Date? = nil,
        previousLastInstalledAt: Date? = nil,
        pendingAt: Date = Date()
    ) {
        defaults.set(dayKey, forKey: Key.pendingSelfRenewDate)
        defaults.set(appID.uuidString, forKey: Key.pendingSelfAppID)
        set(previousExpiry, forKey: Key.pendingSelfPreviousExpiry)
        set(previousProvisioningExpiry, forKey: Key.pendingSelfPreviousProvisioningExpiry)
        set(previousLastSignedAt, forKey: Key.pendingSelfPreviousLastSignedAt)
        set(previousLastInstalledAt, forKey: Key.pendingSelfPreviousLastInstalledAt)
        set(pendingAt, forKey: Key.pendingSelfStartedAt)
    }

    func reconcilePendingSelfRenewal(
        currentExpiry: Date?,
        currentProvisioningExpiry: Date? = nil,
        currentLastSignedAt: Date? = nil,
        currentLastInstalledAt: Date? = nil
    ) -> DailyAutoRenewSelfReconciliation? {
        guard let pendingDay = defaults.string(forKey: Key.pendingSelfRenewDate) else { return nil }
        guard let appIDValue = defaults.string(forKey: Key.pendingSelfAppID),
              let appID = UUID(uuidString: appIDValue) else { return nil }
        let previousExpiry = date(forKey: Key.pendingSelfPreviousExpiry)
        let pendingAt = date(forKey: Key.pendingSelfStartedAt)

        // `lastSignedAt`, `lastInstalledAt`, and the stored provisioning expiry
        // are written before iOS replaces the running Seal. They prove that a
        // package was prepared, not that installation succeeded. The only
        // trustworthy cross-launch evidence is the expiration date read from
        // the embedded profile of the Seal process that is running now.
        guard confirmsInstalledReplacement(
            currentExpiry: currentExpiry,
            previousExpiry: previousExpiry,
            signedProfileExpiry: currentProvisioningExpiry,
            pendingAt: pendingAt
        ) else { return nil }
        let evidence: DailyAutoRenewSelfReconciliation.Evidence = .embeddedExpiryAdvanced
        clearPendingSelfRenewal()
        return DailyAutoRenewSelfReconciliation(
            dayKey: pendingDay,
            appID: appID,
            evidence: evidence
        )
    }

    private func confirmsInstalledReplacement(
        currentExpiry: Date?,
        previousExpiry: Date?,
        signedProfileExpiry: Date?,
        pendingAt: Date?
    ) -> Bool {
        guard let currentExpiry else { return false }
        if let previousExpiry {
            return currentExpiry > previousExpiry
        }

        // Legacy/self records may not have captured the previous embedded
        // expiry. In that case require the currently embedded expiry to match
        // the newly signed profile stored before replacement, and to be newer
        // than the installation attempt itself.
        guard let signedProfileExpiry, let pendingAt else { return false }
        return abs(currentExpiry.timeIntervalSince(signedProfileExpiry)) < 1
            && currentExpiry > pendingAt
    }

    private func date(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    private func set(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func clearPendingSelfRenewal() {
        defaults.removeObject(forKey: Key.pendingSelfRenewDate)
        defaults.removeObject(forKey: Key.pendingSelfAppID)
        defaults.removeObject(forKey: Key.pendingSelfPreviousExpiry)
        defaults.removeObject(forKey: Key.pendingSelfPreviousProvisioningExpiry)
        defaults.removeObject(forKey: Key.pendingSelfPreviousLastSignedAt)
        defaults.removeObject(forKey: Key.pendingSelfPreviousLastInstalledAt)
        defaults.removeObject(forKey: Key.pendingSelfStartedAt)
    }
}
