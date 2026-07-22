import Foundation
import Dispatch
import Testing
@testable import Seal

struct ImportWorkflowTests {
    @Test
    func preparesParsedDraftForConfirmation() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make(includeShareExtension: true)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let workflow = makeWorkflow(environment: environment)
        await workflow.prepare(sourceURL: source)

        let draft = try requireDraft(await workflow.state)
        #expect(draft.parsedIPA.name == "Demo")
        #expect(draft.parsedIPA.extensions.count == 1)
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path))
    }

    @Test
    func confirmationCommitsFilesAndRecord() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let appID = UUID()
        let workflow = makeWorkflow(environment: environment, appID: appID)

        await workflow.prepare(sourceURL: source)
        await workflow.confirm()

        let record = try requireCompleted(await workflow.state)
        #expect(record.id == appID)
        #expect(record.state == .imported)
        #expect(record.ipaRelativePath == "Apps/\(appID.uuidString)/Original.ipa")
        #expect(try await environment.appStore.fetchAll() == [record])
        #expect(FileManager.default.fileExists(
            atPath: environment.documents.appending(path: record.ipaRelativePath).path
        ))
    }

    @Test
    func cancellationRemovesPreparedDraft() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let workflow = makeWorkflow(environment: environment)

        await workflow.prepare(sourceURL: source)
        let draft = try requireDraft(await workflow.state)
        await workflow.cancel()

        #expect(await workflow.state == .idle)
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path) == false)
    }

    @Test
    func parserFailureCleansStagedFileAndKeepsRecoveryCopyShort() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make(apps: [.init(malformedInfo: true)])
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let workflow = makeWorkflow(environment: environment)

        await workflow.prepare(sourceURL: source)

        let failure = try requireFailure(await workflow.state)
        #expect(failure.code == "SEAL-IPA-102")
        #expect(failure.recovery == "选择其他 IPA")
        let temporaryRoot = environment.cache.appending(
            path: "Seal/Temp",
            directoryHint: .isDirectory
        )
        let remaining = try FileManager.default.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: nil
        )
        #expect(remaining.isEmpty)
    }

    @Test
    func persistenceFailureCanRetryWithoutReselectingIPA() async throws {
        let environment = try makeEnvironment(appStore: FailOnceAppStore())
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let appID = UUID()
        let workflow = makeWorkflow(environment: environment, appID: appID)

        await workflow.prepare(sourceURL: source)
        let draft = try requireDraft(await workflow.state)
        await workflow.confirm()
        let failure = try requireFailure(await workflow.state)
        #expect(failure.code == "SEAL-IPA-205")
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path))
        #expect(FileManager.default.fileExists(
            atPath: environment.documents
                .appending(path: "Apps/\(appID.uuidString)/Original.ipa")
                .path
        ) == false)

        await workflow.retry()

        _ = try requireCompleted(await workflow.state)
        let records = try await environment.appStore.fetchAll()
        #expect(records.count == 1)
        #expect(FileManager.default.fileExists(atPath: draft.stagedIPA.url.path) == false)
    }

    @Test
    func replacementSaveFailureRestoresPreviousIPAAndIconWithoutLeavingBackup() async throws {
        let failingStore = FailOnceAppStore()
        let environment = try makeEnvironment(appStore: failingStore)
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let appID = UUID()
        let oldIPAData = Data("old ipa".utf8)
        let oldIconData = Data("old icon".utf8)
        let oldRecord = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Old Demo",
            version: "0.9",
            buildNumber: "1",
            size: Int64(oldIPAData.count),
            iconRelativePath: "Apps/\(appID.uuidString)/Icon.png",
            state: .imported,
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let oldIPAURL = environment.documents.appending(path: oldRecord.ipaRelativePath)
        let oldIconURL = environment.documents.appending(path: oldRecord.iconRelativePath!)
        try FileManager.default.createDirectory(
            at: oldIPAURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try oldIPAData.write(to: oldIPAURL, options: .atomic)
        try oldIconData.write(to: oldIconURL, options: .atomic)
        try await failingStore.save(oldRecord)
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let workflow = makeWorkflow(environment: environment, appID: UUID())

        await workflow.prepare(sourceURL: source)
        await workflow.confirm()

        let failure = try requireFailure(await workflow.state)
        #expect(failure.code == "SEAL-IPA-205")
        #expect(try Data(contentsOf: oldIPAURL) == oldIPAData)
        #expect(try Data(contentsOf: oldIconURL) == oldIconData)
        let appsRoot = environment.documents.appending(path: "Apps", directoryHint: .isDirectory)
        let hiddenEntries = try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".") }
        #expect(hiddenEntries.isEmpty)
        #expect(try await failingStore.fetchAll() == [oldRecord])
    }

    @Test
    func successfulReplacementFinalizesWithoutLeavingBackup() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let appID = UUID()
        let oldData = Data("old ipa".utf8)
        let oldRecord = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Old Demo",
            version: "0.9",
            buildNumber: "1",
            size: Int64(oldData.count),
            state: .imported,
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let oldIPAURL = environment.documents.appending(path: oldRecord.ipaRelativePath)
        try FileManager.default.createDirectory(
            at: oldIPAURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try oldData.write(to: oldIPAURL, options: .atomic)
        try await environment.appStore.save(oldRecord)
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let workflow = makeWorkflow(environment: environment, appID: UUID())

        await workflow.prepare(sourceURL: source)
        await workflow.confirm()

        let completed = try requireCompleted(await workflow.state)
        #expect(completed.id == appID)
        #expect(try Data(contentsOf: oldIPAURL) != oldData)
        let appsRoot = environment.documents.appending(path: "Apps", directoryHint: .isDirectory)
        let hiddenEntries = try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".") }
        #expect(hiddenEntries.isEmpty)
    }

    @Test
    func cancelInvalidatesSuspendedCommitBeforeItCanWriteDatabaseOrFiles() async throws {
        let gate = BlockingPersistenceGate()
        let appStore = try CoreDataAppStore(
            inMemory: true,
            beforeSave: { operation in
                guard operation == .replaceImportedApp else { return }
                gate.suspendUntilResumed()
            }
        )
        let environment = try makeEnvironment(appStore: appStore)
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let appID = UUID()
        let oldData = Data("old ipa".utf8)
        let oldRecord = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            name: "Old Demo",
            version: "0.9",
            buildNumber: "1",
            size: Int64(oldData.count),
            state: .imported,
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let oldIPAURL = environment.documents.appending(path: oldRecord.ipaRelativePath)
        try FileManager.default.createDirectory(
            at: oldIPAURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try oldData.write(to: oldIPAURL, options: .atomic)
        try await appStore.save(oldRecord)
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let workflow = makeWorkflow(environment: environment, appID: UUID())
        await workflow.prepare(sourceURL: source)

        let confirmation = Task { await workflow.confirm() }
        gate.waitUntilSuspended()
        await workflow.cancel()
        gate.resume()
        await confirmation.value

        #expect(await workflow.state == .idle)
        #expect(try await appStore.fetchAll() == [oldRecord])
        #expect(try Data(contentsOf: oldIPAURL) == oldData)
        let appsRoot = environment.documents.appending(path: "Apps", directoryHint: .isDirectory)
        let hiddenEntries = try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".") }
        #expect(hiddenEntries.isEmpty)
    }

    @Test
    func duplicateBundleIdentifierIsReplacedAtomically() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let oldRecord = AppRecord(
            originalBundleIdentifier: "com.Example.Demo",
            name: "Old Demo",
            version: "0.9",
            buildNumber: "1",
            size: 10,
            state: .imported,
            ipaRelativePath: "Apps/old/Original.ipa",
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let oldIPA = environment.documents.appending(path: oldRecord.ipaRelativePath)
        try FileManager.default.createDirectory(
            at: oldIPA.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old".utf8).write(to: oldIPA)
        try await environment.appStore.save(oldRecord)
        let source = try IPAArchiveFixture.make()
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let newID = UUID()
        let workflow = makeWorkflow(environment: environment, appID: newID)

        await workflow.prepare(sourceURL: source)
        await workflow.confirm()

        let records = try await environment.appStore.fetchAll()
        #expect(records.count == 1)
        #expect(records.first?.id == oldRecord.id)
        #expect(records.first?.name == "Demo")
        #expect(FileManager.default.fileExists(atPath: oldIPA.path) == false)
    }

    private func makeWorkflow(
        environment: Environment,
        appID: UUID = UUID()
    ) -> ImportWorkflow {
        ImportWorkflow(
            parser: IPAParserService(),
            fileStore: environment.fileStore,
            appStore: environment.appStore,
            now: { Date(timeIntervalSince1970: 1_750_000_000) },
            makeID: { appID }
        )
    }

    private func makeEnvironment(
        appStore: (any AppStore)? = nil
    ) throws -> Environment {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SealWorkflowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let cache = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let resolvedAppStore: any AppStore
        if let appStore {
            resolvedAppStore = appStore
        } else {
            resolvedAppStore = try CoreDataAppStore(inMemory: true)
        }

        return Environment(
            root: root,
            documents: documents,
            cache: cache,
            fileStore: AppFileStore(
                documentsDirectory: documents,
                cacheDirectory: cache
            ),
            appStore: resolvedAppStore
        )
    }

    private func requireDraft(
        _ state: ImportWorkflowState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ImportDraft {
        guard case .awaitingConfirmation(let draft) = state else {
            Issue.record("Expected confirmation state, got \(state).", sourceLocation: sourceLocation)
            throw TestFailure.unexpectedState
        }
        return draft
    }

    private func requireCompleted(
        _ state: ImportWorkflowState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> AppRecord {
        guard case .completed(let record) = state else {
            Issue.record("Expected completed state, got \(state).", sourceLocation: sourceLocation)
            throw TestFailure.unexpectedState
        }
        return record
    }

    private func requireFailure(
        _ state: ImportWorkflowState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ImportFailure {
        guard case .failed(let failure) = state else {
            Issue.record("Expected failed state, got \(state).", sourceLocation: sourceLocation)
            throw TestFailure.unexpectedState
        }
        return failure
    }
}

private final class BlockingPersistenceGate: @unchecked Sendable {
    private let suspended = DispatchSemaphore(value: 0)
    private let resumed = DispatchSemaphore(value: 0)

    func suspendUntilResumed() {
        suspended.signal()
        resumed.wait()
    }

    func waitUntilSuspended() {
        suspended.wait()
    }

    func resume() {
        resumed.signal()
    }
}

private extension ImportWorkflowTests {
    struct Environment {
        let root: URL
        let documents: URL
        let cache: URL
        let fileStore: AppFileStore
        let appStore: any AppStore
    }

    enum TestFailure: Error {
        case unexpectedState
    }
}
