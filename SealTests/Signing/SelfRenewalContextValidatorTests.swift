import Foundation
import Testing
@testable import Seal

struct SelfRenewalContextValidatorTests {
    @Test
    func acceptsCurrentBundleBoundAccountAndProfileTeam() throws {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(id: selectedAccountID, teamID: "T3432ZHJUF9")

        try SelfRenewalContextValidator.validate(
            currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            targetBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            currentSigningTeamIdentifier: "t3432zhjuf9",
            selectedAccount: selectedAccount,
            boundAccountID: selectedAccountID,
            selectedAccountID: selectedAccountID
        )
    }

    @Test
    func rejectsChangingBundleIdentifierDuringSelfRenewal() {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(id: selectedAccountID, teamID: "T3432ZHJUF9")

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
    func rejectsAStaleBoundAccountID() {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(id: selectedAccountID, teamID: "T3432ZHJUF9")

        #expect(throws: ImportFailure.self) {
            try SelfRenewalContextValidator.validate(
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                targetBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                currentSigningTeamIdentifier: "T3432ZHJUF9",
                selectedAccount: selectedAccount,
                boundAccountID: UUID(),
                selectedAccountID: selectedAccountID
            )
        }
    }

    @Test
    func rejectsAnAppleAccountFromAnotherTeam() {
        let selectedAccountID = UUID()
        let selectedAccount = makeAccount(id: selectedAccountID, teamID: "OTHERTEAM")

        #expect(throws: ImportFailure.self) {
            try SelfRenewalContextValidator.validate(
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                targetBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
                currentSigningTeamIdentifier: "T3432ZHJUF9",
                selectedAccount: selectedAccount,
                boundAccountID: selectedAccountID,
                selectedAccountID: selectedAccountID
            )
        }
    }

    private func makeAccount(id: UUID, teamID: String) -> AppleAccountRecord {
        AppleAccountRecord(
            id: id,
            maskedEmail: "sun***n1@gmail.com",
            accountIdentifier: "account",
            teamID: teamID,
            teamName: "Team",
            lastVerifiedAt: .now
        )
    }
}
