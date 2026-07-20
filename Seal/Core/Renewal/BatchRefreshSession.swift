import Foundation

struct BatchRefreshSession: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running
        case completed(BatchRefreshResult)
        case failed(ImportFailure)
    }

    let id: UUID
    var status: Status
    var currentIndex: Int
    var total: Int
    var currentAppName: String?
    var currentStage: SigningStage?
    var succeeded: Int
    var failed: Int

    init(id: UUID = UUID()) {
        self.id = id
        status = .running
        currentIndex = 0
        total = 0
        succeeded = 0
        failed = 0
    }
}
