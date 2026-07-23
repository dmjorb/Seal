import Foundation

enum SigningCertificateSelectionPolicy {
    static func validateAccountAndTeam(
        for app: AppRecord,
        account: AppleAccountRecord
    ) throws {
        guard app.state == .installed || app.isSeal else { return }
        guard let boundAccountID = app.accountID else {
            throw ImportFailure(
                title: "续签记录不完整",
                reason: "未记录上次签名此 App 的 Apple ID。",
                recovery: "重新导入 IPA 签名并安装",
                code: "SEAL-AUTH-110"
            )
        }
        guard boundAccountID == account.id else {
            throw ImportFailure(
                title: "Apple ID 不匹配",
                reason: "续签必须使用上次签名此 App 的 Apple ID。",
                recovery: "切换回原 Apple ID",
                code: "SEAL-AUTH-111"
            )
        }
        guard let teamID = normalized(app.signingTeamID) else {
            throw ImportFailure(
                title: "续签记录不完整",
                reason: "未记录上次签名此 App 的 Team。",
                recovery: "重新导入 IPA 签名并安装",
                code: "SEAL-AUTH-113"
            )
        }
        guard teamID.caseInsensitiveCompare(account.teamID) == .orderedSame else {
            throw ImportFailure(
                title: "Team 不匹配",
                reason: "续签必须使用上次签名此 App 的 Team。",
                recovery: "选择 Team",
                code: "SEAL-AUTH-112"
            )
        }
    }

    static func resolvedSerialNumber(
        for app: AppRecord,
        account: AppleAccountRecord,
        requestedSerialNumber: String? = nil
    ) throws -> String? {
        try validateAccountAndTeam(for: app, account: account)
        let local = normalized(account.certificateSerialNumber)
        if let requested = normalized(requestedSerialNumber),
           let local,
           requested.caseInsensitiveCompare(local) == .orderedSame {
            return local
        }
        if let selected = normalized(account.selectedCertificateSerialNumber),
           let local,
           selected.caseInsensitiveCompare(local) == .orderedSame {
            return local
        }
        return local
    }

    static func localAvailabilityMessage(
        for app: AppRecord,
        account: AppleAccountRecord
    ) -> String? {
        do {
            try validateAccountAndTeam(for: app, account: account)
        } catch let failure as ImportFailure {
            return failure.reason
        } catch {
            return "续签账号不可用"
        }
        guard let selected = normalized(account.selectedCertificateSerialNumber) else { return nil }
        guard let local = normalized(account.certificateSerialNumber),
              selected.caseInsensitiveCompare(local) == .orderedSame else {
            return "本机没有所选证书对应的私钥，将在签名时自动处理证书。"
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
