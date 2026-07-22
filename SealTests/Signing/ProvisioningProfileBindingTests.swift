import Foundation
import Testing
@testable import Seal

struct ProvisioningProfileBindingTests {
    @Test
    func acceptsExactTeamBundleCertificateAndDeviceBinding() throws {
        let binding = makeBinding()
        let result = try binding.validated(
            expectedTeamID: "TEAM123",
            expectedBundleID: "com.example.app",
            expectedCertificateSerialNumber: "A1B2C3",
            expectedDeviceIdentifier: "UDID-123",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(result == binding)
    }

    @Test
    func rejectsCertificateMismatchWithoutSilentReplacement() {
        let binding = makeBinding()
        #expect(throws: ImportFailure.self) {
            _ = try binding.validated(
                expectedTeamID: "TEAM123",
                expectedBundleID: "com.example.app",
                expectedCertificateSerialNumber: "DIFFERENT",
                expectedDeviceIdentifier: "UDID-123",
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
    }

    @Test
    func rejectsUnsupportedEntitlementInsteadOfSilentlyDroppingIt() {
        #expect(throws: ImportFailure.self) {
            try ProvisioningProfileBinding.validateEntitlements(
                requestedKeys: ["aps-environment", "com.apple.developer.associated-domains"],
                profileKeys: ["aps-environment"],
                bundleIdentifier: "com.example.app"
            )
        }
    }

    @Test
    func appGroupsMustBeAuthorizedByProfile() {
        #expect(throws: ImportFailure.self) {
            try ProvisioningProfileBinding.validateEntitlements(
                requestedKeys: ["com.apple.security.application-groups"],
                profileKeys: [],
                bundleIdentifier: "com.example.app"
            )
        }
    }


    @Test
    func rejectsEntitlementValueMismatch() {
        #expect(throws: ImportFailure.self) {
            try ProvisioningProfileBinding.validateEntitlements(
                requested: ["aps-environment": .string("production")],
                profile: ["aps-environment": .string("development")],
                bundleIdentifier: "com.example.app"
            )
        }
    }

    @Test
    func acceptsProfileWildcardAndArraySubset() throws {
        try ProvisioningProfileBinding.validateEntitlements(
            requested: [
                "com.apple.developer.associated-domains": .array([
                    .string("applinks:example.com")
                ]),
                "custom.identifier": .string("TEAM123.com.example.app")
            ],
            profile: [
                "com.apple.developer.associated-domains": .array([
                    .string("applinks:example.com"),
                    .string("webcredentials:example.com")
                ]),
                "custom.identifier": .string("TEAM123.*")
            ],
            bundleIdentifier: "com.example.app"
        )
    }

    private func makeBinding() -> ProvisioningProfileBinding {
        ProvisioningProfileBinding(
            bundleIdentifier: "com.example.app",
            profileUUID: "PROFILE-UUID",
            profileName: "Profile",
            teamIdentifier: "TEAM123",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
            certificateSerialNumbers: ["A1B2C3"],
            deviceIdentifiers: ["UDID-123"],
            entitlements: [
                "application-identifier": .string("TEAM123.com.example.app"),
                "aps-environment": .string("development")
            ]
        )
    }
}
