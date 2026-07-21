import Foundation

enum SigningCertificateSelectionPolicy {
    static func validateAccountAndTeam(
        for app: AppRecord,
        account: AppleAccountRecord
    ) throws {
        // No Seal-side Apple ID / Team / certificate lock.
        // Apple portal and iOS installation are the authoritative validators.
    }

    static func resolvedSerialNumber(
        for app: AppRecord,
        account: AppleAccountRecord,
        requestedSerialNumber: String? = nil
    ) throws -> String? {
        let requested = requestedSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requested, requested.isEmpty == false { return requested }
        let selected = account.selectedCertificateSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, selected.isEmpty == false { return selected }
        let cached = account.certificateSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cached?.isEmpty == false ? cached : nil
    }

    static func localAvailabilityMessage(
        for app: AppRecord,
        account: AppleAccountRecord
    ) -> String? {
        nil
    }
}
