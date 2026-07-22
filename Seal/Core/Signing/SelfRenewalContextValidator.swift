import Foundation

enum SelfRenewalContextValidator {
    /// Verifies Seal self-renewal against the identity of the Seal process that
    /// is currently running. This is an additional defense on top of the
    /// persisted app/account binding used for every installed app renewal.
    static func validate(
        currentBundleIdentifier: String,
        targetBundleIdentifier: String,
        currentSigningTeamIdentifier: String?,
        selectedAccount: AppleAccountRecord,
        boundAccountID: UUID?,
        selectedAccountID: UUID
    ) throws {
        guard currentBundleIdentifier.caseInsensitiveCompare(targetBundleIdentifier)
                == .orderedSame else {
            throw failure(
                title: "Seal Bundle ID 不匹配",
                reason: "Seal 自续签必须覆盖当前已安装的 Bundle ID。",
                recovery: "恢复当前 Seal 的签名记录",
                code: "SEAL-BUNDLE-003"
            )
        }
        guard let boundAccountID else {
            throw failure(
                title: "Seal 续签记录不完整",
                reason: "未记录上次签名 Seal 的 Apple ID。",
                recovery: "重新安装并绑定当前 Seal",
                code: "SEAL-AUTH-110"
            )
        }
        guard boundAccountID == selectedAccountID,
              selectedAccount.id == selectedAccountID else {
            throw failure(
                title: "Apple ID 不匹配",
                reason: "Seal 自续签必须使用上次签名当前 Seal 的 Apple ID。",
                recovery: "切换回原 Apple ID",
                code: "SEAL-AUTH-111"
            )
        }
        if let currentSigningTeamIdentifier = normalized(currentSigningTeamIdentifier) {
            guard currentSigningTeamIdentifier.caseInsensitiveCompare(selectedAccount.teamID)
                    == .orderedSame else {
                throw failure(
                    title: "Team 不匹配",
                    reason: "当前运行的 Seal 与所选 Apple ID 不属于同一个 Team。",
                    recovery: "重新验证原 Apple ID",
                    code: "SEAL-AUTH-112"
                )
            }
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func failure(
        title: String,
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(title: title, reason: reason, recovery: recovery, code: code)
    }
}
