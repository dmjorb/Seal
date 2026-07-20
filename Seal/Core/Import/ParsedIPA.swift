import Foundation

struct ParsedIPA: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String
    let version: String
    let buildNumber: String
    let fileSize: Int64
    let iconData: Data?
    let extensions: [AppExtensionRecord]
    let entitlementKeys: Set<String>
}
