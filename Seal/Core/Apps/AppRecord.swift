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
    var signingTeamID: String?
    var certificateSerialNumber: String?
    var signedDeviceIdentifier: String?
    var provisioningProfileUUID: String?
    var provisioningProfileName: String?
    var provisioningProfileCreationDate: Date?
    var provisioningProfileExpirationDate: Date?
    var entitlementValidationStatus: String?
    var capabilityValidationStatus: String?
    var lastSignedAt: Date?
    var lastInstalledAt: Date?
    var removedExtensionBundleIdentifiers: [String]
    var signingTargets: [SigningTargetRecord]
    let ipaRelativePath: String
    var signedIPARelativePath: String?
    var signedIPASHA256: String?
    var signedArtifactStatus: SignedArtifactStatus?
    var preferredBundleIdentifier: String?
    var preferredDisplayName: String?
    var preferredIconRelativePath: String?
    var lastInstallFailureCode: String?
    var lastInstallFailureReason: String?
    var pendingFileTransactionID: UUID?
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
        signingTeamID: String? = nil,
        certificateSerialNumber: String? = nil,
        signedDeviceIdentifier: String? = nil,
        provisioningProfileUUID: String? = nil,
        provisioningProfileName: String? = nil,
        provisioningProfileCreationDate: Date? = nil,
        provisioningProfileExpirationDate: Date? = nil,
        entitlementValidationStatus: String? = nil,
        capabilityValidationStatus: String? = nil,
        lastSignedAt: Date? = nil,
        lastInstalledAt: Date? = nil,
        removedExtensionBundleIdentifiers: [String] = [],
        signingTargets: [SigningTargetRecord] = [],
        ipaRelativePath: String,
        signedIPARelativePath: String? = nil,
        signedIPASHA256: String? = nil,
        signedArtifactStatus: SignedArtifactStatus? = nil,
        preferredBundleIdentifier: String? = nil,
        preferredDisplayName: String? = nil,
        preferredIconRelativePath: String? = nil,
        lastInstallFailureCode: String? = nil,
        lastInstallFailureReason: String? = nil,
        pendingFileTransactionID: UUID? = nil,
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
        self.signingTeamID = signingTeamID
        self.certificateSerialNumber = certificateSerialNumber
        self.signedDeviceIdentifier = signedDeviceIdentifier
        self.provisioningProfileUUID = provisioningProfileUUID
        self.provisioningProfileName = provisioningProfileName
        self.provisioningProfileCreationDate = provisioningProfileCreationDate
        self.provisioningProfileExpirationDate = provisioningProfileExpirationDate
        self.entitlementValidationStatus = entitlementValidationStatus
        self.capabilityValidationStatus = capabilityValidationStatus
        self.lastSignedAt = lastSignedAt
        self.lastInstalledAt = lastInstalledAt
        self.removedExtensionBundleIdentifiers = removedExtensionBundleIdentifiers
        self.signingTargets = signingTargets
        self.ipaRelativePath = ipaRelativePath
        self.signedIPARelativePath = signedIPARelativePath
        self.signedIPASHA256 = signedIPASHA256
        self.signedArtifactStatus = signedArtifactStatus
        self.preferredBundleIdentifier = preferredBundleIdentifier
        self.preferredDisplayName = preferredDisplayName
        self.preferredIconRelativePath = preferredIconRelativePath
        self.lastInstallFailureCode = lastInstallFailureCode
        self.lastInstallFailureReason = lastInstallFailureReason
        self.pendingFileTransactionID = pendingFileTransactionID
        self.isSeal = isSeal
        self.isPinned = isPinned
        self.importedAt = importedAt
        self.extensions = extensions
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case originalBundleIdentifier
        case mappedBundleIdentifier
        case name
        case version
        case buildNumber
        case size
        case iconRelativePath
        case state
        case expiryDate
        case accountID
        case signingTeamID
        case certificateSerialNumber
        case signedDeviceIdentifier
        case provisioningProfileUUID
        case provisioningProfileName
        case provisioningProfileCreationDate
        case provisioningProfileExpirationDate
        case entitlementValidationStatus
        case capabilityValidationStatus
        case lastSignedAt
        case lastInstalledAt
        case removedExtensionBundleIdentifiers
        case signingTargets
        case ipaRelativePath
        case signedIPARelativePath
        case signedIPASHA256
        case signedArtifactStatus
        case preferredBundleIdentifier
        case preferredDisplayName
        case preferredIconRelativePath
        case lastInstallFailureCode
        case lastInstallFailureReason
        case pendingFileTransactionID
        case isSeal
        case isPinned
        case importedAt
        case extensions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalBundleIdentifier = try container.decode(String.self, forKey: .originalBundleIdentifier)
        mappedBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .mappedBundleIdentifier)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        buildNumber = try container.decode(String.self, forKey: .buildNumber)
        size = try container.decode(Int64.self, forKey: .size)
        iconRelativePath = try container.decodeIfPresent(String.self, forKey: .iconRelativePath)
        state = try container.decode(AppState.self, forKey: .state)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        signingTeamID = try container.decodeIfPresent(String.self, forKey: .signingTeamID)
        certificateSerialNumber = try container.decodeIfPresent(String.self, forKey: .certificateSerialNumber)
        signedDeviceIdentifier = try container.decodeIfPresent(String.self, forKey: .signedDeviceIdentifier)
        provisioningProfileUUID = try container.decodeIfPresent(String.self, forKey: .provisioningProfileUUID)
        provisioningProfileName = try container.decodeIfPresent(String.self, forKey: .provisioningProfileName)
        provisioningProfileCreationDate = try container.decodeIfPresent(Date.self, forKey: .provisioningProfileCreationDate)
        provisioningProfileExpirationDate = try container.decodeIfPresent(Date.self, forKey: .provisioningProfileExpirationDate)
        entitlementValidationStatus = try container.decodeIfPresent(String.self, forKey: .entitlementValidationStatus)
        capabilityValidationStatus = try container.decodeIfPresent(String.self, forKey: .capabilityValidationStatus)
        lastSignedAt = try container.decodeIfPresent(Date.self, forKey: .lastSignedAt)
        lastInstalledAt = try container.decodeIfPresent(Date.self, forKey: .lastInstalledAt)
        removedExtensionBundleIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .removedExtensionBundleIdentifiers
        ) ?? []
        signingTargets = try container.decodeIfPresent(
            [SigningTargetRecord].self,
            forKey: .signingTargets
        ) ?? []
        ipaRelativePath = try container.decode(String.self, forKey: .ipaRelativePath)
        signedIPARelativePath = try container.decodeIfPresent(String.self, forKey: .signedIPARelativePath)
        signedIPASHA256 = try container.decodeIfPresent(String.self, forKey: .signedIPASHA256)
        signedArtifactStatus = try container.decodeIfPresent(SignedArtifactStatus.self, forKey: .signedArtifactStatus)
        preferredBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .preferredBundleIdentifier)
        preferredDisplayName = try container.decodeIfPresent(String.self, forKey: .preferredDisplayName)
        preferredIconRelativePath = try container.decodeIfPresent(String.self, forKey: .preferredIconRelativePath)
        lastInstallFailureCode = try container.decodeIfPresent(String.self, forKey: .lastInstallFailureCode)
        lastInstallFailureReason = try container.decodeIfPresent(String.self, forKey: .lastInstallFailureReason)
        pendingFileTransactionID = try container.decodeIfPresent(UUID.self, forKey: .pendingFileTransactionID)
        isSeal = try container.decodeIfPresent(Bool.self, forKey: .isSeal) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        extensions = try container.decodeIfPresent(
            [AppExtensionRecord].self,
            forKey: .extensions
        ) ?? []
    }

    var hasPersistedSigningIdentity: Bool {
        mappedBundleIdentifier?.isEmpty == false
            && accountID != nil
            && signingTeamID?.isEmpty == false
            && certificateSerialNumber?.isEmpty == false
            && signedDeviceIdentifier?.isEmpty == false
            && provisioningProfileExpirationDate != nil
            && signedIPARelativePath?.isEmpty == false
    }

    var requiresLockedSigningIdentity: Bool {
        hasPersistedSigningIdentity
    }

    var displayName: String {
        if let trimmed = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           trimmed.isEmpty == false {
            return trimmed
        }
        return name
    }

    var displayIconRelativePath: String? {
        preferredIconRelativePath ?? iconRelativePath
    }

    var hasSignedArtifact: Bool {
        signedIPARelativePath?.isEmpty == false && signedIPASHA256?.isEmpty == false
    }

}
