import Foundation
import Testing
@testable import Seal

struct SelfRenewalContextValidatorTests {
    @Test
    func acceptsTheCurrentBundleAndProfileTeamEvenWhenTheStoredAccountIDIsStale() throws {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(
            id: selectedAccountID,
            teamID: "T3432ZHJUF9"
        )

        try SelfRenewalContextValidator.validate(
            currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            targetBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            currentSigningTeamIdentifier: "t3432zhjuf9",
            selectedAccount: selectedAccount,
            boundAccountID: UUID(),
            selectedAccountID: selectedAccountID
        )
    }

    @Test
    func rejectsChangingTheBundleIdentifierDuringSelfRenewal() {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(
            id: selectedAccountID,
            teamID: "T3432ZHJUF9"
        )

        #expect(throws: ImportFailure.self) {
            try SelfRenewalContextValidator.validate(
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                targetBundleIdentifier: "com.mjorb.seal.dmj",
                currentSigningTeamIdentifier: "T3432ZHJUF9",
                selectedAccount: selectedAccount,
                boundAccountID: selectedAccountID,
                selectedAccountID: selectedAccountID
            )
        }
    }

    @Test
    func rejectsAnAppleAccountFromAnotherTeam() {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(
            id: selectedAccountID,
            teamID: "OTHERTEAM"
        )

        do {
            try SelfRenewalContextValidator.validate(
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                targetBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                currentSigningTeamIdentifier: "T3432ZHJUF9",
                selectedAccount: selectedAccount,
                boundAccountID: selectedAccountID,
                selectedAccountID: selectedAccountID
            )
            Issue.record("Expected Team mismatch to fail.")
        } catch let failure as ImportFailure {
            #expect(failure.code == "SEAL-SELF-103")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeAccount(
        id: UUID,
        teamID: String
    ) -> AppleAccountRecord {
        AppleAccountRecord(
            id: id,
            maskedEmail: "sunuannian1@gmail.com",
            accountIdentifier: "account",
            teamID: teamID,
            teamName: "Team",
            lastVerifiedAt: .now
        )
    }
}
