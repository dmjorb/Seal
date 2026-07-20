import Foundation

struct AccountSecret: Codable, Equatable, Sendable {
    let email: String
    let accountIdentifier: String
    let dsid: String
    let authToken: String
    var certificateP12: Data?
    var certificateSerialNumber: String?
    var certificateMachineIdentifier: String?
}
