import Foundation
import Testing
@testable import Seal

struct AppFileStoreTests {
    @Test
    func explicitLeaseReleaseIsIdempotent() async throws {
        let coordinator = AppOperationCoordinator()
        let appID = UUID()
        let lease = try await coordinator.acquire(appID: appID, kind: .signing)

        await lease.release()
        await lease.release()
        await coordinator.waitUntilIdle()

        #expect(await coordinator.isBusy(appID: appID) == false)
        let replacement = try await coordinator.acquire(appID: appID, kind: .signing)
        await replacement.release()
    }

    @Test
    func destroyingLeaseOwnerEventuallyReleasesCoordinatorWithoutPolling() async throws {
        let coordinator = AppOperationCoordinator()
        let appID = UUID()
        var owner: OperationLeaseOwner? = OperationLeaseOwner(
            lease: try await coordinator.acquire(appID: appID, kind: .signing)
        )
        #expect(owner != nil)
        #expect(await coordinator.isBusy(appID: appID))

        owner = nil
        await coordinator.waitUntilIdle()

        #expect(await coordinator.isBusy(appID: appID) == false)
    }

    @Test
    func signedCacheCleanupSkipsLeasedApp() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = AppOperationCoordinator()
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let leasedAppID = UUID()
        let idleAppID = UUID()
        let leasedPath = try await store.storeSignedIPA(
            sourceURL: fixture.source,
            appID: leasedAppID
        )
        let idlePath = try await store.storeSignedIPA(
            sourceURL: fixture.source,
            appID: idleAppID
        )
        let operationLease = try await coordinator.acquire(
            appID: leasedAppID,
            kind: .signing
        )
        defer { Task { await operationLease.release() } }
        let cleanupLease = try await coordinator.acquire(appID: nil, kind: .cleaning)
        defer { Task { await cleanupLease.release() } }

        let result = try await store.clearSignedIPAs(
            excluding: await coordinator.snapshot()
        )

        #expect(result.skippedAppIDs == [leasedAppID])
        #expect(try await store.exists(relativePath: leasedPath))
        #expect(try await store.exists(relativePath: idlePath) == false)
    }

    @Test
    func globalOperationRejectsStorageCleanupLease() async throws {
        let coordinator = AppOperationCoordinator()
        let importLease = try await coordinator.acquire(appID: nil, kind: .importing)
        defer { Task { await importLease.release() } }

        await #expect(throws: AppOperationCoordinator.AcquisitionError.self) {
            try await coordinator.acquire(appID: nil, kind: .cleaning)
        }
    }

    @Test
    func removalRecoveryRestoresTombstoneWhenDatabaseRecordStillExists() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let appID = UUID()
        let staged = try await store.stage(sourceURL: fixture.source)
        let committed = try await store.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(committed)
        let record = makeRecord(appID: appID, files: committed.files)

        _ = try await store.prepareRemoval(appID: appID)
        let recoveredStore = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        try await recoveredStore.recoverRemovals(appRecords: [record])

        #expect(try await recoveredStore.exists(relativePath: committed.files.ipaRelativePath))
        #expect(try removalArtifactNames(in: fixture.documents).isEmpty)
    }

    @Test
    func committedRemovalTombstoneIsInvisibleToRecordRecovery() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let appID = UUID()
        let validIPA = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: validIPA.deletingLastPathComponent()) }
        let staged = try await store.stage(sourceURL: validIPA)
        let committed = try await store.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(committed)
        let removal = try await store.prepareRemoval(appID: appID)
        let appStore = OperationRecoveryAppStore()

        try await AppRecordRecovery(appStore: appStore, fileStore: store).restoreMissingRecords()
        _ = removal

        #expect(await appStore.fetchAll().isEmpty)
        #expect(try removalArtifactNames(in: fixture.documents).isEmpty)
    }

    @Test
    func transientSigningStateDoesNotMakeInstalledAppRemovable() {
        let app = AppRecord(
            originalBundleIdentifier: "com.example.installed",
            name: "Installed",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .signing,
            expiryDate: Date(timeIntervalSince1970: 2_000),
            lastInstalledAt: Date(timeIntervalSince1970: 1_000),
            ipaRelativePath: "Apps/installed/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 500)
        )

        #expect(
            AppStorageCleanupPolicy.canRemoveImportedRecord(
                app,
                leasedAppIDs: []
            ) == false
        )
    }

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
        let transaction = try await store.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(transaction)

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
        let transaction = try await store.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: Data("icon".utf8)
        )
        let files = transaction.files
        try await store.finalize(transaction)

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

        let firstTransaction = try await store.prepareCommit(
            staged: firstStage,
            appID: UUID(),
            iconData: nil
        )
        let secondTransaction = try await store.prepareCommit(
            staged: secondStage,
            appID: UUID(),
            iconData: nil
        )
        try await store.finalize(firstTransaction)
        try await store.finalize(secondTransaction)

        #expect(firstTransaction.files.ipaRelativePath != secondTransaction.files.ipaRelativePath)
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
        let transaction = try await store.prepareCommit(
            staged: staged,
            appID: UUID(),
            iconData: nil
        )
        let files = transaction.files
        try await store.finalize(transaction)
        let ipaURL = fixture.documents.appending(path: files.ipaRelativePath)

        #expect(FileManager.default.fileExists(
            atPath: ipaURL.appendingPathExtension("protected").path
        ))
    }

    @Test
    func rollbackRestoresPreviousIPAAndIconWithoutLeavingTransactionDirectories() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        let appID = UUID()
        let originalIPA = Data("old ipa".utf8)
        let originalIcon = Data("old icon".utf8)
        try originalIPA.write(to: fixture.source, options: .atomic)
        let originalStage = try await store.stage(sourceURL: fixture.source)
        let originalTransaction = try await store.prepareCommit(
            staged: originalStage,
            appID: appID,
            iconData: originalIcon
        )
        try await store.finalize(originalTransaction)

        try Data("new ipa".utf8).write(to: fixture.source, options: .atomic)
        let replacementStage = try await store.stage(sourceURL: fixture.source)
        let replacement = try await store.prepareCommit(
            staged: replacementStage,
            appID: appID,
            iconData: Data("new icon".utf8)
        )
        let appsRoot = fixture.documents.appending(path: "Apps", directoryHint: .isDirectory)
        #expect(try transactionDirectoryNames(in: appsRoot).contains { $0.contains(".backup-") })

        try await store.rollback(replacement)

        #expect(
            try Data(contentsOf: fixture.documents.appending(path: replacement.files.ipaRelativePath))
                == originalIPA
        )
        #expect(
            try Data(contentsOf: fixture.documents.appending(path: replacement.files.iconRelativePath!))
                == originalIcon
        )
        #expect(try transactionDirectoryNames(in: appsRoot).isEmpty)
    }

    @Test
    func rollbackRestoreFailurePutsNewFilesBackAndPersistsRecoveryForNextStore() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appID = UUID()
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache,
            beforeFileOperation: { operation in
                guard operation == .restoreBackup else { return }
                throw InjectedFileOperationFailure.expected
            }
        )
        let oldData = Data("old ipa".utf8)
        try oldData.write(to: fixture.source, options: .atomic)
        let originalStage = try await store.stage(sourceURL: fixture.source)
        let original = try await store.prepareCommit(
            staged: originalStage,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(original)
        let newData = Data("new ipa".utf8)
        try newData.write(to: fixture.source, options: .atomic)
        let replacementStage = try await store.stage(sourceURL: fixture.source)
        let replacement = try await store.prepareCommit(
            staged: replacementStage,
            appID: appID,
            iconData: nil
        )

        await #expect(throws: ImportFailure.self) {
            try await store.rollback(replacement)
        }

        let finalURL = fixture.documents.appending(path: replacement.files.ipaRelativePath)
        #expect(try Data(contentsOf: finalURL) == newData)
        let appsRoot = fixture.documents.appending(path: "Apps", directoryHint: .isDirectory)
        #expect(try transactionDirectoryNames(in: appsRoot).isEmpty == false)

        let recoveredStore = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        try await recoveredStore.recoverTransactions(appRecords: [])

        #expect(try Data(contentsOf: finalURL) == oldData)
        #expect(try transactionDirectoryNames(in: appsRoot).isEmpty)
    }

    @Test
    func finalizeRemoveFailureIsRetriedFromPersistentCommittedJournal() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appID = UUID()
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache,
            beforeFileOperation: { operation in
                guard operation == .removeBackup else { return }
                throw InjectedFileOperationFailure.expected
            }
        )
        try Data("old ipa".utf8).write(to: fixture.source, options: .atomic)
        let originalStage = try await store.stage(sourceURL: fixture.source)
        let original = try await store.prepareCommit(
            staged: originalStage,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(original)
        let newData = Data("new ipa".utf8)
        try newData.write(to: fixture.source, options: .atomic)
        let replacementStage = try await store.stage(sourceURL: fixture.source)
        let replacement = try await store.prepareCommit(
            staged: replacementStage,
            appID: appID,
            iconData: nil
        )
        let committedRecord = makeRecord(appID: appID, files: replacement.files)
        try await store.setExpectedRecord(committedRecord, for: replacement)

        await #expect(throws: ImportFailure.self) {
            try await store.finalize(replacement)
        }

        let recoveredStore = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        try await recoveredStore.recoverTransactions(appRecords: [committedRecord])

        let finalURL = fixture.documents.appending(path: replacement.files.ipaRelativePath)
        #expect(try Data(contentsOf: finalURL) == newData)
        let appsRoot = fixture.documents.appending(path: "Apps", directoryHint: .isDirectory)
        #expect(try transactionDirectoryNames(in: appsRoot).isEmpty)
    }

    @Test
    func recoveryTreatsExpectedRecordMatchAsCommittedAcrossMarkerWindow() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appID = UUID()
        let store = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        try Data("old ipa".utf8).write(to: fixture.source, options: .atomic)
        let originalStage = try await store.stage(sourceURL: fixture.source)
        let original = try await store.prepareCommit(
            staged: originalStage,
            appID: appID,
            iconData: nil
        )
        try await store.finalize(original)
        let newData = Data("new ipa".utf8)
        try newData.write(to: fixture.source, options: .atomic)
        let replacementStage = try await store.stage(sourceURL: fixture.source)
        let replacement = try await store.prepareCommit(
            staged: replacementStage,
            appID: appID,
            iconData: nil
        )
        let committedRecord = makeRecord(appID: appID, files: replacement.files)
        try await store.setExpectedRecord(committedRecord, for: replacement)

        let recoveredStore = AppFileStore(
            documentsDirectory: fixture.documents,
            cacheDirectory: fixture.cache
        )
        try await recoveredStore.recoverTransactions(appRecords: [committedRecord])

        let finalURL = fixture.documents.appending(path: replacement.files.ipaRelativePath)
        #expect(try Data(contentsOf: finalURL) == newData)
        let appsRoot = fixture.documents.appending(path: "Apps", directoryHint: .isDirectory)
        #expect(try transactionDirectoryNames(in: appsRoot).isEmpty)
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

    private func transactionDirectoryNames(in appsRoot: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: appsRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix(".") }
    }

    private func removalArtifactNames(in documents: URL) throws -> [String] {
        let appsRoot = documents.appending(path: "Apps", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: appsRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.contains(".removing-") || $0 == ".removals" }
    }

    private func makeRecord(appID: UUID, files: StoredAppFiles) -> AppRecord {
        AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Demo",
            version: "2.0",
            buildNumber: "2",
            size: 7,
            state: .imported,
            ipaRelativePath: files.ipaRelativePath,
            importedAt: Date(timeIntervalSince1970: 200)
        )
    }
}

private enum InjectedFileOperationFailure: Error {
    case expected
}

private final class OperationLeaseOwner {
    let lease: AppOperationCoordinator.Lease

    init(lease: AppOperationCoordinator.Lease) {
        self.lease = lease
    }
}

private actor OperationRecoveryAppStore: AppStore {
    private var records: [AppRecord] = []
    func fetchAll() -> [AppRecord] { records }
    func save(_ record: AppRecord) { records.append(record) }
    func replaceImportedApp(_ record: AppRecord) -> [AppRecord] { records.append(record); return [] }
    func delete(id: UUID) { records.removeAll { $0.id == id } }
}
