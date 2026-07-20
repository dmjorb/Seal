import Foundation

enum SigningCertificateSelectionPolicy {
    static func resolvedSerialNumber(
        for app: AppRecord,
        account: AppleAccountRecord,
        requestedSerialNumber: String? = nil
    ) throws -> String? {
        let lockedSerialNumber = app.state == .installed
            ? app.certificateSerialNumber
            : nil

        if let lockedSerialNumber,
           let requestedSerialNumber,
           lockedSerialNumber != requestedSerialNumber {
            throw ImportFailure(
                title: "续签证书不匹配",
                reason: "当前应用必须沿用上次实际签名证书。",
                recovery: "恢复原证书，或重新导入 IPA 作为新应用签名",
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
        } catch {
            return "续签证书与当前选择不一致。"
        }
        guard let serialNumber else { return nil }
        guard account.certificateSerialNumber == serialNumber else {
            return app.state == .installed
                ? "续签必须使用上次签名证书，但 Seal 本地已没有对应私钥。"
                : "当前选择的签名证书没有可用的本地私钥。"
        }
        return nil
    }
}
