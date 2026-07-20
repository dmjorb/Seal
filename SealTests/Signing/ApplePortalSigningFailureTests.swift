import Foundation
import Testing
@testable import Seal

struct ApplePortalSigningFailureTests {
    @Test
    func identifiesAppIDFailuresInsteadOfCollapsingThemIntoGenericSigningFailure() {
        let failure = ApplePortalSigningFailure.make(
            stage: .appID,
            error: NSError(
                domain: "ApplePortal",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Bundle identifier is unavailable."]
            )
        )

        #expect(failure.code == "SEAL-APPID-302")
        #expect(failure.reason.contains("App ID"))
        #expect(failure.reason.contains("ApplePortal 409"))
    }

    @Test
    func matchesExistingBundleIdentifiersWithoutCaseSensitivity() {
        #expect(
            ApplePortalAppIDResolver.matches(
                existingBundleIdentifier: "com.Example.Demo",
                requestedBundleIdentifier: "com.example.demo"
            )
        )
    }

    @Test
    func requiresExplicitConfirmationBeforeReplacingASideStoreCertificate() {
        #expect(
            CertificateReplacementPolicy.requiresConfirmation(
                machineNames: ["SideStore - Alex's iPhone"]
            )
        )
        #expect(
            CertificateReplacementPolicy.requiresConfirmation(
                machineNames: ["Seal Alex's iPhone"]
            ) == false
        )
    }

    @Test
    func preservesUnderlyingPortalFailureForDiagnosis() {
        let failure = ApplePortalSigningFailure.make(
            stage: .provisioningProfile,
            error: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
            )
        )

        #expect(failure.code == "SEAL-PROFILE-303")
        #expect(failure.reason.contains("描述文件"))
        #expect(failure.reason.contains("NSURLErrorDomain -1001"))
    }
}
