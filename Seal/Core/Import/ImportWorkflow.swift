import Foundation

actor ImportWorkflow {
    private(set) var state: ImportWorkflowState = .idle

    private let parser: IPAParserService
    private let fileStore: AppFileStore
    private let appStore: any AppStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var retryDraft: ImportDraft?

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
            if let stagedIPA {
                try? await fileStore.cancel(stagedIPA)
            }
            state = .idle
        } catch {
            if let stagedIPA {
                try? await fileStore.cancel(stagedIPA)
            }
            state = .failed(Self.importFailure(from: error))
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

        if let draft {
            try? await fileStore.cancel(draft.stagedIPA)
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
        var committedFiles: StoredAppFiles?

        do {
            let records = try await appStore.fetchAll()
            let existing = Self.existingPendingImportRecord(
                for: draft.parsedIPA,
                in: records
            )
            let commitAppID = existing?.id ?? draft.appID
            let files = try await fileStore.commit(
                staged: draft.stagedIPA,
                appID: commitAppID,
                iconData: draft.parsedIPA.iconData
            )
            committedFiles = files
            let record = Self.makeRecord(
                draft: draft,
                files: files,
                importedAt: now(),
                replacing: existing
            )
            let replaced = try await appStore.replaceImportedApp(record)

            try? await fileStore.cancel(draft.stagedIPA)
            for oldRecord in replaced where oldRecord.id != record.id {
                try? await fileStore.rollback(
                    StoredAppFiles(
                        ipaRelativePath: oldRecord.ipaRelativePath,
                        iconRelativePath: oldRecord.iconRelativePath
                    )
                )
            }
            retryDraft = nil
            state = .completed(record)
        } catch is CancellationError {
            if let committedFiles {
                try? await fileStore.rollback(committedFiles)
            }
            retryDraft = nil
            state = .awaitingConfirmation(draft)
        } catch {
            if let committedFiles {
                try? await fileStore.rollback(committedFiles)
            }
            retryDraft = draft
            state = .failed(
                committedFiles == nil
                    ? Self.importFailure(from: error)
                    : Self.persistenceFailure
            )
        }
    }

    private func discardRetryDraft() async {
        if let retryDraft {
            try? await fileStore.cancel(retryDraft.stagedIPA)
        }
        retryDraft = nil
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
                && record.originalBundleIdentifier == parsed.bundleIdentifier
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
}
