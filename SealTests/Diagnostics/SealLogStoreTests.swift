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

    @Test
    func redactsSensitiveAppleAndPairingValuesBeforePersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "Logs.json")
        let store = SealLogStore(
            fileURL: fileURL,
            fileProtector: MarkerFileProtector()
        )
        let uuid = "12345678-1234-1234-1234-1234567890AB"
        let jwt = "eyJabcdefghijk.abcdefghijklmnop.abcdefghijklmnop"
        try await store.append(
            category: .account,
            message: "Apple ID demo@icloud.com Team ID: ABCDEFGHIJ Serial: 1234567890ABCDEF UDID: 000081100012345678901234 UUID: \(uuid) Authorization: Bearer-secret Cookie: session-secret JWT: \(jwt)"
        )

        let storedText = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        #expect(storedText.contains("demo@icloud.com") == false)
        #expect(storedText.contains("1234567890ABCDEF") == false)
        #expect(storedText.contains(uuid) == false)
        #expect(storedText.contains(jwt) == false)
        #expect(storedText.contains("Bearer-secret") == false)
        #expect(storedText.contains("session-secret") == false)
    }

}
