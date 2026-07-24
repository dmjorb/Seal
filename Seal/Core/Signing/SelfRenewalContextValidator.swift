import Foundation

enum SelfRenewalContextValidator {
    static func validate(
        currentBundleIdentifier: String,
        targetBundleIdentifier: String,
        currentSigningTeamIdentifier: String?,
        selectedAccount: AppleAccountRecord,
        boundAccountID: UUID?,
        selectedAccountID: UUID
    ) throws {
        guard currentBundleIdentifier.caseInsensitiveCompare(targetBundleIdentifier) == .orderedSame else {
            throw ImportFailure(
                title: "Seal 身份不匹配",
                reason: "Seal 自续签必须继续使用当前安装的 Bundle ID。",
                recovery: "恢复当前 Bundle ID",
                code: "SEAL-SELF-102"
            )
        }

        if let currentSigningTeamIdentifier,
           currentSigningTeamIdentifier.isEmpty == false,
           currentSigningTeamIdentifier.caseInsensitiveCompare(selectedAccount.teamID) != .orderedSame {
            throw ImportFailure(
                title: "Team 不匹配",
                reason: "当前 Seal 与所选 Apple ID 不属于同一个 Team。",
                recovery: "选择 Team",
                code: "SEAL-SELF-103"
            )
        }

        // A stale local account record ID is allowed when the installed profile's
        // Team still matches. Team identity is authoritative for self-renewal.
        _ = boundAccountID
        _ = selectedAccountID
    }
}
