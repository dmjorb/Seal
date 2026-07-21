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
            let existing = Self.existingRecord(
                for: draft.parsedIPA,
                in: records
            )
            let commitAppID = existing?.isSeal == true ? existing?.id ?? draft.appID : draft.appID
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
            let replaced: [AppRecord]
            if record.isSeal {
                try await appStore.save(record)
                replaced = []
            } else {
                replaced = try await appStore.replaceImportedApp(record)
            }

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
        let isSealPackage = existing?.isSeal == true && isCurrentSealBundle(parsed.bundleIdentifier)
        let currentSealBundleIdentifier = Bundle.main.bundleIdentifier
        return AppRecord(
            id: existing?.id ?? draft.appID,
            originalBundleIdentifier: isSealPackage
                ? (existing?.originalBundleIdentifier ?? parsed.bundleIdentifier)
                : parsed.bundleIdentifier,
            mappedBundleIdentifier: isSealPackage
                ? (currentSealBundleIdentifier ?? existing?.mappedBundleIdentifier ?? parsed.bundleIdentifier)
                : existing?.mappedBundleIdentifier,
            name: parsed.name,
            version: parsed.version,
            buildNumber: parsed.buildNumber,
            size: parsed.fileSize,
            iconRelativePath: files.iconRelativePath,
            state: isSealPackage ? .installed : .preflightPassed,
            expiryDate: isSealPackage ? existing?.expiryDate : nil,
            accountID: isSealPackage ? nil : existing?.accountID,
            certificateSerialNumber: nil,
            ipaRelativePath: files.ipaRelativePath,
            signedIPARelativePath: nil,
            preferredBundleIdentifier: isSealPackage
                ? (currentSealBundleIdentifier ?? existing?.preferredBundleIdentifier ?? parsed.bundleIdentifier)
                : existing?.preferredBundleIdentifier,
            isSeal: isSealPackage,
            isPinned: isSealPackage ? true : (existing?.isPinned ?? false),
            importedAt: isSealPackage ? (existing?.importedAt ?? importedAt) : importedAt,
            extensions: parsed.extensions
        )
    }


    private static func existingRecord(
        for parsed: ParsedIPA,
        in records: [AppRecord]
    ) -> AppRecord? {
        let isCurrentRunningSealPackage = isCurrentSealBundle(parsed.bundleIdentifier)

        if isCurrentRunningSealPackage,
           let currentSeal = records.first(where: { record in
               record.isSeal && matchesSealRecord(record, bundleIdentifier: parsed.bundleIdentifier)
           }) {
            return currentSeal
        }

        return records.first(where: { record in
            guard record.originalBundleIdentifier == parsed.bundleIdentifier else { return false }
            return record.isSeal == false || isCurrentRunningSealPackage
        })
    }


    private static func matchesSealRecord(_ record: AppRecord, bundleIdentifier: String) -> Bool {
        record.originalBundleIdentifier == bundleIdentifier
            || record.mappedBundleIdentifier == bundleIdentifier
            || record.preferredBundleIdentifier == bundleIdentifier
    }

    private static func isCurrentSealBundle(_ bundleIdentifier: String) -> Bool {
        guard let current = Bundle.main.bundleIdentifier else { return false }
        return bundleIdentifier == current
    }

    private static func importFailure(from error: Error) -> ImportFailure {
        if let failure = error as? ImportFailure {
            return failure
        }
        return ImportFailure(
            title: "无法导入 IPA",
            reason: "处理失败",
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
