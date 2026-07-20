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
    func renewalUsesCurrentlySelectedAccountCertificate() throws {
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
            ) == "NEW"
        )
    }

    @Test
    func requestedCertificateWinsForRenewal() throws {
        let account = makeAccount(
            localSerial: "OLD",
            selectedSerial: "SELECTED"
        )
        var app = makeApp(state: .installed)
        app.certificateSerialNumber = "OLD"

        #expect(
            try SigningCertificateSelectionPolicy.resolvedSerialNumber(
                for: app,
                account: account,
                requestedSerialNumber: "REQUESTED"
            ) == "REQUESTED"
        )
    }

    @Test
    func localAvailabilityDetectsMissingPrivateKeyForSelectedCertificate() {
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

    @Test
    func accountAndTeamHistoryDoesNotBlockBeforeAppleValidation() throws {
        let account = makeAccount(localSerial: "LOCAL", selectedSerial: "LOCAL")
        var app = makeApp(state: .installed)
        app.accountID = UUID()
        app.signingTeamID = "ORIGINALTEAM"
        app.certificateSerialNumber = "OLD"

        try SigningCertificateSelectionPolicy.validateAccountAndTeam(
            for: app,
            account: account
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
