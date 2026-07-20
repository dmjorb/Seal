import Foundation

struct AppExtensionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let originalBundleIdentifier: String
    var mappedBundleIdentifier: String?
    let kind: AppExtensionKind

    init(
        id: UUID = UUID(),
        name: String,
        originalBundleIdentifier: String,
        mappedBundleIdentifier: String? = nil,
        kind: AppExtensionKind = .unknown
    ) {
        self.id = id
        self.name = name
        self.originalBundleIdentifier = originalBundleIdentifier
        self.mappedBundleIdentifier = mappedBundleIdentifier
        self.kind = kind
    }
}
