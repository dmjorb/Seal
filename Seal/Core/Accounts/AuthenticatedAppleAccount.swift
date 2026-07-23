import Foundation

struct AppleTeamRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let isFreeTeam: Bool

    init(id: String, name: String, isFreeTeam: Bool) {
        self.id = id
        self.name = name
        self.isFreeTeam = isFreeTeam
    }
}

struct AuthenticatedAppleAccount: Sendable {
    let maskedEmail: String
    let accountIdentifier: String
    let teams: [AppleTeamRecord]
    let secret: AccountSecret
    let verifiedAt: Date

    func record(team: AppleTeamRecord, id: UUID = UUID()) -> AppleAccountRecord {
        AppleAccountRecord(
            id: id,
            maskedEmail: maskedEmail,
            accountIdentifier: accountIdentifier,
            teamID: team.id,
            teamName: team.name,
            isFreeTeam: team.isFreeTeam,
            status: .verified,
            lastVerifiedAt: verifiedAt
        )
    }
}
