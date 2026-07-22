import Foundation
import Testing
@testable import Seal

struct SelfAppRegistrarTests {
    @Test
    func preservesTheFirstOriginalBundleIdentifierAcrossSelfUpdates() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal.apps.renewed",
                declaredOriginalBundleIdentifier: "com.mjorb.seal",
                existingOriginalBundleIdentifier: "com.mjorb.seal"
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func usesEmbeddedOriginalBundleIdentifierAfterTheAppContainerChanges() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal.apps.renewed",
                declaredOriginalBundleIdentifier: "com.mjorb.seal",
                existingOriginalBundleIdentifier: nil
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func usesTheCurrentIdentifierOnlyForFirstRegistration() {
        #expect(
            SelfAppBundleIdentity.originalBundleIdentifier(
                currentBundleIdentifier: "com.mjorb.seal",
                declaredOriginalBundleIdentifier: nil,
                existingOriginalBundleIdentifier: nil
            ) == "com.mjorb.seal"
        )
    }

    @Test
    func matchesTheInstalledProfileTeamToTheStoredAccount() {
        let expectedID = UUID()
        let accounts = [
            AppleAccountRecord(
                maskedEmail: "other@icloud.com",
                accountIdentifier: "other",
                teamID: "OTHERTEAM",
                teamName: "Other",
                lastVerifiedAt: .distantPast
            ),
            AppleAccountRecord(
                id: expectedID,
                maskedEmail: "sunuannian1@gmail.com",
                accountIdentifier: "current",
                teamID: "T3432ZHJUF9",
                teamName: "Current",
                lastVerifiedAt: .now
            )
        ]

        #expect(
            SelfAppAccountBinding.matchedAccountID(
                teamIdentifier: "t3432zhjuf9",
                accounts: accounts
            ) == expectedID
        )
    }

    @Test
    func profileTeamWithoutSavedMatchPreservesExistingBinding() {
        let staleAccountID = UUID()

        #expect(
            SelfAppAccountBinding.resolvedAccountID(
                teamIdentifier: "CURRENTTEAM",
                accounts: [],
                fallbackAccountID: staleAccountID
            ) == staleAccountID
        )
    }

    @Test
    func accountReadFailureIsPropagated() async throws {
        let fixture = try makeRegistrarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registrar = SelfAppRegistrar(
            metadata: fixture.metadata,
            appStore: RegistrarAppStore(),
            accountRepository: RegistrarAccountRepository(fetchError: .expected),
            fileStore: fixture.fileStore
        )

        await #expect(throws: RegistrarTestError.self) {
            try await registrar.ensureRegistered()
        }
    }

    @Test
    func preservesExistingBindingAndInstallMetadataWhenProfileTeamHasNoMatch() async throws {
        let fixture = try makeRegistrarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let appID = UUID()
        let source = try IPAArchiveFixture.make(apps: [
            .init(bundleIdentifier: fixture.metadata.bundleIdentifier)
        ])
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let staged = try await fixture.fileStore.stage(sourceURL: source)
        let transaction = try await fixture.fileStore.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await fixture.fileStore.finalize(transaction)
        let signedPath = try await fixture.fileStore.storeSignedIPA(
            sourceURL: source,
            appID: appID
        )
        let accountID = UUID()
        let installedAt = Date(timeIntervalSince1970: 1_000)
        let expiry = Date(timeIntervalSince1970: 2_000)
        let existing = AppRecord(
            id: appID,
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: fixture.metadata.bundleIdentifier,
            name: "Seal",
            version: "0.9",
            buildNumber: "9",
            size: 10,
            state: .installed,
            expiryDate: expiry,
            accountID: accountID,
            signingTeamID: "EXISTINGTEAM",
            certificateSerialNumber: "CERTIFICATE",
            lastInstalledAt: installedAt,
            ipaRelativePath: transaction.files.ipaRelativePath,
            signedIPARelativePath: signedPath,
            preferredBundleIdentifier: fixture.metadata.bundleIdentifier,
            isSeal: true,
            isPinned: true,
            importedAt: Date(timeIntervalSince1970: 100)
        )
        let appStore = RegistrarAppStore(records: [existing])
        let registrar = SelfAppRegistrar(
            metadata: fixture.metadata,
            appStore: appStore,
            accountRepository: RegistrarAccountRepository(),
            fileStore: fixture.fileStore
        )

        try await registrar.ensureRegistered()

        let updated = try #require(await appStore.fetchAll().first)
        #expect(updated.accountID == accountID)
        #expect(updated.lastInstalledAt == installedAt)
        #expect(updated.expiryDate == expiry)
        #expect(updated.signedIPARelativePath == signedPath)
        #expect(updated.certificateSerialNumber == "CERTIFICATE")
        #expect(updated.signingTeamID == "EXISTINGTEAM")
        #expect(try await fixture.fileStore.exists(relativePath: signedPath))
    }

    @Test
    func duplicateSealFilesAreRemovedAndRecoveryCannotRecreateRecord() async throws {
        let fixture = try makeRegistrarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let currentID = UUID()
        let duplicateID = UUID()
        let currentSource = try IPAArchiveFixture.make(apps: [
            .init(bundleIdentifier: fixture.metadata.bundleIdentifier)
        ])
        let duplicateSource = try IPAArchiveFixture.make(apps: [
            .init(bundleIdentifier: "com.example.legacy-seal")
        ])
        defer { try? FileManager.default.removeItem(at: currentSource.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: duplicateSource.deletingLastPathComponent()) }
        let currentFiles = try await commit(
            currentSource,
            appID: currentID,
            fileStore: fixture.fileStore
        )
        let duplicateFiles = try await commit(
            duplicateSource,
            appID: duplicateID,
            fileStore: fixture.fileStore
        )
        let current = makeSealRecord(
            id: currentID,
            bundleIdentifier: fixture.metadata.bundleIdentifier,
            files: currentFiles
        )
        let duplicate = makeSealRecord(
            id: duplicateID,
            bundleIdentifier: "com.example.legacy-seal",
            files: duplicateFiles
        )
        let appStore = RegistrarAppStore(records: [current, duplicate])
        let registrar = SelfAppRegistrar(
            metadata: fixture.metadata,
            appStore: appStore,
            accountRepository: RegistrarAccountRepository(),
            fileStore: fixture.fileStore
        )

        try await registrar.ensureRegistered()
        try await AppRecordRecovery(
            appStore: appStore,
            fileStore: fixture.fileStore
        ).restoreMissingRecords()

        let records = await appStore.fetchAll()
        #expect(records.map(\.id) == [currentID])
        #expect(try await fixture.fileStore.exists(relativePath: duplicateFiles.ipaRelativePath) == false)
    }

    @Test
    func duplicateDeleteFailureRollsBackFilesAndRetryDoesNotFinalizeMainTransactionTwice() async throws {
        let fixture = try makeRegistrarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let currentID = UUID()
        let duplicateID = UUID()
        let currentSource = try IPAArchiveFixture.make(apps: [
            .init(bundleIdentifier: fixture.metadata.bundleIdentifier)
        ])
        let duplicateSource = try IPAArchiveFixture.make(apps: [
            .init(bundleIdentifier: "com.example.duplicate")
        ])
        defer { try? FileManager.default.removeItem(at: currentSource.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: duplicateSource.deletingLastPathComponent()) }
        let currentFiles = try await commit(currentSource, appID: currentID, fileStore: fixture.fileStore)
        let duplicateFiles = try await commit(duplicateSource, appID: duplicateID, fileStore: fixture.fileStore)
        let appStore = RegistrarAppStore(
            records: [
                makeSealRecord(
                    id: currentID,
                    bundleIdentifier: fixture.metadata.bundleIdentifier,
                    files: currentFiles
                ),
                makeSealRecord(
                    id: duplicateID,
                    bundleIdentifier: "com.example.duplicate",
                    files: duplicateFiles
                )
            ],
            failDeleteOnceFor: duplicateID
        )
        let registrar = SelfAppRegistrar(
            metadata: fixture.metadata,
            appStore: appStore,
            accountRepository: RegistrarAccountRepository(),
            fileStore: fixture.fileStore
        )

        await #expect(throws: RegistrarTestError.self) {
            try await registrar.ensureRegistered()
        }
        #expect(try await fixture.fileStore.exists(relativePath: duplicateFiles.ipaRelativePath))

        try await registrar.ensureRegistered()

        #expect(await appStore.fetchAll().map(\.id) == [currentID])
        #expect(try await fixture.fileStore.exists(relativePath: duplicateFiles.ipaRelativePath) == false)
    }

    @Test
    func missingProfileTeamFallsBackToStoredAccount() {
        let storedAccountID = UUID()

        #expect(
            SelfAppAccountBinding.resolvedAccountID(
                teamIdentifier: nil,
                accounts: [],
                fallbackAccountID: storedAccountID
            ) == storedAccountID
        )
    }

    @Test
    func doesNotReuseAnUnrelatedLegacySealRecord() {
        let stale = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.dmj",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/stale.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.dmj",
            isSeal: true,
            importedAt: .distantPast
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [stale],
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9"
            ) == nil
        )
    }

    @Test
    func originalIdentifierDoesNotOverrideAStaleInstalledIdentifier() {
        let stale = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.dmj",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/stale.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.dmj",
            isSeal: true,
            importedAt: .distantPast
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [stale],
                currentBundleIdentifier: "com.mjorb.seal"
            ) == nil
        )
    }

    @Test
    func reusesTheRecordThatMatchesTheCurrentInstalledBundleIdentifier() {
        let matching = AppRecord(
            originalBundleIdentifier: "com.mjorb.seal",
            mappedBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            name: "Seal",
            version: "1.0",
            buildNumber: "1",
            size: 1,
            state: .installed,
            accountID: UUID(),
            ipaRelativePath: "Apps/current.ipa",
            preferredBundleIdentifier: "com.mjorb.seal.t3432zhjuf9",
            isSeal: true,
            importedAt: .now
        )

        #expect(
            SelfAppRecordSelection.preferredExistingSealRecord(
                in: [matching],
                currentBundleIdentifier: "com.mjorb.seal.t3432zhjuf9"
            )?.id == matching.id
        )
    }

    private func makeRegistrarFixture() throws -> (
        root: URL,
        metadata: SelfAppMetadata,
        fileStore: AppFileStore
    ) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SelfRegistrarTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let bundle = root.appending(path: "RunningSeal.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("running seal".utf8).write(to: bundle.appending(path: "Seal"))
        return (
            root,
            SelfAppMetadata(
                bundleURL: bundle,
                bundleIdentifier: "com.mjorb.seal.current",
                originalBundleIdentifier: "com.mjorb.seal",
                name: "Seal",
                version: "1.0",
                buildNumber: "10",
                iconData: nil,
                expirationDate: nil,
                signingTeamIdentifier: "UNMATCHEDTEAM",
                signingApplicationIdentifier: nil
            ),
            AppFileStore(
                documentsDirectory: root.appending(path: "Documents"),
                cacheDirectory: root.appending(path: "Caches")
            )
        )
    }

    private func commit(
        _ source: URL,
        appID: UUID,
        fileStore: AppFileStore
    ) async throws -> StoredAppFiles {
        let staged = try await fileStore.stage(sourceURL: source)
        let transaction = try await fileStore.prepareCommit(
            staged: staged,
            appID: appID,
            iconData: nil
        )
        try await fileStore.finalize(transaction)
        return transaction.files
    }

    private func makeSealRecord(
        id: UUID,
        bundleIdentifier: String,
        files: StoredAppFiles
    ) -> AppRecord {
        AppRecord(
            id: id,
            originalBundleIdentifier: bundleIdentifier,
            mappedBundleIdentifier: bundleIdentifier,
            name: "Seal",
            version: "0.9",
            buildNumber: "9",
            size: 1,
            state: .installed,
            ipaRelativePath: files.ipaRelativePath,
            preferredBundleIdentifier: bundleIdentifier,
            isSeal: true,
            isPinned: true,
            importedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private enum RegistrarTestError: Error {
    case expected
}

private actor RegistrarAccountRepository: AccountRepository {
    private let accounts: [AppleAccountRecord]
    private let fetchError: RegistrarTestError?

    init(
        accounts: [AppleAccountRecord] = [],
        fetchError: RegistrarTestError? = nil
    ) {
        self.accounts = accounts
        self.fetchError = fetchError
    }

    func fetchAll() throws -> [AppleAccountRecord] {
        if let fetchError { throw fetchError }
        return accounts
    }

    func save(_ account: AppleAccountRecord) {}
    func delete(id: UUID) {}
}

private actor RegistrarAppStore: AppStore {
    private var records: [AppRecord]
    private var failDeleteOnceFor: UUID?

    init(records: [AppRecord] = [], failDeleteOnceFor: UUID? = nil) {
        self.records = records
        self.failDeleteOnceFor = failDeleteOnceFor
    }

    func fetchAll() -> [AppRecord] { records }

    func save(_ record: AppRecord) {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func replaceImportedApp(_ record: AppRecord) -> [AppRecord] {
        let replaced = records.filter {
            $0.originalBundleIdentifier == record.originalBundleIdentifier
        }
        records.removeAll {
            $0.originalBundleIdentifier == record.originalBundleIdentifier
        }
        records.append(record)
        return replaced
    }

    func delete(id: UUID) throws {
        if failDeleteOnceFor == id {
            failDeleteOnceFor = nil
            throw RegistrarTestError.expected
        }
        records.removeAll { $0.id == id }
    }
}
