import Foundation

struct AppleAccountRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var maskedEmail: String
    let accountIdentifier: String
    let teamID: String
    let teamName: String
    let isFreeTeam: Bool?
    var status: AccountStatus
    var certificateSerialNumber: String?
    var lastVerifiedAt: Date

    init(
        id: UUID = UUID(),
        maskedEmail: String,
        accountIdentifier: String,
        teamID: String,
        teamName: String,
        isFreeTeam: Bool? = nil,
        status: AccountStatus = .verified,
        certificateSerialNumber: String? = nil,
        lastVerifiedAt: Date
    ) {
        self.id = id
        self.maskedEmail = maskedEmail
        self.accountIdentifier = accountIdentifier
        self.teamID = teamID
        self.teamName = teamName
        self.isFreeTeam = isFreeTeam
        self.status = status
        self.certificateSerialNumber = certificateSerialNumber
        self.lastVerifiedAt = lastVerifiedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
