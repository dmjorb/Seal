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
            mappedMainBundleID: first
        )
        let appGroup = mapper.appGroupID(
            original: "group.com.example.demo",
            teamID: "TEAM1"
        )

        #expect(first == "com.example.demo.seal")
        #expect(first == repeated)
        #expect(appExtension.hasPrefix("\(first).e"))
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
    func policyAllowsRequestedBundleIdentifierForRenewal() throws {
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
            ) == "com.example.demo.other"
        )
    }

    @Test
    func policyAllowsRequestedBundleIdentifierForSealPackage() throws {
        let seal = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: nil,
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
            ) == "com.mjorb.seal.seal"
        )
    }
}
