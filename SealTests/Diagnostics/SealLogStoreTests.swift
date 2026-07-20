import Foundation
import Testing
@testable import Seal

struct SealLogStoreTests {
    @Test
    func keepsOnlyNewestEntries() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SealLogStore(
            fileURL: directory.appending(path: "Logs.json"),
            maximumEntries: 2,
            fileProtector: MarkerFileProtector()
        )

        try await store.append(category: .system, message: "one")
        try await store.append(category: .system, message: "two")
        try await store.append(category: .system, message: "three")
        let entries = try await store.entries()

        #expect(entries.map(\.message) == ["three", "two"])
    }
}
