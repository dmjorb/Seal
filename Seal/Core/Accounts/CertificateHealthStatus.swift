import Foundation

struct CertificateHealthStatus: Equatable, Sendable {
    enum CheckState: String, Equatable, Sendable {
        case valid
        case invalid
        case unknown
    }

    let serialNumber: String
    let portalPresence: CheckState
    let p12Readable: CheckState
    let localPrivateKey: CheckState
    let keychainReadable: CheckState
    let appleIDMatch: CheckState
    let teamMatch: CheckState
    let expirationDate: Date?
    let lastSignedAt: Date?
    let relatedAppCount: Int

    var expirationState: CheckState {
        guard let expirationDate else { return .unknown }
        return expirationDate > Date() ? .valid : .invalid
    }

    var isUsable: Bool {
        portalPresence == .valid
            && p12Readable == .valid
            && localPrivateKey == .valid
            && keychainReadable == .valid
            && appleIDMatch == .valid
            && teamMatch == .valid
            && expirationState == .valid
    }
}
