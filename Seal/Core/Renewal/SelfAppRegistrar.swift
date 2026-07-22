import Foundation
import ZIPFoundation

protocol SelfAppRegistering: Actor {
    func ensureRegistered() async throws
}

actor SelfAppRegistrar: SelfAppRegistering {
    private let metadata: SelfAppMetadata
    private let appStore: any AppStore
    private let accountRepository: any AccountRepository
    private let fileStore: AppFileStore
    private let operationCoordinator: AppOperationCoordinator
    private var pendingFinalization: PendingFinalization?
    private var pendingDuplicateCleanup: PendingDuplicateCleanup?

    init(
        metadata: SelfAppMetadata,
        appStore: any AppStore,
        accountRepository: any AccountRepository,
        fileStore: AppFileStore,
        operationCoordinator: AppOperationCoordinator = AppOperationCoordinator()
    ) {
        self.metadata = metadata
        self.appStore = appStore
        self.accountRepository = accountRepository
        self.fileStore = fileStore
        self.operationCoordinator = operationCoordinator
    }

    func ensureRegistered() async throws {
        try await operationCoordinator.withLease(
            appID: nil,
            kind: .selfReplacing
        ) { [self] _ in
            try await performRegistration()
        }
    }

    private func performRegistration() async throws {
        if let pendingFinalization {
            try await finishCommittedRegistration(pendingFinalization)
            return
        }
        if let pendingDuplicateCleanup {
            try await finishDuplicateCleanup(pendingDuplicateCleanup)
            return
        }
        var records = try await appStore.fetchAll()
        try await fileStore.recoverRemovals(appRecords: records)
        records = try await appStore.fetchAll()
        try await fileStore.recoverTransactions(appRecords: records)
        records = try await appStore.fetchAll()
        let accounts = try await accountRepository.fetchAll()
        let existing = SelfAppRecordSelection.preferredExistingSealRecord(
            in: records,
            currentBundleIdentifier: metadata.bundleIdentifier
        )
        let matchedAccountID = SelfAppAccountBinding.matchedAccountID(
            teamIdentifier: metadata.signingTeamIdentifier,
            accounts: accounts
        )
        let resolvedAccountID = matchedAccountID ?? existing?.accountID
        let resolvedSigningTeamID = matchedAccountID == nil
            ? existing?.signingTeamID
            : metadata.signingTeamIdentifier ?? existing?.signingTeamID
        let id = existing?.id ?? UUID()
        let preservedIconData: Data? = if let path = existing?.iconRelativePath {
            try? await fileStore.read(relativePath: path)
        } else {
            nil
        }
        let preservedSignedIPAData: Data? = if let path = existing?.signedIPARelativePath {
            try? await fileStore.read(relativePath: path)
        } else {
            nil
        }
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
        var transaction: AppFileTransaction?
        var databaseCommitted = false
        do {
            let preparedTransaction = try await fileStore.prepareCommit(
                staged: staged,
                appID: id,
                iconData: metadata.iconData ?? preservedIconData
            )
            transaction = preparedTransaction

            if let preservedSignedIPAData,
               let signedPath = existing?.signedIPARelativePath {
                try await fileStore.restoreSignedIPA(
                    preservedSignedIPAData,
                    relativePath: signedPath,
                    appID: id
                )
            }

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
                iconRelativePath: preparedTransaction.files.iconRelativePath,
                state: .installed,
                expiryDate: metadata.expirationDate ?? existing?.expiryDate,
                accountID: resolvedAccountID,
                signingTeamID: resolvedSigningTeamID,
                certificateSerialNumber: existing?.certificateSerialNumber,
                signedDeviceIdentifier: existing?.signedDeviceIdentifier,
                provisioningProfileUUID: existing?.provisioningProfileUUID,
                provisioningProfileName: existing?.provisioningProfileName,
                provisioningProfileCreationDate: existing?.provisioningProfileCreationDate,
                provisioningProfileExpirationDate: metadata.expirationDate
                    ?? existing?.provisioningProfileExpirationDate,
                entitlementValidationStatus: existing?.entitlementValidationStatus,
                capabilityValidationStatus: existing?.capabilityValidationStatus,
                lastSignedAt: existing?.lastSignedAt,
                lastInstalledAt: existing?.lastInstalledAt,
                removedExtensionBundleIdentifiers: existing?.removedExtensionBundleIdentifiers ?? [],
                signingTargets: existing?.signingTargets ?? [],
                ipaRelativePath: preparedTransaction.files.ipaRelativePath,
                signedIPARelativePath: existing?.signedIPARelativePath,
                preferredBundleIdentifier: metadata.bundleIdentifier,
                isSeal: true,
                isPinned: true,
                importedAt: existing?.importedAt ?? Date(),
                extensions: existing?.extensions ?? []
            )
            try await fileStore.setExpectedRecord(record, for: preparedTransaction)
            try await appStore.save(record)
            databaseCommitted = true
            let pendingFinalization = PendingFinalization(
                transaction: preparedTransaction,
                records: records,
                keptID: id
            )
            self.pendingFinalization = pendingFinalization
            try await finishCommittedRegistration(pendingFinalization)
            transaction = nil
            try? await fileStore.cancel(staged)
        } catch {
            if databaseCommitted == false, let transaction {
                do {
                    try await fileStore.rollback(transaction)
                } catch {
                    try? await fileStore.cancel(staged)
                    throw error
                }
            }
            try? await fileStore.cancel(staged)
            throw error
        }
    }

    private func finishCommittedRegistration(
        _ pendingFinalization: PendingFinalization
    ) async throws {
        do {
            try await fileStore.finalize(pendingFinalization.transaction)
            self.pendingFinalization = nil
        } catch {
            self.pendingFinalization = pendingFinalization
            throw Self.cleanupFailure
        }

        let duplicateCleanup = PendingDuplicateCleanup(
            records: pendingFinalization.records,
            keptID: pendingFinalization.keptID
        )
        self.pendingDuplicateCleanup = duplicateCleanup
        try await finishDuplicateCleanup(duplicateCleanup)
    }

    private func finishDuplicateCleanup(
        _ cleanup: PendingDuplicateCleanup
    ) async throws {
        var currentRecords = try await appStore.fetchAll()
        try await fileStore.recoverRemovals(appRecords: currentRecords)
        currentRecords = try await appStore.fetchAll()

        for record in cleanup.records where record.id != cleanup.keptID && record.isSeal {
            guard currentRecords.contains(where: { $0.id == record.id }) else { continue }
            let removal = try await fileStore.prepareRemoval(appID: record.id)
            do {
                try await appStore.delete(id: record.id)
            } catch {
                try await fileStore.rollbackRemoval(removal)
                self.pendingDuplicateCleanup = cleanup
                throw error
            }
            do {
                try await fileStore.finalizeRemoval(removal)
            } catch {
                self.pendingDuplicateCleanup = cleanup
                throw Self.cleanupFailure
            }
            currentRecords.removeAll { $0.id == record.id }
        }
        pendingDuplicateCleanup = nil
    }

    private static let cleanupFailure = ImportFailure(
        title: "Seal 已登记，但备份清理失败",
        reason: "应用记录和新 IPA 已提交；旧备份仍等待清理。",
        recovery: "重试清理",
        code: "SEAL-IPA-206"
    )

    private struct PendingFinalization: Sendable {
        let transaction: AppFileTransaction
        let records: [AppRecord]
        let keptID: UUID
    }

    private struct PendingDuplicateCleanup: Sendable {
        let records: [AppRecord]
        let keptID: UUID
    }

}
