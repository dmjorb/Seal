import Foundation
import Testing
@testable import Seal

struct SigningCoordinatorSignedArtifactTests {
    @Test
    func installsPersistedSignedArtifactWithoutRunningSigningAgain() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let appID = UUID()
        let source = environment.root.appending(path: "AlreadySigned.ipa")
        try Data("signed-ipa-payload".utf8).write(to: source)
        let signedPath = try await environment.fileStore.storeSignedIPA(sourceURL: source, appID: appID)
        let sha = try await environment.fileStore.sha256(relativePath: signedPath)
        let expiration = Date().addingTimeInterval(3 * 86_400)
        let app = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: "com.example.demo.seal",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 18,
            state: .signed,
            signedDeviceIdentifier: "DEVICE-1",
            provisioningProfileExpirationDate: expiration,
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            signedIPARelativePath: signedPath,
            signedIPASHA256: sha,
            signedArtifactStatus: .available,
            preferredBundleIdentifier: "com.example.demo.seal",
            importedAt: Date()
        )
        try await environment.appStore.save(app)

        let coordinator = SigningCoordinator(
            appStore: environment.appStore,
            accountRepository: environment.accountRepository,
            keychain: KeychainVault(),
            fileStore: environment.fileStore,
            installChannel: environment.installChannel
        )
        let result = try await coordinator.installSignedArtifact(appID: appID) { _ in }

        #expect(result.state == .installed)
        #expect(result.signedArtifactStatus == .installed)
        #expect(result.mappedBundleIdentifier == "com.example.demo.seal")
        #expect(await environment.installChannel.installCount == 1)
        #expect(await environment.installChannel.verifyCount == 1)
    }

    @Test
    func missingSignedFileIsKeptAsRecordAndMarkedMissing() async throws {
        let environment = try makeEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.root) }
        let appID = UUID()
        let app = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: "com.example.demo.seal",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 18,
            state: .signed,
            signedDeviceIdentifier: "DEVICE-1",
            provisioningProfileExpirationDate: Date().addingTimeInterval(86_400),
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            signedIPARelativePath: "Apps/\(appID.uuidString)/Signed.ipa",
            signedIPASHA256: String(repeating: "a", count: 64),
            signedArtifactStatus: .available,
            preferredBundleIdentifier: "com.example.demo.seal",
            importedAt: Date()
        )
        try await environment.appStore.save(app)
        let coordinator = SigningCoordinator(
            appStore: environment.appStore,
            accountRepository: environment.accountRepository,
            keychain: KeychainVault(),
            fileStore: environment.fileStore,
            installChannel: environment.installChannel
        )

        do {
            _ = try await coordinator.installSignedArtifact(appID: appID) { _ in }
            Issue.record("Expected missing signed artifact failure")
        } catch let failure as ImportFailure {
            #expect(failure.code == "SEAL-INSTALL-711")
        }
        let records = try await environment.appStore.fetchAll()
        let stored = try #require(records.first { $0.id == appID })
        #expect(stored.state == .signed)
        #expect(stored.signedArtifactStatus == .missing)
    }

    private func makeEnvironment() throws -> Environment {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SealSignedArtifactTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        let cache = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let appStore = try CoreDataAppStore(inMemory: true)
        let accountRepository = ProtectedAccountRepository(
            fileURL: root.appending(path: "Accounts.json"),
            fileProtector: MarkerFileProtector()
        )
        return Environment(
            root: root,
            fileStore: AppFileStore(documentsDirectory: documents, cacheDirectory: cache),
            appStore: appStore,
            accountRepository: accountRepository,
            installChannel: SignedArtifactInstallChannel()
        )
    }
}

private extension SigningCoordinatorSignedArtifactTests {
    struct Environment {
        let root: URL
        let fileStore: AppFileStore
        let appStore: CoreDataAppStore
        let accountRepository: ProtectedAccountRepository
        let installChannel: SignedArtifactInstallChannel
    }
}

private actor SignedArtifactInstallChannel: InstallChannel {
    private(set) var installCount = 0
    private(set) var verifyCount = 0

    func start() async throws -> String { "DEVICE-1" }
    func diagnose() async -> InstallChannelDiagnostics { .empty }
    func isReady() async -> Bool { true }
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async throws {
        installCount += 1
    }
    func verifyInstalled(bundleID: String) async throws {
        verifyCount += 1
    }
}
