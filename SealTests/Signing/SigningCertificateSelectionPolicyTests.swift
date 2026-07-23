import Foundation
import Testing
@testable import Seal

struct SigningCertificateSelectionPolicyTests {
    @Test
    func newSigningUsesCurrentLocallyUsableCertificate() throws {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "REMOTE")
        let app = makeApp(state: .imported)

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account
            ) == "LOCAL"
        )
    }

    @Test
    func renewalUsesCurrentLocallyUsableAccountCertificate() throws {
        let account = makeAccount(localSerial: "NEW", selectedSerial: "NEW")
        var app = makeApp(state: .installed)
        app.accountID = account.id
        app.signingTeamID = account.teamID
        app.certificateSerialNumber = "OLD"

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account
            ) == "NEW"
        )
    }

    @Test
    func arbitraryRequestedCertificateCannotOverrideLocalCertificate() throws {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "LOCAL")
        let app = makeApp(state: .imported)

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account,
                requestedSerialNumber: "REMOTE"
            ) == "LOCAL"
        )
    }

    @Test
    func localAvailabilityDetectsMissingPrivateKeyForSelectedCertificate() {
        let account = makeAccount(localSerial: nil, selectedSerial: "REMOTE")
        let app = makeApp(state: .imported)

        #expect(
            SigningCertificateSelectionPolicy.localAvailabilityMessage(
                for: app,
                account: account
            ) != nil
        )
    }


    @Test
    func renewalRejectsMissingPreviousTeam() {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "LOCAL")
        var app = makeApp(state: .installed)
        app.accountID = account.id
        app.signingTeamID = nil

        #expect(throws: ImportFailure.self) {
            try SigningCertificateSelectionPolicy.validateAccountAndTeam(
                for: app,
                account: account
            )
        }
    }

    @Test
    func renewalTeamMismatchRequestsExplicitTeamSelection() throws {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "LOCAL")
        var app = makeApp(state: .installed)
        app.accountID = account.id
        app.signingTeamID = "OTHERTEAM"

        do {
            try SigningCertificateSelectionPolicy.validateAccountAndTeam(
                for: app,
                account: account
            )
            Issue.record("Expected Team mismatch failure")
        } catch let failure as ImportFailure {
            #expect(failure.code == "SEAL-AUTH-112")
            #expect(failure.recovery == "选择 Team")
        }
    }

    @Test
    func renewalRejectsDifferentAccountAndTeam() {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "LOCAL")
        var app = makeApp(state: .installed)
        app.accountID = UUID()
        app.signingTeamID = "ORIGINALTEAM"

        #expect(throws: ImportFailure.self) {
            try SigningCertificateSelectionPolicy.validateAccountAndTeam(
                for: app,
                account: account
            )
        }
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
