import Foundation

struct SigningTargetRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let profileUUID: String?
    let profileName: String?
    let profileCreationDate: Date?
    let profileExpirationDate: Date
    let teamIdentifier: String
    let certificateSerialNumbers: [String]
    let deviceIdentifiers: [String]
    let entitlementKeys: [String]

    init(binding: ProvisioningProfileBinding) {
        bundleIdentifier = binding.bundleIdentifier
        profileUUID = binding.profileUUID
        profileName = binding.profileName
        profileCreationDate = binding.creationDate
        profileExpirationDate = binding.expirationDate
        teamIdentifier = binding.teamIdentifier
        certificateSerialNumbers = binding.certificateSerialNumbers
        deviceIdentifiers = binding.deviceIdentifiers
        entitlementKeys = binding.entitlementKeys
    }

    init(
        bundleIdentifier: String,
        profileUUID: String?,
        profileName: String?,
        profileCreationDate: Date?,
        profileExpirationDate: Date,
        teamIdentifier: String,
        certificateSerialNumbers: [String],
        deviceIdentifiers: [String],
        entitlementKeys: [String]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.profileUUID = profileUUID
        self.profileName = profileName
        self.profileCreationDate = profileCreationDate
        self.profileExpirationDate = profileExpirationDate
        self.teamIdentifier = teamIdentifier
        self.certificateSerialNumbers = certificateSerialNumbers
        self.deviceIdentifiers = deviceIdentifiers
        self.entitlementKeys = entitlementKeys
    }
}
