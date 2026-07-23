import Foundation
import Testing
@testable import Seal

struct BundleIDMapperTests {
    @Test
    func defaultMainBundleIdentifierUsesReadableSealSuffix() {
        let mapper = BundleIDMapper()
        let first = mapper.mainBundleID(original: "com.example.demo", teamID: "TEAM1")
        let repeated = mapper.mainBundleID(original: "com.example.demo", teamID: "TEAM2")
        let appExtension = mapper.extensionBundleID(
            original: "com.example.demo.share",
            originalMainBundleID: "com.example.demo",
            mappedMainBundleID: first
        )
        let appGroup = mapper.appGroupID(
            original: "group.com.example.demo",
            teamID: "TEAM1"
        )

        #expect(first == "com.example.demo.seal")
        #expect(first == repeated)
        #expect(appExtension == "com.example.demo.seal.share")
        #expect(appGroup.hasPrefix("group.com.mjorb.seal.groups."))
        #expect(appGroup == mapper.appGroupID(
            original: "group.com.example.demo",
            teamID: "TEAM1"
        ))
    }

    @Test
    func requestedMainBundleIdentifierWins() {
        let mapper = BundleIDMapper()
        #expect(
            mapper.mainBundleID(
                original: "com.example.demo",
                teamID: "TEAM1",
                requested: "com.example.demo.custom"
            ) == "com.example.demo.custom"
        )
    }

    @Test
    func policyIgnoresRequestedBundleIdentifierForRenewal() throws {
        let installed = AppRecord(
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: "com.example.demo.seal",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            ipaRelativePath: "Apps/demo.ipa",
            importedAt: Date()
        )

        #expect(
            try BundleIDPolicy.targetBundleIdentifier(
                for: installed,
                requestedBundleIdentifier: "com.example.demo.other"
            ) == "com.example.demo.seal"
        )
    }

    @Test
    func policyUsesMappedBundleIdentifierForInstalledRenewal() throws {
        var installed = AppRecord(
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: "com.example.demo.seal",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            ipaRelativePath: "Apps/demo.ipa",
            importedAt: Date()
        )
        installed.preferredBundleIdentifier = "com.example.demo.old"

        #expect(try BundleIDPolicy.targetBundleIdentifier(for: installed) == "com.example.demo.seal")
    }

    @Test
    func policyRejectsInstalledRenewalWithoutSignedBundleIdentifier() throws {
        let installed = AppRecord(
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: nil,
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            ipaRelativePath: "Apps/demo.ipa",
            importedAt: Date()
        )

        #expect(throws: ImportFailure.self) {
            try BundleIDPolicy.targetBundleIdentifier(for: installed)
        }
    }

    @Test
    func policyIgnoresRequestedBundleIdentifierForSealPackage() throws {
        let seal = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.current",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            ipaRelativePath: "Apps/seal.ipa",
            isSeal: true,
            importedAt: Date()
        )

        #expect(
            try BundleIDPolicy.targetBundleIdentifier(
                for: seal,
                requestedBundleIdentifier: "com.mjorb.seal.seal",
                currentSealBundleIdentifier: "com.mjorb.seal"
            ) == "com.mjorb.seal.current"
        )
    }

    @Test
    func recommendedBundleIdentifierDoesNotDoubleAppendSealCaseInsensitively() {
        #expect(BundleIDPolicy.recommendedBundleIdentifier(for: "com.example.demo") == "com.example.demo.seal")
        #expect(BundleIDPolicy.recommendedBundleIdentifier(for: "com.example.demo.seal") == "com.example.demo.seal")
        #expect(BundleIDPolicy.recommendedBundleIdentifier(for: "com.example.demo.SEAL") == "com.example.demo.SEAL")
    }

    @Test
    func extensionMappingPreservesRelativeSuffix() {
        let mapper = BundleIDMapper()
        #expect(
            mapper.extensionBundleID(
                original: "com.example.app.widget",
                originalMainBundleID: "com.example.app",
                mappedMainBundleID: "com.example.app.seal"
            ) == "com.example.app.seal.widget"
        )
        #expect(
            mapper.extensionBundleID(
                original: "com.example.app.share",
                originalMainBundleID: "com.example.app",
                mappedMainBundleID: "com.example.custom"
            ) == "com.example.custom.share"
        )
    }

    @Test
    func bundleIdentifierValidationCoversFinalRules() {
        #expect(BundleIDPolicy.validationError(for: "") != nil)
        #expect(BundleIDPolicy.validationError(for: "single") != nil)
        #expect(BundleIDPolicy.validationError(for: ".com.example") != nil)
        #expect(BundleIDPolicy.validationError(for: "com..example") != nil)
        #expect(BundleIDPolicy.validationError(for: "com.-example") != nil)
        #expect(BundleIDPolicy.validationError(for: "com.example-") != nil)
        #expect(BundleIDPolicy.validationError(for: "com.example_app") != nil)
        #expect(BundleIDPolicy.validationError(for: "com.example-app") == nil)
    }

}
