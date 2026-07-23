import Foundation
import Testing
@testable import Seal

struct AppRecordRecoveryTests {
    @Test
    func restoresPendingRecordFromAPreservedOriginalIPA() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let appID = UUID()
        let staged = try await environment.fileStore.stage(sourceURL: source)
        _ = try await environment.fileStore.commit(
            staged: staged,
            appID: appID,
            iconData: nil
        )

        try await AppRecordRecovery(
            appStore: environment.appStore,
            fileStore: environment.fileStore
        ).restoreMissingRecords()

        let records = try await environment.appStore.fetchAll()
        let restored = try #require(records.first)
        #expect(restored.id == appID)
        #expect(restored.originalBundleIdentifier == "com.example.demo")
        #expect(restored.state == .imported)
        #expect(restored.accountID == nil)
    }

    @Test
    func orphanWithSignedIPAIsRecoveredAsSignedAwaitingVerification() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let appID = UUID()
        let staged = try await environment.fileStore.stage(sourceURL: source)
        _ = try await environment.fileStore.commit(staged: staged, appID: appID, iconData: nil)
        _ = try await environment.fileStore.storeSignedIPA(sourceURL: source, appID: appID)

        try await AppRecordRecovery(
            appStore: environment.appStore,
            fileStore: environment.fileStore
        ).restoreMissingRecords()

        let restored = try #require(try await environment.appStore.fetchAll().first)
        #expect(restored.state == .signed)
        #expect(restored.signedArtifactStatus == .awaitingVerification)
        #expect(restored.signedIPASHA256?.isEmpty == false)
        #expect(restored.accountID == nil)
    }

    @Test
    func doesNotCreateADuplicateForAnExistingSealRecord() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make(
            apps: [.init(bundleIdentifier: "com.mjorb.seal")]
        )
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let staleAppID = UUID()
        let currentAppID = UUID()
        let staged = try await environment.fileStore.stage(sourceURL: source)
        _ = try await environment.fileStore.commit(
            staged: staged,
            appID: staleAppID,
            iconData: nil
        )
        let currentStaged = try await environment.fileStore.stage(sourceURL: source)
        let files = try await environment.fileStore.commit(
            staged: currentStaged,
            appID: currentAppID,
            iconData: nil
        )
        try await environment.appStore.save(
            AppRecord(
                originalBundleIdentifier: "com.mjorb.seal",
                name: "Seal",
                version: "1.0",
                buildNumber: "1",
                size: 1,
                state: .installed,
                ipaRelativePath: files.ipaRelativePath,
                isSeal: true,
                importedAt: Date()
            )
        )

        try await AppRecordRecovery(
            appStore: environment.appStore,
            fileStore: environment.fileStore
        ).restoreMissingRecords()

        #expect(try await environment.appStore.fetchAll().count == 1)
    }

    private func makeEnvironment() throws -> Environment {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SealRecoveryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let cache = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return Environment(
            root: root,
            fileStore: AppFileStore(documentsDirectory: documents, cacheDirectory: cache),
            appStore: try CoreDataAppStore(inMemory: true)
        )
    }
}

private extension AppRecordRecoveryTests {
    struct Environment {
        let root: URL
        let fileStore: AppFileStore
        let appStore: CoreDataAppStore
    }
}
