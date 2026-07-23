import Foundation
import Testing
@testable import Seal

@MainActor
struct ApplicationOperationCoordinatorTests {
    @Test
    func conflictingWriteOperationsAreRejectedUntilLeaseEnds() throws {
        let coordinator = OperationCoordinator()
        let first = try #require(coordinator.begin(.signing, appID: UUID()))
        #expect(coordinator.begin(.maintainingStorage) == nil)
        #expect(coordinator.conflictFailure(requested: .maintainingStorage).code == "SEAL-OP-001")

        coordinator.end(first)
        let second = try #require(coordinator.begin(.maintainingStorage))
        #expect(second.kind == .maintainingStorage)
        coordinator.end(second)
    }
}
