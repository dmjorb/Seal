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

    func commit(
        staged: StagedIPA,
        appID: UUID,
        iconData: Data?
    ) throws -> StoredAppFiles {
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

            if fileManager.fileExists(atPath: finalDirectory.path) {
                try fileManager.moveItem(at: finalDirectory, to: backupDirectory)
            }
            do {
                try fileManager.moveItem(at: pendingDirectory, to: finalDirectory)
            } catch {
                if fileManager.fileExists(atPath: backupDirectory.path) {
                    try? fileManager.moveItem(at: backupDirectory, to: finalDirectory)
                }
                throw error
            }

            try? fileManager.removeItem(at: backupDirectory)
        } catch is CancellationError {
            try? fileManager.removeItem(at: pendingDirectory)
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(at: pendingDirectory)
            throw ImportFailure(
                title: "无法保存 IPA",
                reason: "本地存储失败",
                recovery: "检查存储空间后重试",
                code: "SEAL-IPA-203"
            )
        }

        return StoredAppFiles(
            ipaRelativePath: "Apps/\(appDirectoryName)/Original.ipa",
            iconRelativePath: iconData == nil
                ? nil
                : "Apps/\(appDirectoryName)/Icon.png"
        )
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
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try protect(destination)
        return relativePath
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
                try? fileManager.removeItem(at: directory)
                continue
            }
            guard let appID = UUID(uuidString: name) else { continue }
            if validAppIDs.contains(appID) == false {
                try? fileManager.removeItem(at: directory)
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

    func clearSignedIPAs() throws {
        let appsRoot = documentsDirectory.appending(path: "Apps", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: appsRoot.path) else { return }
        let directories = try FileManager.default.contentsOfDirectory(
            at: appsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let signedIPA = directory.appending(path: "Signed.ipa")
            if FileManager.default.fileExists(atPath: signedIPA.path) {
                try FileManager.default.removeItem(at: signedIPA)
            }
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

    private func invalidStagedFileFailure() -> ImportFailure {
        ImportFailure(
            title: "无法保存 IPA",
            reason: "临时文件无效",
            recovery: "重新选择 IPA",
            code: "SEAL-IPA-204"
        )
    }
}
