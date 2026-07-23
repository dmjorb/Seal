import Foundation
import Testing
@testable import Seal

struct AuthenticatedAppleAccountTests {
    @Test
    func selectedTeamIsPersistedWithoutChangingAccountIdentity() throws {
        let secret = AccountSecret(
            email: "demo@icloud.com",
            accountIdentifier: "ACCOUNT",
            dsid: "DSID",
            authToken: "TOKEN",
            certificateP12: nil,
            certificateSerialNumber: nil,
            certificateMachineIdentifier: nil
        )
        let authenticated = AuthenticatedAppleAccount(
            maskedEmail: "d***@icloud.com",
            accountIdentifier: "ACCOUNT",
            teams: [
                AppleTeamRecord(id: "FREE", name: "Free", isFreeTeam: true),
                AppleTeamRecord(id: "PAID", name: "Paid", isFreeTeam: false)
            ],
            secret: secret,
            verifiedAt: Date(timeIntervalSince1970: 100)
        )

        let record = authenticated.record(
            team: try #require(authenticated.teams.first { $0.id == "PAID" }),
            id: UUID()
        )

        #expect(record.accountIdentifier == "ACCOUNT")
        #expect(record.teamID == "PAID")
        #expect(record.teamName == "Paid")
        #expect(record.isFreeTeam == false)
        #expect(record.status == .verified)
    }
}
