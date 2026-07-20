import Foundation

enum SigningCertificateSelectionPolicy {
    static func validateAccountAndTeam(
        for app: AppRecord,
        account: AppleAccountRecord
    ) throws {
        // Do not block signing by Seal-owned account/team history.
        // Apple portal and iOS installation perform the authoritative validation.
    }

    static func resolvedSerialNumber(
        for app: AppRecord,
        account: AppleAccountRecord,
        requestedSerialNumber: String? = nil
    ) throws -> String? {
        requestedSerialNumber
            ?? account.selectedCertificateSerialNumber
            ?? account.certificateSerialNumber
    }

    static func localAvailabilityMessage(
        for app: AppRecord,
        account: AppleAccountRecord
    ) -> String? {
        guard let serialNumber = try? resolvedSerialNumber(for: app, account: account),
              serialNumber.isEmpty == false else {
            return nil
        }

        guard account.certificateSerialNumber?.caseInsensitiveCompare(serialNumber) == .orderedSame else {
            return "当前签名证书没有可用的本机私钥。"
        }
        return nil
    }
}
