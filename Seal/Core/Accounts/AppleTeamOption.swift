struct AppleTeamOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isFreeTeam: Bool

    var identifier: String { id }
}
