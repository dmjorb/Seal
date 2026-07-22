import Foundation

struct AuthenticatedAppleAccount: Sendable {
    let record: AppleAccountRecord
    let secret: AccountSecret
}

/// Short-lived authentication material awaiting an explicit team choice.
/// This value is intentionally neither Codable nor persisted outside Keychain.
struct PendingAppleAuthentication: Sendable {
    let accountIdentifier: String
    let secret: AccountSecret
    let maskedEmail: String
    let teams: [AppleTeamOption]

    var selectedAccount: AuthenticatedAppleAccount? { nil }

    func complete(team: AppleTeamOption) throws -> AuthenticatedAppleAccount {
        guard let selectedTeam = teams.first(where: { $0.id == team.id }) else {
            throw ImportFailure(
                title: "无法添加账号",
                reason: "所选开发团队不属于当前 Apple ID。",
                recovery: "重新选择团队",
                code: "SEAL-AUTH-108"
            )
        }

        return AuthenticatedAppleAccount(
            record: AppleAccountRecord(
                maskedEmail: maskedEmail,
                accountIdentifier: accountIdentifier,
                teamID: selectedTeam.id,
                teamName: selectedTeam.name,
                isFreeTeam: selectedTeam.isFreeTeam,
                lastVerifiedAt: Date()
            ),
            secret: secret
        )
    }
}
