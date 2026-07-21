import Foundation

enum SelfRenewalContextValidator {
    /// Seal self-signing follows the same public Apple / iOS path as any imported IPA.
    /// The validator is intentionally a no-op so the current installed Seal bundle,
    /// Team, Apple ID, or previously used certificate never lock a future signing flow.
    static func validate(
        currentBundleIdentifier: String,
        targetBundleIdentifier: String,
        currentSigningTeamIdentifier: String?,
        selectedAccount: AppleAccountRecord,
        boundAccountID: UUID?,
        selectedAccountID: UUID
    ) throws {
        return
    }
}
