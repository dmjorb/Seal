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

    @Test
    func sameDailyBatchRetriesOnlyUnfinishedItemsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "RefreshQueue.json")
        let first = RefreshQueueItem(appID: UUID(), accountID: UUID())
        let second = RefreshQueueItem(appID: UUID(), accountID: UUID())
        let dayKey = "2033-05-18"

        let initialStore = RefreshQueueStore(
            fileURL: fileURL,
            fileProtector: MarkerFileProtector()
        )
        let initialWork = try await initialStore.prepare(
            with: [first, second],
            sessionID: dayKey
        )
        #expect(initialWork.map(\.appID) == [first.appID, second.appID])

        try await initialStore.markCompleted(appID: first.appID)
        try await initialStore.markFailed(appID: second.appID, errorCode: "SEAL-RENEW-500")

        let restartedStore = RefreshQueueStore(
            fileURL: fileURL,
            fileProtector: MarkerFileProtector()
        )
        let resumedWork = try await restartedStore.prepare(
            with: [first, second],
            sessionID: dayKey
        )
        let persisted = try await restartedStore.load()

        #expect(resumedWork.map(\.appID) == [second.appID])
        #expect(persisted.first(where: { $0.appID == first.appID })?.state == .completed)
        #expect(persisted.first(where: { $0.appID == second.appID })?.state == .pending)
    }

    @Test
    func duplicatePersistedAppIDsDoNotCrashAndCompletedStateWins() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "RefreshQueue.json")
        let appID = UUID()
        let pending = RefreshQueueItem(appID: appID, accountID: UUID(), state: .pending)
        let completed = RefreshQueueItem(appID: appID, accountID: UUID(), state: .completed)
        let fixture = RefreshQueueFixture(sessionID: "2033-05-18", items: [completed, pending])
        try JSONEncoder().encode(fixture).write(to: fileURL, options: .atomic)
        let store = RefreshQueueStore(fileURL: fileURL, fileProtector: MarkerFileProtector())

        let loaded = try await store.load()
        let resumed = try await store.prepare(with: [pending], sessionID: "2033-05-18")

        #expect(loaded.count == 1)
        #expect(loaded.first?.state == .completed)
        #expect(resumed.isEmpty)
    }

    @Test
    func newDailyBatchIncludesPreviouslyCompletedItems() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RefreshQueueStore(
            fileURL: directory.appending(path: "RefreshQueue.json"),
            fileProtector: MarkerFileProtector()
        )
        let item = RefreshQueueItem(appID: UUID(), accountID: UUID())

        _ = try await store.prepare(with: [item], sessionID: "2033-05-18")
        try await store.markCompleted(appID: item.appID)
        let nextDayWork = try await store.prepare(with: [item], sessionID: "2033-05-19")
        let persisted = try await store.load()

        #expect(nextDayWork.map(\.appID) == [item.appID])
        #expect(persisted.first?.state == .pending)
    }
}

private struct RefreshQueueFixture: Codable {
    let sessionID: String?
    let items: [RefreshQueueItem]
}
