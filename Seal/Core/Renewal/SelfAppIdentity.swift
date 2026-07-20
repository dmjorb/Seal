import Foundation

enum SelfAppBundleIdentity {
    static func originalBundleIdentifier(
        currentBundleIdentifier: String,
        declaredOriginalBundleIdentifier: String?,
        existingOriginalBundleIdentifier: String?
    ) -> String {
        existingOriginalBundleIdentifier
            ?? declaredOriginalBundleIdentifier
            ?? currentBundleIdentifier
    }
}

enum SelfAppAccountBinding {
    static func matchedAccountID(
        teamIdentifier: String?,
        accounts: [AppleAccountRecord]
    ) -> UUID? {
        guard let teamIdentifier = normalizedTeamIdentifier(teamIdentifier) else {
            return nil
        }
        return accounts.first { account in
            account.teamID.caseInsensitiveCompare(teamIdentifier) == .orderedSame
        }?.id
    }

    static func resolvedAccountID(
        teamIdentifier: String?,
        accounts: [AppleAccountRecord],
        fallbackAccountID: UUID?
    ) -> UUID? {
        guard normalizedTeamIdentifier(teamIdentifier) != nil else {
            return fallbackAccountID
        }
        return matchedAccountID(
            teamIdentifier: teamIdentifier,
            accounts: accounts
        )
    }

    private static func normalizedTeamIdentifier(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              normalized.isEmpty == false else {
            return nil
        }
        return normalized
    }
}

enum SelfAppRecordSelection {
    static func preferredExistingSealRecord(
        in records: [AppRecord],
        currentBundleIdentifier: String
    ) -> AppRecord? {
        records.first { record in
            record.isSeal && matchesSealBundleIdentifier(
                currentBundleIdentifier,
                record: record
            )
        }
    }

    private static func matchesSealBundleIdentifier(
        _ bundleIdentifier: String,
        record: AppRecord
    ) -> Bool {
        let installedIdentifiers = [
            record.mappedBundleIdentifier,
            record.preferredBundleIdentifier
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.isEmpty == false }

        if installedIdentifiers.isEmpty == false {
            return installedIdentifiers.contains { identifier in
                bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
            }
        }

        return bundleIdentifier.caseInsensitiveCompare(record.originalBundleIdentifier) == .orderedSame
    }
}
