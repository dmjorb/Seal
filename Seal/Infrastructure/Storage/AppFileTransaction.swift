import Foundation

struct AppFileTransaction: Codable, Sendable {
    struct BackupPair: Codable, Sendable {
        let original: URL
        let backup: URL
    }

    let id: UUID
    let files: StoredAppFiles
    let finalURLs: [URL]
    let backupPairs: [BackupPair]
    let pendingURL: URL
    let rollbackNewURLs: [URL]
    let hadOriginalFiles: Bool
}

struct AppFileRemovalTransaction: Codable, Sendable {
    let id: UUID
    let appID: UUID
    let originalURL: URL
    let tombstoneURL: URL
}

enum AppFileStoreOperation: Equatable, Sendable {
    case prepareRemoval
    case rollbackRemoval
    case finalizeRemoval
    case moveNewAside
    case restoreBackup
    case restoreNewFiles
    case removeBackup
    case removeRollbackNew
}

struct AppRecordFingerprint: Codable, Equatable, Sendable {
    let id: UUID
    let originalBundleIdentifier: String
    let name: String
    let version: String
    let buildNumber: String
    let size: Int64
    let ipaRelativePath: String
    let importedAt: Date

    init(_ record: AppRecord) {
        id = record.id
        originalBundleIdentifier = record.originalBundleIdentifier
        name = record.name
        version = record.version
        buildNumber = record.buildNumber
        size = record.size
        ipaRelativePath = record.ipaRelativePath
        importedAt = record.importedAt
    }

    func matches(_ record: AppRecord) -> Bool {
        self == AppRecordFingerprint(record)
    }
}
