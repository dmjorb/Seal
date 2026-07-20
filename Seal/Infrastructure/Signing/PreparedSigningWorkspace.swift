import Foundation

struct PreparedSigningWorkspace: Sendable {
    let rootURL: URL
    let payloadURL: URL
    let appURL: URL
    let mappedMainBundleID: String
    let bundleIDMappings: [String: String]

    var targetMainBundleIdentifier: String { mappedMainBundleID }
}
