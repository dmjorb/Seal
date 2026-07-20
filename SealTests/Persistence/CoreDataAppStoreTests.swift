import Foundation
import Testing
@testable import Seal

struct CoreDataAppStoreTests {
    @Test
    func fetchesNewestImportsFirst() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let older = makeRecord(
            name: "Older",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeRecord(
            name: "Newer",
            importedAt: Date(timeIntervalSince1970: 200)
        )

        try await store.save(older)
        try await store.save(newer)

        let records = try await store.fetchAll()
        #expect(records.map(\.name) == ["Newer", "Older"])
    }

    @Test
    func savingSameIDReplacesRecordAndExtensions() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let id = UUID()
        let original = makeRecord(
            id: id,
            name: "Original",
            extensions: [
                AppExtensionRecord(
                    name: "Share",
                    originalBundleIdentifier: "com.example.demo.share",
                    kind: .share
                )
            ]
        )
        let replacement = makeRecord(id: id, name: "Replacement", extensions: [])

        try await store.save(original)
        try await store.save(replacement)

        let records = try await store.fetchAll()
        let saved = try #require(records.first)
        #expect(records.count == 1)
        #expect(saved.name == "Replacement")
        #expect(saved.extensions.isEmpty)
    }

    @Test
    func persistentStoreReloadsSavedRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SealStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Seal.sqlite")
        let record = makeRecord(name: "Persisted")

        do {
            let firstStore = try CoreDataAppStore(storeURL: storeURL)
            try await firstStore.save(record)
        }

        let reopenedStore = try CoreDataAppStore(storeURL: storeURL)
        let records = try await reopenedStore.fetchAll()
        #expect(records == [record])
    }

    @Test
    func deletesRecordByID() async throws {
        let store = try CoreDataAppStore(inMemory: true)
        let record = makeRecord(name: "Delete Me")
        try await store.save(record)

        try await store.delete(id: record.id)

        #expect(try await store.fetchAll() == [])
    }

    private func makeRecord(
        id: UUID = UUID(),
        name: String,
        importedAt: Date = Date(timeIntervalSince1970: 100),
        extensions: [AppExtensionRecord] = []
    ) -> AppRecord {
        AppRecord(
            id: id,
            originalBundleIdentifier: "com.example.\(id.uuidString.lowercased())",
            name: name,
            version: "1.0",
            buildNumber: "1",
            size: 1_024,
            state: .imported,
            ipaRelativePath: "Apps/\(id.uuidString)/Original.ipa",
            importedAt: importedAt,
            extensions: extensions
        )
    }
}
