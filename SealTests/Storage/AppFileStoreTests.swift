import Foundation
import Testing
@testable import Seal

struct AppFileStoreTests {
    @Test
    func discoversCommittedOriginalIPAsForRecordRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = AppFileStore(
            documentsDirectory: root.appending(path: "Documents"),
            cacheDirectory: root.appending(path: "Cache"),
            fileProtector: MarkerFileProtector()
        )
        let appID = UUID()
        let original = root.appending(path: "Input.ipa")
        try Data("ipa".utf8).write(to: original)
        let staged = try await store.stage(sourceURL: original)
        _ = try await store.commit(staged: staged, appID: appID, iconData: nil)

        let stored = try await store.storedOriginalIPAs()

        #expect(stored.count == 1)
        #expect(stored[0].appID == appID)
        #expect(stored[0].relativePath == "Apps/\(appID.uuidString)/Original.ipa")
    }
    @Test
    func stagesAndCommitsOriginalIPAAndIcon() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )

        let staged = try await store.stage(sourceURL: fixture.source)
        #expect(FileManager.default.fileExists(atPath: staged.url.path))

        let appID = UUID()
        let files = try await store.commit(
            staged: staged,
            appID: appID,
            iconData: Data("icon".utf8)
        )

        #expect(files.ipaRelativePath == "Apps/\(appID.uuidString)/Original.ipa")
        #expect(files.iconRelativePath == "Apps/\(appID.uuidString)/Icon.png")
        #expect(FileManager.default.fileExists(
            atPath: fixture.documents.appending(path: files.ipaRelativePath).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: fixture.documents.appending(path: files.iconRelativePath ?? "").path
        ))
        #expect(FileManager.default.fileExists(atPath: staged.url.path))

        try await store.cancel(staged)
        #expect(FileManager.default.fileExists(atPath: staged.url.path) == false)
    }

    @Test
    func cancellationRemovesStagedDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let staged = try await store.stage(sourceURL: fixture.source)

        try await store.cancel(staged)

        #expect(FileManager.default.fileExists(atPath: staged.url.path) == false)
    }

    @Test
    func separateAppIDsNeverOverwriteEachOther() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let firstStage = try await store.stage(sourceURL: fixture.source)
        let secondStage = try await store.stage(sourceURL: fixture.source)

        let first = try await store.commit(staged: firstStage, appID: UUID(), iconData: nil)
        let second = try await store.commit(staged: secondStage, appID: UUID(), iconData: nil)

        #expect(first.ipaRelativePath != second.ipaRelativePath)
    }

    @Test
    func committedIPAUsesFileProtector() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache,
            fileProtector: MarkerFileProtector()
        )
        let staged = try await store.stage(sourceURL: fixture.source)
        let files = try await store.commit(staged: staged, appID: UUID(), iconData: nil)
        let ipaURL = fixture.documents.appending(path: files.ipaRelativePath)

        #expect(FileManager.default.fileExists(
            atPath: ipaURL.appendingPathExtension("protected").path
        ))
    }

    @Test
    func removesStaleTemporaryFilesAtStartup() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let stale = fixture.cache.appending(path: "Seal/Temp/stale.tmp")
        try FileManager.default.createDirectory(
            at: stale.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(to: stale)

        _ = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )

        #expect(FileManager.default.fileExists(atPath: stale.path) == false)
    }

    private func makeFixture() throws -> (
        root: URL,
        documents: URL,
        cache: URL,
        source: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SealFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let cache = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let source = root.appending(path: "Source.ipa")
        try Data("ipa".utf8).write(to: source, options: .atomic)
        return (root, documents, cache, source)
    }
}
