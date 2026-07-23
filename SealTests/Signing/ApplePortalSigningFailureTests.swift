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
        #expect(failure.reason.contains("ApplePortal 409") == false)
        #expect(failure.reason.contains("Bundle identifier is unavailable") == false)
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
    func certificateLimitFailureDoesNotAuthorizeAutomaticRevocation() {
        let failure = ApplePortalSigningFailure.make(
            stage: .certificate,
            error: NSError(
                domain: "ApplePortal",
                code: 3022,
                userInfo: [NSLocalizedDescriptionKey: "Maximum number of certificates reached"]
            )
        )

        #expect(failure.code == "SEAL-CERT-204")
        #expect(failure.reason == "Apple 返回：无法创建签名证书")
        #expect(failure.recovery == "重试")
    }

    @Test
    func unclassifiedAccountFailureDoesNotForceReverification() {
        let failure = ApplePortalSigningFailure.make(
            stage: .account,
            error: NSError(
                domain: "ApplePortal",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected response"]
            )
        )

        #expect(failure.code == "SEAL-VERIFY-500")
        #expect(AppleServiceFailurePolicy.shouldRequireReverification(failure) == false)
    }

    @Test
    func networkFailureIsSeparatedFromAuthenticationAndTechnicalDetailsAreHidden() {
        let failure = ApplePortalSigningFailure.make(
            stage: .provisioningProfile,
            error: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
            )
        )

        #expect(failure.code.hasPrefix("SEAL-NET-"))
        #expect(failure.reason.contains("Apple ID 状态不会被修改"))
        #expect(failure.reason.contains("NSURLErrorDomain") == false)
        #expect(failure.reason.contains("-1001") == false)
    }
}
