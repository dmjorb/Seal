import Foundation

struct StoredAppFiles: Equatable, Sendable {
    let ipaRelativePath: String
    let iconRelativePath: String?
    let preferredIconRelativePath: String?

    init(
        ipaRelativePath: String,
        iconRelativePath: String?,
        preferredIconRelativePath: String? = nil
    ) {
        self.ipaRelativePath = ipaRelativePath
        self.iconRelativePath = iconRelativePath
        self.preferredIconRelativePath = preferredIconRelativePath
    }
}

enum ImportFileTransactionPhase: String, Codable, Sendable {
    case prepared
    case databaseCommitPending
    case finalized
}

struct PreparedAppFileTransaction: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let appID: UUID
    let pendingDirectoryName: String
    let backupDirectoryName: String
    let hadExistingFinalDirectory: Bool
    let files: StoredAppFilesCodable
    var phase: ImportFileTransactionPhase

    var storedFiles: StoredAppFiles {
        StoredAppFiles(
            ipaRelativePath: files.ipaRelativePath,
            iconRelativePath: files.iconRelativePath,
            preferredIconRelativePath: files.preferredIconRelativePath
        )
    }
}

struct StoredAppFilesCodable: Codable, Equatable, Sendable {
    let ipaRelativePath: String
    let iconRelativePath: String?
    let preferredIconRelativePath: String?

    init(_ files: StoredAppFiles) {
        ipaRelativePath = files.ipaRelativePath
        iconRelativePath = files.iconRelativePath
        preferredIconRelativePath = files.preferredIconRelativePath
    }
}
