import Foundation
import ZIPFoundation

enum SelfAppBundleIdentity {
    static func originalBundleIdentifier(
        currentBundleIdentifier: String,
        declaredOriginalBundleIdentifier: String?,
        existingOriginalBundleIdentifier: String?
    ) -> String {
        existingOriginalBundleIdentifier
            ?? declaredOriginalBundleIdentifier
            ?? currentBundleIdentifier
    }
}

actor SelfAppRegistrar {
    private let metadata: SelfAppMetadata
    private let appStore: any AppStore
    private let fileStore: AppFileStore

    init(
        metadata: SelfAppMetadata,
        appStore: any AppStore,
        fileStore: AppFileStore
    ) {
        self.metadata = metadata
        self.appStore = appStore
        self.fileStore = fileStore
    }

    func ensureRegistered() async throws {
        let records = try await appStore.fetchAll()
        let existing = Self.preferredExistingSealRecord(
            in: records,
            currentBundleIdentifier: metadata.bundleIdentifier
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
                mappedBundleIdentifier: existing?.mappedBundleIdentifier ?? metadata.bundleIdentifier,
                name: metadata.name,
                version: metadata.version,
                buildNumber: metadata.buildNumber,
                size: size,
                iconRelativePath: files.iconRelativePath,
                state: .installed,
                expiryDate: isSelfRenewalReturn ? metadata.expirationDate : (existing?.expiryDate ?? metadata.expirationDate),
                accountID: existing?.accountID,
                ipaRelativePath: files.ipaRelativePath,
                signedIPARelativePath: existing?.signedIPARelativePath,
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
    private static func preferredExistingSealRecord(
        in records: [AppRecord],
        currentBundleIdentifier: String
    ) -> AppRecord? {
        let matchingSeal = records.first { record in
            record.isSeal && matchesSealBundleIdentifier(
                currentBundleIdentifier,
                record: record
            )
        }
        if let matchingSeal { return matchingSeal }

        if let installedSeal = records.first(where: { $0.isSeal && $0.state == .installed }) {
            return installedSeal
        }

        return records.first(where: \.isSeal)
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

    private static func matchesSealBundleIdentifier(
        _ bundleIdentifier: String,
        record: AppRecord
    ) -> Bool {
        bundleIdentifier == record.originalBundleIdentifier
            || bundleIdentifier == record.mappedBundleIdentifier
            || bundleIdentifier == record.preferredBundleIdentifier
    }

}
