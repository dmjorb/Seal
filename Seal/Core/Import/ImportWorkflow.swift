import Foundation

actor ImportWorkflow {
    private(set) var state: ImportWorkflowState = .idle

    private let parser: IPAParserService
    private let fileStore: AppFileStore
    private let appStore: any AppStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var retryDraft: ImportDraft?
    private(set) var lastCleanupFailure: ImportFailure?

    init(
        parser: IPAParserService,
        fileStore: AppFileStore,
        appStore: any AppStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.parser = parser
        self.fileStore = fileStore
        self.appStore = appStore
        self.now = now
        self.makeID = makeID
    }

    func prepare(sourceURL: URL) async {
        guard canPrepare else { return }
        await discardRetryDraft()
        if let cleanupFailure = lastCleanupFailure {
            state = .failed(cleanupFailure)
            return
        }
        state = .preparing

        var stagedIPA: StagedIPA?
        do {
            let staged = try await fileStore.stage(sourceURL: sourceURL)
            stagedIPA = staged
            try Task.checkCancellation()
            let parsed = try parser.parse(url: staged.url)
            let draft = ImportDraft(
                appID: makeID(),
                parsedIPA: parsed,
                stagedIPA: staged
            )
            state = .awaitingConfirmation(draft)
        } catch is CancellationError {
            if let stagedIPA, let cleanupFailure = await cancelStagedIPA(stagedIPA) {
                state = .failed(cleanupFailure)
            } else {
                state = .idle
            }
        } catch {
            let importFailure = Self.importFailure(from: error)
            if let stagedIPA, let cleanupFailure = await cancelStagedIPA(stagedIPA) {
                state = .failed(cleanupFailure)
            } else {
                state = .failed(importFailure)
            }
        }
    }

    func confirm(preferredDraft: ImportDraft? = nil) async {
        switch state {
        case .awaitingConfirmation(let draft):
            await commit(draft)
        case .failed, .idle, .completed:
            guard let preferredDraft else { return }
            await commit(preferredDraft)
        case .preparing, .committing:
            return
        }
    }

    func retry() async {
        guard case .failed = state, let draft = retryDraft else { return }
        state = .awaitingConfirmation(draft)
        await commit(draft)
    }

    func cancel() async {
        let draft: ImportDraft?
        switch state {
        case .awaitingConfirmation(let current), .committing(let current):
            draft = current
        case .failed:
            draft = retryDraft
        default:
            draft = nil
        }

        if let draft, let cleanupFailure = await cancelStagedIPA(draft.stagedIPA) {
            retryDraft = nil
            state = .failed(cleanupFailure)
            return
        }
        retryDraft = nil
        state = .idle
    }

    private var canPrepare: Bool {
        switch state {
        case .idle, .completed, .failed:
            return true
        case .preparing, .awaitingConfirmation, .committing:
            return false
        }
    }

    private func commit(_ draft: ImportDraft) async {
        state = .committing(draft)
        var fileTransaction: PreparedAppFileTransaction?
        var databaseReplacedRecords: [AppRecord] = []
        var databaseRecord: AppRecord?

        do {
            let records = try await appStore.fetchAll()
            let existing = Self.existingPendingImportRecord(
                for: draft.parsedIPA,
                in: records
            )
            let preferenceSource = Self.preferenceSource(
                for: draft.parsedIPA,
                in: records,
                excluding: existing?.id
            )
            let commitAppID = existing?.id ?? draft.appID
            let preferredIconData: Data?
            if let path = preferenceSource?.preferredIconRelativePath {
                preferredIconData = try? await fileStore.read(relativePath: path)
            } else {
                preferredIconData = nil
            }

            var transaction = try await fileStore.prepareImportCommit(
                staged: draft.stagedIPA,
                appID: commitAppID,
                iconData: draft.parsedIPA.iconData,
                preferredIconData: preferredIconData
            )
            fileTransaction = transaction
            transaction = try await fileStore.markDatabaseCommitPending(transaction)
            fileTransaction = transaction

            var record = Self.makeRecord(
                draft: draft,
                files: transaction.storedFiles,
                importedAt: now(),
                replacing: existing,
                preferenceSource: preferenceSource
            )
            record.pendingFileTransactionID = transaction.id
            databaseReplacedRecords = try await appStore.replaceImportedApp(record)
            databaseRecord = record

            transaction = try await fileStore.finalizeImportCommit(transaction)
            fileTransaction = transaction

            record.pendingFileTransactionID = nil
            try await appStore.save(record)
            databaseRecord = record
            try await fileStore.completeImportCommit(transaction)
            fileTransaction = nil

            lastCleanupFailure = await cancelStagedIPA(draft.stagedIPA)
            // Replaced pending-import directories are intentionally left for the
            // orphan maintenance pass. Deleting them here would introduce a new
            // post-commit failure point after the authoritative DB/file transaction
            // has already succeeded. Recovery also refuses to resurrect a second
            // record with the same original Bundle ID.
            retryDraft = nil
            state = .completed(record)
        } catch is CancellationError {
            if let rollbackFailure = await rollbackFailedCommit(
                transaction: fileTransaction,
                databaseRecord: databaseRecord,
                replacedRecords: databaseReplacedRecords
            ) {
                retryDraft = nil
                state = .failed(rollbackFailure)
            } else {
                retryDraft = nil
                state = .awaitingConfirmation(draft)
            }
        } catch {
            let originalFailure: ImportFailure
            if fileTransaction?.phase == .databaseCommitPending, databaseRecord == nil {
                originalFailure = Self.persistenceFailure
            } else {
                originalFailure = Self.importFailure(from: error)
            }
            if let transaction = fileTransaction,
               transaction.phase == .finalized {
                // A finalized transaction is intentionally left journaled when a
                // later metadata write fails. Startup recovery can safely finish it.
                retryDraft = nil
                state = .failed(Self.finalizeRecoveryFailure(originalFailure))
                return
            }

            if let rollbackFailure = await rollbackFailedCommit(
                transaction: fileTransaction,
                databaseRecord: databaseRecord,
                replacedRecords: databaseReplacedRecords
            ) {
                retryDraft = nil
                state = .failed(rollbackFailure)
            } else {
                retryDraft = draft
                state = .failed(originalFailure)
            }
        }
    }


    private func rollbackFailedCommit(
        transaction: PreparedAppFileTransaction?,
        databaseRecord: AppRecord?,
        replacedRecords: [AppRecord]
    ) async -> ImportFailure? {
        if let databaseRecord {
            do {
                try await restoreDatabaseAfterFailedImport(
                    newRecordID: databaseRecord.id,
                    replacedRecords: replacedRecords
                )
            } catch {
                // Keep the file transaction journal intact. Startup recovery can
                // inspect the committed database/file state instead of losing the
                // only durable marker for this interrupted operation.
                return Self.rollbackRecoveryFailure
            }
        }

        if let transaction {
            do {
                try await fileStore.abortImportCommit(transaction)
            } catch {
                return Self.rollbackRecoveryFailure
            }
        }
        return nil
    }

    private func restoreDatabaseAfterFailedImport(
        newRecordID: UUID,
        replacedRecords: [AppRecord]
    ) async throws {
        try await appStore.delete(id: newRecordID)
        for record in replacedRecords {
            try await appStore.save(record)
        }
    }

    private func discardRetryDraft() async {
        lastCleanupFailure = nil
        if let retryDraft {
            lastCleanupFailure = await cancelStagedIPA(retryDraft.stagedIPA)
        }
        retryDraft = nil
    }

    private func cancelStagedIPA(_ stagedIPA: StagedIPA) async -> ImportFailure? {
        do {
            try await fileStore.cancel(stagedIPA)
            return nil
        } catch {
            return Self.temporaryCleanupFailure
        }
    }

    func takeCleanupFailure() -> ImportFailure? {
        defer { lastCleanupFailure = nil }
        return lastCleanupFailure
    }

    private static func makeRecord(
        draft: ImportDraft,
        files: StoredAppFiles,
        importedAt: Date,
        replacing existing: AppRecord?,
        preferenceSource: AppRecord?
    ) -> AppRecord {
        let parsed = draft.parsedIPA
        let recordID = existing?.id ?? draft.appID
        let preferredBundleIdentifier = existing?.preferredBundleIdentifier
            ?? preferenceSource?.mappedBundleIdentifier
            ?? preferenceSource?.preferredBundleIdentifier
        let preferredDisplayName = existing?.preferredDisplayName
            ?? preferenceSource?.preferredDisplayName
        let preferredIconRelativePath = existing?.preferredIconRelativePath
            ?? files.preferredIconRelativePath
        let removedExtensionBundleIdentifiers = existing?.removedExtensionBundleIdentifiers
            ?? preferenceSource?.removedExtensionBundleIdentifiers
            ?? []
        let isPinned = existing?.isPinned ?? false

        return AppRecord(
            id: recordID,
            originalBundleIdentifier: parsed.bundleIdentifier,
            mappedBundleIdentifier: nil,
            name: parsed.name,
            version: parsed.version,
            buildNumber: parsed.buildNumber,
            size: parsed.fileSize,
            iconRelativePath: files.iconRelativePath,
            state: .preflightPassed,
            expiryDate: nil,
            accountID: nil,
            certificateSerialNumber: nil,
            removedExtensionBundleIdentifiers: removedExtensionBundleIdentifiers,
            ipaRelativePath: files.ipaRelativePath,
            signedIPARelativePath: nil,
            preferredBundleIdentifier: preferredBundleIdentifier,
            preferredDisplayName: preferredDisplayName,
            preferredIconRelativePath: preferredIconRelativePath,
            isSeal: false,
            isPinned: isPinned,
            importedAt: importedAt,
            extensions: parsed.extensions
        )
    }

    private static func existingPendingImportRecord(
        for parsed: ParsedIPA,
        in records: [AppRecord]
    ) -> AppRecord? {
        records.first(where: { record in
            record.isSeal == false
                && record.originalBundleIdentifier == parsed.bundleIdentifier
                && record.hasSignedArtifact == false
                && [.imported, .failedRecoverable, .failedFinal].contains(record.state)
        })
    }

    private static func preferenceSource(
        for parsed: ParsedIPA,
        in records: [AppRecord],
        excluding excludedID: UUID?
    ) -> AppRecord? {
        records
            .filter { record in
                record.id != excludedID
                    && record.isSeal == false
                    && record.originalBundleIdentifier == parsed.bundleIdentifier
                    && (record.lastSignedAt != nil || record.mappedBundleIdentifier != nil)
            }
            .max { lhs, rhs in
                (lhs.lastSignedAt ?? lhs.importedAt) < (rhs.lastSignedAt ?? rhs.importedAt)
            }
    }

    private static func importFailure(from error: Error) -> ImportFailure {
        if let failure = error as? ImportFailure {
            return failure
        }
        return ImportFailure(
            title: "无法导入 IPA",
            reason: "IPA 解析失败，文件结构或元数据不可读取。",
            recovery: "重试",
            code: "SEAL-IPA-200"
        )
    }

    private static let persistenceFailure = ImportFailure(
        title: "无法保存 IPA",
        reason: "应用记录保存失败",
        recovery: "重试",
        code: "SEAL-IPA-205"
    )

    private static let temporaryCleanupFailure = ImportFailure(
        title: "临时文件清理失败",
        reason: "导入产生的临时文件未能完整删除。",
        recovery: "稍后在存储维护中重试清理",
        code: "SEAL-STORAGE-IMPORT-001"
    )

    private static let rollbackRecoveryFailure = ImportFailure(
        title: "导入恢复未完成",
        reason: "本次导入未能完全回滚。Seal 已保留恢复记录，下次启动时会继续恢复。",
        recovery: "重新打开 Seal 后再重试",
        code: "SEAL-IPA-ROLLBACK-001"
    )

    private static func finalizeRecoveryFailure(_ original: ImportFailure) -> ImportFailure {
        ImportFailure(
            title: "导入提交待恢复",
            reason: "IPA 文件已经提交，但后续状态保存未完成。Seal 已保留恢复记录，下次启动时会继续完成。",
            recovery: "重新打开 Seal 后检查应用状态",
            code: original.code == "SEAL-IPA-205" ? "SEAL-IPA-RECOVERY-001" : original.code
        )
    }
}
