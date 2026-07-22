import Foundation

enum AppSigningDisposition: Equatable, Sendable {
    case signAndInstall
    case signOnly
}

struct AppSigningCustomization: Equatable, Sendable {
    var displayName: String?
    var iconData: Data?

    static let none = AppSigningCustomization(displayName: nil, iconData: nil)

    var normalizedDisplayName: String? {
        guard let displayName else { return nil }
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct AppSigningOptions: Equatable, Sendable {
    var requestedBundleIdentifier: String?
    var customization: AppSigningCustomization
    var disposition: AppSigningDisposition

    static let install = AppSigningOptions(
        requestedBundleIdentifier: nil,
        customization: .none,
        disposition: .signAndInstall
    )
}
