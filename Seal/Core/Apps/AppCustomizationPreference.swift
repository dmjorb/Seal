import Foundation

struct AppCustomizationPreference: Codable, Equatable, Sendable {
    let originalBundleIdentifier: String
    var displayName: String?
    var iconData: Data?
    var lastSuccessfulBundleIdentifier: String?
    var updatedAt: Date

    init(
        originalBundleIdentifier: String,
        displayName: String? = nil,
        iconData: Data? = nil,
        lastSuccessfulBundleIdentifier: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.originalBundleIdentifier = originalBundleIdentifier
        self.displayName = displayName
        self.iconData = iconData
        self.lastSuccessfulBundleIdentifier = lastSuccessfulBundleIdentifier
        self.updatedAt = updatedAt
    }
}
