import Foundation
import Testing
@testable import Seal

struct SigningCertificateSelectionPolicyTests {
    @Test
    func newSigningUsesAccountSelectedCertificate() throws {
        let account = makeAccount(
            localSerial: "LOCAL",
            selectedSerial: "SELECTED"
        )
        let app = makeApp(state: .imported)

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account
            ) == "SELECTED"
        )
    }

    @Test
    func renewalUsesActualPreviousCertificate() throws {
        let account = makeAccount(
            localSerial: "OLD",
            selectedSerial: "NEW"
        )
        var app = makeApp(state: .installed)
        app.certificateSerialNumber = "OLD"

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account
            ) == "OLD"
        )
    }

    @Test
    func renewalRejectsDifferentRequestedCertificate() {
        let account = makeAccount(
            localSerial: "OLD",
            selectedSerial: "NEW"
        )
        var app = makeApp(state: .installed)
        app.certificateSerialNumber = "OLD"

        #expect(throws: ImportFailure.self) {
            _ = try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account,
                requestedSerialNumber: "NEW"
            )
        }
    }

    @Test
    func localAvailabilityDetectsMissingPrivateKey() {
        let account = makeAccount(
            localSerial: nil,
            selectedSerial: "REMOTE"
        )
        let app = makeApp(state: .imported)

        #expect(
            SigningCertificateSelectionPolicy.localAvailabilityMessage(
                for: app,
                account: account
            ) != nil
        )
    }

    private func makeAccount(
        localSerial: String?,
        selectedSerial: String?
    ) -> AppleAccountRecord {
        AppleAccountRecord(
            maskedEmail: "s***@example.com",
            accountIdentifier: "account",
            teamID: "TEAMID",
            teamName: "Personal Team",
            isFreeTeam: true,
            status: .verified,
            certificateSerialNumber: localSerial,
            selectedCertificateSerialNumber: selectedSerial,
            lastVerifiedAt: Date()
        )
    }

    private func makeApp(state: AppState) -> AppRecord {
        AppRecord(
            originalBundleIdentifier: "com.example.app",
            name: "Example",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: state,
            ipaRelativePath: "Apps/example.ipa",
            importedAt: Date()
        )
    }
}
