import CryptoKit
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

actor AppFileStore {
    private let documentsDirectory: URL
    private let temporaryDirectory: URL
    private let fileProtector: any FileProtecting

    init(
        documentsDirectory: URL,
        cacheDirectory: URL,
        fileProtector: any FileProtecting = CompleteFileProtector()
    ) {
        self.documentsDirectory = documentsDirectory.standardizedFileURL
        self.fileProtector = fileProtector
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
            do {
                try Self.removeIfExists(directory, fileManager: fileManager)
            } catch {
                throw Self.temporaryCleanupFailure(
                    reason: "导入已取消，但暂存目录无法删除。"
                )
            }
            throw CancellationError()
        } catch let failure as ImportFailure {
            do {
                try Self.removeIfExists(directory, fileManager: fileManager)
            } catch {
                throw Self.temporaryCleanupFailure(
                    reason: "导入失败，且暂存目录无法删除。"
                )
            }
            throw failure
        } catch {
            do {
                try Self.removeIfExists(directory, fileManager: fileManager)
            } catch {
                throw Self.temporaryCleanupFailure(
                    reason: "文件复制失败，且暂存目录无法删除。"
                )
            }
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
                reason: "本机文件无法读取。",
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

    func prepareImportCommit(
        staged: StagedIPA,
        appID: UUID,
        iconData: Data?,
        preferredIconData: Data? = nil
    ) throws -> PreparedAppFileTransaction {
        try Task.checkCancellation()
        guard isDescendant(staged.url, of: temporaryDirectory) else {
            throw invalidStagedFileFailure()
        }

        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appsRoot, withIntermediateDirectories: true)

        let transactionID = UUID()
        let appDirectoryName = appID.uuidString
        let pendingDirectoryName = ".\(appDirectoryName).pending-\(transactionID.uuidString)"
        let backupDirectoryName = ".\(appDirectoryName).backup-\(transactionID.uuidString)"
        let finalDirectory = appsRoot.appending(path: appDirectoryName, directoryHint: .isDirectory)
        let pendingDirectory = appsRoot.appending(path: pendingDirectoryName, directoryHint: .isDirectory)

        let files = StoredAppFiles(
            ipaRelativePath: "Apps/\(appDirectoryName)/Original.ipa",
            iconRelativePath: iconData == nil ? nil : "Apps/\(appDirectoryName)/Icon.png",
            preferredIconRelativePath: preferredIconData == nil ? nil : "Apps/\(appDirectoryName)/PreferredIcon.png"
        )
        var transaction = PreparedAppFileTransaction(
            id: transactionID,
            appID: appID,
            pendingDirectoryName: pendingDirectoryName,
            backupDirectoryName: backupDirectoryName,
            hadExistingFinalDirectory: fileManager.fileExists(atPath: finalDirectory.path),
            files: StoredAppFilesCodable(files),
            phase: .prepared
        )

        do {
            try fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            let pendingIPA = pendingDirectory.appending(path: "Original.ipa")
            try fileManager.copyItem(at: staged.url, to: pendingIPA)
            try protect(pendingIPA)
            guard (try? pendingIPA.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 > 0 }) == true else {
                throw invalidStagedFileFailure()
            }

            if let iconData {
                let iconURL = pendingDirectory.appending(path: "Icon.png")
                try iconData.write(to: iconURL, options: .atomic)
                try protect(iconURL)
            }
            if let preferredIconData {
                let preferredIconURL = pendingDirectory.appending(path: "PreferredIcon.png")
                try preferredIconData.write(to: preferredIconURL, options: .atomic)
                try protect(preferredIconURL)
            }
            try protect(pendingDirectory)
            try writeImportTransactionJournal(transaction)
            return transaction
        } catch is CancellationError {
            do {
                try Self.removeIfExists(pendingDirectory, fileManager: fileManager)
                try removeImportTransactionJournal(id: transaction.id)
            } catch {
                throw Self.importRecoveryFailure(
                    reason: "导入准备已取消，但临时事务文件无法完整清理。"
                )
            }
            throw CancellationError()
        } catch {
            do {
                try Self.removeIfExists(pendingDirectory, fileManager: fileManager)
                try removeImportTransactionJournal(id: transaction.id)
            } catch {
                throw Self.importRecoveryFailure(
                    reason: "导入准备失败，且临时事务文件无法完整清理。"
                )
            }
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "本地存储准备失败",
                recovery: "检查存储空间后重试",
                code: "SEAL-IPA-203"
            )
        }
    }

    func markDatabaseCommitPending(
        _ transaction: PreparedAppFileTransaction
    ) throws -> PreparedAppFileTransaction {
        var updated = transaction
        updated.phase = .databaseCommitPending
        try writeImportTransactionJournal(updated)
        return updated
    }

    func finalizeImportCommit(
        _ transaction: PreparedAppFileTransaction
    ) throws -> PreparedAppFileTransaction {
        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let finalDirectory = appsRoot.appending(path: transaction.appID.uuidString, directoryHint: .isDirectory)
        let pendingDirectory = appsRoot.appending(path: transaction.pendingDirectoryName, directoryHint: .isDirectory)
        let backupDirectory = appsRoot.appending(path: transaction.backupDirectoryName, directoryHint: .isDirectory)

        // Idempotent finalize: useful when recovering after the app was terminated.
        if fileManager.fileExists(atPath: pendingDirectory.path) == false,
           fileManager.fileExists(atPath: finalDirectory.path) {
            var updated = transaction
            updated.phase = .finalized
            try writeImportTransactionJournal(updated)
            return updated
        }

        guard fileManager.fileExists(atPath: pendingDirectory.path) else {
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "待提交文件缺失",
                recovery: "重新导入 IPA",
                code: "SEAL-IPA-211"
            )
        }

        do {
            if fileManager.fileExists(atPath: finalDirectory.path),
               fileManager.fileExists(atPath: backupDirectory.path) == false {
                try fileManager.moveItem(at: finalDirectory, to: backupDirectory)
            }
            do {
                try fileManager.moveItem(at: pendingDirectory, to: finalDirectory)
            } catch {
                if fileManager.fileExists(atPath: backupDirectory.path) {
                    guard fileManager.fileExists(atPath: finalDirectory.path) == false else {
                        throw Self.importRecoveryFailure(
                            reason: "新旧应用目录同时存在，无法安全恢复旧文件。"
                        )
                    }
                    do {
                        try fileManager.moveItem(at: backupDirectory, to: finalDirectory)
                    } catch {
                        throw Self.importRecoveryFailure(
                            reason: "文件提交失败，并且旧应用目录恢复失败。"
                        )
                    }
                }
                throw error
            }
            var updated = transaction
            updated.phase = .finalized
            try writeImportTransactionJournal(updated)
            return updated
        } catch let failure as ImportFailure {
            throw failure
        } catch {
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "文件提交失败",
                recovery: "检查存储空间后重试",
                code: "SEAL-IPA-212"
            )
        }
    }

    func completeImportCommit(_ transaction: PreparedAppFileTransaction) throws {
        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let backupDirectory = appsRoot.appending(path: transaction.backupDirectoryName, directoryHint: .isDirectory)
        let pendingDirectory = appsRoot.appending(path: transaction.pendingDirectoryName, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.removeItem(at: backupDirectory)
        }
        if fileManager.fileExists(atPath: pendingDirectory.path) {
            try fileManager.removeItem(at: pendingDirectory)
        }
        try removeImportTransactionJournal(id: transaction.id)
    }

    func abortImportCommit(_ transaction: PreparedAppFileTransaction) throws {
        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        let finalDirectory = appsRoot.appending(path: transaction.appID.uuidString, directoryHint: .isDirectory)
        let backupDirectory = appsRoot.appending(path: transaction.backupDirectoryName, directoryHint: .isDirectory)
        let pendingDirectory = appsRoot.appending(path: transaction.pendingDirectoryName, directoryHint: .isDirectory)

        if transaction.phase == .finalized {
            if fileManager.fileExists(atPath: backupDirectory.path) {
                if fileManager.fileExists(atPath: finalDirectory.path) {
                    try fileManager.removeItem(at: finalDirectory)
                }
                try fileManager.moveItem(at: backupDirectory, to: finalDirectory)
            } else if transaction.hadExistingFinalDirectory == false,
                      fileManager.fileExists(atPath: finalDirectory.path) {
                try fileManager.removeItem(at: finalDirectory)
            }
        }
        if fileManager.fileExists(atPath: pendingDirectory.path) {
            try fileManager.removeItem(at: pendingDirectory)
        }
        try removeImportTransactionJournal(id: transaction.id)
    }

    func pendingImportTransactions() throws -> [PreparedAppFileTransaction] {
        let directory = importTransactionsDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let journalURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        let transactions = try journalURLs.map { url in
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(PreparedAppFileTransaction.self, from: data)
            } catch {
                throw Self.importRecoveryFailure(
                    reason: "本地导入事务记录无法读取，已保留原文件以便诊断。"
                )
            }
        }
        return transactions.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Compatibility helper used by existing tests/callers that do not have a
    /// database transaction. New imports use prepare -> DB -> finalize -> complete.
    func commit(
        staged: StagedIPA,
        appID: UUID,
        iconData: Data?
    ) throws -> StoredAppFiles {
        var transaction = try prepareImportCommit(staged: staged, appID: appID, iconData: iconData)
        do {
            transaction = try finalizeImportCommit(transaction)
            try completeImportCommit(transaction)
            return transaction.storedFiles
        } catch {
            let originalError = error
            do {
                try abortImportCommit(transaction)
            } catch {
                throw Self.importRecoveryFailure(
                    reason: "文件提交失败，并且回滚未能完成。"
                )
            }
            throw originalError
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

    func rollback(_ files: StoredAppFiles) throws {
        let ipaURL = documentsDirectory.appending(path: files.ipaRelativePath)
        guard isDescendant(ipaURL, of: documentsDirectory.appending(path: "Apps")) else {
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

    func storedSignedIPA(appID: UUID) throws -> (relativePath: String, url: URL)? {
        let relativePath = "Apps/\(appID.uuidString)/Signed.ipa"
        let url = try fileURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (relativePath, url)
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
        let destination = documentsDirectory.appending(path: relativePath).standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        guard isDescendant(destination, of: documentsDirectory) else {
            throw invalidStagedFileFailure()
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = directory.appending(path: ".Signed.pending-\(UUID().uuidString).ipa")
        let backup = directory.appending(path: ".Signed.backup-\(UUID().uuidString).ipa")
        do {
            try fileManager.copyItem(at: sourceURL, to: pending)
            try protect(pending)
            guard (try? pending.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 > 0 }) == true else {
                throw invalidStagedFileFailure()
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
            }
            do {
                try fileManager.moveItem(at: pending, to: destination)
            } catch {
                if fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }
            try? fileManager.removeItem(at: backup)
            return relativePath
        } catch {
            try? fileManager.removeItem(at: pending)
            if fileManager.fileExists(atPath: destination.path) == false,
               fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    func sha256(relativePath: String) throws -> String {
        let url = try fileURL(relativePath: relativePath)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func validateSHA256(relativePath: String, expected: String) throws -> Bool {
        try sha256(relativePath: relativePath).caseInsensitiveCompare(expected) == .orderedSame
    }

    func storePreferredIcon(data: Data, appID: UUID) throws -> String {
        let relativePath = "Apps/\(appID.uuidString)/PreferredIcon.png"
        let destination = try fileURL(relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        try protect(destination)
        return relativePath
    }

    func removePreferredIcon(appID: UUID) throws {
        let relativePath = "Apps/\(appID.uuidString)/PreferredIcon.png"
        let url = try fileURL(relativePath: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func makeSignedIPAExportCopy(
        relativePath: String,
        fileName: String,
        appID: UUID
    ) throws -> URL {
        let source = try fileURL(relativePath: relativePath)
        let exports = exportDirectory(appID: appID)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let safeName = fileName.isEmpty ? "Seal-Signed.ipa" : fileName
        let destination = exports.appending(path: safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try protect(destination)
        return destination
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
        let exports = exportDirectory(appID: appID)
        if FileManager.default.fileExists(atPath: exports.path) {
            try FileManager.default.removeItem(at: exports)
        }
    }

    private func exportDirectory(appID: UUID) -> URL {
        temporaryDirectory
            .deletingLastPathComponent()
            .appending(path: "Exports", directoryHint: .isDirectory)
            .appending(path: appID.uuidString, directoryHint: .isDirectory)
    }

    func clearOrphanedAppFiles(validAppIDs: Set<UUID>) throws {
        let fileManager = FileManager.default
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: appsRoot.path) else { return }

        let directories = try fileManager.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for directory in directories {
            let name = directory.lastPathComponent
            if name.hasPrefix(".") {
                try fileManager.removeItem(at: directory)
                continue
            }
            guard let appID = UUID(uuidString: name) else { continue }
            if validAppIDs.contains(appID) == false {
                try fileManager.removeItem(at: directory)
            }
        }
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

    func clearTemporaryFiles() throws {
        let sealCache = temporaryDirectory.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: sealCache.path) {
            try FileManager.default.removeItem(at: sealCache)
        }
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


    private var importTransactionsDirectory: URL {
        documentsDirectory.appending(path: "Transactions", directoryHint: .isDirectory)
    }

    private func importTransactionJournalURL(id: UUID) -> URL {
        importTransactionsDirectory.appending(path: "import-\(id.uuidString).json")
    }

    private func writeImportTransactionJournal(_ transaction: PreparedAppFileTransaction) throws {
        let directory = importTransactionsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(transaction)
        let url = importTransactionJournalURL(id: transaction.id)
        try data.write(to: url, options: .atomic)
        try protect(url)
    }

    private func removeImportTransactionJournal(id: UUID) throws {
        let url = importTransactionJournalURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
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

    private func isDescendant(_ candidate: URL, of parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath.hasPrefix("/\(parentPath)/")
    }

    private static func removeIfExists(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func temporaryCleanupFailure(reason: String) -> ImportFailure {
        ImportFailure(
            title: "临时文件清理失败",
            reason: reason,
            recovery: "稍后在存储维护中重试清理",
            code: "SEAL-STORAGE-IMPORT-002"
        )
    }

    private static func importRecoveryFailure(reason: String) -> ImportFailure {
        ImportFailure(
            title: "导入事务恢复未完成",
            reason: reason,
            recovery: "重新打开 Seal 后重试；如持续失败请复制诊断日志",
            code: "SEAL-IPA-RECOVERY-003"
        )
    }

    private func invalidStagedFileFailure() -> ImportFailure {
        ImportFailure(
            title: "无法保存 IPA",
            reason: "临时文件无效",
            recovery: "重新选择 IPA",
            code: "SEAL-IPA-204"
        )
    }
}
