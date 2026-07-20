import Foundation

struct AppExtensionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let originalBundleIdentifier: String
    var mappedBundleIdentifier: String?
    let kind: AppExtensionKind
    var provisioningProfileUUID: String?
    var provisioningProfileName: String?
    var provisioningProfileExpirationDate: Date?
    var certificateSerialNumber: String?

    init(
        id: UUID = UUID(),
        name: String,
        originalBundleIdentifier: String,
        mappedBundleIdentifier: String? = nil,
        kind: AppExtensionKind = .unknown,
        provisioningProfileUUID: String? = nil,
        provisioningProfileName: String? = nil,
        provisioningProfileExpirationDate: Date? = nil,
        certificateSerialNumber: String? = nil
    ) {
        self.id = id
        self.name = name
        self.originalBundleIdentifier = originalBundleIdentifier
        self.mappedBundleIdentifier = mappedBundleIdentifier
        self.kind = kind
        self.provisioningProfileUUID = provisioningProfileUUID
        self.provisioningProfileName = provisioningProfileName
        self.provisioningProfileExpirationDate = provisioningProfileExpirationDate
        self.certificateSerialNumber = certificateSerialNumber
    }
}
