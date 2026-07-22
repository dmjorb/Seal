import Foundation

actor ImportWorkflow {
    private(set) var state: ImportWorkflowState = .idle

    private let parser: IPAParserService
    private let fileStore: AppFileStore
    private let appStore: any AppStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var retryDraft: ImportDraft?
    private var pendingFinalization: PendingFinalization?
    private var pendingRecovery: PendingRecovery?
    private var operationGeneration = 0
    private var operationTask: Task<Void, Never>?

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
        let generation = beginOperation()
        let task = Task {
            await self.prepareOperation(sourceURL: sourceURL, generation: generation)
        }
        operationTask = task
        await task.value
        if isCurrent(generation) {
            operationTask = nil
        }
    }

    private func prepareOperation(sourceURL: URL, generation: Int) async {
        do {
            let records = try await appStore.fetchAll()
            guard isCurrent(generation) else { return }
            try await fileStore.recoverTransactions(appRecords: records)
            guard isCurrent(generation) else { return }
            pendingFinalization = nil
            pendingRecovery = nil
        } catch {
            guard isCurrent(generation) else { return }
            state = .failed(Self.cleanupFailure)
            return
        }
        await discardRetryDraft()
        guard isCurrent(generation) else { return }
        state = .preparing

        var stagedIPA: StagedIPA?
        do {
            let staged = try await fileStore.stage(sourceURL: sourceURL)
            guard isCurrent(generation) else {
                try await fileStore.cancel(staged)
                return
            }
            stagedIPA = staged
            try Task.checkCancellation()
            let parsed = try parser.parse(url: staged.url)
            let draft = ImportDraft(
                appID: makeID(),
                parsedIPA: parsed,
                stagedIPA: staged
            )
            guard isCurrent(generation) else { return }
            state = .awaitingConfirmation(draft)
        } catch is CancellationError {
            if let stagedIPA {
                do { try await fileStore.cancel(stagedIPA) } catch {}
            }
            guard isCurrent(generation) else { return }
            state = .idle
        } catch {
            if let stagedIPA {
                do { try await fileStore.cancel(stagedIPA) } catch {}
            }
            guard isCurrent(generation) else { return }
            state = .failed(Self.importFailure(from: error))
        }
    }

    func confirm(preferredDraft: ImportDraft? = nil) async {
        let draft: ImportDraft
        switch state {
        case .awaitingConfirmation(let current):
            draft = current
        case .failed, .idle, .completed:
            guard let preferredDraft else { return }
            draft = preferredDraft
        case .preparing, .committing:
            return
        }
        let generation = beginOperation()
        let task = Task {
            await self.commit(draft, generation: generation)
        }
        operationTask = task
        await task.value
        if isCurrent(generation) {
            operationTask = nil
        }
    }

    func retry() async {
        if pendingFinalization != nil {
            let generation = beginOperation()
            let task = Task { await self.retryPendingFinalization(generation: generation) }
            operationTask = task
            await task.value
            return
        }
        if pendingRecovery != nil {
            let generation = beginOperation()
            let task = Task { await self.retryPendingRecovery(generation: generation) }
            operationTask = task
            await task.value
            return
        }
        guard case .failed = state, let draft = retryDraft else { return }
        state = .awaitingConfirmation(draft)
        await confirm()
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

        operationGeneration &+= 1
        operationTask?.cancel()
        operationTask = nil
        retryDraft = nil
        state = .idle
        if let draft {
            do { try await fileStore.cancel(draft.stagedIPA) } catch {}
        }
    }

    private var canPrepare: Bool {
        switch state {
        case .idle, .completed, .failed:
            return true
        case .preparing, .awaitingConfirmation, .committing:
            return false
        }
    }

    private func commit(_ draft: ImportDraft, generation: Int) async {
        guard isCurrent(generation) else { return }
        state = .committing(draft)
        var transaction: AppFileTransaction?
        var databaseCommitted = false

        do {
            let records = try await appStore.fetchAll()
            guard isCurrent(generation) else { return }
            let existing = Self.existingPendingImportRecord(
                for: draft.parsedIPA,
                in: records
            )
            let commitAppID = existing?.id ?? draft.appID
            let preparedTransaction = try await fileStore.prepareCommit(
                staged: draft.stagedIPA,
                appID: commitAppID,
                iconData: draft.parsedIPA.iconData
            )
            guard isCurrent(generation) else {
                try await fileStore.rollback(preparedTransaction)
                return
            }
            transaction = preparedTransaction
            let record = Self.makeRecord(
                draft: draft,
                files: preparedTransaction.files,
                importedAt: now(),
                replacing: existing
            )
            try await fileStore.setExpectedRecord(record, for: preparedTransaction)
            guard isCurrent(generation) else {
                try await fileStore.rollback(preparedTransaction)
                return
            }
            try Task.checkCancellation()
            let replaced = try await appStore.replaceImportedApp(record)
            databaseCommitted = true
            guard isCurrent(generation) else { return }

            do { try await fileStore.cancel(draft.stagedIPA) } catch {}
            guard isCurrent(generation) else { return }
            for oldRecord in replaced where oldRecord.id != record.id {
                try? await fileStore.removeStoredFiles(
                    StoredAppFiles(
                        ipaRelativePath: oldRecord.ipaRelativePath,
                        iconRelativePath: oldRecord.iconRelativePath
                    )
                )
                guard isCurrent(generation) else { return }
            }
            do {
                try await fileStore.finalize(preparedTransaction)
                guard isCurrent(generation) else { return }
                transaction = nil
            } catch {
                guard isCurrent(generation) else { return }
                pendingFinalization = PendingFinalization(
                    transaction: preparedTransaction,
                    record: record
                )
                retryDraft = nil
                state = .failed(Self.cleanupFailure)
                return
            }
            retryDraft = nil
            state = .completed(record)
        } catch is CancellationError {
            if let transaction, databaseCommitted == false {
                do {
                    try await fileStore.rollback(transaction)
                } catch {
                    guard isCurrent(generation) else { return }
                    pendingRecovery = PendingRecovery(transaction: transaction, draft: nil)
                    state = .failed(Self.recoveryFailure)
                    return
                }
            }
            guard isCurrent(generation) else { return }
            retryDraft = nil
            state = .awaitingConfirmation(draft)
        } catch {
            if let transaction, databaseCommitted == false {
                do {
                    try await fileStore.rollback(transaction)
                } catch {
                    guard isCurrent(generation) else { return }
                    pendingRecovery = PendingRecovery(transaction: transaction, draft: draft)
                    retryDraft = nil
                    state = .failed(Self.recoveryFailure)
                    return
                }
            }
            guard isCurrent(generation) else { return }
            retryDraft = draft
            state = .failed(
                transaction == nil
                    ? Self.importFailure(from: error)
                    : Self.persistenceFailure
            )
        }
    }

    private func retryPendingFinalization(generation: Int) async {
        guard let pendingFinalization else { return }
        do {
            try await fileStore.finalize(pendingFinalization.transaction)
            guard isCurrent(generation) else { return }
            self.pendingFinalization = nil
            retryDraft = nil
            state = .completed(pendingFinalization.record)
        } catch {
            guard isCurrent(generation) else { return }
            state = .failed(Self.cleanupFailure)
        }
    }

    private func retryPendingRecovery(generation: Int) async {
        guard let pendingRecovery else { return }
        do {
            try await fileStore.rollback(pendingRecovery.transaction)
            guard isCurrent(generation) else { return }
            self.pendingRecovery = nil
            if let draft = pendingRecovery.draft {
                retryDraft = draft
                state = .awaitingConfirmation(draft)
            } else {
                state = .idle
            }
        } catch {
            guard isCurrent(generation) else { return }
            state = .failed(Self.recoveryFailure)
        }
    }

    private func discardRetryDraft() async {
        if let retryDraft {
            try? await fileStore.cancel(retryDraft.stagedIPA)
        }
        retryDraft = nil
    }

    private func beginOperation() -> Int {
        operationGeneration &+= 1
        operationTask?.cancel()
        return operationGeneration
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == operationGeneration && Task.isCancelled == false
    }

    private static func makeRecord(
        draft: ImportDraft,
        files: StoredAppFiles,
        importedAt: Date,
        replacing existing: AppRecord?
    ) -> AppRecord {
        let parsed = draft.parsedIPA
        return AppRecord(
            id: existing?.id ?? draft.appID,
            originalBundleIdentifier: parsed.bundleIdentifier,
            mappedBundleIdentifier: nil,
            name: parsed.name,
            version: parsed.version,
            buildNumber: parsed.buildNumber,
            size: parsed.fileSize,
            iconRelativePath: files.iconRelativePath,
            state: .imported,
            expiryDate: nil,
            accountID: nil,
            certificateSerialNumber: nil,
            ipaRelativePath: files.ipaRelativePath,
            signedIPARelativePath: nil,
            preferredBundleIdentifier: existing?.preferredBundleIdentifier,
            isSeal: false,
            isPinned: existing?.isPinned ?? false,
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
                && record.state != .installed
                && record.originalBundleIdentifier.caseInsensitiveCompare(
                    parsed.bundleIdentifier
                ) == .orderedSame
        })
    }

    private static func importFailure(from error: Error) -> ImportFailure {
        if let failure = error as? ImportFailure {
            return failure
        }
        return ImportFailure(
            title: "无法导入 IPA",
            reason: "来源：IPA 解析\n原始返回：处理失败",
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

    private static let cleanupFailure = ImportFailure(
        title: "IPA 已保存，但备份清理失败",
        reason: "应用记录和新 IPA 已提交；旧备份仍等待清理。",
        recovery: "重试清理",
        code: "SEAL-IPA-206"
    )

    private static let recoveryFailure = ImportFailure(
        title: "IPA 文件恢复未完成",
        reason: "文件事务已安全记录，但仍需重试恢复。",
        recovery: "重试恢复",
        code: "SEAL-IPA-206"
    )

    private struct PendingFinalization: Sendable {
        let transaction: AppFileTransaction
        let record: AppRecord
    }

    private struct PendingRecovery: Sendable {
        let transaction: AppFileTransaction
        let draft: ImportDraft?
    }
}
