import Foundation
import ZIPFoundation

struct SettingsStorageUsage: Equatable, Sendable {
    var originalIPAs: Int64
    var signedIPAs: Int64
    var appData: Int64
    var temporary: Int64

    static let empty = SettingsStorageUsage(
        originalIPAs: 0,
        signedIPAs: 0,
        appData: 0,
        temporary: 0
    )

    var total: Int64 {
        originalIPAs + signedIPAs + appData + temporary
    }
}

struct StoredOriginalIPA: Sendable {
    let appID: UUID
    let relativePath: String
    let url: URL
}

struct AppFileCleanupResult: Equatable, Sendable {
    var skippedAppIDs: Set<UUID> = []
}

enum AppStorageCleanupPolicy {
    static func canRemoveImportedRecord(
        _ app: AppRecord,
        leasedAppIDs: Set<UUID>
    ) -> Bool {
        guard leasedAppIDs.contains(app.id) == false,
              app.isSeal == false,
              app.state != .installed,
              app.lastInstalledAt == nil,
              app.expiryDate == nil else {
            return false
        }
        return true
    }
}

actor AppFileStore {
    private let documentsDirectory: URL
    private let temporaryDirectory: URL
    private let fileProtector: any FileProtecting
    private let beforeFileOperation: @Sendable (AppFileStoreOperation) throws -> Void

    init(
        documentsDirectory: URL,
        cacheDirectory: URL,
        fileProtector: any FileProtecting = CompleteFileProtector(),
        beforeFileOperation: @escaping @Sendable (AppFileStoreOperation) throws -> Void = { _ in }
    ) {
        self.documentsDirectory = documentsDirectory.standardizedFileURL
        self.fileProtector = fileProtector
        self.beforeFileOperation = beforeFileOperation
        temporaryDirectory = cacheDirectory
            .appending(path: "Seal/Temp", directoryHint: .isDirectory)
            .standardizedFileURL
        try? FileManager.default.removeItem(
            at: temporaryDirectory.deletingLastPathComponent()
        )
    }

    static func live() throws -> AppFileStore {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first,
        let cache = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "应用目录不可用",
                recovery: "重新打开 Seal",
                code: "SEAL-IPA-201"
            )
        }
        return AppFileStore(documentsDirectory: documents, cacheDirectory: cache)
    }

    func stage(sourceURL: URL) throws -> StagedIPA {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let id = UUID()
        let directory = temporaryDirectory
            .appending(path: id.uuidString, directoryHint: .isDirectory)
        let stagedURL = directory.appending(path: "Input.ipa")
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try copyImportSource(sourceURL, to: stagedURL)
            try protect(stagedURL)
            return StagedIPA(id: id, url: stagedURL)
        } catch is CancellationError {
            try? fileManager.removeItem(at: directory)
            throw CancellationError()
        } catch let failure as ImportFailure {
            try? fileManager.removeItem(at: directory)
            throw failure
        } catch {
            try? fileManager.removeItem(at: directory)
            throw ImportFailure(
                title: "无法导入 IPA",
                reason: "文件复制失败",
                recovery: "重新选择 IPA",
                code: "SEAL-IPA-202"
            )
        }
    }

    private func copyImportSource(_ sourceURL: URL, to stagedURL: URL) throws {
        let fileExtension = sourceURL.pathExtension.lowercased()

        if fileExtension == "ipa" {
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
            return
        }

        if fileExtension == "zip" {
            try copyOrExtractZIPImportSource(sourceURL, to: stagedURL)
            return
        }

        if isReadableZIPArchive(sourceURL) {
            try copyOrExtractZIPImportSource(sourceURL, to: stagedURL)
            return
        }

        throw ImportFailure(
            title: "无法导入 IPA",
            reason: "请选择 .ipa 文件，或包含单个 .ipa 的 GitHub 构建产物 zip。当前文件：\(sourceURL.lastPathComponent)",
            recovery: "重新选择文件",
            code: "SEAL-IPA-207"
        )
    }

    private func copyOrExtractZIPImportSource(_ sourceURL: URL, to stagedURL: URL) throws {
        let archive = try openArchive(sourceURL)

        if archiveContainsPayloadApp(archive) {
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
            return
        }

        try extractSingleIPA(from: archive, to: stagedURL)
    }

    private func isReadableZIPArchive(_ sourceURL: URL) -> Bool {
        (try? Archive(url: sourceURL, accessMode: .read)) != nil
    }

    private func openArchive(_ sourceURL: URL) throws -> Archive {
        do {
            return try Archive(url: sourceURL, accessMode: .read)
        } catch {
            throw ImportFailure(
                title: "无法导入构建产物",
                reason: "来源：文件系统\n原始返回：文件无法读取",
                recovery: "重新选择",
                code: "SEAL-IPA-208"
            )
        }
    }

    private func archiveContainsPayloadApp(_ archive: Archive) -> Bool {
        archive.contains { entry in
            let path = entry.path.lowercased()
            return path.hasPrefix("payload/") && path.contains(".app/")
        }
    }

    private func extractSingleIPA(from archive: Archive, to stagedURL: URL) throws {
        let ipaEntries = archive.filter { entry in
            entry.type == .file && entry.path.lowercased().hasSuffix(".ipa")
        }

        guard ipaEntries.count == 1, let ipaEntry = ipaEntries.first else {
            throw ImportFailure(
                title: "无法导入构建产物",
                reason: ipaEntries.isEmpty ? "压缩包中没有找到 IPA。" : "压缩包中包含多个 IPA，无法判断要导入哪一个。",
                recovery: "先在文件 App 中解压，再选择具体 IPA",
                code: "SEAL-IPA-209"
            )
        }

        do {
            try archive.extract(ipaEntry, to: stagedURL)
        } catch {
            throw ImportFailure(
                title: "无法导入构建产物",
                reason: "无法从压缩包中取出 IPA。",
                recovery: "先解压后再导入 IPA",
                code: "SEAL-IPA-210"
            )
        }
    }

    func prepareCommit(
        staged: StagedIPA,
        appID: UUID,
        iconData: Data?
    ) throws -> AppFileTransaction {
        try Task.checkCancellation()
        guard isDescendant(staged.url, of: temporaryDirectory) else {
            throw invalidStagedFileFailure()
        }

        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(
            path: "Apps",
            directoryHint: .isDirectory
        )
        let appDirectoryName = appID.uuidString
        let finalDirectory = appsRoot.appending(
            path: appDirectoryName,
            directoryHint: .isDirectory
        )
        let pendingDirectory = appsRoot.appending(
            path: ".\(appDirectoryName).pending-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let backupDirectory = appsRoot.appending(
            path: ".\(appDirectoryName).backup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let transactionID = UUID()
        let rollbackNewDirectory = appsRoot.appending(
            path: ".\(appDirectoryName).rollback-new-\(transactionID.uuidString)",
            directoryHint: .isDirectory
        )
        let hadOriginalFiles = fileManager.fileExists(atPath: finalDirectory.path)
        let transaction = AppFileTransaction(
            id: transactionID,
            files: StoredAppFiles(
                ipaRelativePath: "Apps/\(appDirectoryName)/Original.ipa",
                iconRelativePath: iconData == nil
                    ? nil
                    : "Apps/\(appDirectoryName)/Icon.png"
            ),
            finalURLs: [finalDirectory],
            backupPairs: hadOriginalFiles
                ? [.init(original: finalDirectory, backup: backupDirectory)]
                : [],
            pendingURL: pendingDirectory,
            rollbackNewURLs: [rollbackNewDirectory],
            hadOriginalFiles: hadOriginalFiles
        )
        var journalWasWritten = false

        do {
            try fileManager.createDirectory(
                at: pendingDirectory,
                withIntermediateDirectories: true
            )
            let pendingIPA = pendingDirectory.appending(path: "Original.ipa")
            try fileManager.copyItem(at: staged.url, to: pendingIPA)
            try protect(pendingIPA)

            if let iconData {
                let iconURL = pendingDirectory.appending(path: "Icon.png")
                try iconData.write(to: iconURL, options: .atomic)
                try protect(iconURL)
            }
            try protect(pendingDirectory)
            try writeJournal(
                TransactionJournal(transaction: transaction, phase: .preparing)
            )
            journalWasWritten = true

            if hadOriginalFiles {
                try fileManager.moveItem(at: finalDirectory, to: backupDirectory)
            }
            try fileManager.moveItem(at: pendingDirectory, to: finalDirectory)
            try updateJournal(transactionID: transaction.id) { journal in
                journal.phase = .prepared
            }
        } catch is CancellationError {
            if journalWasWritten {
                do {
                    try rollback(transaction)
                } catch {
                    throw transactionFailure(
                        reason: "取消后无法恢复文件；恢复操作已记录并将在下次启动重试"
                    )
                }
            } else if fileManager.fileExists(atPath: pendingDirectory.path) {
                try fileManager.removeItem(at: pendingDirectory)
            }
            throw CancellationError()
        } catch {
            if journalWasWritten {
                do {
                    try rollback(transaction)
                } catch {
                    throw transactionFailure(
                        reason: "保存失败且无法恢复旧文件；恢复操作已记录并将在下次启动重试"
                    )
                }
            } else if fileManager.fileExists(atPath: pendingDirectory.path) {
                try fileManager.removeItem(at: pendingDirectory)
            }
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "本地存储失败",
                recovery: "检查存储空间后重试",
                code: "SEAL-IPA-203"
            )
        }

        return transaction
    }

    func finalize(_ transaction: AppFileTransaction) throws {
        do {
            try validate(transaction)
            try updateJournal(transactionID: transaction.id) { journal in
                journal.phase = .committed
            }
            for pair in transaction.backupPairs
            where FileManager.default.fileExists(atPath: pair.backup.path) {
                try beforeFileOperation(.removeBackup)
                try FileManager.default.removeItem(at: pair.backup)
            }
            try removeJournal(transactionID: transaction.id)
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw transactionFailure(
                reason: "数据库已提交，但旧备份清理失败；清理操作已记录并可重试"
            )
        }
    }

    func setExpectedRecord(
        _ record: AppRecord,
        for transaction: AppFileTransaction
    ) throws {
        try validate(transaction)
        try updateJournal(transactionID: transaction.id) { journal in
            journal.expectedRecord = AppRecordFingerprint(record)
        }
    }

    func recoverTransactions(appRecords: [AppRecord]) throws {
        for journal in try loadJournals() {
            let transaction = journal.transaction
            try validate(transaction)
            let databaseContainsExpectedRecord = journal.expectedRecord.map { expected in
                appRecords.contains(where: expected.matches)
            } ?? false

            if journal.phase == .committed || databaseContainsExpectedRecord {
                try finalize(transaction)
                continue
            }

            if journal.phase == .preparing {
                let backupExists = transaction.backupPairs.contains {
                    FileManager.default.fileExists(atPath: $0.backup.path)
                }
                let pendingExists = FileManager.default.fileExists(
                    atPath: transaction.pendingURL.path
                )
                if transaction.hadOriginalFiles, backupExists == false {
                    if pendingExists {
                        try FileManager.default.removeItem(at: transaction.pendingURL)
                    }
                    try removeJournal(transactionID: transaction.id)
                    continue
                }
                if transaction.hadOriginalFiles == false, pendingExists {
                    try FileManager.default.removeItem(at: transaction.pendingURL)
                    try removeJournal(transactionID: transaction.id)
                    continue
                }
            }
            try rollback(transaction)
        }
    }

    func cancel(_ staged: StagedIPA) throws {
        guard isDescendant(staged.url, of: temporaryDirectory) else {
            throw invalidStagedFileFailure()
        }
        let directory = staged.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func rollback(_ transaction: AppFileTransaction) throws {
        try validate(transaction)
        let fileManager = FileManager.default
        try updateJournal(transactionID: transaction.id) { journal in
            journal.phase = .rollingBack
        }

        for (index, finalURL) in transaction.finalURLs.enumerated() {
            let rollbackNewURL = transaction.rollbackNewURLs[index]
            let backupPair = transaction.backupPairs.first { $0.original == finalURL }
            let backupExists = backupPair.map {
                fileManager.fileExists(atPath: $0.backup.path)
            } ?? false

            if fileManager.fileExists(atPath: rollbackNewURL.path) == false,
               fileManager.fileExists(atPath: finalURL.path),
               backupExists || transaction.hadOriginalFiles == false {
                do {
                    try beforeFileOperation(.moveNewAside)
                    try fileManager.moveItem(at: finalURL, to: rollbackNewURL)
                } catch {
                    throw transactionFailure(
                        reason: "无法暂存新文件；恢复操作已记录并可重试"
                    )
                }
            }

            if let backupPair,
               fileManager.fileExists(atPath: backupPair.backup.path) {
                do {
                    try beforeFileOperation(.restoreBackup)
                    try fileManager.moveItem(at: backupPair.backup, to: backupPair.original)
                } catch {
                    if fileManager.fileExists(atPath: finalURL.path) == false,
                       fileManager.fileExists(atPath: rollbackNewURL.path) {
                        do {
                            try beforeFileOperation(.restoreNewFiles)
                            try fileManager.moveItem(at: rollbackNewURL, to: finalURL)
                            try updateJournal(transactionID: transaction.id) { journal in
                                journal.phase = .prepared
                            }
                        } catch {
                            throw transactionFailure(
                                reason: "旧文件与新文件都无法恢复到正式位置；恢复操作已记录"
                            )
                        }
                    }
                    throw transactionFailure(
                        reason: "旧文件恢复失败；新文件已复位，恢复操作可重试"
                    )
                }
            }

            if fileManager.fileExists(atPath: rollbackNewURL.path) {
                do {
                    try beforeFileOperation(.removeRollbackNew)
                    try fileManager.removeItem(at: rollbackNewURL)
                } catch {
                    throw transactionFailure(
                        reason: "旧文件已恢复，但新文件临时副本清理失败；清理可重试"
                    )
                }
            }
        }
        if fileManager.fileExists(atPath: transaction.pendingURL.path) {
            try fileManager.removeItem(at: transaction.pendingURL)
        }
        try removeJournal(transactionID: transaction.id)
    }

    func removeStoredFiles(_ files: StoredAppFiles) throws {
        let ipaURL = documentsDirectory.appending(path: files.ipaRelativePath)
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard isDescendant(ipaURL, of: appsRoot) else {
            throw invalidStagedFileFailure()
        }
        let directory = ipaURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func read(relativePath: String) throws -> Data {
        let url = try fileURL(relativePath: relativePath)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func fileURL(relativePath: String) throws -> URL {
        let url = documentsDirectory.appending(path: relativePath).standardizedFileURL
        guard isDescendant(url, of: documentsDirectory) else {
            throw invalidStagedFileFailure()
        }
        return url
    }

    func exists(relativePath: String) throws -> Bool {
        let url = try fileURL(relativePath: relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func storedOriginalIPAs() throws -> [StoredOriginalIPA] {
        let appsRoot = documentsDirectory.appending(
            path: "Apps",
            directoryHint: .isDirectory
        )
        guard FileManager.default.fileExists(atPath: appsRoot.path) else { return [] }

        return try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory in
            guard let appID = UUID(uuidString: directory.lastPathComponent) else { return nil }
            let ipaURL = directory.appending(path: "Original.ipa")
            guard FileManager.default.fileExists(atPath: ipaURL.path) else { return nil }
            return StoredOriginalIPA(
                appID: appID,
                relativePath: "Apps/\(appID.uuidString)/Original.ipa",
                url: ipaURL
            )
        }
    }

    func signingWorkspace(appID: UUID) throws -> URL {
        let url = temporaryDirectory
            .deletingLastPathComponent()
            .appending(path: "Signing/\(appID.uuidString)", directoryHint: .isDirectory)
            .standardizedFileURL
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func storeSignedIPA(sourceURL: URL, appID: UUID) throws -> String {
        let relativePath = "Apps/\(appID.uuidString)/Signed.ipa"
        let destination = documentsDirectory.appending(path: relativePath)
        guard isDescendant(destination, of: documentsDirectory) else {
            throw invalidStagedFileFailure()
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try protect(destination)
        return relativePath
    }

    func restoreSignedIPA(
        _ data: Data,
        relativePath: String,
        appID: UUID
    ) throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let appRoot = appsRoot.appending(path: appID.uuidString, directoryHint: .isDirectory)
        let destination = documentsDirectory.appending(path: relativePath).standardizedFileURL
        guard destination.lastPathComponent == "Signed.ipa",
              isDescendant(destination, of: appRoot) else {
            throw invalidStagedFileFailure()
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        try protect(destination)
    }

    func removeSignedIPA(appID: UUID) throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let signedIPA = appsRoot
            .appending(path: appID.uuidString, directoryHint: .isDirectory)
            .appending(path: "Signed.ipa")
            .standardizedFileURL
        guard isDescendant(signedIPA, of: appsRoot) else {
            throw invalidStagedFileFailure()
        }
        if FileManager.default.fileExists(atPath: signedIPA.path) {
            try FileManager.default.removeItem(at: signedIPA)
        }
    }

    @discardableResult
    func clearOrphanedAppFiles(
        validAppIDs: Set<UUID>,
        preserving protectedAppIDs: Set<UUID> = []
    ) throws -> AppFileCleanupResult {
        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: appsRoot.path) else { return AppFileCleanupResult() }
        var result = AppFileCleanupResult()

        let directories = try fileManager.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for directory in directories {
            let name = directory.lastPathComponent
            if name.hasPrefix(".") {
                if name == ".transactions"
                    || name == ".removals"
                    || name.contains(".removing-") {
                    continue
                }
                try? fileManager.removeItem(at: directory)
                continue
            }
            guard let appID = UUID(uuidString: name) else { continue }
            if protectedAppIDs.contains(appID) {
                result.skippedAppIDs.insert(appID)
                continue
            }
            if validAppIDs.contains(appID) == false {
                try? fileManager.removeItem(at: directory)
            }
        }
        return result
    }

    func removeApp(appID: UUID) throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let directory = appsRoot
            .appending(path: appID.uuidString, directoryHint: .isDirectory)
            .standardizedFileURL
        guard isDescendant(directory, of: appsRoot) else {
            throw invalidStagedFileFailure()
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func prepareRemoval(appID: UUID) throws -> AppFileRemovalTransaction {
        try Task.checkCancellation()
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let originalURL = appsRoot
            .appending(path: appID.uuidString, directoryHint: .isDirectory)
            .standardizedFileURL
        let transactionID = UUID()
        let tombstoneURL = appsRoot
            .appending(
                path: ".\(appID.uuidString).removing-\(transactionID.uuidString)",
                directoryHint: .isDirectory
            )
            .standardizedFileURL
        let transaction = AppFileRemovalTransaction(
            id: transactionID,
            appID: appID,
            originalURL: originalURL,
            tombstoneURL: tombstoneURL
        )
        try validate(transaction)
        try writeRemovalJournal(RemovalJournal(transaction: transaction, phase: .preparing))

        do {
            if FileManager.default.fileExists(atPath: originalURL.path) {
                try beforeFileOperation(.prepareRemoval)
                try FileManager.default.moveItem(at: originalURL, to: tombstoneURL)
            }
            try updateRemovalJournal(transactionID: transaction.id) { journal in
                journal.phase = .prepared
            }
            return transaction
        } catch {
            try? rollbackRemoval(transaction)
            throw error
        }
    }

    func finalizeRemoval(_ transaction: AppFileRemovalTransaction) throws {
        try validate(transaction)
        try beforeFileOperation(.finalizeRemoval)
        try updateRemovalJournal(transactionID: transaction.id) { journal in
            journal.phase = .committed
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: transaction.tombstoneURL.path) {
            try fileManager.removeItem(at: transaction.tombstoneURL)
        }
        if fileManager.fileExists(atPath: transaction.originalURL.path) {
            try fileManager.removeItem(at: transaction.originalURL)
        }
        try removeRemovalJournal(transactionID: transaction.id)
    }

    func rollbackRemoval(_ transaction: AppFileRemovalTransaction) throws {
        try validate(transaction)
        let fileManager = FileManager.default
        let originalExists = fileManager.fileExists(atPath: transaction.originalURL.path)
        let tombstoneExists = fileManager.fileExists(atPath: transaction.tombstoneURL.path)
        if tombstoneExists, originalExists == false {
            try beforeFileOperation(.rollbackRemoval)
            try fileManager.moveItem(at: transaction.tombstoneURL, to: transaction.originalURL)
        } else if tombstoneExists, originalExists {
            throw transactionFailure(reason: "删除回滚检测到冲突目录；恢复操作将在下次启动重试")
        }
        try removeRemovalJournal(transactionID: transaction.id)
    }

    func recoverRemovals(appRecords: [AppRecord]) throws {
        let existingIDs = Set(appRecords.map(\.id))
        for journal in try loadRemovalJournals() {
            if existingIDs.contains(journal.transaction.appID) {
                try rollbackRemoval(journal.transaction)
            } else {
                try finalizeRemoval(journal.transaction)
            }
        }
    }

    @discardableResult
    func clearTemporaryFiles(
        excluding protectedAppIDs: Set<UUID> = []
    ) throws -> AppFileCleanupResult {
        let sealCache = temporaryDirectory.deletingLastPathComponent()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sealCache.path) else {
            return AppFileCleanupResult()
        }
        guard protectedAppIDs.isEmpty == false else {
            try FileManager.default.removeItem(at: sealCache)
            return AppFileCleanupResult()
        }

        var result = AppFileCleanupResult()
        if fileManager.fileExists(atPath: temporaryDirectory.path) {
            result.skippedAppIDs.formUnion(protectedAppIDs)
        }
        let signingRoot = sealCache.appending(path: "Signing", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: signingRoot.path) {
            for directory in try fileManager.contentsOfDirectory(
                at: signingRoot,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                if let appID = UUID(uuidString: directory.lastPathComponent),
                   protectedAppIDs.contains(appID) {
                    result.skippedAppIDs.insert(appID)
                } else {
                    try fileManager.removeItem(at: directory)
                }
            }
        }
        return result
    }

    func storageUsage() throws -> SettingsStorageUsage {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let sealCache = temporaryDirectory.deletingLastPathComponent()
        var usage = SettingsStorageUsage.empty

        if FileManager.default.fileExists(atPath: appsRoot.path) {
            try enumerateFiles(at: appsRoot) { url, size in
                switch url.lastPathComponent.lowercased() {
                case "original.ipa":
                    usage.originalIPAs += size
                case "signed.ipa":
                    usage.signedIPAs += size
                default:
                    usage.appData += size
                }
            }
        }

        if FileManager.default.fileExists(atPath: sealCache.path) {
            usage.temporary = try directorySize(at: sealCache)
        }
        return usage
    }

    @discardableResult
    func clearSignedIPAs(
        excluding protectedAppIDs: Set<UUID> = []
    ) throws -> AppFileCleanupResult {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: appsRoot.path) else {
            return AppFileCleanupResult()
        }
        var result = AppFileCleanupResult()
        let directories = try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            guard let appID = UUID(uuidString: directory.lastPathComponent) else { continue }
            let signedIPA = directory.appending(path: "Signed.ipa")
            if FileManager.default.fileExists(atPath: signedIPA.path) {
                if protectedAppIDs.contains(appID) {
                    result.skippedAppIDs.insert(appID)
                } else {
                    try FileManager.default.removeItem(at: signedIPA)
                }
            }
        }
        return result
    }


    private func directorySize(at url: URL) throws -> Int64 {
        var total: Int64 = 0
        try enumerateFiles(at: url) { _, size in
            total += size
        }
        return total
    }

    private func enumerateFiles(
        at directory: URL,
        _ body: (URL, Int64) throws -> Void
    ) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true { continue }
            try body(url, Int64(values.fileSize ?? 0))
        }
    }

    private func protect(_ url: URL) throws {
        try fileProtector.protect(url)
    }

    private var transactionJournalDirectory: URL {
        documentsDirectory.appending(
            path: "Apps/.transactions",
            directoryHint: .isDirectory
        )
    }

    private var removalJournalDirectory: URL {
        documentsDirectory.appending(
            path: "Apps/.removals",
            directoryHint: .isDirectory
        )
    }

    private func journalURL(transactionID: UUID) -> URL {
        transactionJournalDirectory.appending(path: "\(transactionID.uuidString).json")
    }

    private func removalJournalURL(transactionID: UUID) -> URL {
        removalJournalDirectory.appending(path: "\(transactionID.uuidString).json")
    }

    private func writeJournal(_ journal: TransactionJournal) throws {
        try FileManager.default.createDirectory(
            at: transactionJournalDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(journal)
        try data.write(to: journalURL(transactionID: journal.transaction.id), options: .atomic)
    }

    private func updateJournal(
        transactionID: UUID,
        _ update: (inout TransactionJournal) -> Void
    ) throws {
        let url = journalURL(transactionID: transactionID)
        let data = try Data(contentsOf: url)
        var journal = try JSONDecoder().decode(TransactionJournal.self, from: data)
        update(&journal)
        try writeJournal(journal)
    }

    private func loadJournals() throws -> [TransactionJournal] {
        guard FileManager.default.fileExists(atPath: transactionJournalDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: transactionJournalDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { url in
            try JSONDecoder().decode(
                TransactionJournal.self,
                from: Data(contentsOf: url)
            )
        }
    }

    private func removeJournal(transactionID: UUID) throws {
        let fileManager = FileManager.default
        let url = journalURL(transactionID: transactionID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.fileExists(atPath: transactionJournalDirectory.path) else { return }
        let remaining = try fileManager.contentsOfDirectory(
            at: transactionJournalDirectory,
            includingPropertiesForKeys: nil
        )
        if remaining.isEmpty {
            try fileManager.removeItem(at: transactionJournalDirectory)
        }
    }

    private func writeRemovalJournal(_ journal: RemovalJournal) throws {
        try FileManager.default.createDirectory(
            at: removalJournalDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(journal)
        try data.write(
            to: removalJournalURL(transactionID: journal.transaction.id),
            options: .atomic
        )
    }

    private func updateRemovalJournal(
        transactionID: UUID,
        _ update: (inout RemovalJournal) -> Void
    ) throws {
        let url = removalJournalURL(transactionID: transactionID)
        var journal = try JSONDecoder().decode(
            RemovalJournal.self,
            from: Data(contentsOf: url)
        )
        update(&journal)
        try writeRemovalJournal(journal)
    }

    private func loadRemovalJournals() throws -> [RemovalJournal] {
        guard FileManager.default.fileExists(atPath: removalJournalDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: removalJournalDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { url in
            try JSONDecoder().decode(
                RemovalJournal.self,
                from: Data(contentsOf: url)
            )
        }
    }

    private func removeRemovalJournal(transactionID: UUID) throws {
        let fileManager = FileManager.default
        let url = removalJournalURL(transactionID: transactionID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard fileManager.fileExists(atPath: removalJournalDirectory.path) else { return }
        if try fileManager.contentsOfDirectory(
            at: removalJournalDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty {
            try fileManager.removeItem(at: removalJournalDirectory)
        }
    }

    private func transactionFailure(reason: String) -> ImportFailure {
        ImportFailure(
            title: "文件事务恢复未完成",
            reason: reason,
            recovery: "重试恢复；若问题持续，请重新打开 Seal",
            code: "SEAL-IPA-206"
        )
    }

    private func validate(_ transaction: AppFileTransaction) throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let urls = transaction.finalURLs + transaction.backupPairs.flatMap {
            [$0.original, $0.backup]
        } + transaction.rollbackNewURLs + [transaction.pendingURL]
        guard transaction.finalURLs.count == transaction.rollbackNewURLs.count,
              urls.allSatisfy({ isDescendant($0, of: appsRoot) }) else {
            throw invalidStagedFileFailure()
        }
    }

    private func validate(_ transaction: AppFileRemovalTransaction) throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard isDescendant(transaction.originalURL, of: appsRoot),
              isDescendant(transaction.tombstoneURL, of: appsRoot),
              transaction.originalURL.lastPathComponent == transaction.appID.uuidString,
              transaction.tombstoneURL.lastPathComponent.hasPrefix(
                ".\(transaction.appID.uuidString).removing-"
              ) else {
            throw invalidStagedFileFailure()
        }
    }

    private func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath.hasPrefix("/\(parentPath)/")
    }

    private func invalidStagedFileFailure() -> ImportFailure {
        ImportFailure(
            title: "无法保存 IPA",
            reason: "临时文件无效",
            recovery: "重新选择 IPA",
            code: "SEAL-IPA-204"
        )
    }

    private struct TransactionJournal: Codable, Sendable {
        var transaction: AppFileTransaction
        var phase: Phase
        var expectedRecord: AppRecordFingerprint?

        init(
            transaction: AppFileTransaction,
            phase: Phase,
            expectedRecord: AppRecordFingerprint? = nil
        ) {
            self.transaction = transaction
            self.phase = phase
            self.expectedRecord = expectedRecord
        }

        enum Phase: String, Codable, Sendable {
            case preparing
            case prepared
            case committed
            case rollingBack
        }
    }

    private struct RemovalJournal: Codable, Sendable {
        enum Phase: String, Codable, Sendable {
            case preparing
            case prepared
            case committed
        }

        var transaction: AppFileRemovalTransaction
        var phase: Phase
    }
}
