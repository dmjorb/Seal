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
        let accounts = try await accountRepository.fetchAll()
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
            do {
                try await fileStore.cancel(staged)
            } catch {
                throw ImportFailure(
                    title: "Seal 临时文件清理失败",
                    reason: "Seal 自身注册已写入文件，但暂存文件未能清理。",
                    recovery: "重新打开 Seal 后在存储维护中重试",
                    code: "SEAL-STORAGE-SELF-001"
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
                iconRelativePath: files.iconRelativePath,
                state: .installed,
                expiryDate: metadata.expirationDate,
                accountID: resolvedAccountID,
                signingTeamID: metadata.signingTeamIdentifier ?? existing?.signingTeamID,
                certificateSerialNumber: existing?.certificateSerialNumber,
                provisioningProfileExpirationDate: metadata.expirationDate,
                ipaRelativePath: files.ipaRelativePath,
                signedIPARelativePath: nil,
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
        } catch {
            let originalError = error
            do {
                try await fileStore.cancel(staged)
            } catch {
                throw ImportFailure(
                    title: "Seal 自身注册恢复未完成",
                    reason: "注册流程失败，且暂存文件未能清理。",
                    recovery: "重新打开 Seal 后检查存储",
                    code: "SEAL-STORAGE-SELF-002"
                )
            }
            throw originalError
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
