import Foundation

struct RefreshQueueItem: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case running
        case completed
        case failed
    }

    let id: UUID
    let appID: UUID
    let accountID: UUID
    var state: State
    var lastErrorCode: String?

    init(
        id: UUID = UUID(),
        appID: UUID,
        accountID: UUID,
        state: State = .pending,
        lastErrorCode: String? = nil
    ) {
        self.id = id
        self.appID = appID
        self.accountID = accountID
        self.state = state
        self.lastErrorCode = lastErrorCode
    }
}
