import Foundation

actor AppRecordRecovery {
    private let appStore: any AppStore
    private let fileStore: AppFileStore
    private let parser: IPAParserService

    init(
        appStore: any AppStore,
        fileStore: AppFileStore,
        parser: IPAParserService = IPAParserService()
    ) {
        self.appStore = appStore
        self.fileStore = fileStore
        self.parser = parser
    }

    func restoreMissingRecords() async throws {
        var existing = try await appStore.fetchAll()
        try await fileStore.recoverRemovals(appRecords: existing)
        existing = try await appStore.fetchAll()
        try await fileStore.recoverTransactions(appRecords: existing)
        existing = try await appStore.fetchAll()
        let storedIPAs = try await fileStore.storedOriginalIPAs()
        for stored in storedIPAs {
            guard existing.contains(where: { $0.ipaRelativePath == stored.relativePath }) == false else {
                continue
            }
            guard let parsed = try? parser.parse(url: stored.url) else { continue }
            guard existing.contains(where: {
                $0.isSeal && Self.matchesSealBundleIdentifier(
                    parsed.bundleIdentifier,
                    record: $0
                )
            }) == false else {
                continue
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: stored.url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? parsed.fileSize
            let record = AppRecord(
                id: stored.appID,
                originalBundleIdentifier: parsed.bundleIdentifier,
                name: parsed.name,
                version: parsed.version,
                buildNumber: parsed.buildNumber,
                size: size,
                state: .imported,
                expiryDate: nil,
                lastInstalledAt: nil,
                ipaRelativePath: stored.relativePath,
                isPinned: false,
                importedAt: Date(),
                extensions: parsed.extensions
            )
            try await appStore.save(record)
        }
    }

    private static func matchesSealBundleIdentifier(
        _ bundleIdentifier: String,
        record: AppRecord
    ) -> Bool {
        bundleIdentifier == record.originalBundleIdentifier
            || bundleIdentifier == record.mappedBundleIdentifier
    }
}
