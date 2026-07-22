import Foundation
import Testing
@testable import Seal

struct SigningCoordinatorTests {
    @Test
    func signingSessionExposesCancellationRequestedWithoutChangingStage() {
        let app = AppRecord(
            originalBundleIdentifier: "com.example.cancel",
            name: "Cancel",
            version: "1",
            buildNumber: "1",
            size: 1,
            state: .signing,
            ipaRelativePath: "Original.ipa",
            importedAt: Date()
        )
        let account = AppleAccountRecord(
            maskedEmail: "c***@example.com",
            accountIdentifier: "account",
            teamID: "TEAM",
            teamName: "Team",
            lastVerifiedAt: Date()
        )
        var session = SigningSession(
            app: app,
            account: account,
            status: .running(.signing)
        )

        #expect(session.cancellationRequested == false)
        session.cancellationRequested = true
        #expect(session.cancellationRequested)
        #expect(session.status == .running(.signing))
    }

    @Test
    func validSignedIPAInstallsWithoutCallingPortalAndStopsChannel() async throws {
        let fixture = try await makeFixture(cacheState: .valid)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let installed = try await fixture.coordinator.signAndInstall(
            appID: fixture.app.id,
            accountID: fixture.account.id,
            progress: { _ in }
        )

        #expect(installed.state == .installed)
        #expect(await fixture.portal.callCount == 0)
        #expect(await fixture.channel.installCallCount == 1)
        #expect(await fixture.channel.stopCallCount == 1)
    }

    @Test
    func missingCachedFileFallsBackToPortalAndStopsChannel() async throws {
        let fixture = try await makeFixture(cacheState: .missingFile)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        await #expect(throws: PortalProbeError.self) {
            _ = try await fixture.coordinator.signAndInstall(
                appID: fixture.app.id,
                accountID: fixture.account.id,
                progress: { _ in }
            )
        }

        #expect(await fixture.portal.callCount == 1)
        #expect(await fixture.channel.installCallCount == 0)
        #expect(await fixture.channel.stopCallCount == 1)
    }

    @Test
    func expiredOrMismatchedMetadataFallsBackToPortal() async throws {
        for cacheState in [CacheState.expired, .mismatchedDevice, .mismatchedCertificate] {
            let fixture = try await makeFixture(cacheState: cacheState)
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            await #expect(throws: PortalProbeError.self) {
                _ = try await fixture.coordinator.signAndInstall(
                    appID: fixture.app.id,
                    accountID: fixture.account.id,
                    progress: { _ in }
                )
            }
            #expect(await fixture.portal.callCount == 1)
            #expect(await fixture.channel.stopCallCount == 1)
        }
    }

    @Test
    func cancellationRemainsCancellationAndStopsChannel() async throws {
        let fixture = try await makeFixture(cacheState: .valid)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.channel.setInstallError(CancellationError())

        do {
            _ = try await fixture.coordinator.signAndInstall(
                appID: fixture.app.id,
                accountID: fixture.account.id,
                progress: { _ in }
            )
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }

        #expect(await fixture.portal.callCount == 0)
        #expect(await fixture.channel.stopCallCount == 1)
    }

    @Test
    func sameAppLeaseCannotBeReentered() async throws {
        let gate = StartGate()
        let fixture = try await makeFixture(cacheState: .valid, startGate: gate)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = Task {
            try await fixture.coordinator.signAndInstall(
                appID: fixture.app.id,
                accountID: fixture.account.id,
                progress: { _ in }
            )
        }
        await gate.waitUntilEntered()

        do {
            _ = try await fixture.coordinator.signAndInstall(
                appID: fixture.app.id,
                accountID: fixture.account.id,
                progress: { _ in }
            )
            Issue.record("Expected operation lease conflict")
        } catch {
            #expect(error as? AppOperationCoordinator.AcquisitionError == .busy)
        }

        await gate.release()
        _ = try await first.value
        #expect(await fixture.channel.installCallCount == 1)
    }

    private func makeFixture(
        cacheState: CacheState,
        startGate: StartGate? = nil
    ) async throws -> SigningFixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SigningCoordinatorTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let documents = root.appending(path: "Documents")
        let cache = root.appending(path: "Caches")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileStore = AppFileStore(
            documentsDirectory: documents,
            cacheDirectory: cache
        )
        let account = AppleAccountRecord(
            maskedEmail: "t***@example.com",
            accountIdentifier: "account",
            teamID: "TEAM",
            teamName: "Team",
            certificateSerialNumber: "CERT",
            selectedCertificateSerialNumber: "CERT",
            lastVerifiedAt: Date()
        )
        let appID = UUID()
        let signedPath = "Apps/\(appID.uuidString)/Signed.ipa"
        let appDirectory = documents.appending(
            path: "Apps/\(appID.uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )
        try Data("original".utf8).write(
            to: appDirectory.appending(path: "Original.ipa")
        )
        let app = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.example.demo",
            mappedBundleIdentifier: "com.example.demo.seal",
            name: "Demo",
            version: "1.0",
            buildNumber: "1",
            size: 6,
            state: .waitingForInstallChannel,
            accountID: account.id,
            signingTeamID: account.teamID,
            certificateSerialNumber: cacheState == .mismatchedCertificate ? "OTHER" : "CERT",
            signedDeviceIdentifier: cacheState == .mismatchedDevice ? "other-device" : "device",
            provisioningProfileExpirationDate: cacheState == .expired
                ? Date().addingTimeInterval(-60)
                : Date().addingTimeInterval(3_600),
            ipaRelativePath: "Apps/\(appID.uuidString)/Original.ipa",
            signedIPARelativePath: signedPath,
            preferredBundleIdentifier: "com.example.demo.seal",
            importedAt: Date()
        )
        if cacheState != .missingFile {
            try await fileStore.restoreSignedIPA(
                Data("signed".utf8),
                relativePath: signedPath,
                appID: appID
            )
        }
        let appStore = SigningAppStore(app: app)
        let accounts = SigningAccountStore(account: account)
        let secrets = SigningSecretStore(
            secret: AccountSecret(
                email: "test@example.com",
                accountIdentifier: account.accountIdentifier,
                dsid: "dsid",
                authToken: "token"
            )
        )
        let channel = SigningInstallChannel(startGate: startGate)
        let portal = PortalProbe()
        let coordinator = SigningCoordinator(
            appStore: appStore,
            accountRepository: accounts,
            keychain: secrets,
            fileStore: fileStore,
            installChannel: channel,
            portal: portal,
            operationCoordinator: AppOperationCoordinator()
        )
        return SigningFixture(
            root: root,
            app: app,
            account: account,
            channel: channel,
            portal: portal,
            coordinator: coordinator
        )
    }
}

private enum CacheState: Equatable {
    case valid
    case missingFile
    case expired
    case mismatchedDevice
    case mismatchedCertificate
}

private struct SigningFixture {
    let root: URL
    let app: AppRecord
    let account: AppleAccountRecord
    let channel: SigningInstallChannel
    let portal: PortalProbe
    let coordinator: SigningCoordinator
}

private actor SigningAppStore: AppStore {
    private var app: AppRecord

    init(app: AppRecord) { self.app = app }
    func fetchAll() -> [AppRecord] { [app] }
    func save(_ record: AppRecord) { app = record }
    func replaceImportedApp(_ record: AppRecord) -> [AppRecord] { app = record; return [] }
    func delete(id: UUID) {}
}

private actor SigningAccountStore: AccountRepository {
    private var account: AppleAccountRecord

    init(account: AppleAccountRecord) { self.account = account }
    func fetchAll() -> [AppleAccountRecord] { [account] }
    func save(_ account: AppleAccountRecord) { self.account = account }
    func delete(id: UUID) {}
}

private actor SigningSecretStore: AccountSecretStoring {
    private var secret: AccountSecret?

    init(secret: AccountSecret) { self.secret = secret }
    func save(_ secret: AccountSecret, for accountID: UUID) { self.secret = secret }
    func load(accountID: UUID) -> AccountSecret? { secret }
    func delete(accountID: UUID) { secret = nil }
    func clearSigningMaterial(accountID: UUID) {
        secret?.certificateP12 = nil
        secret?.certificateSerialNumber = nil
        secret?.certificateMachineIdentifier = nil
    }
}

private actor SigningInstallChannel: InstallChannel {
    private let startGate: StartGate?
    private var installError: Error?
    private(set) var installCallCount = 0
    private(set) var stopCallCount = 0

    init(startGate: StartGate?) { self.startGate = startGate }

    func setInstallError(_ error: Error) { installError = error }
    func start() async -> String {
        if let startGate { await startGate.enter() }
        return "device"
    }
    func stop() async { stopCallCount += 1 }
    func diagnose() async -> InstallChannelDiagnostics { .empty }
    func isReady() async -> Bool { true }
    func install(ipaData: Data, bundleID: String, isSelfReplacement: Bool) async throws {
        installCallCount += 1
        if let installError { throw installError }
    }
    func verifyInstalled(bundleID: String) async {}
}

private actor PortalProbe: SigningPortal {
    private(set) var callCount = 0

    func sign(
        app: AppRecord,
        account: AppleAccountRecord,
        secret: AccountSecret,
        deviceIdentifier: String,
        originalIPAURL: URL,
        workspaceRoot: URL,
        targetBundleIdentifier: String?,
        selectedCertificateSerialNumber: String?,
        allowDroppingExtensions: Bool,
        persistSigningMaterial: @escaping @Sendable (AccountSecret, String) async throws -> Void,
        progress: @Sendable (SigningStage) async -> Void
    ) async throws -> PortalSigningResult {
        callCount += 1
        throw PortalProbeError.invoked
    }
}

private enum PortalProbeError: Error {
    case invoked
}

private actor StartGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
