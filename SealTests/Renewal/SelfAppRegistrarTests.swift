import Foundation
import Testing
@testable import Seal

struct SelfAppRegistrarTests {
    @Test
    func preservesTheFirstOriginalBundleIdentifierAcrossSelfUpdates() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal.apps.renewed",
                declaredOriginalBundleIdentifier: "com.mjorb.seal",
                existingOriginalBundleIdentifier: "com.mjorb.seal"
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func usesEmbeddedOriginalBundleIdentifierAfterTheAppContainerChanges() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal.apps.renewed",
                declaredOriginalBundleIdentifier: "com.mjorb.seal",
                existingOriginalBundleIdentifier: nil
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func usesTheCurrentIdentifierOnlyForFirstRegistration() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal",
                declaredOriginalBundleIdentifier: nil,
                existingOriginalBundleIdentifier: nil
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func matchesTheInstalledProfileTeamToTheStoredAccount() {
        let expectedID = UUID()
        let accounts = [
            AppleAccountRecord(
                maskedEmail: "other@icloud.com",
                accountIdentifier: "other",
                teamID: "OTHERTEAM",
                teamName: "Other",
                lastVerifiedAt: .distantPast
            ),
            AppleAccountRecord(
                id: expectedID,
                maskedEmail: "sunuannian1@gmail.com",
                accountIdentifier: "current",
                teamID: "T3432ZHJUF9",
                teamName: "Current",
                lastVerifiedAt: .now
            )
        ]

        #expect(
            SelfAppAccountBinding.matchedAccountID(
                teamIdentifier: "t3432zhjuf9",
                accounts: accounts
            ) == expectedID
        )
    }

    @Test
    func profileTeamWithoutSavedMatchDoesNotReuseStaleAccount() {
        let staleAccountID = UUID()

        #expect(
            SelfAppAccountBinding.resolvedAccountID(
                teamIdentifier: "CURRENTTEAM",
                accounts: [],
                fallbackAccountID: staleAccountID
            ) == nil
        )
    }

    @Test
    func missingProfileTeamFallsBackToStoredAccount() {
        let storedAccountID = UUID()

        #expect(
            SelfAppAccountBinding.resolvedAccountID(
                teamIdentifier: nil,
                accounts: [],
                fallbackAccountID: storedAccountID
            ) == storedAccountID
        )
    }

    @Test
    func doesNotReuseAnUnrelatedLegacySealRecord() {
        let stale = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.dmj",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/stale.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.dmj",
            isSeal: true,
            importedAt: .distantPast
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [stale],
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9"
            ) == nil
        )
    }

    @Test
    func originalIdentifierDoesNotOverrideAStaleInstalledIdentifier() {
        let stale = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.dmj",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/stale.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.dmj",
            isSeal: true,
            importedAt: .distantPast
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [stale],
                currentBundleIdentifier: "com.mjorb.seal"
            ) == nil
        )
    }

    @Test
    func reusesTheRecordThatMatchesTheCurrentInstalledBundleIdentifier() {
        let matching = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/current.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            isSeal: true,
            importedAt: .now
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [matching],
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9"
            )?.id == matching.id
        )
    }
}
