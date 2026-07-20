import Foundation

struct PortalSigningResult: Sendable {
    let mappedMainBundleID: String
    let mappedBundleIdentifiers: [String: String]
    let expirationDate: Date
    let signedIPAURL: URL
    let updatedSecret: AccountSecret
    let certificateSerialNumber: String
    let droppedExtensionBundleIdentifiers: [String]
}
