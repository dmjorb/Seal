import Foundation
import ZIPFoundation

actor SelfAppRegistrar {
    private let metadata: SelfAppMetadata
    private let appStore: any AppStore
    private let accountRepository: any AccountRepository
    private let fileStore: AppFileStore

    init(
        metadata: SelfAppMetadata,
        appStore: any AppStore,
        accountRepository: any AccountRepository,
        fileStore: AppFileStore
    ) {
        self.metadata = metadata
        self.appStore = appStore
        self.accountRepository = accountRepository
        self.fileStore = fileStore
    }

    func ensureRegistered() async throws {
        let records = try await appStore.fetchAll()
        let accounts = (try? await accountRepository.fetchAll()) ?? []
        let existing = SelfAppRecordSelection.preferredExistingSealRecord(
            in: records,
            currentBundleIdentifier: metadata.bundleIdentifier
        )
        let resolvedAccountID = SelfAppAccountBinding.resolvedAccountID(
            teamIdentifier: metadata.signingTeamIdentifier,
            accounts: accounts,
            fallbackAccountID: existing?.accountID
        )
        let id = existing?.id ?? UUID()
        let workspace = try await fileStore.signingWorkspace(appID: UUID())
        defer { try? FileManager.default.removeItem(at: workspace) }
        let payload = workspace.appending(path: "Payload", directoryHint: .isDirectory)
        let appURL = payload.appending(
            path: "\(metadata.name).app",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: payload,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: metadata.bundleURL, to: appURL)
        let ipaURL = workspace.appending(path: "Seal.ipa")
        try FileManager.default.zipItem(
            at: payload,
            to: ipaURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let staged = try await fileStore.stage(sourceURL: ipaURL)
        do {
            let files = try await fileStore.commit(
                staged: staged,
                appID: id,
                iconData: metadata.iconData
            )
            try? await fileStore.cancel(staged)

            let isSelfRenewalReturn = SelfRenewalTracker.pendingBundleIdentifier == metadata.bundleIdentifier
            let record = AppRecord(
                id: id,
                originalBundleIdentifier: SelfAppBundleIdentity.originalBundleIdentifier(
                    currentBundleIdentifier: metadata.bundleIdentifier,
                    declaredOriginalBundleIdentifier: metadata.originalBundleIdentifier,
                    existingOriginalBundleIdentifier: existing?.originalBundleIdentifier
                ),
                mappedBundleIdentifier: metadata.bundleIdentifier,
                name: metadata.name,
                version: metadata.version,
                buildNumber: metadata.buildNumber,
                size: size,
                iconRelativePath: files.iconRelativePath,
                state: .installed,
                expiryDate: isSelfRenewalReturn ? metadata.expirationDate : (existing?.expiryDate ?? metadata.expirationDate),
                accountID: resolvedAccountID,
                certificateSerialNumber: existing?.certificateSerialNumber,
                ipaRelativePath: files.ipaRelativePath,
                signedIPARelativePath: existing?.signedIPARelativePath,
                preferredBundleIdentifier: metadata.bundleIdentifier,
                isSeal: true,
                isPinned: true,
                importedAt: existing?.importedAt ?? Date(),
                extensions: existing?.extensions ?? []
            )
            try await appStore.save(record)
            try await Self.removeDuplicateSealRecords(
                records,
                keeping: id,
                appStore: appStore
            )
            SelfRenewalTracker.markCompletedIfMatches(
                bundleIdentifier: metadata.bundleIdentifier,
                version: metadata.version
            )
        } catch {
            try? await fileStore.cancel(staged)
            throw error
        }
    }
    private static func removeDuplicateSealRecords(
        _ records: [AppRecord],
        keeping keptID: UUID,
        appStore: any AppStore
    ) async throws {
        for record in records where record.id != keptID && record.isSeal {
            try await appStore.delete(id: record.id)
        }
    }

}
