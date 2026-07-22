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
    func certificateLimitAutomaticallyRevokesUnusableCertificateAndRetries() async throws {
        let portal = CertificatePortalOperationsSpy(candidates: ["OLD"])
        let operations = CertificatePortalOperations<String>(
            addCertificate: { try await portal.addCertificate() },
            cleanupCandidates: { await portal.cleanupCandidates() },
            revokeCertificate: { certificate in
                try await portal.revokeCertificate(certificate)
            }
        )

        let created = try await ApplePortalCertificateCapacityOrchestrator.create(
            using: operations
        )

        #expect(created == "NEW")
        #expect(await portal.addCallCount() == 2)
        #expect(await portal.revokeCallCount() == 1)
    }

    @Test
    func certificateLimitFailsAfterAutomaticCleanupHasNoCandidate() async {
        let portal = CertificatePortalOperationsSpy(candidates: [])
        let operations = CertificatePortalOperations<String>(
            addCertificate: { try await portal.addCertificate() },
            cleanupCandidates: { await portal.cleanupCandidates() },
            revokeCertificate: { certificate in
                try await portal.revokeCertificate(certificate)
            }
        )

        do {
            _ = try await ApplePortalCertificateCapacityOrchestrator.create(using: operations)
            Issue.record("Expected certificate capacity failure")
        } catch let failure as ImportFailure {
            #expect(failure.code == "SEAL-CERT-211")
            #expect(failure.reason.contains("自动检查"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func reusedAppIDPreservesExistingFeaturesAndEntitlements() {
        let mergedFeatures = ApplePortalAppIDResolver.mergePreservingRemoteValues(
            remote: ["push": true, "groups": true],
            requested: ["push": false, "icloud": true]
        )
        let mergedEntitlements = ApplePortalAppIDResolver.mergePreservingRemoteValues(
            remote: ["environment": "production", "groups": "remote"],
            requested: ["environment": "development", "health": "requested"]
        )

        #expect(mergedFeatures == ["push": true, "groups": true, "icloud": true])
        #expect(mergedEntitlements == [
            "environment": "production",
            "groups": "remote",
            "health": "requested"
        ])
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

private actor CertificatePortalOperationsSpy {
    private var addCalls = 0
    private var revokeCalls = 0
    private let candidates: [String]

    init(candidates: [String]) {
        self.candidates = candidates
    }

    func addCertificate() throws -> String {
        addCalls += 1
        if addCalls == 1 {
            throw NSError(
                domain: "ApplePortal",
                code: 3022,
                userInfo: [NSLocalizedDescriptionKey: "Maximum number of certificates reached"]
            )
        }
        return "NEW"
    }

    func cleanupCandidates() -> [String] { candidates }

    func revokeCertificate(_ certificate: String) throws {
        revokeCalls += 1
    }

    func addCallCount() -> Int { addCalls }
    func revokeCallCount() -> Int { revokeCalls }
}
