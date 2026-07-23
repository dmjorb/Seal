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
        try await recoverPendingFileTransactions()
        try await reconcileKnownRecords()

        let existing = try await appStore.fetchAll()
        let storedIPAs = try await fileStore.storedOriginalIPAs()
        for stored in storedIPAs {
            guard existing.contains(where: { $0.ipaRelativePath == stored.relativePath }) == false else {
                continue
            }
            guard let parsed = try? parser.parse(url: stored.url) else { continue }
            guard existing.contains(where: {
                $0.isSeal && Self.matchesSealBundleIdentifier(parsed.bundleIdentifier, record: $0)
            }) == false else {
                continue
            }
            // A leftover directory from an older replaced import must never be
            // resurrected as a second app record. Bundle identity, not the file
            // name, is the stable recovery key for third-party imports.
            guard existing.contains(where: {
                $0.isSeal == false
                    && $0.originalBundleIdentifier.caseInsensitiveCompare(
                        parsed.bundleIdentifier
                    ) == .orderedSame
            }) == false else {
                continue
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: stored.url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? parsed.fileSize
            let signedArtifact = try await recoveredSignedArtifact(appID: stored.appID)
            let record = AppRecord(
                id: stored.appID,
                originalBundleIdentifier: parsed.bundleIdentifier,
                mappedBundleIdentifier: signedArtifact?.mappedBundleIdentifier,
                name: parsed.name,
                version: parsed.version,
                buildNumber: parsed.buildNumber,
                size: size,
                iconRelativePath: nil,
                state: signedArtifact == nil ? .imported : .signed,
                expiryDate: nil,
                accountID: nil,
                ipaRelativePath: stored.relativePath,
                signedIPARelativePath: signedArtifact?.relativePath,
                signedIPASHA256: signedArtifact?.sha256,
                signedArtifactStatus: signedArtifact == nil ? nil : .awaitingVerification,
                preferredBundleIdentifier: signedArtifact?.mappedBundleIdentifier
                    ?? BundleIDPolicy.recommendedBundleIdentifier(for: parsed.bundleIdentifier),
                isPinned: false,
                importedAt: Date(),
                extensions: parsed.extensions
            )
            try await appStore.save(record)
        }
    }

    private func recoverPendingFileTransactions() async throws {
        let transactions = try await fileStore.pendingImportTransactions()
        guard transactions.isEmpty == false else { return }

        var records = try await appStore.fetchAll()
        var failedTransactionCount = 0
        for transaction in transactions {
            let matchingRecord = records.first { $0.pendingFileTransactionID == transaction.id }

            if matchingRecord != nil || transaction.phase == .finalized {
                do {
                    let finalized = transaction.phase == .finalized
                        ? transaction
                        : try await fileStore.finalizeImportCommit(transaction)
                    if var record = matchingRecord {
                        record.pendingFileTransactionID = nil
                        try await appStore.save(record)
                        if let index = records.firstIndex(where: { $0.id == record.id }) {
                            records[index] = record
                        }
                    }
                    try await fileStore.completeImportCommit(finalized)
                } catch {
                    // Leave the journal intact so a later launch can retry.
                    failedTransactionCount += 1
                }
            } else {
                do {
                    try await fileStore.abortImportCommit(transaction)
                } catch {
                    failedTransactionCount += 1
                }
            }
        }

        if failedTransactionCount > 0 {
            throw ImportFailure(
                title: "本地事务恢复未完成",
                reason: "有 \(failedTransactionCount) 个 IPA 文件事务仍需恢复，恢复记录已保留。",
                recovery: "重新打开 Seal 后重试",
                code: "SEAL-IPA-RECOVERY-002"
            )
        }
    }

    private func reconcileKnownRecords() async throws {
        var records = try await appStore.fetchAll()
        for index in records.indices {
            var record = records[index]
            guard let signedPath = record.signedIPARelativePath else { continue }
            let exists = try await fileStore.exists(relativePath: signedPath)
            if exists == false {
                record.signedArtifactStatus = .missing
                if record.state != .installed && record.isSeal == false {
                    record.state = .signed
                }
                try await appStore.save(record)
                records[index] = record
                continue
            }

            do {
                let hash = try await fileStore.sha256(relativePath: signedPath)
                if let expected = record.signedIPASHA256,
                   expected.caseInsensitiveCompare(hash) != .orderedSame {
                    record.signedArtifactStatus = .damaged
                } else {
                    // Legacy signed packages gain integrity metadata during migration.
                    record.signedIPASHA256 = hash
                    if record.signedArtifactStatus == nil
                        || record.signedArtifactStatus == .missing
                        || record.signedArtifactStatus == .damaged {
                        record.signedArtifactStatus = record.state == .installed ? .installed : .available
                    }
                }
                try await appStore.save(record)
                records[index] = record
            } catch {
                record.signedArtifactStatus = .damaged
                if record.state != .installed && record.isSeal == false {
                    record.state = .signed
                }
                try await appStore.save(record)
                records[index] = record
            }
        }
    }

    private struct RecoveredSignedArtifact {
        let relativePath: String
        let sha256: String
        let mappedBundleIdentifier: String?
    }

    private func recoveredSignedArtifact(appID: UUID) async throws -> RecoveredSignedArtifact? {
        guard let signed = try await fileStore.storedSignedIPA(appID: appID) else { return nil }
        let hash = try await fileStore.sha256(relativePath: signed.relativePath)
        let mappedBundleIdentifier = (try? parser.parse(url: signed.url))?.bundleIdentifier
        return RecoveredSignedArtifact(
            relativePath: signed.relativePath,
            sha256: hash,
            mappedBundleIdentifier: mappedBundleIdentifier
        )
    }

    private static func matchesSealBundleIdentifier(
        _ bundleIdentifier: String,
        record: AppRecord
    ) -> Bool {
        bundleIdentifier == record.originalBundleIdentifier
            || bundleIdentifier == record.mappedBundleIdentifier
    }
}
