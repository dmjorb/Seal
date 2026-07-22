import Foundation
import Testing
@testable import Seal

@MainActor
struct AppsViewModelOperationTests {
    @Test
    func refreshSigningChannelStopsAfterSuccessfulProbe() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let channel = RefreshInstallChannel(result: .success)
        let viewModel = makeViewModel(fixture: fixture, installChannel: channel)

        #expect(await viewModel.refreshSigningChannel())
        #expect(await channel.startCallCount == 1)
        #expect(await channel.stopCallCount == 1)
    }

    @Test
    func refreshSigningChannelStopsAfterFailedProbe() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let channel = RefreshInstallChannel(result: .failure)
        let viewModel = makeViewModel(fixture: fixture, installChannel: channel)

        #expect(await viewModel.refreshSigningChannel() == false)
        #expect(await channel.startCallCount == 1)
        #expect(await channel.stopCallCount == 1)
    }

    @Test
    func cancelSigningKeepsRunningSessionUntilCoordinatorFinishesCancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let account = AppleAccountRecord(
            maskedEmail: "c***@example.com",
            accountIdentifier: "cancel-account",
            teamID: "TEAM",
            teamName: "Team",
            lastVerifiedAt: Date()
        )
        let app = AppRecord(
            originalBundleIdentifier: "com.example.cancel",
            name: "Cancel",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .imported,
            ipaRelativePath: "Original.ipa",
            importedAt: Date()
        )
        await fixture.appStore.replaceRecords([app])
        await fixture.accounts.replaceRecords([account])
        let coordinator = ControllableSigningCoordinator()
        let channel = RefreshInstallChannel(result: .success)
        let viewModel = makeViewModel(
            fixture: fixture,
            installChannel: channel,
            signingCoordinator: coordinator
        )

        await viewModel.beginSigning(for: app, accountID: account.id)
        #expect(await eventually { await coordinator.hasStarted })

        viewModel.cancelSigning()

        #expect(await eventually { await coordinator.hasObservedCancellation })
        let cancellingSession = try #require(viewModel.signingSession)
        #expect(cancellingSession.cancellationRequested)
        #expect(cancellingSession.status == .running(.waitingForChannel))

        await coordinator.finishCancellation()

        #expect(await eventually { viewModel.signingSession == nil })
    }

    @Test
    func accountMarkedNeedsVerificationRemainsSelectableAfterReload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let account = AppleAccountRecord(
            maskedEmail: "o***@example.com",
            accountIdentifier: "offline-account",
            teamID: "TEAM",
            teamName: "Team",
            status: .needsVerification,
            lastVerifiedAt: Date()
        )
        await fixture.accounts.replaceRecords([account])
        let viewModel = makeViewModel(fixture: fixture)

        await viewModel.load(force: true)

        #expect(viewModel.selectableAccounts.map(\.id) == [account.id])
        #expect(viewModel.verifiedAccounts.isEmpty)
        await viewModel.selectActiveAccount(id: account.id)
        #expect(viewModel.activeAccountID == account.id)
    }

    @Test
    func loadPresentsRetryableSelfRegistrationFailure() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let expected = ImportFailure(
            title: "无法登记 Seal",
            reason: "账号存储暂时不可读",
            recovery: "重试",
            code: "SEAL-SELF-REG-001"
        )
        let viewModel = makeViewModel(
            fixture: fixture,
            selfRegistrar: OperationSelfRegistrar(error: expected)
        )

        await viewModel.load()

        #expect(viewModel.alertFailure == expected)
    }

    @Test
    func loadDoesNotPresentFailureForRegistrationCancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let viewModel = makeViewModel(
            fixture: fixture,
            selfRegistrar: OperationSelfRegistrar(error: CancellationError())
        )

        await viewModel.load()

        #expect(viewModel.alertFailure == nil)
    }

    @Test
    func importLeaseRemainsAssociatedWithDraftUntilCancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let viewModel = makeViewModel(fixture: fixture)

        await viewModel.importSelectedFile(source)

        let draft = try #require(viewModel.sheetDraft)
        #expect(await fixture.coordinator.snapshot() == [draft.appID])
        let cleanupLease = try await fixture.coordinator.acquire(appID: nil, kind: .cleaning)
        let cleanupResult = try await fixture.fileStore.clearTemporaryFiles(
            excluding: await fixture.coordinator.snapshot()
        )
        await cleanupLease.release()
        #expect(cleanupResult.skippedAppIDs.contains(draft.appID))
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path))

        await viewModel.cancelImport()

        #expect(await fixture.coordinator.snapshot().isEmpty)
    }

    @Test
    func recoverableImportFailureRetainsLeaseUntilRetryCompletes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        await fixture.appStore.failNextReplacement()
        let viewModel = makeViewModel(fixture: fixture)

        await viewModel.importSelectedFile(source)
        let draft = try #require(viewModel.sheetDraft)
        await viewModel.confirmImport()

        #expect(viewModel.sheetFailure != nil)
        #expect(await fixture.coordinator.snapshot() == [draft.appID])
        let cleanupLease = try await fixture.coordinator.acquire(appID: nil, kind: .cleaning)
        let cleanupResult = try await fixture.fileStore.clearTemporaryFiles(
            excluding: await fixture.coordinator.snapshot()
        )
        await cleanupLease.release()
        #expect(cleanupResult.skippedAppIDs.contains(draft.appID))
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path))

        await viewModel.retryImport()

        #expect(viewModel.sheetDraft == nil)
        #expect(await fixture.coordinator.snapshot().isEmpty)
    }

    @Test
    func postInstallCleanupPreservesFormalSignedIPAsAndAnotherLeasedWorkspace() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let installedID = UUID()
        let activeID = UUID()
        let installedPath = try await fixture.fileStore.storeSignedIPA(
            sourceURL: fixture.source,
            appID: installedID
        )
        let activePath = try await fixture.fileStore.storeSignedIPA(
            sourceURL: fixture.source,
            appID: activeID
        )
        _ = try await fixture.fileStore.signingWorkspace(appID: installedID)
        let activeWorkspace = try await fixture.fileStore.signingWorkspace(appID: activeID)
        await fixture.appStore.replaceRecords([
            makeApp(id: installedID, signedPath: installedPath),
            makeApp(id: activeID, signedPath: activePath)
        ])
        let activeLease = try await fixture.coordinator.acquire(appID: activeID, kind: .signing)
        defer { Task { await activeLease.release() } }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "behavior.deleteIPAAfterInstall")
        defer { defaults.removeObject(forKey: "behavior.deleteIPAAfterInstall") }
        let viewModel = makeViewModel(fixture: fixture)

        await viewModel.cleanTemporaryFilesIfNeeded(appID: installedID)

        #expect(FileManager.default.fileExists(atPath: activeWorkspace.path))
        #expect(try await fixture.fileStore.exists(relativePath: activePath))
        #expect(try await fixture.fileStore.exists(relativePath: installedPath))
        let active = try #require(await fixture.appStore.fetchAll().first { $0.id == activeID })
        #expect(active.signedIPARelativePath == activePath)
    }

    @Test
    func batchPostInstallCleanupPreservesAllFormalSignedIPAsAndMetadata() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let activeID = UUID()
        let idleID = UUID()
        let activePath = try await fixture.fileStore.storeSignedIPA(
            sourceURL: fixture.source,
            appID: activeID
        )
        let idlePath = try await fixture.fileStore.storeSignedIPA(
            sourceURL: fixture.source,
            appID: idleID
        )
        await fixture.appStore.replaceRecords([
            makeApp(id: activeID, signedPath: activePath),
            makeApp(id: idleID, signedPath: idlePath)
        ])
        let activeLease = try await fixture.coordinator.acquire(appID: activeID, kind: .signing)
        defer { Task { await activeLease.release() } }
        UserDefaults.standard.set(true, forKey: "behavior.deleteIPAAfterInstall")
        defer { UserDefaults.standard.removeObject(forKey: "behavior.deleteIPAAfterInstall") }
        let viewModel = makeViewModel(fixture: fixture)

        await viewModel.cleanTemporaryFilesIfNeeded()

        #expect(try await fixture.fileStore.exists(relativePath: activePath))
        #expect(try await fixture.fileStore.exists(relativePath: idlePath))
        let records = await fixture.appStore.fetchAll()
        #expect(records.first { $0.id == activeID }?.signedIPARelativePath == activePath)
        #expect(records.first { $0.id == idleID }?.signedIPARelativePath == idlePath)
    }

    @Test
    func deleteDatabaseFailureRollsBackRemovalTombstone() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = OperationFileRecorder()
        let fileStore = AppFileStore(
            documentsDirectory: root.appending(path: "Documents"),
            cacheDirectory: root.appending(path: "Caches"),
            beforeFileOperation: { recorder.record($0) }
        )
        let appStore = OperationAppStore()
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let app = try await commitImportedApp(
            source: source,
            fileStore: fileStore
        )
        await appStore.replaceRecords([app])
        await appStore.failNextDelete()
        let viewModel = makeViewModel(
            fileStore: fileStore,
            appStore: appStore,
            root: root
        )

        let deleted = await viewModel.delete(app)

        #expect(deleted == false)
        #expect(recorder.operations.contains(.prepareRemoval))
        #expect(recorder.operations.contains(.rollbackRemoval))
        #expect(try await fileStore.exists(relativePath: app.ipaRelativePath))
        #expect(await appStore.fetchAll().contains { $0.id == app.id })
    }

    @Test
    func interruptedDeleteIsFinalizedByRebuiltRecoveryWithoutResurrection() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = AppFileStore(
            documentsDirectory: root.appending(path: "Documents"),
            cacheDirectory: root.appending(path: "Caches"),
            beforeFileOperation: { operation in
                if operation == .finalizeRemoval { throw OperationInjectedFailure.expected }
            }
        )
        let appStore = OperationAppStore()
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let app = try await commitImportedApp(source: source, fileStore: fileStore)
        await appStore.replaceRecords([app])
        let viewModel = makeViewModel(
            fileStore: fileStore,
            appStore: appStore,
            root: root
        )

        #expect(await viewModel.delete(app) == false)
        #expect(await appStore.fetchAll().isEmpty)

        let rebuiltStore = AppFileStore(
            documentsDirectory: root.appending(path: "Documents"),
            cacheDirectory: root.appending(path: "Caches")
        )
        try await AppRecordRecovery(
            appStore: appStore,
            fileStore: rebuiltStore
        ).restoreMissingRecords()

        #expect(await appStore.fetchAll().isEmpty)
        #expect(try await rebuiltStore.exists(relativePath: app.ipaRelativePath) == false)
    }

    private func makeFixture() throws -> (
        root: URL,
        source: URL,
        fileStore: AppFileStore,
        appStore: OperationAppStore,
        accounts: OperationAccountRepository,
        coordinator: AppOperationCoordinator
    ) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppsVMOperationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Signed.ipa")
        try Data("signed".utf8).write(to: source)
        return (
            root,
            source,
            AppFileStore(
                documentsDirectory: root.appending(path: "Documents"),
                cacheDirectory: root.appending(path: "Caches")
            ),
            OperationAppStore(),
            OperationAccountRepository(),
            AppOperationCoordinator()
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppsVMDeleteTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeViewModel(
        fileStore: AppFileStore,
        appStore: OperationAppStore,
        root: URL
    ) -> AppsViewModel {
        AppsViewModel(
            workflow: ImportWorkflow(
                parser: IPAParserService(),
                fileStore: fileStore,
                appStore: appStore
            ),
            appStore: appStore,
            fileStore: fileStore,
            accountRepository: OperationAccountRepository(),
            appRecordRecovery: nil,
            selfAppRegistrar: nil,
            operationCoordinator: AppOperationCoordinator()
        )
    }

    private func commitImportedApp(
        source: URL,
        fileStore: AppFileStore
    ) async throws -> AppRecord {
        let appID = UUID()
        let staged = try await fileStore.stage(sourceURL: source)
        let transaction = try await fileStore.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await fileStore.finalize(transaction)
        return AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.delete",
            name: "Delete",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .imported,
            ipaRelativePath: transaction.files.ipaRelativePath,
            importedAt: Date()
        )
    }

    private func makeViewModel(
        fixture: (
            root: URL,
            source: URL,
            fileStore: AppFileStore,
            appStore: OperationAppStore,
            accounts: OperationAccountRepository,
            coordinator: AppOperationCoordinator
        ),
        selfRegistrar: (any SelfAppRegistering)? = nil,
        installChannel: (any InstallChannel)? = nil,
        signingCoordinator: (any SigningCoordinating)? = nil
    ) -> AppsViewModel {
        AppsViewModel(
            workflow: ImportWorkflow(
                parser: IPAParserService(),
                fileStore: fixture.fileStore,
                appStore: fixture.appStore
            ),
            appStore: fixture.appStore,
            fileStore: fixture.fileStore,
            accountRepository: fixture.accounts,
            appRecordRecovery: nil,
            selfAppRegistrar: selfRegistrar,
            operationCoordinator: fixture.coordinator,
            installChannel: installChannel,
            signingCoordinator: signingCoordinator
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func makeApp(id: UUID, signedPath: String) -> AppRecord {
        AppRecord(
            id: id,
            originalBundleIdentifier: "com.example.\(id.uuidString)",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            expiryDate: Date.distantFuture,
            lastInstalledAt: Date(),
            ipaRelativePath: "Apps/\(id.uuidString)/Original.ipa",
            signedIPARelativePath: signedPath,
            importedAt: Date()
        )
    }
}

private actor RefreshInstallChannel: InstallChannel {
    enum Result: Equatable {
        case success
        case failure
    }

    let result: Result
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(result: Result) { self.result = result }

    func start() async throws -> String {
        startCallCount += 1
        if result == .failure { throw RefreshChannelError.expected }
        return "device"
    }

    func stop() async { stopCallCount += 1 }
    func diagnose() async -> InstallChannelDiagnostics { .empty }
    func isReady() async -> Bool { result == .success }
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async throws {}
    func verifyInstalled(bundleID: String) async throws {}
}

private actor ControllableSigningCoordinator: SigningCoordinating {
    private(set) var hasStarted = false
    private(set) var hasObservedCancellation = false
    private var completion: CheckedContinuation<Void, Never>?

    func signAndInstall(
        appID: UUID,
        accountID: UUID,
        requestedBundleIdentifier: String?,
        selectedCertificateSerialNumber: String?,
        allowDroppingExtensions: Bool,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> AppRecord {
        hasStarted = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion = continuation
            }
        } onCancel: {
            Task { await self.observeCancellation() }
        }
        throw CancellationError()
    }

    func finishCancellation() {
        completion?.resume()
        completion = nil
    }

    private func observeCancellation() {
        hasObservedCancellation = true
    }
}

private enum RefreshChannelError: Error {
    case expected
}

private actor OperationSelfRegistrar: SelfAppRegistering {
    private enum Outcome: Sendable {
        case failure(ImportFailure)
        case cancellation
    }
    private let outcome: Outcome

    init(error: ImportFailure) {
        outcome = .failure(error)
    }

    init(error: CancellationError) {
        outcome = .cancellation
    }

    func ensureRegistered() async throws {
        switch outcome {
        case .failure(let failure): throw failure
        case .cancellation: throw CancellationError()
        }
    }
}

private actor OperationAppStore: AppStore {
    private var records: [AppRecord] = []
    private var shouldFailNextReplacement = false
    private var shouldFailNextDelete = false

    func fetchAll() -> [AppRecord] { records }
    func save(_ record: AppRecord) {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }
    func replaceImportedApp(_ record: AppRecord) throws -> [AppRecord] {
        if shouldFailNextReplacement {
            shouldFailNextReplacement = false
            throw AppStoreError.invalidConfiguration
        }
        records.append(record)
        return []
    }
    func delete(id: UUID) throws {
        if shouldFailNextDelete {
            shouldFailNextDelete = false
            throw OperationInjectedFailure.expected
        }
        records.removeAll { $0.id == id }
    }
    func replaceRecords(_ records: [AppRecord]) { self.records = records }
    func failNextReplacement() { shouldFailNextReplacement = true }
    func failNextDelete() { shouldFailNextDelete = true }
}

private actor OperationAccountRepository: AccountRepository {
    private var records: [AppleAccountRecord] = []

    func fetchAll() -> [AppleAccountRecord] { records }
    func save(_ account: AppleAccountRecord) {
        records.removeAll { $0.id == account.id }
        records.append(account)
    }
    func delete(id: UUID) { records.removeAll { $0.id == id } }
    func replaceRecords(_ records: [AppleAccountRecord]) { self.records = records }
}

private enum OperationInjectedFailure: Error {
    case expected
}

private final class OperationFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AppFileStoreOperation] = []

    var operations: [AppFileStoreOperation] {
        lock.withLock { values }
    }

    func record(_ operation: AppFileStoreOperation) {
        lock.withLock { values.append(operation) }
    }
}
