import Foundation

enum AccountAvailabilityPolicy {
    static func isSelectable(_ account: AppleAccountRecord) -> Bool {
        account.status != .needsVerification
    }

    static func repairedStatus(
        for account: AppleAccountRecord,
        hasLocalSecret: Bool
    ) -> AccountStatus {
        guard account.status == .needsVerification,
              account.verificationFailureReason == nil,
              hasLocalSecret else {
            return account.status
        }
        // Older Seal builds persisted transient network failures as
        // `needsVerification`. Keep the account locally selectable without
        // pretending that a fresh Apple Portal verification has succeeded.
        return .availableOffline
    }
}
