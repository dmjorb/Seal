import Foundation
import Testing
@preconcurrency import AltSign
@testable import Seal

struct AppleAccountClientTests {
    @Test
    @MainActor
    func multipleTeamsRequireExplicitSelectionBeforeAuthenticationCompletes() async throws {
        let first = AppleTeamOption(id: "T1", name: "Team One", isFreeTeam: false)
        let second = AppleTeamOption(id: "T2", name: "Personal Team", isFreeTeam: true)
        let api = TestAppleAccountAPI(teams: [first, second])
        let client = AppleAccountClient(
            anisetteProvider: TestAnisetteProvider(),
            api: api
        )

        let pending = try await client.beginAuthentication(
            email: "seal.user@icloud.com",
            password: "password",
            verificationCode: { nil }
        )

        #expect(api.authenticateCallCount == 1)
        #expect(api.fetchTeamsCallCount == 1)
        #expect(api.fetchTeamsAppleID == "seal.user@icloud.com")
        #expect(pending.teams.map(\.identifier) == ["T1", "T2"])
        #expect(pending.selectedAccount == nil)

        let authenticated = try pending.complete(team: second)
        #expect(authenticated.record.teamID == "T2")
        #expect(authenticated.record.teamName == "Personal Team")
        #expect(authenticated.record.isFreeTeam == true)

        #expect(throws: ImportFailure.self) {
            try pending.complete(
                team: AppleTeamOption(id: "OTHER", name: "Other", isFreeTeam: false)
            )
        }
    }

    @Test
    func masksEmailWithoutPersistingTheFullAddress() {
        #expect(AppleAccountClient.mask("seal.user@icloud.com") == "sea***er@icloud.com")
        #expect(AppleAccountClient.mask("developer@icloud.com") == "dev***er@icloud.com")
        #expect(AppleAccountClient.mask("13812345678") == "138****5678")
        #expect(AppleAccountClient.mask("+8613812345678") == "+86 138****5678")
        #expect(AppleAccountClient.mask("+14155552671") == "+1 415****2671")
        #expect(AppleAccountClient.mask("invalid") == "inv***id")
    }

    @Test
    func preservesAppleErrorCodeWhenTeamLookupFailsAfterVerification() {
        let error = NSError(
            domain: "com.apple.authentication",
            code: -20101,
            userInfo: [NSLocalizedDescriptionKey: "Developer services are unavailable"]
        )

        let failure = AppleAuthenticationFailure.make(
            stage: .teamLookup,
            error: error
        )

        #expect(failure.code == "SEAL-AUTH-105")
        #expect(failure.reason.contains("-20101"))
        #expect(failure.reason.contains("Developer services are unavailable"))
    }
}

@MainActor
private final class TestAppleAccountAPI: AppleAccountAPI {
    private let teams: [AppleTeamOption]
    private(set) var authenticateCallCount = 0
    private(set) var fetchTeamsCallCount = 0
    private(set) var fetchTeamsAppleID: String?

    init(teams: [AppleTeamOption]) {
        self.teams = teams
    }

    func authenticate(
        email: String,
        password: String,
        anisetteData: ALTAnisetteData,
        verificationCode: @escaping @MainActor @Sendable () async -> String?
    ) async throws -> AppleAccountAuthenticationSession {
        authenticateCallCount += 1
        return AppleAccountAuthenticationSession(
            appleID: email,
            accountIdentifier: "ACCOUNT",
            dsid: "DSID",
            authToken: "TOKEN"
        )
    }

    func fetchTeams(
        authentication: AppleAccountAuthenticationSession,
        anisetteData: ALTAnisetteData
    ) async throws -> [AppleTeamOption] {
        fetchTeamsCallCount += 1
        fetchTeamsAppleID = authentication.appleID
        return teams
    }
}

private struct TestAnisetteProvider: AnisetteProvider {
    func fetch() async throws -> ALTAnisetteData {
        guard let data = ALTAnisetteData(json: [
            "deviceSerialNumber": "0",
            "deviceDescription": "<MacBookPro>",
            "localUserID": "LOCAL",
            "deviceUniqueIdentifier": "00000000-0000-0000-0000-000000000000",
            "date": "2026-07-21T00:00:00Z",
            "locale": "en_US",
            "timeZone": "PST",
            "machineID": "MACHINE",
            "oneTimePassword": "OTP",
            "routingInfo": "0"
        ]) else {
            throw AnisetteV3Error.invalidServerResponse
        }
        return data
    }

    func resetProvisioning() async {}
}
