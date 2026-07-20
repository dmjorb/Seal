import Foundation

struct AppRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let originalBundleIdentifier: String
    var mappedBundleIdentifier: String?
    let name: String
    let version: String
    let buildNumber: String
    let size: Int64
    var iconRelativePath: String?
    var state: AppState
    var expiryDate: Date?
    var accountID: UUID?
    var certificateSerialNumber: String?
    let ipaRelativePath: String
    var signedIPARelativePath: String?
    var preferredBundleIdentifier: String?
    let isSeal: Bool
    var isPinned: Bool
    let importedAt: Date
    var extensions: [AppExtensionRecord]

    init(
        id: UUID = UUID(),
        originalBundleIdentifier: String,
        mappedBundleIdentifier: String? = nil,
        name: String,
        version: String,
        buildNumber: String,
        size: Int64,
        iconRelativePath: String? = nil,
        state: AppState,
        expiryDate: Date? = nil,
        accountID: UUID? = nil,
        certificateSerialNumber: String? = nil,
        ipaRelativePath: String,
        signedIPARelativePath: String? = nil,
        preferredBundleIdentifier: String? = nil,
        isSeal: Bool = false,
        isPinned: Bool = false,
        importedAt: Date,
        extensions: [AppExtensionRecord] = []
    ) {
        self.id = id
        self.originalBundleIdentifier = originalBundleIdentifier
        self.mappedBundleIdentifier = mappedBundleIdentifier
        self.name = name
        self.version = version
        self.buildNumber = buildNumber
        self.size = size
        self.iconRelativePath = iconRelativePath
        self.state = state
        self.expiryDate = expiryDate
        self.accountID = accountID
        self.certificateSerialNumber = certificateSerialNumber
        self.ipaRelativePath = ipaRelativePath
        self.signedIPARelativePath = signedIPARelativePath
        self.preferredBundleIdentifier = preferredBundleIdentifier
        self.isSeal = isSeal
        self.isPinned = isPinned
        self.importedAt = importedAt
        self.extensions = extensions
    }
}
