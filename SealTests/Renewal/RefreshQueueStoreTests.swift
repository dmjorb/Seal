import Foundation
import Testing
@testable import Seal

struct RefreshQueueStoreTests {
    @Test
    func persistsPendingAndCompletedItems() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RefreshQueueStore(
            fileURL: directory.appending(path: "RefreshQueue.json"),
            fileProtector: MarkerFileProtector()
        )
        let first = RefreshQueueItem(appID: UUID(), accountID: UUID())
        let second = RefreshQueueItem(appID: UUID(), accountID: UUID())

        try await store.replace(with: [first, second])
        try await store.markCompleted(appID: first.appID)
        let reloaded = try await store.load()

        #expect(reloaded.count == 2)
        #expect(reloaded.first(where: { $0.appID == first.appID })?.state == .completed)
        #expect(reloaded.first(where: { $0.appID == second.appID })?.state == .pending)
    }
}
