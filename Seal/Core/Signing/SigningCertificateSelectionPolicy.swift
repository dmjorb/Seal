import Foundation

enum SigningCertificateSelectionPolicy {
    static func validateAccountAndTeam(
        for app: AppRecord,
        account: AppleAccountRecord
    ) throws {
        guard app.requiresLockedSigningIdentity else { return }

        if let accountID = app.accountID, accountID != account.id {
            throw ImportFailure(
                title: "续签账号不匹配",
                reason: "此应用绑定的 Apple ID 记录是 \(accountID.uuidString)，当前选择的是 \(account.id.uuidString)。Seal 没有静默切换账号。",
                recovery: "重新添加或选择首次签名使用的 Apple ID",
                code: "SEAL-AUTH-111"
            )
        }

        if let signingTeamID = app.signingTeamID,
           signingTeamID.caseInsensitiveCompare(account.teamID) != .orderedSame {
            throw ImportFailure(
                title: "续签 Team 不匹配",
                reason: "此应用首次签名使用 Team \(signingTeamID)，当前 Apple ID 属于 Team \(account.teamID)。Seal 没有静默切换 Team。",
                recovery: "选择首次签名使用的 Apple ID / Team",
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

        let lockedSerialNumber = app.requiresLockedSigningIdentity
            ? app.certificateSerialNumber
            : nil

        if let lockedSerialNumber,
           let requestedSerialNumber,
           lockedSerialNumber.caseInsensitiveCompare(requestedSerialNumber) != .orderedSame {
            throw ImportFailure(
                title: "续签证书不匹配",
                reason: "此应用首次签名使用证书 Serial：\(lockedSerialNumber)。当前选择的是：\(requestedSerialNumber)。Seal 没有静默更换证书。",
                recovery: "恢复原证书，或在证书页面明确执行证书迁移",
                code: "SEAL-CERT-208"
            )
        }

        return lockedSerialNumber
            ?? requestedSerialNumber
            ?? account.selectedCertificateSerialNumber
            ?? account.certificateSerialNumber
    }

    static func localAvailabilityMessage(
        for app: AppRecord,
        account: AppleAccountRecord
    ) -> String? {
        let serialNumber: String?
        do {
            serialNumber = try resolvedSerialNumber(
                for: app,
                account: account
            )
        } catch let failure as ImportFailure {
            return failure.reason
        } catch {
            return "续签签名身份不一致。"
        }
        guard let serialNumber else { return nil }
        guard account.certificateSerialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame else {
            return app.requiresLockedSigningIdentity
                ? "该签名产物必须使用原证书 Serial：\(serialNumber)，但 Seal 本地没有对应私钥。"
                : "当前选择的证书 Serial：\(serialNumber) 没有可用的本地私钥。"
        }
        return nil
    }
}
