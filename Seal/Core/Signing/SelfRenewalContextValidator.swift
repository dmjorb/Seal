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
            throw failure(
                reason: "当前操作会改变 Seal 的 Bundle ID。改变 Bundle ID 属于安装新的 Seal，不是续签当前 Seal。当前安装 Bundle ID 是 \(currentBundleIdentifier)，目标 Bundle ID 是 \(targetBundleIdentifier)。",
                recovery: "重新导入 IPA 并作为新应用签名",
                code: "SEAL-SELF-102"
            )
        }

        if let currentSigningTeamIdentifier = currentSigningTeamIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           currentSigningTeamIdentifier.isEmpty == false {
            guard currentSigningTeamIdentifier.caseInsensitiveCompare(selectedAccount.teamID) == .orderedSame else {
                throw failure(
                    reason: "当前 Seal 是 Team \(currentSigningTeamIdentifier) 签出的，所选 Apple ID 属于 Team \(selectedAccount.teamID)。Seal 自续签必须使用签出当前安装版本的 Apple ID / Team。",
                    recovery: "切换到签出当前 Seal 的 Apple ID",
                    code: "SEAL-SELF-103"
                )
            }
            return
        }

        if let boundAccountID, boundAccountID != selectedAccountID {
            throw failure(
                reason: "无法从当前安装描述文件读取 Team，且本地记录绑定了另一 Apple ID。当前 Seal 的 Bundle ID 是 \(currentBundleIdentifier)。",
                recovery: "重新添加签出当前 Seal 的 Apple ID 后重试",
                code: "SEAL-SELF-103"
            )
        }
    }

    private static func failure(
        reason: String,
        recovery: String,
        code: String
    ) -> ImportFailure {
        ImportFailure(
            title: "无法完成签名",
            reason: reason,
            recovery: recovery,
            code: code
        )
    }
}
