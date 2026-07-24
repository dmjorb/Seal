enum AccountStatus: String, Codable, Equatable, Sendable {
    case verified
    case availableOffline
    case needsVerification

    var isSelectable: Bool {
        self != .needsVerification
    }
}

enum AccountVerificationFailureReason: String, Codable, Equatable, Sendable {
    case credentialsRejected
    case localCredentialsMissing
    case localCredentialsMismatch
}
